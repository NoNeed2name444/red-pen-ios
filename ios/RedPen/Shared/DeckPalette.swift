import Foundation

/// The colours one exported deck is printed in.
///
/// Derived from a single base colour per mode - the same tint the mode's
/// screens use - rather than hand-picked per element, so a deck printed from
/// Cases looks like Cases and a deck printed from OSCE looks like OSCE, and
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

    /// The mode tints, kept in step with Theme's.
    static func of(_ kind: StudySetKind) -> DeckPalette {
        switch kind {
        case .mcq:     return DeckPalette(red: 0.78, green: 0.16, blue: 0.16)
        case .anki:    return DeckPalette(red: 0.31, green: 0.36, blue: 0.86)
        case .book:    return DeckPalette(red: 0.10, green: 0.55, blue: 0.50)
        case .qa:      return DeckPalette(red: 0.90, green: 0.49, blue: 0.13)
        case .osce:    return DeckPalette(red: 0.20, green: 0.62, blue: 0.35)
        case .narrate: return DeckPalette(red: 0.55, green: 0.32, blue: 0.80)
        }
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

    /// Whether white text can be read on this colour.
    ///
    /// The header bar is filled with the base colour and its text is white. Two
    /// of the mode tints are bright - amber above all - and white on them is
    /// close to unreadable in print, so those bars take the darkened shade
    /// instead. Measured by relative luminance rather than by eye, because "it
    /// looked fine on my screen" is how a printed page ends up illegible.
    var carriesWhiteText: Bool { luminance < 0.5 }

    /// Relative luminance, weighted the way the eye responds.
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// The colour a header bar is actually filled with.
    var barFill: DeckPalette { carriesWhiteText ? self : shade(0.38) }

    var hex: String {
        String(format: "#%02X%02X%02X",
               Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

private extension Double {
    func clamped() -> Double { Swift.min(1, Swift.max(0, self)) }
}
