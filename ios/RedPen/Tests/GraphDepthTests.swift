// The depth fade in the 3D map's SceneKit themes (plan 4f,
// docs/design/depth-fade.md): SceneKit's fog curve along the view, the band
// following the focus at every zoom, the Graphics setting setting how far
// it reaches, Increase Contrast fading less, nothing drawn or picked past
// the end, detail dropping only where a body is mostly faded (with
// hysteresis) and morphing rather than fading, name pills never
// half-faded, how each kind of material fades (light to nothing, never a
// veil), the meter for the before-and-after numbers, and a link chip's
// glide reaching a body past the end - for Neurons and Space; Performance
// fades in its own engine.
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
    let u: SIMD4<Float> = band.uniform
    check("D1f \(name): the shader is given start, end, k and most, as multiples of the focus",
          u.x == band.start && u.y == band.end && u.z == band.k && u.w == band.most
          && near(u.x * focus, from, 1e-5) && near(u.y * focus, to, 1e-5))
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
    check("D6d \(name): the camera's far plane is the end", near(band.far(focus: focus, near: 0.05)!, far, 1e-5))
    check("D6e \(name): never closer than four near planes (a camera right up against its target)",
          near(band.far(focus: 0.001, near: 0.05)!, 0.2, 1e-6))
}
for (name, band) in bands where !band.culls {
    check("D6f \(name): no far plane of its own when nothing is culled", band.far(focus: 7, near: 0.05) == nil)
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
    let drawnAt: Float = band.cull(focus: focus).map { $0 * 0.99 } ?? focus * 50
    check("D8c \(name): the chosen cell's pill shows wherever it is drawn",
          GraphDepthPills.shows(depth: drawnAt, focus: focus, band: band, chosen: true, was: false))
    if let far = band.cull(focus: focus) {
        check("D8e \(name): none past the end, chosen or not (the body is not drawn)",
              !GraphDepthPills.shows(depth: far * 1.01, focus: focus, band: band, chosen: true, was: true))
    }
    check("D8d \(name): a shown pill lingers a little past the start, then goes",
          GraphDepthPills.shows(depth: start * 1.03, focus: focus, band: band, chosen: false, was: true)
          && !GraphDepthPills.shows(depth: start * 1.1, focus: focus, band: band, chosen: false, was: true))
}

// MARK: D9 - SceneKit's side: the backdrop inside the far plane, writes only on a move

for (name, band) in bands {
    let built: Float = 400
    for focus: Float in [0.05, 1, 12, 80, 400] {
        let near: Float = 0.001
        let far: Float? = band.far(focus: focus, near: near)
        let radius: Float = GraphDepthBand.skyRadius(far: far, near: near, built: built)
        if let far {
            check("D9a \(name) focus \(focus): the backdrop inside the far plane, clear of the near plane",
                  radius < far && radius > near && radius <= built, "\(radius)")
        } else {
            check("D9a \(name) focus \(focus): the backdrop as built when nothing is culled", radius == built)
        }
    }
}
check("D9b a still focus writes nothing", !GraphDepthBand.moved(from: 10, to: 10.01))
check("D9c a zoom writes", GraphDepthBand.moved(from: 10, to: 10.1) && GraphDepthBand.moved(from: 10, to: 9.9))
check("D9d the first frame writes", GraphDepthBand.moved(from: -1, to: 3))
check("D9e a target well ahead stands as the focus; one at or behind the eye does not",
      GraphDepthFocus.usable(0.5) && !GraphDepthFocus.usable(0) && !GraphDepthFocus.usable(-3)
      && !GraphDepthFocus.usable(.nan) && !GraphDepthFocus.usable(GraphDepthBand.nearestFocus))

// MARK: D10 - how each material fades: light to nothing, never a veil

check("D10a added light (and screened, subtracted, maxed) is light", GraphDepthMode.of(adds: true, writesDepth: true) == .light
      && GraphDepthMode.of(adds: true, writesDepth: false) == .light)
check("D10b laid over without writing depth is see-through; solid writes depth",
      GraphDepthMode.of(adds: false, writesDepth: false) == .see && GraphDepthMode.of(adds: false, writesDepth: true) == .solid)
check("D10c the shader reads the modes as 0, 1 and 2",
      GraphDepthMode.light.rawValue == 0 && GraphDepthMode.see.rawValue == 1 && GraphDepthMode.solid.rawValue == 2)
