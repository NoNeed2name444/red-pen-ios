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
          let mine = all["WardReliefTests.swift"] as? [String: Any] else { return [:] }
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

for dark in [false, true] {
    let mode = dark ? "dark" : "light"
    let base = WardRelief.base(dark: dark)
    check("\(mode): the relief falls on the palette's base",
          base == WardPalette.hex(.background, dark: dark))

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

        // A control's face has an ink edge at 3:1 or more; a card or a slab
        // has none until Increase Contrast, which strengthens both
        let control = WardRelief.raised(lift, dark: dark, control: true)
        let strong = WardRelief.raised(lift, dark: dark, highContrast: true)
        let strongControl = WardRelief.raised(lift, dark: dark, highContrast: true, control: true)
        let edge = WardPalette.contrast(WardRelief.edgeColor(dark: dark), base)
        let strongEdge = WardPalette.contrast(WardRelief.edgeColor(dark: dark, highContrast: true), base)
        let edgeLabel = "\(tag): a control's edge reads at least 3:1 on the base"
        check(edgeLabel, control.edgeAlpha == WardRelief.edgeAlpha(dark: dark) &&
              (edge >= WardRelief.edgeContrast || owner(edgeLabel, edge)), f(edge))
        check("\(tag): a card has no edge", spec.edgeAlpha == 0)
        check("\(tag): a control's face is a card's with the edge",
              control.highlight == spec.highlight && control.shade == spec.shade && control.inner == spec.inner)
        check("\(tag): pressed in keeps the edge",
              inset.edgeAlpha == spec.edgeAlpha &&
              WardRelief.inset(lift, dark: dark, control: true).edgeAlpha == control.edgeAlpha)
        check("\(tag): Increase Contrast edges a card",
              strong.edgeAlpha == WardRelief.containerHighContrastEdge && strong.edgeAlpha > 0)
        check("\(tag): Increase Contrast strengthens a control's edge, past a card's",
              strongControl.edgeAlpha > control.edgeAlpha && strongEdge > edge &&
              strongControl.edgeAlpha > strong.edgeAlpha, "\(f(strongEdge)) vs \(f(edge))")
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
      WardPress.release == 0.07 && WardPress.shadePress == 0.21 &&
      WardPress.shadeRelease == 0.26 && WardPress.depth == 1 &&
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
            let raised = WardRelief.raised(lift, dark: dark, highContrast: strong, control: true)
            func spec(_ q: Double) -> WardPressSpec {
                WardPress.spec(lift, depth: q, dark: dark, highContrast: strong)
            }
            check("\(lift)/\(dark)/\(strong): a pressable face is a control's, edged",
                  spec(0).edgeAlpha == WardRelief.edgeAlpha(dark: dark, highContrast: strong))
            check("\(lift)/\(dark)/\(strong): an icon tile's is a card's",
                  WardPress.spec(lift, depth: 0.5, dark: dark, highContrast: strong, control: false).edgeAlpha
                    == WardRelief.containerEdgeAlpha(highContrast: strong))
            check("\(lift)/\(dark)/\(strong): depth clamps", spec(-1) == spec(0) && spec(2) == spec(1))
            for q in [-1.0, 0.0, 0.5, 1.0, 2.0] {
                check("a button's outline stays crisp \(lift)/\(dark)/\(strong)/\(q)", spec(q).blur == 0)
                let tile = WardPress.spec(lift, depth: q, dark: dark, highContrast: strong, control: false)
                let extra = min(1, max(0, q))
                check("an icon tile keeps its softness \(lift)/\(dark)/\(strong)/\(q)", near(tile.blur, expected + extra))
                check("an icon tile casts no rim highlight \(lift)/\(dark)/\(strong)/\(q)", !tile.outerHighlight.lit)
            }
            let resting = spec(0), pressed = spec(1)
            check("\(lift)/\(dark)/\(strong): resting lights are the rim",
                  resting.outerShade.lit && resting.outerHighlight.lit && !resting.innerShade.lit && !resting.innerHighlight.lit)
            check("\(lift)/\(dark)/\(strong): pressed lights fall inside",
                  !pressed.outerShade.lit && !pressed.outerHighlight.lit && pressed.innerShade.lit && pressed.innerHighlight.lit)
            let rim = WardRelief.rim(lift, dark: dark, highContrast: strong)
            var previous = spec(0)
            for i in 0...100 {
                let q = Double(i) / 100, up = 1 - q, down = q
                let current = spec(q)
                let lights = [current.outerHighlight, current.outerShade, current.innerShade, current.innerHighlight]
                var deeper = raised.shade
                deeper.alpha = min(1, raised.shade.alpha * 1.25)
                let originals = [rim.highlight, rim.shade, deeper, raised.highlight]
                let weights = [up, up, down, down]
                for j in 0..<4 {
                    let light = lights[j], original = originals[j], w = weights[j]
                    check("spec \(lift)/\(dark)/\(strong)/\(i)/\(j)",
                          light.hex == original.hex && near(light.alpha, original.alpha * w) &&
                          near(light.x, original.x * w) && near(light.y, original.y * w) &&
                          near(light.radius, original.radius * (0.6 + 0.4 * w)))
                }
                check("edge \(i)", current.edgeAlpha == raised.edgeAlpha)
                check("a button's rim never reaches past rimReach \(lift)/\(dark)/\(strong)/\(i)",
                      WardRelief.reach(current.outerHighlight) <= WardRelief.rimReach + 1e-9 &&
                      WardRelief.reach(current.outerShade) <= WardRelief.rimReach + 1e-9)
                let old = [previous.outerHighlight, previous.outerShade, previous.innerShade, previous.innerHighlight]
                check("continuous \(lift)/\(dark)/\(strong)/\(i)", zip(old, lights).allSatisfy {
                    abs($0.alpha - $1.alpha) <= 0.01 + 1e-9 &&
                    abs($0.x - $1.x) <= 0.12 + 1e-9 && abs($0.y - $1.y) <= 0.12 + 1e-9
                })
                previous = current
            }
        }
    }
}

