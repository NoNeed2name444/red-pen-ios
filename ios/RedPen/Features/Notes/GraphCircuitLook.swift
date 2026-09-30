import SceneKit
import UIKit
import Metal
import simd

// MARK: - The Circuit look
//
// How the Circuit theme (GraphCircuit) is dressed, for the shared theme
// scene (GraphThemeScene): tidy circuits of light, calm and legible at a
// glance, with few kinds of part.
//
// - each collection's tile: a floating rounded slab of near-black blue
//   glass, its rim lit faintly in the collection's own hue, a little of
//   that light spilling onto the dark round it (a child of its chip, so
//   dragging the chip moves the whole circuit); a folder inside gets a flat
//   inlay on the glass - a breath of fill, a lighter inner rim and a
//   hairline edge in the hue - open towards the return rail its lanes run
//   out to, so no lane ever cuts its edge; inlays nest;
// - chips in the style of modern system-on-chip packages (evoking, never
//   copying): a rounded square titanium package with a bright satin
//   chamfer, a near-black smoked-glass lid, and under it a faint die (cores
//   in the collection's hue, a GPU grid in ice blue, a neural block,
//   cache) and an etched outline in the hue that brightens as the pulse
//   passes; its folder's name printed on it with the app's own model tag
//   ("S-14 Pro"), letter-spaced in the hue. A chip in a folder is smaller,
//   its satin rim brighter so it reads from afar;
// - rings of light (pages), amber glass capsules (ideas: lit with links,
//   smoked glass with a thin amber rim without; a faint chevron points
//   along the current), violet prisms (loose notes), a dark glass source
//   cell with a glowing ring at each tile's top, titanium ports where a
//   fibre leaves for another tile;
// - the guides (GraphCircuitShaders.trace), one flat strip per wire and
//   link in two geometries (GraphRibbonWriter, routed by GraphLinkRoute on
//   the board with this look's circuit map): ice-blue wiring - the trunk
//   heaviest, branches lighter, the return rails thinnest, in indigo - and
//   violet links, almost invisible until one of their notes is chosen; a
//   joint dot only where a branch leaves a trunk or a lane joins a rail
//   (one geometry a tile);
// - one pulse of light a beat runs from each tile's source round its
//   circuit (the tiles' beats staggered), every part flashing as it passes
//   - all in the shaders, from `rpClock` and each part's distance.
//
// The halos (a lit capsule's light, the source's, a prism's, the chosen
// part's ring) are camera-facing squares: they stand at the part's top and
// are lifted towards the camera by a third of their size, so the glass
// never cuts off their lower half while nearer parts still hide them.
//
// The Graphics budget (GraphQuality.current) sets the cost: at Smooth the
// shapes have fewer segments, no halos, and the shaders their simple path
// (rpDetail 0: no glass sheen, die grids or reflection band). Reduce Motion
// or a still space: no pulse; the circuit rests fully lit.

