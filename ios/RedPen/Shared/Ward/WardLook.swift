import Foundation

/// The parts of the app, each with a colour of its own (the owner, 14 Oct:
/// "colour difference for each mode"; 15 Oct: the buttons, links and
/// other accents were still blue in every section; 16 Oct: palette
/// direction 3, seven section colours; 22 Oct: the ten-colour palette's
/// hexes exactly, no shades). Each section has a hue and one colour, the
/// owner's hex, in every role and both modes: the paper's grid and the
/// controls' edges (`ink`), the words and glyphs of buttons, links, the
/// chosen dock tab, progress and a right answer (`accent`), and the fills
/// under white words (`fill`). The base, the cards and the body text stay
/// the Ward palette's, and so do the colours that mean something: Discharge
/// green, Resus red, Caution amber for due, the ECG red and the beam's
/// orange. WardLookTests asks the sections to keep apart from those and
/// from each other (at least 0.075 in OKLab, both modes) and says where
/// the owner's colours fall short.
enum WardSection: String, CaseIterable, Sendable {
    case questions, cards, textbook, cases, osce, audio, ideas

    /// The look outside any section (a screen that sets none, and home
    /// before a section is asked for): Cards' Care Blue, which is also the
    /// palette's primary. Not Questions, or every screen without a section
    /// would turn red; and the default paper ink and the control edges
    /// follow it, so the app keeps no blue of its own.
    static let outside: WardSection = .cards

    /// The hue, in OKLCH degrees (perceptual, so equal steps look equal).
    var hue: Double { WardSection.table[self]!.hue }

    /// The section's ink (light, dark) as 0xRRGGBB: the grid's lines and
    /// the controls' edges, the owner's hex as the fill is. WardLookTests
    /// asks 3:1 on the base and on a card at a control's edge strength
    /// (WardRelief.edgeAlpha). Questions' is red, and its grid red at the
    /// paper's own strengths, like real ECG paper.
    var ink: (light: UInt32, dark: UInt32) { WardSection.table[self]!.ink }

    /// Words and glyphs in the section's colour (buttons' labels, links,
    /// icons, the chosen tab, progress, a right answer), light and dark:
    /// the owner's hex as the fill is. WardLookTests asks 4.5:1 on every
    /// tier of its mode, the well to a sheet.
    var accent: (light: UInt32, dark: UInt32) { WardSection.table[self]!.accent }

    /// A fill in the section's colour, the owner's hex, under white words
    /// (onPrimary) (a switch that is on, a chosen segment).
    var fill: (light: UInt32, dark: UInt32) { WardSection.table[self]!.fill }

    func accent(dark: Bool) -> UInt32 { dark ? accent.dark : accent.light }
    func fill(dark: Bool) -> UInt32 { dark ? fill.dark : fill.light }
    func ink(dark: Bool) -> UInt32 { dark ? ink.dark : ink.light }

    /// The ground behind every page, (light, dark) as 0xRRGGBB: the plain
    /// base (WardPalette's .background) in every section. The owner never
    /// asked for a wash of the section's colour (added 21 Oct, the base
    /// mixed toward the fill), and the owner's phone build of 16 Oct has
    /// plain grey grounds, so since 22 Oct the ground is the base again, as
    /// it was before the wash. Kept as the one route every caller takes
    /// (home's ground, the dock's slab, the bars, the launch pictures).
    var wash: (light: UInt32, dark: UInt32) { (wash(dark: false), wash(dark: true)) }

    func wash(dark: Bool) -> UInt32 { WardPalette.hex(.background, dark: dark) }

    /// The colours that mean something, which no section's accent may
    /// look like.
    static let semanticTokens: [WardToken] = [.success, .danger, .warning, .ecg, .beam]

    /// Every section's colours: the owner's hex in every role and both
    /// modes. Written here by hand: tools/ward_accents.py, which works
    /// shades out from the hue, exits 1 on these fills (white reads under
    /// 4.6:1 on each), so it cannot --write them; its --check holds this
    /// table to it but for the owner's accepted cases
    /// (tests/ward/owner-accepted.json).
    /// (ink, accent, fill) as (light, dark) 0xRRGGBB.
    // ward_accents.py: begin
    private static let table: [WardSection: WardSectionColours] = [
        .questions: WardSectionColours(hue: 23, ink: (0xFF6B6B, 0xFF6B6B), accent: (0xFF6B6B, 0xFF6B6B), fill: (0xFF6B6B, 0xFF6B6B)),
        .cards: WardSectionColours(hue: 260, ink: (0x3B82F6, 0x3B82F6), accent: (0x3B82F6, 0x3B82F6), fill: (0x3B82F6, 0x3B82F6)),
        .textbook: WardSectionColours(hue: 182, ink: (0x14B8A6, 0x14B8A6), accent: (0x14B8A6, 0x14B8A6), fill: (0x14B8A6, 0x14B8A6)),
        .cases: WardSectionColours(hue: 42, ink: (0xFF9F7A, 0xFF9F7A), accent: (0xFF9F7A, 0xFF9F7A), fill: (0xFF9F7A, 0xFF9F7A)),
        .osce: WardSectionColours(hue: 129, ink: (0xA3E635, 0xA3E635), accent: (0xA3E635, 0xA3E635), fill: (0xA3E635, 0xA3E635)),
        .audio: WardSectionColours(hue: 294, ink: (0xA78BFA, 0xA78BFA), accent: (0xA78BFA, 0xA78BFA), fill: (0xA78BFA, 0xA78BFA)),
        .ideas: WardSectionColours(hue: 350, ink: (0xF472B6, 0xF472B6), accent: (0xF472B6, 0xF472B6), fill: (0xF472B6, 0xF472B6)),
    ]
    // ward_accents.py: end

