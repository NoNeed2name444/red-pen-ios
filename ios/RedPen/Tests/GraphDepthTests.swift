// The depth fade in the 3D map's SceneKit themes (plan 4f,
// docs/design/depth-fade.md): SceneKit's fog curve along the view, the band
// following the focus at every zoom, the Graphics setting setting how far
// it reaches, Increase Contrast fading less, nothing drawn or picked past
// the end, detail dropping only where a body is mostly faded (with
// hysteresis), and name pills never half-faded - for Neurons and Space;
// Performance fades in its own engine.
//
// Compiled with Features/Notes/GraphDepthFade.swift, GraphTheme.swift and
// Shared/Space/GraphicsQuality.swift, which import only Foundation.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Float, _ b: Float, _ eps: Float) -> Bool { abs(a - b) <= eps }

let tiers: [GraphicsTier] = [.smooth, .high]
let themes: [GraphTheme] = [.neurons, .space]
var bands: [(String, GraphDepthBand)] = []
for theme in themes {
    for tier in tiers {
        for contrast in [false, true] {
            if let band = GraphDepthBand.of(theme, tier: tier, contrast: contrast) {
                bands.append(("\(theme.rawValue) \(tier)\(contrast ? "+contrast" : "")", band))
            }
        }
    }
}
check("D0a a band for every SceneKit theme, tier and contrast", bands.count == 8, "\(bands.count)")
check("D0b none for Performance (its own engine)", GraphDepthBand.of(.performance, tier: .high, contrast: false) == nil
      && GraphDepthBand.of(.performance, tier: .smooth, contrast: true) == nil)

// MARK: D1 - the curve is SceneKit's fog formula

for (name, band) in bands {
    let focus: Float = 10
    let (from, to) = band.span(focus: focus)
    check("D1a \(name): crisp up to the start", band.fade(depth: from, focus: focus) == 0
          && band.fade(depth: from * 0.5, focus: focus) == 0 && band.fade(depth: 0, focus: focus) == 0)
    check("D1b \(name): all the way (its most) from the end on",
          near(band.fade(depth: to, focus: focus), band.most, 1e-6)
          && near(band.fade(depth: to * 3, focus: focus), band.most, 1e-6))
    var worst: Float = 0
    var last: Float = -1
    var rising = true
    for step in 0...200 {
        let z: Float = from + (to - from) * Float(step) / 200
        let t: Float = min(max((z - from) / (to - from), 0), 1)
        let want: Float = pow(t, band.k) * band.most
        let got: Float = band.fade(depth: z, focus: focus)
        worst = max(worst, abs(got - want))
        if got < last { rising = false }
        last = got
    }
    check("D1c \(name): f = clamp((z - start) / (end - start), 0, 1)^k", worst < 1e-5, "\(worst)")
    check("D1d \(name): deeper never fades less", rising)
    check("D1e \(name): light is 1 - f", near(band.light(depth: (from + to) / 2, focus: focus),
                                              1 - band.fade(depth: (from + to) / 2, focus: focus), 1e-6))
    let fog = band.fog(focus: focus)
    check("D1f \(name): SceneKit's fog takes the same start, end and exponent",
          fog.start == from && fog.end == to && fog.exponent == band.k && fog.strongest == band.most)
}

// MARK: D2 - the band follows the focus, at every zoom

for (name, band) in bands {
    // flown in to a small note inside a cell, a cell, the whole map
    let foci: [Float] = [0.02, 0.4, 3, 60]
    var same = true
    for share: Float in [0.5, 1, 1.2, 1.5, 2, 2.4, 3, 5] {
        let reference: Float = band.fade(depth: share * 3, focus: 3)
        for focus in foci where !near(band.fade(depth: share * focus, focus: focus), reference, 1e-5) {
            same = false
        }
    }
    check("D2a \(name): the same fade at every zoom (depth in multiples of the focus)", same)
    var crisp = true
    for focus in foci where band.fade(depth: focus, focus: focus) != 0 { crisp = false }
    check("D2b \(name): what the camera looks at is always crisp", crisp)
    check("D2c \(name): the fade starts behind the focus", band.start > 1 && band.end > band.start)
}

