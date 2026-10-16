import Foundation

// MARK: - The depth fade in the 3D map's SceneKit themes
//
// The owner, 15 Oct (about 8:35 am): "u know how deep see videos or cell 3d
// high quality videos have fade for far objects ? that's how i want
// performance mode to be and also all other modes too to run smoother."
// The rules are docs/design/depth-fade.md (plan 4f); this is the numbers
// and the maths for the two SceneKit themes, Neurons and Space (the
// Performance theme draws its own in Metal).
//
// Near the camera a body is crisp; with distance it loses its light and
// dissolves into the theme's own background (the Neurons' tissue fluid,
// Space's near-black sky), until it is gone. Depth is along the view
// (view-space z), and the band follows the focus: it starts behind what
// the camera looks at (its orbit target, or the body it flew to) and is
// measured in multiples of that depth, so flown in close to a small note
// inside a cell the fade looks the same as over the whole map. Turning the
// map brings the far side forward and it sharpens, with no timers: the
// fade is worked out from where things are.
//
// The band is measured in the framing's reach (T0057): each framing (the
// tilted default view, or a fly-in) records R, how far past the focus its
// deepest point lies, and the fade runs over shares of it, a straight ramp
//     f = clamp((z - from) / (to - from), 0, 1) × most,
// from = F·(1 + c), to = F·(1 + c + (b - a)·R), c the crisp reach. The
// Neurons fade per pixel, by a specialised shader of our own on every
// material (all added light); Space fades per body - each body's gate goes
// to opacity 1 - f, hidden at f = 1 - with only its links, far lines and
// the chosen body's ring and disk on the shader. Light added to what is
// behind it fades to nothing, see-through things go see-through, and
// nothing is mixed toward a tint, so a body dissolves into whatever lies
// behind it (GraphDepthMode).
//
// The Graphics setting sets how far the band reaches: Smooth pulls its end
// in, so less is drawn. Past the end everything is fully faded, so it is
// not drawn (the camera's far plane, and each body hidden) and cannot be
// picked; fly-to, search and the filter still reach any body, since flying
// to it brings it into the crisp zone. Increase Contrast starts the fade
// later and stops it short of the background, so far bodies stay
// distinguishable (and nothing is culled). Reduce Motion changes nothing:
// the fade is not motion.
//
// Inside the band detail drops (GraphDepthDetail), only where a body is
// mostly faded already and with hysteresis, and by shrinking away rather
// than fading; and name pills, being interface, never half-fade: one shows
// only in the crisp zone, or for the chosen body (GraphDepthPills).
//
// Foundation only, tested on Linux (Tests/GraphDepthTests.swift); the
// SceneKit half is GraphDepthKeeper.swift.

/// Where a framing leaves the map, for the band (T0057): its reach R, the
/// deepest framed point's view depth over the focus's, less 1 (kept within
/// GraphTilt.reachRange), and how much of it stays crisp: in the whole view
/// the band's own share of it (nil, a·R), flown in all of it and a little
/// more (R + 0.02), so the flown system is crisp.
nonisolated struct GraphDepthFrame: Sendable, Equatable {
    let reach: Float
    let crisp: Float?

    init(reach: Float, crisp: Float?) {
        let range: ClosedRange<Float> = GraphTilt.reachRange
        self.reach = reach.isFinite ? min(max(reach, range.lowerBound), range.upperBound) : range.upperBound
        self.crisp = crisp
    }

    /// The fly-in's margin past its deepest point.
    static let flyMargin: Float = 0.02

    static func whole(_ reach: Float) -> GraphDepthFrame { GraphDepthFrame(reach: reach, crisp: nil) }
    static func fly(_ reach: Float) -> GraphDepthFrame {
        let r: Float = GraphDepthFrame(reach: reach, crisp: nil).reach
        return GraphDepthFrame(reach: r, crisp: r + flyMargin)
    }
}

