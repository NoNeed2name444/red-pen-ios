import SwiftUI

// MARK: - The canvas tools
//
// The Board (Recentre, Connect, Look) and the Space (Filter, Recentre) each have a
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

/// "Lines: Curved / Straight", as a section of a Look menu - the 3D map's
/// (GraphStyleTool) and the board's (IdeaBoardLookTool). It is the same
/// stored choice as Settings > Look and feel (GraphLineStyle); the map
/// redraws its links on the next frame, the board at once.
struct IdeaLinesPicker: View {
    @AppStorage(SpaceSettings.straightLinesKey) private var straightLines: Bool = false

    var body: some View {
        Section("Lines") {
            Picker("Lines", selection: straightBinding) {
                ForEach(GraphLineStyle.allCases) { style in
                    Label(style.title, systemImage: Self.symbol(style))
                        .tag(style.isStraight)
                        .accessibilityIdentifier("lookLines-" + style.rawValue)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    /// The style in force (a design-preview run's `-ideasLines` included),
    /// written back as the stored choice.
    private var straightBinding: Binding<Bool> {
        Binding<Bool>(
            get: { GraphLineStyle.inForce(straightLines).isStraight },
            set: { straightLines = $0 }
        )
    }

    static func symbol(_ style: GraphLineStyle) -> String {
        switch style {
        case .curved: return "point.topleft.down.to.point.bottomright.curvepath"
        case .straight: return "line.diagonal"
        }
    }
}

/// The board's Look tool: how its connectors are drawn (IdeaLinesPicker).
/// Tinted while it is off the standard (Straight).
struct IdeaBoardLookTool: View {
    @AppStorage(SpaceSettings.straightLinesKey) private var straightLines: Bool = false

    var body: some View {
        let straight: Bool = GraphLineStyle.inForce(straightLines).isStraight
        let ink: Color = straight ? Color.accentColor : Color.secondary
        let glass: Glass = IdeaToolGlass.glass(active: straight)
        Menu {
            IdeaLinesPicker()
        } label: {
            IdeaToolFace(symbol: "paintpalette")
        }
        .foregroundStyle(ink)
        .glassEffect(glass, in: .circle)
        .popOut(.floating, in: Circle())
        .hoverEffect(.highlight)
        .accessibilityLabel("Look")
        .accessibilityValue(straight ? "Straight lines" : "Curved lines")
        .accessibilityHint("Choose whether the lines between cards are curved or straight.")
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