@MainActor
final class GraphCircuitLook: GraphThemeLook {
    let theme: GraphTheme = .circuit
    let lively: Bool
    let bold: Bool
    let budget: GraphicsBudget
    let support: CircuitSupport
    let linkMaterial: SCNMaterial
    let farMaterial: SCNMaterial
    let linkHalfWidth: Float = 0.05
    let farHalfWidth: Float = 0.04
    let hotRing: SCNGeometry
    private(set) var clocked: [SCNMaterial] = []
    /// The board the guides are routed on, with the plan's circuit map
    /// (made with the first body, before the links are drawn).
    private(set) var board: GraphLinkBoard?
    /// A part's frame: x across the tile, y up out of it, z down it.
    let upTurn: simd_quatf
    private var shapes: [String: SCNGeometry] = [:]
    /// The plan being dressed: each body's pulse spot, and each tile's hue.
    private var spots: [CircuitPulseSpot] = []
    private var accents: [Int: SIMD3<Float>] = [:]

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
        linkMaterial = Self.guideMaterial(far: false, bold: bold, lively: lively, budget: budget, support: support,
                                          width: 0.05)
        farMaterial = Self.guideMaterial(far: true, bold: bold, lively: lively, budget: budget, support: support,
                                         width: 0.04)
        let hot: SCNMaterial = Self.glowMaterial(tint: Self.ice * 0.3, ring: Self.hot, gain: 0.12, support: support)
        hotRing = GraphSceneBuilder.plane(hot)
        if support.has("trace") {
            clocked.append(linkMaterial)
            clocked.append(farMaterial)
        }
    }

    // MARK: colours (sRGB, as on screen)

    static let glass = SIMD3<Float>(0.052, 0.060, 0.080)
    static let bevel = SIMD3<Float>(0.78, 0.84, 0.95)
    static let ice = SIMD3<Float>(0.50, 0.82, 1.0)
    static let packet = SIMD3<Float>(0.88, 0.97, 1.0)
    static let violet = SIMD3<Float>(0.70, 0.62, 1.0)
    static let indigo = SIMD3<Float>(0.40, 0.52, 1.0)
    static let warm = SIMD3<Float>(1.0, 0.70, 0.36)
    static let lilac = SIMD3<Float>(0.74, 0.62, 1.0)
    static let titanium = SIMD3<Float>(0.34, 0.335, 0.33)
    static let smoke = SIMD3<Float>(0.030, 0.034, 0.044)
    static let hot = SIMD3<Float>(0.6, 0.85, 1.0)
    /// The collections' hues, by their place on the bench: cyan, rose,
    /// violet, mint, amber, coral.
    static let hues: [SIMD3<Float>] = [
        SIMD3<Float>(0.36, 0.80, 1.0), SIMD3<Float>(1.0, 0.45, 0.55), SIMD3<Float>(0.62, 0.56, 1.0),
        SIMD3<Float>(0.35, 0.92, 0.72), SIMD3<Float>(1.0, 0.72, 0.35), SIMD3<Float>(1.0, 0.55, 0.40)
    ]

    func tone(region: Int, plan: ThemePlan) -> UIColor? {
        Self.colour(accent(region, plan: plan))
    }

    /// A tile's hue, by its region (its chip's body index).
    private func accent(_ region: Int, plan: ThemePlan) -> SIMD3<Float> {
        if let made = accents[region] { return made }
        let k: Int = plan.regions.firstIndex(of: region) ?? 0
        let hue: SIMD3<Float> = Self.hues[k % Self.hues.count]
        accents[region] = hue
        return hue
    }

    // MARK: the plan's circuit

    /// The pulse spots and the routes' map, once a plan (with its first
    /// body).
    private func prepare(_ plan: ThemePlan) {
        spots = GraphCircuit.pulseSpots(plan)
        accents = [:]
        var map = GraphCircuitMap(spacing: Float(GraphCircuit.pulseSpacing))
        for s in spots {
            let at = SIMD2<Float>(Float(s.at.x), Float(s.at.y))
            map.add(GraphCircuitSpot(at: at, dist: Float(s.dist), kind: s.kind))
        }
        board?.circuit = map
    }

    private func dist(_ index: Int) -> Float {
        index < spots.count ? Float(spots[index].dist) : 0
    }

    // MARK: a part

    func makeBody(_ body: ThemeBody, index: Int, plan: ThemePlan) -> GraphThemeParts {
        if index == 0 || spots.count != plan.bodies.count { prepare(plan) }
        let node = SCNNode()
        switch body.kind {
        case .note: node.name = "note:" + body.id.uuidString
        case .folder: node.name = "folder:" + body.id.uuidString
        case .home: node.name = "home"
        case .fixture: node.name = "fixture"
        }
        let role: CircuitRole = CircuitRole(rawValue: body.role) ?? .led
        let size: Float = body.sphere

        // the tile's frame (y up out of it)
        let up = SCNNode()
        up.simdOrientation = upTurn
        node.addChildNode(up)
        for piece in pieces(role, body: body, index: index, plan: plan) { up.addChildNode(piece) }
        if role.isContainer {
            addGround(to: node, body: body, index: index, plan: plan)
        }

        // the halo, on GraphSim's ring pieces: at the part's top, lifted
        // towards the camera (so the glass never cuts off its lower half)
        let top: Float = size * Self.height(role)
        let holder = SCNNode()
        holder.simdPosition = GraphUniverse.float3(GraphCircuit.normal) * top
        let facing = SCNBillboardConstraint()
        facing.freeAxes = .all
        holder.constraints = [facing]
        let across: Float = size * Self.haloSize(role)
        let lift = SCNNode()
        lift.simdPosition = SIMD3<Float>(0, 0, across * 0.35)
        holder.addChildNode(lift)
        let stretch = SCNNode()
        let lit: Bool = body.links > 0
        let glowing: Bool = (role == .led && lit) || role == .vcc || role == .pad
        let standing: Bool = glowing && budget.haze
        let halo: SCNGeometry = standing ? haloGeometry(role, dist: dist(index)) : GraphThemeParts.noHalo
        let leaf = SCNNode(geometry: halo)
        leaf.simdScale = SIMD3<Float>(across, across, 1)
        leaf.renderingOrder = 7
        leaf.categoryBitMask = 2
        stretch.addChildNode(leaf)
        lift.addChildNode(stretch)
        node.addChildNode(holder)
        let disk = SCNNode()
        node.addChildNode(disk)

        let reach: Float = max(size * Self.reach(role), 0.00002)
        var parts = GraphThemeParts(node: node, radius: reach, ringStretch: stretch, ringLeaf: leaf,
                                    ringGeometry: halo, diskLeaf: disk)
        if body.kind == .fixture {
            node.categoryBitMask = 2
            up.categoryBitMask = 2
        }
        parts.thinnable = !glowing && !role.isContainer
        return parts
    }

    /// How far out from its centre a part's guides start (times the links'
    /// trim) and it can be picked, in sizes: just past its rim; a joint's
    /// guides meet at its centre.
    private static func reach(_ role: CircuitRole) -> Float {
        switch role {
        case .processor, .module, .soc: return 1.0
        case .capacitor: return 0.8
        case .led: return 1.0
        case .pad: return 0.75
        case .vcc: return 1.0
        case .connector: return 1.2
        case .ground, .bus: return 0.001
        }
    }

    /// A part's top, in sizes above the glass (where its halo stands).
    private static func height(_ role: CircuitRole) -> Float {
        switch role {
        case .processor, .soc, .module: return 0.33
        case .capacitor: return 0.4
        case .led: return 1.0
        case .pad: return 0.42
        case .vcc: return 0.35
        default: return 0.05
        }
    }

    /// A halo's size, in sizes.
    private static func haloSize(_ role: CircuitRole) -> Float {
        switch role {
        case .processor, .soc, .module: return 3.4
        case .led: return 6.5
        case .vcc: return 4.5
        case .pad: return 5
        default: return 4
        }
    }

    // MARK: the parts' pieces

    /// The pieces of a part, in the tile's frame (y up from the glass).
    private func pieces(_ role: CircuitRole, body: ThemeBody, index: Int, plan: ThemePlan) -> [SCNNode] {
        let high: Bool = budget.tier == .high
        let s: Float = body.sphere
        let d: Float = dist(index)
        switch role {
        case .processor, .soc, .module:
            let small: Bool = role == .module
            let side: Float = s * 2.5
            let hue: SIMD3<Float> = accent(body.region, plan: plan)
            let busy: Float = Float(GraphUniverse.clamp(log2(1 + Double(body.count)) / 6, 0, 1))
            let frame = partMaterial(0, a: Self.ice, c: Self.titanium, shine: 0.8, dist: d)
            let lidLook = partMaterial(1, a: Self.ice, b: hue, c: Self.smoke, shine: 0.16,
                                       glow: small ? busy * 0.5 : busy, rim: small ? 0.75 : 0.4, dist: d)
            let package = piece(slab("package", 0.5, 0.5, 0.13, 0.10, 0.025), look: frame, y: 0.05 * side,
                                scale: side)
            let lid = piece(slab("lid", 0.455, 0.455, 0.11, 0.03, 0.012), look: lidLook, y: 0.115 * side,
                            scale: side)
            let plate: SCNNode = nameplate(body, hue: hue)
            plate.simdScale = SIMD3<Float>(side, side, side)
            return [package, lid, plate]
        case .capacitor:
            let ring = SCNTorus(ringRadius: 0.8, pipeRadius: 0.2)
            ring.ringSegmentCount = high ? 48 : 24
            ring.pipeSegmentCount = high ? 12 : 8
            let look = partMaterial(2, a: Self.ice, c: SIMD3<Float>(0.02, 0.03, 0.04), shine: 0.4, glow: 0.9, dist: d)
            return [piece(ring, look: look, y: 0.2 * s, scale: s)]
        case .led:
            let lit: Bool = body.links > 0
            let capsule = SCNCapsule(capRadius: 0.5, height: 2.6)
            capsule.radialSegmentCount = high ? 20 : 12
            capsule.capSegmentCount = high ? 6 : 4
            let body3: SCNGeometry = capsule
            let smoked = SIMD3<Float>(0.025, 0.022, 0.02)
            let look = partMaterial(3, a: Self.warm, c: smoked, shine: 1.0, glow: lit ? 1.0 : 0.12, dist: d)
            let node = piece(body3, look: look, y: 0.5 * s, scale: s)
            // lying along its lane, its axis (y) pointing the way current runs
            let out: Float = laneWay(index, plan: plan)
            let turn = simd_quatf(angle: -out * Float.pi / 2, axis: SIMD3<Float>(0, 0, 1))
            node.simdOrientation = turn
            return [node]
        case .pad:
            let look = partMaterial(4, a: Self.lilac, c: SIMD3<Float>(0.10, 0.09, 0.15), shine: 1.0, glow: 1.3, dist: d)
            return [piece(prism(), look: look, y: 0, scale: s)]
        case .vcc:
            let cell = SCNCylinder(radius: 1, height: 0.35)
            cell.radialSegmentCount = high ? 40 : 20
            let look = partMaterial(5, a: Self.ice, c: Self.titanium, shine: 0.8, dist: d)
            return [piece(cell, look: look, y: 0.175 * s, scale: s)]
        case .connector:
            let port = SCNBox(width: 1.0, height: 0.3, length: 0.5, chamferRadius: 0.1)
            port.chamferSegmentCount = high ? 3 : 1
            let look = partMaterial(6, a: Self.violet, c: Self.titanium, shine: 0.8, dist: d)
            return [piece(port, look: look, y: 0.015, scale: 0.1)]
        case .ground, .bus:
            // a joint: its dot is drawn with its tile's (addGround)
            return []
        }
    }

    /// Which way along x a capsule's current runs: away from what feeds it.
    private func laneWay(_ index: Int, plan: ThemePlan) -> Float {
        guard index < plan.feeds.count, index < spots.count else { return 1 }
        let f: Int = plan.feeds[index]
        guard f >= 0, f < spots.count else { return 1 }
        return spots[index].at.x >= spots[f].at.x ? 1 : -1
    }

    /// A piece: its own geometry (sharing the shape's vertices) in its own
    /// material, at height `y` in the tile's frame, scaled evenly.
    private func piece(_ geometry: SCNGeometry, look: SCNMaterial, y: Float, scale: Float) -> SCNNode {
        let copy: SCNGeometry = geometry.copy() as? SCNGeometry ?? geometry
        copy.materials = [look]
        let node = SCNNode(geometry: copy)
        node.simdPosition = SIMD3<Float>(0, y, 0)
        node.simdScale = SIMD3<Float>(scale, scale, scale)
        return node
    }

    // MARK: shapes (one each, shared)

    private func slab(_ key: String, _ hx: Float, _ hz: Float, _ corner: Float, _ height: Float,
                      _ bevel: Float) -> SCNGeometry {
        if let made = shapes[key] { return made }
        let steps: Int = budget.tier == .high ? 6 : 3
        let made: SCNGeometry = CircuitMesh.slab(halfX: hx, halfZ: hz, corner: corner, height: height, bevel: bevel,
                                                 steps: steps)
        shapes[key] = made
        return made
    }

    private func prism() -> SCNGeometry {
        if let made = shapes["prism"] { return made }
        let made: SCNGeometry = CircuitMesh.prism()
        shapes["prism"] = made
        return made
    }

    // MARK: materials

    /// A part's material, by pattern and colours, with its own distance
    /// along the circuit (so it flashes as the pulse passes).
    private func partMaterial(_ pattern: Int, a: SIMD3<Float>, b: SIMD3<Float> = SIMD3<Float>(0.6, 0.6, 0.6),
                              c: SIMD3<Float>, shine: Float, glow: Float = 0, rim: Float = 0,
                              dist: Float) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = GraphStyleProbe.blackContents
        guard support.has("part") else {
            let lit: Bool = pattern >= 2 && pattern <= 5
            let plain: SIMD3<Float> = lit ? a * (0.35 + 0.5 * min(glow, 1)) : c * 0.9
            material.diffuse.contents = Self.colour(plain)
            return material
        }
        material.shaderModifiers = [.surface: CircuitShaders.part]
        GraphStyleUniforms.defaults(material)
        Self.set(material, "rpDetail", budget.shaderDetail)
        Self.set(material, "rpPattern", Float(pattern))
        Self.set(material, "rpShine", shine)
        Self.set(material, "rpGlow", glow)
        Self.set(material, "rpRim", rim)
        Self.pulse(material, dist: dist, lively: lively)
        Self.tint(material, "rpTintA", a)
        Self.tint(material, "rpTintB", b)
        Self.tint(material, "rpTintC", c)
        clocked.append(material)
        return material
    }

    /// The beat every pulsing material shares, and this one's distance.
    private static func pulse(_ material: SCNMaterial, dist: Float, lively: Bool) {
        set(material, "rpMotion", lively ? 1 : 0)
        set(material, "rpSpeed", Float(GraphCircuit.pulseSpeed))
        set(material, "rpSpacing", Float(GraphCircuit.pulseSpacing))
        set(material, "rpDist", dist)
    }

    /// The light guides: the wiring (`far` false) or the links.
    private static func guideMaterial(far: Bool, bold: Bool, lively: Bool, budget: GraphicsBudget,
                                      support: CircuitSupport, width: Float) -> SCNMaterial {
        let strength: Float = bold ? 1.3 : 1
        guard support.has("trace") else {
            let plain: SCNMaterial = GraphLook.link(bold: bold, shader: false, lively: lively)
            plain.multiply.contents = colour(far ? violet * 0.4 : ice)
            plain.isDoubleSided = true
            return plain
        }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = GraphStyleProbe.blackContents
        // light on the glass, over a little darkening of its channel:
        // premultiplied (the light has no alpha of its own); the hair under
        // 1 keeps SceneKit drawing it in its blended pass, after the glass
        material.blendMode = .alpha
        material.transparency = 0.999
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        material.shaderModifiers = [.surface: CircuitShaders.trace]
        GraphStyleUniforms.defaults(material)
        set(material, "rpMotion", lively ? 1 : 0)
        set(material, "rpDetail", budget.shaderDetail)
        set(material, "rpSpeed", Float(GraphCircuit.pulseSpeed))
        set(material, "rpSpacing", Float(GraphCircuit.pulseSpacing))
        set(material, "rpWidth", width)
        set(material, "rpFar", far ? 1 : 0)
        let plane = GraphLinkBoard(right: SIMD3<Float>(1, 0, 0), forward: SIMD3<Float>(0, 1, 0),
                                   normal: SIMD3<Float>(0, 0, 1))
        set(material, "rpLift", plane.lift)
        set(material, "rpStep", plane.step)
        tint(material, "rpNormal", GraphUniverse.float3(GraphCircuit.normal))
        tint(material, "rpTintA", ice * strength)
        tint(material, "rpTintB", packet)
        tint(material, "rpTintC", violet * strength)
        tint(material, "rpTintD", indigo * strength)
        return material
    }

    /// A halo for a lit capsule, the source or a prism, flashing as the
    /// pulse passes.
    private func haloGeometry(_ role: CircuitRole, dist: Float) -> SCNGeometry {
        var tint: SIMD3<Float> = Self.warm
        var gain: Float = 0.30
        var flash: Float = 0.5
        if role == .vcc {
            tint = Self.ice
            gain = 0.35
            flash = 0.3
        } else if role == .pad {
            tint = Self.lilac
            gain = 0.14
            flash = 0.35
        }
        let material: SCNMaterial = Self.glowMaterial(tint: tint, ring: SIMD3<Float>(0, 0, 0), gain: gain,
                                                      support: support)
        if support.has("glow") {
            Self.set(material, "rpFlash", flash)
            Self.pulse(material, dist: dist, lively: lively)
            clocked.append(material)
        }
        return GraphSceneBuilder.plane(material)
    }

    /// A glow: `shape` 0 round, 1 a tile's spill, 2 a folder's inlay, 3 a
    /// tile's joint dots (GraphCircuitShaders.glow).
    private static func glowMaterial(tint: SIMD3<Float>, ring: SIMD3<Float>, gain: Float,
                                     support: CircuitSupport, shape: Float = 0) -> SCNMaterial {
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
        set(material, "rpShape", shape)
        set(material, "rpFlash", 0)
        set(material, "rpDist", 0)
        set(material, "rpSpeed", Float(GraphCircuit.pulseSpeed))
        set(material, "rpSpacing", Float(GraphCircuit.pulseSpacing))
        Self.tint(material, "rpTintA", tint)
        Self.tint(material, "rpTintC", ring)
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

    // MARK: tiles, inlays and joints

    /// A chip's ground: a collection's glass tile, its spill of light and
    /// its joint dots (a controller's `patch`: the tile round it), or a
    /// folder's inlay (a sub-chip's) - children of the chip, so they move
    /// with it.
    private func addGround(to node: SCNNode, body: ThemeBody, index: Int, plan: ThemePlan) {
        guard index < plan.patches.count else { return }
        let patch: SIMD4<Float> = plan.patches[index]
        guard patch.z > 0.001, patch.w > 0.001 else { return }
        let hue: SIMD3<Float> = accent(body.region, plan: plan)
        let r: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.right)
        let f: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
        let n: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.normal)
        let centre: SIMD3<Float> = r * patch.x + f * patch.y
        if body.parent >= 0 {
            // which way its rail is: away from its tile's middle
            let open: Float = patch.x >= 0 ? 1 : -1
            node.addChildNode(inlay(patch, hue: hue, open: open, at: centre + n * 0.003, depth: body.depth))
            return
        }
        let thick: Float = 0.09
        let tile: SCNGeometry = CircuitMesh.slab(halfX: patch.z, halfZ: patch.w, corner: 0.34, height: thick,
                                                 bevel: 0.03, steps: budget.tier == .high ? 6 : 3)
        tile.materials = [tileMaterial(half: SIMD3<Float>(patch.z, thick * 0.5, patch.w), hue: hue)]
        let slab = SCNNode(geometry: tile)
        slab.simdPosition = centre - n * (thick * 0.5)
        slab.simdOrientation = upTurn
        slab.categoryBitMask = 2
        slab.renderingOrder = -3
        node.addChildNode(slab)
        node.addChildNode(spill(patch, hue: hue, at: centre - n * (thick + 0.02)))
        if let dots = jointDots(index, plan: plan) { node.addChildNode(dots) }
    }

    private func tileMaterial(half: SIMD3<Float>, hue: SIMD3<Float>) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        guard support.has("board") else {
            material.diffuse.contents = Self.colour(Self.glass + hue * 0.03)
            return material
        }
        material.diffuse.contents = GraphStyleProbe.blackContents
        material.shaderModifiers = [.surface: CircuitShaders.board]
        GraphStyleUniforms.defaults(material)
        Self.set(material, "rpDetail", budget.shaderDetail)
        Self.set(material, "rpCorner", 0.34)
        material.setValue(NSValue(scnVector3: SCNVector3(x: half.x, y: half.y, z: half.z)), forKey: "rpSize")
        Self.tint(material, "rpTintA", Self.glass)
        Self.tint(material, "rpTintB", hue)
        Self.tint(material, "rpTintC", Self.bevel)
        return material
    }

    /// A flat square in the tile's frame, `span` across its half side, at
    /// `at`; turned half round (its +x to -x) when `flip`.
    private func flatSquare(_ material: SCNMaterial, span: Float, at: SIMD3<Float>, flip: Bool) -> SCNNode {
        let node = SCNNode(geometry: GraphSceneBuilder.plane(material))
        let lie = simd_quatf(angle: -Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let spin = simd_quatf(angle: flip ? Float.pi : 0, axis: SIMD3<Float>(0, 1, 0))
        node.simdOrientation = upTurn * spin * lie
        node.simdPosition = at
        node.simdScale = SIMD3<Float>(span * 2, span * 2, 1)
        node.categoryBitMask = 2
        return node
    }

    /// A tile's light spilling onto the dark round it, in its hue.
    private func spill(_ patch: SIMD4<Float>, hue: SIMD3<Float>, at: SIMD3<Float>) -> SCNNode {
        let span: Float = max(patch.z, patch.w) + 0.9
        let material: SCNMaterial = Self.glowMaterial(tint: hue, ring: SIMD3<Float>(0, 0, 0), gain: 0.10,
                                                      support: support, shape: 1)
        let size = SCNVector3(x: patch.z / span, y: patch.w / span, z: 0.34 / span)
        material.setValue(NSValue(scnVector3: size), forKey: "rpSize")
        let node: SCNNode = flatSquare(material, span: span, at: at, flip: false)
        node.renderingOrder = -4
        return node
    }

    /// A folder's inlay, open towards its rail (`open` +1 or -1 across the
    /// tile).
    private func inlay(_ patch: SIMD4<Float>, hue: SIMD3<Float>, open: Float, at: SIMD3<Float>,
                       depth: Int) -> SCNNode {
        let span: Float = max(patch.z, patch.w) + 0.05
        let gain: Float = depth <= 1 ? 1.0 : 0.75
        let material: SCNMaterial = Self.glowMaterial(tint: hue, ring: Self.bevel, gain: gain, support: support,
                                                      shape: 2)
        let size = SCNVector3(x: patch.z / span, y: patch.w / span, z: 0.16 / span)
        material.setValue(NSValue(scnVector3: size), forKey: "rpSize")
        Self.set(material, "rpLine", 0.007 / span)
        let node: SCNNode = flatSquare(material, span: span, at: at, flip: open < 0)
        node.renderingOrder = -2
        return node
    }

    /// Tile `index`'s joint dots, one geometry: where a branch leaves a
    /// trunk (two or more wires out of a joint) and where a lane joins a
    /// rail that runs on from below - only the real T-junctions.
    private func jointDots(_ index: Int, plan: ThemePlan) -> SCNNode? {
        var wiresOut = [Int](repeating: 0, count: plan.bodies.count)
        var railIn = [Bool](repeating: false, count: plan.bodies.count)
        var laneIn = [Bool](repeating: false, count: plan.bodies.count)
        for l in plan.links where l.kind == 5 {
            let fromRail: Bool = plan.bodies[l.a].role == CircuitRole.ground.rawValue
            if fromRail {
                railIn[l.b] = true
            } else {
                wiresOut[l.a] += 1
                laneIn[l.b] = true
            }
        }
        let home: SIMD3<Float> = plan.bodies[index].home
        var dots: [(SIMD3<Float>, Int)] = []
        for (i, b) in plan.bodies.enumerated() where b.region == index && b.kind == .fixture {
            if b.role == CircuitRole.bus.rawValue && wiresOut[i] >= 2 { dots.append((b.home - home, 0)) }
            if b.role == CircuitRole.ground.rawValue && railIn[i] && laneIn[i] { dots.append((b.home - home, 1)) }
        }
        guard !dots.isEmpty else { return nil }
        let r: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.right)
        let f: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
        let n: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.normal)
        let geometry: SCNGeometry = CircuitMesh.dots(dots, right: r * 0.05, forward: f * 0.05, up: n * 0.03)
        let material: SCNMaterial = Self.glowMaterial(tint: Self.ice, ring: Self.indigo, gain: 0.9, support: support,
                                                      shape: 3)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.categoryBitMask = 2
        node.renderingOrder = 6
        return node
    }

    /// A chip's name, printed on its lid: its folder's name and its model
    /// tag (GraphCircuit.modelTag), in the chip's frame at unit size.
    private func nameplate(_ body: ThemeBody, hue: SIMD3<Float>) -> SCNNode {
        let plane = SCNPlane(width: 0.72, height: 0.36)
        let material = SCNMaterial()
        material.lightingModel = .constant
        let tag: String = GraphCircuit.modelTag(count: body.count, depth: max(body.depth, 0))
        material.diffuse.contents = CircuitArt.nameplate(body.title, tag: tag, hue: Self.colour(hue))
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        plane.materials = [material]
        let holder = SCNNode()
        let node = SCNNode(geometry: plane)
        node.simdPosition = SIMD3<Float>(0, 0.132, 0)
        node.simdOrientation = simd_quatf(angle: -Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        node.categoryBitMask = 2
        node.renderingOrder = 3
        holder.addChildNode(node)
        return holder
    }

    // MARK: each frame

    /// Nothing: the pulse and every flash run in the shaders.
    func ticker(parts: [GraphThemeParts], plan: ThemePlan) -> GraphThemeTicker? {
        nil
    }

    // MARK: behind the tiles

    func makeSky() -> SCNNode {
        CircuitRoom.makeSky()
    }
}

