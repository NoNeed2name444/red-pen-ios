import Foundation

/// The Ward Round palette (docs/design/targets-2026-10-01.md §1): one table of
/// light and dark values that every colour in the app is drawn from, and the
/// contrast each text colour is promised against the surface it sits on.
///
/// Soft UI: the ground and every card are one matte base per mode, so a
/// card is told from the ground by its relief (WardRelief), never by a
/// different colour or an edge.
///
/// Foundation only, so the promises are tested on Linux (WardPaletteTests);
/// WardTokens turns the table into SwiftUI colours.
enum WardToken: String, CaseIterable {
    /// The matte base every screen sits on
    case background
    /// Cards, rows, sheets: the same base, raised or pressed in by relief
    case surface
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
        .surface:      (0xE0E5EC, 0x2A2E35),
        .primary:      (0x1D5FB0, 0x2A6BC4),
        .primaryInk:   (0x1D5FB0, 0x7DB0F2),
        .onPrimary:    (0xFFFFFF, 0xFFFFFF),
        .ecg:          (0xBA273B, 0xF2788A),
        .beam:         (0xC2620B, 0xF0A04B),
        .success:      (0x137045, 0x4CC38A),
        .warning:      (0x8F5400, 0xE7AE45),
        .danger:       (0xC0262D, 0xF57A7F),
        .ink:          (0x0E1B2C, 0xE8EEF5),
        .inkSecondary: (0x4E5E73, 0xA3B1C3),
        .hairline:     (0xC8D0DA, 0x1F2228),
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
