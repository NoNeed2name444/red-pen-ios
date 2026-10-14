import Foundation

/// The Ward Round palette (docs/design/targets-2026-10-01.md §1): one table of
/// light and dark values that every colour in the app is drawn from, and the
/// contrast each text colour is promised against the surface it sits on.
///
/// Soft UI on four close tiers per mode: a well pressed in, the matte base,
/// a card a shade off it, and a sheet or a bar a shade further, so a card
/// is told from the ground by its relief (WardRelief) and a whisper of
/// colour, never by an edge.
///
/// The two modes are two characters, not one palette inverted (the owner,
/// 14 Oct: "lacks color difference for each mode"). Day is the ward at
/// noon: Theatre Blue on clean grey paper, navy Chart Ink, cards a touch
/// lighter than the ground. Night is the ward's monitors after lights out:
/// a monitor cyan accent, warmer reds and greens that glow without
/// glaring, near-white ink with a brighter secondary grey, and cards that
/// lift by lightening, as a dark room shows depth. The bases stay
/// #E0E5EC and #2A2E35: the launch screen and the launch logo are drawn
/// on them.
///
/// Foundation only, so the promises are tested on Linux (WardPaletteTests);
/// WardTokens turns the table into SwiftUI colours.
enum WardToken: String, CaseIterable {
    /// The matte base every screen sits on
    case background
    /// Cards and rows: a shade off the base, raised by relief
    case surface
    /// Sheets, floating bars, popovers: a shade further than a card
    case raised
    /// Wells pressed into the base: fields, tracks, a chosen segment
    case well
    /// Theatre Blue as a fill: a switch that is on, the app's tint
    case primary
    /// Theatre Blue as text and glyphs on a surface
    case primaryInk
    /// White on a primary fill
    case onPrimary
    /// ECG Red: the secondary accent
    case ecg
    /// Pager Amber: the progress beam, the countdown pill
    case beam
    /// Discharge Green
    case success
    /// Caution Amber
    case warning
    /// Resus Red
    case danger
    /// Chart Ink: text
    case ink
    /// Biro Grey: secondary text and small caps
    case inkSecondary
    /// A groove: separators and the empty part of a track
    case hairline
    /// The vitals monitor's well, dark in both modes
    case monitor
}

enum WardPalette {
    /// (light, dark) as 0xRRGGBB.
    static let table: [WardToken: (light: UInt32, dark: UInt32)] = [
        .background:   (0xE0E5EC, 0x2A2E35),
        .surface:      (0xE4E8EE, 0x2F333B),
        .raised:       (0xE9EDF2, 0x353A43),
        .well:         (0xD8DEE6, 0x24282E),
        .primary:      (0x1D5FB0, 0x136F8E),
        .primaryInk:   (0x1D5FB0, 0x5CC8EC),
        .onPrimary:    (0xFFFFFF, 0xFFFFFF),
        .ecg:          (0xBA273B, 0xFF8A9B),
        .beam:         (0xC2620B, 0xF5A54A),
        .success:      (0x137045, 0x5DD39E),
        .warning:      (0x8F5400, 0xF2B64E),
        .danger:       (0xB8222A, 0xFF8A8F),
        .ink:          (0x0E1B2C, 0xEEF2F7),
        .inkSecondary: (0x4E5E73, 0xB0BCCB),
        .hairline:     (0xC8D0DA, 0x1F2228),
        .monitor:      (0x0E1B2C, 0x0E1B2C),
    ]

    /// The tiers from deepest to highest: a well, the base, a card, a sheet.
    static let tiers: [WardToken] = [.well, .background, .surface, .raised]

    static func hex(_ token: WardToken, dark: Bool) -> UInt32 {
        let pair = table[token]!
        return dark ? pair.dark : pair.light
    }

    /// 0...1 components.
    static func rgb(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    /// A colour part way from `a` to `b` (t 0 to 1), mixed in linear light
    /// so the middle of a light-to-dark shift is not muddy: what one frame
    /// of the appearance glide shows (WardSchemeGlide).
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        let t = min(1, max(0, t))
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func gamma(_ c: Double) -> Double { c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }
        let (r0, g0, b0) = rgb(a), (r1, g1, b1) = rgb(b)
        func channel(_ x: Double, _ y: Double) -> UInt32 {
            let v = gamma(linear(x) + (linear(y) - linear(x)) * t)
            return UInt32((min(1, max(0, v)) * 255).rounded())
        }
        return channel(r0, r1) << 16 | channel(g0, g1) << 8 | channel(b0, b1)
    }

    /// WCAG 2 relative luminance.
    static func luminance(_ hex: UInt32) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = rgb(hex)
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG 2 contrast ratio, 1...21.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Each text colour, what it sits on, and the ratio it is promised:
    /// 4.5 for text, 3 for the beam (large text and graphics only).
    static let promises: [(text: WardToken, on: WardToken, ratio: Double)] = [
        (.ink, .surface, 4.5), (.ink, .background, 4.5),
        (.ink, .raised, 4.5), (.ink, .well, 4.5),
        (.inkSecondary, .raised, 4.5), (.inkSecondary, .well, 4.5),
        (.primaryInk, .raised, 4.5), (.primaryInk, .well, 4.5),
        (.inkSecondary, .surface, 4.5), (.inkSecondary, .background, 4.5),
        (.primaryInk, .surface, 4.5), (.primaryInk, .background, 4.5),
        (.onPrimary, .primary, 4.5),
        (.ecg, .surface, 4.5), (.success, .surface, 4.5),
        (.warning, .surface, 4.5), (.danger, .surface, 4.5),
        (.beam, .surface, 3),
        // soft UI tints labels and glyphs, not fills, so the accents sit on
        // the ground too
        (.ecg, .background, 4.5), (.success, .background, 4.5),
        (.warning, .background, 4.5), (.danger, .background, 4.5),
        (.beam, .background, 3),
    ]

    /// The monitor's well wears the dark values in both modes (MonitorCard
    /// sets the dark scheme), so each is promised on it too.
    static let monitorPromises: [(text: WardToken, ratio: Double)] = [
        (.ink, 4.5), (.inkSecondary, 4.5), (.primaryInk, 4.5), (.ecg, 4.5),
        (.success, 4.5), (.warning, 4.5), (.danger, 4.5), (.beam, 3),
    ]
}

/// The one spacing scale: every gap, padding and radius in the soft UI is
/// a step of it (the owner, 14 Oct: "the iOS design is a bit cramped").
/// WardSpace and WardRadius (WardTokens) are drawn from it.
enum WardScale {
    static let steps: [Double] = [4, 8, 12, 16, 24, 32]
    static let xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0
    /// Extra room between the lines of a paragraph, on top of the text
    /// style's own leading.
    static let leading = 4.0

    static func onScale(_ value: Double) -> Bool { steps.contains(value) }
}

/// Light to dark and back: the colours move to the other palette over
/// about a third of a second, a colour shift and never a fade (WardSchemeGlide
/// in WardTokens draws it; under Reduce Motion they switch at once).
enum WardSchemeGlide {
    static let duration = 0.35

    /// One frame of the shift, `t` of the way from light to dark.
    static func frame(_ token: WardToken, t: Double) -> UInt32 {
        WardPalette.mix(WardPalette.hex(token, dark: false), WardPalette.hex(token, dark: true), t)
    }
}
