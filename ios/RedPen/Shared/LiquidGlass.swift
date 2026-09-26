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
// each time. They add nothing of their own on top of Apple's effect, except
// what `accessibleGlass` does for the reader who asked for it.
//
// Reduce Transparency and Increase Contrast: the glass becomes a solid
// surface with a visible edge. The system already frosts its glass further
// for both settings, but text on a pane over the moving night sky still
// wanted a surface that does not change behind it, and an edge that says
// where the control ends. (Solid is also cheaper than glass to draw.)

/// Liquid Glass, or a solid surface with an edge for the reader who asked
/// for less transparency or more contrast.
private struct AccessibleGlass<S: Shape>: ViewModifier {
    let glass: Glass
    let shape: S
    /// A wash of colour over the solid surface - the glass's tint, which a
    /// `Glass` value cannot be asked for.
    let wash: Color?
    /// The solid surface itself, for glass that carries white text over the
    /// camera rather than the screen's own ink; nil for the system's
    /// grouped background.
    let base: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background { solid }
                .overlay {
                    shape
                        .stroke(Color.primary.opacity(0.6), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var solid: some View {
        ZStack {
            shape.fill(base ?? Color(uiColor: .secondarySystemBackground))
            if let wash { shape.fill(wash) }
        }
    }
}

extension View {
    /// `glassEffect(_:in:)`, made solid with an edge under Reduce
    /// Transparency or Increase Contrast. Every glass surface in the app
    /// goes through this (or the panel and chip below, which use it).
    func accessibleGlass<S: Shape>(_ glass: Glass = .regular, in shape: S, wash: Color? = nil,
                                   base: Color? = nil) -> some View {
        modifier(AccessibleGlass(glass: glass, shape: shape, wash: wash, base: base))
    }
}

/// A glass capsule in the colour of the screen it sits on.
private struct GlassChip: ViewModifier {
    let tint: Color?
    @Environment(\.modeTint) private var modeTint

    func body(content: Content) -> some View {
        let colour: Color = (tint ?? modeTint).opacity(0.35)
        content.accessibleGlass(.regular.tint(colour), in: Capsule(), wash: colour.opacity(0.5))
    }
}

extension View {
    /// A floating bottom control bar — matches the way iOS 26's own toolbars
    /// and tab bars sit as a rounded pane of glass over the content.
    func liquidGlassPanel(cornerRadius: CGFloat = 22, tint: Color = .clear) -> some View {
        let glass: Glass = tint == .clear ? .regular : .regular.tint(tint)
        let wash: Color? = tint == .clear ? nil : tint
        return accessibleGlass(glass, in: RoundedRectangle(cornerRadius: cornerRadius), wash: wash)
    }

    /// A small glass capsule — for the score / progress chips in each mode's
    /// header and the mode emoji on a library row.
    /// `tint: nil` - the default - means "whatever colour this screen is",
    /// which is nearly always what a chip wants.
    func liquidGlassChip(tint: Color? = nil) -> some View {
        modifier(GlassChip(tint: tint))
    }

    /// The glass panel, standing out of the screen at `plane` (see
    /// PopOut.swift) as one unit.
    func liquidGlassPanel(cornerRadius: CGFloat = 22, tint: Color = .clear, plane: PopOutPlane) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return liquidGlassPanel(cornerRadius: cornerRadius, tint: tint)
            .popOut(plane, in: shape)
    }

    /// The glass chip, standing out of the screen at `plane`.
    func liquidGlassChip(tint: Color? = nil, plane: PopOutPlane) -> some View {
        liquidGlassChip(tint: tint)
            .popOut(plane, in: Capsule())
    }
}
