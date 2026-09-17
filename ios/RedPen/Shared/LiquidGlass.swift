import SwiftUI

// MARK: - Liquid Glass, Apple's own way
//
// iOS 26's Liquid Glass is a real system material with a real API —
// `View.glassEffect(_:in:)`, `GlassEffectContainer`, and the `.glass` /
// `.glassProminent` button styles — so the app uses exactly those instead of
// faking the look with blurs and gradients. The project's deployment target
// is iOS 26, so nothing here needs an availability check.
//
// The two helpers below are just short names for the two shapes this app
// uses everywhere (a floating control bar and a small capsule chip), so a
// view can say `.liquidGlassPanel()` rather than spelling the shape out
// each time. They add nothing of their own on top of Apple's effect.

extension View {
    /// A floating bottom control bar — matches the way iOS 26's own toolbars
    /// and tab bars sit as a rounded pane of glass over the content.
    func liquidGlassPanel(cornerRadius: CGFloat = 22, tint: Color = .clear) -> some View {
        glassEffect(
            tint == .clear ? .regular : .regular.tint(tint),
            in: .rect(cornerRadius: cornerRadius)
        )
    }

    /// A small glass capsule — for the score / progress chips in each mode's
    /// header and the mode emoji on a library row.
    func liquidGlassChip(tint: Color = .accentColor) -> some View {
        glassEffect(.regular.tint(tint.opacity(0.35)), in: .capsule)
    }
}
