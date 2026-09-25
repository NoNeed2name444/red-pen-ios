import SceneKit
import UIKit
import Metal
import simd

// MARK: - The Circuit look
//
// How the Circuit theme (GraphCircuit) is dressed, for the shared theme
// scene (GraphThemeScene): a motherboard in dark green solder mask under
// everything (decorate), each chip's zone its own sub-board in its zone's
// shade, and on them the parts - processors under brushed lids on green
// substrates in their sockets, module chips in black epoxy with tinned
// pins, both with their folder's name silkscreened on top; electrolytic
// cans, copper inductor coils, banded resistors and diodes on their leads,
// LEDs in their zone's colour, pin headers, tiny surface-mount parts, gold
// edge fingers and pads. Links are copper traces lying flat on the board,
// routed square with rounded 45° corners (the board passed to the ribbon
// writer), buses three traces wide; current drifts along them and packets
// run at random times, and the LED (or chip) a packet reaches lights up.
//
// Colours suit the app's dark ground: near-black green board, copper and
// gold, cyan-white current; each processor's zone has its own accent (amber,
// cyan, green, magenta, red) for its LEDs and its name pills' rims.
//
// Nothing is made per part but its nodes: geometry is one shape per kind of
// part, materials one per pattern and colour, shared; only each chip's
// silkscreened name is its own small picture.
//
// The Graphics budget (GraphQuality.current) sets the cost: at Smooth the
// shapes have fewer segments and a chip fewer pins, the shaders their simple
// path (rpDetail 0: no grain, hatching, vias, drifting dots or bursts) and
// fewer packets run. Reduce Motion or a still space: no current moves.

@MainActor
final class GraphCircuitLook: GraphThemeLook {
    let theme: GraphTheme = .circuit
    let lively: Bool
    let bold: Bool
    let budget: GraphicsBudget
    let support: CircuitSupport
    let linkMaterial: SCNMaterial
    let farMaterial: SCNMaterial
    let linkHalfWidth: Float = 0.045
    let farHalfWidth: Float = 0.09
    let hotRing: SCNGeometry
    private(set) var clocked: [SCNMaterial] = []
    let board: GraphLinkBoard?
    /// The board's turn: x across it, y up out of it, z down it.
    let upTurn: simd_quatf
    private var parts: [String: SCNMaterial] = [:]
    private var shapes: [String: SCNGeometry] = [:]
    private var dressed: [CircuitPieceKey: SCNGeometry] = [:]
    private var halos: [String: SCNGeometry] = [:]
    private var glows: [Int: SCNGeometry] = [:]
    private var slotOf: [Int: Int] = [:]
    private var slotsFor: Int = -1

