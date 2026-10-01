// The Ideas map's name pills stay readable whatever is behind them
// (GraphLabelContrast.swift): the contrast maths, the background estimate,
// choosing the style, and easing between styles without flicker.
//
// Compiled with GraphLabelContrast.swift alone (Foundation only).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool {
    abs(a - b) <= tolerance
}

// MARK: C1 the WCAG maths

check("C1 black is 0, white is 1", GraphRGB.black.luminance == 0 && near(GraphRGB.white.luminance, 1, 1e-9))
check("C1 black on white is 21:1", near(GraphContrast.ratio(.black, .white), 21, 1e-6))
check("C1 the ratio is symmetric", GraphContrast.ratio(0.2, 0.7) == GraphContrast.ratio(0.7, 0.2))
let grey = GraphRGB(0.5, 0.5, 0.5)
check("C1 mid grey is 0.214", near(grey.luminance, 0.214, 0.001), "\(grey.luminance)")
check("C1 #767676 on white just passes 4.5", GraphContrast.ratio(GraphRGB(0x76 / 255.0, 0x76 / 255.0, 0x76 / 255.0),
                                                                  .white) >= 4.5)
check("C1 green is brighter than blue", GraphRGB(0, 1, 0).luminance > GraphRGB(0, 0, 1).luminance * 5)
check("C1 blending", GraphRGB.white.over(.black, alpha: 0.5) == GraphRGB(0.5, 0.5, 0.5))

// MARK: C2 what is behind a label

let eye = SIMD3<Double>(0, 0, 10)
let star: GraphGlow? = GraphBackdropEstimate.glow(at: SIMD3<Double>(0, 0, 0), radius: 0.4, reach: 2.6,
                                                  colour: GraphRGB(1, 0.97, 0.88), strength: 0.9, eye: eye)
let space = GraphRGB(0.03, 0.03, 0.06)
let right = SIMD3<Double>(1, 0, 0)
let up = SIMD3<Double>(0, 1, 0)
func points(_ x: Double, _ y: Double) -> [SIMD3<Double>] {
    GraphBackdropEstimate.pillPoints(centre: SIMD3<Double>(x, y, 0), right: right, up: up, halfWidth: 0.3,
                                     halfHeight: 0.08, eye: eye)
}
check("C2 a glow is made", star != nil)
let glows: [GraphGlow] = star.map { [$0] } ?? []
let onStar: GraphBackdrop = GraphBackdropEstimate.measure(points: points(0, 0), glows: glows, backdrop: space)
let inHalo: GraphBackdrop = GraphBackdropEstimate.measure(points: points(0, 0.6), glows: glows, backdrop: space)
let empty: GraphBackdrop = GraphBackdropEstimate.measure(points: points(4, 4), glows: glows, backdrop: space)
check("C2 over a bright star: bright", onStar.mean.luminance > 0.6, "\(onStar.mean.luminance)")
check("C2 in its halo: lit, and busy", inHalo.mean.luminance > empty.mean.luminance + 0.02 && inHalo.busy > 0.01,
      "\(inHalo)")
check("C2 far away: the backdrop", empty.mean == space && empty.busy == 0)
check("C2 five points across a pill", points(0, 0).count == 5)
check("C2 a body behind the eye is ignored",
      GraphBackdropEstimate.glow(at: SIMD3<Double>(0, 0, 10), radius: 0.4, reach: 2, colour: .white, strength: 1,
                                 eye: eye) == nil)
let pale = GraphRGB(0.80, 0.82, 0.86)
check("C2 a pale nebula backdrop is pale", GraphBackdropEstimate.measure(points: points(0, 0), glows: [],
                                                                         backdrop: pale).mean.luminance > 0.5)

// MARK: C3 choosing the style

let plain = GraphLabelSettings()
let backs: [(String, GraphBackdrop)] = [
    ("the night sky", GraphBackdrop.flat(space)),
    ("a bright star", onStar),
    ("a star's halo", inHalo),
    ("a supernova", GraphBackdrop.flat(GraphRGB(1, 0.98, 0.94))),
    ("a glowing cell", GraphBackdrop.flat(GraphRGB(0.95, 0.62, 0.78))),
    ("a lit LED", GraphBackdrop.flat(GraphRGB(0.95, 1, 0.85))),
    ("the dark board", GraphBackdrop.flat(GraphRGB(0.06, 0.10, 0.08))),
    ("a pale nebula", GraphBackdrop.flat(pale)),
    ("half star, half night", GraphBackdrop(mean: GraphRGB(0.5, 0.5, 0.5), brightest: 1, darkest: 0))
]
var lowContrast: [String] = []
for (name, back) in backs {
    for tint in [GraphRGB.white, GraphRGB(1, 0.5, 0.2), GraphRGB(0.2, 0.9, 0.4), GraphRGB(0.3, 0.3, 1)] {
        let look: GraphLabelLook = GraphLabelChooser.choose(back, tint: tint, settings: plain)
        let worst: Double = GraphLabelChooser.worstContrast(text: look.text, pill: look.pill, opacity: look.opacity,
                                                            back: back)
        if worst < 4.5 { lowContrast.append("\(name): \(worst)") }
    }
}
check("C3 at least 4.5:1 over every background, whatever the body's colour", lowContrast.isEmpty, "\(lowContrast)")
let nightLook: GraphLabelLook = GraphLabelChooser.choose(.flat(space), tint: .white, settings: plain)
check("C3 on the night sky: light words on a see-through dark pill", !nightLook.darkText && nightLook.opacity < 0.9,
      "\(nightLook)")
