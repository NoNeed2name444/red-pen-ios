import SceneKit
import UIKit
import Metal
import simd

// MARK: - The depth fade, on SceneKit
//
// The SceneKit half of GraphDepthFade.swift (plan 4f,
// docs/design/depth-fade.md), for the scenes the theme builder and the
// Universe builder make. Built once for both SceneKit themes; nothing in a
// theme's own shaders changes.
//
// - A shader of our own (GraphDepthShader) is added, at the fragment entry
//   point, to every material of the map as built (GraphDepth.install walks
//   the scene; the name pills and the backdrop are left alone). Each pixel
//   finds its own depth along the view and the focus's depth from the
//   point the camera looks at, and fades by the band's curve: light added
//   to what is behind it fades to nothing, see-through things go
//   see-through, solid ones mix toward the background's colour
//   (GraphDepthMode). The band's numbers are given to each material once;
//   the point looked at only when it moves along the view (a fly-in, a
//   recentre), so zooming and turning write nothing.
// - Past the band's end nothing is drawn: the camera's far plane is the
//   end, and each body past it is hidden (a gate node holding everything it
//   draws), so it cannot be picked either.
// - Name pills sit in a gate of their own, shown only in the crisp zone or
//   for the chosen body, never faded.
// - A body's extras (its look's choice: the Neurons' halo and the glow of
//   arriving impulses, the smaller cells' dendrites) shrink away once it is
//   mostly faded and grow back once it is crisper (GraphDepthDetail).
//
// Once a frame, on the render thread, the keeper reads where the camera is
// and what it orbits - SceneKit's camera controller's target, which
// Graph3DView hands over when the scene goes on screen (GraphDepth.follow);
// the map's middle until then - and where GraphSim has put each body. It
// runs as an action on a node of its own rather than in a look's ticker,
// which a still map (Reduce Motion) does not have: the fade is not motion.
//
// The shader is checked once on the device first (GraphDepthProbe); where
// it does not work the map is drawn as before, unfaded.
//
// For the proof (plan 4f): `-graphDepthOff` draws the map as before, and
// `-graphDepthMeter` shows SceneKit's statistics and keeps the frame times
// (GraphDepthMeter) on an element the UI tests read, "graphDepthMeter",
// after whether the fade is on, off, or off because the shader failed its
// check (GraphDepthState).

/// The depth fade's shader, added at the fragment entry point beside a
/// material's own shaders. `rpDepthBand` is the band (start, end, k, most:
/// GraphDepthBand.uniform), `rpDepthAim` the point the camera looks at in
/// the scene's space, `rpDepthTint` the background's colour (linear) and
/// the material's GraphDepthMode code in w.
nonisolated enum GraphDepthShader {
    static let fragment: String = """
    #pragma arguments
    float4 rpDepthBand;
    float4 rpDepthTint;
    float3 rpDepthAim;

    #pragma body
    float4 rpDepthAt = scn_frame.viewTransform * float4(rpDepthAim, 1.0);
    float rpDepthFocus = max(-rpDepthAt.z, 0.0005);
    float rpDepthFrom = rpDepthBand.x * rpDepthFocus;
    float rpDepthWidth = max((rpDepthBand.y - rpDepthBand.x) * rpDepthFocus, 0.000001);
    float rpDepthAlong = clamp((-_surface.position.z - rpDepthFrom) / rpDepthWidth, 0.0, 1.0);
    float rpDepthFade = rpDepthAlong > 0.0 ? pow(rpDepthAlong, rpDepthBand.z) * rpDepthBand.w : 0.0;
    if (rpDepthTint.w < 0.5) {
        _output.color.rgb = _output.color.rgb * (1.0 - rpDepthFade);
    } else if (rpDepthTint.w < 1.5) {
        _output.color = _output.color * (1.0 - rpDepthFade);
    } else {
        _output.color.rgb = mix(_output.color.rgb, rpDepthTint.rgb * _output.color.a, rpDepthFade);
    }
    """

    /// Gives `material` the shader and its numbers.
    static func dress(_ material: SCNMaterial, band: GraphDepthBand, mode: GraphDepthMode,
                      tint: SIMD3<Float>, aim: SIMD3<Float>) {
        var modifiers: [SCNShaderModifierEntryPoint: String] = material.shaderModifiers ?? [:]
        modifiers[.fragment] = fragment
        material.shaderModifiers = modifiers
        let b: SIMD4<Float> = band.uniform
        material.setValue(NSValue(scnVector4: SCNVector4(x: b.x, y: b.y, z: b.z, w: b.w)), forKey: "rpDepthBand")
        material.setValue(NSValue(scnVector4: SCNVector4(x: tint.x, y: tint.y, z: tint.z, w: mode.rawValue)),
                          forKey: "rpDepthTint")
        point(material, at: aim)
    }

    /// Points `material`'s fade at `aim`.
    static func point(_ material: SCNMaterial, at aim: SIMD3<Float>) {
        material.setValue(NSValue(scnVector3: SCNVector3(x: aim.x, y: aim.y, z: aim.z)), forKey: "rpDepthAim")
    }

    /// How `material` fades, from how it is drawn; nil for one the fade
    /// leaves alone (multiplied over what is behind it).
    static func mode(of material: SCNMaterial) -> GraphDepthMode? {
        switch material.blendMode {
        case .add, .screen, .subtract, .max:
            return .light
        case .multiply:
            return nil
        case .alpha, .replace:
            return GraphDepthMode.of(adds: false, writesDepth: material.writesToDepthBuffer)
        @unknown default:
            return nil
        }
    }
}

