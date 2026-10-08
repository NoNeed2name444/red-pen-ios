// Soft UI relief: in light and dark, at every lift, the highlight is lighter
// than the base and the shade darker, the two read apart but softly, they
// grow with the lift, the dark highlight never glares, the same input gives
// the same relief, and pressed in is raised mirrored.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func f(_ x: Double) -> String { String(format: "%.3f", x) }

for dark in [false, true] {
    let mode = dark ? "dark" : "light"
    let base = WardRelief.base(dark: dark)
    check("\(mode): the relief falls on the palette's base",
          base == WardPalette.hex(.background, dark: dark) && base == WardPalette.hex(.surface, dark: dark))

    var last: WardReliefSpec?
    for lift in WardLift.allCases {
        let tag = "\(mode) \(lift)"
        let spec = WardRelief.raised(lift, dark: dark)
        let hi = WardRelief.composite(spec.highlight, on: base)
        let sh = WardRelief.composite(spec.shade, on: base)
        let (lb, lh, ls) = (WardPalette.luminance(base), WardPalette.luminance(hi), WardPalette.luminance(sh))

        check("\(tag): the highlight is lighter than the base", lh > lb, "\(f(lh)) vs \(f(lb))")
        check("\(tag): the shade is darker than the base", ls < lb, "\(f(ls)) vs \(f(lb))")
        let apart = WardPalette.contrast(hi, sh)
        check("\(tag): highlight and shade read apart, softly", apart >= 1.25 && apart <= 2.5, f(apart))
        check("\(tag): each light shows on the base",
              WardPalette.contrast(hi, base) >= 1.08 && WardPalette.contrast(sh, base) >= 1.08,
              "\(f(WardPalette.contrast(hi, base))) / \(f(WardPalette.contrast(sh, base)))")

        // lit from the top left
        check("\(tag): the highlight falls up and left, the shade down and right",
              spec.highlight.x < 0 && spec.highlight.y < 0 && spec.shade.x > 0 && spec.shade.y > 0 &&
              spec.highlight.x == -spec.shade.x && spec.highlight.y == -spec.shade.y)
        check("\(tag): the highlight is white", spec.highlight.hex == 0xFFFFFF)

        // the ranges the design asks for
        if dark {
            check("\(tag): white at 0.05 to 0.09", (0.05...0.09).contains(spec.highlight.alpha), f(spec.highlight.alpha))
            check("\(tag): black at 0.45 to 0.6",
                  spec.shade.hex == 0x000000 && (0.45...0.6).contains(spec.shade.alpha), f(spec.shade.alpha))
            check("\(tag): no white glare", WardPalette.contrast(hi, base) <= 1.4, f(WardPalette.contrast(hi, base)))
        } else {
            check("\(tag): white at 0.7 to 0.9", (0.7...0.9).contains(spec.highlight.alpha), f(spec.highlight.alpha))
            check("\(tag): #A3B1C6 at 0.5 to 0.65",
                  spec.shade.hex == 0xA3B1C6 && (0.5...0.65).contains(spec.shade.alpha), f(spec.shade.alpha))
        }

        // grows with the lift
        if let last {
            check("\(tag): stands further off than the lift below",
                  spec.shade.x > last.shade.x && spec.shade.radius > last.shade.radius &&
                  spec.highlight.alpha >= last.highlight.alpha && spec.shade.alpha >= last.shade.alpha)
            let wasApart = WardPalette.contrast(WardRelief.composite(last.highlight, on: base),
                                                WardRelief.composite(last.shade, on: base))
            check("\(tag): reads at least as strongly as the lift below", apart >= wasApart, "\(f(apart)) vs \(f(wasApart))")
        }
        last = spec

        // deterministic, and pressed in mirrors raised
        check("\(tag): the same input gives the same relief", WardRelief.raised(lift, dark: dark) == spec)
        let inset = WardRelief.inset(lift, dark: dark)
        check("\(tag): raised drops its lights outside, pressed in casts them inside", !spec.inner && inset.inner)
        check("\(tag): pressed in is raised mirrored", inset == spec.mirrored() && inset.mirrored() == spec)
        check("\(tag): pressed in keeps the lights where they are",
              inset.highlight == spec.highlight && inset.shade == spec.shade)

        // Increase Contrast: an ink edge and a deeper shade, nothing else moves
        let strong = WardRelief.raised(lift, dark: dark, highContrast: true)
        check("\(tag): no edge without Increase Contrast", spec.edgeAlpha == 0)
        check("\(tag): Increase Contrast adds an edge at 0.3 to 0.4", (0.3...0.4).contains(strong.edgeAlpha), f(strong.edgeAlpha))
        check("\(tag): Increase Contrast deepens the shade",
              strong.shade.alpha > spec.shade.alpha &&
              WardPalette.luminance(WardRelief.composite(strong.shade, on: base)) < ls)
        check("\(tag): Increase Contrast keeps the geometry and the highlight",
              strong.highlight == spec.highlight && strong.shade.x == spec.shade.x && strong.shade.radius == spec.shade.radius)
        check("\(tag): Increase Contrast pressed in mirrors too",
              WardRelief.inset(lift, dark: dark, highContrast: true) == strong.mirrored())
    }
}