/// How a theme's map fades with depth, at one Graphics tier: as shares of
/// the framing's reach (GraphDepthFrame), so the band fits whatever the
/// framing shows - the far edge of the tilted default view, or a flown-in
/// system - and follows the focus F through glides and pinches.
nonisolated struct GraphDepthBand: Sendable, Equatable {
    /// Where the fade starts (a) and ends (b), as shares of the reach R
    /// past the focus: the span runs from F·(1 + c) to F·(1 + c + (b - a)·R),
    /// c the crisp reach (a·R in the whole view).
    let a: Float
    let b: Float
    /// The curve's power: 1, a straight ramp (the shader then needs no pow).
    let k: Float
    /// How far the fade goes: 1 all the way into the background; less
    /// with Increase Contrast.
    let most: Float

    /// The Neurons: on High the far edge of the default view is faded 0.94
    /// and nothing is culled; Smooth culls past 0.9 of the reach.
    static let neuronsHigh = GraphDepthBand(a: 0.20, b: 1.05, k: 1, most: 1)
    static let neuronsSmooth = GraphDepthBand(a: 0.20, b: 0.90, k: 1, most: 1)
    /// Space culls its far strip in every default view: past 0.85 of the
    /// reach on High, 0.75 on Smooth, so less is drawn.
    static let spaceHigh = GraphDepthBand(a: 0.20, b: 0.85, k: 1, most: 1)
    static let spaceSmooth = GraphDepthBand(a: 0.20, b: 0.75, k: 1, most: 1)

    /// Increase Contrast: a and b this much later (a fly-in's band this
    /// much wider), and fading at most this far, so a far body keeps four
    /// tenths of its light; nothing is culled.
    static let contrastLater: Float = 1.35
    static let contrastMost: Float = 0.6

    /// The focus's depth is never taken as less than this (a target at
    /// or behind the eye).
    static let nearestFocus: Float = 0.0005

    /// A theme's band at a tier, with Increase Contrast or not; nil for
    /// Performance, which fades in its own Metal engine.
    static func of(_ theme: GraphTheme, tier: GraphicsTier, contrast: Bool) -> GraphDepthBand? {
        let base: GraphDepthBand
        switch theme {
        case .neurons: base = tier == .high ? neuronsHigh : neuronsSmooth
        case .space: base = tier == .high ? spaceHigh : spaceSmooth
        case .performance: return nil
        }
        guard contrast else { return base }
        return GraphDepthBand(a: base.a * contrastLater, b: base.b * contrastLater, k: base.k, most: contrastMost)
    }

    /// Whether the fade goes all the way, so what is past the end is gone.
    var culls: Bool { most >= 1 }

    /// The focus's depth as the band uses it.
    static func focus(_ depth: Float) -> Float {
        guard depth.isFinite else { return nearestFocus }
        return max(depth, nearestFocus)
    }

    /// Where the fade starts and ends (view depth) for a focus at `focus`
    /// in `frame`.
    func span(focus: Float, frame: GraphDepthFrame) -> (start: Float, end: Float) {
        let d: Float = Self.focus(focus)
        let c: Float = frame.crisp ?? a * frame.reach
        let from: Float = d * (1 + c)
        return (from, from + d * max(b - a, 0.000_01) * frame.reach)
    }

    /// The three numbers the shader is given (`rpDepthSpan`): where the
    /// fade starts, one over its width, and how far it goes.
    func uniform(focus: Float, frame: GraphDepthFrame) -> SIMD3<Float> {
        let (from, to): (Float, Float) = span(focus: focus, frame: frame)
        return SIMD3<Float>(from, 1 / max(to - from, 0.000_001), most)
    }

    /// How far along the band depth `z` is, 0 to 1, before the curve.
    func along(depth z: Float, focus: Float, frame: GraphDepthFrame) -> Float {
        let (from, to): (Float, Float) = span(focus: focus, frame: frame)
        guard z.isFinite else { return 1 }
        let width: Float = max(to - from, 0.000_001)
        return min(max((z - from) / width, 0), 1)
    }

    /// The fade at view depth `z` with the focus at depth `focus`: 0 crisp
    /// up to the band's start, `most` from its end on.
    func fade(depth z: Float, focus: Float, frame: GraphDepthFrame) -> Float {
        let t: Float = along(depth: z, focus: focus, frame: frame)
        guard t > 0 else { return 0 }
        return (k == 1 ? t : pow(t, k)) * most
    }

    /// How much of a body's light is left at depth `z`: 1 - f.
    func light(depth z: Float, focus: Float, frame: GraphDepthFrame) -> Float {
        1 - fade(depth: z, focus: focus, frame: frame)
    }

    /// Where nothing is drawn any more: the band's end, where everything is
    /// fully faded; nil when the fade stops short (Increase Contrast).
    func cull(focus: Float, frame: GraphDepthFrame) -> Float? {
        guard culls else { return nil }
        return span(focus: focus, frame: frame).end
    }

    /// Whether a body at depth `z` is drawn and can be picked: not when it
    /// is past the band's end.
    func pickable(depth z: Float, focus: Float, frame: GraphDepthFrame) -> Bool {
        guard let far = cull(focus: focus, frame: frame) else { return true }
        return z < far
    }

    /// The camera's far plane: the band's end, never closer than four near
    /// planes; nil when nothing is culled and the scene's own far plane
    /// stays.
    func far(focus: Float, near: Float, frame: GraphDepthFrame) -> Float? {
        guard let end = cull(focus: focus, frame: frame) else { return nil }
        return max(end, near * 4)
    }

    /// The backdrop's radius under a far plane at `far` (nil: the scene's
    /// own): half way to it, so the far plane never clips it, and clear of
    /// the near plane; never past `built`, its radius as the scene made it.
    static func skyRadius(far: Float?, near: Float, built: Float) -> Float {
        guard let far else { return built }
        let clear: Float = max(near * 2, 0.000_01)
        return max(min(built, far * 0.5), clear)
    }

    /// Whether a depth moved enough since `shown` to write it again (one
    /// part in five hundred), so a still camera writes nothing.
    static func moved(from shown: Float, to now: Float) -> Bool {
        guard shown > 0, shown.isFinite else { return true }
        return abs(now - shown) > shown * 0.002
    }

    /// A body's opacity at fade `f` (Space fades per body): 1 - f, written
    /// again only once it moves by a step of 1/255 or more.
    static func opacity(fade f: Float) -> Float { min(max(1 - f, 0), 1) }
    static func stepped(from shown: Float, to now: Float) -> Bool {
        abs(now - shown) >= 1.0 / 255 - 0.000_001 || (now == 0) != (shown == 0) || (now == 1) != (shown == 1)
    }
}

