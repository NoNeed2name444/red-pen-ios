// One animated value for every Ward colour: the light/dark shift and the
// move between sections. Its ends are the palette's own colours, the middle
// is a linear-light mix, every token of a frame is taken at the same point
// (so no frame mixes two looks), a part held in the other mode stays put,
// each section's ink reads as an edge and sits apart (OKLab), and the relief,
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
                           .ecg, .beam, .success, .warning, .danger, .ink, .inkSecondary, .hairline, .monitor,
                           .faded, .fadedInk]
// the look outside any section, whose accents are the palette's own (Cards'
// since direction 3; Questions' were, when they were Theatre Blue)
let day = WardLook(dark: false, section: WardSection.outside)
let night = WardLook(dark: true, section: WardSection.outside)

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
      mid.ink(dark: true, held: true) == WardSection.outside.ink.dark)
check("the app's own page moves while it turns light", toDay.night(dark: false) > 0 && toDay.night(dark: false) < 1)
let sideways = WardGlide(from: day, to: WardLook(dark: false, section: .questions), progress: 0.5)
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
// outside any section the look is Cards (not Questions, or every screen
// without a section would turn red), and the default paper ink is its ink
check("outside any section the look is Cards", WardSection.outside == .cards)
check("the default paper ink is the outside look's",
      WardPaper.ink(dark: false, highContrast: false).hex == WardSection.outside.ink(dark: false) &&
      WardPaper.ink(dark: true, highContrast: false).hex == WardSection.outside.ink(dark: true))
check("Questions: hue 20 and the pinned fills",
      WardSection.questions.hue == 20 && WardSection.questions.fill.light == 0xC03946 &&
      WardSection.questions.fill.dark == 0xCB3E4B)
for dark in [false, true] {
    check("\(dark ? "dark" : "light"): primary and primaryInk equal Cards' fill and accent",
          WardPalette.hex(.primary, dark: dark) == WardSection.cards.fill(dark: dark) &&
          WardPalette.hex(.primaryInk, dark: dark) == WardSection.cards.accent(dark: dark))
}

// OKLab (Ottosson), perceptual: equal distances look about equally
// different, and the hue is the one the eye sees (an HSL hue drifts with
// lightness: a dark yellow reads olive).
func oklab(_ x: UInt32) -> (L: Double, a: Double, b: Double) {
    func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let (r0, g0, b0) = WardPalette.rgb(x)
    let r = linear(r0), g = linear(g0), b = linear(b0)
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}
func hue(_ x: UInt32) -> Double {
    let o = oklab(x)
    let d = atan2(o.b, o.a) * 180 / .pi
    return d < 0 ? d + 360 : d
}
func distance(_ x: UInt32, _ y: UInt32) -> Double {
    let p = oklab(x), q = oklab(y)
    return ((p.L - q.L) * (p.L - q.L) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b)).squareRoot()
}
func apart(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 360); return min(d, 360 - d) }

// How far apart (OKLab) two sections, or a section and a colour that
// means something, must sit to be told apart at a glance. 0.10 would be
// clearly apart; with seven sections and six meanings all at text
// contrast, 0.076 is the most these hue families give (tools/ward_accents.py).
let sectionsApart = 0.075

