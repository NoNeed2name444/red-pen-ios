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

check("the lifts are ordered low to peak", WardLift.allCases == WardLift.allCases.sorted() && WardLift.low < .peak)
check("a light on its own colour at full strength is that colour",
      WardRelief.composite(WardReliefLight(hex: 0x123456, alpha: 1, x: 0, y: 0, radius: 0), on: 0xFFFFFF) == 0x123456)
check("a light at no strength leaves the base",
      WardRelief.composite(WardReliefLight(hex: 0x123456, alpha: 0, x: 0, y: 0, radius: 0), on: 0xE0E5EC) == 0xE0E5EC)

print(failures.isEmpty ? "\nALL WARD RELIEF TESTS PASS"
                       : "\n\(failures.count) WARD RELIEF TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
