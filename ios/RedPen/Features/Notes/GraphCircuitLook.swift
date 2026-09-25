import SceneKit
import UIKit
import Metal
import simd

// MARK: - The Circuit look
//
// How the Circuit theme (GraphCircuit) is dressed, for the shared theme
// scene (GraphThemeScene): calm, readable boards on a dark bench, with few
// kinds of part.
//
// - each collection's board: plain dark green solder mask with a soft
//   vignette and a thin outline, its copper power rail along the top and
//   ground rail along the bottom (a child of its chip, so dragging the chip
//   moves the whole circuit); a sub-folder's sub-board a shade lighter;
// - chips in the style of modern system-on-chip packages (evoking, never
//   copying): a rounded square package, its near-black, lightly brushed
//   anodised lid with a soft sheen, a thin bright bevel and an etched
//   outline inset, a faint die layout showing under it (performance and
//   efficiency cores, a GPU grid, a neural block, cache) - more blocks the
//   more the folder holds - its folder's name printed on it in the
//   system font with the app's own model tag ("S-12 Pro"); at High a
//   subtle ring of tiny passives round the controller;
// - capacitors (pages): dark cans with a pale stripe and aluminium tops;
// - LEDs (ideas): amber domes, lit when the idea has links, dim when not;
// - gold pads (loose notes) on the board's edge, and gold edge connectors
//   where a link leaves for another board;
// - traces: one copper trace per link, square with rounded 45° corners
//   (GraphLinkRoute), a thin gold bus between boards; now and then a cyan
//   packet runs down from the power rail, and the LED it reaches lights.
//
// Colours: restrained copper, green and white, with one accent - cyan
// current, amber LEDs.
//
// The glows (an LED's light, a busy chip's, the chosen part's ring) are
// camera-facing squares: they stand at the part's top and are lifted
// towards the camera by a third of their size, so the board never cuts
// off their lower half while nearer parts still hide them.
//
// The Graphics budget (GraphQuality.current) sets the cost: at Smooth the
// shapes have fewer segments, no passives ring or rail labels, the shaders
// their simple path (rpDetail 0) and fewer packets run. Reduce Motion or a
// still space: no current moves.

