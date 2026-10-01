import Foundation

/// The Ward Round palette (docs/design/targets-2026-10-01.md §1): one table of
/// light and dark values that every colour in the app is drawn from, and the
/// contrast each text colour is promised against the surface it sits on.
///
/// Foundation only, so the promises are tested on Linux (WardPaletteTests);
/// WardTokens turns the table into SwiftUI colours.
enum WardToken: String, CaseIterable {
    /// Ward White: the ground every screen sits on
    case background
    /// Clean Sheet: cards, rows, sheets
    case surface
    /// Theatre Blue as a fill: primary buttons, selected chips
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
    /// Card edges and separators
    case hairline
    /// The vitals monitor card, dark in both modes
    case monitor
}

enum WardPalette {
    /// (light, dark) as 0xRRGGBB.
    static let table: [WardToken: (light: UInt32, dark: UInt32)] = [
        .background:   (0xF3F6F9, 0x0B131D),
        .surface:      (0xFFFFFF, 0x152230),
        .primary:      (0x1D5FB0, 0x2A6BC4),
        .primaryInk:   (0x1D5FB0, 0x7DB0F2),
        .onPrimary:    (0xFFFFFF, 0xFFFFFF),
        .ecg:          (0xD32F45, 0xF2788A),
        .beam:         (0xC2620B, 0xF0A04B),
        .success:      (0x16804F, 0x4CC38A),
        .warning:      (0x9A5B00, 0xE7AE45),
        .danger:       (0xC0262D, 0xF57A7F),
        .ink:          (0x0E1B2C, 0xE8EEF5),
        .inkSecondary: (0x4E5E73, 0xA3B1C3),
        .hairline:     (0xE1E7EE, 0x2A3A4D),
        .monitor:      (0x0E1B2C, 0x0E1B2C),
    ]

    static func hex(_ token: WardToken, dark: Bool) -> UInt32 {
        let pair = table[token]!
        return dark ? pair.dark : pair.light
    }

    /// 0...1 components.
    static func rgb(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
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
        (.inkSecondary, .surface, 4.5), (.inkSecondary, .background, 4.5),
        (.primaryInk, .surface, 4.5), (.primaryInk, .background, 4.5),
        (.onPrimary, .primary, 4.5),
        (.ecg, .surface, 4.5), (.success, .surface, 4.5),
        (.warning, .surface, 4.5), (.danger, .surface, 4.5),
        (.beam, .surface, 3),
    ]
}
