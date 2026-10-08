import SceneKit
import UIKit
import Metal
import CoreImage
import simd

// MARK: - The Neurons look
//
// How the Neurons theme (GraphNeurons) is dressed, for the shared theme
// scene (GraphThemeScene), after the close-up the owner circled on their
// board: every cell a glass soma (NeuronShaders.soma, its membrane
// wobbling) round a deep-violet nucleus with a bright heart, golden light
// hugging it, its edge white-blue; a crown of glass dendrites with golden
// light inside growing out of it (swaying), a faint glow round it, and a
// glow its dendrites give off when an impulse arrives - on dark teal-navy
// fluid with far, blurred blue neurons and gold and blue bokeh behind,
// instead of stars.
//
// What a cell holds is drawn inside it, and only once it is opened: a part
// (a folder in the cell's folder) a smaller gel sphere floating in its
// cytoplasm, a page a vesicle, an idea a granule. An opened container
// clears its middle so what floats there shows: its nucleus settles small
// at the centre, its speckle and its interior's haze thin (rpOpen, eased
// over most of a second as it opens or closes).
//
// Links are the cells' axons: each grows out of its sender from under the
// membrane, swells into a hillock and tapers, and ends in one synapse on
// its target (GraphLinkArbor); its width follows the sender's size and the
// link's strength (GraphRibbonWriter.widthStep).
//
// Colours are the close-up's violet and gold on dark teal-navy
// (NeuronPalette): each cell keeps a touch of its own dye (green, cyan,
// pink, amber, violet) in its nucleus and at its edge, its parts and ideas
// leaning to the dye's accent; receptors gold, drifting cells pale ice;
// axons glass with golden-white light inside, impulses amber in a warm
// orange halo.
//
// Each cell shows a state (NeuronState, chosen in the Look menu or by its
// role): resting, firing, releasing, pacemaker, migrating, engulfing - the
// space styles' six, each a process of its own in the soma and halo
// shaders, and in its shape and motion here: a free pacemaker's bipolar
// arbor turning, a migrating cell's leading process, an engulfing cell's
// fine processes closing and opening.
//
// Nothing is made per cell but its nodes and a container's own soma
// material (each opens on its own): other materials are one per (dye, kind
// of cell, state), geometry one sphere and a few arbor shapes per kind,
// shared; every cell is turned at random so no two look alike.
//
// The Graphics budget (GraphQuality.current) sets the cost: at Smooth the
// sphere has fewer segments, the arbors fewer sides, samples and side
// branches, the shaders their simple path (rpDetail 0: no sparkles, no
// strands, no bursts) and fewer impulses fire. Reduce Motion or a still
// space: no wobble, no sway, no impulses, no easing - the picture whole
// but still.

/// What kind of cell a body is drawn as (its material and arbor).
nonisolated enum NeuronCellKind: Int, CaseIterable, Sendable {
    /// A whole cell (a top-level folder, or the home cell): a soma round a
    /// nucleus, crowned with dendrites.
    case cell
    /// A part of a cell (a folder inside it): a clear sphere inside, with
    /// no processes of its own.
    case part
    /// A page, inside its folder.
    case vesicle
    /// An idea, inside its folder.
    case granule
    /// A free note with links: one long leading process ending in a fan.
    case receptor
    /// A free note with no links: a small cell of many fine processes.
    case drifter
    /// A free pacemaker: two long dendrites, opposite.
    case bipolar

    static func of(_ role: NeuronRole) -> NeuronCellKind {
        switch role {
        case .cell, .home: return .cell
        case .part: return .part
        case .vesicle: return .vesicle
        case .granule: return .granule
        case .receptor: return .receptor
        case .drifter: return .drifter
        }
    }

    /// The nucleus's radius, as a share of the body's (0: none - a part
    /// and a vesicle are clear).
    var nucleus: Float {
        switch self {
        case .cell, .drifter: return 0.3
        case .part, .vesicle: return 0
        case .granule: return 0.5
        case .receptor, .bipolar: return 0.4
        }
    }

    /// How far the membrane wobbles, as a share of the radius.
    var wobble: Float {
        switch self {
        case .cell: return 0.025
        case .part: return 0.035
        case .vesicle, .receptor, .bipolar: return 0.04
        case .granule: return 0.02
        case .drifter: return 0.06
        }
    }

    /// How much of the purple and magenta interior shows: a part's and a
    /// vesicle's thin, so what floats in them, and behind, shows through.
    var fill: Float {
        switch self {
        case .cell, .receptor, .drifter, .bipolar: return 1
        case .part: return 0.45
        case .vesicle: return 0.2
        case .granule: return 0.8
        }
    }

    /// Whether it grows processes of its own (what floats inside a cell
    /// has none).
    var branches: Bool { self == .cell || self == .receptor || self == .drifter || self == .bipolar }

    /// Whether things float inside it once it is opened.
    var holds: Bool { self == .cell || self == .part }
}

@MainActor
final class GraphNeuronLook: GraphThemeLook {
    let theme: GraphTheme = .neurons
    let lively: Bool
    let bold: Bool
    let budget: GraphicsBudget
    let support: NeuronSupport
    /// Each cell's state: chosen in the Look menu, or its role's own.
    let cells: NeuronStateChoice
    let linkMaterial: SCNMaterial
    let farMaterial: SCNMaterial
    /// The axons' half widths before the sender's width step
    /// (GraphRibbonWriter.stepWidth): statics, so init can pass them on.
    static let nearHalf: Float = 0.165
    static let farHalf: Float = 0.26
    var linkHalfWidth: Float { Self.nearHalf }
    var farHalfWidth: Float { Self.farHalf }
    /// An axon starts at 0.9 of its sender's trim radius (0.72 of the
    /// cell's size), under the membrane, so it grows out of the cell.
    let linkTrim: Float = 0.9

    /// Every axon ends in one synapse on its target, a gel golf-tee cup
    /// (GraphLinkArbor, drawn by NeuronShaders.axon): the target's membrane
    /// is 1.25 of its trim radius; the fibre is 0.3 of the axon's half
    /// width there. Only when the axon shader works: the plain fallback
    /// draws no cup.
    var arbor: GraphLinkArbor? {
        support.has("axon") ? GraphLinkArbor(membrane: 1.25, share: 0.3) : nil
    }

    var farArbor: GraphLinkArbor? { arbor }
    let hotRing: SCNGeometry
    private(set) var clocked: [SCNMaterial] = []
    /// Materials whose geometry modifiers read `rpSway` (NeuronImpulses
    /// sets it each frame).
    private(set) var swaying: [SCNMaterial] = []
    /// The containers opening or closing in this build (NeuronImpulses
    /// eases their rpOpen).
    private(set) var openings: [NeuronOpening] = []
    private var somaLooks: [String: SCNMaterial] = [:]
    private var somaShapes: [String: SCNGeometry] = [:]
    private var arborLooks: [String: SCNGeometry] = [:]
    private var haloLooks: [String: SCNGeometry] = [:]
    private let sphere: SCNGeometry
    private let arrivalPlane: SCNGeometry
    /// Each region's dye slot, by body index.
    private var slotOf: [Int: Int] = [:]
    /// The bodies something floats in (some body's parent), by index.
    private var holding: Set<Int> = []
    private var slotsFor: Int = -1
    /// The containers that were open in the last build, so a rebuild knows
    /// which are opening and which closing.
    private static var wasOpen: Set<UUID> = []