/// The focus's depth along the view: how far ahead of the eye the orbit
/// target is (its view-space depth), never less than the band's nearest.
nonisolated enum GraphDepthFocus {
    static func depth(eye: SIMD3<Float>, forward: SIMD3<Float>, target: SIMD3<Float>) -> Float {
        let length: Float = (forward * forward).sum().squareRoot()
        guard length > 0.000_001, length.isFinite else { return GraphDepthBand.nearestFocus }
        let ahead: SIMD3<Float> = target - eye
        let z: Float = (ahead * forward).sum() / length
        return GraphDepthBand.focus(z)
    }

    /// Whether a target at depth `z` can stand as the focus: in front of
    /// the eye by more than the band's nearest. Otherwise the map's middle
    /// does.
    static func usable(_ z: Float) -> Bool {
        z.isFinite && z > GraphDepthBand.nearestFocus * 2
    }
}

/// A link chip's glide (Graph3DView's ease(to:glide:)): the chip's body is
/// brought to the middle of what the card leaves, and never deeper than
/// what the camera looks at, so it lands in the crisp zone. Worked out from
/// where the body is, not from where it is drawn, since past the band's end
/// it is not drawn at all (plan 4f). The camera and what it orbits move
/// together by `move`, so the focus stays as deep as it was, and the body
/// sits on the line of sight through the goal: at its own depth when it is
/// nearer than the focus (the glide as it always was), else at the focus's.
nonisolated enum GraphDepthGlide {
    /// How far the camera (and its orbit target with it) moves: `body` the
    /// chip's body, `eye` the camera, `sight` any point on the line of sight
    /// through the goal on screen, `forward` the camera's facing, `target`
    /// what it orbits. Nil when the goal's line of sight does not go ahead
    /// of the eye, or neither the body nor the target is ahead of it.
    static func move(body: SIMD3<Float>, eye: SIMD3<Float>, sight: SIMD3<Float>, forward: SIMD3<Float>,
                     target: SIMD3<Float>) -> SIMD3<Float>? {
        let line: SIMD3<Float> = sight - eye
        let lineLength: Float = (line * line).sum().squareRoot()
        let facing: Float = (forward * forward).sum().squareRoot()
        guard lineLength > 0.000_001, facing > 0.000_001, lineLength.isFinite, facing.isFinite else { return nil }
        let ray: SIMD3<Float> = line / lineLength
        let ahead: SIMD3<Float> = forward / facing
        let along: Float = (ray * ahead).sum()
        guard along > 0.000_1 else { return nil }
        let own: Float = ((body - eye) * ahead).sum()
        let focus: Float = ((target - eye) * ahead).sum()
        let depth: Float
        switch (GraphDepthFocus.usable(own), GraphDepthFocus.usable(focus)) {
        case (true, true): depth = min(own, focus)
        case (true, false): depth = own
        case (false, true): depth = focus
        case (false, false): return nil
        }
        let arrive: SIMD3<Float> = body - ray * (depth / along)
        let move: SIMD3<Float> = arrive - eye
        guard move.x.isFinite, move.y.isFinite, move.z.isFinite else { return nil }
        return move
    }
}

