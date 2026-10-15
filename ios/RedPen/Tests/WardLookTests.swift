// One animated value for every Ward colour: the light/dark shift and the
// move between sections. Its ends are the palette's own colours, the middle
// is a linear-light mix, every token of a frame is taken at the same point
// (so no frame mixes two looks), a part held in the other mode stays put,
// each section's ink reads as an edge and sits apart in hue, and the relief,
// press and paper specs move with it.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func f(_ x: Double) -> String { String(format: "%.3f", x) }
func h(_ x: UInt32) -> String { String(format: "#%06X", x) }

let tokens: [WardToken] = [.background, .surface, .raised, .well, .primary, .primaryInk, .onPrimary,
                           .ecg, .beam, .success, .warning, .danger, .ink, .inkSecondary, .hairline, .monitor]
let day = WardLook(dark: false, section: .questions)
let night = WardLook(dark: true, section: .questions)

// MARK: - Ends and rest

for look in [day, night] {
    let rest = WardGlide.rest(look)
    check("at rest (\(look.dark ? "dark" : "light")): settled", rest.settled)
    let same = tokens.allSatisfy { rest.hex($0, dark: look.dark) == WardPalette.hex($0, dark: look.dark) }
    check("at rest (\(look.dark ? "dark" : "light")): every token is the palette's", same)
    check("at rest: the ink is the section's", rest.ink(dark: look.dark) == look.section.ink(dark: look.dark))
}

let toNight = WardGlide(from: day, to: night, progress: 0)
check("a shift starts at the light palette",
      tokens.allSatisfy { toNight.hex($0, dark: true) == WardPalette.hex($0, dark: false) })
var end = toNight; end.progress = 1
check("and ends at the dark one",
      tokens.allSatisfy { end.hex($0, dark: true) == WardPalette.hex($0, dark: true) })
check("a finished shift is settled", end.settled && !toNight.settled)
check("the shift lasts about a third of a second", (0.3...0.4).contains(WardGlide.duration), f(WardGlide.duration))

// MARK: - Easing

var lastEase = -1.0
var smooth = true
for i in 0...100 {
    var g = toNight; g.progress = Double(i) / 100
    let e = g.eased
    if e < lastEase - 1e-12 { smooth = false }
    lastEase = e
}
check("the easing never runs backwards", smooth)
var mid = toNight; mid.progress = 0.5
check("the easing is symmetric, half way at half time", abs(mid.eased - 0.5) < 1e-12, f(mid.eased))
var early = toNight; early.progress = 0.05
check("the easing starts gently", early.eased < 0.05, f(early.eased))
var over = toNight; over.progress = 1.7
var under = toNight; under.progress = -0.4
check("progress past the ends is held to them", over.eased == 1 && under.eased == 0)

// MARK: - One point for every token (no frame mixes two looks)

for i in 1..<10 {
    var g = toNight; g.progress = Double(i) / 10
    let n = g.night(dark: true)
    let together = tokens.allSatisfy {
        g.hex($0, dark: true) == WardPalette.mix(WardPalette.hex($0, dark: false), WardPalette.hex($0, dark: true), n)
    }
    check("frame \(i)/10: every token sits at the same point of the shift", together)
}
var lastLum = WardPalette.luminance(WardPalette.hex(.background, dark: false))
var falling = true
for i in 1...20 {
    var g = toNight; g.progress = Double(i) / 20
    let l = WardPalette.luminance(g.hex(.background, dark: true))
    if l > lastLum + 1e-9 { falling = false }
    lastLum = l
}
check("the base darkens steadily, without a flash", falling)

// MARK: - Parts held in the other mode

check("a part held in the other mode stays put during a shift",
      mid.night(dark: false) == 0 && mid.hex(.surface, dark: false) == WardPalette.hex(.surface, dark: false))