    /// Where a kind of set lives, by StudySetKind's raw value (Foundation
    /// only, so the model's enum is not needed here). A kind not listed is
    /// a question set, so it is Questions, not the outside look.
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

/// One section's colours, light and dark (WardSection.table).
struct WardSectionColours: Sendable {
    let hue: Double
    let ink: (light: UInt32, dark: UInt32)
    let accent: (light: UInt32, dark: UInt32)
    let fill: (light: UInt32, dark: UInt32)
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

    /// The palette's own colour this frame, whatever the section (for the
    /// accent tokens, Cards': the look outside any section).
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

    /// The section's wash this frame, for something drawn in `dark`:
    /// shifts with the section's glide, like the grid's ink.
    func wash(dark: Bool, held: Bool = false) -> UInt32 {
        sectioned(dark: dark, held: held) { $0.wash }
    }

    /// A given section's ink this frame (grid and edges), for something
    /// drawn in `dark`: the night mixed as ink(dark:held:) does, but with
    /// no hue shift with the section on show.
    func ink(_ section: WardSection, dark: Bool, held: Bool = false) -> UInt32 {
        let n = night(dark: dark, held: held)
        if n <= 0 { return section.ink.light }
        if n >= 1 { return section.ink.dark }
        return WardPalette.mix(section.ink.light, section.ink.dark, n)
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

/// The look the app is at this moment, read where a colour is drawn. A
/// colour that took its section when a view's body ran kept it: the quiz's
/// rows ran their bodies while the app was still outside any section, so
/// once the screen set its own, a right answer's letter and check stayed
/// Cards' indigo by day while the edges, redrawn on their own, turned the
/// section's colour (the owner, 16 Oct: "the color here doesn't match the
/// mode color"). Every Ward colour now asks here, as it is drawn, so one
/// made before the section was set still shows the section on show.
/// WardLookStore keeps the value and tells the views it has changed.
final class WardLookNow: @unchecked Sendable {
    static let shared = WardLookNow()

    private let lock = NSLock()
    private var current: WardGlide

    init(_ glide: WardGlide = .rest(WardLook(dark: false, section: WardSection.outside))) {
        current = glide
    }

    var glide: WardGlide { lock.withLock { current } }

    func set(_ glide: WardGlide) { lock.withLock { current = glide } }

    /// A palette colour as it is drawn now, in a trait of `dark`.
    func hex(_ token: WardToken, dark: Bool, held: Bool = false) -> UInt32 {
        glide.hex(token, dark: dark, held: held)
    }

    /// The section's ink (grid and edges) as it is drawn now.
    func ink(dark: Bool, held: Bool = false) -> UInt32 {
        glide.ink(dark: dark, held: held)
    }

    /// The section's wash as it is drawn now.
    func wash(dark: Bool, held: Bool = false) -> UInt32 {
        glide.wash(dark: dark, held: held)
    }

    /// A given section's ink (grid and edges) as it is drawn now.
    func ink(_ section: WardSection, dark: Bool, held: Bool = false) -> UInt32 {
        glide.ink(section, dark: dark, held: held)
    }
}

extension WardGlide {
    /// The look a face or the paper draws this frame: the look at rest the
    /// root last handed down (`rest`, nil while a shift is under way or
    /// where the root has not set it), else this frame of the shift.
    static func drawn(rest: WardLook?, live: WardGlide) -> WardGlide { rest.map(WardGlide.rest) ?? live }
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

extension WardSection {
    /// The section home opens on: the dock's first category, Questions
    /// (LibraryView's `category` starts there and is not kept between
    /// launches). The launch screen and the opening stand on its ground.
    static let opening: WardSection = .questions
}

/// Home's ground for a look at rest: the base with the section's wash
/// (what WardBackground draws) and the ECG paper's grid over it, in the
/// section's ink at the mode's strengths, every `WardPaper.cell` points
/// and bold every `WardPaper.boldEvery`, counted from the window's top
/// left. The opening draws it live (LaunchSplash), and the launch screen's
/// picture (LaunchPaper) is drawn from the same numbers by
/// tools/make_launch_ground.py, so the ground is one from the first frame
/// to home at rest, with no change at the hand-off.
struct WardGround: Equatable, Sendable {
    /// The base with the section's wash (WardSection.wash).
    var base: UInt32
    /// The grid's ink and its strengths (WardPaper.ink).
    var ink: WardPaperInk

    static func home(_ section: WardSection = .opening, dark: Bool, highContrast: Bool = false) -> WardGround {
        let look = WardGlide.rest(WardLook(dark: dark, section: section))
        return WardGround(base: look.wash(dark: dark),
                          ink: WardPaper.ink(look: look, dark: dark, highContrast: highContrast))
    }
}
