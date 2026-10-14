import Foundation

// The camera's lens, a theme at a time (the owner's boards: "dynamic
// lighting, depth of field, particles").
//
// Each theme photographs its world with its own lens: Space a telescope's
// soft bloom on the brightest stars with a touch of colour fringe at the
// edge; Neurons a microscope's shallow focus, the far cells melting into
// bokeh, a darker vignette and the glow of bioluminescence; Performance
// no lens at all (speed first).
//
// The Graphics setting decides whether any of it runs: every effect here
// needs SceneKit's HDR post-process pass, so Smooth turns the whole lens
// off and only High has it (HDR, bloom, depth of field and the black hole's
// lensed starlight, which the shaders draw only at rpDetail 1 - the same
// High). Reduce Motion changes nothing here: the lens does not move.
//
// Where a theme has depth of field (Space, Neurons), it keeps one look at
// every zoom: GraphSim focuses on what the camera orbits each frame and
// sets the aperture (fStop) so that something twice as far away is blurred
// by `depthBlur` of the screen's height, whether the camera is a couple of
// units from a cell or sixty from a region; further out, over the whole
// map, the aperture reaches SceneKit's widest and the blur fades rather
// than grows.
//
// The numbers are Foundation only and tested on Linux
// (Tests/GraphLensTests.swift); `apply(to:)` is SceneKit's half.

nonisolated struct GraphLens: Sendable, Equatable {
    /// SceneKit's HDR pass: needed by everything below.
    let hdr: Bool
    /// Bloom: how much, from what brightness up, how wide (points).
    let bloom: Double
    let bloomThreshold: Double
    let bloomBlur: Double
    /// Depth of field: the blur, as a share of the screen's height, of
    /// something twice as far away as the focus. 0 off.
    let depthBlur: Double
    /// Darkened corners: how much, and how far in (SceneKit's power).
    let vignette: Double
    let vignettePower: Double
    /// Colour fringe at the edges (chromatic aberration).
    let fringe: Double
    /// Exposure offset (EV), saturation (1 as drawn) and contrast (0 as drawn).
    let exposure: Double
    let saturation: Double
    let contrast: Double
    /// The black hole's lensed starlight (the ring shader's rpDetail arcs).
    let lensing: Bool

    /// Whether this lens costs a post-process pass.
    var heavy: Bool {
        hdr || bloom > 0 || depthBlur > 0 || vignette > 0 || fringe > 0 || exposure != 0 || saturation != 1
            || contrast != 0
    }

    /// As drawn: no pass, nothing changed.
    static let off = GraphLens(hdr: false, bloom: 0, bloomThreshold: 1, bloomBlur: 0, depthBlur: 0, vignette: 0,
                               vignettePower: 1, fringe: 0, exposure: 0, saturation: 1, contrast: 0, lensing: false)

    /// A theme's lens at a Graphics tier.
    static func of(_ theme: GraphTheme, tier: GraphicsTier) -> GraphLens {
        guard tier == .high else { return .off }
        switch theme {
        case .space:
            // a telescope: only the hottest cores bloom (the glows are
            // already in the shaders, so a low bloom would halo them all)
            return GraphLens(hdr: true, bloom: 0.3, bloomThreshold: 0.88, bloomBlur: 6, depthBlur: 0.0025,
                             vignette: 0.4, vignettePower: 1.4, fringe: 0.3, exposure: 0, saturation: 1.05,
                             contrast: 0.04, lensing: true)
        case .neurons:
            // a microscope: shallow focus, far cells to bokeh, glowing cells
            return GraphLens(hdr: true, bloom: 0.45, bloomThreshold: 0.78, bloomBlur: 9, depthBlur: 0.006,
                             vignette: 0.6, vignettePower: 1.2, fringe: 0.15, exposure: 0, saturation: 1.1,
                             contrast: 0.06, lensing: false)
        case .performance:
            return .off
        }
    }

    /// SceneKit's default sensor: 24 mm high.
    static let sensorHeight: Double = 24

    /// The focal length (mm) of a `fieldOfView`-degree lens on the sensor.
    static func focalLength(fieldOfView: Double) -> Double {
        let half: Double = max(min(fieldOfView, 170), 1) * Double.pi / 360
        return sensorHeight / 2 / tan(half)
    }

    /// The aperture that blurs something at twice `focus` (scene units,
    /// read as metres) by `blur` of the picture's height: a thin lens's
    /// circle of confusion, f² (d - s) / (N d (s - f)), solved for N.
    static func fStop(blur: Double, focus: Double, fieldOfView: Double) -> Double {
        guard blur > 0 else { return 32 }
        let f: Double = focalLength(fieldOfView: fieldOfView) / 1000
        let s: Double = max(focus, f * 4)
        let n: Double = f * f * 0.5 / (blur * (sensorHeight / 1000) * (s - f))
        return min(max(n, 0.02), 32)
    }

    /// The blur (share of the height) a lens at `fStop` gives something at
    /// `distance` when focused at `focus`: the same formula, read forwards.
    static func blur(fStop: Double, focus: Double, distance: Double, fieldOfView: Double) -> Double {
        let f: Double = focalLength(fieldOfView: fieldOfView) / 1000
        let s: Double = max(focus, f * 4)
        let d: Double = max(distance, f * 2)
        return f * f * abs(d - s) / (max(fStop, 0.0001) * d * (s - f)) / (sensorHeight / 1000)
    }
}

