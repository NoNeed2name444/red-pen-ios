import Foundation

/// The parts of the app, each with a colour of its own (the owner, 14 Oct:
/// "colour difference for each mode"). The hue tints only the ECG paper's
/// grid and the edges round the controls; the base, the cards and the
/// words stay the Ward palette's, so text keeps its contrast everywhere.
/// The hues start from the glyph colours the modes already wear on home and
/// in New set: blue questions, red cards, green textbooks, amber OSCE.
enum WardSection: String, CaseIterable, Sendable {
    case questions, cards, textbook, cases, osce, audio, ideas

    /// The section's ink (light, dark) as 0xRRGGBB: the grid's lines and
    /// the controls' edges. Each reads at least 3:1 on the base and on a
    /// card at a control's edge strength (WardRelief.edgeAlpha), and the
    /// hues sit at least 25 degrees apart. Questions keep the paper's blue.
    var ink: (light: UInt32, dark: UInt32) {
        switch self {
        case .questions: return (0x2868C4, 0x78AAF5)   // Theatre Blue paper
        case .cards: return (0xC23048, 0xFF8FA1)       // ECG red
        case .textbook: return (0x18804E, 0x63D99C)    // Discharge green
        case .cases: return (0x0D7C8C, 0x52D2E2)       // teal
        case .osce: return (0x8F6200, 0xEDBF4A)        // Caution amber
        case .audio: return (0x7448C4, 0xB79CFF)       // violet
        case .ideas: return (0xA8327E, 0xF58FD0)       // magenta, apart from OSCE's amber
        }
    }

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

    /// A palette colour this frame, for something drawn in `dark`.
    func hex(_ token: WardToken, dark: Bool, held: Bool = false) -> UInt32 {
        let n = night(dark: dark, held: held)
        if n <= 0 { return WardPalette.hex(token, dark: false) }
        if n >= 1 { return WardPalette.hex(token, dark: true) }
        return WardPalette.mix(WardPalette.hex(token, dark: false), WardPalette.hex(token, dark: true), n)
    }

    /// The section's ink this frame (grid and edges), for something drawn
    /// in `dark`: the hue and the mode move together, at the same point.
    func ink(dark: Bool, held: Bool = false) -> UInt32 {
        let n = night(dark: dark, held: held)
        func at(_ section: WardSection) -> UInt32 {
            if n <= 0 { return section.ink.light }
            if n >= 1 { return section.ink.dark }
            return WardPalette.mix(section.ink.light, section.ink.dark, n)
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