let toDay = WardGlide(from: night, to: day, progress: 0.5)
check("the always-dark monitor stays dark while the app turns light",
      toDay.night(dark: true) == 1 && toDay.hex(.monitor, dark: true) == WardPalette.hex(.monitor, dark: true))
check("a part marked held stays put, even in the mode the app is heading to",
      mid.night(dark: true, held: true) == 1 && mid.hex(.surface, dark: true, held: true) == WardPalette.hex(.surface, dark: true) &&
      mid.ink(dark: true, held: true) == WardSection.questions.ink.dark)
check("the app's own page moves while it turns light", toDay.night(dark: false) > 0 && toDay.night(dark: false) < 1)
let sideways = WardGlide(from: day, to: WardLook(dark: false, section: .cards), progress: 0.5)
check("a move between sections keeps the palette where it is",
      sideways.night(dark: false) == 0 && sideways.night(dark: true) == 1)

// MARK: - Retargeting

let back = mid.retargeted(day)
check("turning back mid-way runs the same path in reverse from where it is",
      back.from == night && back.to == day && abs(back.progress - 0.5) < 1e-12 &&
      back.hex(.background, dark: false) == mid.hex(.background, dark: true))
var q = toNight; q.progress = 0.25
let backQ = q.retargeted(day)
check("and lands on the same colour, a quarter in",
      backQ.hex(.surface, dark: false) == q.hex(.surface, dark: true),
      h(backQ.hex(.surface, dark: false)) + " vs " + h(q.hex(.surface, dark: true)))
check("the same destination again changes nothing", mid.retargeted(night) == mid)
let fresh = WardGlide.rest(day).retargeted(night)
check("from rest a shift starts at the beginning", fresh.from == day && fresh.to == night && fresh.progress == 0)
let elsewhere = mid.retargeted(WardLook(dark: true, section: .osce))
check("somewhere new starts from where it was headed",
      elsewhere.from == night && elsewhere.to.section == .osce && elsewhere.progress == 0)

// MARK: - Sections

let sections = WardSection.allCases
check("seven sections", sections.count == 7)
check("questions keep the paper's blue",
      WardSection.questions.ink.light == WardPaper.ink(dark: false, highContrast: false).hex &&
      WardSection.questions.ink.dark == WardPaper.ink(dark: true, highContrast: false).hex)

func hue(_ x: UInt32) -> Double {
    let (r, g, b) = WardPalette.rgb(x)
    let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
    guard d > 0 else { return 0 }
    var hh: Double
    if mx == r { hh = (g - b) / d } else if mx == g { hh = (b - r) / d + 2 } else { hh = (r - g) / d + 4 }
    hh *= 60
    return hh < 0 ? hh + 360 : hh
}
func apart(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 360); return min(d, 360 - d) }

for dark in [false, true] {
    let mode = dark ? "dark" : "light"
    var closest = 360.0, pair = ""
    for (i, a) in sections.enumerated() {
        for b in sections[(i + 1)...] {
            let d = apart(hue(a.ink(dark: dark)), hue(b.ink(dark: dark)))
            if d < closest { closest = d; pair = "\(a)/\(b)" }
        }
    }
    check("\(mode): every section's hue sits at least 25 degrees from the others", closest >= 25, "\(pair) \(f(closest))")
    for s in sections {
        check("\(mode) \(s): light and dark inks share a hue",
              apart(hue(s.ink.light), hue(s.ink.dark)) <= 8, f(apart(hue(s.ink.light), hue(s.ink.dark))))
        for tier in [WardToken.background, .surface] {
            let base = WardPalette.hex(tier, dark: dark)
            let c = WardPalette.contrast(WardRelief.edgeColor(s, dark: dark, on: base), base)
            check("\(mode) \(s): a control's edge reads 3:1 on the \(tier)", c >= WardRelief.edgeContrast, f(c))
        }
    }
}
check("set kinds find their section",
      WardSection(kindRaw: "anki") == .cards && WardSection(kindRaw: "book") == .textbook &&
      WardSection(kindRaw: "cases") == .cases && WardSection(kindRaw: "osce") == .osce &&
      WardSection(kindRaw: "narrate") == .audio && WardSection(kindRaw: "mcq") == .questions)