    init(lively: Bool, bold: Bool) {
        self.lively = lively
        self.bold = bold
        let budget: GraphicsBudget = GraphQuality.current
        self.budget = budget
        let support: CircuitSupport = CircuitProbe.support
        self.support = support
        let r: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.right)
        let f: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
        let n: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.normal)
        board = GraphLinkBoard(right: r, forward: f, normal: n)
        let angle: Float = Float.pi / 2 - Float(GraphCircuit.tilt)
        upTurn = simd_quatf(angle: angle, axis: SIMD3<Float>(1, 0, 0))
        linkMaterial = Self.traceMaterial(bus: false, bold: bold, lively: lively, budget: budget, support: support,
                                          width: 0.045)
        farMaterial = Self.traceMaterial(bus: true, bold: bold, lively: lively, budget: budget, support: support,
                                         width: 0.09)
        hotRing = GraphSceneBuilder.plane(Self.glowMaterial(tint: Self.current * 0.5, ring: Self.hot, gain: 0.3,
                                                            support: support))
        if support.has("trace") {
            clocked.append(linkMaterial)
            clocked.append(farMaterial)
        }
    }

    // MARK: colours (sRGB, as on screen)

    static let mask = SIMD3<Float>(0.035, 0.13, 0.085)
    static let copper = SIMD3<Float>(0.98, 0.64, 0.32)
    static let gold = SIMD3<Float>(1.0, 0.78, 0.36)
    static let silk = SIMD3<Float>(0.86, 0.88, 0.82)
    static let tin = SIMD3<Float>(0.78, 0.80, 0.83)
    static let current = SIMD3<Float>(0.62, 0.95, 1.0)
    static let currentGlow = SIMD3<Float>(0.25, 0.55, 1.0)
    static let hot = SIMD3<Float>(0.6, 0.95, 1.0)
    /// Each processor's zone: its sub-board's mask and its accent (its
    /// LEDs, its name pills' rims).
    static let zones: [(SIMD3<Float>, SIMD3<Float>)] = [
        (SIMD3<Float>(0.05, 0.19, 0.12), SIMD3<Float>(1.0, 0.72, 0.22)),
        (SIMD3<Float>(0.03, 0.15, 0.17), SIMD3<Float>(0.30, 0.90, 1.0)),
        (SIMD3<Float>(0.04, 0.09, 0.20), SIMD3<Float>(0.40, 1.0, 0.45)),
        (SIMD3<Float>(0.12, 0.06, 0.17), SIMD3<Float>(1.0, 0.38, 0.82)),
        (SIMD3<Float>(0.07, 0.07, 0.08), SIMD3<Float>(1.0, 0.32, 0.25))
    ]
    /// Loose notes' accent: the edge's gold.
    static let edgeZone = (SIMD3<Float>(0.05, 0.12, 0.09), SIMD3<Float>(1.0, 0.8, 0.4))

    /// A body's zone slot: its processor's place in the plan, 5 round.
    private func slot(_ body: ThemeBody, plan: ThemePlan) -> Int {
        if slotsFor != plan.bodies.count {
            slotOf = [:]
            for (k, r) in plan.regions.enumerated() { slotOf[r] = k % Self.zones.count }
            slotsFor = plan.bodies.count
        }
        if body.region >= 0 { return slotOf[body.region] ?? 0 }
        return -1
    }

    private static func zone(_ slot: Int) -> (SIMD3<Float>, SIMD3<Float>) {
        slot < 0 ? edgeZone : zones[slot % zones.count]
    }

    func tone(region: Int, plan: ThemePlan) -> UIColor? {
        guard region >= 0, region < plan.bodies.count else { return nil }
        let c: SIMD3<Float> = Self.zone(slot(plan.bodies[region], plan: plan)).1
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    // MARK: a part

    func makeBody(_ body: ThemeBody, index: Int, plan: ThemePlan) -> GraphThemeParts {
        let node = SCNNode()
        switch body.kind {
        case .note: node.name = "note:" + body.id.uuidString
        case .folder: node.name = "folder:" + body.id.uuidString
        case .home: node.name = "home"
        }
        let role: CircuitRole = CircuitRole(rawValue: body.role) ?? .resistor
        let zoneSlot: Int = slot(body, plan: plan)
        let size: Float = body.sphere

        // the board's frame (y up out of it), turned along y for a part
        // lying along the board's y, and scaled to the part's size
        let up = SCNNode()
        up.simdOrientation = upTurn
        node.addChildNode(up)
        let orient = SCNNode()
        let vertical: Bool = simd_dot(body.axis, GraphUniverse.float3(GraphCircuit.forward)) > 0.5
        if vertical && role.isOriented {
            orient.simdOrientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(0, 1, 0))
        }
        up.addChildNode(orient)
        let shape = SCNNode()
        shape.simdScale = SIMD3<Float>(size, size, size)
        orient.addChildNode(shape)
        for piece in pieces(role, zone: zoneSlot) { shape.addChildNode(piece) }
        if role.isContainer {
            shape.addChildNode(nameplate(body, role: role))
            if index < plan.patches.count {
                if let zoneBoard = subBoard(plan.patches[index], zone: zoneSlot) { node.addChildNode(zoneBoard) }
            }
        }

        // the halo, on GraphSim's ring pieces
        let holder = SCNNode()
        let facing = SCNBillboardConstraint()
        facing.freeAxes = .all
        holder.constraints = [facing]
        let stretch = SCNNode()
        // only an LED and a chip have a standing glow, and none on Smooth
        // (no haze); a passive part's, at a twentieth of the light, cost a
        // blended quad five times its size and showed nothing
        let glowing: Bool = role == .led || role.isContainer
        let halo: SCNGeometry = glowing && budget.haze ? haloGeometry(role, zone: zoneSlot) : GraphThemeParts.noHalo
        let leaf = SCNNode(geometry: halo)
        let across: Float = size * (role.isContainer ? 4.2 : 5)
        leaf.simdScale = SIMD3<Float>(across, across, 1)
        leaf.renderingOrder = 7
        leaf.categoryBitMask = 2
        stretch.addChildNode(leaf)
        holder.addChildNode(stretch)
        node.addChildNode(holder)
        let disk = SCNNode()
        node.addChildNode(disk)

        var parts = GraphThemeParts(node: node, radius: size * Self.reach(role), ringStretch: stretch,
                                    ringLeaf: leaf, ringGeometry: halo, diskLeaf: disk)
        // a lit LED's light, or a busy chip's, as current arrives
        if role == .led || role.isContainer {
            let light = SCNNode(geometry: glowGeometry(role == .led ? zoneSlot : 99))
            let wide: Float = size * (role == .led ? 7 : 4.5)
            light.simdScale = SIMD3<Float>(wide, wide, 1)
            light.renderingOrder = 8
            light.categoryBitMask = 2
            light.opacity = 0
            light.isHidden = true
            holder.addChildNode(light)
            parts.glow = light
        }
        parts.thinnable = !glowing
        return parts
    }

    /// How far out from its centre a part's traces start (times the links'
    /// trim) and it can be picked, in sizes.
    private static func reach(_ role: CircuitRole) -> Float {
        switch role {
        case .processor, .module, .soc: return 1.0
        case .resistor, .diode: return 1.2
        case .header: return 1.3
        case .capacitor: return 0.8
        case .inductor: return 0.85
        case .led: return 0.75
        case .smd: return 0.9
        case .edgePin: return 1.0
        case .pad: return 0.7
        }
    }

    // MARK: the parts' pieces

    /// The pieces of a part, in its own unit frame (y up from the board).
    private func pieces(_ role: CircuitRole, zone: Int) -> [SCNNode] {
        let high: Bool = budget.tier == .high
        let accent: SIMD3<Float> = Self.zone(zone).1
        switch role {
        case .processor, .soc:
            let socket = piece(box("socket", 2.3, 0.05, 2.3, 0.02), y: 0.025,
                               look: material(6, SIMD3<Float>(0.13, 0.13, 0.14), shine: 0.2))
            let substrate = piece(box("substrate", 1.9, 0.08, 1.9, 0.02), y: 0.09,
                                  look: material(12, SIMD3<Float>(0.10, 0.30, 0.18), b: Self.gold, shine: 0.4))
            let lid = piece(box("lid", 1.4, 0.12, 1.4, 0.05), y: 0.19,
                            look: material(1, SIMD3<Float>(0.72, 0.74, 0.77), shine: 1))
            return [socket, substrate, lid]
        case .module:
            let body = piece(box("ic", 1.7, 0.24, 1.7, 0.03), y: 0.16,
                             look: material(0, SIMD3<Float>(0.075, 0.075, 0.085), shine: 0.35))
            let pins = piece(icPins(high ? 8 : 5), y: 0, look: material(7, Self.tin, shine: 1))
            return [body, pins]
        case .capacitor:
            let can = piece(cylinder("can", 0.8, 1.6, high ? 32 : 16), y: 0.8,
                            look: material(4, SIMD3<Float>(0.10, 0.16, 0.42), b: SIMD3<Float>(0.62, 0.68, 0.78),
                                           c: SIMD3<Float>(0.78, 0.80, 0.83), shine: 0.7))
            return [can]
        case .inductor:
            let coil = piece(torus(high), y: 0.3, look: material(5, SIMD3<Float>(0.86, 0.46, 0.22), shine: 0.9))
            let core = piece(cylinder("core", 0.42, 0.5, high ? 24 : 12), y: 0.25,
                             look: material(6, SIMD3<Float>(0.16, 0.16, 0.17), shine: 0.3))
            return [core, coil]
        case .resistor, .diode:
            let isDiode: Bool = role == .diode
            let bodyLook: SCNMaterial = isDiode
                ? material(3, SIMD3<Float>(0.10, 0.10, 0.11), b: SIMD3<Float>(0.86, 0.87, 0.9), shine: 0.9)
                : material(2, SIMD3<Float>(0.80, 0.68, 0.48), b: Self.gold, shine: 0.5)
            let long: CGFloat = isDiode ? 2.2 : 2.5
            let round: CGFloat = isDiode ? 0.38 : 0.42
            let body = piece(capsule(isDiode ? "diode" : "resistor", round, long, high), y: 0.5, look: bodyLook)
            body.simdOrientation = simd_quatf(angle: -Float.pi / 2, axis: SIMD3<Float>(0, 0, 1))
            let leads = piece(axialLeads(), y: 0, look: material(7, Self.tin, shine: 1))
            return [body, leads]
        case .led:
            let dome = piece(capsule("led", 0.62, 1.9, high), y: 1.0,
                             look: material(9, accent, shine: 1, glow: lively ? 0.45 : 0.35))
            let rim = piece(cylinder("ledRim", 0.72, 0.12, high ? 24 : 12), y: 0.06,
                            look: material(9, accent, shine: 0.6, glow: 0.15))
            return [rim, dome]
        case .header:
            let base = piece(box("header", 4.0, 0.5, 0.9, 0.04), y: 0.25,
                             look: material(6, SIMD3<Float>(0.07, 0.07, 0.08), shine: 0.25))
            let pins = piece(headerPins(), y: 0, look: material(7, Self.gold, shine: 1))
            return [base, pins]
        case .smd:
            let chip = piece(box("smd", 2.0, 0.55, 1.0, 0.03), y: 0.275,
                             look: material(8, SIMD3<Float>(0.14, 0.11, 0.09), b: Self.tin, shine: 0.6))
            return [chip]
        case .edgePin:
            let finger = piece(box("finger", 1.0, 0.04, 2.6, 0.01), y: 0.02, look: material(10, Self.gold, shine: 1))
            return [finger]
        case .pad:
            let pad = piece(cylinder("pad", 0.8, 0.04, high ? 24 : 12), y: 0.02,
                            look: material(11, Self.gold, shine: 1))
            return [pad]
        }
    }

    /// A piece: a shared shape in a shared material (one geometry per
    /// pair, so SceneKit can draw alike pieces together).
    private func piece(_ geometry: SCNGeometry, y: Float, look: SCNMaterial) -> SCNNode {
        let key = CircuitPieceKey(shape: ObjectIdentifier(geometry), look: ObjectIdentifier(look))
        let dressedShape: SCNGeometry
        if let made = dressed[key] {
            dressedShape = made
        } else {
            let copy: SCNGeometry = geometry.copy() as? SCNGeometry ?? geometry
            copy.materials = [look]
            dressed[key] = copy
            dressedShape = copy
        }
        let node = SCNNode(geometry: dressedShape)
        node.simdPosition = SIMD3<Float>(0, y, 0)
        return node
    }

    // MARK: shapes (one each, shared)

    private func box(_ key: String, _ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ round: CGFloat) -> SCNGeometry {
        if let made = shapes[key] { return made }
        let made = SCNBox(width: w, height: h, length: l, chamferRadius: round)
        made.chamferSegmentCount = budget.tier == .high ? 3 : 1
        shapes[key] = made
        return made
    }

    private func cylinder(_ key: String, _ r: CGFloat, _ h: CGFloat, _ sides: Int) -> SCNGeometry {
        if let made = shapes[key] { return made }
        let made = SCNCylinder(radius: r, height: h)
        made.radialSegmentCount = sides
        shapes[key] = made
        return made
    }

    private func capsule(_ key: String, _ r: CGFloat, _ h: CGFloat, _ high: Bool) -> SCNGeometry {
        if let made = shapes[key] { return made }
        let made = SCNCapsule(capRadius: r, height: h)
        made.radialSegmentCount = high ? 24 : 12
        made.capSegmentCount = high ? 8 : 4
        shapes[key] = made
        return made
    }

    private func torus(_ high: Bool) -> SCNGeometry {
        if let made = shapes["torus"] { return made }
        let made = SCNTorus(ringRadius: 0.72, pipeRadius: 0.3)
        made.ringSegmentCount = high ? 48 : 24
        made.pipeSegmentCount = high ? 14 : 8
        shapes["torus"] = made
        return made
    }

    /// A chip's gull-wing pins, `perSide` on each side, as one geometry.
    private func icPins(_ perSide: Int) -> SCNGeometry {
        let key: String = "pins\(perSide)"
        if let made = shapes[key] { return made }
        var list: [(SIMD3<Float>, SIMD3<Float>)] = []
        let pitch: Float = 1.4 / Float(max(perSide, 1))
        for k in 0..<perSide {
            let along: Float = (Float(k) - Float(perSide - 1) * 0.5) * pitch
            let half = SIMD3<Float>(0.15, 0.025, 0.045)
            list.append((SIMD3<Float>(1.0, 0.025, along), half))
            list.append((SIMD3<Float>(-1.0, 0.025, along), half))
            let across = SIMD3<Float>(0.045, 0.025, 0.15)
            list.append((SIMD3<Float>(along, 0.025, 1.0), across))
            list.append((SIMD3<Float>(along, 0.025, -1.0), across))
        }
        let made: SCNGeometry = CircuitMesh.boxes(list)
        shapes[key] = made
        return made
    }

    /// A resistor's or diode's two leads: down into the board at each end,
    /// and the wire through the body.
    private func axialLeads() -> SCNGeometry {
        if let made = shapes["leads"] { return made }
        let list: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3<Float>(-1.5, 0.25, 0), SIMD3<Float>(0.045, 0.25, 0.045)),
            (SIMD3<Float>(1.5, 0.25, 0), SIMD3<Float>(0.045, 0.25, 0.045)),
            (SIMD3<Float>(0, 0.5, 0), SIMD3<Float>(1.54, 0.04, 0.04))
        ]
        let made: SCNGeometry = CircuitMesh.boxes(list)
        shapes["leads"] = made
        return made
    }

    /// A header's four pins, standing up out of its base.
    private func headerPins() -> SCNGeometry {
        if let made = shapes["headerPins"] { return made }
        var list: [(SIMD3<Float>, SIMD3<Float>)] = []
        for k in 0..<4 {
            let x: Float = -1.5 + Float(k)
            list.append((SIMD3<Float>(x, 0.6, 0), SIMD3<Float>(0.08, 0.6, 0.08)))
        }
        let made: SCNGeometry = CircuitMesh.boxes(list)
        shapes["headerPins"] = made
        return made
    }

    // MARK: materials

    /// A part's material, by pattern and colours (one each, shared).
    private func material(_ pattern: Int, _ a: SIMD3<Float>, b: SIMD3<Float> = SIMD3<Float>(0.6, 0.6, 0.6),
                          c: SIMD3<Float> = SIMD3<Float>(0.6, 0.6, 0.6), shine: Float,
                          glow: Float = 0) -> SCNMaterial {
        let key: String = "\(pattern)|\(a)|\(b)|\(c)|\(glow)"
        if let made = parts[key] { return made }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = GraphStyleProbe.blackContents
        guard support.has("part") else {
            let plain: SIMD3<Float> = pattern == 9 ? a * (0.5 + glow) : a * 0.8
            material.diffuse.contents = Self.colour(plain)
            parts[key] = material
            return material
        }
        material.shaderModifiers = [.surface: CircuitShaders.part]
        GraphStyleUniforms.defaults(material)
        Self.set(material, "rpDetail", budget.shaderDetail)
        Self.set(material, "rpPattern", Float(pattern))
        Self.set(material, "rpShine", shine)
        Self.set(material, "rpGlow", glow)
        Self.tint(material, "rpTintA", a)
        Self.tint(material, "rpTintB", b)
        Self.tint(material, "rpTintC", c)
        parts[key] = material
        return material
    }

    /// A trace (a bus of three when `bus`): copper, with current in cyan.
    private static func traceMaterial(bus: Bool, bold: Bool, lively: Bool, budget: GraphicsBudget,
                                      support: CircuitSupport, width: Float) -> SCNMaterial {
        let base: SIMD3<Float> = bus ? gold : copper
        let strength: Float = bold ? 1.3 : 1
        guard support.has("trace") else {
            let plain: SCNMaterial = GraphLook.link(bold: bold, shader: false, lively: lively)
            plain.multiply.contents = colour(base)
            plain.isDoubleSided = true
            return plain
        }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = GraphStyleProbe.blackContents
        // copper over the board, not light on it: blended by the shader's
        // alpha (premultiplied - the current's light rides on top with no
        // alpha of its own); the hair under 1 keeps SceneKit drawing it in
        // its blended pass, after the opaque board
        material.blendMode = .alpha
        material.transparency = 0.999
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        material.shaderModifiers = [.surface: CircuitShaders.trace]
        GraphStyleUniforms.defaults(material)
        set(material, "rpMotion", lively ? 1 : 0)
        set(material, "rpDetail", budget.shaderDetail)
        let high: Bool = budget.tier == .high
        // held still (Reduce Motion, a still space): no packets at all,
        // rather than packets frozen partway along
        set(material, "rpRate", lively ? (high ? 0.6 : 0.35) : 0)
        set(material, "rpBurst", lively && high ? 0.2 : 0)
        set(material, "rpBundle", bus ? 1 : 0)
        set(material, "rpWidth", width)
        tint(material, "rpTintA", base * strength)
        tint(material, "rpTintB", current)
        tint(material, "rpTintC", currentGlow)
        return material
    }

    private func haloGeometry(_ role: CircuitRole, zone: Int) -> SCNGeometry {
        let lit: Bool = role == .led
        let key: String = lit ? "led\(zone)" : (role.isContainer ? "chip\(zone)" : "part")
        if let made = halos[key] { return made }
        let accent: SIMD3<Float> = Self.zone(zone).1
        let gain: Float = lit ? 0.55 : (role.isContainer ? 0.12 : 0.05)
        let tint: SIMD3<Float> = lit || role.isContainer ? accent : Self.current
        let made: SCNGeometry = GraphSceneBuilder.plane(Self.glowMaterial(tint: tint, ring: SIMD3<Float>(0, 0, 0),
                                                                          gain: gain, support: support))
        halos[key] = made
        return made
    }

    /// The light of current arriving: an LED's in its zone's colour (`zone`
    /// 0...5), a chip's cyan (99).
    private func glowGeometry(_ zone: Int) -> SCNGeometry {
        if let made = glows[zone] { return made }
        let tint: SIMD3<Float> = zone == 99 ? Self.current : Self.zone(zone).1
        let gain: Float = zone == 99 ? 0.7 : 1.6
        let made: SCNGeometry = GraphSceneBuilder.plane(Self.glowMaterial(tint: tint, ring: SIMD3<Float>(0, 0, 0),
                                                                          gain: gain, support: support))
        glows[zone] = made
        return made
    }

    private static func glowMaterial(tint: SIMD3<Float>, ring: SIMD3<Float>, gain: Float,
                                     support: CircuitSupport) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = GraphStyleProbe.blackContents
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        guard support.has("glow") else {
            material.diffuse.contents = NeuronArt.softDisc
            material.multiply.contents = colour(tint * min(gain, 1) + ring)
            return material
        }
        material.shaderModifiers = [.surface: CircuitShaders.glow]
        GraphStyleUniforms.defaults(material)
        set(material, "rpGain", gain)
        Self.tint(material, "rpTintA", tint)
        Self.tint(material, "rpTintC", ring)
        return material
    }

    private func boardMaterial(zone: Bool, mask: SIMD3<Float>, size: SIMD3<Float>) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        guard support.has("board") else {
            material.diffuse.contents = Self.colour(mask)
            return material
        }
        material.diffuse.contents = GraphStyleProbe.blackContents
        material.shaderModifiers = [.surface: CircuitShaders.board]
        GraphStyleUniforms.defaults(material)
        Self.set(material, "rpDetail", budget.shaderDetail)
        Self.set(material, "rpZone", zone ? 1 : 0)
        material.setValue(NSValue(scnVector3: SCNVector3(x: size.x, y: size.y, z: size.z)), forKey: "rpSize")
        Self.tint(material, "rpTintA", mask)
        Self.tint(material, "rpTintB", Self.copper)
        Self.tint(material, "rpTintC", Self.silk)
        return material
    }

    private static func set(_ material: SCNMaterial, _ key: String, _ value: Float) {
        material.setValue(NSNumber(value: value), forKey: key)
    }

    private static func tint(_ material: SCNMaterial, _ key: String, _ c: SIMD3<Float>) {
        material.setValue(NSValue(scnVector3: SCNVector3(x: c.x, y: c.y, z: c.z)), forKey: key)
    }

    static func colour(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(min(c.x, 1)), green: CGFloat(min(c.y, 1)), blue: CGFloat(min(c.z, 1)), alpha: 1)
    }

    // MARK: boards

    /// A chip's own sub-board: `patch` (its centre from the chip, on the
    /// board, and its half size) as a thin slab just above the motherboard,
    /// a child of the chip so it moves with it.
    private func subBoard(_ patch: SIMD4<Float>, zone: Int) -> SCNNode? {
        guard patch.z > 0.001, patch.w > 0.001 else { return nil }
        let size = SIMD3<Float>(patch.z, 0.003, patch.w)
        let slab = SCNBox(width: CGFloat(patch.z * 2), height: 0.006, length: CGFloat(patch.w * 2), chamferRadius: 0)
        slab.materials = [boardMaterial(zone: true, mask: Self.zone(zone).0, size: size)]
        let node = SCNNode(geometry: slab)
        let r: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.right)
        let f: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
        let n: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.normal)
        node.simdPosition = r * patch.x + f * patch.y + n * 0.003
        node.simdOrientation = upTurn
        node.categoryBitMask = 2
        node.renderingOrder = -2
        return node
    }

    /// The motherboard, under everything.
    func decorate(world: SCNNode, plan: ThemePlan) {
        guard let g = plan.ground else { return }
        let half = SIMD3<Float>((g.z - g.x) * 0.5, 0.04, (g.w - g.y) * 0.5)
        let slab = SCNBox(width: CGFloat(half.x * 2), height: 0.08, length: CGFloat(half.z * 2), chamferRadius: 0.02)
        slab.materials = [boardMaterial(zone: false, mask: Self.mask, size: half)]
        let node = SCNNode(geometry: slab)
        node.name = "motherboard"
        let r: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.right)
        let f: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
        let n: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.normal)
        let cx: Float = (g.x + g.z) * 0.5
        let cy: Float = (g.y + g.w) * 0.5
        node.simdPosition = r * cx + f * cy - n * 0.04
        node.simdOrientation = upTurn
        node.categoryBitMask = 2
        node.renderingOrder = -3
        world.addChildNode(node)
    }

    /// A chip's name, silkscreened (a processor's on its lid, a module's
    /// on its epoxy): its folder's name and a part number.
    private func nameplate(_ body: ThemeBody, role: CircuitRole) -> SCNNode {
        let lid: Bool = role != .module
        let wide: CGFloat = lid ? 1.2 : 1.4
        let plane = SCNPlane(width: wide, height: wide * 0.5)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = CircuitArt.nameplate(body.title, number: body.seed, dark: lid)
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.simdPosition = SIMD3<Float>(0, lid ? 0.252 : 0.282, 0)
        node.simdOrientation = simd_quatf(angle: -Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        node.categoryBitMask = 2
        node.renderingOrder = 3
        return node
    }

    // MARK: each frame

    /// Lights each LED (and chip) as a packet reaches it - the same
    /// arrivals the trace shader flashes, worked out by the Neurons'
    /// NeuronImpulses on the same timing.
    func ticker(parts: [GraphThemeParts], plan: ThemePlan) -> GraphThemeTicker? {
        guard lively, support.has("trace") else { return nil }
        let high: Bool = budget.tier == .high
        return NeuronImpulses(glows: parts.map(\.glow), swaying: [], rate: high ? 0.6 : 0.35,
                              bursts: high ? 0.2 : 0)
    }

    // MARK: behind the board

    func makeSky() -> SCNNode {
        CircuitRoom.makeSky()
    }
}

