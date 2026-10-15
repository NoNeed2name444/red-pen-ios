import Foundation

/// The parts of the app, each with a colour of its own (the owner, 14 Oct:
/// "colour difference for each mode"; 15 Oct: the buttons, links and
/// other accents were still blue in every section). Each section has a
/// hue, and every accent is drawn from it: the paper's grid and the
/// controls' edges (`ink`), the words and glyphs of buttons, links, the
/// chosen dock tab and progress (`accent`), and the fills under white
/// words (`fill`). The base, the cards and the body text stay the Ward
/// palette's, and so do the colours that mean something: Discharge green
/// for right, Resus red for wrong, Caution amber for due, the blue New
/// badge. A section's hue keeps clear of those (`semanticHues`), so
/// Cards is no longer red and Textbook no longer green.
enum WardSection: String, CaseIterable, Sendable {
    case questions, cards, textbook, cases, osce, audio, ideas

    /// The hue, in degrees. Questions keep the palette's own blue, as
    /// drawn (its colours below are the palette's, not derived). The rest
    /// sit at least 25 degrees from each other and from Questions' blue
    /// and night cyan, and at least 30 from the semantic hues.
    var hue: Double {
        switch self {
        case .questions: return 214   // Theatre Blue
        case .cases: return 246       // indigo
        case .audio: return 274       // violet
        case .cards: return 300       // orchid
        case .ideas: return 326       // magenta
        case .osce: return 70         // brass
        case .textbook: return 100    // leaf
        }
    }

    /// The section's ink (light, dark) as 0xRRGGBB: the grid's lines and
    /// the controls' edges. Each reads at least 3:1 on the base and on a
    /// card at a control's edge strength (WardRelief.edgeAlpha).
    var ink: (light: UInt32, dark: UInt32) {
        if self == .questions { return (0x2868C4, 0x78AAF5) }   // Theatre Blue paper
        return WardSection.derived[self]!.ink
    }

    /// Words and glyphs in the section's colour (buttons' labels, links,
    /// icons, the chosen tab, progress), light and dark: 4.5:1 on every
    /// tier of its mode, the well to a sheet.
    var accent: (light: UInt32, dark: UInt32) {
        if self == .questions {
            return (WardPalette.hex(.primaryInk, dark: false), WardPalette.hex(.primaryInk, dark: true))
        }
        return WardSection.derived[self]!.accent
    }

    /// A fill in the section's colour, under white words (a switch that
    /// is on, a chosen segment): white reads 4.5:1 on it.
    var fill: (light: UInt32, dark: UInt32) {
        if self == .questions {
            return (WardPalette.hex(.primary, dark: false), WardPalette.hex(.primary, dark: true))
        }
        return WardSection.derived[self]!.fill
    }

    func accent(dark: Bool) -> UInt32 { dark ? accent.dark : accent.light }
    func fill(dark: Bool) -> UInt32 { dark ? fill.dark : fill.light }

    /// The colours that mean something, which no section's accent may
    /// look like: right, wrong, due, and the New badge's blue.
    static let semanticTokens: [WardToken] = [.success, .danger, .warning]

    /// Every derived section's colours, worked out once.
    private static let derived: [WardSection: (ink: (light: UInt32, dark: UInt32),
                                               accent: (light: UInt32, dark: UInt32),
                                               fill: (light: UInt32, dark: UInt32))] = {
        var out: [WardSection: (ink: (light: UInt32, dark: UInt32), accent: (light: UInt32, dark: UInt32),
                                fill: (light: UInt32, dark: UInt32))] = [:]
        for section in allCases where section != .questions {
            let h: Double = section.hue
            out[section] = (
                ink: (WardAccentMaker.edge(hue: h, dark: false), WardAccentMaker.edge(hue: h, dark: true)),
                accent: (WardAccentMaker.text(hue: h, dark: false), WardAccentMaker.text(hue: h, dark: true)),
                fill: (WardAccentMaker.fill(hue: h, dark: false), WardAccentMaker.fill(hue: h, dark: true))
            )
        }
        return out
    }()

    func ink(dark: Bool) -> UInt32 { dark ? ink.dark : ink.light }

