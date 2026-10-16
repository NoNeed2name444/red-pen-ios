// The Ward Round palette: every text colour keeps its promised contrast on
// the surface it sits on, in light and in dark, and the app's AccentColor
// and LaunchBackground assets are the primary (Cards' indigo) and the bases
// from the same table.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

check("every token has a value", WardToken.allCases.allSatisfy { WardPalette.table[$0] != nil })
check("white on black is 21", abs(WardPalette.contrast(0xFFFFFF, 0x000000) - 21) < 0.01)
check("Theatre Blue on Clean Sheet is about 6.3",
      abs(WardPalette.contrast(0x1D5FB0, 0xFFFFFF) - 6.3) < 0.1,
      String(WardPalette.contrast(0x1D5FB0, 0xFFFFFF)))

for dark in [false, true] {
    for p in WardPalette.promises {
        let r = WardPalette.contrast(WardPalette.hex(p.text, dark: dark), WardPalette.hex(p.on, dark: dark))
        check("\(dark ? "dark" : "light"): \(p.text) on \(p.on) at least \(p.ratio)", r >= p.ratio,
              String(format: "%.2f", r))
    }
}
// The words of a chip or a pill sit on a well pressed into what is under
// it, with the well's inner shade over its edge (the review's B4). Every ink
// a chip can wear reads 4.5:1 on it, in light and dark, with and without
// Increase Contrast (which deepens the shade): the semantic tones' words,
// Biro Grey, Chart Ink and the primary, and every section's accent, which
// is what the New chip and the bed chips take.
check("the shade is there at a chip's edge and gone where its words start",
      WardRelief.shadeCoverage(.low, depth: 0) > 0.5 && WardRelief.shadeCoverage(.low, depth: 6) < 0.01)
let chipInks: [WardToken] = [.primaryInk, .ecg, .success, .warning, .danger, .inkSecondary, .ink]
// the nearest a chip's words come to its edge: its vertical padding (4)
// and the line's own leading above a capital (2 at least)
let chipTextDepth = 6.0
for dark in [false, true] {
    for hc in [false, true] {
        let mode = "\(dark ? "dark" : "light")\(hc ? " with Increase Contrast" : "")"
        let well = WardPalette.hex(.well, dark: dark)
        let ground = WardRelief.insetGround(well, lift: .low, dark: dark, highContrast: hc, depth: chipTextDepth)
        for token in chipInks {
            let r = WardPalette.contrast(WardPalette.hex(token, dark: dark), ground)
            check("\(mode): \(token) reads 4.5:1 on a chip's well", r >= 4.5, String(format: "%.3f", r))
        }
        for section in WardSection.allCases {
            let r = WardPalette.contrast(section.accent(dark: dark), ground)
            check("\(mode): \(section)'s accent reads 4.5:1 on a chip's well", r >= 4.5, String(format: "%.3f", r))
        }
    }
}
check("the monitor card is dark in both modes",
      WardPalette.luminance(WardPalette.hex(.monitor, dark: false)) < 0.05 &&
      WardPalette.luminance(WardPalette.hex(.monitor, dark: true)) < 0.05)

// soft UI on close tiers: a well, the base, a card, a sheet, each a shade
// off the one before, so a card is told from the ground mostly by relief
for dark in [false, true] {
    let mode = dark ? "dark" : "light"
    let lum = WardPalette.tiers.map { WardPalette.luminance(WardPalette.hex($0, dark: dark)) }
    check("\(mode): the tiers rise from well to sheet", lum == lum.sorted() && Set(lum).count == lum.count)
    for (a, b) in zip(WardPalette.tiers, WardPalette.tiers.dropFirst()) {
        let step = WardPalette.contrast(WardPalette.hex(a, dark: dark), WardPalette.hex(b, dark: dark))
        check("\(mode): \(a) to \(b) is a soft step", step > 1.02 && step < 1.25, String(format: "%.3f", step))
    }
    let groove = WardPalette.contrast(WardPalette.hex(.hairline, dark: dark), WardPalette.hex(.background, dark: dark))
    check("\(mode): a groove shows but stays soft", groove >= 1.1 && groove < 1.6,
          String(format: "%.2f", groove))
}
// palette direction 3's grounds (16 Oct): the launch screen is drawn on them
check("the bases the launch screen is drawn on are kept",
      WardPalette.hex(.background, dark: false) == 0xE9EDF2 && WardPalette.hex(.background, dark: true) == 0x171C24)

