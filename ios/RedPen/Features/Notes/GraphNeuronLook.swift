import SceneKit
import UIKit
import Metal
import simd

// MARK: - The Neurons look
//
// How the Neurons theme (GraphNeurons) is dressed, for the shared theme
// scene (GraphThemeScene): every cell a translucent, glowing gel body -
// soma (NeuronShaders.soma, its membrane wobbling), its dendritic arbor of
// soft tapered tubes (swaying), a halo round it, and a glow its dendrites
// give off when an impulse arrives - on a dark tissue backdrop of blurred
// extracellular light and out-of-focus cells, instead of stars.
//
// Colours are fluorescence dyes on black: each region its own (teal, green,
// azure, violet, lime), its nucleus in a second dye; receptors gold,
// microglia pale ice; axons pale teal, impulses amber with a magenta halo.
//
// Nothing is made per cell but its nodes: materials are one per (region
// dye, kind of cell), geometry one sphere and a few arbor shapes per kind,
// shared; every cell is turned at random so no two look alike.
//
// The Graphics budget (GraphQuality.current) sets the cost: at Smooth the
// sphere has fewer segments, the arbors fewer sides, samples and side
// branches, the shaders their simple path (rpDetail 0: no organelles, no
// spines, no bursts) and fewer impulses fire. Reduce Motion or a still
// space: no wobble, no sway, no impulses - the picture whole but still.

/// What kind of cell a body is drawn as (its material and arbor).
nonisolated enum NeuronCellKind: Int, CaseIterable, Sendable {
    case hub
    case pyramidal
    case interneuron
    case commissural
    case glia
    case receptor
    case microglia

    static func of(_ role: NeuronRole) -> NeuronCellKind {
        switch role {
        case .region, .relay, .brainstem: return .hub
        case .pyramidal: return .pyramidal
        case .interneuron: return .interneuron
        case .commissural: return .commissural
        case .glia: return .glia
        case .receptor: return .receptor
        case .microglia: return .microglia
        }
    }

    /// The nucleus's radius, as a share of the cell's.
    var nucleus: Float {
        switch self {
        case .hub: return 0.42
        case .pyramidal, .commissural: return 0.46
        case .interneuron: return 0.5
        case .glia: return 0.32
        case .receptor: return 0.4
        case .microglia: return 0.28
        }
    }

    /// How far the membrane wobbles, as a share of the radius.
    var wobble: Float {
        switch self {
        case .hub: return 0.03
        case .pyramidal, .commissural, .receptor: return 0.04
        case .interneuron: return 0.045
        case .glia: return 0.05
        case .microglia: return 0.07
        }
    }
}

@MainActor
final class GraphNeuronLook: GraphThemeLook {
    let theme: GraphTheme = .neurons
    let lively: Bool
    let bold: Bool
    let budget: GraphicsBudget
    let support: NeuronSupport
    let linkMaterial: SCNMaterial
    let farMaterial: SCNMaterial
    let linkHalfWidth: Float = 0.08
    let farHalfWidth: Float = 0.13

    /// Every axon ends in one synapse on its target, a gel golf-tee cup
    /// (GraphLinkArbor, drawn by NeuronShaders.axon): the cell's membrane
    /// is 1.25 of its trim radius; one fibre is 0.3 of an axon's half
    /// width, 0.2 of a tract's (three fibres, gathered before the cup).
    /// Only when the axon shader works: the plain fallback draws no cup.
    var arbor: GraphLinkArbor? {
        support.has("axon") ? GraphLinkArbor(membrane: 1.25, share: 0.3) : nil
    }

    var farArbor: GraphLinkArbor? {
        support.has("axon") ? GraphLinkArbor(membrane: 1.25, share: 0.2) : nil
    }
    let hotRing: SCNGeometry
    private(set) var clocked: [SCNMaterial] = []
    /// Materials whose geometry modifiers read `rpSway` (NeuronImpulses
    /// sets it each frame).
    private(set) var swaying: [SCNMaterial] = []
    private var somaLooks: [String: SCNMaterial] = [:]
    private var somaShapes: [String: SCNGeometry] = [:]
    private var arborLooks: [String: SCNGeometry] = [:]
    private var haloLooks: [Int: SCNGeometry] = [:]
    private let sphere: SCNGeometry
    private let arrivalPlane: SCNGeometry
    /// Each region's dye slot, by body index.
    private var slotOf: [Int: Int] = [:]
    private var slotsFor: Int = -1