for dark in [false, true] {
    let mode = dark ? "dark" : "light"
    var closest = 9.0, pair = ""
    for (i, a) in sections.enumerated() {
        for b in sections[(i + 1)...] {
            let d = distance(a.ink(dark: dark), b.ink(dark: dark))
            if d < closest { closest = d; pair = "\(a)/\(b)" }
        }
    }
    check("\(mode): every section's ink is told apart from the others' (0.06)", closest >= 0.06, "\(pair) \(f(closest))")
    for s in sections {
        check("\(mode) \(s): light and dark inks share a hue",
              apart(hue(s.ink.light), hue(s.ink.dark)) <= 4, f(apart(hue(s.ink.light), hue(s.ink.dark))))
    }
    for s in sections {
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

// (from the outside look, Cards, so the move is to Questions)
let toCards = WardGlide(from: day, to: WardLook(dark: false, section: .questions), progress: 0)
var cardsEnd = toCards; cardsEnd.progress = 1
check("a move to Questions starts in indigo and ends in red",
      toCards.ink(dark: false) == WardSection.cards.ink.light && cardsEnd.ink(dark: false) == WardSection.questions.ink.light)
var cardsMid = toCards; cardsMid.progress = 0.5
check("half way it is the linear-light mix, not either",
      cardsMid.ink(dark: false) == WardPalette.mix(WardSection.cards.ink.light, WardSection.questions.ink.light, 0.5))
check("a move between sections leaves the palette alone, but for the accents",
      tokens.filter { $0 != .primary && $0 != .primaryInk }
        .allSatisfy { cardsMid.hex($0, dark: false) == WardPalette.hex($0, dark: false) })
check("half way between sections the accents are the linear-light mix",
      cardsMid.hex(.primaryInk, dark: false) == WardPalette.mix(WardSection.cards.accent.light, WardSection.questions.accent.light, 0.5))
let both = WardGlide(from: day, to: WardLook(dark: true, section: .textbook), progress: 0.5)
let n = both.night(dark: true)
let expect = WardPalette.mix(WardPalette.mix(WardSection.outside.ink.light, WardSection.outside.ink.dark, n),
                             WardPalette.mix(WardSection.textbook.ink.light, WardSection.textbook.ink.dark, n), both.eased)
check("mode and section move together, at the same point", both.ink(dark: true) == expect)

// MARK: - What moves, and what changes in one step

let swap = WardGlide.toward(night, from: .rest(day))
check("light to dark arrives in one step, every colour at once",
      swap.settled && swap.to == night && tokens.allSatisfy { swap.hex($0, dark: true) == WardPalette.hex($0, dark: true) })
let swapBack = WardGlide.toward(WardLook(dark: true, section: .questions), from: cardsMid)
check("a mode change mid-way through a section's shift lands at once too",
      swapBack.settled && swapBack.to == WardLook(dark: true, section: .questions))
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
        check("\(mode) \(s): the palette's own primaryInk stays the palette's",
              rest.paletteHex(.primaryInk, dark: dark) == WardPalette.hex(.primaryInk, dark: dark))
        // the hue is the section's, in all three roles
        for (role, c) in [("ink", s.ink(dark: dark)), ("accent", accent), ("fill", fill)] {
            check("\(mode) \(s): its \(role) is its hue", apart(hue(c), s.hue) <= 2, f(hue(c)))
        }
    }
    // the sections apart from one another in their accents too
    var closest = 9.0, pair = ""
    for (i, a) in sections.enumerated() {
        for b in sections[(i + 1)...] {
            let d = distance(a.accent(dark: dark), b.accent(dark: dark))
            if d < closest { closest = d; pair = "\(a)/\(b)" }
        }
    }
    check("\(mode): every section's accent is told apart from the others'", closest >= sectionsApart, "\(pair) \(f(closest))")
    // and from what means something: right, wrong, due, the ECG red, the
    // beam, and (away from Cards, whose own indigo it is) the primary
    for s in sections {
        var near = 9.0, what = ""
        for token in WardSection.semanticTokens {
            let d = distance(s.accent(dark: dark), WardPalette.hex(token, dark: dark))
            if d < near { near = d; what = "\(token)" }
        }
        if s != .cards {
            let d = distance(s.accent(dark: dark), WardPalette.hex(.primaryInk, dark: dark))
            if d < near { near = d; what = "the primary's indigo" }
        }
        check("\(mode) \(s): the accent is not mistaken for a colour that means something", near >= sectionsApart,
              "\(what) \(f(near))")
        // a wrong answer's faded ink is a grey, never taken for an accent
        let faded = distance(s.accent(dark: dark), WardPalette.hex(.fadedInk, dark: dark))
        check("\(mode) \(s): the faded ink is 0.095 or more from the accent", faded >= 0.095, f(faded))
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

// A colour reads the look as it is drawn (WardLookNow), not as it was
// when a view's body ran: the quiz's right answer, made while the app was
// still outside any section, shows the section the screen set after it,
// in both modes (the owner, 16 Oct: "the color here doesn't match the mode
// color"), and so does every other Ward colour.
do {
    let now = WardLookNow()
    let outside = WardLook(dark: false, section: WardSection.outside)
    check("the look starts outside any section", now.glide == .rest(outside) && WardLookNow.shared.glide == .rest(outside))
    now.set(.rest(WardLook(dark: false, section: .questions)))
    check("a right answer made outside any section shows Questions' accent by day",
          now.hex(.primaryInk, dark: false) == 0x970525, h(now.hex(.primaryInk, dark: false)))
    check("and at night", now.hex(.primaryInk, dark: true) == 0xD98888, h(now.hex(.primaryInk, dark: true)))
    check("and its edges Questions' ink", now.ink(dark: false) == 0xC82D40 && now.ink(dark: true) == 0xF0777A)
    for section in WardSection.allCases {
        for dark in [false, true] {
            now.set(.rest(WardLook(dark: dark, section: section)))
            for token in WardToken.allCases {
                let want: UInt32 = token == .primaryInk ? section.accent(dark: dark)
                    : token == .primary ? section.fill(dark: dark) : WardPalette.hex(token, dark: dark)
                check("drawn now: \(section) \(dark ? "dark" : "light") \(token)", now.hex(token, dark: dark) == want,
                      h(now.hex(token, dark: dark)) + " vs " + h(want))
            }
            check("drawn now: \(section) \(dark ? "dark" : "light") ink", now.ink(dark: dark) == section.ink(dark: dark))
        }
    }
    let shift = WardGlide(from: outside, to: WardLook(dark: false, section: .questions), progress: 0.5)
    now.set(shift)
    check("mid-shift, a colour is this frame's", now.hex(.primaryInk, dark: false) == shift.hex(.primaryInk, dark: false) &&
          now.ink(dark: false) == shift.ink(dark: false))
    check("a part held in one mode keeps it mid-shift",
          now.hex(.primaryInk, dark: true, held: true) == shift.hex(.primaryInk, dark: true, held: true))
    let rest = WardLook(dark: true, section: .audio)
    check("a face or the paper draws the look at rest it was handed",
          WardGlide.drawn(rest: rest, live: shift) == .rest(rest))
    check("and the shift's frame where it was handed none", WardGlide.drawn(rest: nil, live: shift) == shift)
}

// MARK: - A given section's ink (mode tile ring)

// Each mode tile's ring takes the ink of its own mode's section, following
// the light/dark shift without shifting its hue with the section on show.
for section in [WardSection.questions, WardSection.cards] {
    // A glide between two completely different sections (textbook -> osce)
    // shifting from light to dark:
    let shift = WardGlide(from: WardLook(dark: false, section: .textbook),
                          to: WardLook(dark: true, section: .osce),
                          progress: 0)
    check("\(section): at night 0, ink is the section's light ink",
          shift.ink(section, dark: true) == section.ink.light &&
          shift.ink(section, dark: false) == section.ink.light)

    var shiftEnd = shift; shiftEnd.progress = 1
    check("\(section): at night 1, ink is the section's dark ink",
          shiftEnd.ink(section, dark: true) == section.ink.dark)

    for i in 1...9 {
        var mid = shift; mid.progress = Double(i) / 10
        let n = mid.night(dark: true)
        let expected = WardPalette.mix(section.ink.light, section.ink.dark, n)
        check("\(section): frame \(i)/10 is the light/dark mix without hue shift",
              mid.ink(section, dark: true) == expected)
    }

    // At rest in another section (cases)
    let restLight = WardGlide.rest(WardLook(dark: false, section: .cases))
    check("\(section): at rest in another section (light), ink is section's light ink",
          restLight.ink(section, dark: false) == section.ink.light)
    let restDark = WardGlide.rest(WardLook(dark: true, section: .cases))
    check("\(section): at rest in another section (dark), ink is section's dark ink",
          restDark.ink(section, dark: true) == section.ink.dark)
}

do {
    let now = WardLookNow()
    now.set(.rest(WardLook(dark: false, section: .textbook)))
    check("WardLookNow: Questions ink in Textbook section is Questions' light ink",
          now.ink(.questions, dark: false) == WardSection.questions.ink.light)
    check("WardLookNow: Cards ink in Textbook section is Cards' light ink",
          now.ink(.cards, dark: false) == WardSection.cards.ink.light)
}

// MARK: - Each section's wash

for dark in [false, true] {
    let mode = dark ? "dark" : "light"
    let chartInk = WardPalette.hex(.ink, dark: dark)
    let biroGrey = WardPalette.hex(.inkSecondary, dark: dark)
    for s in sections {
        let wash = s.wash(dark: dark)
        let cChart = WardPalette.contrast(chartInk, wash)
        check("\(mode) \(s): Chart Ink keeps 4.5:1 on its wash", cChart >= 4.5, "\(h(wash)) \(f(cChart))")
        let cBiro = WardPalette.contrast(biroGrey, wash)
        check("\(mode) \(s): Biro Grey keeps 4.5:1 on its wash", cBiro >= 4.5, "\(h(wash)) \(f(cBiro))")
        let cAccent = WardPalette.contrast(s.accent(dark: dark), wash)
        check("\(mode) \(s): its accent keeps 4.5:1 on its wash", cAccent >= 4.5, "\(h(wash)) \(f(cAccent))")
    }
    // no two sections' washes are the same
    var washes: [UInt32] = []
    for s in sections {
        let w = s.wash(dark: dark)
        check("\(mode) \(s): wash is unique among sections", !washes.contains(w), h(w))
        washes.append(w)
    }
}

do {
    let now = WardLookNow()
    for section in WardSection.allCases {
        for dark in [false, true] {
            now.set(.rest(WardLook(dark: dark, section: section)))
            check("drawn now: \(section) \(dark ? "dark" : "light") wash",
                  now.wash(dark: dark) == section.wash(dark: dark),
                  h(now.wash(dark: dark)) + " vs " + h(section.wash(dark: dark)))
        }
    }
    let shift = WardGlide(from: day, to: WardLook(dark: false, section: .questions), progress: 0.5)
    now.set(shift)
    let midWash = now.wash(dark: false)
    let expectWash = WardPalette.mix(WardSection.cards.wash(dark: false), WardSection.questions.wash(dark: false), shift.eased)
    check("mid-shift, wash is linear-light mix", midWash == expectWash, "\(h(midWash)) vs \(h(expectWash))")
}

// MARK: - The opening's ground is home's

// The owner, 21 Oct, on the launch's first frame and home: "the background
// color doesn't match the main menu". The first frame (the launch screen's
// LaunchPaper, drawn by tools/make_launch_ground.py) and the opening stand
// on home's own ground: the base with the section's wash, and the grid in
// the section's ink at the paper's strengths, for the section home opens on.

do {
    let library = (try? String(contentsOfFile: "ios/RedPen/Features/Library/LibraryView.swift", encoding: .utf8)) ?? ""
    check("home opens on WardSection.opening: Questions, the dock's first category",
          WardSection.opening == .questions && library.contains("@State var category: StudyCategory = .questions")
          && library.contains(".wardSection(inIdeas ? .ideas : WardSection(rawValue: category.rawValue) ?? .questions)"))
    for section in WardSection.allCases {
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let ground = WardGround.home(section, dark: dark)
            let look = WardGlide.rest(WardLook(dark: dark, section: section))
            check("\(section) \(mode): the ground's base is home's wash (WardBackground)",
                  ground.base == section.wash(dark: dark) && ground.base == look.wash(dark: dark), h(ground.base))
            check("\(section) \(mode): the ground's grid is home's paper ink",
                  ground.ink == WardPaper.ink(look: look, dark: dark, highContrast: false)
                  && ground.ink.hex == section.ink(dark: dark), h(ground.ink.hex))
            check("\(section) \(mode): under Increase Contrast the ground has no grid, as home's paper",
                  WardGround.home(section, dark: dark, highContrast: true).ink.fine == 0
                  && WardGround.home(section, dark: dark, highContrast: true).ink.bold == 0)
        }
    }
}

// The script's colours, for every section in light and dark, are home's:
// it prints the ground it would draw for each (--table).
do {
    let script = "tools/make_launch_ground.py"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", script, "--table"]
    let pipe = Pipe()
    process.standardOutput = pipe
    var table: [String: Any]? = nil
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        table = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    } catch {
        table = nil
    }
    check("\(script) --table runs and prints its grounds", table != nil)
    let rows = table?["sections"] as? [String: [String: [String: Any]]] ?? [:]
    check("the script draws the section home opens on", (table?["opening"] as? String) == WardSection.opening.rawValue,
          "\(table?["opening"] ?? "none")")
    check("the script knows every section", Set(rows.keys) == Set(WardSection.allCases.map(\.rawValue)), "\(rows.keys.sorted())")
    for section in WardSection.allCases {
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let ground = WardGround.home(section, dark: dark)
            let row = rows[section.rawValue]?[mode] ?? [:]
            let base = (row["base"] as? String).flatMap { UInt32($0, radix: 16) }
            let ink = (row["ink"] as? String).flatMap { UInt32($0, radix: 16) }
            check("script, \(section) \(mode): its base is home's ground (base with wash)", base == ground.base,
                  "\(base.map(h) ?? "none") vs \(h(ground.base))")
            check("script, \(section) \(mode): its grid ink is home's", ink == ground.ink.hex
                  && (row["fine"] as? Double) == ground.ink.fine && (row["bold"] as? Double) == ground.ink.bold,
                  "\(ink.map(h) ?? "none") \(row["fine"] ?? "") \(row["bold"] ?? "") vs \(h(ground.ink.hex)) \(ground.ink.fine) \(ground.ink.bold)")
        }
    }
}