    init(lively: Bool, bold: Bool, cells: NeuronStateChoice = .natural) {
        self.lively = lively
        self.bold = bold
        self.cells = cells
        let budget: GraphicsBudget = GraphQuality.current
        self.budget = budget
        let support: NeuronSupport = NeuronProbe.support
        self.support = support
        linkMaterial = Self.axonMaterial(base: Self.fibre, bold: bold, lively: lively, budget: budget,
                                         support: support, half: Self.nearHalf)
        farMaterial = Self.axonMaterial(base: Self.tract, bold: bold, lively: lively, budget: budget,
                                        support: support, half: Self.farHalf)
        let ball = SCNSphere(radius: 1)
        ball.segmentCount = budget.tier == .high ? 40 : 24
        sphere = ball
        hotRing = GraphSceneBuilder.plane(Self.haloMaterial(tint: SIMD3<Float>(0.75, 1.0, 1.0), hot: true,
                                                            support: support))
        arrivalPlane = GraphSceneBuilder.plane(Self.arrivalMaterial(support: support))
        if support.has("axon") {
            clocked.append(linkMaterial)
            clocked.append(farMaterial)
        }
    }

    // MARK: colours

    /// The soma's golden sparkles, the light inside the axons and tracts
    /// (golden-white, as in the owner's close-up), and the impulses
    /// (NeuronPalette: amber in a warm orange halo).
    static let sparkle = SIMD3<Float>(1.0, 0.88, 0.6)
    static let fibre = SIMD3<Float>(1.0, 0.8, 0.45)
    static let tract = SIMD3<Float>(1.0, 0.72, 0.38)
    static let impulse: SIMD3<Float> = NeuronPalette.impulse
    static let impulseHalo: SIMD3<Float> = NeuronPalette.impulseHalo

    /// What the plan says once per build: each region's dye slot, and
    /// which bodies hold others.
    private func learn(_ plan: ThemePlan) {
        guard slotsFor != plan.bodies.count else { return }
        slotOf = [:]
        for (k, r) in plan.regions.enumerated() { slotOf[r] = k % NeuronPalette.dyes.count }
        holding = []
        for body in plan.bodies where body.parent >= 0 { holding.insert(body.parent) }
        slotsFor = plan.bodies.count
    }

    /// A body's dye slot: its region's place in the plan (5 dyes round), 5
    /// for a receptor, 6 for a drifting cell.
    private func slot(_ body: ThemeBody, plan: ThemePlan) -> Int {
        learn(plan)
        if body.region >= 0 { return slotOf[body.region] ?? 0 }
        return body.role == NeuronRole.drifter.rawValue ? 6 : 5
    }

    /// A cell's membrane colour: its slot's dye, an idea's (and a part's)
    /// leaning to the region's accent.
    private static func membrane(slot: Int, idea: Bool) -> SIMD3<Float> {
        NeuronPalette.dye(slot: slot, idea: idea)
    }