for f: Float in [0, 0.3, 0.7, 1] {
    let lit = GraphDepthMode.light.apply(0.8, alpha: 1, fade: f, background: 0.2)
    check("D10d light at fade \(f): its contribution times 1 - f, whatever the background (no veil)",
          near(lit.value, 0.8 * (1 - f), 1e-6) && lit.alpha == 1
          && GraphDepthMode.light.apply(0.8, alpha: 1, fade: f, background: 0.9).value == lit.value)
    let seen = GraphDepthMode.see.apply(0.6, alpha: 0.5, fade: f, background: 0.2)
    check("D10e see-through at fade \(f): colour and coverage times 1 - f",
          near(seen.value, 0.6 * (1 - f), 1e-6) && near(seen.alpha, 0.5 * (1 - f), 1e-6))
    let solid = GraphDepthMode.solid.apply(0.6, alpha: 1, fade: f, background: 0.02)
    check("D10f solid at fade \(f): mixed toward the background",
          near(solid.value, 0.6 + (0.02 - 0.6) * f, 1e-6) && solid.alpha == 1)
}
check("D10g fully faded light is gone, a solid body is the background",
      GraphDepthMode.light.apply(1, alpha: 1, fade: 1, background: 0.3).value == 0
      && near(GraphDepthMode.solid.apply(0.9, alpha: 1, fade: 1, background: 0.03).value, 0.03, 1e-6))

// MARK: D11 - extras morph (shrink and grow), never cross-fade

var grown: Float = 1
var steps = 0
var smooth = true
var lastSize: Float = GraphDepthDetail.size(grown)
while grown > 0 && steps < 1000 {
    grown = GraphDepthDetail.grown(grown, keep: false, dt: 1.0 / 60, still: false)
    let size: Float = GraphDepthDetail.size(grown)
    if size > lastSize || lastSize - size > 0.2 { smooth = false }
    lastSize = size
    steps += 1
}
check("D11a gone in about a quarter of a second at 60 a second", steps >= 14 && steps <= 16, "\(steps)")
check("D11b shrinking only, in small steps", smooth)
check("D11c with Reduce Motion (or a still space) at once",
      GraphDepthDetail.grown(1, keep: false, dt: 0.016, still: true) == 0
      && GraphDepthDetail.grown(0, keep: true, dt: 0.016, still: true) == 1)
check("D11d eased: no jolt at either end", GraphDepthDetail.size(0) == 0 && GraphDepthDetail.size(1) == 1
      && GraphDepthDetail.size(0.05) < 0.05 && GraphDepthDetail.size(0.95) > 0.95)
check("D11e a long or bad frame never overshoots", GraphDepthDetail.grown(0.2, keep: false, dt: 5, still: false) == 0
      && GraphDepthDetail.grown(0.9, keep: true, dt: .nan, still: false) == 1
      && GraphDepthDetail.grown(0.5, keep: true, dt: -1, still: false) == 0.5)

// MARK: D12 - the meter: the numbers before and after

var meter = GraphDepthMeter()
check("D12a nothing yet: zeros", meter.summary.mean == 0 && meter.summary.worst == 0)
var clock: Double = 10
meter.tick(clock)
for k in 0..<100 {
    clock += k == 50 ? 0.050 : 0.010
    meter.tick(clock)
}
let s12 = meter.summary
check("D12b mean, 95th percentile and worst of the gaps (ms)",
      near(s12.mean, 10.4, 0.01) && near(s12.p95, 10, 0.01) && near(s12.worst, 50, 0.01), "\(s12)")
clock += 3
meter.tick(clock)
check("D12c a pause (the app away) is not a frame", meter.gaps.count == 100 && meter.summary.worst < 51)
for _ in 0..<500 {
    clock += 0.008
    meter.tick(clock)
}
check("D12d only the last couple of seconds are kept", meter.gaps.count == GraphDepthMeter.kept)
let line: String = meter.label(.on, drawn: 12, of: 30)
check("D12e its line says the fade is on, the numbers and how many are drawn",
      line.hasPrefix("on frame 8.00 p95 8.00 worst 8.00 n 240") && line.hasSuffix("drawn 12/30"), line)