let toCards = WardGlide(from: day, to: WardLook(dark: false, section: .cards), progress: 0)
var cardsEnd = toCards; cardsEnd.progress = 1
check("a move to Cards starts in blue and ends in red",
      toCards.ink(dark: false) == WardSection.questions.ink.light && cardsEnd.ink(dark: false) == WardSection.cards.ink.light)
var cardsMid = toCards; cardsMid.progress = 0.5
check("half way it is the linear-light mix, not either",
      cardsMid.ink(dark: false) == WardPalette.mix(WardSection.questions.ink.light, WardSection.cards.ink.light, 0.5))
check("a move between sections leaves the palette alone, but for the accents",
      tokens.filter { $0 != .primary && $0 != .primaryInk }
        .allSatisfy { cardsMid.hex($0, dark: false) == WardPalette.hex($0, dark: false) })
check("half way between sections the accents are the linear-light mix",
      cardsMid.hex(.primaryInk, dark: false) == WardPalette.mix(WardSection.questions.accent.light, WardSection.cards.accent.light, 0.5))
let both = WardGlide(from: day, to: WardLook(dark: true, section: .textbook), progress: 0.5)
let n = both.night(dark: true)
let expect = WardPalette.mix(WardPalette.mix(WardSection.questions.ink.light, WardSection.questions.ink.dark, n),
                             WardPalette.mix(WardSection.textbook.ink.light, WardSection.textbook.ink.dark, n), both.eased)
check("mode and section move together, at the same point", both.ink(dark: true) == expect)

// MARK: - What moves, and what changes in one step

let swap = WardGlide.toward(night, from: .rest(day))
check("light to dark arrives in one step, every colour at once",
      swap.settled && swap.to == night && tokens.allSatisfy { swap.hex($0, dark: true) == WardPalette.hex($0, dark: true) })
let swapBack = WardGlide.toward(WardLook(dark: true, section: .cards), from: cardsMid)
check("a mode change mid-way through a section's shift lands at once too",
      swapBack.settled && swapBack.to == WardLook(dark: true, section: .cards))
let toOsce = WardGlide.toward(WardLook(dark: true, section: .osce), from: .rest(night))
check("a move between sections shifts, from the start", !toOsce.settled && toOsce.progress == 0)

// Text keeps its contrast on every frame the app can show: never below
// the lower of the two ends (a mix of light and dark falls to about 1.2:1).
func inkOnBase(_ g: WardGlide, dark: Bool) -> Double {
    WardPalette.contrast(g.hex(.ink, dark: dark), g.hex(.background, dark: dark))
}
var worstText = Double.infinity
for (from, to) in [(day, night), (night, day), (day, WardLook(dark: false, section: .audio)),
                   (night, WardLook(dark: true, section: .ideas)), (day, WardLook(dark: true, section: .cases))] {
    var g = WardGlide.toward(to, from: .rest(from))
    let floor = min(inkOnBase(.rest(from), dark: from.dark), inkOnBase(.rest(to), dark: to.dark))
    for i in 0...20 {
        if !g.settled { g.progress = Double(i) / 20 }
        let c = inkOnBase(g, dark: to.dark)
        worstText = min(worstText, c / floor)
    }
}
check("text never loses contrast in any shift the app makes", worstText >= 0.999, f(worstText))
var mixed = WardGlide(from: day, to: night, progress: 0.5)
check("(the mix it avoids: text half way between the palettes is grey on grey)",
      inkOnBase(mixed, dark: true) < 2, f(inkOnBase(mixed, dark: true)))
mixed.progress = 1

// MARK: - Relief, press and paper move with it