    /// Where a kind of set lives, by StudySetKind's raw value (Foundation
    /// only, so the model's enum is not needed here).
    init(kindRaw: String) {
        switch kindRaw {
        case "anki": self = .cards
        case "book": self = .textbook
        case "cases": self = .cases
        case "osce": self = .osce
        case "narrate": self = .audio
        default: self = .questions
        }
    }
}

/// Works a section's colours out from its hue: for each mode, the most
/// vivid colour of that hue that still keeps its promise, found by
/// stepping the lightness (HSL) towards the page until the promise would
/// break. A margin over each ratio keeps rounding from tipping it.
enum WardAccentMaker {
    static let margin = 0.1

    /// 0xRRGGBB from hue (degrees), saturation and lightness (0...1).
    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> UInt32 {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        func byte(_ v: Double) -> UInt32 { UInt32((min(1, max(0, v + m)) * 255).rounded()) }
        return byte(r1) << 16 | byte(g1) << 8 | byte(b1)
    }

    /// The lightness, stepping from `start` towards `end`, of the last
    /// colour that still keeps `ok`.
    private static func search(hue: Double, saturation: Double, from start: Double, to end: Double,
                               _ ok: (UInt32) -> Bool) -> UInt32 {
        var best: UInt32 = hsl(hue, saturation, start)
        let steps = 200
        for i in 0...steps {
            let l = start + (end - start) * Double(i) / Double(steps)
            let c = hsl(hue, saturation, l)
            if ok(c) { best = c } else { break }
        }
        return best
    }

    /// Words and glyphs: 4.5:1 on every tier of the mode.
    static func text(hue: Double, dark: Bool) -> UInt32 {
        let tiers = WardPalette.tiers.map { WardPalette.hex($0, dark: dark) }
        let ok: (UInt32) -> Bool = { c in tiers.allSatisfy { WardPalette.contrast(c, $0) >= 4.5 + margin } }
        // light: from dark ink up towards the page; dark: from the page's
        // own brightness down, pastel and bright
        return dark ? search(hue: hue, saturation: 0.85, from: 0.95, to: 0.4, ok)
                    : search(hue: hue, saturation: 0.62, from: 0.1, to: 0.6, ok)
    }

    /// A fill under white words: 4.5:1 for the words.
    static func fill(hue: Double, dark: Bool) -> UInt32 {
        let white = WardPalette.hex(.onPrimary, dark: dark)
        let ok: (UInt32) -> Bool = { c in WardPalette.contrast(white, c) >= 4.5 + margin }
        return search(hue: hue, saturation: dark ? 0.7 : 0.62, from: 0.1, to: 0.6, ok)
    }

    /// The grid's and the edges' ink: as an edge, at the mode's edge
    /// strength, 3:1 on the base and on a card.
    static func edge(hue: Double, dark: Bool) -> UInt32 {
        let alpha: Double = WardRelief.edgeAlpha(dark: dark)
        let grounds = [WardToken.background, .surface].map { WardPalette.hex($0, dark: dark) }
        let ok: (UInt32) -> Bool = { c in
            grounds.allSatisfy { ground in
                let edge = WardRelief.composite(WardReliefLight(hex: c, alpha: alpha, x: 0, y: 0, radius: 0), on: ground)
                return WardPalette.contrast(edge, ground) >= WardRelief.edgeContrast + margin
            }
        }
        return dark ? search(hue: hue, saturation: 0.8, from: 0.95, to: 0.4, ok)
                    : search(hue: hue, saturation: 0.62, from: 0.1, to: 0.6, ok)
    }
}

/// The wash behind the word being spoken in Audio: the section's fill at
/// this strength, under Chart Ink words.
enum WardWash {
    static let alpha = 0.22
}

/// What the app looks like at rest: light or dark, and which section.
struct WardLook: Equatable, Sendable {
    var dark: Bool
    var section: WardSection
}

/// The one animated value every Ward colour is drawn from: a move from one
/// look to another, `progress` 0 to 1 over `duration`. Every colour of a
/// frame is taken from the same progress, so no frame mixes two looks: the
/// whole app is at one point of the same shift. Colours mix in linear
/// light (WardPalette.mix), so the middle is not muddy; nothing fades.
struct WardGlide: Equatable, Sendable {
    var from: WardLook
    var to: WardLook
    var progress: Double

    static let duration = WardSchemeGlide.duration

