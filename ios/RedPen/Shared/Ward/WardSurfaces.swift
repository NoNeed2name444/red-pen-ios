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

extension Animation {
    static func wardClick(down: Bool) -> Animation {
        let c = WardPress.quickCurve
        return .timingCurve(c.x1, c.y1, c.x2, c.y2,
                            duration: down ? WardPress.press : WardPress.release)
    }

    static func wardShade(down: Bool) -> Animation {
        Animation(WardShadeAnimation(duration: down ? WardPress.shadePress : WardPress.shadeRelease))
    }
}

private struct WardShadeAnimation: CustomAnimation {
    let duration: TimeInterval

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval,
                                       context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: WardPress.glide(time / duration))
    }
}

/// A control anywhere inside a container keeps that container on the base.
struct WardHoldsControl: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        let next = nextValue()
        value = value || next
    }
}

/// Controls soften the base-colour face and active lights together as they glide
/// into the page; labels stay sharp, as does the Increase Contrast edge.
struct WardPressFace<S: InsettableShape>: View {
    let shape: S
    var lift: WardLift = .mid
    var pressed: Bool
    var fill = AnyShapeStyle(Color.wardSurface)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        WardPressRelief(shape: shape, lift: lift, depth: pressed ? 1 : 0,
                        fill: fill, dark: scheme == .dark, strong: contrast == .increased)
            .animation(reduceMotion ? nil : .wardShade(down: pressed), value: pressed)
            .preference(key: WardHoldsControl.self, value: true)
    }
}

extension WardPressFace {
    init(shape: S, lift: WardLift = .mid, pressed: Bool, fill: Color) {
        self.init(shape: shape, lift: lift, pressed: pressed, fill: AnyShapeStyle(fill))
    }
}

private struct WardPressRelief<S: InsettableShape>: View, Animatable {
    let shape: S
    let lift: WardLift
    var depth: Double
    let fill: AnyShapeStyle
    let dark: Bool
    let strong: Bool

    var animatableData: Double {
        get { depth }
        set { depth = newValue }
    }

    var body: some View {
        let spec = WardPress.spec(lift, depth: depth, dark: dark, highContrast: strong)
        ZStack {
            ZStack {
                if spec.outerShade.lit {
                    shape.fill(fill.shadow(.ward(spec.outerShade, inner: false)))
                } else {
                    shape.fill(fill)
                }
                if spec.innerShade.lit || spec.innerHighlight.lit {
                    shape.fill(innerFill(spec))
                }
            }
            .compositingGroup()
            .blur(radius: spec.blur)
            if spec.edgeAlpha > 0 {
                shape.strokeBorder(Color.wardInk.opacity(spec.edgeAlpha), lineWidth: 1)
            }
        }
    }

    private func innerFill(_ spec: WardPressSpec) -> AnyShapeStyle {
        var style = fill
        if spec.innerShade.lit {
            style = AnyShapeStyle(style.shadow(.ward(spec.innerShade, inner: true)))
        }
        if spec.innerHighlight.lit {
            style = AnyShapeStyle(style.shadow(.ward(spec.innerHighlight, inner: true)))
        }
        return style
    }
}