@MainActor
final class GraphCircuitLook: GraphThemeLook {
    let theme: GraphTheme = .circuit
    let lively: Bool
    let bold: Bool
    let budget: GraphicsBudget
    let support: CircuitSupport
    let linkMaterial: SCNMaterial
    let farMaterial: SCNMaterial
    let linkHalfWidth: Float = 0.032
    let farHalfWidth: Float = 0.022
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
    private var silks: [String: SCNMaterial] = [:]
    /// Packets per slot: calm - now and then, not all the time.
    private var packetRate: Float {
        guard lively else { return 0 }
        return budget.tier == .high ? 0.28 : 0.18
    }

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
        let high: Bool = budget.tier == .high
        let rate: Float = lively ? (high ? 0.28 : 0.18) : 0
        linkMaterial = Self.traceMaterial(bus: false, bold: bold, lively: lively, budget: budget, support: support,
                                          width: 0.032, rate: rate)
        farMaterial = Self.traceMaterial(bus: true, bold: bold, lively: lively, budget: budget, support: support,
                                         width: 0.022, rate: rate)
        hotRing = GraphSceneBuilder.plane(Self.glowMaterial(tint: Self.current * 0.5, ring: Self.hot, gain: 0.3,
                                                            support: support))
        if support.has("trace") {
            clocked.append(linkMaterial)
            clocked.append(farMaterial)
        }
    }

    // MARK: colours (sRGB, as on screen)

    static let mask = SIMD3<Float>(0.035, 0.13, 0.085)
    static let subMask = SIMD3<Float>(0.05, 0.17, 0.11)
    static let copper = SIMD3<Float>(0.92, 0.60, 0.32)
    static let gold = SIMD3<Float>(1.0, 0.78, 0.36)
    static let silk = SIMD3<Float>(0.86, 0.88, 0.84)
    static let tin = SIMD3<Float>(0.78, 0.80, 0.83)
    static let current = SIMD3<Float>(0.55, 0.95, 1.0)
    static let currentGlow = SIMD3<Float>(0.25, 0.6, 1.0)
    static let hot = SIMD3<Float>(0.6, 0.95, 1.0)
    static let amber = SIMD3<Float>(1.0, 0.70, 0.22)
    static let lid = SIMD3<Float>(0.055, 0.058, 0.066)
    static let substrate = SIMD3<Float>(0.05, 0.10, 0.075)

    func tone(region: Int, plan: ThemePlan) -> UIColor? {
        // one restrained rim for every board's name pills: copper
        Self.colour(Self.copper)
    }

    // MARK: a part

    func makeBody(_ body: ThemeBody, index: Int, plan: ThemePlan) -> GraphThemeParts {
        let node = SCNNode()
        switch body.kind {
        case .note: node.name = "note:" + body.id.uuidString
        case .folder: node.name = "folder:" + body.id.uuidString
        case .home: node.name = "home"
        case .fixture: node.name = "fixture"
        }
        let role: CircuitRole = CircuitRole(rawValue: body.role) ?? .led
        let size: Float = body.sphere

        // the board's frame (y up out of it), scaled to the part's size
        let up = SCNNode()
        up.simdOrientation = upTurn
        node.addChildNode(up)
        let shape = SCNNode()
        shape.simdScale = SIMD3<Float>(size, size, size)
        up.addChildNode(shape)
        for piece in pieces(role, body: body) { shape.addChildNode(piece) }
        if role.isContainer {
            shape.addChildNode(nameplate(body, role: role))
            if index < plan.patches.count, let slab = boardSlab(plan.patches[index], sub: role == .module) {
                node.addChildNode(slab)
            }
            for bar in plan.bars where bar.owner == index {
                node.addChildNode(rail(bar))
            }
            if role != .module && budget.tier == .high {
                for bar in plan.bars where bar.owner == index && (bar.kind == 0 || bar.y == lowestRail(plan, index)) {
                    if let label = railLabel(bar) { node.addChildNode(label) }
                }
            }
        }

        // the halo, on GraphSim's ring pieces: at the part's top, lifted
        // towards the camera (so the board never cuts off its lower half)
        let top: Float = size * Self.height(role)
        let holder = SCNNode()
        holder.simdPosition = GraphUniverse.float3(GraphCircuit.normal) * top
        let facing = SCNBillboardConstraint()
        facing.freeAxes = .all
        holder.constraints = [facing]
        let glowing: Bool = role == .led || role.isContainer
        let across: Float = size * (role.isContainer ? 4.2 : 5)
        let lift = SCNNode()
        lift.simdPosition = SIMD3<Float>(0, 0, across * 0.35)
        holder.addChildNode(lift)
        let stretch = SCNNode()
        let lit: Bool = body.links > 0
        let standing: Bool = glowing && budget.haze && (role != .led || lit)
        let halo: SCNGeometry = standing ? haloGeometry(role) : GraphThemeParts.noHalo
        let leaf = SCNNode(geometry: halo)
        leaf.simdScale = SIMD3<Float>(across, across, 1)
        leaf.renderingOrder = 7
        leaf.categoryBitMask = 2
        stretch.addChildNode(leaf)
        lift.addChildNode(stretch)
        node.addChildNode(holder)
        let disk = SCNNode()
        node.addChildNode(disk)

        var parts = GraphThemeParts(node: node, radius: size * Self.reach(role), ringStretch: stretch,
                                    ringLeaf: leaf, ringGeometry: halo, diskLeaf: disk)
        // an LED's light, or a busy chip's, as current arrives
        if role == .led || role.isContainer {
            let light = SCNNode(geometry: glowGeometry(role == .led ? 0 : 99))
            let wide: Float = size * (role == .led ? 7 : 4.5)
            light.simdScale = SIMD3<Float>(wide, wide, 1)
            light.renderingOrder = 8
            light.categoryBitMask = 2
            light.opacity = 0
            light.isHidden = true
            lift.addChildNode(light)
            parts.glow = light
        }
        if body.kind == .fixture {
            node.categoryBitMask = 2
            shape.categoryBitMask = 2
        }
        parts.thinnable = !glowing
        return parts
    }

    /// The lowest ground rail a board carries (its bottom edge's).
    private func lowestRail(_ plan: ThemePlan, _ owner: Int) -> Float {
        var y: Float = Float.greatestFiniteMagnitude
        for bar in plan.bars where bar.owner == owner && bar.kind == 1 { y = min(y, bar.y) }
        return y
    }

    /// How far out from its centre a part's traces start (times the links'
    /// trim) and it can be picked, in sizes.
    private static func reach(_ role: CircuitRole) -> Float {
        switch role {
        case .processor, .module, .soc: return 1.0
        case .capacitor: return 0.8
        case .led: return 0.75
        case .pad: return 0.7
        case .vcc, .ground, .bus: return 0.4
        case .connector: return 0.8
        }
    }

    /// A part's top, in sizes above the board (where its glow stands).
    private static func height(_ role: CircuitRole) -> Float {
        switch role {
        case .processor, .soc, .module: return 0.2
        case .capacitor: return 1.6
        case .led: return 1.7
        default: return 0.05
        }
    }

    // MARK: the parts' pieces

    /// The pieces of a part, in its own unit frame (y up from the board).
    private func pieces(_ role: CircuitRole, body: ThemeBody) -> [SCNNode] {
        let high: Bool = budget.tier == .high
        switch role {
        case .processor, .soc, .module:
            let small: Bool = role == .module
            let blocks: Float = GraphUniverse.clamp(log2(1 + Double(body.count)) / 6, 0, 1).float
            let base = piece(box("package", 1.9, 0.07, 1.9, 0.14), y: 0.035,
                             look: material(6, Self.substrate, shine: 0.25))
            let lidShape: SCNGeometry = box(small ? "lidSmall" : "lid", small ? 1.55 : 1.6, 0.12,
                                            small ? 1.55 : 1.6, 0.16)
            let cover = piece(lidShape, y: 0.13,
                              look: material(13, Self.lid, b: Self.silk, c: SIMD3<Float>(0.35, 0.42, 0.6),
                                             shine: 0.9, glow: small ? blocks * 0.5 : blocks))
            var out: [SCNNode] = [base, cover]
            if !small && high {
                out.append(piece(passives(), y: 0, look: material(8, SIMD3<Float>(0.32, 0.26, 0.2), b: Self.tin,
                                                                  shine: 0.5)))
            }
            return out
        case .capacitor:
            let can = piece(cylinder("can", 0.8, 1.6, high ? 32 : 16), y: 0.8,
                            look: material(4, SIMD3<Float>(0.10, 0.12, 0.13), b: SIMD3<Float>(0.80, 0.82, 0.80),
                                           c: SIMD3<Float>(0.74, 0.76, 0.79), shine: 0.7))
            return [can]
        case .led:
            let lit: Bool = body.links > 0
            let glow: Float = lit ? (lively ? 0.45 : 0.35) : 0.05
            let dome = piece(capsule("led", 0.62, 1.9, high), y: 1.0,
                             look: material(9, Self.amber, shine: 1, glow: glow))
            let rim = piece(cylinder("ledRim", 0.72, 0.12, high ? 24 : 12), y: 0.06,
                            look: material(9, Self.amber, shine: 0.6, glow: lit ? 0.15 : 0.02))
            return [rim, dome]
        case .pad:
            let pad = piece(cylinder("pad", 0.9, 0.05, high ? 24 : 12), y: 0.025,
                            look: material(11, Self.gold, shine: 1))
            return [pad]
        case .connector:
            let finger = piece(box("finger", 1.2, 0.05, 2.2, 0.02), y: 0.025, look: material(10, Self.gold, shine: 1))
            return [finger]
        case .vcc, .ground, .bus:
            let via = piece(cylinder("via", 0.9, 0.05, 12), y: 0.025, look: material(7, Self.tin, shine: 0.8))
            return [via]
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
        made.chamferSegmentCount = budget.tier == .high ? 4 : 2
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

    /// A subtle ring of tiny passives round a controller's package, as one
    /// geometry: small two-tone chips along each side.
    private func passives() -> SCNGeometry {
        if let made = shapes["passives"] { return made }
        var list: [(SIMD3<Float>, SIMD3<Float>)] = []
        let half = SIMD3<Float>(0.05, 0.025, 0.025)
        for k in 0..<7 {
            let along: Float = -0.72 + Float(k) * 0.24
            list.append((SIMD3<Float>(along, 0.095, 1.07), half))
            list.append((SIMD3<Float>(along, 0.095, -1.07), half))
            let turned = SIMD3<Float>(0.025, 0.025, 0.05)
            list.append((SIMD3<Float>(1.07, 0.095, along), turned))
            list.append((SIMD3<Float>(-1.07, 0.095, along), turned))
        }
        let made: SCNGeometry = CircuitMesh.boxes(list)
        shapes["passives"] = made
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

    /// A trace: copper, with current in cyan; `bus` the thin gold bus
    /// between boards.
    private static func traceMaterial(bus: Bool, bold: Bool, lively: Bool, budget: GraphicsBudget,
                                      support: CircuitSupport, width: Float, rate: Float) -> SCNMaterial {
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
        // held still (Reduce Motion, a still space): no packets at all,
        // rather than packets frozen partway along
        set(material, "rpRate", rate)
        set(material, "rpBurst", 0)
        set(material, "rpBundle", 0)
        set(material, "rpWidth", width)
        tint(material, "rpTintA", base * strength)
        tint(material, "rpTintB", current)
        tint(material, "rpTintC", currentGlow)
        return material
    }

    private func haloGeometry(_ role: CircuitRole) -> SCNGeometry {
        let lit: Bool = role == .led
        let key: String = lit ? "led" : "chip"
        if let made = halos[key] { return made }
        let gain: Float = lit ? 0.5 : 0.1
        let tint: SIMD3<Float> = lit ? Self.amber : Self.current
        let made: SCNGeometry = GraphSceneBuilder.plane(Self.glowMaterial(tint: tint, ring: SIMD3<Float>(0, 0, 0),
                                                                          gain: gain, support: support))
        halos[key] = made
        return made
    }

    /// The light of current arriving: an LED's amber (0), a chip's cyan (99).
    private func glowGeometry(_ which: Int) -> SCNGeometry {
        if let made = glows[which] { return made }
        let tint: SIMD3<Float> = which == 99 ? Self.current : Self.amber
        let gain: Float = which == 99 ? 0.6 : 1.5
        let made: SCNGeometry = GraphSceneBuilder.plane(Self.glowMaterial(tint: tint, ring: SIMD3<Float>(0, 0, 0),
                                                                          gain: gain, support: support))
        glows[which] = made
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

    private func boardMaterial(sub: Bool, size: SIMD3<Float>) -> SCNMaterial {
        let mask: SIMD3<Float> = sub ? Self.subMask : Self.mask
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
        Self.set(material, "rpZone", sub ? 1 : 0)
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

    // MARK: boards and rails

    /// A board (a controller's `patch`: its centre from the chip, on the
    /// bench, and its half size) or a sub-board (a sub-folder chip's), as a
    /// slab under the parts, a child of the chip so it moves with it.
    private func boardSlab(_ patch: SIMD4<Float>, sub: Bool) -> SCNNode? {
        guard patch.z > 0.001, patch.w > 0.001 else { return nil }
        let thick: Float = sub ? 0.006 : 0.08
        let size = SIMD3<Float>(patch.z, thick * 0.5, patch.w)
        let slab = SCNBox(width: CGFloat(patch.z * 2), height: CGFloat(thick), length: CGFloat(patch.w * 2),
                          chamferRadius: sub ? 0 : 0.03)
        slab.materials = [boardMaterial(sub: sub, size: size)]
        let node = SCNNode(geometry: slab)
        let r: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.right)
        let f: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
        let n: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.normal)
        let lift: Float = sub ? 0.003 : -thick * 0.5
        node.simdPosition = r * patch.x + f * patch.y + n * lift
        node.simdOrientation = upTurn
        node.categoryBitMask = 2
        node.renderingOrder = sub ? -2 : -3
        return node
    }

    /// A power or ground rail: a flat copper bar on the board.
    private func rail(_ bar: ThemeBar) -> SCNNode {
        let wide: CGFloat = CGFloat(bar.half * 2)
        let across: CGFloat = bar.kind == 0 ? 0.05 : 0.04
        let shape = SCNBox(width: wide, height: 0.008, length: across, chamferRadius: 0)
        shape.materials = [material(7, bar.kind == 0 ? Self.copper : Self.copper * 0.85, shine: 0.7)]
        let node = SCNNode(geometry: shape)
        let r: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.right)
        let f: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
        let n: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.normal)
        node.simdPosition = r * bar.x + f * bar.y + n * 0.006
        node.simdOrientation = upTurn
        node.categoryBitMask = 2
        node.renderingOrder = -1
        return node
    }

    /// "VCC" or "GND", silkscreened at a rail's left end.
    private func railLabel(_ bar: ThemeBar) -> SCNNode? {
        let text: String = bar.kind == 0 ? "VCC" : "GND"
        let look: SCNMaterial
        if let made = silks[text] {
            look = made
        } else {
            let made = SCNMaterial()
            made.lightingModel = .constant
            made.diffuse.contents = CircuitArt.silk(text)
            made.blendMode = .alpha
            made.writesToDepthBuffer = false
            made.readsFromDepthBuffer = true
            silks[text] = made
            look = made
        }
        let plane = SCNPlane(width: 0.16, height: 0.06)
        plane.materials = [look]
        let node = SCNNode(geometry: plane)
        let r: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.right)
        let f: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
        let n: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.normal)
        let x: Float = bar.x - bar.half + 0.1
        let y: Float = bar.y + (bar.kind == 0 ? -0.07 : 0.07)
        node.simdPosition = r * x + f * y + n * 0.004
        // lying on the board, reading along x
        node.simdOrientation = upTurn * simd_quatf(angle: -Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        node.categoryBitMask = 2
        node.renderingOrder = -1
        return node
    }

    /// A chip's name, printed on its lid: its folder's name and its model
    /// tag (GraphCircuit.modelTag).
    private func nameplate(_ body: ThemeBody, role: CircuitRole) -> SCNNode {
        let wide: CGFloat = role == .module ? 1.25 : 1.3
        let plane = SCNPlane(width: wide, height: wide * 0.5)
        let material = SCNMaterial()
        material.lightingModel = .constant
        let tag: String = GraphCircuit.modelTag(count: body.count, depth: max(body.depth, 0))
        material.diffuse.contents = CircuitArt.nameplate(body.title, tag: tag)
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.simdPosition = SIMD3<Float>(0, 0.192, 0.1)
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
        return NeuronImpulses(glows: parts.map(\.glow), swaying: [], rate: packetRate, bursts: 0)
    }

    // MARK: behind the boards

    func makeSky() -> SCNNode {
        CircuitRoom.makeSky()
    }
}