/// A shape and a material, as a dictionary key.
struct CircuitPieceKey: Hashable {
    let shape: ObjectIdentifier
    let look: ObjectIdentifier
}

// MARK: - Boxes in one geometry

/// Many small axis-aligned boxes (pins, leads) as one geometry: one draw.
@MainActor
enum CircuitMesh {
    /// Each (centre, half size).
    static func boxes(_ list: [(SIMD3<Float>, SIMD3<Float>)]) -> SCNGeometry {
        var points: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        // each face: its normal and two edges, turning so it faces out
        let x = SIMD3<Float>(1, 0, 0)
        let y = SIMD3<Float>(0, 1, 0)
        let z = SIMD3<Float>(0, 0, 1)
        var faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        faces.append((x, y, z))
        faces.append((-x, z, y))
        faces.append((y, z, x))
        faces.append((-y, x, z))
        faces.append((z, x, y))
        faces.append((-z, y, x))
        for (centre, half) in list {
            for (n, u, v) in faces {
                let first = Int32(points.count)
                let middle: SIMD3<Float> = centre + n * half
                let du: SIMD3<Float> = u * half
                let dv: SIMD3<Float> = v * half
                let corners: [SIMD3<Float>] = [middle - du - dv, middle + du - dv, middle + du + dv, middle - du + dv]
                for c in corners {
                    points.append(SCNVector3(x: c.x, y: c.y, z: c.z))
                    normals.append(SCNVector3(x: n.x, y: n.y, z: n.z))
                }
                indices.append(contentsOf: [first, first + 1, first + 2, first, first + 2, first + 3])
            }
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals)],
                           elements: [element])
    }
}

