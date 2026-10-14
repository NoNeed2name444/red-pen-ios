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
    static let wardRaised = ward(.raised)
    static let wardWell = ward(.well)
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

    /// The ink of an edge: the ECG paper's blue (WardRelief.edgeHex), drawn
    /// at a spec's edge strength.
    static let wardEdgeInk = Color(uiColor: UIColor { traits in
        let (r, g, b) = WardPalette.rgb(WardRelief.edgeHex(dark: traits.userInterfaceStyle == .dark))
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    })

    /// A control's edge: the paper's blue at WardRelief.edgeAlpha, at least
    /// 3:1 on the base, stronger under Increase Contrast.
    static let wardEdge = Color(uiColor: UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        let (r, g, b) = WardPalette.rgb(WardRelief.edgeHex(dark: dark))
        return UIColor(red: r, green: g, blue: b,
                       alpha: WardRelief.edgeAlpha(dark: dark, highContrast: traits.accessibilityContrast == .high))
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

/// Gaps and padding, every one a step of WardScale (4, 8, 12, 16, 24, 32).
enum WardSpace {
    static let xs = CGFloat(WardScale.xs), s = CGFloat(WardScale.s), m = CGFloat(WardScale.m)
    /// the screen's side gutter, and a card's padding
    static let gutter = CGFloat(WardScale.l)
    static let l = CGFloat(WardScale.l), xl = CGFloat(WardScale.xl), xxl = CGFloat(WardScale.xxl)
    /// between the sections of a page
    static let section = CGFloat(WardScale.xl)
    /// extra room between the lines of a paragraph
    static let leading = CGFloat(WardScale.leading)
}

/// Corner radii, on the same scale.
enum WardRadius {
    static let card = CGFloat(WardScale.l)
    static let tile = CGFloat(WardScale.xl)
    static let button = CGFloat(WardScale.l)
    static let field = CGFloat(WardScale.m)
    static let icon = CGFloat(WardScale.m)
    static let bar = CGFloat(WardScale.xl)
}

/// Light to dark and back as a colour shift (WardSchemeGlide): the scheme
/// the window has is passed on to the app a beat later, under an
/// animation, so every Ward colour, which resolves from the scheme, moves
/// from the old palette to the new one instead of jumping. Colours change;
/// nothing fades. Under Reduce Motion the switch is immediate. Set once at
/// the root, outside the paper and the base, so they shift too.
struct WardSchemeGlideModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: ColorScheme?

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, shown ?? scheme)
            .onAppear { shown = scheme }
            .onChange(of: scheme) { _, now in
                if reduceMotion {
                    shown = now
                } else {
                    withAnimation(.easeInOut(duration: WardSchemeGlide.duration)) { shown = now }
                }
            }
    }
}

extension View {
    /// Light and dark switch with a colour shift (WardSchemeGlideModifier).
    func wardSchemeGlide() -> some View { modifier(WardSchemeGlideModifier()) }
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