// MARK: D3 - the focus's depth along the view

let eye = SIMD3<Float>(1, 2, 3)
check("D3a straight ahead: its distance",
      near(GraphDepthFocus.depth(eye: eye, forward: SIMD3<Float>(0, 0, -1), target: SIMD3<Float>(1, 2, -7)), 10, 1e-5))
check("D3b off to the side: only its depth along the view counts",
      near(GraphDepthFocus.depth(eye: eye, forward: SIMD3<Float>(0, 0, -1), target: SIMD3<Float>(9, -4, -7)), 10, 1e-5))
check("D3c a forward that is not unit length is the same",
      near(GraphDepthFocus.depth(eye: eye, forward: SIMD3<Float>(0, 0, -4), target: SIMD3<Float>(1, 2, -7)), 10, 1e-5))
check("D3d a target behind the eye: the nearest focus, never negative",
      GraphDepthFocus.depth(eye: eye, forward: SIMD3<Float>(0, 0, -1), target: SIMD3<Float>(1, 2, 8))
          == GraphDepthBand.nearestFocus)
check("D3e no direction: the nearest focus",
      GraphDepthFocus.depth(eye: eye, forward: SIMD3<Float>(0, 0, 0), target: SIMD3<Float>(1, 2, -7))
          == GraphDepthBand.nearestFocus)
check("D3f an unusable depth is the nearest focus", GraphDepthBand.focus(.nan) == GraphDepthBand.nearestFocus
      && GraphDepthBand.focus(-.infinity) == GraphDepthBand.nearestFocus)

// MARK: D4 - the Graphics setting sets the band

for theme in themes {
    let high: GraphDepthBand = GraphDepthBand.of(theme, tier: .high, contrast: false)!
    let smooth: GraphDepthBand = GraphDepthBand.of(theme, tier: .smooth, contrast: false)!
    let name: String = theme.rawValue
    check("D4a \(name): Smooth pulls the end in (less drawn)", smooth.end < high.end, "\(smooth.end) \(high.end)")
    check("D4b \(name): High reaches further", high.cull(focus: 10)! > smooth.cull(focus: 10)!)
    check("D4c \(name): both fade all the way, so both cull",
          high.culls && smooth.culls && high.most == 1 && smooth.most == 1)
    check("D4d \(name): the curve begins gently at both (k at least 1)", high.k >= 1 && smooth.k >= 1)
    check("D4e \(name): a whole map still shows its far side faded, not gone (end at least twice the focus)",
          smooth.end >= 2 && high.end >= 2)
}
check("D4f Space reaches further than the Neurons' shallow field",
      GraphDepthBand.of(.space, tier: .high, contrast: false)!.end > GraphDepthBand.of(.neurons, tier: .high, contrast: false)!.end)

// MARK: D5 - Increase Contrast fades less

for theme in themes {
  for tier in tiers {
    let plain: GraphDepthBand = GraphDepthBand.of(theme, tier: tier, contrast: false)!
    let bold: GraphDepthBand = GraphDepthBand.of(theme, tier: tier, contrast: true)!
    check("D5a \(theme.rawValue) \(tier): the fade starts later", bold.start > plain.start)
    check("D5b \(theme.rawValue) \(tier): and stops short of the fluid", bold.most < 1 && bold.most >= 0.5)
    check("D5c \(theme.rawValue) \(tier): so nothing is culled, and everything can be picked",
          !bold.culls && bold.cull(focus: 5) == nil && bold.pickable(depth: 1000, focus: 5))
    var less = true
    for z: Float in stride(from: 0, through: 40, by: 0.25) where bold.fade(depth: z, focus: 5) > plain.fade(depth: z, focus: 5) {
        less = false
    }
    check("D5d \(theme.rawValue) \(tier): never fades more than without it", less)
  }
}

// MARK: D6 - past the end: not drawn, not picked