// MARK: - Behind the board

/// The Circuit's backdrop, in place of the stars: a dark workshop - near
/// black, a little warm light from the lamp up to the left and a cool
/// glow from below. Made once, on a sphere of radius 1, shared by every
/// scene and scaled by the builder; GraphSim keeps it round the camera.
@MainActor
enum CircuitRoom {
    static func makeSky() -> SCNNode {
        let sky = SCNNode()
        sky.name = "sky"
        sky.categoryBitMask = 2
        let dome = SCNNode(geometry: Self.dome)
        dome.renderingOrder = -30
        dome.categoryBitMask = 2
        sky.addChildNode(dome)
        return sky
    }

    private static let dome: SCNGeometry = makeDome()

    private static func makeDome() -> SCNGeometry {
        let columns: Int = 48
        let rows: Int = 24
        let lamp: SIMD3<Float> = simd_normalize(SIMD3<Float>(-0.5, 0.7, 0.5))
        let under: SIMD3<Float> = simd_normalize(SIMD3<Float>(0.2, -0.8, 0.3))
        var positions: [SCNVector3] = []
        var colours: [Float] = []
        for row in 0...rows {
            let lat: Float = Float.pi * (Float(row) / Float(rows) - 0.5)
            for column in 0...columns {
                let lon: Float = 2 * Float.pi * Float(column) / Float(columns)
                let flat: Float = cos(lat)
                let dir = SIMD3<Float>(flat * cos(lon), sin(lat), flat * sin(lon))
                positions.append(SCNVector3(x: dir.x, y: dir.y, z: dir.z))
                var c = SIMD3<Float>(0.012, 0.018, 0.02)
                let warm: Float = max(simd_dot(dir, lamp), 0)
                let cool: Float = max(simd_dot(dir, under), 0)
                c += SIMD3<Float>(0.07, 0.05, 0.03) * pow(warm, 3)
                c += SIMD3<Float>(0.01, 0.05, 0.05) * pow(cool, 2)
                let lin = SIMD3<Float>(pow(c.x, 2.2), pow(c.y, 2.2), pow(c.z, 2.2))
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
        let data: Data = colours.withUnsafeBufferPointer { Data(buffer: $0) }
        let colourSource = SCNGeometrySource(data: data, semantic: .color, vectorCount: positions.count,
                                             usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4,
                                             dataOffset: 0, dataStride: 12)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), colourSource],
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
}

/// A chip's silkscreened name: its folder's name in capitals and a part
/// number, in pale ink (laser-etched grey on a processor's metal lid).
@MainActor
enum CircuitArt {
    static func nameplate(_ title: String, number: UInt64, dark: Bool) -> UIImage {
        let size = CGSize(width: 256, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let ink: UIColor = dark ? UIColor(white: 0.18, alpha: 0.85) : UIColor(white: 0.9, alpha: 0.9)
        let name: String = String(title.uppercased().prefix(12))
        let code: String = "RP" + String(1000 + Int(number % 9000)) + "-" + String(Int((number >> 16) % 90) + 10)
        return renderer.image { _ in
            let big = UIFont.monospacedSystemFont(ofSize: name.count > 8 ? 26 : 32, weight: .bold)
            let small = UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)
            let top: [NSAttributedString.Key: Any] = [.font: big, .foregroundColor: ink]
            let bottom: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: ink]
            let first = NSAttributedString(string: name, attributes: top)
            let second = NSAttributedString(string: code, attributes: bottom)
            let a: CGSize = first.size()
            let b: CGSize = second.size()
            first.draw(at: CGPoint(x: (size.width - a.width) / 2, y: 30))
            second.draw(at: CGPoint(x: (size.width - b.width) / 2, y: 36 + a.height))
        }
    }
}

