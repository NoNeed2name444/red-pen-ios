// The Performance map's view: a Metal view drawn by GraphPerfRenderer, and
// the hands on it.
//
//   one finger    turns the map round its target (and keeps turning a
//                 little after a flick)
//   two fingers   slide it; a pinch comes closer or goes back
//   tap           what is under the finger (GraphPerfScreenBins: the same
//                 rules as the other themes' pick) - a body, or a cluster
//                 drawn as one glow
//   double tap    the same, for opening; on empty space, back to the whole map
//   hold          a body's options
//
// The camera glides (eased, 0.6 s; at once with Reduce Motion) to frame
// the whole map, a cluster, or a body. The chosen body's name sits on a pill
// above it. When nothing moves - no finger, no glide, no spin, the layout
// settled - the view stops drawing until something changes.
//
// Free of Stethoscore types: the theme's glue (GraphPerfTheme.swift) turns
// hits into notes and folders, and the app's settings into a tier.
#if canImport(Metal) && canImport(MetalKit) && canImport(UIKit)
import Foundation
import MetalKit
import QuartzCore
import UIKit

/// What a touch landed on.
enum GraphPerfHit: Equatable {
    /// A body drawn one by one (its index).
    case body(Int)
    /// A cluster drawn as one glow (its index).
    case cluster(Int)
}

@MainActor
final class GraphPerfMapView: UIView, UIGestureRecognizerDelegate {
    let metal: MTKView
    let renderer: GraphPerfRenderer?
    var onTap: (GraphPerfHit?) -> Void = { _ in }
    var onDoubleTap: (GraphPerfHit?) -> Void = { _ in }
    var onHold: (GraphPerfHit, CGPoint) -> Void = { _, _ in }
    var onStats: (GraphPerfStats) -> Void = { _ in }
    /// The part of the view under glass on each side (points); framing fits the rest.
    var insets: (top: Float, left: Float, bottom: Float, right: Float) = (0, 0, 0, 0)
    var reduceMotion: Bool = false
    var preferredFPS: Int = 60 {
        didSet { metal.preferredFramesPerSecond = preferredFPS }
    }

    static let turnRate: Float = 0.006
    static let defaultYaw: Float = 0.55
    static let defaultPitch: Float = 0.32

    private let pill = UILabel()
    private let pillBack = UIView()
    private let unavailable = UILabel()
    private var spin = SIMD2<Float>(0, 0)
    private var glide: (from: GraphPerfCamera, to: GraphPerfCamera, start: CFTimeInterval, duration: Double)?
    private var touching: Int = 0
    private var panTouches: Int = 0
    private var lastBusy: CFTimeInterval = 0
    /// Framed for a map of this many bodies (0: not yet).
    private var framedBodies: Int = 0

    override init(frame: CGRect) {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearDepth = 1
        let sky: SIMD3<Float> = GraphPerfScene.background
        view.clearColor = MTLClearColor(red: Double(sky.x), green: Double(sky.y), blue: Double(sky.z), alpha: 1)
        view.sampleCount = 1
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        metal = view
        renderer = GraphPerfRenderer(view: view)
        super.init(frame: frame)
        backgroundColor = UIColor(red: CGFloat(sky.x), green: CGFloat(sky.y), blue: CGFloat(sky.z), alpha: 1)
        metal.delegate = renderer
        addSubview(metal)
        if renderer == nil {
            unavailable.text = "This device cannot draw the fast map."
            unavailable.textColor = .secondaryLabel
            unavailable.textAlignment = .center
            unavailable.numberOfLines = 0
            addSubview(unavailable)
            metal.isPaused = true
        }
        renderer?.beforeFrame = { [weak self] seconds in self?.advance(seconds) }
        renderer?.onStats = { [weak self] stats in self?.onStats(stats) }
        setUpPill()
        setUpGestures()
        isAccessibilityElement = true
        accessibilityIdentifier = "graph3D"
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metal.frame = bounds
        unavailable.frame = bounds.insetBy(dx: 32, dy: 32)
        if framedBodies == 0, let scene = renderer?.scene, bounds.width > 1, bounds.height > 1 {
            frameWhole(scene, animated: false)
        }
        wake()
    }

    // MARK: - The map

    /// Shows a newly built map. A first map, or one of a very different
    /// size (the demo switched on or off), is framed whole; an edit to the
    /// same map keeps the camera where it is.
    func show(_ scene: GraphPerfScene) {
        guard let renderer else { return }
        renderer.load(scene)
        let bodies: Int = max(scene.bodyCount, 1)
        let changed: Bool = framedBodies == 0 || bodies > 2 * framedBodies || 2 * bodies < framedBodies
        if changed && bounds.width > 1 && bounds.height > 1 {
            frameWhole(scene, animated: false)
        }
        updatePill()
        wake()
    }

