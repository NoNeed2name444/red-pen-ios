// The Space theme's depth fade (docs/design/depth-fade.md) and near-only
// loading (plan 4e), as numbers: how far along the camera's view a body
// starts to dissolve into the sky and where it is gone, the band following
// what the camera looks at; how much of a body's fine shader detail its
// size on screen earns; when a far, tiny body is drawn as a glowing point
// instead; and which bodies are outside the view and so neither drawn nor
// animated.
//
// The shaders apply the fade and the detail weight themselves
// (GraphStyleShaders' depth pieces, from the same constants); GraphSim
// applies the rest each frame and hands the shaders the band. Foundation
// only, built on the Performance theme's camera maths (GraphPerfFrustum,
// GraphPerfLOD), so it is tested on Linux (Tests/SpaceDepthTests).
import Foundation

/// Where the fade starts and ends along the view (view-space depth, scene
/// units), how it curves, and how far it may go.
nonisolated struct SpaceDepthBand: Sendable, Equatable {
    var start: Float
    var end: Float
    /// k in f = clamp((z - start) / (end - start), 0, 1)^k: SceneKit's
    /// fogDensityExponent.
    var exponent: Float
    /// The most f reaches: 1 dissolves into the sky; under 1 (Increase
    /// Contrast) it stops short, so far bodies stay distinguishable.
    var cap: Float

    /// No fade at all: what a shader reads when nothing set its band (all
    /// four 0, GraphStyleUniforms.defaults).
    static let off = SpaceDepthBand(start: 0, end: 0, exponent: 0, cap: 0)

    /// How far a thing at view depth `depth` has faded, 0 (crisp) to `cap`.
    /// The shaders' rp_dfF.
    func fade(_ depth: Float) -> Float {
        let width: Float = end - start
        guard fades else { return 0 }
        let t: Float = min(max((depth - start) / width, 0), 1)
        return pow(t, max(exponent, 0.0001)) * cap
    }

    /// What is left of an additive light (a glow, a corona, a beam, a
    /// link): it fades to nothing, never towards a colour.
    func light(_ depth: Float) -> Float { 1 - fade(depth) }

    /// Whether the band fades anything at all (`off` does not).
    var fades: Bool { end - start > 0.0001 && cap > 0 }

    /// In the crisp zone (nothing faded): where name pills may show.
    /// Everywhere when the band fades nothing.
    func crisp(_ depth: Float) -> Bool { !fades || depth <= start }

    /// Whether the far end reaches the background, so what lies past it
    /// is fully faded and is not drawn.
    var culls: Bool { cap >= 1 && end - start > 0.0001 }

    /// Fully faded, so not drawn, not animated and not pickable.
    func gone(_ depth: Float) -> Bool { culls && depth >= end }

    /// The last of a solid body's dissolve: its opacity, 1 until it is
    /// nearly faded (f 0.85), then to 0 at the band's end, so a body seen
    /// against the brighter parts of the sky (the band, a nebula) does not
    /// end as a dark disc that then vanishes. 1 throughout when the band
    /// stops short (nothing is culled then either).
    func dissolve(_ depth: Float) -> Float {
        guard culls else { return 1 }
        return 1 - GraphPerfLOD.smoothstep(0.85, 1, fade(depth))
    }

    /// What the shaders' rpFade carries.
    var uniform: SIMD4<Float> { SIMD4<Float>(start, end, exponent, cap) }
}

/// A body's level of detail beyond its shader's own weight.
nonisolated enum SpaceBodyLevel: Sendable, Equatable {
    /// Its whole look (the shaders weigh their fine detail by its size).
    case body
    /// Too small on screen for its look to show: one glowing point in its
    /// colour, at its size.
    case point
    /// Outside the view or fully faded: nothing drawn or animated.
    case gone
}

