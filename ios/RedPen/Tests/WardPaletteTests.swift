// The Ward Round palette: every text colour keeps its promised contrast on
// the surface it sits on, in light and in dark, and the app's AccentColor
// and LaunchBackground assets are the primary (Cards' Care Blue) and the bases
// from the same table.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: - The owner's accepted cases

// The owner, 22 Oct 2026, about 3:44 AM Cairo, shown that the exact colours
// fail the readability checks: "STOP IMPROVISING DONT CHANGE THE COLORS I
// GAVE U". So every colour is the owner's hex as given, white words on the
// fills included, on the plain ground. A check below that falls short only
// because of that passes only as its exact case on the owner's list
// (ios/RedPen/Tests/OwnerAccepted.json, under this file's name), measured
// within 0.01 of the value recorded there. Any other case still fails, and
// so does a listed case no check here measures short.
let ownerFile = "ios/RedPen/Tests/OwnerAccepted.json"
let ownerList: [String: Double] = {
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while !FileManager.default.fileExists(atPath: dir.appendingPathComponent(ownerFile).path), dir.path != "/" {
        dir.deleteLastPathComponent()
    }
    guard let data = FileManager.default.contents(atPath: dir.appendingPathComponent(ownerFile).path),
          let all = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let mine = all["WardPaletteTests.swift"] as? [String: Any] else { return [:] }
    var out: [String: Double] = [:]
    for (key, value) in mine {
        if let n = value as? NSNumber { out[key] = n.doubleValue } else if let d = value as? Double { out[key] = d }
    }
    return out
}()
var ownerSeen: Set<String> = []
/// True only when `measured`, short of its check's threshold, is the
/// owner's accepted case `key` at the value recorded for it.
func owner(_ key: String, _ measured: Double) -> Bool {
    ownerSeen.insert(key)
    guard let listed = ownerList[key] else {
        print("owner-accepted miss: \"\(key)\": " + String(format: "%.3f", measured))
        return false
    }
    guard abs(measured - listed) <= 0.01 else {
        print("owner-accepted moved: \"\(key)\": " + String(format: "%.3f", measured) + ", listed " + String(format: "%.3f", listed))
        return false
    }
    return true
}

check("every token has a value", WardToken.allCases.allSatisfy { WardPalette.table[$0] != nil })
check("white on black is 21", abs(WardPalette.contrast(0xFFFFFF, 0x000000) - 21) < 0.01)
check("Theatre Blue on Clean Sheet is about 6.3",
      abs(WardPalette.contrast(0x1D5FB0, 0xFFFFFF) - 6.3) < 0.1,
      String(WardPalette.contrast(0x1D5FB0, 0xFFFFFF)))

for dark in [false, true] {
    for p in WardPalette.promises {
        let r = WardPalette.contrast(WardPalette.hex(p.text, dark: dark), WardPalette.hex(p.on, dark: dark))
        let label = "\(dark ? "dark" : "light"): \(p.text) on \(p.on) at least \(p.ratio)"
        check(label, r >= p.ratio || owner(label, r), String(format: "%.2f", r))
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
            let label = "\(mode): \(token) reads 4.5:1 on a chip's well"
            check(label, r >= 4.5 || owner(label, r), String(format: "%.3f", r))
        }
        for section in WardSection.allCases {
            let r = WardPalette.contrast(section.accent(dark: dark), ground)
            let label = "\(mode): \(section)'s accent reads 4.5:1 on a chip's well"
            check(label, r >= 4.5 || owner(label, r), String(format: "%.3f", r))
        }
    }
}
// A cloze card's revealed answer is ink on the card, the section's accent an
// underline under it (the owner, 30 Oct, D16): the words read 4.5:1. The
// underline carries no meaning alone (the answer is also bold), so it is not
// held to a ratio: the owner's light accents sit under 3:1.
for dark in [false, true] {
    let words = WardPalette.contrast(WardPalette.hex(.ink, dark: dark), WardPalette.hex(.surface, dark: dark))
    let label = "\(dark ? "dark" : "light"): a cloze answer's ink reads 4.5:1 on the card"
    check(label, words >= 4.5 || owner(label, words), String(format: "%.3f", words))
}
check("the monitor card is dark in both modes",
      WardPalette.luminance(WardPalette.hex(.monitor, dark: false)) < 0.05 &&
      WardPalette.luminance(WardPalette.hex(.monitor, dark: true)) < 0.05)

