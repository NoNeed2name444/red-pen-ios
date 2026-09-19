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

/// A glass capsule in the colour of the screen it sits on.
private struct GlassChip: ViewModifier {
    let tint: Color?
    @Environment(\.modeTint) private var modeTint

    func body(content: Content) -> some View {
        content.glassEffect(.regular.tint((tint ?? modeTint).opacity(0.35)), in: .capsule)
    }
}

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
    /// `tint: nil` - the default - means "whatever colour this screen is",
    /// which is nearly always what a chip wants.
    func liquidGlassChip(tint: Color? = nil) -> some View {
        modifier(GlassChip(tint: tint))
    }
}