nonisolated enum SpaceDepth {
    // MARK: the band

    /// The band in multiples of the focus's view depth, per Graphics tier:
    /// High reaches further (more drawn), Smooth pulls the end in (less
    /// drawn). The start sits behind the focus, so what the camera looks
    /// at is always crisp, at every zoom.
    static func reach(_ tier: GraphicsTier) -> (start: Float, end: Float) {
        switch tier {
        case .high: return (1.15, 2.6)
        case .smooth: return (1.1, 2.0)
        }
    }

    /// k: a little slower to start than linear, as deep water.
    static let exponent: Float = 1.25
    /// Increase Contrast: the fade starts later and stops short.
    static let contrastStart: Float = 1.25
    static let contrastCap: Float = 0.7
    /// The nearest a focus may lie along the view (scene units) and still
    /// set a band. One this near, at the eye or behind it is stale (the
    /// camera moved past what it last looked at): a band scaled from it
    /// would fade, then cull, everything in front, so there is none.
    static let nearestFocus: Float = 0.05

    /// The band for a camera whose focus (its orbit target, or the body it
    /// flew to) lies `focusDepth` along its view. Start and end scale with
    /// it, so zooming in on one small body looks the same as the whole map.
    /// `off` for a focus at most `nearestFocus` ahead, behind the eye or
    /// not a number.
    static func band(focusDepth: Float, tier: GraphicsTier, contrast: Bool = false) -> SpaceDepthBand {
        guard focusDepth.isFinite, focusDepth > nearestFocus else { return .off }
        let d: Float = focusDepth
        let r = reach(tier)
        let start: Float = r.start * (contrast ? contrastStart : 1)
        return SpaceDepthBand(start: d * start, end: d * r.end, exponent: exponent,
                              cap: contrast ? contrastCap : 1)
    }

    /// The view depth of `point`: how far along the camera's unit
    /// `forward` from its `eye` (the band's z, not distance from the map's
    /// centre).
    static func depth(of point: SIMD3<Float>, eye: SIMD3<Float>, forward: SIMD3<Float>) -> Float {
        ((point - eye) * forward).sum()
    }

    // MARK: detail by size on screen

    /// The shaders' weight on their fine detail for a body `pixelRadius`
    /// points across its radius on screen: none at
    /// GraphStyleShaders.detailLow, all of it from detailHigh, smooth
    /// between (the shaders' rp_lod). Up close it is always 1, so a body
    /// near the camera looks exactly as it did.
    static func detail(pixelRadius: Float) -> Float {
        GraphPerfLOD.smoothstep(GraphStyleShaders.detailLow, GraphStyleShaders.detailHigh, pixelRadius)
    }

    /// Under this radius on screen (points) a body becomes a point, and
    /// from `pointLeave` it is a body again: the gap keeps it from
    /// flickering at the edge. At these sizes its look is a dot of its
    /// colour anyway, so the change does not show.
    static let pointEnter: Float = 1.5
    static let pointLeave: Float = 2.25
    /// Inside the band, where it has mostly faded (f from `fadedFrom`), a
    /// body is drawn as a point from this larger size, with the same gap.
    static let fadedFrom: Float = 0.6
    static let fadedPointEnter: Float = 3
    static let fadedPointLeave: Float = 3.75

    /// The level for a body now, given the level it had: gone outside the
    /// view or past the band; a point when small (sooner when mostly
    /// faded); else its whole body. Only the point's edge has a gap, as
    /// the other two changes happen where nothing of it shows.
    static func level(_ previous: SpaceBodyLevel, pixelRadius: Float, fade: Float, gone: Bool,
                      inView: Bool) -> SpaceBodyLevel {
        if gone || !inView { return .gone }
        let faded: Bool = fade >= fadedFrom
        let enter: Float = faded ? fadedPointEnter : pointEnter
        let leave: Float = faded ? fadedPointLeave : pointLeave
        switch previous {
        case .point: return pixelRadius > leave ? .body : .point
        case .body: return pixelRadius < enter ? .point : .body
        case .gone: return pixelRadius < (enter + leave) / 2 ? .point : .body
        }
    }

    /// The point's radius on screen (points): the body's own, never under
    /// one point, so it neither jumps in size at the change nor vanishes
    /// between pixels.
    static func pointRadius(pixelRadius: Float) -> Float { max(pixelRadius, 1) }

    /// A body's radius on screen in points: GraphPerfLOD's, with the focal
    /// length for a view `viewHeight` points tall and a vertical field of
    /// view `fovY` (radians).
    static func pixelRadius(_ radius: Float, depth: Float, viewHeight: Float, fovY: Float) -> Float {
        GraphPerfLOD.pixelRadius(radius, depth: depth, focal: focal(viewHeight: viewHeight, fovY: fovY))
    }

    /// The focal length in points (what the shaders' rpFocal carries).
    static func focal(viewHeight: Float, fovY: Float) -> Float {
        viewHeight / 2 / tan(max(fovY, 0.001) / 2)
    }

    // MARK: what can be reached

    /// Whether a body can be picked and is shown to VoiceOver (plan 4f,
    /// owner 23 Oct): past the band's end it has faded out and is culled,
    /// with no hit area and no element. A body only outside the view keeps
    /// both, so the rotors can still reach it. The chosen body is always
    /// kept.
    static func reachable(pastBand: Bool, chosen: Bool) -> Bool {
        chosen || !pastBand
    }

    // MARK: the view

    /// The view volume of the Space map's camera (GraphPerfFrustum, the
    /// Performance theme's), from its eye and unit axes.
    static func frustum(eye: SIMD3<Float>, forward: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>,
                        fovY: Float, width: Float, height: Float, near: Float, far: Float) -> GraphPerfFrustum {
        GraphPerfFrustum.of(eye: eye, forward: forward, right: right, up: up, fovY: fovY, width: width,
                            height: height, near: near, far: far)
    }

    /// How far past its radius a body's look reaches, by style code
    /// (GraphNodeStyle.code: black hole, rocky, gas giant, comet, pulsar,
    /// sun): its disk, ring, corona, beams or tail. A body is outside the
    /// view only when all of that is.
    static func reachOfLook(styleCode: Int) -> Float {
        switch styleCode {
        case 0: return 4      // the accretion disk and its lensed ring
        case 1: return 3      // the halo and the moon
        case 2: return 3.5    // the ring
        case 3: return 16     // the tail
        case 4: return 12     // the beams
        case 5: return 5      // the corona
        default: return 5
        }
    }

    /// Whether a body at `centre` of radius `radius`, its look reaching
    /// `reach` radii, has any of itself inside `frustum`.
    static func inView(_ frustum: GraphPerfFrustum, centre: SIMD3<Float>, radius: Float, reach: Float) -> Bool {
        frustum.touches(centre: centre, radius: radius * max(reach, 1))
    }
}