// The rim: the one soft light the app keeps, on buttons only (the owner,
// 14 Oct). Small: 2 points of blur and at most 3 of offset, the whole of it
// within rimReach, which is less than the smallest gap between two
// controls, so it never reaches another control or the words beside it.
check("the rim's reach is under the scale's smallest gap between controls",
      WardRelief.rimReach < WardScale.s && WardRelief.rimReach <= WardRelief.rimMaxOffset + WardRelief.rimMaxBlur)
for dark in [false, true] {
    let base = WardRelief.base(dark: dark)
    var lastReach = 0.0
    for lift in WardLift.allCases {
        for strong in [false, true] {
            let tag = "rim \(dark ? "dark" : "light") \(lift)\(strong ? " strong" : "")"
            let rim = WardRelief.rim(lift, dark: dark, highContrast: strong)
            let wide = WardRelief.raised(lift, dark: dark, highContrast: strong)
            check("\(tag): a blur of 2 points", (2...WardRelief.rimMaxBlur).contains(rim.highlight.radius) &&
                  rim.shade.radius == rim.highlight.radius)
            check("\(tag): a small offset, up and left then down and right",
                  rim.highlight.x < 0 && rim.highlight.y < 0 && rim.shade.x > 0 && rim.shade.y > 0 &&
                  rim.shade.x <= WardRelief.rimMaxOffset && rim.highlight.x == -rim.shade.x)
            check("\(tag): within its reach", WardRelief.reach(rim.highlight) <= WardRelief.rimReach &&
                  WardRelief.reach(rim.shade) <= WardRelief.rimReach)
            check("\(tag): never wider than the relief a card keeps",
                  WardRelief.reach(rim.shade) <= WardRelief.reach(wide.shade) || lift == .low)
            check("\(tag): raised, outside the face", !rim.inner)
            check("\(tag): a control's edge", rim.edgeAlpha == WardRelief.edgeAlpha(dark: dark, highContrast: strong))
            let hi = WardRelief.composite(rim.highlight, on: base), sh = WardRelief.composite(rim.shade, on: base)
            check("\(tag): the highlight is lighter than the base and the shade darker",
                  WardPalette.luminance(hi) > WardPalette.luminance(base) &&
                  WardPalette.luminance(sh) < WardPalette.luminance(base))
            check("\(tag): the two read apart", WardPalette.contrast(hi, sh) >= 1.3, f(WardPalette.contrast(hi, sh)))
            if dark { check("\(tag): no white glare", WardPalette.contrast(hi, base) <= 1.4, f(WardPalette.contrast(hi, base))) }
            if strong {
                check("\(tag): Increase Contrast deepens the shade",
                      rim.shade.alpha > WardRelief.rim(lift, dark: dark).shade.alpha)
            }
        }
        let reach = WardRelief.reach(WardRelief.rim(lift, dark: dark).shade)
        check("rim \(dark) \(lift): a higher button's rim reaches no less", reach >= lastReach)
        lastReach = reach
    }
}