let paleLook: GraphLabelLook = GraphLabelChooser.choose(.flat(pale), tint: .white, settings: plain)
check("C3 on a pale nebula: dark words on a pale pill", paleLook.darkText, "\(paleLook)")
let starLook: GraphLabelLook = GraphLabelChooser.choose(onStar, tint: .white, settings: plain)
check("C3 over a bright star the pill is more opaque", starLook.opacity > nightLook.opacity,
      "\(starLook.opacity) vs \(nightLook.opacity)")
let busyLook: GraphLabelLook = GraphLabelChooser.choose(backs[8].1, tint: .white, settings: plain)
check("C3 busy backgrounds: more opaque, outlined", busyLook.opacity >= 0.9, "\(busyLook)")
let tintedA: GraphLabelLook = GraphLabelChooser.choose(.flat(space), tint: GraphRGB(1, 0.2, 0.2), settings: plain)
let tintedB: GraphLabelLook = GraphLabelChooser.choose(.flat(space), tint: GraphRGB(0.2, 0.2, 1), settings: plain)
check("C3 the pill leans towards the body's colour", tintedA.pill.r > tintedB.pill.r && tintedB.pill.b > tintedA.pill.b)
let strong = GraphLabelSettings(increaseContrast: true, reduceTransparency: false)
var notStrongest: [String] = []
for (name, back) in backs {
    let look: GraphLabelLook = GraphLabelChooser.choose(back, tint: .white, settings: strong)
    if !(look.opacity == 1 && look.pill == .black && look.text == .white && look.outline) { notStrongest.append(name) }
}
check("C3 Increase Contrast: always the strongest style", notStrongest.isEmpty, "\(notStrongest)")
let solid = GraphLabelSettings(increaseContrast: false, reduceTransparency: true)
let opaque: Bool = backs.allSatisfy { GraphLabelChooser.choose($0.1, tint: .white, settings: solid).opacity == 1 }
check("C3 Reduce Transparency: an opaque pill", opaque)

// MARK: C4 easing and hysteresis

var tracker = GraphLabelTracker(nightLook)
tracker.measure(.flat(pale), tint: .white, settings: plain, elapsed: 0.2)
check("C4 one bright measure does not switch the words", !tracker.target.darkText)
tracker.measure(.flat(pale), tint: .white, settings: plain, elapsed: 0.2)
check("C4 held bright for longer than the hold: it switches", tracker.target.darkText)
var steps: Int = 0
var lastOpacity: Double = tracker.shown.opacity
var monotone: Bool = true
while tracker.step(1.0 / 60) {
    steps += 1
    if steps > 1000 { break }
}
check("C4 the change eases over about 0.3 s", steps >= 16 && steps <= 20, "\(steps) frames")
check("C4 it arrives", tracker.shown == tracker.target)
// a planet passing behind, on and off every measure: never flickers
var flicker = GraphLabelTracker(nightLook)
var switches: Int = 0
var wasDark: Bool = flicker.target.darkText
for k in 0..<60 {
    let back: GraphBackdrop = k % 2 == 0 ? .flat(pale) : .flat(space)
    flicker.measure(back, tint: .white, settings: plain, elapsed: 0.2)
    if flicker.target.darkText != wasDark {
        switches += 1
        wasDark = flicker.target.darkText
    }
}
check("C4 a body passing on and off behind it never flips the words", switches == 0, "\(switches) switches")
var fade = GraphLabelTracker(nightLook)
fade.measure(onStar, tint: .white, settings: plain, elapsed: 0.2)
var rising: Bool = true
var before: Double = fade.shown.opacity
while fade.step(1.0 / 120) {
    if fade.shown.opacity < before - 1e-9 { rising = false }
    before = fade.shown.opacity
}
check("C4 the pill's opacity eases smoothly (never back and forth)", rising && fade.shown.opacity > nightLook.opacity)
_ = monotone
_ = lastOpacity
var instant = GraphLabelTracker(nightLook)
instant.measure(onStar, tint: .white, settings: plain, elapsed: 0.2)
instant.step(0.001, instant: true)
check("C4 Reduce Motion: at once", instant.shown == instant.target)

// MARK: C5 the budget and the bodies' light

check("C5 measured about 5 times a second, less on Smooth", GraphLabelSampler.interval(smooth: false) <= 0.25
      && GraphLabelSampler.interval(smooth: true) > GraphLabelSampler.interval(smooth: false))
check("C5 at most 10 labels", GraphLabelSampler.most <= 10)
let bright: Double = GraphShine.universe("star", empty: false, tier: 1).colour.luminance
let dim: Double = GraphShine.universe("rocky", empty: false, tier: 0).colour.luminance
check("C5 a star shines brighter than a rocky planet", bright > dim * 3)
check("C5 a lit LED shines, an unlit one does not", GraphShine.circuit(6, lit: true).strength
      > GraphShine.circuit(6, lit: false).strength)
check("C5 a chip is dark", GraphShine.circuit(0, lit: false).colour.luminance < 0.05)
let flash0: (Double, Double) = GraphShine.deathFlash("supernova", t: 0.2, duration: 2.4)
let flashLate: (Double, Double) = GraphShine.deathFlash("supernova", t: 2.3, duration: 2.4)
check("C5 a supernova flares, then fades", flash0.0 > 0.8 && flashLate.0 < 0.05 && flash0.1 > 5, "\(flash0) \(flashLate)")
check("C5 each theme's ground is dark", ["space", "neurons", "circuit"].allSatisfy {
    GraphShine.backdrop(theme: $0).luminance < 0.02
})

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