/// Whether the depth fade's shader compiles and fades on this device: drawn
/// crisp at the focus, and gone past the band's end, in GraphStyleProbe's
/// tiny offscreen render. Kept once it can be trusted (GraphProbeMemo).
nonisolated enum GraphDepthProbe {
    /// A fresh check unless one is kept: off the main thread (the themes'
    /// prepare step).
    static var support: Bool { memo.check(visit: { GraphForeground.shared.visit }) }

    /// The last answer without checking again, or a check now if there is
    /// none: the build.
    static var latest: Bool { memo.latest(visit: { GraphForeground.shared.visit }) }

    private static let memo = GraphProbeMemo<Bool> {
        let works: Bool = GraphDepthProbe.run()
        return (works, works)
    }

    private static func run() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        // the probe's camera is 3 in front of the plane: aimed at the plane
        // it is the focus, so crisp; aimed half a unit ahead of the eye the
        // band ends at 1.3, so the plane is gone
        let crisp: Bool = renders(aim: SIMD3<Float>(0, 0, 0), device: device)
        let gone: Bool = renders(aim: SIMD3<Float>(0, 0, 2.5), device: device)
        return crisp && !gone
    }

    private static func renders(aim: SIMD3<Float>, device: MTLDevice) -> Bool {
        GraphStyleProbe.renders([.fragment: GraphDepthShader.fragment], on: SCNPlane(width: 4, height: 4),
                                device: device) { material in
            material.diffuse.contents = UIColor.white
            GraphDepthShader.dress(material, band: .neuronsHigh, mode: .light, tint: SIMD3<Float>(0, 0, 0),
                                   aim: aim)
        }
    }
}