    func tone(region: Int, plan: ThemePlan) -> UIColor? {
        guard region >= 0, region < plan.bodies.count else { return nil }
        let c: SIMD3<Float> = NeuronPalette.dye(slot: slot(plan.bodies[region], plan: plan))
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    // MARK: a cell

    /// The shape a state gives a free note: a pacemaker bipolar (two long
    /// dendrites), a migrating one a leading process (the receptor's), an
    /// engulfing one many fine processes (the drifter's). A cell and what
    /// floats inside one keep their own.
    static func shape(_ kind: NeuronCellKind, state: NeuronState) -> NeuronCellKind {
        guard kind == .receptor || kind == .drifter || kind == .bipolar else { return kind }
        switch state {
        case .pacemaker: return .bipolar
        case .migrating: return .receptor
        case .engulfing: return .drifter
        case .resting, .firing, .releasing: return kind
        }
    }

    func makeBody(_ body: ThemeBody, index: Int, plan: ThemePlan) -> GraphThemeParts {
        learn(plan)
        let node = SCNNode()
        switch body.kind {
        case .note: node.name = "note:" + body.id.uuidString
        case .folder: node.name = "folder:" + body.id.uuidString
        case .home: node.name = "home"
        }
        let role: NeuronRole = NeuronRole(rawValue: body.role) ?? .granule
        let state: NeuronState = cells.state(of: index, in: plan)
        let kind: NeuronCellKind = Self.shape(NeuronCellKind.of(role), state: state)
        // a part and an idea lean to the region's accent
        let idea: Bool = kind == .part || kind == .granule
        let inner: Bool = body.parent >= 0
        let open: Bool = kind.holds && holding.contains(index)
        let dyeSlot: Int = slot(body, plan: plan)
        var random = UniverseRandom(body.seed ^ 0xCE11)
        let size: Float = body.sphere

        let geometry: SCNGeometry = kind.holds
            ? ownSoma(id: body.id, slot: dyeSlot, kind: kind, state: state, idea: idea, open: open)
            : somaGeometry(slot: dyeSlot, kind: kind, state: state, idea: idea)
        let soma = SCNNode(geometry: geometry)
        soma.simdScale = SIMD3<Float>(size, size, size)
        soma.simdOrientation = Self.randomTurn(&random)
        soma.renderingOrder = 6
        node.addChildNode(soma)

        var arbor: SCNNode?
        if kind.branches {
            let variant: Int = Int(body.seed % 3)
            let made = SCNNode(geometry: arborGeometry(kind: kind, variant: variant, slot: dyeSlot, idea: idea))
            made.simdScale = SIMD3<Float>(size, size, size)
            made.simdOrientation = Self.arborTurn(kind, axis: body.axis, random: &random)
            made.renderingOrder = 6
            made.categoryBitMask = 2
            node.addChildNode(made)
            arbor = made
        }

        // the halo, on GraphSim's ring pieces
        let holder = SCNNode()
        let facing = SCNBillboardConstraint()
        facing.freeAxes = .all
        holder.constraints = [facing]
        let stretch = SCNNode()
        // Smooth (no haze), or inside a cell: no standing halo for a resting
        // body - one blended quad five times its size less for each - but a
        // body in a state keeps its own, as its process is drawn there
        let standing: Bool = (budget.haze && !inner) || state != .resting
        let halo: SCNGeometry = standing ? haloGeometry(slot: dyeSlot, state: state, idea: idea) : GraphThemeParts.noHalo
        let leaf = SCNNode(geometry: halo)
        let across: Float = size * 5
        leaf.simdScale = SIMD3<Float>(across, across, 1)
        leaf.renderingOrder = 7
        leaf.categoryBitMask = 2
        stretch.addChildNode(leaf)
        holder.addChildNode(stretch)
        node.addChildNode(holder)
        let disk = SCNNode()
        node.addChildNode(disk)

        // the glow of arriving impulses, hidden until one lands, facing the
        // camera in the halo's holder (one billboard a cell, not two)
        let glow = SCNNode(geometry: arrivalPlane)
        let wide: Float = size * 7
        glow.simdScale = SIMD3<Float>(wide, wide, 1)
        glow.renderingOrder = 8
        glow.categoryBitMask = 2
        glow.opacity = 0
        glow.isHidden = true
        holder.addChildNode(glow)

        if lively {
            Self.move(state, inner: inner, soma: soma, arbor: arbor, size: size, random: &random)
        }

        var parts = GraphThemeParts(node: node, radius: size * 0.8, ringStretch: stretch, ringLeaf: leaf,
                                    ringGeometry: halo, diskLeaf: disk)
        parts.glow = glow
        // the many small resting notes' halos go first in a crowded map
        parts.thinnable = body.kind == .note && state == .resting
        return parts
    }

    /// A container's own soma (each opens and closes on its own): a copy of
    /// the sphere with its own material, its rpOpen eased from how it was
    /// in the last build to how it is now (NeuronImpulses), or set at once
    /// when nothing moves.
    private func ownSoma(id: UUID, slot: Int, kind: NeuronCellKind, state: NeuronState, idea: Bool,
                         open: Bool) -> SCNGeometry {
        let copy: SCNGeometry = sphere.copy() as? SCNGeometry ?? sphere
        let material: SCNMaterial = makeSoma(slot: slot, kind: kind, state: state, idea: idea)
        copy.materials = [material]
        let was: Bool = Self.wasOpen.contains(id)
        if Self.wasOpen.count > 4096 { Self.wasOpen.removeAll() }
        if open { Self.wasOpen.insert(id) } else { Self.wasOpen.remove(id) }
        guard support.has("soma") else { return copy }
        if lively && was != open {
            Self.set(material, "rpOpen", was ? 1 : 0)
            openings.append(NeuronOpening(material: material, from: was ? 1 : 0, to: open ? 1 : 0))
        } else {
            Self.set(material, "rpOpen", open ? 1 : 0)
        }
        return copy
    }

    /// Each state's own movement, on SceneKit's actions (none for a resting
    /// cell: its membrane breathes in the shader):
    /// - firing: the soma twitches at each spike of a burst, then rests;
    /// - releasing: the soma swells slowly and gives, as it lets go;
    /// - pacemaker: the bipolar arbor turns steadily, the soma kicks each
    ///   beat (twice a turn of NeuronState.beatPeriod, as the halo's);
    /// - migrating: the nucleus steps forward along the leading process and
    ///   the process draws after it (nucleokinesis) - inside a cell, where
    ///   nothing wanders off, a gentle pulse instead;
    /// - engulfing: the arbor closes and opens again, turning slowly (with
    ///   no arbor, the soma).
    private static func move(_ state: NeuronState, inner: Bool, soma: SCNNode, arbor: SCNNode?, size: Float,
                             random: inout UniverseRandom) {
        let lag: Double = random.unit() * 2
        let up: SIMD3<Float> = (arbor?.simdOrientation ?? soma.simdOrientation).act(SIMD3<Float>(0, 1, 0))
        let axis = SCNVector3(x: up.x, y: up.y, z: up.z)
        let s = CGFloat(size)
        let period = Double(NeuronState.beatPeriod)
        var somaLoop: SCNAction?
        var arborLoop: SCNAction?
        switch state {
        case .resting:
            break
        case .firing:
            let spike: SCNAction = pulse(to: s * 1.07, from: s, rise: 0.05, fall: 0.16)
            somaLoop = SCNAction.sequence([spike, spike, spike, SCNAction.wait(duration: 1.2, withRange: 0.8)])
        case .releasing:
            somaLoop = pulse(to: s * 1.06, from: s, rise: 1.6, fall: 2.2)
            if arbor != nil { arborLoop = pulse(to: s * 1.03, from: s, rise: 1.6, fall: 2.2) }
        case .pacemaker:
            let kick: SCNAction = pulse(to: s * 1.05, from: s, rise: 0.06, fall: 0.3)
            somaLoop = SCNAction.sequence([kick, SCNAction.wait(duration: max(period / 2 - 0.36, 0.05))])
            if arbor != nil { arborLoop = SCNAction.rotate(by: CGFloat.pi * 2, around: axis, duration: period * 4) }
        case .migrating:
            if inner {
                somaLoop = pulse(to: s * 1.04, from: s, rise: 1.4, fall: 2.2)
                break
            }
            let step: SIMD3<Float> = up * (size * 0.35)
            let ahead = SCNAction.move(by: SCNVector3(x: step.x, y: step.y, z: step.z), duration: 1.4)
            ahead.timingMode = .easeInEaseOut
            let draw = SCNAction.move(by: SCNVector3(x: -step.x, y: -step.y, z: -step.z), duration: 2.2)
            draw.timingMode = .easeInEaseOut
            somaLoop = SCNAction.sequence([ahead, SCNAction.wait(duration: 0.4), draw])
            let half: SIMD3<Float> = step * 0.5
            let reach = SCNAction.move(by: SCNVector3(x: half.x, y: half.y, z: half.z), duration: 1.8)
            reach.timingMode = .easeInEaseOut
            let after = SCNAction.move(by: SCNVector3(x: -half.x, y: -half.y, z: -half.z), duration: 2.2)
            after.timingMode = .easeInEaseOut
            arborLoop = SCNAction.sequence([reach, after])
        case .engulfing:
            guard arbor != nil else {
                let close = SCNAction.scale(to: s * 0.9, duration: 1.8)
                close.timingMode = .easeInEaseOut
                let open = SCNAction.scale(to: s * 1.04, duration: 2.4)
                open.timingMode = .easeInEaseOut
                somaLoop = SCNAction.sequence([close, open])
                break
            }
            let close = SCNAction.scale(to: s * 0.86, duration: 1.8)
            close.timingMode = .easeInEaseOut
            let open = SCNAction.scale(to: s * 1.04, duration: 2.4)
            open.timingMode = .easeInEaseOut
            let turn = SCNAction.rotate(by: CGFloat.pi / 3, around: axis, duration: 4.2)
            arborLoop = SCNAction.group([SCNAction.sequence([close, open]), turn])
        }
        if let somaLoop {
            soma.runAction(SCNAction.sequence([SCNAction.wait(duration: lag), SCNAction.repeatForever(somaLoop)]))
        }
        if let arborLoop, let arbor {
            arbor.runAction(SCNAction.sequence([SCNAction.wait(duration: lag), SCNAction.repeatForever(arborLoop)]))
        }
    }

    /// Swell to `to` and settle back to `from`.
    private static func pulse(to: CGFloat, from: CGFloat, rise: Double, fall: Double) -> SCNAction {
        let grow = SCNAction.scale(to: to, duration: rise)
        grow.timingMode = .easeOut
        let back = SCNAction.scale(to: from, duration: fall)
        back.timingMode = .easeInEaseOut
        return SCNAction.sequence([grow, back])
    }

    /// A turn to anywhere, from the cell's own numbers.
    private static func randomTurn(_ random: inout UniverseRandom) -> simd_quatf {
        let y: Float = Float(random.signed())
        let angle: Float = Float(random.unit()) * 2 * Float.pi
        let ring: Float = max(1 - y * y, 0).squareRoot()
        let axis = SIMD3<Float>(cos(angle) * ring, y, sin(angle) * ring)
        let spin: Float = Float(random.unit()) * 2 * Float.pi
        return simd_quatf(angle: spin, axis: simd_normalize(axis))
    }

    /// A receptor's leading process and a bipolar cell's long dendrites
    /// point along the body's axis (the arbor's +y), twisted at random
    /// about it; every other arbor turned anyhow.
    private static func arborTurn(_ kind: NeuronCellKind, axis: SIMD3<Float>,
                                  random: inout UniverseRandom) -> simd_quatf {
        if kind == .cell {
            // a cell's crown stays in the plane facing the camera (the
            // sheet's), turned about the view and tipped a little
            let spin: Float = Float(random.unit()) * 2 * Float.pi
            let tip: Float = 0.2 * Float(random.signed())
            let turn = simd_quatf(angle: spin, axis: SIMD3<Float>(0, 0, 1))
            return simd_quatf(angle: tip, axis: SIMD3<Float>(1, 0, 0)) * turn
        }
        guard kind == .receptor || kind == .bipolar else { return randomTurn(&random) }
        let up = SIMD3<Float>(0, 1, 0)
        let size: Float = simd_length(axis)
        let to: SIMD3<Float> = size > 0.0001 ? axis / size : up
        let twist: Float = Float(random.unit()) * 2 * Float.pi
        let along = simd_quatf(from: up, to: to)
        return simd_quatf(angle: twist, axis: to) * along
    }

    // MARK: materials

    /// The shared sphere, dressed once per dye, kind of cell, state and
    /// whether it is an idea's.
    private func somaGeometry(slot: Int, kind: NeuronCellKind, state: NeuronState, idea: Bool) -> SCNGeometry {
        let key: String = "s\(slot)-\(kind.rawValue)-\(state.code)-\(idea ? 1 : 0)"
        if let made = somaShapes[key] { return made }
        let copy: SCNGeometry = sphere.copy() as? SCNGeometry ?? sphere
        copy.materials = [makeSoma(slot: slot, kind: kind, state: state, idea: idea)]
        somaShapes[key] = copy
        return copy
    }

    private func makeSoma(slot: Int, kind: NeuronCellKind, state: NeuronState, idea: Bool) -> SCNMaterial {
        let membrane: SIMD3<Float> = Self.membrane(slot: slot, idea: idea)
        let material: SCNMaterial = Self.additive()
        guard support.has("soma") else {
            material.diffuse.contents = Self.colour(membrane * (0.25 + 0.2 * kind.fill))
            return material
        }
        material.shaderModifiers = [.geometry: NeuronShaders.wobble, .surface: NeuronShaders.soma]
        GraphStyleUniforms.defaults(material)
        Self.set(material, "rpMotion", lively ? 1 : 0)
        Self.set(material, "rpDetail", budget.shaderDetail)
        Self.set(material, "rpNucleus", kind.nucleus)
        Self.set(material, "rpState", Float(state.code))
        Self.set(material, "rpOpen", 0)
        Self.set(material, "rpFill", kind.fill)
        Self.set(material, "rpSway", 0)
        Self.set(material, "rpWobble", lively ? kind.wobble : 0)
        Self.tint(material, "rpTintA", membrane)
        Self.tint(material, "rpTintB", NeuronPalette.nucleus)
        Self.tint(material, "rpTintC", Self.sparkle)
        clocked.append(material)
        swaying.append(material)
        return material
    }

    private func arborGeometry(kind: NeuronCellKind, variant: Int, slot: Int, idea: Bool) -> SCNGeometry {
        let key: String = "a\(kind.rawValue)-\(variant)-\(slot)-\(idea ? 1 : 0)"
        if let made = arborLooks[key] { return made }
        let shapeKey: String = "shape\(kind.rawValue)-\(variant)"
        let shape: SCNGeometry
        if let made = arborLooks[shapeKey] {
            shape = made
        } else {
            let high: Bool = budget.tier == .high
            let branches: [NeuronBranch] = NeuronArbor.branches(kind, variant: variant, rich: high)
            // a cell's thick glass tubes need more sides to stay round
            let round: Int = kind == .cell ? (high ? 10 : 7) : (high ? 6 : 4)
            shape = NeuronArbor.mesh(branches, sides: round, segments: high ? 14 : 9)
            arborLooks[shapeKey] = shape
        }
        let geometry: SCNGeometry = shape.copy() as? SCNGeometry ?? shape
        geometry.materials = [makeArbor(slot: slot, idea: idea)]
        arborLooks[key] = geometry
        return geometry
    }

    /// The dendrites: glass with golden light inside near the soma, a
    /// touch of the membrane's dye in it (as in the owner's close-up); on
    /// the clock, so the gold streaks and particles drift out along them.
    private func makeArbor(slot: Int, idea: Bool) -> SCNMaterial {
        let key: String = "m\(slot)-\(idea ? 1 : 0)"
        if let made = somaLooks[key] { return made }
        let membrane: SIMD3<Float> = Self.membrane(slot: slot, idea: idea)
        let golden: SIMD3<Float> = SIMD3<Float>(1.0, 0.74, 0.36) * 0.88 + membrane * 0.12
        let material: SCNMaterial = Self.additive()
        if support.has("arbor") {
            material.shaderModifiers = [.geometry: NeuronShaders.sway, .surface: NeuronShaders.arbor]
            GraphStyleUniforms.defaults(material)
            Self.set(material, "rpDetail", budget.shaderDetail)
            Self.set(material, "rpMotion", lively ? 1 : 0)
            Self.set(material, "rpSway", 0)
            Self.set(material, "rpWobble", lively ? 0.03 : 0)
            Self.tint(material, "rpTintA", golden * 0.95)
            swaying.append(material)
            clocked.append(material)
        } else {
            material.diffuse.contents = Self.colour(golden * 0.4)
        }
        somaLooks[key] = material
        return material
    }

    private func haloGeometry(slot: Int, state: NeuronState, idea: Bool) -> SCNGeometry {
        let key: String = "h\(slot)-\(state.code)-\(idea ? 1 : 0)"
        if let made = haloLooks[key] { return made }
        // gold-leaning, as the light round the owner's close-up is
        let tint: SIMD3<Float> = SIMD3<Float>(1.0, 0.74, 0.36) * 0.7 + NeuronPalette.glow(slot: slot, idea: idea) * 0.3
        let material: SCNMaterial = Self.haloMaterial(tint: tint, hot: false, support: support, state: state,
                                                      lively: lively)
        if support.has("halo") && state != .resting { clocked.append(material) }
        let plane: SCNGeometry = GraphSceneBuilder.plane(material)
        haloLooks[key] = plane
        return plane
    }

    private static func haloMaterial(tint: SIMD3<Float>, hot: Bool, support: NeuronSupport,
                                     state: NeuronState = .resting, lively: Bool = false) -> SCNMaterial {
        let material: SCNMaterial = additive()
        material.isDoubleSided = true
        guard support.has("halo") else {
            material.diffuse.contents = NeuronArt.softDisc
            let gain: Float = hot ? 0.9 : (state == .resting ? 0.4 : 0.6)
            material.multiply.contents = colour(tint * gain)
            return material
        }
        material.shaderModifiers = [.surface: NeuronShaders.halo]
        GraphStyleUniforms.defaults(material)
        set(material, "rpGain", hot ? 1.8 : 1)
        set(material, "rpState", Float(state.code))
        set(material, "rpMotion", lively ? 1 : 0)
        Self.tint(material, "rpTintA", tint)
        let ring: SIMD3<Float> = hot ? SIMD3<Float>(0.75, 0.95, 1.0) : SIMD3<Float>(0, 0, 0)
        Self.tint(material, "rpTintC", ring)
        return material
    }

    /// An arriving impulse's glow: its amber, a quarter of the way to its
    /// orange halo.
    private static let arrivalGlow: SIMD3<Float> = impulse + (impulseHalo - impulse) * 0.25

    private static func arrivalMaterial(support: NeuronSupport) -> SCNMaterial {
        let material: SCNMaterial = additive()
        material.isDoubleSided = true
        guard support.has("arrival") else {
            material.diffuse.contents = NeuronArt.softDisc
            material.multiply.contents = colour(arrivalGlow * 0.8)
            return material
        }
        material.shaderModifiers = [.surface: NeuronShaders.arrival]
        GraphStyleUniforms.defaults(material)
        tint(material, "rpTintA", arrivalGlow)
        tint(material, "rpTintB", impulse)
        return material
    }

    /// An axon, a single fibre in `base`: the impulses' rate and bursts
    /// from the Graphics budget.
    private static func axonMaterial(base: SIMD3<Float>, bold: Bool, lively: Bool, budget: GraphicsBudget,
                                     support: NeuronSupport, half: Float) -> SCNMaterial {
        let strength: Float = bold ? 1.35 : 1
        guard support.has("axon") else {
            let plain: SCNMaterial = GraphLook.link(bold: bold, shader: false, lively: lively)
            plain.multiply.contents = colour(base)
            return plain
        }
        let material: SCNMaterial = additive()
        material.isDoubleSided = true
        material.shaderModifiers = [.surface: NeuronShaders.axon]
        GraphStyleUniforms.defaults(material)
        set(material, "rpMotion", lively ? 1 : 0)
        let high: Bool = budget.tier == .high
        // held still (Reduce Motion, a still space): no impulses at all,
        // rather than impulses frozen partway along the axons
        set(material, "rpRate", lively ? (high ? 0.55 : 0.3) : 0)
        set(material, "rpBurst", lively && high ? 0.18 : 0)
        set(material, "rpBundle", 0)
        set(material, "rpHalf", half)
        set(material, "rpDetail", budget.shaderDetail)
        tint(material, "rpTintA", base * strength)
        tint(material, "rpTintB", impulse)
        tint(material, "rpTintC", impulseHalo)
        return material
    }

    /// Unlit, added to what is behind, tested against depth but never
    /// writing it: gel lets light through.
    private static func additive() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        // a texture, not a colour, so the shaders get texture coordinates
        // (the plain fallbacks put their own contents over it)
        material.diffuse.contents = GraphStyleProbe.blackContents
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        return material
    }