// The pictures the launch screen shows were drawn with home's ground: each
// carries the ground it was drawn with (a PNG text chunk, "WardGround"), at
// its idiom's size in points times its scale, so no line is scaled.
do {
    let set = "ios/RedPen/Assets.xcassets/LaunchPaper.imageset/"
    /// The width, height and "WardGround" text of a PNG, read from its
    /// uncompressed chunks.
    func png(_ path: String) -> (width: Int, height: Int, ground: String)? {
        guard let data = FileManager.default.contents(atPath: path), data.count > 33 else { return nil }
        let bytes = [UInt8](data)
        func u32(_ i: Int) -> Int { bytes[i..<i + 4].reduce(0) { $0 << 8 | Int($1) } }
        var ground = ""
        var i = 8
        while i + 8 <= bytes.count {
            let length = u32(i)
            let type = String(decoding: bytes[i + 4..<i + 8], as: UTF8.self)
            guard i + 12 + length <= bytes.count else { break }
            if type == "tEXt" {
                let body = bytes[i + 8..<i + 8 + length]
                if let zero = body.firstIndex(of: 0),
                   String(decoding: body[body.startIndex..<zero], as: UTF8.self) == "WardGround" {
                    ground = String(decoding: body[(zero + 1)...], as: UTF8.self)
                }
            }
            i += 12 + length
        }
        return (u32(16), u32(20), ground)
    }
    func label(_ g: WardGround) -> String {
        func n(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(x) }
        return String(format: "base=#%06X ink=#%06X", g.base, g.ink.hex) + " fine=\(n(g.ink.fine)) bold=\(n(g.ink.bold))"
    }
    for (idiom, size, scales) in [("iphone", (480, 1040), [2, 3]), ("ipad", (1400, 1400), [2])] {
        for dark in [false, true] {
            let ground = WardGround.home(.opening, dark: dark)
            for scale in scales {
                let name = "paper-\(idiom)\(dark ? "-dark" : "")@\(scale)x.png"
                let read = png(set + name)
                check("\(name): drawn at \(scale)x of \(size.0) by \(size.1) points",
                      read?.width == size.0 * scale && read?.height == size.1 * scale,
                      "\(read.map { "\($0.width)x\($0.height)" } ?? "unreadable")")
                let expect = "\(WardSection.opening.rawValue) \(dark ? "dark" : "light") " + label(ground)
                check("\(name): drawn with home's ground", read?.ground == expect,
                      "\(read?.ground ?? "unreadable") vs \(expect)")
            }
        }
    }
}

print(failures.isEmpty ? "\nall passed" : "\n\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