let liftOrder: [Int] = WardLift.allCases.map { $0.rawValue }
check("the lifts are ordered low to peak", liftOrder == liftOrder.sorted() && liftOrder.first == WardLift.low.rawValue
      && liftOrder.last == WardLift.peak.rawValue)
check("pressed in sinks one lift, never below low",
      WardLift.peak.lower == .high && WardLift.high.lower == .mid && WardLift.mid.lower == .low && WardLift.low.lower == .low)
check("a light on its own colour at full strength is that colour",
      WardRelief.composite(WardReliefLight(hex: 0x123456, alpha: 1, x: 0, y: 0, radius: 0), on: 0xFFFFFF) == 0x123456)
check("a light at no strength leaves the base",
      WardRelief.composite(WardReliefLight(hex: 0x123456, alpha: 0, x: 0, y: 0, radius: 0), on: 0xE0E5EC) == 0xE0E5EC)

for (alpha, expected) in [(0.0, false), (1e-4, false), (2e-4, true)] {
    check("light visibility at \(alpha)",
          WardReliefLight(hex: 0xFFFFFF, alpha: alpha, x: 0, y: 0, radius: 0).lit == expected)
}

// The retro press has separate click and shade tracks, with no overshoot.
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 }
check("press constants", WardPress.sinkScale == 0.985 && WardPress.press == 0.05 &&
      WardPress.release == 0.07 && WardPress.shadePress == 0.15 &&
      WardPress.shadeRelease == 0.18 && WardPress.depth == 0.7 &&
      WardPress.softKeep == 0.6 && WardPress.hollowSoft == 1)
let curve = WardPress.quickCurve
check("quick curve controls", near(curve.x1, 1.0 / 3) && curve.y1 == 0.5 &&
      near(curve.x2, 2.0 / 3) && near(curve.y2, 5.0 / 6))
for i in 0...20 {
    let t = Double(i) / 20, v = 1 - t
    let x = 3 * v * v * t * curve.x1 + 3 * v * t * t * curve.x2 + t * t * t
    let y = 3 * v * v * t * curve.y1 + 3 * v * t * t * curve.y2 + t * t * t
    check("Bezier \(i): x=t, y=quick(t)", near(x, t) && near(y, WardPress.quick(t)))
    check("glide \(i)", near(WardPress.glide(t), sin(t * .pi / 2)))
}
check("progress clamps", WardPress.quick(-1) == 0 && WardPress.quick(2) == 1 &&
      WardPress.glide(-1) == 0 && near(WardPress.glide(2), 1))
check("release completes click", WardPress.releaseHold(held: -1) == 0.05 &&
      WardPress.releaseHold(held: 0) == 0.05 && near(WardPress.releaseHold(held: 0.02), 0.03) &&
      WardPress.releaseHold(held: 0.05) == 0 && WardPress.releaseHold(held: 1) == 0)