    private static func set(_ material: SCNMaterial, _ key: String, _ value: Float) {
        material.setValue(NSNumber(value: value), forKey: key)
    }

    private static func tint(_ material: SCNMaterial, _ key: String, _ c: SIMD3<Float>) {
        material.setValue(NSValue(scnVector3: SCNVector3(x: c.x, y: c.y, z: c.z)), forKey: key)
    }

    private static func colour(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(min(c.x, 1)), green: CGFloat(min(c.y, 1)), blue: CGFloat(min(c.z, 1)), alpha: 1)
    }

    // MARK: each frame

    func ticker(parts: [GraphThemeParts], plan: ThemePlan) -> GraphThemeTicker? {
        guard lively else { return nil }
        let high: Bool = budget.tier == .high
        let fires: Bool = support.has("axon")
        return NeuronImpulses(glows: parts.map(\.glow), swaying: swaying, openings: openings,
                              rate: fires ? (high ? 0.55 : 0.3) : 0, bursts: high ? 0.18 : 0)
    }

    // MARK: the tissue

    func makeSky() -> SCNNode {
        NeuronTissue.makeSky()
    }
}

// MARK: - Impulses on the render thread

/// Lights each cell's dendrites as impulses reach it - the same arrivals
/// the axon shader flashes (NeuronImpulse) - moves the membranes' and
/// dendrites' clock, and eases each opening or closing container's rpOpen
/// over 0.9 s from the first frame it sees. GraphSim calls it once a frame, under its
/// SCNTransaction, after the links are written. Render thread only.
nonisolated final class NeuronImpulses: GraphThemeTicker {
    private let glows: [SCNNode?]
    private let swaying: [SCNMaterial]
    private let openings: [NeuronOpening]
    private var openedAt: Float = -1
    private var settled: Bool
    private let rate: Float
    private let bursts: Float
    private var level: [Float]
    private var shown: [Float]
    private var last: Float = -1

    init(glows: [SCNNode?], swaying: [SCNMaterial], openings: [NeuronOpening] = [], rate: Float, bursts: Float) {
        self.glows = glows
        self.swaying = swaying
        self.openings = openings
        settled = openings.isEmpty
        self.rate = rate
        self.bursts = bursts
        level = [Float](repeating: 0, count: glows.count)
        shown = [Float](repeating: 0, count: glows.count)
    }

    func tick(time: Float, step: Float, links: [GraphRibbonLink], far: [GraphRibbonLink]) {
        let clock = NSNumber(value: time)
        for material in swaying { material.setValue(clock, forKey: "rpSway") }
        ease(time)
        // a new clock, a wrap or a long pause: start watching from now
        guard last >= 0, time > last, time - last < 1 else {
            last = time
            return
        }
        let fade: Float = exp(-step / 0.35)
        for i in level.indices where level[i] > 0 { level[i] *= fade }
        if rate > 0 {
            land(links, until: time)
            land(far, until: time)
        }
        last = time
        for i in glows.indices {
            let want: Float = level[i] < 0.02 ? 0 : level[i]
            guard abs(want - shown[i]) > 0.02 || (want == 0 && shown[i] > 0) else { continue }
            shown[i] = want
            guard let glow = glows[i] else { continue }
            glow.isHidden = want == 0
            glow.opacity = CGFloat(want)
        }
    }

    /// The containers' openings, smoothstepped over 0.9 s.
    private func ease(_ time: Float) {
        guard !settled else { return }
        if openedAt < 0 || time < openedAt { openedAt = time }
        let t: Float = min(max((time - openedAt) / 0.9, 0), 1)
        let k: Float = t * t * (3 - 2 * t)
        for opening in openings {
            let value: Float = opening.from + (opening.to - opening.from) * k
            opening.material.setValue(NSNumber(value: value), forKey: "rpOpen")
        }
        if t >= 1 { settled = true }
    }

    private func land(_ list: [GraphRibbonLink], until time: Float) {
        for link in list where link.grow > 0.99 && link.b < level.count {
            let seed: Int = GraphRibbonWriter.themeSeed(link.seed)
            if NeuronImpulse.lands(seed: seed, from: last, to: time, rate: rate, bursts: bursts) {
                level[link.b] = 1
            }
        }
    }
}

