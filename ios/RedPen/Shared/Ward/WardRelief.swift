import Foundation

/// How far a soft UI surface stands off the base: a row or a chip sits low,
/// a card mid, a sheet or a floating bar high, the one hero of a screen at
/// its peak.
///
/// Not Comparable on purpose: a `<` of its own would join every `<` the
/// compiler weighs app-wide; order by `rawValue` instead.
enum WardLift: Int, CaseIterable, Sendable {
    case low = 1, mid, high, peak

    /// One step nearer the base, never below low: what a raised surface
    /// sinks to, pressed in, while it is held.
    var lower: WardLift { WardLift(rawValue: rawValue - 1) ?? .low }
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

    /// Lights below the visible threshold are omitted from rendering.
    var lit: Bool { alpha > 1e-4 }
}

/// A relief: a highlight from the top left and a shade to the bottom right.
/// Raised, they are drop shadows outside the shape; pressed in (`inner`),
/// the same two fall inside it, so the shade lines the top-left wall and
/// the highlight the bottom-right one.
struct WardReliefSpec: Equatable, Sendable {
    var highlight: WardReliefLight
    var shade: WardReliefLight
    var inner: Bool
    /// The ink edge's strength; 0 draws none.
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
/// at 0.45 to 0.6. A control's face (a button, a chip, a tile to tap, a
/// field) has a 1-pt edge in the ECG paper's blue that reads at least 3:1
/// on the base (the owner, 9 Oct: buttons "not visually distinct in
/// borders", then "make the line around the buttons match the grid
/// color"), so what can
/// be pressed stands apart from what cannot; a card or a slab shows its
/// shape by its lights alone, as Retro Press draws it, with an edge only
/// under Increase Contrast. Increase Contrast deepens the shade and
/// strengthens both edges.
enum WardRelief {
    static let lightShade: UInt32 = 0xA3B1C6
    static let highContrastShadeGain = 0.15
    /// A control's edge, light and dark, in the paper's blue: about 3.3:1
    /// on the base in both (the grid's own strength would be about 2:1).
    static let lightEdge = 0.85
    static let darkEdge = 0.65
    static let highContrastEdge = 1.0
    /// A card's or a slab's edge under Increase Contrast; none otherwise.
    static let containerHighContrastEdge = 0.35
    /// The least a control's boundary may read against the base (WCAG 1.4.11).
    static let edgeContrast = 3.0

    /// A control's edge strength.
    static func edgeAlpha(dark: Bool, highContrast: Bool = false) -> Double {
        highContrast ? highContrastEdge : (dark ? darkEdge : lightEdge)
    }

    /// A card's or a slab's edge strength: 0 unless Increase Contrast is on.
    static func containerEdgeAlpha(highContrast: Bool = false) -> Double {
        highContrast ? containerHighContrastEdge : 0
    }

    /// The ink of a control's edge: the ECG paper's blue, so the edges
    /// carry on the grid and its frame line.
    static func edgeHex(dark: Bool) -> UInt32 {
        WardPaper.ink(dark: dark, highContrast: false).hex
    }

    /// A control's edge as it lands on the base.
    static func edgeColor(dark: Bool, highContrast: Bool = false) -> UInt32 {
        composite(WardReliefLight(hex: edgeHex(dark: dark),
                                  alpha: edgeAlpha(dark: dark, highContrast: highContrast),
                                  x: 0, y: 0, radius: 0), on: base(dark: dark))
    }

    /// The shade's offset from the shape, down and right; the highlight
    /// falls the same distance up and left.
    static func offset(_ lift: WardLift) -> Double {
        switch lift {
        case .low: return 2
        case .mid: return 5
        case .high: return 8
        case .peak: return 11
        }
    }

