import Foundation

/// The colours one exported deck is printed in.
///
/// Derived from a single base colour per mode - the same tint the mode's
/// screens use - rather than hand-picked per element, so a deck printed from
/// MCQ looks like MCQ and a deck printed from OSCE looks like OSCE, and
/// adding a mode later cannot produce a palette nobody chose.
///
/// Three shades come out of the base: the base itself for the header bar and
/// headings, a DARKENED shade for text that has to stay readable on paper, and
/// a LIGHT TINT for chips and rules. The darkening matters: several mode tints
/// are bright enough that body text set in them is uncomfortable in print, where
/// there is no backlight to carry it.
struct DeckPalette: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red.clamped()
        self.green = green.clamped()
        self.blue = blue.clamped()
    }

    /// The mode tints, kept in step with Theme's: each section's fill in the
    /// owner's 2026-10-21 palette (WardSection.fill).
    static func of(_ kind: StudySetKind) -> DeckPalette {
        switch kind {
        case .mcq:     return DeckPalette(hex: 0xFF6B6B)   // Vital Coral
        case .anki:    return DeckPalette(hex: 0x3B82F6)   // Care Blue
        case .book:    return DeckPalette(hex: 0x14B8A6)   // Pulse Teal
        case .osce:    return DeckPalette(hex: 0xA3E635)   // Lime Zest
        case .narrate: return DeckPalette(hex: 0xA78BFA)   // Soft Lilac
        case .cases:   return DeckPalette(hex: 0xFF9F7A)   // Peach Glow
        }
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Darkened towards black - for headings and emphasised words on paper.
    func shade(_ amount: Double = 0.22) -> DeckPalette {
        let keep = (1 - amount).clamped()
        return DeckPalette(red: red * keep, green: green * keep, blue: blue * keep)
    }

    /// Lightened towards white - for chips, rules and the giant watermark.
    func tint(_ amount: Double = 0.86) -> DeckPalette {
        let a = amount.clamped()
        let r: Double = red + (1 - red) * a
        let g: Double = green + (1 - green) * a
        let b: Double = blue + (1 - blue) * a
        return DeckPalette(red: r, green: g, blue: b)
    }

    /// Whether white text can be read on this colour: WCAG's 4.5:1.
    ///
    /// The header bar is filled with the base colour and its text is white.
    /// The 2026-10-21 mode tints are all bright, and white on them is under
    /// AA, so those bars take a darkened shade instead. Measured by WCAG
    /// contrast rather than by eye, because "it looked fine on my screen" is
    /// how a printed page ends up illegible.
    var carriesWhiteText: Bool { 1.05 / (wcagLuminance + 0.05) >= 4.5 }

    /// WCAG 2 relative luminance, in linear light.
    var wcagLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Relative luminance, weighted the way the eye responds.
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// Words in the mode's colour on the paper and its pale tints: the
    /// lightest shade from 0.10 down that reads 5:1 on white, so it keeps
    /// 4.5:1 on a tint of 0.86 or paler.
    var ink: DeckPalette {
        var amount = 0.10
        while 1.05 / (shade(amount).wcagLuminance + 0.05) < 5 && amount < 1 { amount += 0.02 }
        return shade(amount)
    }

    /// The colour a header bar is actually filled with: the tint, or the
    /// lightest shade of it from 0.38 down that carries white text.
    var barFill: DeckPalette {
        if carriesWhiteText { return self }
        var amount = 0.38
        while !shade(amount).carriesWhiteText && amount < 1 { amount += 0.02 }
        return shade(amount)
    }

    var hex: String {
        String(format: "#%02X%02X%02X",
               Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

private extension Double {
    func clamped() -> Double { Swift.min(1, Swift.max(0, self)) }
}