// MARK: - Meshes

/// The Circuit's own shapes, each one geometry, y up.
@MainActor
enum CircuitMesh {
    /// A rounded slab: a rounded rectangle `halfX` by `halfZ` with corners
    /// of radius `corner`, `height` thick (y from -height/2 to height/2),
    /// its top edge rounded off by `bevel`; `steps` segments a corner.
    static func slab(halfX: Float, halfZ: Float, corner: Float, height: Float, bevel: Float,
                     steps: Int) -> SCNGeometry {
        var points: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        let top: Float = height * 0.5
        // the profile: inset, height, how much up and how much out
        var profile: [SIMD4<Float>] = []
        for k in 0...4 {
            let a: Float = Float(k) / 4 * Float.pi / 2
            let inset: Float = bevel - bevel * sin(a)
            let y: Float = top - bevel * (1 - cos(a))
            profile.append(SIMD4<Float>(inset, y, cos(a), sin(a)))
        }
        profile.append(SIMD4<Float>(0, -top, 0, 1))
        points.append(SCNVector3(x: 0, y: top, z: 0))
        normals.append(SCNVector3(x: 0, y: 1, z: 0))
        var rings: [Int32] = []
        var count: Int = 0
        for p in profile {
            rings.append(Int32(points.count))
            let outline: [(SIMD2<Float>, SIMD2<Float>)] = Self.outline(halfX, halfZ, corner, inset: p.x, steps: steps)
            count = outline.count
            for (q, d) in outline {
                points.append(SCNVector3(x: q.x, y: p.y, z: q.y))
                normals.append(SCNVector3(x: d.x * p.w, y: p.z, z: d.y * p.w))
            }
        }
        let first: Int32 = rings[0]
        for k in 0..<count {
            let a: Int32 = first + Int32(k)
            let b: Int32 = first + Int32((k + 1) % count)
            indices.append(contentsOf: [0, b, a])
        }
        for r in 0..<(rings.count - 1) {
            for k in 0..<count {
                let a0: Int32 = rings[r] + Int32(k)
                let a1: Int32 = rings[r] + Int32((k + 1) % count)
                let b0: Int32 = rings[r + 1] + Int32(k)
                let b1: Int32 = rings[r + 1] + Int32((k + 1) % count)
                indices.append(contentsOf: [a0, a1, b0, a1, b1, b0])
            }
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals)],
                           elements: [element])
    }

    /// Points round a rounded rectangle `inset` in from its edge, with
    /// their outward directions, turning from +x towards +z.
    static func outline(_ hx: Float, _ hz: Float, _ r: Float, inset: Float,
                        steps: Int) -> [(SIMD2<Float>, SIMD2<Float>)] {
        let rr: Float = max(r - inset, 0)
        let cx: Float = max(hx - r, 0)
        let cz: Float = max(hz - r, 0)
        let corners: [SIMD3<Float>] = [SIMD3<Float>(1, 1, 0), SIMD3<Float>(-1, 1, 0.5),
                                       SIMD3<Float>(-1, -1, 1), SIMD3<Float>(1, -1, 1.5)]
        var out: [(SIMD2<Float>, SIMD2<Float>)] = []
        for c in corners {
            for k in 0...steps {
                let a: Float = Float.pi * (c.z + 0.5 * Float(k) / Float(steps))
                let d = SIMD2<Float>(cos(a), sin(a))
                let centre = SIMD2<Float>(c.x * cx, c.y * cz)
                out.append((centre + d * rr, d))
            }
        }
        return out
    }

    /// A loose note's prism: a flat, faceted diamond (a squashed
    /// octahedron), each face flat-shaded.
    static func prism() -> SCNGeometry {
        let tips: [SIMD3<Float>] = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1), SIMD3<Float>(-1, 0, 0),
                                    SIMD3<Float>(0, 0, -1)]
        var points: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for apexY in [Float(0.42), Float(-0.2)] {
            let apex = SIMD3<Float>(0, apexY, 0)
            for k in 0..<4 {
                let a: SIMD3<Float> = tips[k]
                let b: SIMD3<Float> = tips[(k + 1) % 4]
                var n: SIMD3<Float> = simd_normalize(simd_cross(b - a, apex - a))
                var order: [SIMD3<Float>] = [a, b, apex]
                if n.y * apexY < 0 {
                    n = -n
                    order = [b, a, apex]
                }
                let base = Int32(points.count)
                for p in order {
                    points.append(SCNVector3(x: p.x, y: p.y, z: p.z))
                    normals.append(SCNVector3(x: n.x, y: n.y, z: n.z))
                }
                indices.append(contentsOf: [base, base + 1, base + 2])
            }
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals)],
                           elements: [element])
    }

    /// A tile's joint dots as one geometry: a flat square at each point,
    /// lifted by `up`, its texture's u carrying the dot's kind (kind * 2 +
    /// across it).
    static func dots(_ list: [(SIMD3<Float>, Int)], right: SIMD3<Float>, forward: SIMD3<Float>,
                     up: SIMD3<Float>) -> SCNGeometry {
        var points: [SCNVector3] = []
        var coords: [CGPoint] = []
        var indices: [Int32] = []
        let n: SIMD3<Float> = simd_normalize(up)
        var normals: [SCNVector3] = []
        for (p, kind) in list {
            let c: SIMD3<Float> = p + up
            let corners: [SIMD3<Float>] = [c - right - forward, c + right - forward, c + right + forward,
                                           c - right + forward]
            let u0: CGFloat = CGFloat(kind * 2)
            let uv: [CGPoint] = [CGPoint(x: u0, y: 1), CGPoint(x: u0 + 1, y: 1), CGPoint(x: u0 + 1, y: 0),
                                 CGPoint(x: u0, y: 0)]
            let base = Int32(points.count)
            for (k, q) in corners.enumerated() {
                points.append(SCNVector3(x: q.x, y: q.y, z: q.z))
                normals.append(SCNVector3(x: n.x, y: n.y, z: n.z))
                coords.append(uv[k])
            }
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let sources: [SCNGeometrySource] = [SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals),
                                            SCNGeometrySource(textureCoordinates: coords)]
        return SCNGeometry(sources: sources, elements: [element])
    }
}