/// A container opening (to 1) or closing (to 0): its own soma material,
/// whose rpOpen NeuronImpulses eases.
nonisolated struct NeuronOpening {
    let material: SCNMaterial
    let from: Float
    let to: Float
}

// MARK: - The dendrites' shapes

/// One tapered tube of an arbor, in the soma's unit frame: a quadratic
/// curve from `start` through `bend` to `end`, `r0` thick at the start and
/// `r1` at the tip; `s0`...`s1` its share of the dendrite's length (the
/// shader fades and beads by it). `flare` widens the base into a trumpet
/// (by flare * (1 - t)^4 along it), so a dendrite flows out of the glass
/// round the soma, as in the owner's close-up.
nonisolated struct NeuronBranch: Sendable {
    let start: SIMD3<Float>
    let bend: SIMD3<Float>
    let end: SIMD3<Float>
    let r0: Float
    let r1: Float
    let s0: Float
    let s1: Float
    var flare: Float = 0
}

@MainActor
enum NeuronArbor {
    /// The branches for a kind of cell (three variants each), each from
    /// 0.9 of the radius (a cell's from 0.75, inside its glass), every tip
    /// within the map's reach (GraphNeurons.reach for a cell and a
    /// receptor, about 1.15 radii for a drifter and a bipolar cell):
    /// a cell's crown of dendrites as in the owner's close-up - thick glass
    /// tubes round it in the plane facing the camera (tilting a little out
    /// of it), each flaring into a trumpet where it leaves the soma (the
    /// trumpets together the glass body the soma sits in, webbed between)
    /// and tapering only a little, its tip faded out by the shader; a
    /// receptor's leading process ending in a fan, and a short one behind;
    /// a drifter's many fine processes; a bipolar cell's two opposite ones.
    /// What floats inside a cell has none. `rich` adds a cell a dendrite
    /// and the others side branches.
    static func branches(_ kind: NeuronCellKind, variant: Int, rich: Bool) -> [NeuronBranch] {
        var random = UniverseRandom(UInt64(kind.rawValue * 31 + variant) &* 0x9E37_79B9 &+ 7)
        var out: [NeuronBranch] = []
        func add(_ dir: SIMD3<Float>, length: Float, thick: Float, sides: Int, from: Float = 0.9,
                 tipShare: Float = 0.12, flare: Float = 0, planar: Bool = false) {
            let d: SIMD3<Float> = simd_normalize(dir)
            let start: SIMD3<Float> = d * from
            // a crown in the plane wanders in it, so its bends show
            let side: SIMD3<Float> = planar
                ? GraphLinkCurve.unit(GraphLinkCurve.cross(d, SIMD3<Float>(0, 0, 1)), or: SIMD3<Float>(1, 0, 0))
                : GraphLinkCurve.perpendicular(to: d)
            let wander: Float = Float(random.signed()) * 0.3 * length
            let bend: SIMD3<Float> = start + d * (length * 0.5) + side * wander
            let lean: SIMD3<Float> = side * (wander * 0.6)
            let end: SIMD3<Float> = start + d * length + lean
            out.append(NeuronBranch(start: start, bend: bend, end: end, r0: thick, r1: thick * tipShare, s0: 0, s1: 1,
                                    flare: flare))
            guard sides > 0 && (rich || sides > 1) else { return }
            for k in 0..<sides {
                let t: Float = 0.4 + 0.25 * Float(k) + 0.1 * Float(random.unit())
                let at: SIMD3<Float> = curve(start, bend, end, min(t, 0.85))
                let twist: Float = Float(random.unit()) * 2 * Float.pi
                let axis: SIMD3<Float> = GraphLinkCurve.rotate(side, about: d, by: twist)
                let out2: SIMD3<Float> = GraphLinkCurve.rotate(d, about: axis, by: 0.7 + 0.3 * Float(random.unit()))
                // a side branch's tip stays inside the reach too
                let room: Float = max(Float(GraphNeurons.reach) - 0.03 - simd_length(at), 0.04)
                let reach: Float = min(length * (0.35 + 0.15 * Float(random.unit())), room)
                let mid: SIMD3<Float> = at + out2 * (reach * 0.5)
                let tip: SIMD3<Float> = at + out2 * reach
                let r: Float = thick * (1 - t) * 0.75
                out.append(NeuronBranch(start: at, bend: mid, end: tip, r0: r, r1: r * 0.15, s0: t, s1: 1))
            }
        }
        let extra: Int = rich ? 1 : 0
        switch kind {
        case .cell:
            let count: Int = 6 + extra
            // the longest a dendrite from 0.75 can be with its tip in reach
            let most: Float = Float(GraphNeurons.reach) - 0.75 - 0.05
            for k in 0..<count {
                let a: Float = 2 * Float.pi * (Float(k) + 0.35 * Float(random.signed())) / Float(count)
                let dir = SIMD3<Float>(cos(a), sin(a), 0.35 * Float(random.signed()))
                let length: Float = min(1.0 + 0.2 * Float(random.unit()), most)
                add(dir, length: length, thick: 0.3, sides: 0, from: 0.75, tipShare: 0.7, flare: 0.5,
                    planar: true)
            }
        case .receptor:
            add(SIMD3<Float>(0, 1, 0), length: 0.65, thick: 0.24, sides: 0)
            let tip: SIMD3<Float> = out.last?.end ?? SIMD3<Float>(0, 1.55, 0)
            for k in 0..<4 {
                let a: Float = Float(k) * Float.pi / 2
                let dir = SIMD3<Float>(cos(a) * 0.7, 1, sin(a) * 0.7)
                let end: SIMD3<Float> = tip + simd_normalize(dir) * 0.15
                let mid: SIMD3<Float> = (tip + end) * 0.5
                out.append(NeuronBranch(start: tip, bend: mid, end: end, r0: 0.07, r1: 0.03, s0: 0.8, s1: 1))
            }
            add(SIMD3<Float>(0, -1, 0), length: 0.4, thick: 0.17, sides: 0)
        case .drifter:
            for k in 0..<12 {
                let d: SIMD3<Float> = GraphUniverse.float3(ThemeLayout.fibonacci(k, 12))
                add(d, length: 0.2 + 0.05 * Float(random.unit()), thick: 0.09, sides: 0)
            }
        case .bipolar:
            add(SIMD3<Float>(0, 1, 0.1), length: 0.25, thick: 0.2, sides: 0)
            add(SIMD3<Float>(0, -1, -0.1), length: 0.22, thick: 0.18, sides: 0)
            add(SIMD3<Float>(1, 0, 0.3), length: 0.12, thick: 0.12, sides: 0)
            add(SIMD3<Float>(-1, 0.2, -0.3), length: 0.12, thick: 0.12, sides: 0)
        case .part, .vesicle, .granule:
            break
        }
        return out
    }