/// How one material fades, as the shader reads it. Nothing is mixed toward
/// a tint (T0057): a body dissolves into whatever lies behind it.
nonisolated enum GraphDepthMode: Float, Sendable, CaseIterable {
    /// Light added to what is behind it: its contribution times (1 - f),
    /// so it dissolves into exactly what is behind it.
    case light = 0
    /// Laid over what is behind it and see-through: colour and coverage
    /// times (1 - f), the same. An opaque material is made see-through
    /// (blended, no depth write) before it is given the shader.
    case see = 1

    /// A material's mode from how it is drawn: added (or screened,
    /// subtracted, maxed: each fades to no effect as it dims), else laid
    /// over and see-through.
    static func of(adds: Bool) -> GraphDepthMode { adds ? .light : .see }

    /// What one channel becomes at fade `f`, from `value` with coverage
    /// `alpha`: the shader's arithmetic.
    func apply(_ value: Float, alpha: Float, fade f: Float) -> (value: Float, alpha: Float) {
        switch self {
        case .light: return (value * (1 - f), alpha)
        case .see: return (value * (1 - f), alpha * (1 - f))
        }
    }
}

/// The depth fade's fragment shader, specialised: the mode, the curve and
/// how far it goes compiled in, and only the span (`rpDepthSpan`: where the
/// fade starts, one over its width, its most) given by the CPU when the
/// focus or the framing moves. No matrix, and no pow for a straight ramp.
nonisolated enum GraphDepthShaderText {
    /// What marks a fragment shader as the fade's own.
    static let marker: String = "// rp-depth"

    static func fragment(mode: GraphDepthMode, most: Float, k: Float) -> String {
        let ramp: String = "saturate((-_surface.position.z - rpDepthSpan.x) * rpDepthSpan.y)"
        let curved: String = k == 1 ? ramp : "pow(\(ramp), \(literal(k)))"
        let faded: String = most == 1 ? curved : "\(curved) * rpDepthSpan.z"
        let apply: String = mode == .light ? "_output.color.rgb *= (1.0 - rpDepthFade);"
                                           : "_output.color *= (1.0 - rpDepthFade);"
        return """
        \(marker) \(mode == .light ? "light" : "see")
        #pragma arguments
        float3 rpDepthSpan;

        #pragma body
        float rpDepthFade = \(faded);
        \(apply)
        """
    }

    /// The shader's formula in Swift, for the checks: f at view depth `z`
    /// for a span (from, 1/width, most).
    static func evaluate(depth z: Float, span: SIMD3<Float>, k: Float) -> Float {
        let t: Float = min(max((z - span.x) * span.y, 0), 1)
        return (k == 1 ? t : pow(t, k)) * span.z
    }

    private static func literal(_ v: Float) -> String { String(format: "%.4f", v) }
}