for lift in WardLift.allCases {
    check("\(lift): the relief's ends are light and dark",
          WardRelief.raised(lift, night: 0) == WardRelief.raised(lift, dark: false) &&
          WardRelief.raised(lift, night: 1) == WardRelief.raised(lift, dark: true) &&
          WardRelief.rim(lift, night: 0) == WardRelief.rim(lift, dark: false) &&
          WardRelief.rim(lift, night: 1) == WardRelief.rim(lift, dark: true) &&
          WardRelief.inset(lift, night: 1, control: true) == WardRelief.inset(lift, dark: true, control: true))
    let m = WardRelief.rim(lift, night: 0.5)
    let a = WardRelief.rim(lift, dark: false), b = WardRelief.rim(lift, dark: true)
    check("\(lift): half way, the rim's lights sit between",
          m.highlight.alpha >= min(a.highlight.alpha, b.highlight.alpha) &&
          m.highlight.alpha <= max(a.highlight.alpha, b.highlight.alpha) &&
          m.shade.hex == WardPalette.mix(a.shade.hex, b.shade.hex, 0.5))
    check("\(lift): the rim never reaches further half way",
          WardRelief.reach(m.highlight) <= WardRelief.rimReach + 1e-9 && WardRelief.reach(m.shade) <= WardRelief.rimReach + 1e-9)
    check("\(lift): the press's ends are light and dark",
          WardPress.spec(lift, depth: 0.4, night: 0) == WardPress.spec(lift, depth: 0.4, dark: false) &&
          WardPress.spec(lift, depth: 0.4, night: 1) == WardPress.spec(lift, depth: 0.4, dark: true))
}
for hc in [false, true] {
    let p0 = WardPaper.ink(night: 0, highContrast: hc, hex: 0x123456)
    let p1 = WardPaper.ink(night: 1, highContrast: hc, hex: 0x123456)
    let l = WardPaper.ink(dark: false, highContrast: hc), d = WardPaper.ink(dark: true, highContrast: hc)
    check("paper (contrast \(hc)): its strengths run from light to dark, in the section's ink",
          p0.fine == l.fine && p0.bold == l.bold && p1.fine == d.fine && p1.bold == d.bold && p0.hex == 0x123456)
}

// MARK: - Each section's accents

// Every accent role in every section and mode keeps its ratio: words and
// glyphs 4.5:1 on each tier (the well to a sheet), 3:1 as a graphic or
// large text (a progress beam, an icon) on the same; white words 4.5:1 on
// the fill; and the accents read on the vitals monitor, which is dark in
// both modes.
for dark in [false, true] {
    let mode = dark ? "dark" : "light"
    for s in sections {
        let accent = s.accent(dark: dark), fill = s.fill(dark: dark)
        for tier in WardPalette.tiers {
            let c = WardPalette.contrast(accent, WardPalette.hex(tier, dark: dark))
            check("\(mode) \(s): accent words read 4.5:1 on the \(tier)", c >= 4.5, "\(h(accent)) \(f(c))")
            check("\(mode) \(s): accent glyphs read 3:1 on the \(tier)", c >= 3, f(c))
        }
        let white = WardPalette.contrast(WardPalette.hex(.onPrimary, dark: dark), fill)
        check("\(mode) \(s): white words read 4.5:1 on the fill", white >= 4.5, "\(h(fill)) \(f(white))")
        if dark {
            let m = WardPalette.contrast(accent, WardPalette.hex(.monitor, dark: true))
            check("\(s): the accent reads 4.5:1 on the monitor", m >= 4.5, f(m))
        }
        // the glide hands out the section's accents for the palette's
        // accent tokens
        let rest = WardGlide.rest(WardLook(dark: dark, section: s))
        check("\(mode) \(s): at rest the accent tokens are the section's",
              rest.hex(.primaryInk, dark: dark) == accent && rest.hex(.primary, dark: dark) == fill)
        check("\(mode) \(s): the New badge's blue stays the palette's",
              rest.paletteHex(.primaryInk, dark: dark) == WardPalette.hex(.primaryInk, dark: dark))
        // the hue is the section's, in all three roles
        for (role, c) in [("ink", s.ink(dark: dark)), ("accent", accent), ("fill", fill)] where s != .questions {
            check("\(mode) \(s): its \(role) is its hue", apart(hue(c), s.hue) <= 6, f(hue(c)))
        }
    }
    // the sections apart from one another in their accents too
    var closest = 360.0, pair = ""
    for (i, a) in sections.enumerated() {
        for b in sections[(i + 1)...] {
            let d = apart(hue(a.accent(dark: dark)), hue(b.accent(dark: dark)))
            if d < closest { closest = d; pair = "\(a)/\(b)" }
        }
    }
    check("\(mode): every section's accent sits at least 25 degrees from the others", closest >= 25, "\(pair) \(f(closest))")
    // and clear of what means something: right, wrong, due, and (away
    // from Questions, whose own blue it is) the New badge
    for s in sections where s != .questions {
        for token in WardSection.semanticTokens {
            let d = apart(hue(s.accent(dark: dark)), hue(WardPalette.hex(token, dark: dark)))
            check("\(mode) \(s): the accent is clearly not \(token)'s colour (30 degrees)", d >= 30, f(d))
        }
        let blue = apart(hue(s.accent(dark: dark)), hue(WardPalette.hex(.primaryInk, dark: dark)))
        check("\(mode) \(s): the accent is clearly not the New badge's blue (25 degrees)", blue >= 25, f(blue))
    }
}

