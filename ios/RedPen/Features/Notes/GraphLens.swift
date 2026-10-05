import SceneKit

// MARK: - The camera's lens
//
// How a map's camera develops its picture. At the High quality budget a
// map is drawn in high dynamic range: its glows may go brighter than white,
// and the camera blooms whatever does - light spilling round a soma's core,
// an LED, a sun's corona, a pulsar's beams - with a touch of vignette and
// colour, as a microscope's or a camera's picture has. Flown in to a
// folder (or a design preview close-up), a lens with an aperture also
// focuses on it, the rest falling softly out of focus.
//
// At Smooth nothing here is spent: no HDR, no bloom, no depth of field -
// the picture is drawn as it always was, the glows clipped at white.
//
// Each theme has its own (GraphThemeLook.lens); the Space's is
// GraphLens.space.

struct GraphLens: Equatable {
    /// Bloom: how strong, from how bright (1 is white), how wide (points)
    /// and in how many passes, each `spread` wider.
    var bloom: CGFloat = 0
    var threshold: CGFloat = 1
    var blur: CGFloat = 8
    var iterations: Int = 1
    var spread: CGFloat = 0
    /// Exposure, in stops.
    var exposure: CGFloat = 0
    /// Colour: 1 and 0 leave it alone.
    var saturation: CGFloat = 1
    var contrast: CGFloat = 0
    /// Darkening towards the corners: how much, and how far in.
    var vignette: CGFloat = 0
    var vignettePower: CGFloat = 1
    /// Colour fringing towards the edges, as a real lens has.
    var fringe: CGFloat = 0
    /// Depth of field when focused on something (flown in, a close-up): the
    /// f-number, smaller blurring more; 0 for none.
    var aperture: CGFloat = 0

    /// No HDR and nothing added: how every map was drawn before.
    static let flat = GraphLens()

    /// Whether this lens spends anything at all.
    var isFlat: Bool { self == .flat }

    /// Sets `camera` up for the budget in force.
    func apply(to camera: SCNCamera, budget: GraphicsBudget = GraphQuality.current) {
        let rich: Bool = budget.tier == .high && !isFlat
        camera.wantsHDR = rich
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = rich ? bloom : 0
        camera.bloomThreshold = threshold
        camera.bloomBlurRadius = blur
        camera.bloomIterationCount = max(iterations, 1)
        camera.bloomIterationSpread = spread
        camera.exposureOffset = rich ? exposure : 0
        camera.saturation = rich ? saturation : 1
        camera.contrast = rich ? contrast : 0
        camera.vignettingIntensity = rich ? vignette : 0
        camera.vignettingPower = vignettePower
        camera.colorFringeStrength = rich ? fringe : 0
        camera.wantsDepthOfField = false
    }

    /// Focuses on something `distance` away, or on nothing (nil: the whole
    /// map, sharp throughout). Only a lens with an aperture, at High.
    func focus(_ camera: SCNCamera, at distance: Float?, budget: GraphicsBudget = GraphQuality.current) {
        guard let distance, distance > 0, aperture > 0, budget.tier == .high else {
            camera.wantsDepthOfField = false
            return
        }
        camera.wantsDepthOfField = true
        camera.focusDistance = CGFloat(distance)
        camera.fStop = aperture
        camera.apertureBladeCount = 6
        camera.focalBlurSampleCount = 12
    }
}
