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
// T0057: the band is measured in the framing's reach (GraphDepthFrame), so
// these checks run at a reach of 0.4 (the old calls below read through the
// extension at the top), and D14 to D16 check the canonical tilted framing,
// the specialised shader text and Space's per-body opacity.
//
// Compiled with Features/Notes/GraphDepthFade.swift, GraphTilt.swift,
// GraphTheme.swift and Shared/Space/GraphicsQuality.swift, which import only
// Foundation.
import Foundation

/// The whole view at a reach of 0.4, for the checks that only need a band.
let wf: GraphDepthFrame = .whole(0.4)
extension GraphDepthBand {
    func span(focus: Float) -> (start: Float, end: Float) { span(focus: focus, frame: wf) }
    func fade(depth z: Float, focus: Float) -> Float { fade(depth: z, focus: focus, frame: wf) }
    func light(depth z: Float, focus: Float) -> Float { light(depth: z, focus: focus, frame: wf) }
    func cull(focus: Float) -> Float? { cull(focus: focus, frame: wf) }
    func pickable(depth z: Float, focus: Float) -> Bool { pickable(depth: z, focus: focus, frame: wf) }
    func far(focus: Float, near: Float) -> Float? { far(focus: focus, near: near, frame: wf) }
}

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
    let u: SIMD3<Float> = band.uniform(focus: focus, frame: wf)
    check("D1f \(name): the shader is given where the fade starts, one over its width, and its most",
          near(u.x, from, 1e-5) && near(u.y, 1 / (to - from), 1e-5) && u.z == band.most)
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
    check("D2c \(name): the fade starts behind the focus", band.a > 0 && band.b > band.a
          && band.span(focus: 3).start > 3)
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
    check("D4a \(name): Smooth pulls the end in (less drawn)", smooth.b < high.b, "\(smooth.b) \(high.b)")
    check("D4b \(name): High reaches further", high.cull(focus: 10)! > smooth.cull(focus: 10)!)
    check("D4c \(name): both fade all the way, so both cull",
          high.culls && smooth.culls && high.most == 1 && smooth.most == 1)
    check("D4d \(name): the curve begins gently at both (k at least 1)", high.k >= 1 && smooth.k >= 1)
    // rewritten (T0057): the band is now in shares of the framing's reach,
    // so the whole map's far side is the reach itself; the old rule (end at
    // least twice the focus) was for the turned sheet seen face-on
    check("D4e \(name): the band ends at least 0.75 of the reach past the focus (0.55 past its start), and k 1",
          high.b - high.a >= 0.55 && smooth.b - smooth.a >= 0.55 && high.k == 1 && smooth.k == 1)
}
// rewritten (T0057): Space no longer reaches further; it culls its far strip
// in every default view (the per-body fade's speed), the Neurons on High keep
// the whole view drawn and faded
check("D4f Space culls its far strip on both tiers; the Neurons on High draw it all, faded",
      GraphDepthBand.spaceHigh.b < 1 && GraphDepthBand.spaceSmooth.b < 1 && GraphDepthBand.neuronsHigh.b > 1
      && GraphDepthBand.neuronsSmooth.b < 1 && GraphDepthBand.spaceSmooth.b < GraphDepthBand.spaceHigh.b)

// MARK: D5 - Increase Contrast fades less