/// How a theme's map fills the screen when framed whole (Graph3DView's
/// frame()): `fill` of the part not under glass, and how much of the map's
/// depth counts - 1 every point at its own depth, so nothing near the
/// camera ever leaves the screen; less frames the map's middle layer, so
/// the nearest cells run past the edges as a microscope's field does
/// (the owner's board: the map fills the frame, the near cells cropped and
/// soft in the depth of field).
nonisolated struct GraphFit: Sendable, Equatable {
    let fill: Float
    let depth: Float

    /// The usual framing: 80% of the window, every point at its depth.
    static let plain = GraphFit(fill: 0.8, depth: 1)

    static func of(_ theme: GraphTheme, universe: Bool) -> GraphFit {
        guard universe else { return .plain }
        switch theme {
        case .neurons: return GraphFit(fill: 1.0, depth: 0.35)
        case .space, .performance: return GraphFit(fill: 0.88, depth: 1)
        }
    }

    /// A map's points (about its middle) as this fit counts them.
    func counted(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard depth != 1 else { return points }
        return points.map { SIMD3<Float>($0.x, $0.y, $0.z * depth) }
    }
}

#if canImport(SceneKit)
import SceneKit

extension GraphLens {
    /// Sets a camera to this lens. The focus and aperture are kept up to
    /// date by GraphSim (focus(_:on:)) while depth of field is on.
    @MainActor
    func apply(to camera: SCNCamera) {
        camera.wantsHDR = hdr
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = CGFloat(exposure)
        camera.bloomIntensity = CGFloat(bloom)
        camera.bloomThreshold = CGFloat(bloomThreshold)
        camera.bloomBlurRadius = CGFloat(bloomBlur)
        camera.wantsDepthOfField = depthBlur > 0
        camera.apertureBladeCount = 6
        camera.focalBlurSampleCount = 12
        camera.vignettingIntensity = CGFloat(vignette)
        camera.vignettingPower = CGFloat(vignettePower)
        camera.colorFringeStrength = CGFloat(fringe)
        camera.colorFringeIntensity = fringe > 0 ? 0.6 : 0
        camera.saturation = CGFloat(saturation)
        camera.contrast = CGFloat(contrast)
    }

    /// Focuses on `distance` (scene units) and opens the aperture to keep
    /// the blur this lens wants. Called on the render thread each frame.
    nonisolated func focus(_ camera: SCNCamera, at distance: Double) {
        guard depthBlur > 0, distance.isFinite, distance > 0 else { return }
        camera.focusDistance = CGFloat(distance)
        camera.fStop = CGFloat(GraphLens.fStop(blur: depthBlur, focus: distance,
                                               fieldOfView: Double(camera.fieldOfView)))
    }
}
#endif