    init(lively: Bool, bold: Bool) {
        self.lively = lively
        self.bold = bold
        let budget: GraphicsBudget = GraphQuality.current
        self.budget = budget
        let support: NeuronSupport = NeuronProbe.support
        self.support = support
        linkMaterial = Self.axonMaterial(bundle: false, bold: bold, lively: lively, budget: budget, support: support,
                                         half: 0.08)
        farMaterial = Self.axonMaterial(bundle: true, bold: bold, lively: lively, budget: budget, support: support,
                                        half: 0.13)
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

    /// The regions' membrane dyes and their nuclei's (sRGB, as on screen).
    static let dyes: [(SIMD3<Float>, SIMD3<Float>)] = [
        (SIMD3<Float>(0.30, 0.95, 0.85), SIMD3<Float>(0.45, 0.55, 1.0)),
        (SIMD3<Float>(0.50, 1.00, 0.55), SIMD3<Float>(0.75, 0.55, 1.0)),
        (SIMD3<Float>(0.42, 0.72, 1.00), SIMD3<Float>(0.35, 0.95, 0.80)),
        (SIMD3<Float>(0.75, 0.58, 1.00), SIMD3<Float>(0.45, 0.95, 0.75)),
        (SIMD3<Float>(0.72, 1.00, 0.50), SIMD3<Float>(0.40, 0.60, 1.00))
    ]
    static let receptorDye = (SIMD3<Float>(1.0, 0.82, 0.45), SIMD3<Float>(0.5, 0.6, 1.0))
    static let microgliaDye = (SIMD3<Float>(0.62, 0.78, 0.95), SIMD3<Float>(0.9, 0.6, 0.9))
    static let organelles = SIMD3<Float>(0.9, 0.95, 0.7)
    static let fibre = SIMD3<Float>(0.50, 0.90, 0.86)
    static let tract = SIMD3<Float>(0.45, 0.80, 0.95)
    static let impulse = SIMD3<Float>(1.0, 0.72, 0.30)
    static let impulseHalo = SIMD3<Float>(1.0, 0.32, 0.80)

    /// A body's dye slot: its region's place in the plan (5 dyes round), 5
    /// for a receptor, 6 for a microglial cell.
    private func slot(_ body: ThemeBody, plan: ThemePlan) -> Int {
        if slotsFor != plan.bodies.count {
            slotOf = [:]
            for (k, r) in plan.regions.enumerated() { slotOf[r] = k % Self.dyes.count }
            slotsFor = plan.bodies.count
        }
        if body.region >= 0 { return slotOf[body.region] ?? 0 }
        return body.role == NeuronRole.microglia.rawValue ? 6 : 5
    }

    private static func dye(_ slot: Int) -> (SIMD3<Float>, SIMD3<Float>) {
        if slot == 5 { return receptorDye }
        if slot == 6 { return microgliaDye }
        return dyes[max(slot, 0) % dyes.count]
    }

    func tone(region: Int, plan: ThemePlan) -> UIColor? {
        guard region >= 0, region < plan.bodies.count else { return nil }
        let c: SIMD3<Float> = Self.dye(slot(plan.bodies[region], plan: plan)).0
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    // MARK: a cell

    func makeBody(_ body: ThemeBody, index: Int, plan: ThemePlan) -> GraphThemeParts {
        let node = SCNNode()
        switch body.kind {
        case .note: node.name = "note:" + body.id.uuidString
        case .folder: node.name = "folder:" + body.id.uuidString
        case .home: node.name = "home"
        case .fixture: node.name = "fixture"
        }
        let role: NeuronRole = NeuronRole(rawValue: body.role) ?? .interneuron
        let kind: NeuronCellKind = NeuronCellKind.of(role)
        let dyeSlot: Int = slot(body, plan: plan)
        var random = UniverseRandom(body.seed ^ 0xCE11)
        let size: Float = body.sphere

        let soma = SCNNode(geometry: somaGeometry(slot: dyeSlot, kind: kind))
        soma.simdScale = SIMD3<Float>(size, size, size)
        soma.simdOrientation = Self.randomTurn(&random)
        soma.renderingOrder = 6
        node.addChildNode(soma)

        let variant: Int = Int(body.seed % 3)
        let arbor = SCNNode(geometry: arborGeometry(kind: kind, variant: variant, slot: dyeSlot))
        arbor.simdScale = SIMD3<Float>(size, size, size)
        arbor.simdOrientation = Self.arborTurn(kind, axis: body.axis, random: &random)
        arbor.renderingOrder = 6
        arbor.categoryBitMask = 2
        node.addChildNode(arbor)

        // the halo, on GraphSim's ring pieces
        let holder = SCNNode()
        let facing = SCNBillboardConstraint()
        facing.freeAxes = .all
        holder.constraints = [facing]
        let stretch = SCNNode()
        // Smooth (no haze): no standing halo - one blended quad five times
        // the cell's size less for every cell - only the chosen one's
        let halo: SCNGeometry = budget.haze ? haloGeometry(slot: dyeSlot) : GraphThemeParts.noHalo
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

        var parts = GraphThemeParts(node: node, radius: size * 0.8, ringStretch: stretch, ringLeaf: leaf,
                                    ringGeometry: halo, diskLeaf: disk)
        parts.glow = glow
        // the many small cells' halos go first in a crowded map
        parts.thinnable = body.kind == .note && kind != .pyramidal
        return parts
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

    /// A pyramidal cell's apical dendrite, and a receptor's peripheral
    /// process, point outward (the arbor's +y along the body's axis),
    /// twisted at random about it; every other arbor turned anyhow.
    private static func arborTurn(_ kind: NeuronCellKind, axis: SIMD3<Float>,
                                  random: inout UniverseRandom) -> simd_quatf {
        guard kind == .pyramidal || kind == .receptor else { return randomTurn(&random) }
        let up = SIMD3<Float>(0, 1, 0)
        let size: Float = simd_length(axis)
        let to: SIMD3<Float> = size > 0.0001 ? axis / size : up
        let twist: Float = Float(random.unit()) * 2 * Float.pi
        let along = simd_quatf(from: up, to: to)
        return simd_quatf(angle: twist, axis: to) * along
    }

    // MARK: materials

    /// The shared sphere, dressed once per dye and kind of cell.
    private func somaGeometry(slot: Int, kind: NeuronCellKind) -> SCNGeometry {
        let key: String = "s\(slot)-\(kind.rawValue)"
        if let made = somaShapes[key] { return made }
        let copy: SCNGeometry = sphere.copy() as? SCNGeometry ?? sphere
        copy.materials = [makeSoma(slot: slot, kind: kind)]
        somaShapes[key] = copy
        return copy
    }

    private func makeSoma(slot: Int, kind: NeuronCellKind) -> SCNMaterial {
        let dye: (SIMD3<Float>, SIMD3<Float>) = Self.dye(slot)
        var membrane: SIMD3<Float> = dye.0
        if kind == .glia { membrane = (dye.0 + SIMD3<Float>(0.95, 0.9, 0.8)) * 0.5 }
        let material: SCNMaterial = Self.additive()
        guard support.has("soma") else {
            material.diffuse.contents = Self.colour(membrane * 0.45)
            return material
        }
        material.shaderModifiers = [.geometry: NeuronShaders.wobble, .surface: NeuronShaders.soma]
        GraphStyleUniforms.defaults(material)
        Self.set(material, "rpMotion", lively ? 1 : 0)
        Self.set(material, "rpDetail", budget.shaderDetail)
        Self.set(material, "rpNucleus", kind.nucleus)
        Self.set(material, "rpSway", 0)
        Self.set(material, "rpWobble", lively ? kind.wobble : 0)
        Self.tint(material, "rpTintA", membrane)
        Self.tint(material, "rpTintB", dye.1)
        Self.tint(material, "rpTintC", Self.organelles)
        clocked.append(material)
        swaying.append(material)
        return material
    }

    private func arborGeometry(kind: NeuronCellKind, variant: Int, slot: Int) -> SCNGeometry {
        let key: String = "a\(kind.rawValue)-\(variant)-\(slot)"
        if let made = arborLooks[key] { return made }
        let shapeKey: String = "shape\(kind.rawValue)-\(variant)"
        let shape: SCNGeometry
        if let made = arborLooks[shapeKey] {
            shape = made
        } else {
            let high: Bool = budget.tier == .high
            let branches: [NeuronBranch] = NeuronArbor.branches(kind, variant: variant, rich: high)
            shape = NeuronArbor.mesh(branches, sides: high ? 6 : 4, segments: high ? 10 : 6)
            arborLooks[shapeKey] = shape
        }
        let geometry: SCNGeometry = shape.copy() as? SCNGeometry ?? shape
        geometry.materials = [makeArbor(slot: slot, kind: kind)]
        arborLooks[key] = geometry
        return geometry
    }

    private func makeArbor(slot: Int, kind: NeuronCellKind) -> SCNMaterial {
        let key: String = "m\(slot)-\(kind == .glia ? 1 : 0)"
        if let made = somaLooks[key] { return made }
        let dye: (SIMD3<Float>, SIMD3<Float>) = Self.dye(slot)
        var membrane: SIMD3<Float> = dye.0
        if kind == .glia { membrane = (dye.0 + SIMD3<Float>(0.95, 0.9, 0.8)) * 0.5 }
        let material: SCNMaterial = Self.additive()
        if support.has("arbor") {
            material.shaderModifiers = [.geometry: NeuronShaders.sway, .surface: NeuronShaders.arbor]
            GraphStyleUniforms.defaults(material)
            Self.set(material, "rpDetail", budget.shaderDetail)
            Self.set(material, "rpSway", 0)
            Self.set(material, "rpWobble", lively ? 0.03 : 0)
            Self.tint(material, "rpTintA", membrane * 0.95)
            swaying.append(material)
        } else {
            material.diffuse.contents = Self.colour(membrane * 0.25)
        }
        somaLooks[key] = material
        return material
    }

    private func haloGeometry(slot: Int) -> SCNGeometry {
        if let made = haloLooks[slot] { return made }
        let tint: SIMD3<Float> = Self.dye(slot).0
        let plane: SCNGeometry = GraphSceneBuilder.plane(Self.haloMaterial(tint: tint, hot: false, support: support))
        haloLooks[slot] = plane
        return plane
    }

    private static func haloMaterial(tint: SIMD3<Float>, hot: Bool, support: NeuronSupport) -> SCNMaterial {
        let material: SCNMaterial = additive()
        material.isDoubleSided = true
        guard support.has("halo") else {
            material.diffuse.contents = NeuronArt.softDisc
            material.multiply.contents = colour(tint * (hot ? 0.9 : 0.4))
            return material
        }
        material.shaderModifiers = [.surface: NeuronShaders.halo]
        GraphStyleUniforms.defaults(material)
        set(material, "rpGain", hot ? 1.8 : 1)
        Self.tint(material, "rpTintA", tint)
        let ring: SIMD3<Float> = hot ? SIMD3<Float>(0.75, 0.95, 1.0) : SIMD3<Float>(0, 0, 0)
        Self.tint(material, "rpTintC", ring)
        return material
    }

    private static func arrivalMaterial(support: NeuronSupport) -> SCNMaterial {
        let material: SCNMaterial = additive()
        material.isDoubleSided = true
        guard support.has("arrival") else {
            material.diffuse.contents = NeuronArt.softDisc
            material.multiply.contents = colour(impulseHalo * 0.8)
            return material
        }
        material.shaderModifiers = [.surface: NeuronShaders.arrival]
        GraphStyleUniforms.defaults(material)
        tint(material, "rpTintA", impulseHalo)
        tint(material, "rpTintB", impulse)
        return material
    }

    /// An axon (a tract of three when `bundle`): the impulses' rate and
    /// bursts from the Graphics budget.
    private static func axonMaterial(bundle: Bool, bold: Bool, lively: Bool, budget: GraphicsBudget,
                                     support: NeuronSupport, half: Float) -> SCNMaterial {
        let base: SIMD3<Float> = bundle ? tract : fibre
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
        set(material, "rpBundle", bundle ? 1 : 0)
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
        return NeuronImpulses(glows: parts.map(\.glow), swaying: swaying, rate: fires ? (high ? 0.55 : 0.3) : 0,
                              bursts: high ? 0.18 : 0)
    }

    // MARK: the tissue

    func makeSky() -> SCNNode {
        NeuronTissue.makeSky()
    }
}

// MARK: - Impulses on the render thread

/// Lights each cell's dendrites as impulses reach it - the same arrivals
/// the axon shader flashes (NeuronImpulse) - and moves the membranes' and
/// dendrites' clock. GraphSim calls it once a frame, under its
/// SCNTransaction, after the links are written. Render thread only.
nonisolated final class NeuronImpulses: GraphThemeTicker {
    private let glows: [SCNNode?]
    private let swaying: [SCNMaterial]
    private let rate: Float
    private let bursts: Float
    private var level: [Float]
    private var shown: [Float]
    private var last: Float = -1

    init(glows: [SCNNode?], swaying: [SCNMaterial], rate: Float, bursts: Float) {
        self.glows = glows
        self.swaying = swaying
        self.rate = rate
        self.bursts = bursts
        level = [Float](repeating: 0, count: glows.count)
        shown = [Float](repeating: 0, count: glows.count)
    }

    func tick(time: Float, step: Float, links: [GraphRibbonLink], far: [GraphRibbonLink]) {
        let clock = NSNumber(value: time)
        for material in swaying { material.setValue(clock, forKey: "rpSway") }
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

    private func land(_ list: [GraphRibbonLink], until time: Float) {
        for link in list where link.grow > 0.99 && link.b < level.count {
            let seed: Int = GraphRibbonWriter.themeSeed(link.seed)
            if NeuronImpulse.lands(seed: seed, from: last, to: time, rate: rate, bursts: bursts) {
                level[link.b] = 1
            }
        }
    }
}

// MARK: - The dendrites' shapes

/// One tapered tube of an arbor, in the soma's unit frame: a quadratic
/// curve from `start` through `bend` to `end`, `r0` thick at the start and
/// `r1` at the tip; `s0`...`s1` its share of the dendrite's length (the
/// shader fades and beads by it).
nonisolated struct NeuronBranch: Sendable {
    let start: SIMD3<Float>
    let bend: SIMD3<Float>
    let end: SIMD3<Float>
    let r0: Float
    let r1: Float
    let s0: Float
    let s1: Float
}

@MainActor
enum NeuronArbor {
    /// The branches for a kind of cell (three variants each): a pyramidal
    /// cell's long apical dendrite up +y and a skirt of basal ones; a hub's
    /// many even dendrites; an interneuron's few short ones; a commissural
    /// cell's two long opposite ones; an astrocyte's star of fine processes;
    /// a receptor's one long process ending in a fan; a microglial cell's
    /// thin, much-branched ones. `rich` adds side branches.
    static func branches(_ kind: NeuronCellKind, variant: Int, rich: Bool) -> [NeuronBranch] {
        var random = UniverseRandom(UInt64(kind.rawValue * 31 + variant) &* 0x9E37_79B9 &+ 7)
        var out: [NeuronBranch] = []
        func add(_ dir: SIMD3<Float>, length: Float, thick: Float, sides: Int) {
            let d: SIMD3<Float> = simd_normalize(dir)
            let start: SIMD3<Float> = d * 0.9
            let side: SIMD3<Float> = GraphLinkCurve.perpendicular(to: d)
            let wander: Float = Float(random.signed()) * 0.3 * length
            let bend: SIMD3<Float> = start + d * (length * 0.5) + side * wander
            let lean: SIMD3<Float> = side * (wander * 0.6)
            let end: SIMD3<Float> = start + d * length + lean
            out.append(NeuronBranch(start: start, bend: bend, end: end, r0: thick, r1: thick * 0.12, s0: 0, s1: 1))
            guard rich || sides > 1 else { return }
            for k in 0..<sides {
                let t: Float = 0.4 + 0.25 * Float(k) + 0.1 * Float(random.unit())
                let at: SIMD3<Float> = curve(start, bend, end, min(t, 0.85))
                let twist: Float = Float(random.unit()) * 2 * Float.pi
                let axis: SIMD3<Float> = GraphLinkCurve.rotate(side, about: d, by: twist)
                let out2: SIMD3<Float> = GraphLinkCurve.rotate(d, about: axis, by: 0.7 + 0.3 * Float(random.unit()))
                let reach: Float = length * (0.35 + 0.15 * Float(random.unit()))
                let mid: SIMD3<Float> = at + out2 * (reach * 0.5)
                let tip: SIMD3<Float> = at + out2 * reach
                let r: Float = thick * (1 - t) * 0.75
                out.append(NeuronBranch(start: at, bend: mid, end: tip, r0: r, r1: r * 0.15, s0: t, s1: 1))
            }
        }
        let extra: Int = rich ? 1 : 0
        switch kind {
        case .pyramidal:
            add(SIMD3<Float>(0, 1, 0), length: 3.2, thick: 0.3, sides: 1 + extra)
            for k in 0..<4 {
                let a: Float = Float(k) * Float.pi / 2 + Float(random.unit()) * 0.6
                add(SIMD3<Float>(cos(a), -0.55, sin(a)), length: 1.5 + 0.5 * Float(random.unit()), thick: 0.2,
                    sides: extra)
            }
        case .hub:
            for k in 0..<7 {
                let d: SIMD3<Double> = ThemeLayout.fibonacci(k, 7)
                let jitter = SIMD3<Float>(Float(random.signed()), Float(random.signed()), Float(random.signed()))
                let dir: SIMD3<Float> = GraphUniverse.float3(d) + jitter * 0.25
                add(dir, length: 1.4 + 0.8 * Float(random.unit()), thick: 0.24, sides: extra)
            }
        case .interneuron:
            for k in 0..<5 {
                let d: SIMD3<Float> = GraphUniverse.float3(ThemeLayout.fibonacci(k, 5))
                add(d, length: 1.1 + 0.5 * Float(random.unit()), thick: 0.18, sides: extra)
            }
        case .commissural:
            add(SIMD3<Float>(0, 1, 0.1), length: 2.6, thick: 0.24, sides: extra)
            add(SIMD3<Float>(0, -1, -0.1), length: 2.2, thick: 0.22, sides: extra)
            add(SIMD3<Float>(1, 0, 0.3), length: 1.0, thick: 0.14, sides: 0)
            add(SIMD3<Float>(-1, 0.2, -0.3), length: 0.9, thick: 0.14, sides: 0)
        case .glia:
            for k in 0..<12 {
                let d: SIMD3<Float> = GraphUniverse.float3(ThemeLayout.fibonacci(k, 12))
                add(d, length: 0.9 + 0.5 * Float(random.unit()), thick: 0.12, sides: 0)
            }
        case .receptor:
            add(SIMD3<Float>(0, 1, 0), length: 2.8, thick: 0.22, sides: 0)
            let tip: SIMD3<Float> = out.last?.end ?? SIMD3<Float>(0, 3.7, 0)
            for k in 0..<4 {
                let a: Float = Float(k) * Float.pi / 2
                let dir = SIMD3<Float>(cos(a) * 0.7, 1, sin(a) * 0.7)
                let end: SIMD3<Float> = tip + simd_normalize(dir) * 0.6
                let mid: SIMD3<Float> = (tip + end) * 0.5
                out.append(NeuronBranch(start: tip, bend: mid, end: end, r0: 0.06, r1: 0.03, s0: 0.8, s1: 1))
            }
            add(SIMD3<Float>(0, -1, 0), length: 1.2, thick: 0.16, sides: 0)
        case .microglia:
            for k in 0..<6 {
                let d: SIMD3<Float> = GraphUniverse.float3(ThemeLayout.fibonacci(k, 6))
                add(d, length: 1.4 + 0.6 * Float(random.unit()), thick: 0.1, sides: 1 + extra)
            }
        }
        return out
    }

    static func curve(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let u: Float = 1 - t
        let ab: SIMD3<Float> = a * (u * u) + b * (2 * u * t)
        return ab + c * (t * t)
    }

    /// Every branch as a tube of `sides` round and `segments` along, in one
    /// geometry (texture u: the share along the dendrite, v: round it).
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
                let t: Float = Float(j) / Float(steps)
                let p: SIMD3<Float> = curve(branch.start, branch.bend, branch.end, t)
                let ahead: SIMD3<Float> = curve(branch.start, branch.bend, branch.end, min(t + 0.02, 1))
                let behind: SIMD3<Float> = curve(branch.start, branch.bend, branch.end, max(t - 0.02, 0))
                let along: SIMD3<Float> = GraphLinkCurve.unit(ahead - behind, or: SIMD3<Float>(0, 1, 0))
                let n1: SIMD3<Float> = GraphLinkCurve.perpendicular(to: along)
                let n2: SIMD3<Float> = GraphLinkCurve.cross(along, n1)
                let taper: Float = branch.r0 + (branch.r1 - branch.r0) * t
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

// MARK: - The tissue behind

/// The Neurons' backdrop, in place of the stars: dark tissue lit by soft,
/// blurred extracellular glows (teal, green, a little magenta), with a
/// scatter of out-of-focus cells - pale rings of light, as in a
/// microscope's deep field. Made once, on a sphere of radius 1, shared by
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
        let cells = SCNNode(geometry: Self.blurred)
        cells.renderingOrder = -29
        cells.categoryBitMask = 2
        sky.addChildNode(cells)
        return sky
    }

    /// The glows: (direction, reach in radians, colour, sRGB).
    private static func glows() -> [(SIMD3<Float>, Float, SIMD3<Float>)] {
        var random = UniverseRandom(0x7155)
        let hues: [SIMD3<Float>] = [
            SIMD3<Float>(0.03, 0.10, 0.09), SIMD3<Float>(0.03, 0.09, 0.05), SIMD3<Float>(0.02, 0.05, 0.10),
            SIMD3<Float>(0.07, 0.02, 0.06)
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
                var c = SIMD3<Float>(0.010, 0.026, 0.032)
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

    private static let blurred: SCNGeometry = makeBlurred()

    /// Out-of-focus cells: soft rings on the sky, each a quad facing the
    /// middle, in one geometry.
    private static func makeBlurred() -> SCNGeometry {
        var random = UniverseRandom(0xB0E4)
        var positions: [SCNVector3] = []
        var coords: [CGPoint] = []
        var colours: [Float] = []
        var indices: [Int32] = []
        let tints: [SIMD3<Float>] = [SIMD3<Float>(0.10, 0.30, 0.27), SIMD3<Float>(0.12, 0.28, 0.14),
                                     SIMD3<Float>(0.22, 0.10, 0.22), SIMD3<Float>(0.10, 0.18, 0.32)]
        for k in 0..<44 {
            let d: SIMD3<Float> = GraphUniverse.float3(ThemeLayout.fibonacci(k, 44))
            let jitter = SIMD3<Float>(Float(random.signed()), Float(random.signed()), Float(random.signed()))
            let dir: SIMD3<Float> = simd_normalize(d + jitter * 0.25)
            let size: Float = 0.025 + 0.06 * Float(random.unit())
            let u: SIMD3<Float> = GraphLinkCurve.perpendicular(to: dir)
            let v: SIMD3<Float> = GraphLinkCurve.cross(dir, u)
            let first = Int32(positions.count)
            let corners: [(Float, Float)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            let tint: SIMD3<Float> = linear(tints[k % tints.count] * (0.5 + 0.5 * Float(random.unit())))
            for (x, y) in corners {
                let p: SIMD3<Float> = dir * 0.98 + u * (x * size) + v * (y * size)
                positions.append(SCNVector3(x: p.x, y: p.y, z: p.z))
                coords.append(CGPoint(x: CGFloat((x + 1) / 2), y: CGFloat((y + 1) / 2)))
                colours.append(contentsOf: [tint.x, tint.y, tint.z])
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
        material.diffuse.contents = NeuronArt.blurredCell
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

/// Two small pictures, drawn once: a soft disc (the fallback glows) and an
/// out-of-focus cell (a soft ring round a fainter middle).
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

    static let blurredCell: UIImage = draw { context, size in
        let clear = UIColor(white: 1, alpha: 0).cgColor
        let faint = UIColor(white: 1, alpha: 0.35).cgColor
        let rim = UIColor(white: 1, alpha: 0.9).cgColor
        let colours: [CGColor] = [faint, faint, rim, clear]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray,
                                        locations: [0, 0.55, 0.8, 1]) else { return }
        let middle = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle,
                                   endRadius: size / 2, options: [])
    }

    private static func draw(_ paint: (CGContext, CGFloat) -> Void) -> UIImage {
        let side: CGFloat = 64
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
                                                 ("rpBurst", 0.2), ("rpBundle", 0), ("rpHalf", 0.08)]
                for (key, value) in values { material.setValue(NSNumber(value: value), forKey: key) }
            }
            if ok { passed.insert(name) }
        }
        return NeuronSupport(passed: passed)
    }
}