    static func curve(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let u: Float = 1 - t
        let ab: SIMD3<Float> = a * (u * u) + b * (2 * u * t)
        return ab + c * (t * t)
    }

    /// Every branch as a tube of `sides` round and `segments` along, in one
    /// geometry (texture u: the share along the dendrite, v: round it); a
    /// flared one's rings crowd toward its base, where the trumpet curves.
    static func mesh(_ branches: [NeuronBranch], sides: Int, segments: Int) -> SCNGeometry {
        var points: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var coords: [CGPoint] = []
        var indices: [Int32] = []
        let ring: Int = max(sides, 3)
        let steps: Int = max(segments, 2)
        for branch in branches {
            let first: Int32 = Int32(points.count)
            for j in 0...steps {
                let even: Float = Float(j) / Float(steps)
                let t: Float = branch.flare > 0 ? pow(even, 1.6) : even
                let p: SIMD3<Float> = curve(branch.start, branch.bend, branch.end, t)
                let ahead: SIMD3<Float> = curve(branch.start, branch.bend, branch.end, min(t + 0.02, 1))
                let behind: SIMD3<Float> = curve(branch.start, branch.bend, branch.end, max(t - 0.02, 0))
                let along: SIMD3<Float> = GraphLinkCurve.unit(ahead - behind, or: SIMD3<Float>(0, 1, 0))
                let n1: SIMD3<Float> = GraphLinkCurve.perpendicular(to: along)
                let n2: SIMD3<Float> = GraphLinkCurve.cross(along, n1)
                let rest: Float = 1 - t
                let bell: Float = rest * rest
                let taper: Float = branch.r0 + (branch.r1 - branch.r0) * t + branch.flare * bell * bell
                let s: Float = branch.s0 + (branch.s1 - branch.s0) * t
                for k in 0...ring {
                    let a: Float = Float(k) / Float(ring) * 2 * Float.pi
                    let n: SIMD3<Float> = n1 * cos(a) + n2 * sin(a)
                    let v: SIMD3<Float> = p + n * taper
                    points.append(SCNVector3(x: v.x, y: v.y, z: v.z))
                    normals.append(SCNVector3(x: n.x, y: n.y, z: n.z))
                    coords.append(CGPoint(x: CGFloat(s), y: CGFloat(Float(k) / Float(ring))))
                }
            }
            let row: Int32 = Int32(ring + 1)
            for j in 0..<steps {
                for k in 0..<ring {
                    let a: Int32 = first + Int32(j) * row + Int32(k)
                    let b: Int32 = a + row
                    indices.append(contentsOf: [a, b, a + 1, a + 1, b, b + 1])
                }
            }
        }
        let vertexSource = SCNGeometrySource(vertices: points)
        let normalSource = SCNGeometrySource(normals: normals)
        let coordSource = SCNGeometrySource(textureCoordinates: coords)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vertexSource, normalSource, coordSource], elements: [element])
    }
}

