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
// The curve is SceneKit's own fog formula,
//     f = clamp((z - start) / (end - start), 0, 1) ^ k,
// with start and end the band's multiples times the focus's depth, worked
// out per pixel by a shader of our own on every material of the map
// (GraphDepthKeeper.swift), not by SceneKit's fog: SceneKit's fog would
// reach the name pills and the backdrop too, and measures from the eye
// rather than along the view. How each material fades (GraphDepthMode):
// light added to what is behind it (glows, halos, impulses, links, and
// every Neurons material) fades to nothing - its contribution times
// (1 - f) - so it dissolves into exactly what is behind it, at the darkest
// and the brightest parts of the background alike; fading it toward the
// background's colour instead would lay a veil over the glows. What is
// laid over the background goes see-through the same way, and only what
// is solid (Space's lit bodies) is mixed toward the background's colour.
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

/// How a theme's map fades with depth, at one Graphics tier.
nonisolated struct GraphDepthBand: Sendable, Equatable {
    /// Where the fade starts and where it reaches the background, as
    /// multiples of the focus's depth along the view.
    let start: Float
    let end: Float
    /// The curve's power (SceneKit's fogDensityExponent): above 1 the
    /// fade begins gently, so what is just behind the focus stays clear.
    let k: Float
    /// How far the fade goes: 1 all the way into the background; less
    /// with Increase Contrast.
    let most: Float

    /// The Neurons, a microscope's shallow field: the fade begins a little
    /// behind the focus and reaches the fluid at about two and a half times
    /// its depth (High), or twice it (Smooth, less drawn).
    static let neuronsHigh = GraphDepthBand(start: 1.15, end: 2.6, k: 1.4, most: 1)
    static let neuronsSmooth = GraphDepthBand(start: 1.1, end: 2.0, k: 1.2, most: 1)
    /// Space reaches further: a map seen whole is deep, and its far side
    /// stays in sight, faded.
    static let spaceHigh = GraphDepthBand(start: 1.2, end: 3.0, k: 1.5, most: 1)
    static let spaceSmooth = GraphDepthBand(start: 1.15, end: 2.4, k: 1.3, most: 1)

    /// Increase Contrast: the band starts and ends this much later, and
    /// fades at most this far, so a far body keeps four tenths of its light.
    static let contrastLater: Float = 1.35
    static let contrastMost: Float = 0.6

    /// The focus's depth is never taken as less than this (a target at
    /// or behind the eye). The shader keeps the same floor.
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
        return GraphDepthBand(start: base.start * contrastLater, end: base.end * contrastLater, k: base.k,
                              most: contrastMost)
    }

    /// Whether the fade goes all the way, so what is past the end is gone.
    var culls: Bool { most >= 1 }

    /// The four numbers the shader is given once (start, end, k, most): it
    /// finds the focus's depth itself, each frame, from where the camera
    /// is and what it looks at.
    var uniform: SIMD4<Float> { SIMD4<Float>(start, end, k, most) }

    /// The focus's depth as the band uses it.
    static func focus(_ depth: Float) -> Float {
        guard depth.isFinite else { return nearestFocus }
        return max(depth, nearestFocus)
    }

    /// Where the fade starts and ends (view depth) for a focus at `focus`.
    func span(focus: Float) -> (start: Float, end: Float) {
        let d: Float = Self.focus(focus)
        return (start * d, end * d)
    }

    /// How far along the band depth `z` is, 0 to 1, before the curve.
    func along(depth z: Float, focus: Float) -> Float {
        let (from, to): (Float, Float) = span(focus: focus)
        guard z.isFinite else { return 1 }
        let width: Float = max(to - from, 0.000_001)
        return min(max((z - from) / width, 0), 1)
    }

    /// The fade at view depth `z` with the focus at depth `focus`: 0 crisp
    /// up to the band's start, `most` from its end on.
    func fade(depth z: Float, focus: Float) -> Float {
        let t: Float = along(depth: z, focus: focus)
        guard t > 0 else { return 0 }
        return pow(t, k) * most
    }

    /// How much of a body's light is left at depth `z`: 1 - f.
    func light(depth z: Float, focus: Float) -> Float {
        1 - fade(depth: z, focus: focus)
    }

    /// Where nothing is drawn any more, for a focus at `focus`: the band's
    /// end, where everything is fully faded; nil when the fade stops short
    /// (Increase Contrast) and nothing is culled.
    func cull(focus: Float) -> Float? {
        guard culls else { return nil }
        return span(focus: focus).end
    }

    /// Whether a body at depth `z` is drawn and can be picked: not when it
    /// is past the band's end.
    func pickable(depth z: Float, focus: Float) -> Bool {
        guard let far = cull(focus: focus) else { return true }
        return z < far
    }

    /// The camera's far plane for a focus at `focus` with the near plane at
    /// `near`: the band's end, never closer than four near planes (a camera
    /// right up against what it looks at keeps a sliver of room for the
    /// backdrop); nil when nothing is culled and the scene's own far plane
    /// stays.
    func far(focus: Float, near: Float) -> Float? {
        guard let end = cull(focus: focus) else { return nil }
        return max(end, near * 4)
    }

    /// The backdrop's radius under a far plane at `far` (nil: the scene's
    /// own): half way to it, so the far plane never clips it, and clear of
    /// the near plane; never past `built`, its radius as the scene made it.
    /// It is drawn first and writes no depth, so its radius changes nothing
    /// else.
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