/// Keeps one scene's depth fade on the camera's focus. Built on the main
/// thread; `step` runs on the render thread, `follow` and `show` on the
/// main thread.
nonisolated final class GraphDepthKeeper: @unchecked Sendable {
    /// One body: its gate (everything it draws but its name), its name
    /// pill's gate, and its extras with their own sizes.
    struct Body {
        let gate: SCNNode
        let pill: SCNNode
        let extras: [(node: SCNNode, scale: SIMD3<Float>)]
        var hidden: Bool = false
        var named: Bool = true
        var kept: Bool = true
        var grown: Float = 1
    }

    /// nil: measuring only (`-graphDepthOff`, or the shader failed its check).
    let band: GraphDepthBand?
    /// Which of those, for the meter's label.
    let state: GraphDepthState
    private weak var world: SCNNode?
    private weak var camera: SCNNode?
    private weak var sky: SCNNode?
    private weak var sim: GraphSim?
    private let builtSky: Float
    /// The map's middle in the world node's space: the focus until the
    /// camera controller is handed over.
    private let middle: SIMD3<Float>
    private let materials: [SCNMaterial]
    /// Reduce Motion or a still space: extras change size at once.
    private let still: Bool
    private let lock = NSLock()
    /// The view's camera controller: what the camera orbits. Under the lock.
    private weak var controller: SCNCameraController?
    /// Where the meter's numbers go (main thread).
    private weak var readout: UILabel?
    /// How many bodies the map has, and how many are hidden past the end
    /// (the meter's "drawn").
    private let total: Int
    private var hiddenCount: Int = 0

    // the render thread's own
    private var bodies: [Body]
    /// The point the shader is aimed at, and whether it has been written.
    private var aim: SIMD3<Float> = .zero
    private var aimed: Bool = false
    private var lastFar: Float = -1
    private var lastSky: Float = -1
    private var lastTime: Double = -1
    private var meter: GraphDepthMeter?
    private var lastRead: Double = 0

    init(band: GraphDepthBand?, state: GraphDepthState, world: SCNNode, camera: SCNNode, sky: SCNNode,
         sim: GraphSim, builtSky: Float, middle: SIMD3<Float>, materials: [SCNMaterial], bodies: [Body],
         still: Bool, metered: Bool, total: Int) {
        self.band = band
        self.state = state
        self.total = total
        self.world = world
        self.camera = camera
        self.sky = sky
        self.sim = sim
        self.builtSky = builtSky
        self.middle = middle
        self.materials = materials
        self.bodies = bodies
        self.still = still
        self.meter = metered ? GraphDepthMeter() : nil
    }

    /// What the camera orbits from now on (main thread).
    func follow(_ controller: SCNCameraController) {
        lock.lock()
        self.controller = controller
        lock.unlock()
    }

    /// Where the meter's numbers go from now on (main thread).
    func show(on label: UILabel) {
        lock.lock()
        readout = label
        lock.unlock()
    }

    /// One frame. Render thread.
    func step() {
        let now: Double = CACurrentMediaTime()
        let dt: Float = lastTime < 0 ? 0 : Float(now - lastTime)
        lastTime = now
        if meter != nil { measure(now) }
        guard let band, let camera, let world else { return }
        let pose: simd_float4x4 = camera.presentation.simdWorldTransform
        let eye = SIMD3<Float>(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
        let forward = SIMD3<Float>(-pose.columns.2.x, -pose.columns.2.y, -pose.columns.2.z)
        let toScene: simd_float4x4 = world.presentation.simdWorldTransform
        let target: SIMD3<Float> = focusPoint(eye: eye, forward: forward, toScene: toScene)
        let focus: Float = GraphDepthFocus.depth(eye: eye, forward: forward, target: target)

        // the shader finds the focus from the point it is aimed at: aimed
        // again only once that point's depth no longer matches the focus's
        let shown: Float = GraphDepthFocus.depth(eye: eye, forward: forward, target: aim)
        if !aimed || GraphDepthBand.moved(from: shown, to: focus) {
            aim = target
            aimed = true
            for material in materials { GraphDepthShader.point(material, at: target) }
        }

        // nothing drawn past the end; the backdrop inside the far plane
        if let lens = camera.camera {
            let near = Float(lens.zNear)
            let far: Float? = band.far(focus: focus, near: near)
            if let far, GraphDepthBand.moved(from: lastFar, to: far) || Float(lens.zFar) != lastFar {
                lens.zFar = Double(far)
                lastFar = Float(lens.zFar)
            }
            let radius: Float = GraphDepthBand.skyRadius(far: far, near: near, built: builtSky)
            if let sky, GraphDepthBand.moved(from: lastSky, to: radius) {
                sky.simdScale = SIMD3<Float>(radius, radius, radius)
                lastSky = radius
            }
        }

        guard let sim else { return }
        let chosen: Int? = sim.selectedNote
        let toView: simd_float4x4 = pose.inverse * toScene
        for (i, local, _, _) in sim.pickables() where i < bodies.count {
            let inView: SIMD4<Float> = toView * SIMD4<Float>(local.x, local.y, local.z, 1)
            let z: Float = -inView.z
            let isChosen: Bool = chosen == i
            // past the end: not drawn, so not picked
            let gone: Bool = !band.pickable(depth: z, focus: focus)
            if gone != bodies[i].hidden {
                bodies[i].hidden = gone
                bodies[i].gate.isHidden = gone
                hiddenCount += gone ? 1 : -1
            }
            // its name: in the crisp zone, or chosen
            let named: Bool = GraphDepthPills.shows(depth: z, focus: focus, band: band, chosen: isChosen,
                                                    was: bodies[i].named)
            if named != bodies[i].named {
                bodies[i].named = named
                bodies[i].pill.isHidden = !named
            }
            // its extras: gone once mostly faded, back once crisper
            guard !bodies[i].extras.isEmpty, !gone else { continue }
            let f: Float = band.fade(depth: z, focus: focus)
            let keep: Bool = isChosen || GraphDepthDetail.keeps(fade: f, had: bodies[i].kept)
            bodies[i].kept = keep
            let grown: Float = GraphDepthDetail.grown(bodies[i].grown, keep: keep, dt: dt, still: still)
            guard grown != bodies[i].grown else { continue }
            bodies[i].grown = grown
            let size: Float = GraphDepthDetail.size(grown)
            for (node, scale) in bodies[i].extras {
                node.isHidden = size <= 0
                node.simdScale = scale * max(size, 0.001)
            }
        }
    }

    /// What the camera orbits, in the scene's space: the controller's
    /// target when it is ahead of the eye, else the map's middle.
    private func focusPoint(eye: SIMD3<Float>, forward: SIMD3<Float>, toScene: simd_float4x4) -> SIMD3<Float> {
        lock.lock()
        let orbit: SCNCameraController? = controller
        lock.unlock()
        if let orbit {
            let t: SCNVector3 = orbit.target
            let point = SIMD3<Float>(t.x, t.y, t.z)
            let ahead: Float = ((point - eye) * forward).sum()
            if GraphDepthFocus.usable(ahead) { return point }
        }
        let m: SIMD4<Float> = toScene * SIMD4<Float>(middle.x, middle.y, middle.z, 1)
        return SIMD3<Float>(m.x, m.y, m.z)
    }

    /// Notes this frame's time and, twice a second, hands the numbers to
    /// the main thread.
    private func measure(_ now: Double) {
        meter?.tick(now)
        guard now - lastRead >= 0.5, let meter else { return }
        lastRead = now
        let text: String = meter.label(state, drawn: total - hiddenCount, of: total)
        lock.lock()
        let label: UILabel? = readout
        lock.unlock()
        guard let label else { return }
        DispatchQueue.main.async { label.text = text }
    }

    /// Runs `step` once a frame, as an action on its own node in `scene`
    /// (the action keeps the keeper; the keeper keeps nothing).
    static func start(_ keeper: GraphDepthKeeper, in scene: SCNScene) {
        let driver = SCNNode()
        driver.name = "depthFade"
        scene.rootNode.addChildNode(driver)
        let tick = SCNAction.customAction(duration: 1) { _, _ in keeper.step() }
        driver.runAction(SCNAction.repeatForever(tick), forKey: "depthFade")
    }
}

/// Sets the fade going on built scenes, and keeps their keepers by scene so
/// Graph3DView's one line can hand the camera controller to the scene it
/// puts on screen. Main thread.
@MainActor
enum GraphDepth {
    private final class Held {
        weak var keeper: GraphDepthKeeper?
        init(_ keeper: GraphDepthKeeper) { self.keeper = keeper }
    }

    private static var held: [ObjectIdentifier: Held] = [:]

    /// `-graphDepthOff`: the map as it was, for the before pictures.
    static let off: Bool = ProcessInfo.processInfo.arguments.contains("-graphDepthOff")
    /// `-graphDepthMeter`: SceneKit's statistics on screen and the frame
    /// times on "graphDepthMeter", for the measurements.
    static let metered: Bool = ProcessInfo.processInfo.arguments.contains("-graphDepthMeter")

    /// One body as the builder made it: its node (a child of `world`), its
    /// name pill (a child of the node) and its extras (the look's choice).
    struct Made {
        let node: SCNNode
        let label: SCNNode
        var extras: [SCNNode] = []
    }

    /// Sets the fade going on a built scene in `theme` (none for a theme
    /// with no band) at the Graphics tier now: `world` holds the map, `sky`
    /// is the backdrop as built, of radius `skyRadius`, `middle` the map's
    /// middle in the world node's space, `bodies` in GraphSim's order,
    /// `more` the materials not on the map yet (the links', the chosen
    /// body's ring), `tint` the background's colour (sRGB) that solid
    /// things fade toward. Called once the scene is whole, before it is on
    /// screen.
    static func install(theme: GraphTheme, scene: SCNScene, world: SCNNode, camera: SCNNode, sky: SCNNode,
                        skyRadius: Float, middle: SIMD3<Float>, contrast: Bool, still: Bool, sim: GraphSim,
                        bodies: [Made], more: [SCNMaterial], tint: SIMD3<Float>) {
        guard let planned = GraphDepthBand.of(theme, tier: GraphQuality.current.tier, contrast: contrast)
        else { return }
        // where the shader failed its check the map is drawn as before, and
        // the meter says so ("fallback")
        let state: GraphDepthState = GraphDepthState.of(asked: !off, works: off || GraphDepthProbe.latest)
        let band: GraphDepthBand? = state == .on ? planned : nil
        guard band != nil || metered else { return }
        var kept: [GraphDepthKeeper.Body] = []
        var materials: [SCNMaterial] = []
        if let band {
            kept = bodies.map(gate)
            let aim: SIMD3<Float> = world.simdConvertPosition(middle, to: nil)
            let background: SIMD3<Float> = linear(tint)
            for material in Self.materials(under: world, more: more) {
                guard let mode = GraphDepthShader.mode(of: material) else { continue }
                // one with a fragment shader of its own is left as it is
                if let own = material.shaderModifiers?[.fragment], own != GraphDepthShader.fragment { continue }
                GraphDepthShader.dress(material, band: band, mode: mode, tint: background, aim: aim)
                materials.append(material)
            }
        }
        let keeper = GraphDepthKeeper(band: band, state: state, world: world, camera: camera, sky: sky, sim: sim,
                                      builtSky: skyRadius, middle: middle, materials: materials, bodies: kept,
                                      still: still, metered: metered, total: bodies.count)
        held = held.filter { $0.value.keeper != nil }
        held[ObjectIdentifier(scene)] = Held(keeper)
        GraphDepthKeeper.start(keeper, in: scene)
    }

    /// The scene on `view` follows what its camera orbits (nothing for a
    /// scene with no depth fade); with `-graphDepthMeter`, SceneKit's
    /// statistics show and the frame times go on "graphDepthMeter".
    static func follow(_ view: SCNView) {
        guard let scene = view.scene, let keeper = held[ObjectIdentifier(scene)]?.keeper else { return }
        keeper.follow(view.defaultCameraController)
        guard metered else { return }
        view.showsStatistics = true
        keeper.show(on: readout(over: view))
    }

    private static let readoutTag: Int = 0x4F_DE97

    /// The meter's line, over the map near its top: on the window, since
    /// the map's own accessibility elements are its bodies (Graph3DView),
    /// so the UI tests can read it.
    private static func readout(over view: SCNView) -> UILabel {
        let host: UIView = view.window ?? view
        if let found = host.viewWithTag(readoutTag) as? UILabel { return found }
        let made = UILabel(frame: CGRect(x: 8, y: 64, width: max(host.bounds.width - 16, 200), height: 16))
        made.tag = readoutTag
        made.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        made.textColor = .white
        made.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        made.isUserInteractionEnabled = false
        made.accessibilityIdentifier = "graphDepthMeter"
        made.text = "waiting"
        host.addSubview(made)
        return made
    }

    /// Puts everything a body draws but its name in a gate of its own, and
    /// its name in another (each with no transform, so nothing moves).
    private static func gate(_ made: Made) -> GraphDepthKeeper.Body {
        let gate = SCNNode()
        gate.name = "depthGate"
        for child in made.node.childNodes where child !== made.label {
            gate.addChildNode(child)
        }
        made.node.addChildNode(gate)
        let pill = SCNNode()
        pill.name = "depthPill"
        made.node.addChildNode(pill)
        pill.addChildNode(made.label)
        let extras = made.extras.map { (node: $0, scale: $0.simdScale) }
        return GraphDepthKeeper.Body(gate: gate, pill: pill, extras: extras)
    }

    /// Every material under `world` (not the name pills', which are
    /// interface), and `more`, each once.
    private static func materials(under world: SCNNode, more: [SCNMaterial]) -> [SCNMaterial] {
        var seen = Set<ObjectIdentifier>()
        var found: [SCNMaterial] = []
        func add(_ material: SCNMaterial) {
            if seen.insert(ObjectIdentifier(material)).inserted { found.append(material) }
        }
        func visit(_ node: SCNNode) {
            if node is GraphLabelNode { return }
            if let geometry = node.geometry {
                for material in geometry.materials { add(material) }
            }
            for child in node.childNodes { visit(child) }
        }
        visit(world)
        for material in more { add(material) }
        return found
    }

    /// sRGB to linear, as the shader mixes.
    private static func linear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(pow(max(c.x, 0), 2.2), pow(max(c.y, 0), 2.2), pow(max(c.z, 0), 2.2))
    }
}