/// Detail inside the band: a body's extras (its halo, the glow of arriving
/// impulses, its finer dendrites) go only once it is mostly faded, and come
/// back only once it is clearly crisper, so a body on the line never
/// flickers. Each change morphs - the extras shrink away or grow back over
/// a quarter of a second - never cross-fades; with Reduce Motion it is at
/// once (they are mostly faded by then).
nonisolated enum GraphDepthDetail {
    /// Extras go at this fade or more.
    static let drop: Float = 0.62
    /// And come back at this fade or less.
    static let restore: Float = 0.5
    /// How long they take to shrink away or grow back (seconds).
    static let morph: Float = 0.25

    /// Whether a body keeps its extras at fade `f`, having had them or not.
    static func keeps(fade f: Float, had: Bool) -> Bool {
        had ? f < drop : f <= restore
    }

    /// How grown the extras are (0 gone, 1 whole) after `dt` seconds going
    /// toward kept or gone from `now`; at once when `still`.
    static func grown(_ now: Float, keep: Bool, dt: Float, still: Bool) -> Float {
        let goal: Float = keep ? 1 : 0
        guard !still, dt.isFinite else { return goal }
        let step: Float = max(dt, 0) / morph
        return keep ? min(now + step, 1) : max(now - step, 0)
    }

    /// Their size at `grown` (0 to 1): eased in and out, so the morph
    /// neither starts nor stops with a jolt.
    static func size(_ grown: Float) -> Float {
        let t: Float = min(max(grown, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Name pills are interface, so they never half-fade: a pill shows only for
/// a body with no fade at all, or the chosen one wherever it is drawn; a
/// shown pill stays until its body's fade reaches `lingerFade`, so one on
/// the line does not flicker. Pills sit outside the body's gate, so the
/// gate's opacity never reaches them.
nonisolated enum GraphDepthPills {
    /// A shown pill stays while its body's fade is below this.
    static let lingerFade: Float = 0.04

    static func shows(depth z: Float, focus: Float, frame: GraphDepthFrame, band: GraphDepthBand, chosen: Bool,
                      was: Bool) -> Bool {
        guard band.pickable(depth: z, focus: focus, frame: frame) else { return false }
        if chosen { return true }
        let f: Float = band.fade(depth: z, focus: focus, frame: frame)
        return f == 0 || (was && f < lingerFade)
    }
}

/// Frame times for the before-and-after measurements: the gaps between
/// frames, summed up as the mean, the 95th percentile and the worst, in
/// milliseconds. The first 3.5 s after the first frame, and after each
/// restart (a framing or fly-in done), are not counted: the map is still
/// settling.
nonisolated struct GraphDepthMeter: Sendable {
    /// How many gaps are kept.
    static let kept: Int = 600
    /// How long after the start nothing is counted (seconds).
    static let settle: Double = 3.5
    private(set) var gaps: [Float] = []
    private var last: Double = -1
    private var from: Double = -1

    init() {}

    /// Counting starts again 3.5 s after the next frame.
    mutating func restart() {
        gaps.removeAll()
        from = -1
    }

    /// A frame drawn at `time` (seconds).
    mutating func tick(_ time: Double) {
        defer { last = time }
        if from < 0 { from = time + Self.settle }
        guard last >= 0, time > last, time >= from else { return }
        let gap = Float((time - last) * 1000)
        // a pause (the app in the background, a sheet) is not a frame
        guard gap < 1000 else { return }
        gaps.append(gap)
        if gaps.count > Self.kept { gaps.removeFirst(gaps.count - Self.kept) }
    }

    /// Mean, 95th percentile and worst gap (ms); zeros before two frames.
    var summary: (mean: Float, p95: Float, worst: Float) {
        guard !gaps.isEmpty else { return (0, 0, 0) }
        let sorted: [Float] = gaps.sorted()
        let mean: Float = sorted.reduce(0, +) / Float(sorted.count)
        let at: Int = min(sorted.count - 1, Int((Float(sorted.count - 1) * 0.95).rounded()))
        return (mean, sorted[at], sorted[sorted.count - 1])
    }

    /// What the meter counts besides the times, over the bodies drawn.
    struct Counts: Sendable, Equatable {
        var drawn: Int = 0
        var total: Int = 0
        /// Drawn with a fade of 0.5 or more.
        var dim: Int = 0
        /// Drawn with their centre outside the window.
        var out: Int = 0
        /// The camera's pitch from face-on, whole degrees.
        var tilt: Int = 0
        /// Broken rules: drawn fully faded, a half-faded pill, a pill on a
        /// fading body that is not chosen.
        var bad: Int = 0
    }

    /// The meter's line: "on frame 8.33 p95 9.10 worst 16.70 n 240 drawn
    /// 12/30 dim 3 out 0 tilt 45 bad 0".
    func label(_ state: GraphDepthState, _ c: Counts) -> String {
        let s = summary
        let numbers = String(format: "frame %.2f p95 %.2f worst %.2f n %d", s.mean, s.p95, s.worst, gaps.count)
        return state.rawValue + " " + numbers
            + " drawn \(c.drawn)/\(c.total) dim \(c.dim) out \(c.out) tilt \(c.tilt) bad \(c.bad)"
    }
}

/// Whether the fade is on, as the measurements read it: on (Space per body);
/// on with the per-pixel shader on Space's bodies (`-graphDepthPerPixel`, the
/// ablation) or on its glows (the probe found node opacity does not fade
/// added light here); off as asked (`-graphDepthOff`); or off because its
/// shader failed the check on this device, which must never pass for on.
nonisolated enum GraphDepthState: String, Sendable, CaseIterable {
    case on
    case onPixel = "on/pixel"
    case onGlowPixel = "on/glowpx"
    case off
    case fallback

    /// `asked`: the fade not turned off; `works`: the shader passed;
    /// `pixel`: the ablation; `glowPixel`: added light needs the shader.
    static func of(asked: Bool, works: Bool, pixel: Bool = false, glowPixel: Bool = false) -> GraphDepthState {
        guard asked else { return .off }
        guard works else { return .fallback }
        if pixel { return .onPixel }
        return glowPixel ? .onGlowPixel : .on
    }

    /// Whether the fade is drawn at all.
    var fades: Bool { self != .off && self != .fallback }
}