/// A shape raised off the base or pressed into it. Raised, the two lights
/// are two fills, the shade drawn over the highlight, so neither shadows the
/// other; the face is one layer, so a fade fades it whole. Increase Contrast
/// deepens the shade and adds an ink edge. Flat containers keep only the fill
/// and that contrast edge, so their controls stand just one level high.
struct WardReliefFace<S: InsettableShape>: View {
    let shape: S
    var lift: WardLift = .mid
    var inset = false
    var flat = false
    var fill = AnyShapeStyle(Color.wardSurface)

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark: Bool = scheme == .dark
        let strong: Bool = contrast == .increased
        let spec: WardReliefSpec = inset ? WardRelief.inset(lift, dark: dark, highContrast: strong)
                                         : WardRelief.raised(lift, dark: dark, highContrast: strong)
        ZStack {
            if flat {
                shape.fill(fill)
            } else if spec.inner {
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
    init(shape: S, lift: WardLift = .mid, inset: Bool = false, flat: Bool = false, fill: Color) {
        self.init(shape: shape, lift: lift, inset: inset, flat: flat, fill: AnyShapeStyle(fill))
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

/// Still ECG paper around the screen; content scrolls beneath the open panel.
struct WardPaperFrame: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            guard let panel = WardPaper.panel(width: Double(size.width), height: Double(size.height)) else { return }
            let ink = WardPaper.ink(dark: scheme == .dark, highContrast: contrast == .increased)
            let (r, g, b) = WardPalette.rgb(ink.hex)
            let color = Color(red: r, green: g, blue: b)
            let rect = CGRect(origin: .zero, size: size)
            let panelRect = CGRect(x: panel.x, y: panel.y, width: panel.width, height: panel.height)
            let hole = RoundedRectangle(cornerRadius: CGFloat(panel.radius), style: .continuous)
                .path(in: panelRect)
            var frame = Path(rect)
            frame.addPath(hole)
            context.drawLayer { layer in
                layer.clip(to: frame, style: FillStyle(eoFill: true))
                layer.fill(Path(rect), with: .color(.wardBackground))
                func drawLine(_ line: Path, bold: Bool) {
                    if ink.fine > 0 {
                        layer.fill(line, with: .color(color.opacity(ink.fine)))
                    }
                    if bold && ink.bold > 0 {
                        layer.fill(line, with: .color(color.opacity(ink.bold)))
                    }
                }
                if ink.fine > 0 || ink.bold > 0 {
                    for line in WardPaper.lines(Double(size.width)) {
                        drawLine(Path(CGRect(x: line.at, y: 0, width: WardPaper.line,
                                             height: size.height)), bold: line.bold)
                    }
                    for line in WardPaper.lines(Double(size.height)) {
                        drawLine(Path(CGRect(x: 0, y: line.at, width: size.width,
                                             height: WardPaper.line)), bold: line.bold)
                    }
                }
            }
            context.stroke(hole, with: .color(color.opacity(ink.edge)), lineWidth: WardPaper.edgeWidth)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A card: raised when it holds no Ward control, otherwise flat on the base.
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
/// it) pressed into a bezel, flat when it holds a Ward control. In a List row
/// a raised bezel stands as low
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
    /// A solid strip under a bar: it hides and blocks the rows beneath, and
    /// nothing fades. The room above the bar is for its lights (a `.high`
    /// slab's reach about 20 pt). Hidden, it takes no room; shown or hidden,
    /// the bar keeps its identity, so a fold never cross-fades it.
    func wardBarBase(room: CGFloat = 24, shown: Bool = true) -> some View {
        self.padding(.top, shown ? room : 0)
            .background {
                if shown {
                    Color.wardBackground
                        .ignoresSafeArea(edges: [.horizontal, .bottom])
                        .transition(.identity)
                }
            }
    }

    func wardCard(padding: CGFloat = WardSpace.gutter, lift: WardLift = .mid) -> some View {
        modifier(WardCardStyle(padding: padding, lift: lift))
    }

    /// Containers stand off the base unless they hold a Ward control; then
    /// only the control is raised and the container keeps its fill and contrast edge.
    func wardRaised<S: InsettableShape>(in shape: S, lift: WardLift = .mid, fill: Color = .wardSurface) -> some View {
        backgroundPreferenceValue(WardHoldsControl.self) { holdsControl in
            WardReliefFace(shape: shape, lift: lift, flat: holdsControl, fill: fill)
        }
    }

    /// Pressed into the base: fields, tracks, wells and whatever is chosen.
    func wardInset<S: InsettableShape>(in shape: S, lift: WardLift = .low, fill: Color = .wardSurface) -> some View {
        background { WardReliefFace(shape: shape, lift: lift, inset: true, fill: fill) }
    }

    /// Raised at rest; glides into a hollow at the same lift while held or chosen.
    func wardRelief<S: InsettableShape>(in shape: S, lift: WardLift = .low, pressed: Bool) -> some View {
        background { WardPressFace(shape: shape, lift: lift, pressed: pressed) }
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