// MARK: - Behind the tiles

/// The Circuit's backdrop, in place of the stars: a deep blue-black dark,
/// a little lighter above. Made once, on a sphere of radius 1, shared by
/// every scene and scaled by the builder; GraphSim keeps it round the
/// camera.
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
        let above: SIMD3<Float> = simd_normalize(SIMD3<Float>(0, 0.8, 0.6))
        let low = SIMD3<Float>(0.004, 0.005, 0.009)
        let high = SIMD3<Float>(0.020, 0.024, 0.040)
        var positions: [SCNVector3] = []
        var colours: [Float] = []
        for row in 0...rows {
            let lat: Float = Float.pi * (Float(row) / Float(rows) - 0.5)
            for column in 0...columns {
                let lon: Float = 2 * Float.pi * Float(column) / Float(columns)
                let flat: Float = cos(lat)
                let dir = SIMD3<Float>(flat * cos(lon), sin(lat), flat * sin(lon))
                positions.append(SCNVector3(x: dir.x, y: dir.y, z: dir.z))
                let share: Float = min(max(0.5 + 0.5 * simd_dot(dir, above), 0), 1)
                let c: SIMD3<Float> = low + (high - low) * share
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

/// A chip's printed name, drawn once each: the only text in the scene.
@MainActor
enum CircuitArt {
    /// Its folder's name in the system font, bold, and under it the app's
    /// own model tag, letter-spaced in the collection's hue, on the chip's
    /// dark lid.
    static func nameplate(_ title: String, tag: String, hue: UIColor) -> UIImage {
        let size = CGSize(width: 512, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let ink = UIColor(white: 0.94, alpha: 0.93)
        let name: String = String(title.prefix(14))
        return renderer.image { _ in
            let big = UIFont.systemFont(ofSize: name.count > 9 ? 54 : 66, weight: .semibold)
            let small = UIFont.systemFont(ofSize: 40, weight: .medium)
            let top: [NSAttributedString.Key: Any] = [.font: big, .foregroundColor: ink]
            let bottom: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: hue, .kern: 7.0]
            let first = NSAttributedString(string: name, attributes: top)
            let second = NSAttributedString(string: tag, attributes: bottom)
            let a: CGSize = first.size()
            let b: CGSize = second.size()
            first.draw(at: CGPoint(x: (size.width - a.width) / 2, y: 58))
            second.draw(at: CGPoint(x: (size.width - b.width) / 2, y: 76 + a.height))
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
/// tiles and parts on a box, the guides and glows on a plane.
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
                let values: [(String, Float)] = [("rpMotion", 1), ("rpPattern", 0), ("rpShine", 1), ("rpGlow", 0),
                                                 ("rpRim", 0.4), ("rpGain", 1), ("rpFlash", 0), ("rpDist", 0),
                                                 ("rpSpeed", 2), ("rpSpacing", 12.8), ("rpWidth", 0.05),
                                                 ("rpFar", 0), ("rpLift", 0.012), ("rpStep", 0.004),
                                                 ("rpShape", 0), ("rpLine", 0.01), ("rpCorner", 0.3)]
                for (key, value) in values { material.setValue(NSNumber(value: value), forKey: key) }
                let size = SCNVector3(x: 1, y: 1, z: 1)
                material.setValue(NSValue(scnVector3: size), forKey: "rpSize")
                material.setValue(NSValue(scnVector3: size), forKey: "rpNormal")
            }
            if ok { passed.insert(name) }
        }
        return CircuitSupport(passed: passed)
    }
}