check("D12f the probe's fallback shows in the numbers, never as on",
      GraphDepthState.of(asked: true, works: false) == .fallback
      && meter.label(.fallback, drawn: 30, of: 30).hasPrefix("fallback ")
      && GraphDepthState.of(asked: true, works: true) == .on
      && GraphDepthState.of(asked: false, works: true) == .off && GraphDepthState.of(asked: false, works: false) == .off)

// MARK: D13 - a link chip's glide reaches a body past the end

func depthAlong(_ p: SIMD3<Float>, eye e: SIMD3<Float>, forward f: SIMD3<Float>) -> Float {
    ((p - e) * f).sum() / (f * f).sum().squareRoot()
}
func offLine(_ p: SIMD3<Float>, eye e: SIMD3<Float>, through q: SIMD3<Float>) -> Float {
    let d: SIMD3<Float> = q - e
    let u: SIMD3<Float> = d / (d * d).sum().squareRoot()
    let v: SIMD3<Float> = p - e
    let along: Float = (v * u).sum()
    let rest: SIMD3<Float> = v - u * along
    return (rest * rest).sum().squareRoot()
}
let gEye = SIMD3<Float>(0, 0, 10)
let gForward = SIMD3<Float>(0, 0, -1)
let gTarget = SIMD3<Float>(0, 0, 8)          // the focus 2 ahead
let gSight = SIMD3<Float>(0, 0.3, 9)         // the goal: a little above the middle
for band in [GraphDepthBand.neuronsHigh, .neuronsSmooth, .spaceHigh, .spaceSmooth] {
    let focus: Float = depthAlong(gTarget, eye: gEye, forward: gForward)
    let body = SIMD3<Float>(3, -2, -30)          // 40 ahead: far past the end
    check("D13a the body starts past the end, not drawn", !band.pickable(depth: depthAlong(body, eye: gEye, forward: gForward),
                                                                          focus: focus))
    guard let move = GraphDepthGlide.move(body: body, eye: gEye, sight: gSight, forward: gForward, target: gTarget) else {
        check("D13b a glide for a body past the end", false)
        continue
    }
    let eye2: SIMD3<Float> = gEye + move
    let target2: SIMD3<Float> = gTarget + move
    let sight2: SIMD3<Float> = gSight + move
    let z: Float = depthAlong(body, eye: eye2, forward: gForward)
    let focus2: Float = depthAlong(target2, eye: eye2, forward: gForward)
    check("D13b it lands at the focus's depth, crisp and drawn", near(z, focus, 1e-3) && band.fade(depth: z, focus: focus2) == 0
          && band.pickable(depth: z, focus: focus2), "\(z)")
    check("D13c on the goal's line of sight", offLine(body, eye: eye2, through: sight2) < 1e-3)
    check("D13d the focus stays as deep (the camera and its target move together)", near(focus2, focus, 1e-4))
}
let nearBody = SIMD3<Float>(0.4, -0.2, 9)      // 1 ahead, nearer than the focus
if let move = GraphDepthGlide.move(body: nearBody, eye: gEye, sight: gSight, forward: gForward, target: gTarget) {
    let eye2: SIMD3<Float> = gEye + move
    check("D13e a body nearer than the focus keeps its depth (the glide as it was): a move across the view only",
          abs((move * gForward).sum()) < 1e-5 && offLine(nearBody, eye: eye2, through: gSight + move) < 1e-4)
} else {
    check("D13e a glide for a near body", false)
}
let behind = SIMD3<Float>(1, 1, 14)            // behind the eye
if let move = GraphDepthGlide.move(body: behind, eye: gEye, sight: gSight, forward: gForward, target: gTarget) {
    check("D13f a body behind the eye is brought round in front, at the focus's depth",
          near(depthAlong(behind, eye: gEye + move, forward: gForward), 2, 1e-3))
} else {
    check("D13f a glide for a body behind the eye", false)
}
check("D13g no glide along a line of sight that does not go ahead",
      GraphDepthGlide.move(body: SIMD3<Float>(0, 0, -30), eye: gEye, sight: SIMD3<Float>(0, 0, 11), forward: gForward,
                           target: gTarget) == nil
      && GraphDepthGlide.move(body: SIMD3<Float>(0, 0, -30), eye: gEye, sight: gEye, forward: gForward, target: gTarget) == nil)

print(failures.isEmpty ? "ALL PASS" : "FAILURES: \(failures.count)")
if !failures.isEmpty { exit(1) }
