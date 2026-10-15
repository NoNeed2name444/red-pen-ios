import SceneKit
import UIKit
import simd

// MARK: - The depth fade, on SceneKit
//
// The SceneKit half of GraphDepthFade.swift (plan 4f,
// docs/design/depth-fade.md), for any scene the theme builder or the
// Universe builder makes. Once a frame, on the render thread, the keeper
// reads where the camera is and what it orbits - SceneKit's camera
// controller's target, which Graph3DView hands over when the scene goes on
// screen (GraphDepth.follow); the map's middle until then - and when the
// focus's depth along the view has moved, sets the band again:
//
// - SceneKit's fog, from the band's start to its end with its exponent,
//   toward black: light added to what is behind it, mixed toward nothing,
//   dissolves into exactly what is behind it, never a veil over the glows;
// - the backdrop kept inside where the fog starts, so the fog never
//   touches it (it is drawn first and writes no depth, so its radius
//   changes nothing else).
//
// It runs as an action on a node of its own rather than in a look's
// ticker, which a still map (Reduce Motion) does not have: the fade is not
// motion, so it follows the camera either way. A still camera writes
// nothing.

/// Keeps one scene's depth fade on the camera's focus. Built on the main
/// thread; `step` runs on the render thread, `follow` on the main thread.
nonisolated final class GraphDepthKeeper: @unchecked Sendable {
    let band: GraphDepthBand
    private weak var scene: SCNScene?
    private weak var world: SCNNode?
    private weak var camera: SCNNode?
    private weak var sky: SCNNode?
    /// The backdrop's radius as the scene was built.
    private let builtSky: Float
    /// The map's middle in the world node's space: the focus until the
    /// camera controller is handed over.
    private let middle: SIMD3<Float>
    private let lock = NSLock()
    /// The view's camera controller: what the camera orbits. Under the lock.
    private weak var controller: SCNCameraController?
    /// The focus's depth last written. Render thread only.
    private var shown: Float = -1

    init(band: GraphDepthBand, scene: SCNScene, world: SCNNode, camera: SCNNode, sky: SCNNode,
         builtSky: Float, middle: SIMD3<Float>) {
        self.band = band
        self.scene = scene
        self.world = world
        self.camera = camera
        self.sky = sky
        self.builtSky = builtSky
        self.middle = middle
        // toward nothing, as strong as the band goes (Increase Contrast:
        // short of it)
        scene.fogColor = UIColor(white: 0, alpha: CGFloat(band.most))
    }

    /// What the camera orbits from now on (main thread).
    func follow(_ controller: SCNCameraController) {
        lock.lock()
        self.controller = controller
        lock.unlock()
    }

    /// The focus's depth along the view now. Render thread.
    func focusDepth() -> Float? {
        guard let camera else { return nil }
        let pose: simd_float4x4 = camera.presentation.simdWorldTransform
        let eye = SIMD3<Float>(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
        let forward = SIMD3<Float>(-pose.columns.2.x, -pose.columns.2.y, -pose.columns.2.z)
        lock.lock()
        let orbit: SCNCameraController? = controller
        lock.unlock()
        let target: SIMD3<Float>
        if let orbit {
            let t: SCNVector3 = orbit.target
            target = SIMD3<Float>(t.x, t.y, t.z)
        } else if let world {
            target = world.presentation.simdConvertPosition(middle, to: nil)
        } else {
            return nil
        }
        return GraphDepthFocus.depth(eye: eye, forward: forward, target: target)
    }

    /// Sets the band for this frame's focus, when it moved. Render thread.
    func step() {
        guard let focus = focusDepth(), GraphDepthBand.moved(from: shown, to: focus) else { return }
        shown = focus
        guard let scene else { return }
        let fog = band.fog(focus: focus)
        scene.fogStartDistance = CGFloat(fog.start)
        scene.fogEndDistance = CGFloat(fog.end)
        scene.fogDensityExponent = CGFloat(fog.exponent)
        if let sky {
            let near: Float = Float(camera?.camera?.zNear ?? 0.01)
            let radius: Float = band.skyRadius(focus: focus, near: near, built: builtSky)
            sky.simdScale = SIMD3<Float>(radius, radius, radius)
        }
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

    /// Sets the fade going on a built scene in `theme` (none for a theme
    /// with no band) at the Graphics tier now: `world` holds the map,
    /// `sky` is the backdrop as built, of radius `skyRadius`, and `middle`
    /// the map's middle in the world node's space.
    static func install(theme: GraphTheme, scene: SCNScene, world: SCNNode, camera: SCNNode, sky: SCNNode,
                        skyRadius: Float, middle: SIMD3<Float>, contrast: Bool) {
        guard let band = GraphDepthBand.of(theme, tier: GraphQuality.current.tier, contrast: contrast) else { return }
        let keeper = GraphDepthKeeper(band: band, scene: scene, world: world, camera: camera, sky: sky,
                                      builtSky: skyRadius, middle: middle)
        held = held.filter { $0.value.keeper != nil }
        held[ObjectIdentifier(scene)] = Held(keeper)
        GraphDepthKeeper.start(keeper, in: scene)
    }

    /// The scene on `view` follows what its camera orbits (nothing for a
    /// scene with no depth fade).
    static func follow(_ view: SCNView) {
        guard let scene = view.scene, let keeper = held[ObjectIdentifier(scene)]?.keeper else { return }
        keeper.follow(view.defaultCameraController)
    }
}
