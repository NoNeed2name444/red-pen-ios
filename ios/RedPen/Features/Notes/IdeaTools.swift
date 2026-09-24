import SwiftUI

// MARK: - The canvas tools
//
// The Board (Recentre, Connect) and the Space (Filter, Recentre) each have a
// couple of small tools. They share one shape and one place: a vertical
// cluster of 44-point glass circles, each standing on the floating plane, at the
// bottom-trailing corner just above Ideas' bottom container - under the right
// thumb on a phone - and on the trailing edge, vertically centred, on a wide
// iPad, where the right hand rests.

/// A vertical cluster of glass tool circles. There is no backing pill, so
/// each circle is lifted on its own (`.popOut(.floating, in: Circle())` on
/// the tool itself): the sheen, rim and slab follow the circles that are
/// really there, never the empty gap between them.
struct IdeaToolCluster<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                content
            }
        }
    }
}

/// The face of one tool: a symbol in a 44-point circle.
struct IdeaToolFace: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.medium))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

/// One round tool button. `active` tints it, for a tool that is switched on
/// (Connect) or narrowing what is shown (Filter).
struct IdeaToolButton: View {
    let symbol: String
    let label: String
    var active: Bool = false
    let action: () -> Void

    init(symbol: String, label: String, active: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.active = active
        self.action = action
    }

    var body: some View {
        let ink: Color = active ? Color.accentColor : Color.secondary
        let glass: Glass = IdeaToolGlass.glass(active: active)
        let traits: AccessibilityTraits = active ? .isSelected : []
        Button(action: action) {
            IdeaToolFace(symbol: symbol)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink)
        .glassEffect(glass, in: .circle)
        .popOut(.floating, in: Circle())
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
        .accessibilityAddTraits(traits)
    }
}

/// The glass under a tool: plain, or faintly tinted when the tool is on.
@MainActor
enum IdeaToolGlass {
    static func glass(active: Bool) -> Glass {
        if active {
            let wash: Color = Color.accentColor.opacity(0.3)
            return Glass.regular.tint(wash).interactive()
        }
        return Glass.regular.interactive()
    }
}

extension View {
    /// Puts a canvas's tools where they belong: bottom-trailing, just above
    /// the bottom container; on the trailing edge, vertically centred, on a
    /// wide iPad.
    func ideaTools<Tools: View>(@ViewBuilder _ tools: () -> Tools) -> some View {
        modifier(IdeaToolsPlacement(tools: tools()))
    }
}

private struct IdeaToolsPlacement<Tools: View>: ViewModifier {
    let tools: Tools
    @Environment(\.windowSpan) private var span

    func body(content: Content) -> some View {
        let broad: Bool = span == .broad
        let spot: Alignment = broad ? .trailing : .bottomTrailing
        content
            .overlay(alignment: spot) {
                IdeaToolCluster { tools }
                    .padding(16)
            }
    }
}