for (lift, expected) in zip(WardLift.allCases, [1.0, 1.5, 2.0, 2.5]) {
    check("softness \(lift)", near(WardPress.soft(lift), expected))
    for dark in [false, true] {
        for strong in [false, true] {
            let raised = WardRelief.raised(lift, dark: dark, highContrast: strong)
            func spec(_ q: Double) -> WardPressSpec {
                WardPress.spec(lift, depth: q, dark: dark, highContrast: strong)
            }
            check("\(lift)/\(dark)/\(strong): depth clamps", spec(-1) == spec(0) && spec(2) == spec(1))
            for (q, extra) in [(-1.0, 0.0), (0.0, 0.0), (0.5, 0.5), (1.0, 1.0), (2.0, 1.0)] {
                check("blur \(lift)/\(dark)/\(strong)/\(q)", near(spec(q).blur, expected + extra))
            }
            let resting = spec(0), pressed = spec(1)
            check("\(lift)/\(dark)/\(strong): resting lights",
                  resting.outerShade.lit && !resting.innerShade.lit && !resting.innerHighlight.lit)
            check("\(lift)/\(dark)/\(strong): pressed lights",
                  !pressed.outerShade.lit && pressed.innerShade.lit && pressed.innerHighlight.lit)
            var previous = spec(0)
            for i in 0...100 {
                let q = Double(i) / 100, up = 1 - q, down = 0.7 * q
                let current = spec(q)
                let lights = [current.outerShade, current.innerShade, current.innerHighlight]
                let originals = [raised.shade, raised.shade, raised.highlight]
                let weights = [up, down, down]
                for j in 0..<3 {
                    let light = lights[j], original = originals[j], w = weights[j]
                    check("spec \(lift)/\(dark)/\(strong)/\(i)/\(j)",
                          light.hex == original.hex && near(light.alpha, original.alpha * w) &&
                          near(light.x, original.x * w) && near(light.y, original.y * w) &&
                          near(light.radius, original.radius * (0.6 + 0.4 * w)))
                }
                check("edge \(i)", current.edgeAlpha == raised.edgeAlpha)
                let old = [previous.outerShade, previous.innerShade, previous.innerHighlight]
                check("continuous \(lift)/\(dark)/\(strong)/\(i)", zip(old, lights).allSatisfy {
                    abs($0.alpha - $1.alpha) <= 0.01 + 1e-9 &&
                    abs($0.x - $1.x) <= 0.12 + 1e-9 && abs($0.y - $1.y) <= 0.12 + 1e-9
                })
                previous = current
            }
        }
    }
}

// Paper frame: exact ink, strict size threshold and grid endpoints.
check("paper constants", WardPaper.frame == 12 && WardPaper.cell == 6 &&
      WardPaper.boldEvery == 5 && WardPaper.line == 1 && WardPaper.edgeWidth == 1.5 &&
      near(WardPaper.cornerShare, 53.33 / 428))
for dark in [false, true] {
    for strong in [false, true] {
        let ink = WardPaper.ink(dark: dark, highContrast: strong)
        check("paper ink \(dark)/\(strong)",
              ink.hex == (dark ? 0x78AAF5 : 0x2868C4) &&
              ink.fine == (strong ? 0 : (dark ? 0.07 : 0.09)) &&
              ink.bold == (strong ? 0 : (dark ? 0.14 : 0.18)) &&
              ink.edge == (dark ? 0.5 : 0.55))
    }
}
check("paper panel excludes threshold", WardPaper.panel(width: 48, height: 500) == nil &&
      WardPaper.panel(width: 500, height: 48) == nil)
if let panel = WardPaper.panel(width: 49, height: 49) {
    check("paper smallest panel", panel.x == 12 && panel.y == 12 &&
          panel.width == 25 && panel.height == 25 && near(panel.radius, 25 * 53.33 / 428))
} else {
    check("paper smallest panel exists", false)
}
for (width, height) in [(428.0, 926.0), (926.0, 428.0)] {
    if let panel = WardPaper.panel(width: width, height: height) {
        check("paper panel \(width)x\(height)", panel.x == 12 && panel.y == 12 &&
              panel.width == width - 24 && panel.height == height - 24 &&
              near(panel.radius, 404 * 53.33 / 428))
    } else {
        check("paper phone panel exists", false)
    }
}
let paper30 = WardPaper.lines(30), paper31 = WardPaper.lines(31)
check("paper grid excludes endpoint", paper30.count == 5 &&
      paper30.map { $0.at } == [0, 6, 12, 18, 24] &&
      paper30.filter { $0.bold }.map { $0.at } == [0])
check("paper grid includes next bold", paper31.count == 6 &&
      paper31.map { $0.at } == [0, 6, 12, 18, 24, 30] &&
      paper31.filter { $0.bold }.map { $0.at } == [0, 30])
check("paper nonpositive grid empty", WardPaper.lines(0).isEmpty && WardPaper.lines(-5).isEmpty)

print(failures.isEmpty ? "\nALL WARD RELIEF TESTS PASS"
                       : "\n\(failures.count) WARD RELIEF TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