// MARK: - Checking the shaders work

/// Which Circuit shaders compiled and drew on this device; a piece whose
/// shader failed is drawn plainly instead (see GraphCircuitLook).
nonisolated struct CircuitSupport: Sendable {
    let passed: Set<String>

    func has(_ name: String) -> Bool { passed.contains(name) }
}

/// Tries each Circuit shader once, off the main thread (GraphThemes.prepare,
/// before the first build), in GraphStyleProbe's tiny offscreen render: the
/// boards and parts on a box, the trace and glow on a plane.
nonisolated enum CircuitProbe {
    static let support: CircuitSupport = run()

    private static func run() -> CircuitSupport {
        guard let device = MTLCreateSystemDefaultDevice() else { return CircuitSupport(passed: []) }
        let tries: [(String, String, Bool)] = [
            ("board", CircuitShaders.board, true),
            ("part", CircuitShaders.part, true),
            ("trace", CircuitShaders.trace, false),
            ("glow", CircuitShaders.glow, false)
        ]
        var passed = Set<String>()
        for (name, source, solid) in tries {
            let shape: SCNGeometry = solid ? SCNBox(width: 2, height: 2, length: 2, chamferRadius: 0)
                : SCNPlane(width: 4, height: 4)
            let ok: Bool = GraphStyleProbe.renders([.surface: source], on: shape, device: device) { material in
                let values: [(String, Float)] = [("rpMotion", 1), ("rpZone", 0), ("rpPattern", 0), ("rpShine", 1),
                                                 ("rpGlow", 0), ("rpGain", 1), ("rpRate", 0.5), ("rpBurst", 0.2),
                                                 ("rpBundle", 0), ("rpWidth", 0.05)]
                for (key, value) in values { material.setValue(NSNumber(value: value), forKey: key) }
                let size = SCNVector3(x: 1, y: 1, z: 1)
                material.setValue(NSValue(scnVector3: size), forKey: "rpSize")
            }
            if ok { passed.insert(name) }
        }
        return CircuitSupport(passed: passed)
    }
}
