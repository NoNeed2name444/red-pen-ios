// The million map's depth fade and depth detail (plan 4f with D1 to D5;
// docs/design/depth-fade.md), with its numbers pinned here and tested on
// Linux (Tests/GraphPerfChunkTests.swift, Tests/GraphPerfDesignTests.swift).
//
// The owner, 15 Oct: "u know how deep see videos or cell 3d high quality
// videos have fade for far objects ? that's how i want performance mode to
// be"; and before it, "the most surfaced is loaded and the deepest to u is
// faded until u turn and they load".
//
// - One curve, SceneKit's fog: f = clamp((z - start) / (end - start), 0, 1)^k
//   along the view's depth z, so the three themes match. A body's colour is
//   mixed towards the map's ground (GraphPerfScene.background) by f, drawn
//   opaque with the depth test; additive light (glows, bundles) is times
//   1 - f, so it fades to nothing and never brightens.
// - The band follows the camera's focus: start and end are multiples of
//   the camera's distance to what it looks at, so the focus is always crisp
//   and a note zoomed into inside a cell looks the same at that scale.
//   Turning the map brings the far side forward and it sharpens, every
//   frame, with no timers.
// - What is past the end is culled (the planner's far plane); detail drops
//   only where f is 0.6 or more, with hysteresis (GraphPerfChunkSettings),
//   by morphing, never a cross-fade.
// - The Graphics setting sets the band (a lower one pulls the end in, so
//   less is drawn); the frame budget may pull it in further, never the rate.
// - Increase Contrast: the fade starts later and stops short of the
//   ground, so far things stay distinguishable (and, never fully faded,
//   nothing is culled for it).
//
// Foundation only, free of Stethoscore types.
import Foundation

/// Where the depth fade starts and ends, and how it bends.
nonisolated struct GraphPerfDepthBand: Sendable, Equatable {
    /// Where the fade starts and where it reaches the ground, as multiples
    /// of the camera's distance to its focus.
    var start: Float
    var end: Float
    /// The curve's exponent (SceneKit's fogDensityExponent): above 1 the
    /// fade sets in softly behind the focus.
    var k: Float
    /// How far it fades at most: 1, into the ground (less with Increase Contrast).
    var most: Float

    /// Only a band that fades fully may cull what lies past it.
    var culls: Bool { most >= 1 }

    /// The Graphics levels' bands: a lower level pulls the end in.
    static let high = GraphPerfDepthBand(start: 1.0, end: 1.4, k: 1.2, most: 1)
    static let smooth = GraphPerfDepthBand(start: 1.0, end: 1.32, k: 1.2, most: 1)
    static let saver = GraphPerfDepthBand(start: 1.0, end: 1.25, k: 1.2, most: 1)
    /// Increase Contrast: start and end this much later, and at most this faded.
    static let contrastLater: Float = 1.15
    static let contrastMost: Float = 0.6
    /// The frame budget pulls the band in down to this share of its width.
    static let tightest: Float = 0.7

    static func of(_ tier: GraphPerfTier, contrast: Bool = false) -> GraphPerfDepthBand {
        var band: GraphPerfDepthBand
        switch tier {
        case .high: band = .high
        case .smooth: band = .smooth
        case .saver: band = .saver
        }
        if contrast {
            band.start *= contrastLater
            band.end *= contrastLater
            band.most = contrastMost
        }
        return band
    }

    /// The band's depths (world units along the view) for a camera `focus`
    /// units from what it looks at, its width times `pull` (the frame
    /// budget's, tightest...1).
    func depths(focus: Float, pull: Float = 1) -> SIMD2<Float> {
        let f = max(focus, 1e-4)
        let s = start * f
        let width = max(end - start, 1e-3) * f * min(max(pull, Self.tightest), 1)
        return SIMD2(s, s + width)
    }

    /// The fade at view depth `z` for the band's `depths`.
    func fade(_ z: Float, depths: SIMD2<Float>) -> Float {
        Self.fade(z, depths: depths, k: k, most: most)
    }

    /// f = clamp((z - start) / (end - start), 0, 1)^k, times `most`.
    static func fade(_ z: Float, depths: SIMD2<Float>, k: Float, most: Float) -> Float {
        let t = min(max((z - depths.x) / max(depths.y - depths.x, 1e-6), 0), 1)
        if t <= 0 { return 0 }
        return Float(pow(Double(t), Double(max(k, 0.05)))) * most
    }
}

/// How a body looks at its depth: the Swift twin of the node shader
/// (GraphPerfMillionShaders' mil_node_*), so the Linux tests hold what the
/// GPU draws to the design (brightness never jumps a frame, sizes morph).
nonisolated enum GraphPerfDepthLook {
    /// A body's size on screen (points, radius): its own, a little smaller
    /// as its detail drops (0.7 at the back), between the floor and the cap,
    /// all times how far its leaf is open (a morph, never a pop).
    static func pixels(radius: Float, focal: Float, depth: Float, open: Float, detail q: Float,
                       floor: Float = GraphPerfLOD.noteClamp.lowerBound,
                       cap: Float = GraphPerfLOD.hubClamp.upperBound) -> Float {
        let o = min(max(open, 0), 1)
        let shrink = 0.7 + 0.3 * min(max(q, 0), 1)
        let p = radius * o * shrink * focal / max(depth, 1e-3)
        return min(max(p, floor * o), cap)
    }

    /// How much a body is shaded as a lit ball (0: a flat dot): it grows
    /// with its pixels and its detail.
    static func lit(pixels: Float, detail q: Float) -> Float {
        smoothstep(2, 8, pixels) * smoothstep(0, 1, q)
    }

    /// The rim of light a big, front body gets.
    static func rim(pixels: Float, detail q: Float) -> Float {
        smoothstep(8, 20, pixels) * smoothstep(0.5, 1, q)
    }

    /// The light's direction (the shader's).
    static let light = SIMD3<Float>(-0.45, 0.55, 0.7) / (SIMD3<Float>(-0.45, 0.55, 0.7) * SIMD3<Float>(-0.45, 0.55, 0.7)).sum().squareRoot()

    /// The diffuse share at a disc's centre (the normal faces the eye).
    static var centreDiffuse: Float { 0.42 + 0.58 * max(light.z, 0) }

    /// The brightest a body is drawn (the ring and rims stop short of white:
    /// the share of the screen at 250 or more stays under 3%).
    static let brightest: Float = 0.94

    /// The colour at a body's centre: its own, shaded as `lit`, then mixed
    /// towards the `ground` (GraphPerfScene.background) by its fade `f`,
    /// and towards it by `dim` too when another note is chosen (the rest
    /// steps back).
    static func centre(colour: SIMD3<Float>, lit: Float, fade f: Float, dim: Float = 0,
                       ground: SIMD3<Float>) -> SIMD3<Float> {
        let shade = 1 + (centreDiffuse - 1) * min(max(lit, 0), 1)
        var c = colour * shade
        c = c + (ground - c) * min(max(f, 0), 1)
        c = c + (ground - c) * min(max(dim, 0), 1)
        return pointwiseMin(c, SIMD3(repeating: brightest))
    }

    /// Additive light's share at fade `f`: it fades to nothing.
    static func glow(fade f: Float) -> Float { 1 - min(max(f, 0), 1) }

    /// Luminance (Rec. 709).
    static func luminance(_ c: SIMD3<Float>) -> Float { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        guard b > a else { return x >= b ? 1 : 0 }
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