// two characters, not one palette inverted: every text colour differs
// between the modes. (The check that the night accent sits 12 degrees or
// more from the day's is retired: it pinned the old cyan night, and the
// owner's indigo is one hue in both modes, 8.7 degrees apart.) The primary
// is the look outside any section: Cards' fill and accent.
for dark in [false, true] {
    check("\(dark ? "dark" : "light"): primary and primaryInk are Cards' fill and accent",
          WardPalette.hex(.primary, dark: dark) == WardSection.cards.fill(dark: dark) &&
          WardPalette.hex(.primaryInk, dark: dark) == WardSection.cards.accent(dark: dark) &&
          WardSection.outside == .cards)
}
for token in [WardToken.primaryInk, .ecg, .success, .warning, .danger, .ink, .inkSecondary, .beam] {
    check("\(token) has a value of its own in each mode",
          WardPalette.hex(token, dark: false) != WardPalette.hex(token, dark: true))
}
// night reads its secondary text more strongly than day: dim rooms need it
let daySecondary = WardPalette.contrast(WardPalette.hex(.inkSecondary, dark: false), WardPalette.hex(.background, dark: false))
let nightSecondary = WardPalette.contrast(WardPalette.hex(.inkSecondary, dark: true), WardPalette.hex(.background, dark: true))
check("night's secondary text has more contrast than day's", nightSecondary > daySecondary,
      String(format: "%.2f vs %.2f", nightSecondary, daySecondary))

// the contrast maths, against WCAG's own worked values
check("contrast is symmetric", WardPalette.contrast(0x1D5FB0, 0xE0E5EC) == WardPalette.contrast(0xE0E5EC, 0x1D5FB0))
check("a colour on itself is 1", WardPalette.contrast(0x2A2E35, 0x2A2E35) == 1)
check("mid grey #777 on white is about 4.48 (just under AA)",
      abs(WardPalette.contrast(0x777777, 0xFFFFFF) - 4.48) < 0.01, String(WardPalette.contrast(0x777777, 0xFFFFFF)))
check("#767676 on white is about 4.54 (just AA)",
      abs(WardPalette.contrast(0x767676, 0xFFFFFF) - 4.54) < 0.01, String(WardPalette.contrast(0x767676, 0xFFFFFF)))
check("luminance of white is 1 and black 0", WardPalette.luminance(0xFFFFFF) == 1 && WardPalette.luminance(0) == 0)

// the appearance glide: a colour shift through linear light, from one
// palette to the other, about a third of a second
check("the glide takes 0.3 to 0.4 s", (0.3...0.4).contains(WardSchemeGlide.duration))
for token in WardToken.allCases {
    check("glide \(token): starts at day and ends at night",
          WardSchemeGlide.frame(token, t: 0) == WardPalette.hex(token, dark: false) &&
          WardSchemeGlide.frame(token, t: 1) == WardPalette.hex(token, dark: true))
}
check("mix clamps", WardPalette.mix(0x000000, 0xFFFFFF, -1) == 0 && WardPalette.mix(0x000000, 0xFFFFFF, 2) == 0xFFFFFF)
check("halfway between black and white in linear light is #BCBCBC",
      WardPalette.mix(0x000000, 0xFFFFFF, 0.5) == 0xBCBCBC, String(WardPalette.mix(0, 0xFFFFFF, 0.5), radix: 16))
var lastLum = 2.0
var steady = true
for i in 0...20 {
    let l = WardPalette.luminance(WardSchemeGlide.frame(.background, t: Double(i) / 20))
    if l > lastLum + 1e-9 { steady = false }
    lastLum = l
}
check("the base darkens steadily through the glide, never flashing", steady)

// the spacing scale
check("the scale is 4, 8, 12, 16, 24, 32", WardScale.steps == [4, 8, 12, 16, 24, 32] &&
      [WardScale.xs, WardScale.s, WardScale.m, WardScale.l, WardScale.xl, WardScale.xxl] == WardScale.steps)
