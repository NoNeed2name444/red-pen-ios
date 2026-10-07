// The camera's lens, a theme at a time: none at Smooth (the post-process
// pass is what Smooth saves), none ever in Performance, the heavy effects
// (HDR, bloom, depth of field, the black hole's lensing) only at High, the
// themes photographed differently, and a depth of field that keeps one
// look at every zoom because the aperture is worked out from the focus.
//
// Compiled with Features/Notes/GraphLens.swift, GraphTheme.swift and
// Shared/Space/GraphicsQuality.swift, which import only Foundation.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double, _ b: Double, _ eps: Double) -> Bool { abs(a - b) <= eps }

let fov: Double = 55

// MARK: L1 - the tiers

for theme in GraphTheme.allCases {
    let smooth: GraphLens = GraphLens.of(theme, tier: .smooth)
    check("L1a \(theme.rawValue): no lens at Smooth", smooth == .off && !smooth.heavy)
}
check("L1b Performance has no lens even at High", GraphLens.of(.performance, tier: .high) == .off)
check("L1c the plain lens costs nothing", !GraphLens.off.heavy)
for theme in [GraphTheme.space, .neurons, .circuit] {
    let high: GraphLens = GraphLens.of(theme, tier: .high)
    check("L1d \(theme.rawValue): HDR, bloom and depth of field at High",
          high.hdr && high.bloom > 0 && high.depthBlur > 0 && high.heavy)
    check("L1e \(theme.rawValue): bloom only on the brightest (the shaders already glow)",
          high.bloomThreshold >= 0.75 && high.bloom <= 0.5, "\(high.bloomThreshold) \(high.bloom)")
    check("L1f \(theme.rawValue): colours kept close to the drawing",
          high.saturation >= 0.9 && high.saturation <= 1.2 && high.contrast >= 0 && high.contrast <= 0.15
          && high.exposure == 0)
    check("L1g \(theme.rawValue): vignette and fringe in range",
          (0...1).contains(high.vignette) && (0...1).contains(high.fringe) && high.vignettePower > 0)
}

// MARK: L2 - lensing follows the shaders' detail

for tier in [GraphicsTier.smooth, .high] {
    let budget: GraphicsBudget = GraphicsBudget.of(tier)
    check("L2a lensed starlight exactly when the shaders draw their detail (\(tier))",
          GraphLens.of(.space, tier: tier).lensing == (budget.shaderDetail >= 1))
}
check("L2b only Space bends light", !GraphLens.of(.neurons, tier: .high).lensing
      && !GraphLens.of(.circuit, tier: .high).lensing)

// MARK: L3 - each theme its own lens

let space: GraphLens = GraphLens.of(.space, tier: .high)
let neurons: GraphLens = GraphLens.of(.neurons, tier: .high)
let circuit: GraphLens = GraphLens.of(.circuit, tier: .high)
check("L3a a microscope focuses shallower than a telescope", neurons.depthBlur > space.depthBlur)
check("L3b the macro lens over the board is the shallowest",
      circuit.depthBlur > neurons.depthBlur && circuit.depthBlur > space.depthBlur)
check("L3c bioluminescence blooms most and widest",
      neurons.bloom > space.bloom && neurons.bloom > circuit.bloom && neurons.bloomBlur > circuit.bloomBlur)
check("L3d the microscope's corners are darkest", neurons.vignette > space.vignette && neurons.vignette > circuit.vignette)
check("L3e a board under a macro lens has no colour fringe, the telescope the most",
      circuit.fringe == 0 && space.fringe > neurons.fringe)
check("L3f the three looks differ", space != neurons && neurons != circuit && space != circuit)

// MARK: L4 - the optics

let focal: Double = GraphLens.focalLength(fieldOfView: fov)
check("L4a a 55° lens on a 24 mm sensor is about 23 mm", near(focal, 23.05, 0.05), "\(focal)")
check("L4b a wider view is a shorter lens",
      GraphLens.focalLength(fieldOfView: 90) < focal && GraphLens.focalLength(fieldOfView: 30) > focal)
check("L4c silly angles stay finite", GraphLens.focalLength(fieldOfView: 0).isFinite
      && GraphLens.focalLength(fieldOfView: 400).isFinite && GraphLens.focalLength(fieldOfView: 400) > 0)

for lens in [space, neurons, circuit] {
    var worst: Double = 0
    for focus in [2.0, 5, 12, 30, 45, 60] {
        let n: Double = GraphLens.fStop(blur: lens.depthBlur, focus: focus, fieldOfView: fov)
        let got: Double = GraphLens.blur(fStop: n, focus: focus, distance: focus * 2, fieldOfView: fov)
        worst = max(worst, abs(got - lens.depthBlur) / lens.depthBlur)
    }
    check("L4d the same blur at twice the focus from a cell to a region, 2 to 60 units (\(lens.depthBlur))",
          worst < 0.01, "worst \(worst)")
    // over the whole map the aperture is at its widest and the blur fades:
    // less than wanted, never more, never none
    let n400: Double = GraphLens.fStop(blur: lens.depthBlur, focus: 400, fieldOfView: fov)
    let far: Double = GraphLens.blur(fStop: n400, focus: 400, distance: 800, fieldOfView: fov)
    check("L4d' the whole map from far off: softer, not sharper or blurrier than wanted (\(lens.depthBlur))",
          far > 0 && far <= lens.depthBlur * 1.0001, "\(far)")
}
let sharp: Double = GraphLens.blur(fStop: GraphLens.fStop(blur: 0.006, focus: 20, fieldOfView: fov), focus: 20,
                                   distance: 20, fieldOfView: fov)
check("L4e what is in focus is sharp", sharp < 1e-9, "\(sharp)")
let n20: Double = GraphLens.fStop(blur: 0.006, focus: 20, fieldOfView: fov)
let nearer: Double = GraphLens.blur(fStop: n20, focus: 20, distance: 30, fieldOfView: fov)
let farther: Double = GraphLens.blur(fStop: n20, focus: 20, distance: 60, fieldOfView: fov)
check("L4f further from the focus is blurrier", farther > nearer && nearer > 0)
check("L4g a closer focus opens the aperture less (smaller fStop further away)",
      GraphLens.fStop(blur: 0.006, focus: 5, fieldOfView: fov) > GraphLens.fStop(blur: 0.006, focus: 50, fieldOfView: fov))
check("L4h no blur asked: the aperture shut down", GraphLens.fStop(blur: 0, focus: 10, fieldOfView: fov) == 32)
let tiny: Double = GraphLens.fStop(blur: 0.9, focus: 1e6, fieldOfView: fov)
let huge: Double = GraphLens.fStop(blur: 1e-9, focus: 0.001, fieldOfView: fov)
check("L4i the aperture stays in SceneKit's range", tiny >= 0.02 && huge <= 32 && tiny.isFinite && huge.isFinite,
      "\(tiny) \(huge)")
check("L4j a focus inside the lens stays finite",
      GraphLens.blur(fStop: 2, focus: 0, distance: 0, fieldOfView: fov).isFinite)

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED: \(failures.joined(separator: ", "))")
exit(failures.isEmpty ? 0 : 1)