// one tone (the owner, 22 Oct: "there shouldn't be 2 tones"; 21 Oct, of the
// quiz dock: "one color not two color toned"): a card and a sheet are the
// page colour exactly, so a card is told from the ground only by relief,
// edges and rings. And a well too (the owner, 22 Oct, asked whether wells
// and sheets take the one tone: yes): a field, a track or a chosen segment
// is the page colour, shown as a well by its inset shade alone (the shade
// at a chip's edge is checked above), no longer a soft step darker.
for dark in [false, true] {
    let mode = dark ? "dark" : "light"
    let base = WardPalette.hex(.background, dark: dark)
    check("\(mode): a card is the page colour (surface == background)",
          WardPalette.hex(.surface, dark: dark) == base, String(WardPalette.hex(.surface, dark: dark), radix: 16))
    check("\(mode): a sheet is the page colour (raised == background)",
          WardPalette.hex(.raised, dark: dark) == base, String(WardPalette.hex(.raised, dark: dark), radix: 16))
    check("\(mode): a card and a sheet are one tone (surface == raised)",
          WardPalette.hex(.surface, dark: dark) == WardPalette.hex(.raised, dark: dark))
    check("\(mode): the tiers are well, then the base, a card and a sheet in one colour",
          WardPalette.tiers == [.well, .background, .surface, .raised])
    let well = WardPalette.hex(.well, dark: dark)
    check("\(mode): a well is the page colour (well == background)", well == base, String(well, radix: 16))
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
// (for the owner's cases, how far apart in OKLab the two modes' values sit)
func modesApart(_ token: WardToken) -> Double {
    func lab(_ x: UInt32) -> (Double, Double, Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r0, g0, b0) = WardPalette.rgb(x)
        let (r, g, b) = (linear(r0), linear(g0), linear(b0))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }
    let p = lab(WardPalette.hex(token, dark: false)), q = lab(WardPalette.hex(token, dark: true))
    return ((p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1) + (p.2 - q.2) * (p.2 - q.2)).squareRoot()
}
for token in [WardToken.primaryInk, .ecg, .success, .warning, .danger, .ink, .inkSecondary, .beam] {
    let label = "\(token) has a value of its own in each mode"
    check(label, WardPalette.hex(token, dark: false) != WardPalette.hex(token, dark: true) || owner(label, modesApart(token)),
          String(format: "%.3f apart", modesApart(token)))
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
// Once checked, a wrong pick reads faded, never like the right answer
// (the owner, 16 Oct: "the faded buttons aren't distinguishable from
// correct answers"): its face is plainly grey against the cards, at night
// plainly lighter than them (asked darker or lighter: "lighter") and by day
// as it was, and it is ringed in the faded ink, not the section's, which
// reads 3:1 against the face, the cards and the base at a control's edge
// strength, with and without Increase Contrast.
func chroma(_ x: UInt32) -> Double {
    func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let (r0, g0, b0) = WardPalette.rgb(x)
    let (r, g, b) = (linear(r0), linear(g0), linear(b0))
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return (a * a + bb * bb).squareRoot()
}
let nightFace = WardPalette.hex(.faded, dark: true), nightCard = WardPalette.hex(.surface, dark: true)
check("night: the faded face is plainly lighter than the cards",
      WardPalette.luminance(nightFace) > WardPalette.luminance(nightCard) &&
      WardPalette.contrast(nightFace, nightCard) >= 1.4, String(format: "%.2f", WardPalette.contrast(nightFace, nightCard)))
check("night: the faded face is grey, greyer than the cards",
      chroma(nightFace) <= 0.015 && chroma(nightFace) < chroma(nightCard), String(format: "%.4f", chroma(nightFace)))
check("day: the faded face is as it was", WardPalette.hex(.faded, dark: false) == 0xDDE2E8)
for dark in [false, true] {
    let face = WardPalette.hex(.faded, dark: dark)
    for hc in [false, true] {
        let ring = WardRelief.composite(WardReliefLight(hex: WardPalette.hex(.fadedInk, dark: dark),
                                                        alpha: WardRelief.edgeAlpha(dark: dark, highContrast: hc),
                                                        x: 0, y: 0, radius: 0), on: face)
        for ground in [WardToken.faded, .surface, .background] {
            let r = WardPalette.contrast(ring, WardPalette.hex(ground, dark: dark))
            check("\(dark ? "dark" : "light")\(hc ? " with Increase Contrast" : ""): a wrong pick's ring reads 3:1 on the \(ground)",
                  r >= WardRelief.edgeContrast, String(format: "%.2f", r))
        }
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
check("AccentColor (light) is the primary, Cards' Care Blue", components(nil) == WardPalette.hex(.primary, dark: false),
      String(components(nil) ?? 0, radix: 16))
check("AccentColor (dark) is the night primary ink, Cards' Care Blue", components("dark") == WardPalette.hex(.primaryInk, dark: true),
      String(components("dark") ?? 0, radix: 16))
let launch = root.appendingPathComponent("ios/RedPen/Assets.xcassets/LaunchBackground.colorset/Contents.json")
check("LaunchBackground (light) is the base", components(nil, in: launch) == WardPalette.hex(.background, dark: false),
      String(components(nil, in: launch) ?? 0, radix: 16))
check("LaunchBackground (dark) is the base", components("dark", in: launch) == WardPalette.hex(.background, dark: true),
      String(components("dark", in: launch) ?? 0, radix: 16))

// D16: the cloze gap's underline is the mode colour token. SwiftUI's Text
// ignores underlineColor, so the colour must ride in the line style.
let cardFace = (try? String(contentsOf: root.appendingPathComponent("ios/RedPen/Features/Anki/AnkiCardFace.swift"),
                            encoding: .utf8)) ?? ""
check("the cloze card face is found", !cardFace.isEmpty)
check("a cloze gap's underline takes the mode colour token in its line style (D16)",
      cardFace.contains("gap.underlineStyle = Text.LineStyle(pattern: .solid, color: Color.wardPrimaryInk)"))
check("a cloze gap's words are ink (D16)", cardFace.contains("gap.foregroundColor = Color.wardInk"))
check("no cloze gap sets underlineColor, which Text ignores", !cardFace.contains("underlineColor"))

// T0211 A1: by day, Due's amber words read 1.42:1, New's, Open plan's and the
// chosen dock tab's coral 2.36:1, and the Ideas switcher's pink 2.25:1. Each
// site's words are read from its source and measured, in every section, light
// and dark, with and without Increase Contrast, on what is behind them: the
// base (one tone: the page, a card, the dock's panel) and, for a chip, a pill
// or a chosen segment, the shade inside its well where the words start. No
// owner case excuses a short one (D1: words become ink, the colour goes on
// the glyph). A disabled control's Biro Grey is not held to a ratio (WCAG
// 1.4.3 leaves inactive controls out).
struct WordSite { let file: String; let from: String; let to: String; let name: String; let pressedIn: Bool }
let wordSites: [WordSite] = [
    WordSite(file: "Features/Library/WardHome.swift", from: "private struct HomePill: View {", to: "\n}\n",
             name: "home's countdown pill", pressedIn: true),
    WordSite(file: "Features/Library/WardHome.swift", from: "private struct HomeChip: View {", to: "\n}\n",
             name: "home's Due and New chips", pressedIn: true),
    WordSite(file: "Features/Library/WardHome.swift", from: "private var planButton: some View {", to: "\n    }\n",
             name: "home's Open plan link", pressedIn: false),
    WordSite(file: "Features/Library/StudyCategory.swift", from: "private struct DockItemFace: View {", to: "\n}\n",
             name: "the dock's tab names", pressedIn: true),
    WordSite(file: "Shared/FloatingSwitcher.swift", from: "private struct SwitcherSegment<Value: Hashable>: View {", to: "\n}\n",
             name: "the Ideas switcher's segments", pressedIn: true),
]
/// The colour given to each line of words in `region`: the first
/// `.foregroundStyle(...)` after each `Text(` or `Label(`, as written.
func wordStyles(_ region: String) -> [String] {
    var out: [String] = []
    var at = region.startIndex
    while let call = region.range(of: #"\b(Text|Label)\("#, options: .regularExpression, range: at..<region.endIndex) {
        at = call.upperBound
        guard let style = region.range(of: ".foregroundStyle(", range: call.upperBound..<region.endIndex) else {
            out.append("")
            continue
        }
        var depth = 1
        var i = style.upperBound
        while i < region.endIndex, depth > 0 {
            if region[i] == "(" { depth += 1 } else if region[i] == ")" { depth -= 1 }
            if depth > 0 { i = region.index(after: i) }
        }
        out.append(String(region[style.upperBound..<i]).trimmingCharacters(in: .whitespaces))
    }
    return out
}
/// The palette token a style names (`Color.wardInk` is `.ink`), the enabled
/// side of `enabled ? <token> : Color.wardDisabledInk`; nil for anything
/// else (a tone, a tint, a local colour), which cannot be measured here.
func wordToken(_ style: String) -> WardToken? {
    var s = style
    if let m = s.range(of: #"^enabled \? (Color)?\.ward\w+ : (Color)?\.wardDisabledInk$"#, options: .regularExpression) {
        s = String(s[m].dropFirst("enabled ? ".count).split(separator: " ").first ?? "")
    }
    guard s.range(of: #"^(Color)?\.ward\w+$"#, options: .regularExpression) != nil,
          let ward = s.range(of: ".ward") else { return nil }
    let name = String(s[ward.upperBound...])
    guard let first = name.first else { return nil }
    return WardToken(rawValue: first.lowercased() + name.dropFirst())
}
for site in wordSites {
    let text = (try? String(contentsOf: root.appendingPathComponent("ios/RedPen/" + site.file), encoding: .utf8)) ?? ""
    guard let a = text.range(of: site.from),
          let b = text.range(of: site.to, range: a.upperBound..<text.endIndex) else {
        check("\(site.name): found in \(site.file)", false)
        continue
    }
    let styles = wordStyles(String(text[a.lowerBound..<b.lowerBound]))
    check("\(site.name): every line of words names its colour", !styles.isEmpty && !styles.contains(""),
          "\(styles.count) lines, \(styles.filter(\.isEmpty).count) without a colour")
    for style in styles where !style.isEmpty {
        guard let token = wordToken(style) else {
            check("\(site.name): its words are a palette token, so they can be measured", false, style)
            continue
        }
        for dark in [false, true] {
            for hc in [false, true] {
                for section in WardSection.allCases {
                    let glide = WardGlide.rest(WardLook(dark: dark, section: section))
                    var grounds: [(String, UInt32)] = [WardToken.background, .surface, .raised, .well]
                        .map { ("\($0)", glide.hex($0, dark: dark)) }
                    if site.pressedIn {
                        grounds.append(("its well", WardRelief.insetGround(glide.hex(.well, dark: dark), lift: .low, dark: dark,
                                                                         highContrast: hc, depth: chipTextDepth)))
                    }
                    for (on, ground) in grounds {
                        let r = WardPalette.contrast(glide.hex(token, dark: dark), ground)
                        check("\(dark ? "dark" : "light")\(hc ? " with Increase Contrast" : "") \(section): \(site.name) (\(token)) read 4.5:1 on \(on)",
                              r >= 4.5, String(format: "%.2f", r))
                    }
                }
            }
        }
    }
}

// The owner's list holds only cases a check above measured short.
check("the owner's list is read (\(ownerFile), WardPaletteTests.swift)", !ownerList.isEmpty)
let ownerStale = ownerList.keys.filter { !ownerSeen.contains($0) }.sorted()
check("every case on the owner's list is one a check here measured short", ownerStale.isEmpty,
      ownerStale.joined(separator: "; "))

print(failures.isEmpty ? "\nALL WARD PALETTE TESTS PASS"
                       : "\n\(failures.count) WARD PALETTE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
