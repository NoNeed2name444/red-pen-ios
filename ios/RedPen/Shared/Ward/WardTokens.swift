#if canImport(SwiftUI)
import SwiftUI
import UIKit

// The Ward Round palette as SwiftUI colours, type, spacing and radii. Every
// colour comes from WardPalette's table through a dynamic UIColor, so light
// and dark have one source and no colour set can drift. The soft UI light
// (WardRelief) is drawn by WardSurfaces.

extension Color {
    static func ward(_ token: WardToken) -> Color {
        Color(uiColor: UIColor { traits in
            let (r, g, b) = WardPalette.rgb(WardPalette.hex(token, dark: traits.userInterfaceStyle == .dark))
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }

    static let wardBackground = ward(.background)
    static let wardSurface = ward(.surface)
    static let wardPrimary = ward(.primary)
    static let wardPrimaryInk = ward(.primaryInk)
    static let wardOnPrimary = ward(.onPrimary)
    static let wardEcg = ward(.ecg)
    static let wardBeam = ward(.beam)
    static let wardSuccess = ward(.success)
    static let wardWarning = ward(.warning)
    static let wardDanger = ward(.danger)
    static let wardInk = ward(.ink)
    static let wardInkSecondary = ward(.inkSecondary)
    static let wardHairline = ward(.hairline)
    static let wardMonitor = ward(.monitor)

    /// Increase Contrast's edge: Chart Ink at WardRelief.highContrastEdge,
    /// clear otherwise, so a line drawn with it shows only when asked for.
    static let wardEdge = Color(uiColor: UIColor { traits in
        guard traits.accessibilityContrast == .high else { return .clear }
        let (r, g, b) = WardPalette.rgb(WardPalette.hex(.ink, dark: traits.userInterfaceStyle == .dark))
        return UIColor(red: r, green: g, blue: b, alpha: WardRelief.highContrastEdge)
    })

    /// One relief light at its strength.
    init(relief light: WardReliefLight) {
        let (r, g, b) = WardPalette.rgb(light.hex)
        self.init(red: r, green: g, blue: b, opacity: light.alpha)
    }
}

/// The type: system fonts only (SF Pro, SF Mono for observations), every one
/// a text style so Dynamic Type scales it.
enum WardType {
    static let display = Font.largeTitle.bold()
    static let title = Font.title3.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let caption = Font.caption
    /// Observations: BP 128/82
    static let obs = Font.system(.body, design: .monospaced)
    static let obsLarge = Font.system(.title2, design: .monospaced).weight(.semibold)
}

enum WardSpace {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12
    /// the screen's side gutter
    static let gutter: CGFloat = 16
    static let l: CGFloat = 20, xl: CGFloat = 24
}

enum WardRadius {
    static let card: CGFloat = 16
    static let button: CGFloat = 14
    static let field: CGFloat = 12
    static let icon: CGFloat = 10
    static let bar: CGFloat = 22
}

/// A small-caps label ("TODAY'S WARD ROUND"): the source string stays in
/// mixed case so VoiceOver reads words, not letters.
struct WardSmallCaps: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Color.wardInkSecondary)
    }
}

extension View {
    func wardSmallCaps() -> some View { modifier(WardSmallCaps()) }
}
#endif