    /// Back to the whole map, from the usual angle.
    func recentre() {
        guard let scene = renderer?.scene else { return }
        frameWhole(scene, animated: true)
    }

    /// Frames a cluster's ball (a folder with everything round it).
    func fly(toCluster s: Int) {
        guard let renderer, let scene = renderer.scene, s >= 0, s < scene.clusters.count else { return }
        let reach: Float = s < scene.graph.systemCount ? scene.layout.systemRadius[s] : scene.clusters.ball[s].w
        let centre: SIMD3<Float> = scene.layout.systemCentre[s]
        let goal: GraphPerfCamera = renderer.camera.framing(centre: centre, radius: max(reach, 1),
                                                            width: Float(bounds.width), height: Float(bounds.height),
                                                            insets: insets, fill: 0.88)
        move(to: goal, animated: true)
    }

    /// Brings a body to the middle of the screen above the card, close enough to read.
    func fly(toBody b: Int) {
        guard let renderer, let scene = renderer.scene, let at = renderer.position(b) else { return }
        let near: Float = scene.layout.spacing * 14
        let ball: Float = near * 0.35
        let goal: GraphPerfCamera = renderer.camera.framing(centre: at, radius: ball, width: Float(bounds.width),
                                                            height: Float(bounds.height), insets: insets, fill: 0.9)
        move(to: goal, animated: true)
    }

    func select(_ body: Int?) {
        guard let renderer, renderer.selected != body else { return }
        renderer.selected = body
        updatePill()
        wake()
    }

    func focus(_ body: Int?) {
        guard let renderer, renderer.focus != body else { return }
        renderer.focus = body
        wake()
    }

    func setMask(_ mask: [Bool]?) {
        renderer?.setMask(mask)
        wake()
    }

    func setTier(_ tier: GraphPerfTier, bold: Bool) {
        guard let renderer, renderer.tier != tier || renderer.bold != bold else { return }
        renderer.tier = tier
        renderer.bold = bold
        wake()
    }

    /// Where body `b` is drawn now (nil behind the eye or off screen).
    func screenPoint(of b: Int) -> CGPoint? {
        guard let renderer, let p = renderer.position(b) else { return nil }
        let at = renderer.camera.project(p, width: Float(bounds.width), height: Float(bounds.height))
        guard at.depth > 0, at.x >= 0, at.y >= 0, at.x <= Float(bounds.width), at.y <= Float(bounds.height) else {
            return nil
        }
        return CGPoint(x: CGFloat(at.x), y: CGFloat(at.y))
    }

    /// What is under `point`: the same rules as the other themes' pick.
    func pick(_ point: CGPoint, reach: Float = GraphPerfPick.fingerReach) -> GraphPerfHit? {
        guard let drawn = renderer?.drawnPoints() else { return nil }
        let bins = GraphPerfScreenBins(drawn.points, width: Float(bounds.width), height: Float(bounds.height))
        guard let k = bins.pick(x: Float(point.x), y: Float(point.y), reach: reach), k < drawn.ids.count else {
            return nil
        }
        let id: Int32 = drawn.ids[k]
        return id >= 0 ? .body(Int(id)) : .cluster(Int(-id - 1))
    }

    // MARK: - The camera

    private func frameWhole(_ scene: GraphPerfScene, animated: Bool) {
        guard let renderer, bounds.width > 1, bounds.height > 1 else { return }
        var from: GraphPerfCamera = renderer.camera
        from.yaw = Self.defaultYaw
        from.pitch = Self.defaultPitch
        let goal: GraphPerfCamera = from.framing(centre: scene.centre, radius: scene.radius, width: Float(bounds.width),
                                                 height: Float(bounds.height), insets: insets, fill: 0.9)
        framedBodies = max(scene.bodyCount, 1)
        move(to: goal, animated: animated)
    }

    private func move(to goal: GraphPerfCamera, animated: Bool) {
        guard let renderer else { return }
        spin = .zero
        if animated && !reduceMotion {
            glide = (renderer.camera, goal, CACurrentMediaTime(), 0.6)
        } else {
            glide = nil
            renderer.camera = goal
        }
        wake()
    }

    /// The zoom's reach: from a little over a body's spacing to well outside the map.
    private var zoomLimits: ClosedRange<Float> {
        guard let scene = renderer?.scene else { return 0.5...1_000 }
        let lo: Float = scene.layout.spacing * 1.5
        return lo...max(scene.radius * 8, lo * 2)
    }

