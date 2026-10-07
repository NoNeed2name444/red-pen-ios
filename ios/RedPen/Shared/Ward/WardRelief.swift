import Foundation

/// How far a soft UI surface stands off the base: a row or a chip sits low,
/// a card mid, a sheet or a floating bar high, the one hero of a screen at
/// its peak.
enum WardLift: Int, CaseIterable, Comparable, Sendable {
    case low = 1, mid, high, peak

    static func < (a: WardLift, b: WardLift) -> Bool { a.rawValue < b.rawValue }
}

/// One of the two lights a relief is drawn with: a colour, how strong it
/// is, where it falls (points) and how soft its edge is (blur radius,
/// points).
struct WardReliefLight: Equatable, Sendable {
    var hex: UInt32
    var alpha: Double
    var x: Double
    var y: Double
    var radius: Double
}

/// A relief: a highlight from the top left and a shade to the bottom right.
/// Raised, they are drop shadows outside the shape; pressed in (`inner`),
/// the same two fall inside it, so the shade lines the top-left wall and
/// the highlight the bottom-right one.
struct WardReliefSpec: Equatable, Sendable {
    var highlight: WardReliefLight
    var shade: WardReliefLight
    var inner: Bool
    /// An ink edge for Increase Contrast; 0 draws none.
    var edgeAlpha: Double

    /// Raised to pressed in and back: the lights stay where they are.
    func mirrored() -> WardReliefSpec {
        var m = self
        m.inner.toggle()
        return m
    }
}

/// The soft UI light, per mode and lift. Foundation only, so the numbers
/// are tested on Linux (WardReliefTests); WardSurfaces draws them.
///
/// Light mode: white at 0.75 to 0.9 and a cool grey shade (#A3B1C6) at 0.5
/// to 0.65. Dark mode: white at 0.05 to 0.08, so nothing glares, and black
/// at 0.45 to 0.6. Increase Contrast deepens the shade and adds the edge.
enum WardRelief {
    static let lightShade: UInt32 = 0xA3B1C6
    static let highContrastShadeGain = 0.15
    static let highContrastEdge = 0.35

    /// The shade's offset from the shape, down and right; the highlight
    /// falls the same distance up and left.
    static func offset(_ lift: WardLift) -> Double {
        switch lift {
        case .low: return 2.5
        case .mid: return 5
        case .high: return 8
        case .peak: return 11
        }
    }

    static func radius(_ lift: WardLift) -> Double {
        switch lift {
        case .low: return 4
        case .mid: return 8
        case .high: return 12
        case .peak: return 16
        }
    }

    /// Per lift, low to peak.
    static let lightHighlight = [0.75, 0.8, 0.85, 0.9]
    static let lightShadeAlpha = [0.5, 0.55, 0.6, 0.65]
    static let darkHighlight = [0.05, 0.06, 0.07, 0.08]
    static let darkShadeAlpha = [0.45, 0.5, 0.55, 0.6]

    static func highlightAlpha(_ lift: WardLift, dark: Bool) -> Double {
        (dark ? darkHighlight : lightHighlight)[lift.rawValue - 1]
    }

    static func shadeAlpha(_ lift: WardLift, dark: Bool, highContrast: Bool = false) -> Double {
        let alpha = (dark ? darkShadeAlpha : lightShadeAlpha)[lift.rawValue - 1]
        return highContrast ? alpha + highContrastShadeGain : alpha
    }

    /// The ground both lights fall on.
    static func base(dark: Bool) -> UInt32 { WardPalette.hex(.background, dark: dark) }

    static func raised(_ lift: WardLift, dark: Bool, highContrast: Bool = false) -> WardReliefSpec {
        let d = offset(lift), r = radius(lift)
        return WardReliefSpec(
            highlight: WardReliefLight(hex: 0xFFFFFF, alpha: highlightAlpha(lift, dark: dark), x: -d, y: -d, radius: r),
            shade: WardReliefLight(hex: dark ? 0x000000 : lightShade,
                                   alpha: shadeAlpha(lift, dark: dark, highContrast: highContrast),
                                   x: d, y: d, radius: r),
            inner: false,
            edgeAlpha: highContrast ? highContrastEdge : 0)
    }

    static func inset(_ lift: WardLift, dark: Bool, highContrast: Bool = false) -> WardReliefSpec {
        raised(lift, dark: dark, highContrast: highContrast).mirrored()
    }

    /// What a light looks like where it lies at full strength on `base`.
    static func composite(_ light: WardReliefLight, on base: UInt32) -> UInt32 {
        let (r0, g0, b0) = WardPalette.rgb(base), (r1, g1, b1) = WardPalette.rgb(light.hex)
        func mix(_ a: Double, _ b: Double) -> UInt32 { UInt32(((a + (b - a) * light.alpha) * 255).rounded()) }
        return mix(r0, r1) << 16 | mix(g0, g1) << 8 | mix(b0, b1)
    }
}
