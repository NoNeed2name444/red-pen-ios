import SwiftUI

// MARK: - The canvas tools
//
// The Board (Recentre, Connect, Look) and the Space (Filter, Recentre) each have a
// couple of small tools. They share one shape and one place: a vertical
// cluster of 44-point circles at the bottom-trailing corner just above Ideas'
// bottom container - under the right thumb on a phone - and on the trailing
// edge, vertically centred, on a wide iPad, where the right hand rests. The
// board's are white with a hairline (Ward Round); the 3D map keeps its glass
// circles, part of its space look.

/// A vertical cluster of tool circles, with no backing pill: each circle
/// carries its own surface, so nothing is drawn in the gap between them.
/// The glass container only matters to the 3D map's glass circles.
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
/// (Connect) or narrowing what is shown (Filter). `ward` gives the board's
/// white circle; without it, the 3D map's glass one.
struct IdeaToolButton: View {
    let symbol: String
    let label: String
    var active: Bool = false
    var ward: Bool = false
    let action: () -> Void

    init(symbol: String, label: String, active: Bool = false, ward: Bool = false,
         action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.active = active
        self.ward = ward
        self.action = action
    }

    var body: some View {
        let traits: AccessibilityTraits = active ? .isSelected : []
        face
            .hoverEffect(.highlight)
            .accessibilityLabel(label)
            .accessibilityAddTraits(traits)
    }

    @ViewBuilder
    private var face: some View {
        if ward {
            Button(action: action) {
                IdeaToolFace(symbol: symbol)
            }
            .buttonStyle(.plain)
            .modifier(IdeaToolWardFace(active: active))
        } else {
            // the 3D map's space look, which keeps its glass and system tint
            let ink: Color = active ? Color.accentColor : Color.secondary
            let glass: Glass = IdeaToolGlass.glass(active: active)
            Button(action: action) {
                IdeaToolFace(symbol: symbol)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ink)
            .glassEffect(glass, in: .circle)
            .popOut(.floating, in: Circle())
        }
    }
}

/// The board's tool circle: Clean Sheet with a hairline, Theatre Blue when on.
struct IdeaToolWardFace: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        let ink: Color = active ? Color.wardOnPrimary : Color.wardPrimaryInk
        let fill: Color = active ? Color.wardPrimary : Color.wardSurface
        let edge: Color = active ? Color.clear : Color.wardHairline
        content
            .foregroundStyle(ink)
            .background(fill, in: Circle())
            .overlay(Circle().strokeBorder(edge, lineWidth: 1))
            .wardShadow()
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
            Picker("Lines", selection: straightBinding) {
                ForEach(GraphLineStyle.allCases) { style in
                    Text(style.title)
                        .tag(style.isStraight)
                        .accessibilityIdentifier("lookLines-" + style.rawValue)
                }
            }
            .pickerStyle(.segmented)
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

    static func symbol(_ style: GraphLineStyle) -> String {
        switch style {
        case .curved: return "point.topleft.down.to.point.bottomright.curvepath"
        case .straight: return "line.diagonal"
        }
    }
}

/// The board's Look tool: how its connectors are drawn (IdeaLinesPicker).
/// Tinted while it is off the standard (Straight). A small popover pointing
/// at the button, beside the tool circles, rather than a menu that grows out
/// over the cards.
struct IdeaBoardLookTool: View {
    @AppStorage(SpaceSettings.straightLinesKey) private var straightLines: Bool = false
    @State private var showing = false

    var body: some View {
        let straight: Bool = GraphLineStyle.inForce(straightLines).isStraight
        Button { showing = true } label: {
            IdeaToolFace(symbol: "paintpalette")
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            IdeaLinesPicker(segmented: true)
                .frame(width: 200)
                .padding(12)
                .presentationCompactAdaptation(.popover)
        }
        .modifier(IdeaToolWardFace(active: straight))
        .hoverEffect(.highlight)
        .accessibilityLabel("Look")
        .accessibilityValue(straight ? "Straight lines" : "Curved lines")
        .accessibilityHint("Choose whether the lines between cards are curved or straight.")
    }
}

/// The glass under a 3D-map tool (its space look, which stays): plain, or
/// faintly tinted when the tool is on.
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