// MARK: - The fluid behind

/// The Neurons' backdrop, in place of the stars, as behind the owner's
/// close-up: dark teal-navy fluid lit by soft, wide glows (teal, blue, a
/// little violet), far neurons blurred out of focus in blue (NeuronBokeh.farCells)
/// and bokeh - gold and blue discs out of focus behind the microscope's
/// plane (NeuronBokeh.discs). Made once, on a sphere of radius 1, shared by
/// every scene and scaled by the builder; GraphSim keeps it round the
/// camera, so it is at infinity.
@MainActor
enum NeuronTissue {
    static func makeSky() -> SCNNode {
        let sky = SCNNode()
        sky.name = "sky"
        sky.categoryBitMask = 2
        let dome = SCNNode(geometry: Self.dome)
        dome.renderingOrder = -30
        dome.categoryBitMask = 2
        sky.addChildNode(dome)
        // both added on, so their order does not matter
        let far = SCNNode(geometry: Self.farCells)
        far.renderingOrder = -29
        far.categoryBitMask = 2
        sky.addChildNode(far)
        let bokeh = SCNNode(geometry: Self.bokeh)
        bokeh.renderingOrder = -29
        bokeh.categoryBitMask = 2
        sky.addChildNode(bokeh)
        return sky
    }

    /// The glows: (direction, reach in radians, colour, sRGB).
    private static func glows() -> [(SIMD3<Float>, Float, SIMD3<Float>)] {
        var random = UniverseRandom(0x7155)
        let hues: [SIMD3<Float>] = [
            SIMD3<Float>(0.02, 0.05, 0.08), SIMD3<Float>(0.015, 0.06, 0.07), SIMD3<Float>(0.035, 0.03, 0.08),
            SIMD3<Float>(0.015, 0.045, 0.08)
        ]
        var out: [(SIMD3<Float>, Float, SIMD3<Float>)] = []
        for k in 0..<16 {
            let d: SIMD3<Float> = GraphUniverse.float3(ThemeLayout.fibonacci(k, 16))
            let jitter = SIMD3<Float>(Float(random.signed()), Float(random.signed()), Float(random.signed()))
            let dir: SIMD3<Float> = simd_normalize(d + jitter * 0.3)
            let reach: Float = 0.35 + 0.45 * Float(random.unit())
            out.append((dir, reach, hues[k % hues.count]))
        }
        return out
    }

    private static let dome: SCNGeometry = makeDome()

    private static func makeDome() -> SCNGeometry {
        let columns: Int = 64
        let rows: Int = 32
        let lights: [(SIMD3<Float>, Float, SIMD3<Float>)] = glows()
        var positions: [SCNVector3] = []
        var colours: [Float] = []
        for row in 0...rows {
            let lat: Float = Float.pi * (Float(row) / Float(rows) - 0.5)
            for column in 0...columns {
                let lon: Float = 2 * Float.pi * Float(column) / Float(columns)
                let flat: Float = cos(lat)
                let dir = SIMD3<Float>(flat * cos(lon), sin(lat), flat * sin(lon))
                positions.append(SCNVector3(x: dir.x, y: dir.y, z: dir.z))
                var c: SIMD3<Float> = NeuronPalette.deep
                for (centre, reach, hue) in lights {
                    let gap: Float = simd_distance(dir, centre) / reach
                    c += hue * exp(-gap * gap)
                }
                let lin: SIMD3<Float> = linear(c)
                colours.append(contentsOf: [lin.x, lin.y, lin.z])
            }
        }
        var indices: [Int32] = []
        let stride: Int = columns + 1
        for row in 0..<rows {
            for column in 0..<columns {
                let a = Int32(row * stride + column)
                let b = Int32(row * stride + column + 1)
                let c = Int32((row + 1) * stride + column)
                let d = Int32((row + 1) * stride + column + 1)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), colourSource(colours, positions.count)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        geometry.materials = [material]
        return geometry
    }

    private static let bokeh: SCNGeometry = makeBokeh()

    /// The bokeh discs (NeuronBokeh.discs), in one geometry.
    private static func makeBokeh() -> SCNGeometry {
        let quads: [SkyQuad] = NeuronBokeh.discs().map { disc in
            SkyQuad(direction: disc.direction, size: disc.size, turn: 0,
                    tint: linear(disc.colour * (0.32 * disc.strength)))
        }
        return skyQuads(quads, radius: 0.98, image: NeuronArt.bokehDisc)
    }

    private static let farCells: SCNGeometry = makeFarCells()

    /// The far neurons (NeuronBokeh.farCells), each turned its own way, in
    /// one geometry, a little farther out than the bokeh.
    private static func makeFarCells() -> SCNGeometry {
        let quads: [SkyQuad] = NeuronBokeh.farCells().map { cell in
            SkyQuad(direction: cell.direction, size: cell.size, turn: cell.turn,
                    tint: linear(cell.colour * (0.42 * cell.strength)))
        }
        return skyQuads(quads, radius: 0.97, image: NeuronArt.farNeuron)
    }

    /// One picture on the sky: where (unit), its half side (radians), how
    /// it is turned (radians) and its colour (linear).
    private struct SkyQuad {
        let direction: SIMD3<Float>
        let size: Float
        let turn: Float
        let tint: SIMD3<Float>
    }

    /// Quads facing the middle at `radius`, each showing `image` in its
    /// vertices' colour, added on, in one geometry.
    private static func skyQuads(_ quads: [SkyQuad], radius: Float, image: UIImage) -> SCNGeometry {
        var positions: [SCNVector3] = []
        var coords: [CGPoint] = []
        var colours: [Float] = []
        var indices: [Int32] = []
        for quad in quads {
            let dir: SIMD3<Float> = quad.direction
            let a: SIMD3<Float> = GraphLinkCurve.perpendicular(to: dir)
            let b: SIMD3<Float> = GraphLinkCurve.cross(dir, a)
            let u: SIMD3<Float> = a * cos(quad.turn) + b * sin(quad.turn)
            let v: SIMD3<Float> = GraphLinkCurve.cross(dir, u)
            let first = Int32(positions.count)
            let corners: [(Float, Float)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            for (x, y) in corners {
                let p: SIMD3<Float> = dir * radius + u * (x * quad.size) + v * (y * quad.size)
                positions.append(SCNVector3(x: p.x, y: p.y, z: p.z))
                coords.append(CGPoint(x: CGFloat((x + 1) / 2), y: CGFloat((y + 1) / 2)))
                colours.append(contentsOf: [quad.tint.x, quad.tint.y, quad.tint.z])
            }
            indices.append(contentsOf: [first, first + 1, first + 2, first, first + 2, first + 3])
        }
        let sources: [SCNGeometrySource] = [SCNGeometrySource(vertices: positions),
                                            SCNGeometrySource(textureCoordinates: coords),
                                            colourSource(colours, positions.count)]
        let geometry = SCNGeometry(sources: sources,
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.blendMode = .add
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        geometry.materials = [material]
        return geometry
    }

    private static func colourSource(_ colours: [Float], _ count: Int) -> SCNGeometrySource {
        let data: Data = colours.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: .color, vectorCount: count, usesFloatComponents: true,
                                 componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
    }

    /// sRGB to linear: vertex colours are taken as linear.
    private static func linear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(pow(max(c.x, 0), 2.2), pow(max(c.y, 0), 2.2), pow(max(c.z, 0), 2.2))
    }
}

/// Small pictures, drawn once: a soft disc (the fallback glows), a bokeh
/// disc (flat, a little brighter at its rim, soft-edged - a light out of
/// focus through a round aperture) and a far neuron out of focus (as
/// behind the owner's close-up).
@MainActor
enum NeuronArt {
    static let softDisc: UIImage = draw { context, size in
        let colours: [CGColor] = [UIColor.white.cgColor, UIColor(white: 1, alpha: 0).cgColor]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray,
                                        locations: [0, 1]) else { return }
        let middle = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle,
                                   endRadius: size / 2, options: [])
    }

