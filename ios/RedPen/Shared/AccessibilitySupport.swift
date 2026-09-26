import SwiftUI
import UIKit

// MARK: - The accessibility pieces every screen shares
//
// Small on purpose. The look stays the app's own - night sky, glass, pop
// tiles - and these only step in when the reader has asked for something:
//
//   scaledFont        a fixed point size that still follows the text size
//                     setting (the big countdown, the score, the dock's
//                     symbols), capped where a symbol would outgrow its place
//   Announce          a sentence for VoiceOver the moment something happens
//                     that is otherwise only seen: an answer marked, a card
//                     rated, a step revealed
//   Motion            an animation, or none under Reduce Motion; a slide that
//                     is only a fade under Reduce Motion
//   minimumHitTarget  44 by 44 points to press, whatever the face looks like
//   GridItem.tiles    tiles as many across as fit, or one across at the
//                     accessibility text sizes
//
// The glass itself (solid with an edge under Reduce Transparency and
// Increase Contrast) is in LiquidGlass.swift; the words VoiceOver says are in
// AccessibilityText.swift, where the Linux suite checks them.

/// A fixed size that grows and shrinks with the reader's text size, relative
/// to `style`, never past `maxSize`.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let maxSize: CGFloat

    init(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight,
         design: Font.Design, maxSize: CGFloat?) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
        self.maxSize = maxSize ?? .greatestFiniteMagnitude
    }

    func body(content: Content) -> some View {
        let shown: CGFloat = min(size, maxSize)
        return content.font(.system(size: shown, weight: weight, design: design))
    }
}

extension View {
    /// `.font(.system(size:weight:design:))` that follows Dynamic Type: the
    /// same size as before at the default text size, scaled like `style`
    /// from there. `maxSize` caps a symbol that would crowd its neighbours.
    func scaledFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body,
                    weight: Font.Weight = .regular, design: Font.Design = .default,
                    maxSize: CGFloat? = nil) -> some View {
        modifier(ScaledSystemFont(size: size, relativeTo: style, weight: weight,
                                  design: design, maxSize: maxSize))
    }

    /// At least 44 by 44 points to press - Apple's minimum - without changing
    /// how big the control looks.
    func minimumHitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// VoiceOver announcements.
enum Announce {
    /// Says `text` if VoiceOver is on. A moment's delay, so the sentence is
    /// not cut off by VoiceOver reading the button that was just pressed.
    @MainActor static func say(_ text: String) {
        guard !text.isEmpty, UIAccessibility.isVoiceOverRunning else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }
}

/// Animations that give way to Reduce Motion.
///
/// Most of the app's movement already asks SpaceQuality (the sky, the
/// pop-out, the warp) or reads accessibilityReduceMotion itself (the card
/// flip, the rings, rise-in). These are for the rest: the small state
/// changes and slides that were written as a plain `withAnimation`.
@MainActor
enum Motion {
    /// `animation`, or none at all under Reduce Motion.
    static func gentle(_ animation: Animation) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : animation
    }
}

extension AnyTransition {
    /// Slides in from `edge` as it fades - only the fade under Reduce Motion.
    @MainActor static func slideFade(_ edge: Edge) -> AnyTransition {
        if UIAccessibility.isReduceMotionEnabled { return .opacity }
        return .move(edge: edge).combined(with: .opacity)
    }

    /// Grows from `scale` as it fades - only the fade under Reduce Motion.
    @MainActor static func growFade(_ scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition {
        if UIAccessibility.isReduceMotionEnabled { return .opacity }
        return .scale(scale: scale, anchor: anchor).combined(with: .opacity)
    }
}

extension GridItem {
    /// Tiles as many across as fit at `minimum` points wide - or one across
    /// at the accessibility text sizes, where a tile's words need the whole
    /// width rather than being cut off at two lines.
    static func tiles(minimum: CGFloat, maximum: CGFloat = .infinity, spacing: CGFloat = 12,
                      accessibilitySize: Bool) -> [GridItem] {
        if accessibilitySize { return [GridItem(.flexible(), spacing: spacing)] }
        return [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: spacing)]
    }
}
