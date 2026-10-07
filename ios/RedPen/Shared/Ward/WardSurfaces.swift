#if canImport(SwiftUI)
import SwiftUI

// Soft UI: one matte base, and every surface shaped out of it by two lights
// from the top left. Raised, a highlight falls up and left of the shape and
// a shade down and right; pressed in, the same two fall inside it. The
// numbers are WardRelief's (tested on Linux); this file draws them.

extension ShadowStyle {
    /// A relief light as a SwiftUI shadow: dropped outside the shape, or cast
    /// inside it when the surface is pressed in.
    static func ward(_ light: WardReliefLight, inner: Bool) -> ShadowStyle {
        let color = Color(relief: light)
        let radius = CGFloat(light.radius), x = CGFloat(light.x), y = CGFloat(light.y)
        return inner ? .inner(color: color, radius: radius, x: x, y: y)
                     : .drop(color: color, radius: radius, x: x, y: y)
    }
}

/// A shape raised off the base or pressed into it. Raised, the two lights
/// are two fills, the shade drawn over the highlight, so neither shadows the
/// other; the face is one layer, so a fade fades it whole. Increase Contrast
/// deepens the shade and adds an ink edge.
struct WardReliefFace<S: InsettableShape>: View {
    let shape: S
    var lift: WardLift = .mid
    var inset = false
    var fill = AnyShapeStyle(Color.wardSurface)

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark: Bool = scheme == .dark
        let strong: Bool = contrast == .increased
        let spec: WardReliefSpec = inset ? WardRelief.inset(lift, dark: dark, highContrast: strong)
                                         : WardRelief.raised(lift, dark: dark, highContrast: strong)
        ZStack {
            if spec.inner {
                shape.fill(fill
                    .shadow(.ward(spec.shade, inner: true))
                    .shadow(.ward(spec.highlight, inner: true)))
            } else {
                shape.fill(fill.shadow(.ward(spec.highlight, inner: false)))
                shape.fill(fill.shadow(.ward(spec.shade, inner: false)))
            }
            if spec.edgeAlpha > 0 {
                shape.strokeBorder(Color.wardInk.opacity(spec.edgeAlpha), lineWidth: 1)
            }
        }
        .compositingGroup()
    }
}

extension WardReliefFace {
    init(shape: S, lift: WardLift = .mid, inset: Bool = false, fill: Color) {
        self.init(shape: shape, lift: lift, inset: inset, fill: AnyShapeStyle(fill))
    }
}

/// The base: one matte colour that every surface is shaped from. Decoration
/// only, so VoiceOver skips it.
struct WardBackground: View {
    var body: some View {
        Color.wardBackground
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A card: raised off the base, no line round it.
struct WardCardStyle: ViewModifier {
    var padding: CGFloat = WardSpace.gutter
    var lift: WardLift = .mid

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wardRaised(in: RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous), lift: lift)
    }
}

/// The vitals monitor: a dark well (Chart Ink in both modes, light text on
/// it) pressed into a raised bezel. In a List row the bezel stands as low
/// as the tiles do (`.low`, with wardCardRow).
struct MonitorCard<Content: View>: View {
    private let lift: WardLift
    private let content: Content
    init(lift: WardLift = .mid, @ViewBuilder content: () -> Content) {
        self.lift = lift
        self.content = content()
    }

    var body: some View {
        let bezel: CGFloat = 6
        content
            .padding(WardSpace.gutter - bezel / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.white)
            .wardInset(in: RoundedRectangle(cornerRadius: WardRadius.card - bezel, style: .continuous),
                       fill: .wardMonitor)
            .environment(\.colorScheme, .dark)
            .padding(bezel)
            .wardRaised(in: RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous), lift: lift)
    }
}

/// A List or Form row as a soft tile raised low off the base. A cell clips
/// what it draws, so the tile keeps clear of the cell's edges by more than
/// its lights reach and no cut shows; between rows that clearance is the gap
/// soft tiles stand apart by. Pressed in, it marks the chosen row.
struct WardRowTile: View {
    var inset = false