    static func rest(_ look: WardLook) -> WardGlide { WardGlide(from: look, to: look, progress: 1) }

    var settled: Bool { progress >= 1 || from == to }

    /// Ease in and out, so the shift starts and ends gently.
    var eased: Double {
        let p = min(1, max(0, progress))
        return p * p * (3 - 2 * p)
    }

    /// A new destination. Back to where this shift started: the same path
    /// in reverse from where it is, so nothing jumps. Anywhere else: the
    /// shift so far is finished at once and a new one starts from there.
    func retargeted(_ look: WardLook) -> WardGlide {
        if look == to { return self }
        if settled { return WardGlide(from: to, to: look, progress: 0) }
        if look == from { return WardGlide(from: to, to: from, progress: 1 - min(1, max(0, progress))) }
        return WardGlide(from: to, to: look, progress: 0)
    }

    /// Where the look goes next, from `now`. Light and dark change in one
    /// step, every colour at once: text and its base swap brightness, so any
    /// mix of the two palettes passes through grey on grey (about 1.2:1 at
    /// half way), which reads as a fade. A move between sections, which
    /// touches only the grid's and the edges' hue, shifts over `duration`.
    static func toward(_ look: WardLook, from now: WardGlide) -> WardGlide {
        if look.dark != now.to.dark { return .rest(look) }
        return now.retargeted(look)
    }

    /// How dark the palette is, 0 to 1, for something drawn in `dark`
    /// (the trait it resolves in). The page follows the app's look and
    /// moves with the shift. A part `held` in one mode (the vitals monitor,
    /// always dark), or drawn in the other mode, stays where it is.
    func night(dark: Bool, held: Bool = false) -> Double {
        if held || from.dark == to.dark || dark != to.dark { return dark ? 1 : 0 }
        let a: Double = from.dark ? 1 : 0, b: Double = to.dark ? 1 : 0
        return a + (b - a) * eased
    }

    /// A palette colour this frame, for something drawn in `dark`. The
    /// accents (`primary`, `primaryInk`) are the section's (WardSection
    /// fill and accent), moving with its hue as the grid's ink does.
    func hex(_ token: WardToken, dark: Bool, held: Bool = false) -> UInt32 {
        switch token {
        case .primary: return sectioned(dark: dark, held: held) { $0.fill }
        case .primaryInk: return sectioned(dark: dark, held: held) { $0.accent }
        default: return paletteHex(token, dark: dark, held: held)
        }
    }

    /// The palette's own colour this frame, whatever the section: the New
    /// badge's blue, which means something and so stays put.
    func paletteHex(_ token: WardToken, dark: Bool, held: Bool = false) -> UInt32 {
        let n = night(dark: dark, held: held)
        if n <= 0 { return WardPalette.hex(token, dark: false) }
        if n >= 1 { return WardPalette.hex(token, dark: true) }
        return WardPalette.mix(WardPalette.hex(token, dark: false), WardPalette.hex(token, dark: true), n)
    }

    /// The section's ink this frame (grid and edges), for something drawn
    /// in `dark`: the hue and the mode move together, at the same point.
    func ink(dark: Bool, held: Bool = false) -> UInt32 {
        sectioned(dark: dark, held: held) { $0.ink }
    }

    /// One of a section's colours this frame: the mode's value of it, and
    /// part way to the next section's while the hue shifts.
    func sectioned(dark: Bool, held: Bool = false,
                   _ pair: (WardSection) -> (light: UInt32, dark: UInt32)) -> UInt32 {
        let n = night(dark: dark, held: held)
        func at(_ section: WardSection) -> UInt32 {
            let p = pair(section)
            if n <= 0 { return p.light }
            if n >= 1 { return p.dark }
            return WardPalette.mix(p.light, p.dark, n)
        }
        if from.section == to.section || settled { return at(to.section) }
        return WardPalette.mix(at(from.section), at(to.section), eased)
    }
}

extension WardRelief {
    /// A control's edge in `section`'s ink as it lands on `base`.
    static func edgeColor(_ section: WardSection, dark: Bool, highContrast: Bool = false,
                          on base: UInt32? = nil) -> UInt32 {
        composite(WardReliefLight(hex: section.ink(dark: dark),
                                  alpha: edgeAlpha(dark: dark, highContrast: highContrast),
                                  x: 0, y: 0, radius: 0), on: base ?? self.base(dark: dark))
    }
}