// Changing section shifts the accents over the glide with their contrast
// never below the lower end (a mix in linear light moves luminance in a
// straight line), and light and dark still swap them in one step.
var worstAccent = Double.infinity, leastAccent = Double.infinity
for dark in [false, true] {
    for a in sections {
        for b in sections where b != a {
            let from = WardLook(dark: dark, section: a), to = WardLook(dark: dark, section: b)
            var g = WardGlide.toward(to, from: .rest(from))
            for tier in WardPalette.tiers {
                let ground = WardPalette.hex(tier, dark: dark)
                let floor = min(WardPalette.contrast(a.accent(dark: dark), ground),
                                WardPalette.contrast(b.accent(dark: dark), ground))
                for i in 0...20 {
                    g.progress = Double(i) / 20
                    let c = WardPalette.contrast(g.hex(.primaryInk, dark: dark), ground)
                    worstAccent = min(worstAccent, c / floor)
                    leastAccent = min(leastAccent, c)
                }
            }
        }
    }
}
// within a byte's rounding of the lower end, and never under 4.5:1
check("a section's shift never drops the accent's contrast below either end", worstAccent >= 0.99, f(worstAccent))
check("a section's shift keeps the accent at 4.5:1 on every frame", leastAccent >= 4.5, f(leastAccent))
let accentSwap = WardGlide.toward(WardLook(dark: true, section: .cards), from: .rest(WardLook(dark: false, section: .cards)))
check("light to dark swaps the accents in one step",
      accentSwap.settled && accentSwap.hex(.primaryInk, dark: true) == WardSection.cards.accent.dark)

// Audio's highlighted line: the line in the accent, pressed into the
// page (a well), and the word being spoken washed in the accent's fill,
// its words in Chart Ink, which keeps 4.5:1 on the wash.
for dark in [false, true] {
    for s in sections {
        let well = WardPalette.hex(.well, dark: dark)
        let wash = WardRelief.composite(WardReliefLight(hex: s.fill(dark: dark), alpha: WardWash.alpha, x: 0, y: 0, radius: 0), on: well)
        let c = WardPalette.contrast(WardPalette.hex(.ink, dark: dark), wash)
        check("\(dark ? "dark" : "light") \(s): words on the spoken word's wash read 4.5:1", c >= 4.5, f(c))
    }
}

print(failures.isEmpty ? "\nall passed" : "\n\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