    /// A tiled row's insets: the tile's clearance (8 a side, 6 above and
    /// below) plus the room its content keeps inside it.
    static let insets = EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
    /// A row that is one big raised button: as far in on every side as the
    /// highest button's lights reach, so the cell never cuts them.
    static let buttonInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
    /// A row that is a card of its own, raised as low as the tiles: its
    /// edges where the tiles' are, its lights clear of the cell's.
    static let cardInsets = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

    var body: some View {
        WardReliefFace(shape: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous),
                       lift: .low, inset: inset)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }
}

extension View {
    func wardCard(padding: CGFloat = WardSpace.gutter, lift: WardLift = .mid) -> some View {
        modifier(WardCardStyle(padding: padding, lift: lift))
    }

    /// Raised off the base: cards, buttons, bars and knobs.
    func wardRaised<S: InsettableShape>(in shape: S, lift: WardLift = .mid, fill: Color = .wardSurface) -> some View {
        background { WardReliefFace(shape: shape, lift: lift, fill: fill) }
    }

    /// Pressed into the base: fields, tracks, wells and whatever is chosen.
    func wardInset<S: InsettableShape>(in shape: S, lift: WardLift = .low, fill: Color = .wardSurface) -> some View {
        background { WardReliefFace(shape: shape, lift: lift, inset: true, fill: fill) }
    }

    /// Raised at rest; pressed in, one lift nearer the base, while held or
    /// chosen.
    func wardRelief<S: InsettableShape>(in shape: S, lift: WardLift = .low, pressed: Bool) -> some View {
        background { WardReliefFace(shape: shape, lift: pressed ? lift.lower : lift, inset: pressed) }
    }

    /// The soft UI's controls: the Theatre Blue that reads on the base as
    /// the tint, and the soft switch and progress bar. Set at the root and
    /// on each screen. Text keeps its own colours (a style set here would
    /// override the tint on plain buttons).
    func wardControls() -> some View {
        self
            .tint(Color.wardPrimaryInk)
            .toggleStyle(WardToggleStyle())
            .progressViewStyle(WardProgressViewStyle())
    }

    /// A screen in the soft UI: the matte base under it and its controls.
    func wardScreen() -> some View {
        self
            .background(WardBackground())
            .wardControls()
    }

    /// A Form or List in the soft UI: its own grey ground hidden for the
    /// base, rows tall enough for their tiles, and the controls.
    func wardForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 56)
            .background(WardBackground())
            .wardControls()
    }

    /// A List or Form row (or a Section's rows) as soft tiles, with insets
    /// that keep the content clear of the tile's edge; the gap between the
    /// tiles parts them, so no separator line. A row that sets its own
    /// background or insets keeps them.
    func wardRowBackground() -> some View {
        self
            .listRowBackground(WardRowTile())
            .listRowInsets(WardRowTile.insets)
            .listRowSeparator(.hidden)
    }

    /// A List or Form row that is one big button: no tile under it, since
    /// the button is raised itself, and room around it for its lights.
    /// Wins over the tiles its Section sets.
    func wardButtonRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowInsets(WardRowTile.buttonInsets)
            .listRowSeparator(.hidden)
    }

    /// A List or Form row that is a card of its own (wardCard or a
    /// MonitorCard, lifted `.low`): no tile under it, and it stands where
    /// the tiles do. A card lifted higher would be cut by the cell.
    func wardCardRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowInsets(WardRowTile.cardInsets)
            .listRowSeparator(.hidden)
    }

    /// A List or Form row that is a well of its own (a WardBanner, a
    /// field): pressed into the base rather than into a tile, its edges
    /// where the tiles' are and its words where theirs are.
    func wardWellRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowInsets(PopOutField.rowInsets)
            .listRowSeparator(.hidden)
    }
}
#endif