/// How one material fades, as the shader reads it (its code).
nonisolated enum GraphDepthMode: Float, Sendable, CaseIterable {
    /// Light added to what is behind it: its contribution times (1 - f),
    /// so it dissolves into exactly what is behind it.
    case light = 0
    /// Laid over what is behind it and see-through: colour and coverage
    /// times (1 - f), the same.
    case see = 1
    /// Solid: mixed toward the background's colour.
    case solid = 2

    /// A material's mode from how it is drawn: added (or screened,
    /// subtracted, maxed: each fades to no effect as it dims), laid over
    /// without writing depth (see-through), or solid.
    static func of(adds: Bool, writesDepth: Bool) -> GraphDepthMode {
        if adds { return .light }
        return writesDepth ? .solid : .see
    }

    /// What one channel becomes at fade `f`, from `value` with coverage
    /// `alpha`, toward `background` (linear): the shader's arithmetic.
    func apply(_ value: Float, alpha: Float, fade f: Float, background: Float) -> (value: Float, alpha: Float) {
        switch self {
        case .light: return (value * (1 - f), alpha)
        case .see: return (value * (1 - f), alpha * (1 - f))
        case .solid: return (value + (background * alpha - value) * f, alpha)
        }
    }
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
/// a body in the crisp zone (no fade at all), or the chosen one wherever it
/// is drawn; a shown pill stays a little past the start, so one on the line
/// does not flicker. Shown or not, it comes and goes by the pills' own
/// rules (GraphSim): never see-through.
nonisolated enum GraphDepthPills {
    /// A shown pill stays until its body is this much past the start.
    static let linger: Float = 1.06

    static func shows(depth z: Float, focus: Float, band: GraphDepthBand, chosen: Bool, was: Bool) -> Bool {
        guard band.pickable(depth: z, focus: focus) else { return false }
        if chosen { return true }
        let start: Float = band.span(focus: focus).start
        return z <= (was ? start * linger : start)
    }
}

/// Frame times for the before-and-after measurements (plan 4f's proof):
/// the gaps between frames over the last couple of seconds, summed up as
/// the mean, the 95th percentile and the worst, in milliseconds.
nonisolated struct GraphDepthMeter: Sendable {
    /// How many gaps are kept (two seconds at 120 a second).
    static let kept: Int = 240
    private(set) var gaps: [Float] = []
    private var last: Double = -1

    init() {}

    /// A frame drawn at `time` (seconds).
    mutating func tick(_ time: Double) {
        defer { last = time }
        guard last >= 0, time > last else { return }
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

    /// The meter's line: whether the fade is on, the summary, and how many
    /// bodies are drawn of the map's: "on frame 8.33 p95 9.10 worst 16.70
    /// n 240 drawn 12/30".
    func label(_ state: GraphDepthState, drawn: Int, of total: Int) -> String {
        let s = summary
        let numbers = String(format: "frame %.2f p95 %.2f worst %.2f n %ld", s.mean, s.p95, s.worst, gaps.count)
        return state.rawValue + " " + numbers + " drawn \(drawn)/\(total)"
    }
}

/// Whether the fade is on, as the measurements read it: on; off as asked
/// (`-graphDepthOff`, the before pictures); or off because its shader failed
/// the check on this device (GraphDepthProbe) and the map is drawn as
/// before, which must never pass for on in the numbers.
nonisolated enum GraphDepthState: String, Sendable, CaseIterable {
    case on
    case off
    case fallback

    /// `asked`: the fade not turned off; `works`: the shader passed.
    static func of(asked: Bool, works: Bool) -> GraphDepthState {
        guard asked else { return .off }
        return works ? .on : .fallback
    }
}
