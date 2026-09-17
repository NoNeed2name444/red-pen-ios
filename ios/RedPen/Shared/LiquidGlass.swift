import SwiftUI

// MARK: - Liquid Glass chrome
//
// iOS 26 introduced a "Liquid Glass" material for system chrome — toolbars,
// tab bars, and controls render as a translucent, specular, light-bending
// surface rather than a flat blur. Apple's real API for it (`.glassEffect()`,
// `GlassEffectContainer`) ships only in the iOS 26 SDK, and this project's
// CI runner's exact Xcode version isn't pinned/known ahead of a build, so
// depending on that symbol directly risks a hard compile failure with no
// way to detect it beforehand. Instead, this file hand-builds the same
// *look* — translucent material, a soft specular highlight along the top
// edge, a hairline rim light, and a floating (rather than edge-to-edge)
// silhouette — entirely with APIs that have been stable since iOS 15, so it
// compiles on whatever SDK the runner has while still reading as "glass."
// If/when the real API is confirmed available here, `.liquidGlass()` below
// is the one place to swap in `.glassEffect()`.

/// Rounded, floating glass panel — the look this app uses for every bottom
/// control bar (quiz footers, the Anki rating row, the Narrate player).
struct LiquidGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 22
    var tint: Color = .clear

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    if tint != .clear {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.10))
                    }
                    // specular highlight, as if light is grazing the top of the glass
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.0)],
                                startPoint: .top, endPoint: .center
                            )
                        )
                        .blendMode(.plusLighter)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
            )
    }
}

extension View {
    /// Wraps this view in a floating Liquid-Glass-style panel. Use for a
    /// bottom control bar in place of `.background(.bar)`.
    func liquidGlassPanel(cornerRadius: CGFloat = 22, tint: Color = .clear) -> some View {
        modifier(LiquidGlassPanel(cornerRadius: cornerRadius, tint: tint))
    }

    /// A smaller glass chip — for the score/progress capsules in each
    /// mode's header, replacing a flat tinted-color capsule.
    func liquidGlassChip(tint: Color = .accentColor) -> some View {
        self
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.6))
            )
    }
}

/// A button style that reads as a glass control: translucent capsule body,
/// a specular top edge, and the soft press-in "squish" Liquid Glass
/// controls use instead of a flat opacity change.
struct LiquidGlassButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : tint)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(prominent ? tint.opacity(0.92) : Color.clear)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(prominent ? 0.30 : 0.45), .white.opacity(0.0)],
                                    startPoint: .top, endPoint: .center
                                )
                            )
                            .blendMode(.plusLighter)
                    )
                    .overlay(
                        Capsule().strokeBorder(.white.opacity(prominent ? 0.35 : 0.5), lineWidth: 0.8)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle { LiquidGlassButtonStyle() }
    static func liquidGlass(tint: Color) -> LiquidGlassButtonStyle { LiquidGlassButtonStyle(tint: tint) }
    static func liquidGlassProminent(tint: Color = .accentColor) -> LiquidGlassButtonStyle { LiquidGlassButtonStyle(tint: tint, prominent: true) }
}