// Paper frame: exact ink, strict size threshold and grid endpoints.
check("paper constants", WardPaper.frame == 12 && WardPaper.cell == 6 &&
      WardPaper.boldEvery == 5 && WardPaper.line == 1 && WardPaper.edgeWidth == 1.5 &&
      near(WardPaper.cornerShare, 53.33 / 428))
for dark in [false, true] {
    for strong in [false, true] {
        let ink = WardPaper.ink(dark: dark, highContrast: strong)
        // the ink outside any section (Cards' Care Blue, the owner's hex in
        // both modes)
        check("paper ink \(dark)/\(strong)",
              ink.hex == 0x3B82F6 &&
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
// The home page's opening, moved down under its header: same sides, bottom
// and corners; held to the frame above and to room for its corners below.
if let base = WardPaper.panel(width: 402, height: 874),
   let low = WardPaper.panel(width: 402, height: 874, top: 280),
   let high = WardPaper.panel(width: 402, height: 874, top: 4),
   let deep = WardPaper.panel(width: 402, height: 874, top: 870) {
    check("paper panel moved down", low.y == 280 && low.x == base.x && low.width == base.width &&
          low.y + low.height == base.y + base.height && low.radius == base.radius)
    check("paper panel never above the frame", high == base)
    check("paper panel keeps room for its corners", near(deep.height, 2 * base.radius) &&
          deep.y + deep.height == base.y + base.height)
} else {
    check("paper moved panel exists", false)
}
let paper30 = WardPaper.lines(30), paper31 = WardPaper.lines(31)
check("paper grid excludes endpoint", paper30.count == 5 &&
      paper30.map { $0.at } == [0, 6, 12, 18, 24] &&
      paper30.filter { $0.bold }.map { $0.at } == [0])
check("paper grid includes next bold", paper31.count == 6 &&
      paper31.map { $0.at } == [0, 6, 12, 18, 24, 30] &&
      paper31.filter { $0.bold }.map { $0.at } == [0, 30])
check("paper nonpositive grid empty", WardPaper.lines(0).isEmpty && WardPaper.lines(-5).isEmpty)

// A band from a global origin: the frame's lines, in local positions.
check("paper band from zero is the frame grid",
      WardPaper.lines(31, from: 0).map { $0.at } == paper31.map { $0.at } &&
      WardPaper.lines(31, from: 0).map { $0.bold } == paper31.map { $0.bold })
let band = WardPaper.lines(20, from: 10)
check("paper band shifts into local positions",
      band.map { $0.at } == [2, 8, 14] && band.map { $0.bold } == [false, false, false],
      "\(band.map { $0.at })")
let bandBold = WardPaper.lines(25, from: 27)
check("paper band keeps the global bold lines",
      bandBold.map { $0.at } == [3, 9, 15, 21] &&
      bandBold.filter { $0.bold }.map { $0.at } == [3],
      "\(bandBold.map { ($0.at, $0.bold) })")
let bandOnLine = WardPaper.lines(12, from: 30)
check("paper band includes a line on its origin, excludes its end",
      bandOnLine.map { $0.at } == [0, 6] && bandOnLine.first?.bold == true)
let bandAbove = WardPaper.lines(14, from: -8)
check("paper band above the origin counts bold lines the same way",
      bandAbove.map { $0.at } == [2, 8] && bandAbove.map { $0.bold } == [false, true],
      "\(bandAbove.map { ($0.at, $0.bold) })")
check("paper band empty for no length", WardPaper.lines(0, from: 40).isEmpty &&
      WardPaper.lines(-3, from: 40).isEmpty && WardPaper.lines(.infinity, from: 0).isEmpty)
var aligned = true
for origin in stride(from: -37.5, through: 211.0, by: 3.25) {
    for line in WardPaper.lines(90, from: origin) {
        let global = line.at + origin
        let k = (global / WardPaper.cell).rounded()
        if abs(k * WardPaper.cell - global) > 1e-9 || line.at < 0 || line.at >= 90 ||
            line.bold != (Int(k) % 5 == 0) { aligned = false }
    }
}
check("paper band lines sit on the frame's grid", aligned)

// Raised and pressed in read apart at a glance, in light and dark, at every
// lift (the owner, 16 Oct: buttons "can't be distinguished between pushed
// and not"). Raised, the rim stands at the largest offset its reach allows
// (2, 2.5, 3, 3), with a crisp blur of 2 and a darker shade (0.9 by day,
// 0.85 at night), and reaches 4 to 5 points, still under the smallest gap
// between two controls. Pressed in, the face sinks the whole of its lift's
// lights, the inner shade a quarter stronger. The shade still starts in at
// the speed it had at the old depth (0.7 over 0.15 and 0.18 seconds).
for (lift, offset) in zip(WardLift.allCases, [2.0, 2.5, 3, 3]) {
    check("raised \(lift): offset \(offset), blur 2", WardRelief.rimOffset(lift) == offset && WardRelief.rimBlur(lift) == 2)
    for dark in [false, true] {
        for strong in [false, true] {
            let tag = "\(lift) \(dark ? "dark" : "light")\(strong ? " strong" : "")"
            let rim = WardRelief.rim(lift, dark: dark, highContrast: strong)
            let shade = min(1, (dark ? 0.85 : 0.9) + (strong ? 0.15 : 0))
            check("raised \(tag): the rim's lights", near(rim.shade.alpha, shade) &&
                  rim.highlight.alpha == (dark ? 0.1 : 0.95) && rim.shade.x == offset && rim.shade.y == offset &&
                  rim.highlight.x == -offset && rim.shade.radius == 2 && rim.highlight.radius == 2,
                  "\(rim.shade.alpha) \(rim.shade.x) \(rim.shade.radius)")
            for light in [rim.highlight, rim.shade] {
                check("raised \(tag): reaches \(offset + 2), within rimReach, under the gap between controls",
                      near(WardRelief.reach(light), offset + 2) && WardRelief.reach(light) <= WardRelief.rimReach &&
                      WardRelief.rimReach == 5 && WardRelief.rimReach < WardScale.s)
            }
            let raised = WardRelief.raised(lift, dark: dark, highContrast: strong, control: true)
            let pressed = WardPress.spec(lift, depth: 1, dark: dark, highContrast: strong)
            check("pressed \(tag): the whole of the lift's shade, a quarter stronger",
                  near(pressed.innerShade.alpha, min(1, raised.shade.alpha * 1.25)) &&
                  near(pressed.innerShade.x, WardRelief.offset(lift)) && near(pressed.innerShade.y, WardRelief.offset(lift)) &&
                  near(pressed.innerShade.radius, WardRelief.radius(lift)),
                  "\(pressed.innerShade.alpha) \(pressed.innerShade.x) \(pressed.innerShade.radius)")
            check("pressed \(tag): and the whole of its highlight",
                  near(pressed.innerHighlight.alpha, raised.highlight.alpha) &&
                  near(pressed.innerHighlight.x, -WardRelief.offset(lift)))
        }
    }
}
check("the shade starts in as fast as at the old depth",
      abs(WardPress.depth / WardPress.shadePress - 0.7 / 0.15) <= 0.03 * 0.7 / 0.15 &&
      abs(WardPress.depth / WardPress.shadeRelease - 0.7 / 0.18) <= 0.03 * 0.7 / 0.18 &&
      WardPress.press == 0.05 && WardPress.release == 0.07)

// Island geometry: continuous arcs joining horizontal lines to the paper frame outline
func nearTol(_ a: Double, _ b: Double, within eps: Double = 0.01) -> Bool {
    abs(a - b) <= eps
}

func joinTangencyDevDeg(corner: WardEdgeCorner, poly: [SIMD2<Double>]) -> Double {
    let radiusV = corner.join - corner.center
    let radiusLen = hypot(radiusV.x, radiusV.y)
    guard radiusLen > 1e-9 else { return 0 }
    let radiusN = radiusV / radiusLen

    var bestDist = Double.infinity
    var bestSegIndex = 0
    for k in 0..<(poly.count - 1) {
        let a = poly[k], b = poly[k + 1]
        let ab = b - a
        let abLenSq = ab.x * ab.x + ab.y * ab.y
        if abLenSq < 1e-12 { continue }
        let t = max(0.0, min(1.0, ((corner.join.x - a.x) * ab.x + (corner.join.y - a.y) * ab.y) / abLenSq))
        let proj = a + t * ab
        let d = hypot(corner.join.x - proj.x, corner.join.y - proj.y)
        if d < bestDist {
            bestDist = d
            bestSegIndex = k
        }
    }
    let segV = poly[bestSegIndex + 1] - poly[bestSegIndex]
    let segLen = hypot(segV.x, segV.y)
    guard segLen > 1e-9 else { return 0 }
    let segT = segV / segLen
    let dot = abs(radiusN.x * segT.x + radiusN.y * segT.y)
    return asin(min(1.0, dot)) * 180.0 / .pi
}

func minPolylineDist(pt: SIMD2<Double>, poly: [SIMD2<Double>]) -> Double {
    var dMin = Double.infinity
    for k in 0..<(poly.count - 1) {
        let a = poly[k], b = poly[k + 1]
        let ab = b - a
        let abLenSq = ab.x * ab.x + ab.y * ab.y
        if abLenSq < 1e-12 {
            dMin = min(dMin, hypot(pt.x - a.x, pt.y - a.y))
        } else {
            let t = max(0.0, min(1.0, ((pt.x - a.x) * ab.x + (pt.y - a.y) * ab.y) / abLenSq))
            let proj = a + t * ab
            dMin = min(dMin, hypot(pt.x - proj.x, pt.y - proj.y))
        }
    }
    return dMin
}

func pointInPoly(_ pt: SIMD2<Double>, poly: [SIMD2<Double>]) -> Bool {
    var inside = false
    var prev = poly.count - 1
    for curr in 0..<poly.count {
        let pi = poly[curr], pj = poly[prev]
        if ((pi.y > pt.y) != (pj.y > pt.y)) &&
            (pt.x < (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y) + pi.x) {
            inside.toggle()
        }
        prev = curr
    }
    return inside
}

// A1 (h): The outline
if let p = WardPaper.panel(width: 402, height: 874) {
    let poly = WardEdge.outline(p)
    let r = p.radius
    let t1 = SIMD2<Double>(p.x + 1.52866483 * r, p.y)
    let t2 = SIMD2<Double>(p.x, p.y + 1.52866483 * r)
    let d1 = poly.map { hypot($0.x - t1.x, $0.y - t1.y) }.min() ?? 1
    let d2 = poly.map { hypot($0.x - t2.x, $0.y - t2.y) }.min() ?? 1
    let minX = p.x, maxX = p.x + p.width, minY = p.y, maxY = p.y + p.height
    var insideAll = true
    for pt in poly {
        if pt.x < minX - 1e-6 || pt.x > maxX + 1e-6 || pt.y < minY - 1e-6 || pt.y > maxY + 1e-6 {
            insideAll = false
        }
    }
    let closed = poly.first == poly.last
    check("outline: closed", closed)
    check("outline: all inside rect", insideAll)
    check("outline: passes through (x + 1.52866483 r, y) within 0.001", d1 <= 0.001, "\(d1)")
    check("outline: passes through (x, y + 1.52866483 r) within 0.001", d2 <= 0.001, "\(d2)")
} else {
    check("outline: panel exists", false)
}

// A1 (a): Window 402 x 874, y 733
if let p = WardPaper.panel(width: 402, height: 874) {
    let poly = WardEdge.outline(p)
    if let j = WardEdge.join(outline: poly, y: 733, radius: p.radius) {
        check("join 402x874 y 733: radius 47.10", nearTol(j.left?.radius ?? 0, 47.10) && nearTol(j.right?.radius ?? 0, 47.10))
        check("join 402x874 y 733: left center (59.10, 780.10)", nearTol(j.left?.center.x ?? 0, 59.10) && nearTol(j.left?.center.y ?? 0, 780.10))
        check("join 402x874 y 733: right center (342.90, 780.10)", nearTol(j.right?.center.x ?? 0, 342.90) && nearTol(j.right?.center.y ?? 0, 780.10))
        check("join 402x874 y 733: left join (12, 780.10)", nearTol(j.left?.join.x ?? 0, 12.0) && nearTol(j.left?.join.y ?? 0, 780.10))
        check("join 402x874 y 733: right join (390, 780.10)", nearTol(j.right?.join.x ?? 0, 390.0) && nearTol(j.right?.join.y ?? 0, 780.10))
        check("join 402x874 y 733: fromX 59.10 toX 342.90", nearTol(j.fromX ?? 0, 59.10) && nearTol(j.toX ?? 0, 342.90))

        if let lc = j.left, let rc = j.right {
            let dLineL = abs(hypot(lc.lineX - lc.center.x, 733.0 - lc.center.y) - lc.radius)
            let dJoinL = abs(hypot(lc.join.x - lc.center.x, lc.join.y - lc.center.y) - lc.radius)
            let dLineR = abs(hypot(rc.lineX - rc.center.x, 733.0 - rc.center.y) - rc.radius)
            let dJoinR = abs(hypot(rc.join.x - rc.center.x, rc.join.y - rc.center.y) - rc.radius)
            check("join 402x874 y 733: arc points on circle within 0.01",
                  dLineL <= 0.01 && dJoinL <= 0.01 && dLineR <= 0.01 && dJoinR <= 0.01)

            let degL = joinTangencyDevDeg(corner: lc, poly: poly)
            let degR = joinTangencyDevDeg(corner: rc, poly: poly)
            check("join 402x874 y 733: join tangent within 0.5 degrees", degL <= 0.5 && degR <= 0.5, "\(degL), \(degR)")
        }
    } else {
        check("join 402x874 y 733: join exists", false)
    }
}

// A1 (b): Windows 834 x 1194, 1194 x 834 and 1032 x 1376, y 128 pt above opening bottom
for (w, h) in [(834.0, 1194.0), (1194.0, 834.0), (1032.0, 1376.0)] {
    if let p = WardPaper.panel(width: w, height: h) {
        let poly = WardEdge.outline(p)
        let maxY = poly.map { $0.y }.max() ?? (p.y + p.height)
        let y = maxY - 128.0
        if let j = WardEdge.join(outline: poly, y: y, radius: p.radius) {
            check("join \(Int(w))x\(Int(h)) y=\(Int(y)): r = 64", nearTol(j.left?.radius ?? 0, 64.0) && nearTol(j.right?.radius ?? 0, 64.0))
            for (side, cOpt) in [("left", j.left), ("right", j.right)] {
                if let c = cOpt {
                    let dJoin = minPolylineDist(pt: c.join, poly: poly)
                    check("join \(Int(w))x\(Int(h)) \(side): join on polyline within 0.1", dJoin <= 0.1, "\(dJoin)")

                    let deg = joinTangencyDevDeg(corner: c, poly: poly)
                    check("join \(Int(w))x\(Int(h)) \(side): tangent within 1 degree", deg <= 1.0, "\(deg)")

                    var maxOut = 0.0
                    for k in 0..<360 {
                        let rad = Double(k) * 2.0 * .pi / 360.0
                        let pt = SIMD2<Double>(c.center.x + c.radius * cos(rad), c.center.y + c.radius * sin(rad))
                        if !pointInPoly(pt, poly: poly) {
                            maxOut = max(maxOut, minPolylineDist(pt: pt, poly: poly))
                        }
                    }
                    check("join \(Int(w))x\(Int(h)) \(side): 360 points inside outline within 0.1", maxOut <= 0.1, "\(maxOut)")
                }
            }
        } else {
            check("join \(Int(w))x\(Int(h)): join exists", false)
        }
    }
}

// A1 (c): Window 402 x 874: y 800 gives r = 31 within 0.01, tangent as in (b); y 840 gives no arcs
if let p = WardPaper.panel(width: 402, height: 874) {
    let poly = WardEdge.outline(p)
    if let j800 = WardEdge.join(outline: poly, y: 800, radius: p.radius) {
        check("join 402x874 y 800: r = 31", nearTol(j800.left?.radius ?? 0, 31.0) && nearTol(j800.right?.radius ?? 0, 31.0))
        if let lc = j800.left {
            let dJoin = minPolylineDist(pt: lc.join, poly: poly)
            let deg = joinTangencyDevDeg(corner: lc, poly: poly)
            check("join 402x874 y 800: tangent as in (b)", dJoin <= 0.1 && deg <= 1.0, "dJoin=\(dJoin), deg=\(deg)")
        }
    } else {
        check("join 402x874 y 800: join exists", false)
    }

    if let j840 = WardEdge.join(outline: poly, y: 840, radius: p.radius) {
        check("join 402x874 y 840: no arcs", j840.left == nil && j840.right == nil)
        if let fx = j840.fromX, let tx = j840.toX {
            let dFrom = minPolylineDist(pt: SIMD2<Double>(fx, 840), poly: poly)
            let dTo = minPolylineDist(pt: SIMD2<Double>(tx, 840), poly: poly)
            check("join 402x874 y 840: fromX and toX on outline within 0.1", dFrom <= 0.1 && dTo <= 0.1, "\(dFrom), \(dTo)")
        } else {
            check("join 402x874 y 840: fromX and toX exist", false)
        }
    } else {
        check("join 402x874 y 840: join exists", false)
    }
}

// A1 (d): In every case above, left and right mirror each other about the window's middle within 0.01 pt.
for (w, h, yVal) in [(402.0, 874.0, 733.0), (834.0, 1194.0, 1194.0 - 12 - 128.0), (402.0, 874.0, 800.0), (402.0, 874.0, 840.0)] {
    if let p = WardPaper.panel(width: w, height: h) {
        let poly = WardEdge.outline(p)
        if let j = WardEdge.join(outline: poly, y: yVal, radius: p.radius) {
            let mid = w / 2.0
            if let lc = j.left, let rc = j.right {
                check("mirroring \(Int(w))x\(Int(h)) y=\(Int(yVal)): centers", nearTol(lc.center.x + rc.center.x, 2 * mid))
                check("mirroring \(Int(w))x\(Int(h)) y=\(Int(yVal)): joins", nearTol(lc.join.x + rc.join.x, 2 * mid))
            }
            if let fx = j.fromX, let tx = j.toX {
                check("mirroring \(Int(w))x\(Int(h)) y=\(Int(yVal)): fromX and toX", nearTol(fx + tx, 2 * mid))
            }
        }
    }
}

// A1 (e): Window 402 x 874, y 733, slab sides at x 28 and 374: slabTopRadius is 31.10 on both sides within 0.01;
// no sampled point of slab's top edge or top corner arcs is above line or outside island's arcs by > 0.01 pt.
// Slab sides at x 120 and 282: 24.
if let p = WardPaper.panel(width: 402, height: 874) {
    let poly = WardEdge.outline(p)
    if let j = WardEdge.join(outline: poly, y: 733, radius: p.radius) {
        let rL = WardEdge.slabTopRadius(j.left, slabSide: 28, leading: true)
        let rR = WardEdge.slabTopRadius(j.right, slabSide: 374, leading: false)
        check("slabTopRadius 28 and 374: 31.10", nearTol(rL, 31.10) && nearTol(rR, 31.10))

        let rL_in = WardEdge.slabTopRadius(j.left, slabSide: 120, leading: true)
        let rR_in = WardEdge.slabTopRadius(j.right, slabSide: 282, leading: false)
        check("slabTopRadius 120 and 282: 24", rL_in == 24 && rR_in == 24)

        // Sample top edge and top corner arcs
        var slabOk = true
        if let lc = j.left, let rc = j.right {
            // Left corner arc
            for k in 0...100 {
                let phi = Double(k) * (.pi / 2.0) / 100.0
                let pt = SIMD2<Double>(28 + rL - rL * sin(phi), 733 + rL - rL * cos(phi))
                if pt.y < 733.0 - 0.01 { slabOk = false }
                if hypot(pt.x - lc.center.x, pt.y - lc.center.y) > lc.radius + 0.01 { slabOk = false }
            }
            // Top edge straight run
            let xStart = 28 + rL, xEnd = 374 - rR
            for k in 0...100 {
                let x = xStart + Double(k) * (xEnd - xStart) / 100.0
                let pt = SIMD2<Double>(x, 733.0)
                if pt.y < 733.0 - 0.01 { slabOk = false }
            }
            // Right corner arc
            for k in 0...100 {
                let phi = Double(k) * (.pi / 2.0) / 100.0
                let pt = SIMD2<Double>(374 - rR + rR * sin(phi), 733 + rR - rR * cos(phi))
                if pt.y < 733.0 - 0.01 { slabOk = false }
                if hypot(pt.x - rc.center.x, pt.y - rc.center.y) > rc.radius + 0.01 { slabOk = false }
            }
        }
        check("slab top edge and corner arcs inside island within 0.01", slabOk)
    } else {
        check("slabTopRadius join exists", false)
    }
}

// A1 (f): Lines under a header: window 402 x 874, y 116: r 47.10, joins (12, 163.10) and (390, 163.10);
// window 834 x 1194, y 90: r = the panel's radius (100.93) within 0.01, tangent as in (b).
if let p = WardPaper.panel(width: 402, height: 874) {
    let poly = WardEdge.outline(p)
    if let j = WardEdge.join(outline: poly, y: 116, radius: p.radius) {
        check("header 402x874 y 116: r 47.10", nearTol(j.left?.radius ?? 0, 47.10))
        check("header 402x874 y 116: joins (12, 163.10) and (390, 163.10)",
              nearTol(j.left?.join.x ?? 0, 12.0) && nearTol(j.left?.join.y ?? 0, 163.10) &&
              nearTol(j.right?.join.x ?? 0, 390.0) && nearTol(j.right?.join.y ?? 0, 163.10))
    }
}
if let p = WardPaper.panel(width: 834, height: 1194) {
    let poly = WardEdge.outline(p)
    if let j = WardEdge.join(outline: poly, y: 90, radius: p.radius) {
        check("header 834x1194 y 90: r = 100.93", nearTol(j.left?.radius ?? 0, 100.93))
        if let lc = j.left {
            let dJoin = minPolylineDist(pt: lc.join, poly: poly)
            let deg = joinTangencyDevDeg(corner: lc, poly: poly)
            check("header 834x1194 y 90: tangent as in (b)", dJoin <= 0.1 && deg <= 1.0, "\(dJoin), \(deg)")
        }
    }
}

// A1 (g): left: false gives no left arc and fromX nil; the right side is as with both.
if let p = WardPaper.panel(width: 402, height: 874) {
    let poly = WardEdge.outline(p)
    let jBoth = WardEdge.join(outline: poly, y: 733, radius: p.radius, left: true, right: true)
    let jRightOnly = WardEdge.join(outline: poly, y: 733, radius: p.radius, left: false, right: true)
    check("left: false gives no left arc and fromX nil", jRightOnly?.left == nil && jRightOnly?.fromX == nil)
    check("left: false keeps right side identical", jRightOnly?.right == jBoth?.right && jRightOnly?.toX == jBoth?.toX)
}

// The owner's list holds only cases a check above measured short.
check("the owner's list is read (\(ownerFile), WardReliefTests.swift)", !ownerList.isEmpty)
let ownerStale = ownerList.keys.filter { !ownerSeen.contains($0) }.sorted()
check("every case on the owner's list is one a check here measured short", ownerStale.isEmpty,
      ownerStale.joined(separator: "; "))

print(failures.isEmpty ? "\nALL WARD RELIEF TESTS PASS"
                       : "\n\(failures.count) WARD RELIEF TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