for theme in themes {
  for tier in tiers {
    let plain: GraphDepthBand = GraphDepthBand.of(theme, tier: tier, contrast: false)!
    let bold: GraphDepthBand = GraphDepthBand.of(theme, tier: tier, contrast: true)!
    check("D5a \(theme.rawValue) \(tier): the fade starts later (a and b times 1.35)",
          bold.a > plain.a && near(bold.a, plain.a * 1.35, 1e-6) && near(bold.b, plain.b * 1.35, 1e-6))
    check("D5e \(theme.rawValue) \(tier): flown in, the band 1.35 times wider and starting where the flight's crisp reach ends",
          near(bold.span(focus: 5, frame: .fly(0.3)).end - bold.span(focus: 5, frame: .fly(0.3)).start,
               1.35 * (plain.span(focus: 5, frame: .fly(0.3)).end - plain.span(focus: 5, frame: .fly(0.3)).start), 1e-4)
          && near(bold.span(focus: 5, frame: .fly(0.3)).start, plain.span(focus: 5, frame: .fly(0.3)).start, 1e-5))
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
    check("D6a \(name): the far plane is the band's end", near(far, band.span(focus: focus).end, 1e-5))
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
          GraphDepthPills.shows(depth: focus, focus: focus, frame: wf, band: band, chosen: false, was: false))
    // rewritten (T0057): the linger is a fade (0.04), not a depth multiple
    check("D8b \(name): never once the cell is fading (no half-faded pill), and a linger only while f < 0.04",
          !GraphDepthPills.shows(depth: start * 1.001, focus: focus, frame: wf, band: band, chosen: false, was: false)
          && GraphDepthPills.lingerFade == 0.04)
    let drawnAt: Float = band.cull(focus: focus).map { $0 * 0.99 } ?? focus * 50
    check("D8c \(name): the chosen cell's pill shows wherever it is drawn",
          GraphDepthPills.shows(depth: drawnAt, focus: focus, frame: wf, band: band, chosen: true, was: false))
    if let far = band.cull(focus: focus) {
        check("D8e \(name): none past the end, chosen or not (the body is not drawn)",
              !GraphDepthPills.shows(depth: far * 1.01, focus: focus, frame: wf, band: band, chosen: true, was: true))
    }
    // rewritten (T0057): lingers by the fade, so at f 0.02 it stays, at 0.06 it goes
    let (_, end8) = band.span(focus: focus)
    let at: (Float) -> Float = { f in start + (end8 - start) * f / band.most }
    check("D8d \(name): a shown pill lingers while f < 0.04, then goes",
          GraphDepthPills.shows(depth: at(0.02), focus: focus, frame: wf, band: band, chosen: false, was: true)
          && !GraphDepthPills.shows(depth: at(0.06), focus: focus, frame: wf, band: band, chosen: false, was: true)
          && !GraphDepthPills.shows(depth: at(0.02), focus: focus, frame: wf, band: band, chosen: false, was: false))
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

// MARK: D10 - how each material fades: light to nothing, never a veil, never a tint

// rewritten (T0057): the solid mode, mixed toward a tint, is gone (defect 9);
// an opaque material is made see-through before it is given the shader
check("D10a added light (and screened, subtracted, maxed) is light", GraphDepthMode.of(adds: true) == .light)
check("D10b anything else is see-through; there is no solid mode", GraphDepthMode.of(adds: false) == .see
      && GraphDepthMode.allCases.count == 2)
check("D10c the modes are 0 and 1", GraphDepthMode.light.rawValue == 0 && GraphDepthMode.see.rawValue == 1)
for f: Float in [0, 0.3, 0.7, 1] {
    let lit = GraphDepthMode.light.apply(0.8, alpha: 1, fade: f)
    check("D10d light at fade \(f): its contribution times 1 - f (no veil)", near(lit.value, 0.8 * (1 - f), 1e-6) && lit.alpha == 1)
    let seen = GraphDepthMode.see.apply(0.6, alpha: 0.5, fade: f)
    check("D10e see-through at fade \(f): colour and coverage times 1 - f",
          near(seen.value, 0.6 * (1 - f), 1e-6) && near(seen.alpha, 0.5 * (1 - f), 1e-6))
}
check("D10g fully faded, nothing is left of either", GraphDepthMode.light.apply(1, alpha: 1, fade: 1).value == 0
      && GraphDepthMode.see.apply(0.9, alpha: 1, fade: 1).alpha == 0)

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

// rewritten (T0057): nothing is counted for 3.5 s after the first frame and
// after each restart, up to 600 gaps are kept, and the line carries dim, out,
// tilt and bad
var meter = GraphDepthMeter()
check("D12a nothing yet: zeros", meter.summary.mean == 0 && meter.summary.worst == 0)
var clock: Double = 10
meter.tick(clock)
while clock < 13.48 { clock += 0.010; meter.tick(clock) }
clock = 13.495
meter.tick(clock)
check("D12g the first 3.5 s are not counted", meter.gaps.isEmpty, "\(meter.gaps.count)")
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
for _ in 0..<1000 {
    clock += 0.008
    meter.tick(clock)
}
check("D12d only the last 600 are kept", meter.gaps.count == GraphDepthMeter.kept && GraphDepthMeter.kept == 600)
let counts = GraphDepthMeter.Counts(drawn: 12, total: 30, dim: 3, out: 0, tilt: 45, bad: 0)
let line: String = meter.label(.on, counts)
check("D12e its line: the state, the numbers, drawn, dim, out, tilt and bad",
      line.hasPrefix("on frame 8.00 p95 8.00 worst 8.00 n 600") && line.hasSuffix("drawn 12/30 dim 3 out 0 tilt 45 bad 0"), line)
check("D12f the probe's fallback shows in the numbers, never as on",
      GraphDepthState.of(asked: true, works: false) == .fallback
      && meter.label(.fallback, counts).hasPrefix("fallback ")
      && GraphDepthState.of(asked: true, works: true) == .on
      && GraphDepthState.of(asked: true, works: true, pixel: true).rawValue == "on/pixel"
      && GraphDepthState.of(asked: true, works: true, glowPixel: true).rawValue == "on/glowpx"
      && GraphDepthState.of(asked: false, works: true) == .off && GraphDepthState.of(asked: false, works: false) == .off)
meter.restart()
clock += 1
meter.tick(clock)
clock += 1
meter.tick(clock)
check("D12h a restart: nothing counted for 3.5 s again", meter.gaps.isEmpty)

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

// MARK: D14 - the canonical tilted framing (T0057)

// a symmetric sheet in the preview's iPhone window, tilted as each theme is
var sheet: [SIMD3<Float>] = []
for y in stride(from: Float(-6), through: 6, by: 0.5) {
    for x in stride(from: Float(-2.5), through: 2.5, by: 0.5) { sheet.append(SIMD3<Float>(x, y, 0)) }
}
for theme in themes {
    let theta: Float = GraphTilt.angle(theme)
    let fit: GraphTiltFit = GraphTilt.fit(points: sheet, pads: sheet.map { _ in 0.3 }, window: GraphTilt.canonical[0],
                                          fill: GraphTilt.canonicalFill, tilt: theta)
    let frame: GraphDepthFrame = .whole(fit.reach)
    let high: GraphDepthBand = GraphDepthBand.of(theme, tier: .high, contrast: false)!
    let edge: Float = high.fade(depth: fit.deepest, focus: fit.focus, frame: frame)
    print("reach \(theme.rawValue): R \(fit.reach), far edge f \(edge)")
    check("D14a \(theme.rawValue) High: the far edge fades at least 0.7", edge >= 0.7, "\(edge)")
    if theme == .space {
        check("D14b space High: and is culled", !high.pickable(depth: fit.deepest, focus: fit.focus, frame: frame))
    }
    check("D14c \(theme.rawValue): the middle is crisp", high.fade(depth: fit.focus, focus: fit.focus, frame: frame) == 0)
    // flown in to one system: every framed point crisp
    let system: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(0.6, 0.2, 0.1), SIMD3<Float>(-0.4, -0.5, -0.2),
                                  SIMD3<Float>(0.1, 0.7, 0.3)]
    let fly: GraphTiltFit = GraphTilt.fit(points: system, pads: system.map { _ in 0.25 }, window: GraphTilt.canonical[1],
                                          fill: 0.88, tilt: theta)
    var allCrisp = true
    for tier in tiers {
        for contrast in [false, true] {
            let band: GraphDepthBand = GraphDepthBand.of(theme, tier: tier, contrast: contrast)!
            for p in system {
                let depth: Float = GraphTilt.project(p, fit: fly, tilt: theta).depth
                if band.fade(depth: depth, focus: fly.focus, frame: .fly(fly.reach)) != 0 { allCrisp = false }
            }
        }
    }
    check("D14d \(theme.rawValue): a fly-in's framed points have f = 0", allCrisp)
}
check("D14e the reach is kept within 0.15 to 1", GraphDepthFrame.whole(0.01).reach == 0.15
      && GraphDepthFrame.whole(4).reach == 1 && GraphDepthFrame.fly(0.5).crisp == 0.52)

