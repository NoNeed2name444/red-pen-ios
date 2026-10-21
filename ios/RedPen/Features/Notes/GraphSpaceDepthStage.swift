#if canImport(SceneKit) && canImport(UIKit)
import SceneKit
import UIKit
import simd

/// The Space theme's depth fade and near-only loading on the live scene
/// (SpaceDepth has the numbers, docs/design/depth-fade.md the look). Made
/// with the scene; GraphSim runs it once a frame on the render thread,
/// under its lock, before anything is animated:
///
/// - the band follows the camera's focus, and every Space shader is handed
///   it (rpFade) with the focal length for its detail by size (rpFocal);
/// - each body gets a level: its whole look; a point in its colour when it
///   is too small on screen for its look to show; or gone, when it is
///   outside the view or past the band's end. A gone body and a point's
///   hidden look are neither drawn nor animated (GraphSim skips them);
///   their positions still move on, so they are right when they return;
/// - a body nearly faded dissolves the last of the way (SpaceDepthBand.
///   dissolve), so it never ends as a dark disc on a bright patch of sky;
/// - names show only in the crisp zone, and nothing past the band can be
///   picked. The chosen body is always kept: it is drawn whole and keeps
///   its name wherever it is.
///
/// Neurons and the plain looks have none (GraphSimLooks.depth is nil).
nonisolated final class GraphSpaceDepthStage: @unchecked Sendable {
    private let nodes: [SCNNode]
    /// Each body's own pieces (every child but its name and its point).
    private let looks: [[SCNNode]]
    /// Each body's point, a child of its node (hidden until needed).
    private let points: [SCNNode]
    private let radius: [Float]
    private let reach: [Float]
    /// Every Space shader material: handed the band and the focal length.
    private let materials: [SCNMaterial]
    private let tier: GraphicsTier
    private let contrast: Bool

    /// Per body, this frame: its level, whether it is past the band, in
    /// the crisp zone, and the opacity its node was last given.
    private(set) var level: [SpaceBodyLevel]
    private(set) var pastBand: [Bool]
    private(set) var crisp: [Bool]
    /// Whose look GraphSim may animate this frame (level .body).
    private(set) var drawn: [Bool]
    private var shownOpacity: [Float]
    private var shownLevel: [SpaceBodyLevel?]
    private(set) var band: SpaceDepthBand = .off
    private var shownUniform = SIMD4<Float>(-1, -1, -1, -1)
    private var shownFocal: Float = -1

    /// `colours`: each body's colour as a point (its GraphShine colour);
    /// `codes`: its GraphNodeStyle code. Main thread.
    @MainActor
    init(nodes: [SCNNode], labels: [SCNNode], radius: [Float], codes: [Int], colours: [GraphRGB],
         materials: [SCNMaterial], tier: GraphicsTier, contrast: Bool) {
        self.nodes = nodes
        self.radius = radius
        self.reach = codes.map { SpaceDepth.reachOfLook(styleCode: $0) }
        self.materials = materials
        self.tier = tier
        self.contrast = contrast
        var lookList: [[SCNNode]] = []
        var pointList: [SCNNode] = []
        var shapes: [String: SCNGeometry] = [:]
        for (i, node) in nodes.enumerated() {
            let label: SCNNode? = i < labels.count ? labels[i] : nil
            lookList.append(node.childNodes.filter { $0 !== label })
            let c: GraphRGB = i < colours.count ? colours[i] : GraphShine.dark.colour
            let key: String = String(format: "%.3f,%.3f,%.3f", c.r, c.g, c.b)
            let shape: SCNGeometry
            if let made = shapes[key] {
                shape = made
            } else {
                shape = Self.pointShape(c)
                shapes[key] = shape
            }
            let point = SCNNode(geometry: shape)
            point.name = "depthPoint"
            point.categoryBitMask = 2
            point.renderingOrder = 6
            point.isHidden = true
            node.addChildNode(point)
            pointList.append(point)
        }
        looks = lookList
        points = pointList
        let n: Int = nodes.count
        level = [SpaceBodyLevel](repeating: .body, count: n)
        pastBand = [Bool](repeating: false, count: n)
        crisp = [Bool](repeating: true, count: n)
        drawn = [Bool](repeating: true, count: n)
        shownOpacity = [Float](repeating: 1, count: n)
        shownLevel = [SpaceBodyLevel?](repeating: nil, count: n)
    }

    /// The stage for a Space scene's bodies: `materials` every Space
    /// shader material in it (shared and per owner), `contrast` Increase
    /// Contrast. The Graphics tier sets how far the band reaches.
    @MainActor
    static func make(infos: [GraphNodeInfo], materials: [SCNMaterial], contrast: Bool) -> GraphSpaceDepthStage {
        GraphSpaceDepthStage(nodes: infos.map(\.node), labels: infos.map(\.label), radius: infos.map(\.radius),
                             codes: infos.map { $0.style.code }, colours: infos.map { $0.shine.colour },
                             materials: materials, tier: GraphQuality.current.tier, contrast: contrast)
    }

    /// A point: a small sphere of flat colour, added to what is behind it
    /// (light, so it fades to nothing), never hiding anything.
    @MainActor
    private static func pointShape(_ c: GraphRGB) -> SCNGeometry {
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 8
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
        material.blendMode = .add
        material.writesToDepthBuffer = false
        sphere.materials = [material]
        return sphere
    }

    /// The camera this frame, in the world's coordinates (the node every
    /// body hangs from): its eye and unit axes, vertical field of view
    /// (radians), the view's size in points, the focus (world
    /// coordinates), each body's position, which bodies the
    /// filter shows, which are ghosts, and the chosen body. Render thread,
    /// under GraphSim's lock.
    func update(eye: SIMD3<Float>, forward: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>, fovY: Float,
                width: Float, height: Float, focus: SIMD3<Float>, position: [SIMD3<Float>],
                visible: [Bool], ghost: [Bool], chosen: Int?) {
        let focusDepth: Float = SpaceDepth.depth(of: focus, eye: eye, forward: forward)
        band = SpaceDepth.band(focusDepth: focusDepth, tier: tier, contrast: contrast)
        let focal: Float = SpaceDepth.focal(viewHeight: height, fovY: fovY)
        handOver(band.uniform, focal: focal)
        let far: Float = band.culls ? band.end * 1.5 : 1e9
        let view: GraphPerfFrustum = SpaceDepth.frustum(eye: eye, forward: forward, right: right, up: up,
                                                         fovY: fovY, width: width, height: height, near: 0.001,
                                                         far: far)
        for i in nodes.indices {
            let depth: Float = SpaceDepth.depth(of: position[i], eye: eye, forward: forward)
            // the level goes by the body's own size, not its pop (an
            // animation), which its node's scale already carries
            let size: Float = radius[i]
            let kept: Bool = i == chosen
            let gone: Bool = !kept && band.gone(depth)
            let inView: Bool = kept || SpaceDepth.inView(view, centre: position[i], radius: size, reach: reach[i])
            let px: Float = GraphPerfLOD.pixelRadius(size, depth: depth, focal: focal)
            let fade: Float = band.fade(depth)
            var now: SpaceBodyLevel = SpaceDepth.level(level[i], pixelRadius: px, fade: fade, gone: gone,
                                                       inView: inView)
            if kept { now = .body }
            level[i] = now
            pastBand[i] = gone
            crisp[i] = band.crisp(depth)
            drawn[i] = now == .body
            guard visible[i] else { continue }
            show(i, now)
            // the last of the dissolve, on the whole body; a ghost (a
            // hidden planet kept for its moons) stays at its 0.3
            let dissolve: Float = kept ? 1 : band.dissolve(depth)
            let opacity: Float = (ghost[i] ? 0.3 : 1) * dissolve
            if abs(opacity - shownOpacity[i]) > 0.01 || (opacity == 1) != (shownOpacity[i] == 1) {
                shownOpacity[i] = opacity
                nodes[i].opacity = CGFloat(opacity)
            }
            if now == .point {
                // the point at the body's own size on screen, its light
                // fading with the band as any glow's does
                let r: Float = SpaceDepth.pointRadius(pixelRadius: px) * max(depth, 0.001) / max(focal, 0.001)
                points[i].simdScale = SIMD3<Float>(r, r, r)
                points[i].opacity = CGFloat(band.light(depth))
            }
        }
    }

    /// Shows body `i` at `now`: its look, its point or neither. Only on a
    /// change.
    private func show(_ i: Int, _ now: SpaceBodyLevel) {
        guard shownLevel[i] != now else { return }
        shownLevel[i] = now
        let whole: Bool = now == .body
        for piece in looks[i] where piece.isHidden == whole {
            piece.isHidden = !whole
        }
        points[i].isHidden = now != .point
    }

    /// The band and focal length, to every Space shader, when they change.
    private func handOver(_ uniform: SIMD4<Float>, focal: Float) {
        let moved: Bool = simd_length(uniform - shownUniform) > max(simd_length(uniform), 1) * 0.0005
        if moved {
            shownUniform = uniform
            let v = SCNVector4(x: uniform.x, y: uniform.y, z: uniform.z, w: uniform.w)
            let value = NSValue(scnVector4: v)
            for material in materials { material.setValue(value, forKey: "rpFade") }
        }
        if abs(focal - shownFocal) > 0.5 {
            shownFocal = focal
            let value = NSNumber(value: focal)
            for material in materials { material.setValue(value, forKey: "rpFocal") }
        }
    }
}
#endif