extension WardReliefLight {
    /// Part way from one light to another: colour in linear light, the rest
    /// straight.
    static func mix(_ a: WardReliefLight, _ b: WardReliefLight, _ t: Double) -> WardReliefLight {
        let t = min(1, max(0, t))
        return WardReliefLight(hex: WardPalette.mix(a.hex, b.hex, t), alpha: a.alpha + (b.alpha - a.alpha) * t,
                               x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t,
                               radius: a.radius + (b.radius - a.radius) * t)
    }
}

extension WardReliefSpec {
    /// Part way from one relief to another (light to dark), so the lights
    /// move with the palette.
    static func mix(_ a: WardReliefSpec, _ b: WardReliefSpec, _ t: Double) -> WardReliefSpec {
        if t <= 0 { return a }
        if t >= 1 { return b }
        return WardReliefSpec(highlight: .mix(a.highlight, b.highlight, t), shade: .mix(a.shade, b.shade, t),
                              inner: b.inner, edgeAlpha: a.edgeAlpha + (b.edgeAlpha - a.edgeAlpha) * t)
    }
}

extension WardPressSpec {
    static func mix(_ a: WardPressSpec, _ b: WardPressSpec, _ t: Double) -> WardPressSpec {
        if t <= 0 { return a }
        if t >= 1 { return b }
        return WardPressSpec(blur: a.blur + (b.blur - a.blur) * t,
                             outerHighlight: .mix(a.outerHighlight, b.outerHighlight, t),
                             outerShade: .mix(a.outerShade, b.outerShade, t),
                             innerShade: .mix(a.innerShade, b.innerShade, t),
                             innerHighlight: .mix(a.innerHighlight, b.innerHighlight, t),
                             edgeAlpha: a.edgeAlpha + (b.edgeAlpha - a.edgeAlpha) * t)
    }
}

extension WardRelief {
    /// Raised, rimmed or pressed in, `night` of the way from light to dark.
    static func raised(_ lift: WardLift, night: Double, highContrast: Bool = false, control: Bool = false) -> WardReliefSpec {
        .mix(raised(lift, dark: false, highContrast: highContrast, control: control),
             raised(lift, dark: true, highContrast: highContrast, control: control), night)
    }

    static func inset(_ lift: WardLift, night: Double, highContrast: Bool = false, control: Bool = false) -> WardReliefSpec {
        .mix(inset(lift, dark: false, highContrast: highContrast, control: control),
             inset(lift, dark: true, highContrast: highContrast, control: control), night)
    }

    static func rim(_ lift: WardLift, night: Double, highContrast: Bool = false) -> WardReliefSpec {
        .mix(rim(lift, dark: false, highContrast: highContrast), rim(lift, dark: true, highContrast: highContrast), night)
    }
}

extension WardPress {
    static func spec(_ lift: WardLift, depth q: Double, night: Double,
                     highContrast: Bool = false, control: Bool = true) -> WardPressSpec {
        .mix(spec(lift, depth: q, dark: false, highContrast: highContrast, control: control),
             spec(lift, depth: q, dark: true, highContrast: highContrast, control: control), night)
    }
}

extension WardPaper {
    /// The paper's ink this frame of `look`'s shift, for paper drawn in
    /// `dark`: the section's hue, at the strengths of the mode it is at.
    static func ink(look: WardGlide, dark: Bool, held: Bool = false, highContrast: Bool) -> WardPaperInk {
        ink(night: look.night(dark: dark, held: held), highContrast: highContrast, hex: look.ink(dark: dark, held: held))
    }

    /// The paper's ink `night` of the way to dark, in `hex` (a section's ink
    /// this frame, WardGlide.ink).
    static func ink(night: Double, highContrast: Bool, hex: UInt32) -> WardPaperInk {
        let a = ink(dark: false, highContrast: highContrast), b = ink(dark: true, highContrast: highContrast)
        let t = min(1, max(0, night))
        return WardPaperInk(hex: hex, fine: a.fine + (b.fine - a.fine) * t,
                            bold: a.bold + (b.bold - a.bold) * t, edge: a.edge + (b.edge - a.edge) * t)
    }
}
