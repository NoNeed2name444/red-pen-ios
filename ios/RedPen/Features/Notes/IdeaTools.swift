import SwiftUI

// MARK: - The canvas tools
//
// The Board (Recentre, Connect, Look) and the Space (Filter, Recentre) each have a
// couple of small tools. They share one shape and one place: a vertical
// cluster of 44-point circles at the bottom-trailing corner just above Ideas'
// bottom container - under the right thumb on a phone - and on the trailing
// edge, vertically centred, on a wide iPad, where the right hand rests. Each
// is a soft circle raised off the base on the floating plane; a tool that is
// on is pressed in, its glyph Theatre Blue. Over the 3D map they take the
// dark scheme with the rest of its chrome.

/// A vertical cluster of tool circles, with no backing pill: each circle
/// carries its own relief, spaced apart so each reads on its own.
struct IdeaToolCluster<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 16) {
            content
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

    /// A tool's glyph: Theatre Blue while the tool is on, Biro Grey at rest.
    static func ink(active: Bool) -> Color {
        active ? Color.wardPrimaryInk : Color.wardInkSecondary
    }
}

/// One round tool button. `active` presses it in and turns its glyph
/// Theatre Blue, for a tool that is switched on (Connect) or narrowing what
/// is shown (Filter).
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
        let traits: AccessibilityTraits = active ? .isSelected : []
        Button(action: action) {
            IdeaToolFace(symbol: symbol)
                .foregroundStyle(IdeaToolFace.ink(active: active))
        }
        .buttonStyle(IdeaToolStyle(active: active))
        .accessibilityLabel(label)
        .accessibilityAddTraits(traits)
    }
}

/// A tool circle as a button: raised off the base on the floating plane,
/// pressed in while it is held or while the tool is on.
struct IdeaToolStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ideaToolRelief(active: active || configuration.isPressed)
    }
}

extension View {
    /// A tool's circle, for one that is not a Button (a Menu's label): the
    /// floating plane's relief, pressed in while the tool is on.
    func ideaToolRelief(active: Bool) -> some View {
        self
            .popOut(.floating, in: Circle(), pressed: active)
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.highlight)
    }
}

/// "Lines: Curved / Straight", as a section of a Look menu - the 3D map's
/// (GraphStyleTool) and the board's (IdeaBoardLookTool). It is the same
/// stored choice as Settings > Look and feel (GraphLineStyle); the map
/// redraws its links on the next frame, the board at once.
struct IdeaLinesPicker: View {
    @AppStorage(SpaceSettings.straightLinesKey) private var straightLines: Bool = false
    /// Two segments side by side, for the board's small popover.
    var segmented: Bool = false

    var body: some View {
        if segmented {
            WardSegmented(selection: styleBinding, options: GraphLineStyle.allCases) { style in
                Text(style.title)
                    .accessibilityIdentifier("lookLines-" + style.rawValue)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Lines")
        } else {
            menuSection
        }
    }

    private var menuSection: some View {
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

    /// The same, as a style, for the segments.
    private var styleBinding: Binding<GraphLineStyle> {
        Binding<GraphLineStyle>(
            get: { GraphLineStyle.inForce(straightLines) },
            set: { straightLines = $0.isStraight }
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
/// Pressed in, its glyph Theatre Blue, while it is off the standard
/// (Straight). A small popover on the base pointing at the button, beside
/// the tool circles, rather than a menu that grows out over the cards.
struct IdeaBoardLookTool: View {
    @AppStorage(SpaceSettings.straightLinesKey) private var straightLines: Bool = false
    @State private var showing = false

    var body: some View {
        let straight: Bool = GraphLineStyle.inForce(straightLines).isStraight
        Button { showing = true } label: {
            IdeaToolFace(symbol: "paintpalette")
                .foregroundStyle(IdeaToolFace.ink(active: straight))
        }
        .buttonStyle(IdeaToolStyle(active: straight))
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            IdeaLinesPicker(segmented: true)
                .frame(width: 200)
                .padding(12)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Color.wardBackground)
        }
        .accessibilityLabel("Look")
        .accessibilityValue(straight ? "Straight lines" : "Curved lines")
        .accessibilityHint("Choose whether the lines between cards are curved or straight.")
    }
}

extension View {
    /// Puts a canvas's tools where they belong: bottom-trailing, just above
    /// the bottom container; on the trailing edge, vertically centred, on a
    /// wide iPad. `corner` keeps them stacked at the bottom-trailing corner
    /// on every window (the 3D map, as the design targets draw it).
    func ideaTools<Tools: View>(corner: Bool = false, @ViewBuilder _ tools: () -> Tools) -> some View {
        modifier(IdeaToolsPlacement(tools: tools(), corner: corner))
    }
}

private struct IdeaToolsPlacement<Tools: View>: ViewModifier {
    let tools: Tools
    var corner: Bool = false
    @Environment(\.windowSpan) private var span

    func body(content: Content) -> some View {
        let broad: Bool = span == .broad && !corner
        let spot: Alignment = broad ? .trailing : .bottomTrailing
        content
            .overlay(alignment: spot) {
                IdeaToolCluster { tools }
                    .padding(16)
            }
    }
}