for (name, band) in bands where band.culls {
    let focus: Float = 7
    let far: Float = band.cull(focus: focus)!
    check("D6a \(name): the far plane is the band's end", near(far, band.end * focus, 1e-5))
    check("D6b \(name): fully faded there", near(band.fade(depth: far, focus: focus), 1, 1e-6))
    check("D6c \(name): a body past it can't be picked; one before it can",
          !band.pickable(depth: far * 1.01, focus: focus) && band.pickable(depth: far * 0.99, focus: focus)
          && band.pickable(depth: focus, focus: focus))
}

// MARK: D7 - detail drops only where mostly faded, with hysteresis

check("D7a extras go only at a fade of about 0.6 or more", GraphDepthDetail.drop >= 0.6)
check("D7b they come back only clearly crisper (a gap between)",
      GraphDepthDetail.restore < GraphDepthDetail.drop - 0.05)
check("D7c kept below the drop; gone at it", GraphDepthDetail.keeps(fade: 0.61, had: true)
      && !GraphDepthDetail.keeps(fade: 0.62, had: true))
check("D7d not back in the gap; back at the restore", !GraphDepthDetail.keeps(fade: 0.55, had: false)
      && GraphDepthDetail.keeps(fade: 0.5, had: false))
// a cell wobbling across the drop line changes once, not every frame
var had = true
var changes = 0
for step in 0..<400 {
    let f: Float = 0.62 + 0.05 * sin(Float(step) * 0.3)
    let now: Bool = GraphDepthDetail.keeps(fade: f, had: had)
    if now != had { changes += 1 }
    had = now
}
check("D7e a cell wobbling on the line changes once", changes == 1, "\(changes)")
// and the depth where the drop happens is well inside the band for every tier
for (name, band) in bands where band.culls {
    let focus: Float = 4
    let (from, to) = band.span(focus: focus)
    var dropAt: Float = to
    for step in 0...1000 {
        let z: Float = from + (to - from) * Float(step) / 1000
        if !GraphDepthDetail.keeps(fade: band.fade(depth: z, focus: focus), had: true) { dropAt = z; break }
    }
    check("D7f \(name): extras go inside the band, past its middle", dropAt > (from + to) / 2 && dropAt < to,
          "\(dropAt) in \(from)...\(to)")
}

// MARK: D8 - name pills never half-fade

for (name, band) in bands {
    let focus: Float = 5
    let start: Float = band.span(focus: focus).start
    check("D8a \(name): a pill shows in the crisp zone",
          GraphDepthPills.shows(depth: focus, focus: focus, band: band, chosen: false, was: false))
    check("D8b \(name): never once the cell is fading (no half-faded pill)",
          !GraphDepthPills.shows(depth: start * 1.001, focus: focus, band: band, chosen: false, was: false)
          && band.fade(depth: start * GraphDepthPills.linger, focus: focus) < 0.05)
    check("D8c \(name): the chosen cell's pill shows wherever it is",
          GraphDepthPills.shows(depth: focus * 50, focus: focus, band: band, chosen: true, was: false))
    check("D8d \(name): a shown pill lingers a little past the start, then goes",
          GraphDepthPills.shows(depth: start * 1.03, focus: focus, band: band, chosen: false, was: true)
          && !GraphDepthPills.shows(depth: start * 1.1, focus: focus, band: band, chosen: false, was: true))
}

// MARK: D9 - SceneKit's side: the dome kept clear of the fog, writes only on a move

for (name, band) in bands {
    let built: Float = 400
    for focus: Float in [0.05, 1, 12, 80] {
        let near: Float = 0.001
        let radius: Float = band.skyRadius(focus: focus, near: near, built: built)
        check("D9a \(name) focus \(focus): the fluid's dome inside the fog's start, clear of the near plane",
              radius < band.span(focus: focus).start && radius > near && radius <= built, "\(radius)")
    }
}
check("D9b a still focus writes nothing", !GraphDepthBand.moved(from: 10, to: 10.01))
check("D9c a zoom writes", GraphDepthBand.moved(from: 10, to: 10.1) && GraphDepthBand.moved(from: 10, to: 9.9))
check("D9d the first frame writes", GraphDepthBand.moved(from: -1, to: 3))

print(failures.isEmpty ? "ALL PASS" : "FAILURES: \(failures.count)")
if !failures.isEmpty { exit(1) }