    static let bokehDisc: UIImage = draw { context, size in
        let clear = UIColor(white: 1, alpha: 0).cgColor
        let body = UIColor(white: 1, alpha: 0.62).cgColor
        let rim = UIColor(white: 1, alpha: 0.9).cgColor
        let colours: [CGColor] = [body, body, rim, clear]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray,
                                        locations: [0, 0.7, 0.86, 1]) else { return }
        let middle = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle,
                                   endRadius: size / 2, options: [])
    }

    /// A soft body and six tapering branches, each forking on the way,
    /// drawn white (the vertex colour tints it), then blurred.
    static let farNeuron: UIImage = blurred(draw(side: 256) { context, size in
        var random = UniverseRandom(0xFA2D)
        let middle = CGPoint(x: size / 2, y: size / 2)
        context.setFillColor(UIColor.white.cgColor)
        for k in 0..<6 {
            let angle: CGFloat = (CGFloat(k) + 0.6 * CGFloat(random.signed())) / 6 * 2 * .pi
            let length: CGFloat = size * (0.26 + 0.14 * CGFloat(random.unit()))
            branch(context, from: middle, angle: angle, length: length, width: size * 0.026, forks: 2,
                   random: &random)
        }
        let colours: [CGColor] = [UIColor.white.cgColor, UIColor(white: 1, alpha: 0.6).cgColor,
                                  UIColor(white: 1, alpha: 0).cgColor]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray,
                                        locations: [0, 0.45, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle,
                                   endRadius: size * 0.1, options: [])
    }, sigma: 2.5)

    /// One tapering branch from `start`: a gently bending filled shape,
    /// `width` thick at its base and a quarter of that at its tip, with
    /// `forks` more branches leaving it half to two thirds of the way out.
    private static func branch(_ context: CGContext, from start: CGPoint, angle: CGFloat, length: CGFloat,
                               width: CGFloat, forks: Int, random: inout UniverseRandom) {
        let steps: Int = 10
        let bend: CGFloat = 0.09 * CGFloat(random.signed())
        let forkAt: Int = 5 + Int(random.unit() * 2)
        var spine: [(CGPoint, CGFloat)] = [(start, angle)]
        var heading: CGFloat = angle
        var at: CGPoint = start
        for _ in 0..<steps {
            heading += bend + 0.05 * CGFloat(random.signed())
            at = CGPoint(x: at.x + cos(heading) * length / CGFloat(steps),
                         y: at.y + sin(heading) * length / CGFloat(steps))
            spine.append((at, heading))
        }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for (i, (p, h)) in spine.enumerated() {
            let w: CGFloat = width * (1 - 0.75 * CGFloat(i) / CGFloat(steps)) / 2
            left.append(CGPoint(x: p.x - sin(h) * w, y: p.y + cos(h) * w))
            right.append(CGPoint(x: p.x + sin(h) * w, y: p.y - cos(h) * w))
        }
        context.beginPath()
        context.addLines(between: left + right.reversed())
        context.closePath()
        context.fillPath()
        guard forks > 0 else { return }
        let (p, h) = spine[forkAt]
        let side: CGFloat = random.unit() < 0.5 ? -1 : 1
        branch(context, from: p, angle: h + side * (0.4 + 0.35 * CGFloat(random.unit())),
               length: length * (0.45 + 0.2 * CGFloat(random.unit())),
               width: width * (1 - 0.75 * CGFloat(forkAt) / CGFloat(steps)) * 0.85, forks: forks - 1,
               random: &random)
    }

    /// `image` out of focus: a Gaussian blur of `sigma` pixels (the image
    /// as drawn, should the blur fail).
    private static func blurred(_ image: UIImage, sigma: Double) -> UIImage {
        guard let input = CIImage(image: image) else { return image }
        let soft: CIImage = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        guard let made = CIContext(options: nil).createCGImage(soft, from: input.extent) else { return image }
        return UIImage(cgImage: made)
    }

    private static func draw(side: CGFloat = 64, _ paint: (CGContext, CGFloat) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { context in paint(context.cgContext, side) }
    }
}

// MARK: - Checking the shaders work

/// Which Neurons shaders compiled and drew on this device; a piece whose
/// shader failed is drawn plainly instead (see GraphNeuronLook).
nonisolated struct NeuronSupport: Sendable {
    let passed: Set<String>

    func has(_ name: String) -> Bool { passed.contains(name) }
}

/// Tries each Neurons shader once, off the main thread (GraphThemes.prepare,
/// before the first build), in GraphStyleProbe's tiny offscreen render: the
/// soma and arbor with their geometry modifiers on a sphere, the rest on a
/// plane.
nonisolated enum NeuronProbe {
    static let support: NeuronSupport = run()

    private static func run() -> NeuronSupport {
        guard let device = MTLCreateSystemDefaultDevice() else { return NeuronSupport(passed: []) }
        let tries: [(String, [SCNShaderModifierEntryPoint: String], Bool)] = [
            ("soma", [.geometry: NeuronShaders.wobble, .surface: NeuronShaders.soma], true),
            ("arbor", [.geometry: NeuronShaders.sway, .surface: NeuronShaders.arbor], true),
            ("halo", [.surface: NeuronShaders.halo], false),
            ("arrival", [.surface: NeuronShaders.arrival], false),
            ("axon", [.surface: NeuronShaders.axon], false)
        ]
        var passed = Set<String>()
        for (name, modifiers, round) in tries {
            let shape: SCNGeometry = round ? SCNSphere(radius: 1.5) : SCNPlane(width: 4, height: 4)
            let ok: Bool = GraphStyleProbe.renders(modifiers, on: shape, device: device) { material in
                let values: [(String, Float)] = [("rpMotion", 1), ("rpNucleus", 0.4), ("rpSway", 0),
                                                 ("rpWobble", 0.02), ("rpGain", 1), ("rpRate", 0.5),
                                                 ("rpBurst", 0.2), ("rpBundle", 0), ("rpHalf", 0.1),
                                                 ("rpOpen", 0), ("rpFill", 1),
                                                 ("rpState", 1)]
                for (key, value) in values { material.setValue(NSNumber(value: value), forKey: key) }
            }
            if ok { passed.insert(name) }
        }
        return NeuronSupport(passed: passed)
    }
}
