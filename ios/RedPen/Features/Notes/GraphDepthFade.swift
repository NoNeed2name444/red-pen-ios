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
// with start and end the band's multiples times the focus's depth. Light
// that is added to what is behind it (glows, halos, impulses, links, and
// every Neurons material) fades to nothing - its contribution times
// (1 - f) - so it dissolves into exactly what is behind it, at the darkest
// and the brightest parts of the background alike; fading it toward the
// background's colour instead would lay a veil over the glows.
//
// The Graphics setting sets how far the band reaches: Smooth pulls its end
// in, so less is drawn. Past the end everything is fully faded, so it is
// not drawn (the camera's far plane) and cannot be picked; fly-to, search
// and the filter still reach any body, since flying to it brings it into
// the crisp zone. Increase Contrast starts the fade later and stops it
// short of the background, so far bodies stay distinguishable (and nothing
// is culled). Reduce Motion changes nothing: the fade is not motion.
//
// Inside the band detail drops (GraphDepthDetail), only where a body is
// mostly faded already and with hysteresis, so nothing pops; and name
// pills, being interface, never half-fade: one shows only in the crisp
// zone, or for the chosen body (GraphDepthPills).
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
        return GraphDepthBand(start: base.start * contrastLater, end: base.end * contrastLater, k: base.k,
                              most: contrastMost)
    }

    /// Whether the fade goes all the way, so what is past the end is gone.
    var culls: Bool { most >= 1 }

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

    /// The camera's far plane for a focus at `focus`: everything past the
    /// band's end is fully faded, so nothing past it is drawn or picked;
    /// nil when the fade stops short (Increase Contrast) and nothing is.
    func cull(focus: Float) -> Float? {
        guard culls else { return nil }
        return span(focus: focus).end
    }

    /// Whether a body at depth `z` can be picked: not when it is past the
    /// band's end, where it is not drawn.
    func pickable(depth z: Float, focus: Float) -> Bool {
        guard let far = cull(focus: focus) else { return true }
        return z < far
    }

    /// SceneKit's fog for this band at a focus: start and end distances,
    /// the exponent, and the fog colour's alpha (its strongest).
    func fog(focus: Float) -> (start: Float, end: Float, exponent: Float, strongest: Float) {
        let (from, to): (Float, Float) = span(focus: focus)
        return (from, to, k, most)
    }

    /// The backdrop stays inside where the fade starts, half way to it, so
    /// SceneKit's fog never touches it (it is drawn first and writes no
    /// depth, so how far away it is changes nothing else), and well clear
    /// of the near plane; never past `built`, its radius as the scene made
    /// it.
    func skyRadius(focus: Float, near: Float, built: Float) -> Float {
        let inside: Float = span(focus: focus).start * 0.5
        let clear: Float = max(near * 4, 0.000_01)
        return min(max(inside, clear), max(built, clear))
    }

    /// Whether a focus moved enough since `shown` to write the fade again
    /// (one part in five hundred), so a still camera writes nothing.
    static func moved(from shown: Float, to focus: Float) -> Bool {
        guard shown > 0, shown.isFinite else { return true }
        return abs(focus - shown) > shown * 0.002
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
}

/// Detail inside the band: a body's extras (its halo, what floats inside
/// it, its finer parts) go only once it is mostly faded, and come back
/// only once it is clearly crisper, so a body on the line never flickers.
/// Each change morphs (a size growing or shrinking), never cross-fades.
nonisolated enum GraphDepthDetail {
    /// Extras go at this fade or more.
    static let drop: Float = 0.62
    /// And come back at this fade or less.
    static let restore: Float = 0.5

    /// Whether a body keeps its extras at fade `f`, having had them or not.
    static func keeps(fade f: Float, had: Bool) -> Bool {
        had ? f < drop : f <= restore
    }
}

/// Name pills are interface, so they never half-fade: a pill shows only for
/// a body in the crisp zone (no fade at all), or the chosen one wherever it
/// is; a shown pill stays a little past the start, so one on the line does
/// not flicker. Shown or not, it comes and goes by the pills' own rules
/// (GraphSim): never see-through.
nonisolated enum GraphDepthPills {
    /// A shown pill stays until its body is this much past the start.
    static let linger: Float = 1.06

    static func shows(depth z: Float, focus: Float, band: GraphDepthBand, chosen: Bool, was: Bool) -> Bool {
        if chosen { return true }
        let start: Float = band.span(focus: focus).start
        return z <= (was ? start * linger : start)
    }
}