// MARK: D15 - the specialised shader text

for (name, band) in bands {
    let text: String = GraphDepthShaderText.fragment(mode: .light, most: band.most, k: band.k)
    check("D15a \(name): marked, no pow (k 1), no matrix", text.hasPrefix(GraphDepthShaderText.marker)
          && !text.contains("pow") && !text.contains("viewTransform") && text.contains("float3 rpDepthSpan"))
    var worst: Float = 0
    for focus: Float in [0.3, 4, 40] {
        let span: SIMD3<Float> = band.uniform(focus: focus, frame: wf)
        for step in 0...300 {
            let z: Float = focus * Float(step) / 100
            worst = max(worst, abs(GraphDepthShaderText.evaluate(depth: z, span: span, k: band.k)
                                   - band.fade(depth: z, focus: focus)))
        }
    }
    check("D15b \(name): its formula equals the band's fade on a depth grid", worst < 1e-5, "\(worst)")
}
check("D15c a curved band's text has its pow; light and see differ",
      GraphDepthShaderText.fragment(mode: .light, most: 1, k: 1.4).contains("pow(")
      && GraphDepthShaderText.fragment(mode: .see, most: 1, k: 1).contains("_output.color *=")
      && GraphDepthShaderText.fragment(mode: .light, most: 1, k: 1).contains("_output.color.rgb *="))

// MARK: D16 - Space per body: opacity 1 - f, in steps of 1/255, hidden at 1

check("D16a opacity is 1 - f", GraphDepthBand.opacity(fade: 0) == 1 && GraphDepthBand.opacity(fade: 0.3) == 0.7
      && GraphDepthBand.opacity(fade: 1) == 0)
check("D16b written only on a step of 1/255 or more", !GraphDepthBand.stepped(from: 0.5, to: 0.5 + 0.5 / 255)
      && GraphDepthBand.stepped(from: 0.5, to: 0.5 + 1.0 / 255) && GraphDepthBand.stepped(from: 0.002, to: 0)
      && GraphDepthBand.stepped(from: 0.999, to: 1))
for (name, band) in bands where band.culls {
    let end: Float = band.span(focus: 6).end
    check("D16c \(name): fully faded is not drawn", band.fade(depth: end, focus: 6) >= 1
          && !band.pickable(depth: end, focus: 6))
}

print(failures.isEmpty ? "ALL PASS" : "FAILURES: \(failures.count)")
if !failures.isEmpty { exit(1) }