private extension Double {
    var float: Float { Float(self) }
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

/// A chip's printed name and the rails' silkscreen, drawn once each.
@MainActor
enum CircuitArt {
    /// Its folder's name in the system font, and under it the app's own
    /// model tag, in soft white on the chip's dark lid.
    static func nameplate(_ title: String, tag: String) -> UIImage {
        let size = CGSize(width: 256, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let ink = UIColor(white: 0.93, alpha: 0.92)
        let soft = UIColor(white: 0.72, alpha: 0.85)
        let name: String = String(title.prefix(14))
        return renderer.image { _ in
            let big = UIFont.systemFont(ofSize: name.count > 9 ? 25 : 31, weight: .semibold)
            let small = UIFont.systemFont(ofSize: 19, weight: .medium)
            let top: [NSAttributedString.Key: Any] = [.font: big, .foregroundColor: ink]
            let bottom: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: soft]
            let first = NSAttributedString(string: name, attributes: top)
            let second = NSAttributedString(string: tag, attributes: bottom)
            let a: CGSize = first.size()
            let b: CGSize = second.size()
            first.draw(at: CGPoint(x: (size.width - a.width) / 2, y: 30))
            second.draw(at: CGPoint(x: (size.width - b.width) / 2, y: 38 + a.height))
        }
    }

    /// A rail's silkscreen ("VCC", "GND") in pale ink.
    static func silk(_ text: String) -> UIImage {
        let size = CGSize(width: 128, height: 48)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let font = UIFont.monospacedSystemFont(ofSize: 30, weight: .bold)
            let look: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: 0.85, alpha: 0.8)]
            let words = NSAttributedString(string: text, attributes: look)
            let s: CGSize = words.size()
            words.draw(at: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2))
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