    static func radius(_ lift: WardLift) -> Double {
        switch lift {
        case .low: return 3
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

    /// A surface raised off the base: a card or a slab, or with `control`
    /// a control's face, which carries the ink edge.
    static func raised(_ lift: WardLift, dark: Bool, highContrast: Bool = false,
                       control: Bool = false) -> WardReliefSpec {
        let d = offset(lift), r = radius(lift)
        return WardReliefSpec(
            highlight: WardReliefLight(hex: 0xFFFFFF, alpha: highlightAlpha(lift, dark: dark), x: -d, y: -d, radius: r),
            shade: WardReliefLight(hex: dark ? 0x000000 : lightShade,
                                   alpha: shadeAlpha(lift, dark: dark, highContrast: highContrast),
                                   x: d, y: d, radius: r),
            inner: false,
            edgeAlpha: control ? edgeAlpha(dark: dark, highContrast: highContrast)
                               : containerEdgeAlpha(highContrast: highContrast))
    }

    static func inset(_ lift: WardLift, dark: Bool, highContrast: Bool = false,
                      control: Bool = false) -> WardReliefSpec {
        raised(lift, dark: dark, highContrast: highContrast, control: control).mirrored()
    }

    /// What a light looks like where it lies at full strength on `base`.
    static func composite(_ light: WardReliefLight, on base: UInt32) -> UInt32 {
        let (r0, g0, b0) = WardPalette.rgb(base), (r1, g1, b1) = WardPalette.rgb(light.hex)
        func mix(_ a: Double, _ b: Double) -> UInt32 { UInt32(((a + (b - a) * light.alpha) * 255).rounded()) }
        return mix(r0, r1) << 16 | mix(g0, g1) << 8 | mix(b0, b1)
    }
}

/// Continuous control relief, independent of SwiftUI and its animation clock.
struct WardPressSpec: Equatable, Sendable {
    var blur: Double
    var outerShade: WardReliefLight
    var innerShade: WardReliefLight
    var innerHighlight: WardReliefLight
    var edgeAlpha: Double
}

enum WardPress {
    static let sinkScale = 0.985
    static let press = 0.05
    static let release = 0.07
    static let shadePress = 0.15
    static let shadeRelease = 0.18
    static let depth = 0.7
    static let softKeep = 0.6
    static let hollowSoft = 1.0

    static func soft(_ lift: WardLift) -> Double {
        Double(lift.rawValue + 1) / 2
    }
    static let quickCurve = (x1: 1.0 / 3, y1: 0.5, x2: 2.0 / 3, y2: 5.0 / 6)

    static func quick(_ u: Double) -> Double {
        let u = min(1, max(0, u))
        return u * (1.5 - 0.5 * u)
    }

    static func glide(_ u: Double) -> Double {
        sin(min(1, max(0, u)) * .pi / 2)
    }

    static func releaseHold(held: Double) -> Double {
        max(0, press - max(0, held))
    }

    /// A pressable face at `depth` (0 raised, 1 pressed in): a control's,
    /// with its ink edge, unless `control` is false (an icon tile that only
    /// shows a choice).
    static func spec(_ lift: WardLift, depth q: Double, dark: Bool,
                     highContrast: Bool = false, control: Bool = true) -> WardPressSpec {
        let q = min(1, max(0, q))
        let up = 1 - q, down = depth * q
        let raised = WardRelief.raised(lift, dark: dark, highContrast: highContrast, control: control)
        func light(_ original: WardReliefLight, weight: Double) -> WardReliefLight {
            WardReliefLight(hex: original.hex, alpha: original.alpha * weight,
                            x: original.x * weight, y: original.y * weight,
                            radius: original.radius * (softKeep + (1 - softKeep) * weight))
        }
        return WardPressSpec(blur: soft(lift) + hollowSoft * q,
                             outerShade: light(raised.shade, weight: up),
                             innerShade: light(raised.shade, weight: down),
                             innerHighlight: light(raised.highlight, weight: down),
                             edgeAlpha: raised.edgeAlpha)
    }
}

/// ECG paper geometry and ink, independent of the rendering framework.
struct WardPaperInk: Equatable, Sendable {
    var hex: UInt32
    var fine: Double
    var bold: Double
    var edge: Double
}

struct WardPaperPanel: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var radius: Double
}

enum WardPaper {
    static let frame = 12.0
    /// Keep controls four points inside the paper frame line.
    static let sideInset = frame + 4
    static let cell = 6.0
    static let boldEvery = 5
    static let line = 1.0
    static let edgeWidth = 1.5
    static let cornerShare = 53.33 / 428

    static func ink(dark: Bool, highContrast: Bool) -> WardPaperInk {
        WardPaperInk(hex: dark ? 0x78AAF5 : 0x2868C4,
                     fine: highContrast ? 0 : (dark ? 0.07 : 0.09),
                     bold: highContrast ? 0 : (dark ? 0.14 : 0.18),
                     edge: dark ? 0.5 : 0.55)
    }

    static func panel(width: Double, height: Double) -> WardPaperPanel? {
        guard width > 4 * frame, height > 4 * frame else { return nil }
        return WardPaperPanel(x: frame, y: frame,
                              width: width - 2 * frame, height: height - 2 * frame,
                              radius: (min(width, height) - 2 * frame) * cornerShare)
    }

    static func lines(_ length: Double) -> [(at: Double, bold: Bool)] {
        lines(length, from: 0)
    }

    /// The frame's lines (k·cell, bold every fifth) that fall in
    /// [origin, origin + length), in positions local to `origin`: a band
    /// that starts at a global `origin` lines up with the frame's grid.
    static func lines(_ length: Double, from origin: Double) -> [(at: Double, bold: Bool)] {
        guard length > 0, origin.isFinite, length.isFinite else { return [] }
        var result: [(at: Double, bold: Bool)] = []
        var k = Int((origin / cell).rounded(.up))
        while Double(k) * cell < origin + length {
            let at = Double(k) * cell - origin
            if at >= 0 {
                result.append((at: at, bold: ((k % boldEvery) + boldEvery) % boldEvery == 0))
            }
            k += 1
        }
        return result
    }
}