    /// Every frame: the glide, the spin, the name pill, and whether to keep drawing.
    private func advance(_ seconds: Double) {
        guard let renderer else { return }
        let now: CFTimeInterval = CACurrentMediaTime()
        if let g = glide {
            let t: Float = Float((now - g.start) / g.duration)
            renderer.camera = GraphPerfCamera.glide(g.from, g.to, t: t)
            if t >= 1 { glide = nil }
        }
        if spin != .zero {
            let dt = Float(seconds)
            renderer.camera.orbit(yaw: spin.x * dt, pitch: spin.y * dt)
            spin *= exp(-3.5 * dt)
            if abs(spin.x) < 0.02 && abs(spin.y) < 0.02 { spin = .zero }
        }
        updatePill()
        let busy: Bool = touching > 0 || glide != nil || spin != .zero || renderer.isSettling
        if busy {
            lastBusy = now
        } else if now - lastBusy > 0.6 {
            metal.isPaused = true
        }
    }

    /// Draw again (something changed).
    func wake() {
        lastBusy = CACurrentMediaTime()
        guard renderer != nil, metal.isPaused else { return }
        renderer?.resumeClock()
        metal.isPaused = false
    }

    // MARK: - The name pill

    private func setUpPill() {
        pillBack.backgroundColor = UIColor(white: 0.04, alpha: 0.86)
        pillBack.layer.cornerRadius = 11
        pillBack.layer.borderWidth = 1
        pillBack.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        pillBack.isUserInteractionEnabled = false
        pillBack.isHidden = true
        pill.font = UIFont.preferredFont(forTextStyle: .footnote)
        pill.textColor = .white
        pill.textAlignment = .center
        pillBack.addSubview(pill)
        addSubview(pillBack)
    }

    private func updatePill() {
        guard let renderer, let scene = renderer.scene, let chosen = renderer.selected,
              let at = screenPoint(of: chosen) else {
            pillBack.isHidden = true
            return
        }
        let title: String = scene.title(chosen)
        if pill.text != title {
            pill.text = title
            pill.sizeToFit()
        }
        let width: CGFloat = min(pill.bounds.width + 20, bounds.width - 24)
        let height: CGFloat = pill.bounds.height + 8
        pillBack.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        pill.frame = CGRect(x: 10, y: 4, width: width - 20, height: height - 8)
        let above: CGFloat = 26
        let x: CGFloat = min(max(at.x, width / 2 + 12), bounds.width - width / 2 - 12)
        pillBack.center = CGPoint(x: x, y: max(at.y - above, height / 2 + 4))
        pillBack.isHidden = false
    }

    // MARK: - Hands

    private func setUpGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
        let twice = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        twice.numberOfTapsRequired = 2
        twice.delegate = self
        addGestureRecognizer(twice)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.5
        hold.delegate = self
        addGestureRecognizer(hold)
    }

    /// A pan with a pinch, and a tap with a double tap, run together: choosing is instant.
    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        let pair: Bool = (gesture is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
            || (gesture is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
        let taps: Bool = gesture is UITapGestureRecognizer && other is UITapGestureRecognizer
        return pair || taps
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let renderer else { return }
        switch gesture.state {
        case .began:
            touching += 1
            glide = nil
            spin = .zero
            panTouches = gesture.numberOfTouches
            gesture.setTranslation(.zero, in: self)
        case .changed:
            let moved: CGPoint = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            // a finger joined or left: the centre jumped, so skip this move
            if gesture.numberOfTouches != panTouches {
                panTouches = gesture.numberOfTouches
                break
            }
            if panTouches >= 2 {
                renderer.camera.pan(dx: Float(moved.x), dy: Float(moved.y), viewHeight: Float(bounds.height))
            } else {
                renderer.camera.orbit(yaw: -Float(moved.x) * Self.turnRate, pitch: Float(moved.y) * Self.turnRate)
            }
        case .ended, .cancelled, .failed:
            touching = max(touching - 1, 0)
            if panTouches == 1 && gesture.state == .ended && !reduceMotion {
                let v: CGPoint = gesture.velocity(in: self)
                spin = SIMD2(-Float(v.x) * Self.turnRate, Float(v.y) * Self.turnRate)
                let fastest: Float = 6
                spin = SIMD2(min(max(spin.x, -fastest), fastest), min(max(spin.y, -fastest), fastest))
            }
        default:
            break
        }
        wake()
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard let renderer else { return }
        switch gesture.state {
        case .began:
            touching += 1
            glide = nil
            spin = .zero
        case .changed:
            renderer.camera.zoom(by: Float(gesture.scale), limits: zoomLimits)
            gesture.scale = 1
        case .ended, .cancelled, .failed:
            touching = max(touching - 1, 0)
        default:
            break
        }
        wake()
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        wake()
        onTap(pick(gesture.location(in: self)))
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        wake()
        let hit: GraphPerfHit? = pick(gesture.location(in: self))
        if hit == nil { recentre() }
        onDoubleTap(hit)
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point: CGPoint = gesture.location(in: self)
        guard let hit = pick(point) else { return }
        onHold(hit, point)
    }
}
#endif