check("on the scale", WardScale.onScale(12) && !WardScale.onScale(10) && !WardScale.onScale(20))

check("light: the base is a light grey", WardPalette.luminance(WardPalette.hex(.background, dark: false)) > 0.7)
// 0.010, not 0.015: the owner's #171C24 measures 0.0114, still far from black
check("dark: the base is a dark grey, not black",
      (0.010...0.06).contains(WardPalette.luminance(WardPalette.hex(.background, dark: true))))

// A wrong answer is the faded row (the owner, 15 Oct: "the wrong should be
// faded"), in colours, never opacity: its ink reads 4.5:1 on its face, on
// the quiz's raised row and on the Lens's row pressed into the card (the
// inner shade included, at the chip's text depth), with and without
// Increase Contrast.
for dark in [false, true] {
    let mode = dark ? "dark" : "light"
    let ink = WardPalette.hex(.fadedInk, dark: dark), face = WardPalette.hex(.faded, dark: dark)
    let r = WardPalette.contrast(ink, face)
    check("\(mode): the faded ink reads 4.5:1 on the faded row", r >= 4.5, String(format: "%.2f", r))
    for hc in [false, true] {
        let ground = WardRelief.insetGround(face, lift: .low, dark: dark, highContrast: hc, depth: chipTextDepth)
        let c = WardPalette.contrast(ink, ground)
        check("\(mode)\(hc ? " with Increase Contrast" : ""): the faded ink reads 4.5:1 on its inset row",
              c >= 4.5, String(format: "%.2f", c))
    }
}
for p in WardPalette.monitorPromises {
    let r = WardPalette.contrast(WardPalette.hex(p.text, dark: true), WardPalette.hex(.monitor, dark: true))
    check("monitor: \(p.text) at least \(p.ratio)", r >= p.ratio, String(format: "%.2f", r))
}

// the asset catalogue agrees with the table
// (the suites run from the repository root, or from anywhere under it)
var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
while !FileManager.default.fileExists(atPath: root.appendingPathComponent("ios/RedPen").path), root.path != "/" {
    root.deleteLastPathComponent()
}
let accent = root.appendingPathComponent("ios/RedPen/Assets.xcassets/AccentColor.colorset/Contents.json")
check("the AccentColor asset is found", FileManager.default.fileExists(atPath: accent.path), accent.path)
func components(_ appearance: String?, in asset: URL = accent) -> UInt32? {
    guard let data = try? Data(contentsOf: asset),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let colors = json["colors"] as? [[String: Any]] else { return nil }
    for entry in colors {
        let appearances = entry["appearances"] as? [[String: String]] ?? []
        guard appearances.first?["value"] == appearance,
              let c = (entry["color"] as? [String: Any])?["components"] as? [String: String] else { continue }
        func byte(_ k: String) -> UInt32? { c[k].flatMap { UInt32($0.dropFirst(2), radix: 16) } }
        guard let r = byte("red"), let g = byte("green"), let b = byte("blue") else { return nil }
        return r << 16 | g << 8 | b
    }
    return nil
}
check("AccentColor (light) is the primary, Cards' indigo", components(nil) == WardPalette.hex(.primary, dark: false),
      String(components(nil) ?? 0, radix: 16))
check("AccentColor (dark) is the night primary ink, Cards' indigo", components("dark") == WardPalette.hex(.primaryInk, dark: true),
      String(components("dark") ?? 0, radix: 16))
let launch = root.appendingPathComponent("ios/RedPen/Assets.xcassets/LaunchBackground.colorset/Contents.json")
check("LaunchBackground (light) is the base", components(nil, in: launch) == WardPalette.hex(.background, dark: false),
      String(components(nil, in: launch) ?? 0, radix: 16))
check("LaunchBackground (dark) is the base", components("dark", in: launch) == WardPalette.hex(.background, dark: true),
      String(components("dark", in: launch) ?? 0, radix: 16))

print(failures.isEmpty ? "\nALL WARD PALETTE TESTS PASS"
                       : "\n\(failures.count) WARD PALETTE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
