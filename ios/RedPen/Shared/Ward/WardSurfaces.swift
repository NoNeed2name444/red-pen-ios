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

/// Faces drawn without their lights: no shade cast round them and no
/// softening of their outline, only the face, its edge and, held or
/// chosen, the hollow inside it. For what floats over a page (the home's
/// New set and dock: the owner, 9 Oct, "remove the glow around the deck
/// and floating buttons").
private struct WardUnlitKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var wardUnlit: Bool {
        get { self[WardUnlitKey.self] }
        set { self[WardUnlitKey.self] = newValue }
    }
}

extension View {
    /// The Ward faces inside are drawn without their lights (WardUnlitKey).
    func wardUnlit(_ unlit: Bool = true) -> some View {
        environment(\.wardUnlit, unlit)
    }
}

/// Controls soften the base-colour face and active lights together as they glide
/// into the page; labels stay sharp, as does the ink edge. A face that only
/// shows a choice (an icon tile) passes `control: false` and has no edge.
///
/// At rest the lights are drawn once and shown from an image (WardLightImages);
/// while the face is pressed, held or moving between the two, they are live.
struct WardPressFace<S: InsettableShape>: View {
    let shape: S
    var lift: WardLift = .mid
    var pressed: Bool
    var fill: AnyShapeStyle
    /// The fill when it is a plain colour, the only fill the images cover.
    var fillColor: Color?
    var control = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.wardUnlit) private var unlit

    init(shape: S, lift: WardLift = .mid, pressed: Bool, fill: Color = .wardSurface, control: Bool = true) {
        self.shape = shape
        self.lift = lift
        self.pressed = pressed
        self.fill = AnyShapeStyle(fill)
        self.fillColor = fill
        self.control = control
    }

    /// Any fill: drawn live, since the images cover colours only.
    init(shape: S, lift: WardLift = .mid, pressed: Bool, fill: AnyShapeStyle, control: Bool = true) {
        self.shape = shape
        self.lift = lift
        self.pressed = pressed
        self.fill = fill
        self.fillColor = nil
        self.control = control
    }

    var body: some View {
        WardPressRelief(shape: shape, lift: lift, depth: pressed ? 1 : 0, fill: fill, fillColor: fillColor,
                        dark: scheme == .dark, strong: contrast == .increased, control: control,
                        unlit: unlit)
            .animation(reduceMotion ? nil : .wardShade(down: pressed), value: pressed)
            .preference(key: WardHoldsControl.self, value: true)
    }
}

private struct WardPressRelief<S: InsettableShape>: View, Animatable {
    let shape: S
    let lift: WardLift
    var depth: Double
    let fill: AnyShapeStyle
    let fillColor: Color?
    let dark: Bool
    let strong: Bool
    let control: Bool
    var unlit = false

    /// Below this a face counts as at rest: the picture is the same to the eye.
    private static var rest: Double { 0.001 }

    var animatableData: Double {
        get { depth }
        set { depth = newValue }
    }

    var body: some View {
        let live = WardPressDrawing(shape: shape, lift: lift, depth: depth, fill: fill,
                                    dark: dark, strong: strong, control: control, unlit: unlit)
        if depth <= Self.rest, !unlit, let fillColor, let kind = WardFaceShape(shape) {
            let spec = WardPress.spec(lift, depth: 0, dark: dark, highContrast: strong, control: control)
            WardLitFace(kind: kind, look: .press, lift: lift, control: control, dark: dark, strong: strong,
                        fill: fillColor, reach: WardLightSlice.reach(spec), inner: false, live: live) { outline, dark in
                AnyView(WardPressDrawing(shape: outline, lift: lift, depth: 0, fill: fill,
                                         dark: dark, strong: strong, control: control, unlit: false))
            }
        } else {
            live
        }
    }
}

/// A pressable face's drawing at `depth`: the one drawing code, run live or
/// into an image (WardLitFace).
private struct WardPressDrawing<S: InsettableShape>: View {
    let shape: S
    let lift: WardLift
    let depth: Double
    let fill: AnyShapeStyle
    let dark: Bool
    let strong: Bool
    let control: Bool
    let unlit: Bool

    var body: some View {
        let spec = WardPress.spec(lift, depth: depth, dark: dark, highContrast: strong, control: control)
        ZStack {
            ZStack {
                if spec.outerShade.lit && !unlit {
                    shape.fill(fill.shadow(.ward(spec.outerShade, inner: false)))
                } else {
                    shape.fill(fill)
                }
                if spec.innerShade.lit || spec.innerHighlight.lit {
                    shape.fill(innerFill(spec))
                }
            }
            .compositingGroup()
            .blur(radius: unlit ? 0 : spec.blur)
            if spec.edgeAlpha > 0 {
                shape.strokeBorder(Color.wardEdgeInk.opacity(spec.edgeAlpha), lineWidth: 1)
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
/// other; the face is one layer. A control's face (`control`: a tile to tap,
/// a field, a switch's track) has a 1-pt ink edge at 3:1 or more on the
/// base; a card's or a slab's has one only under Increase Contrast, which
/// also deepens the shade. Flat containers keep only the fill (and that
/// edge), so their controls stand just one level high.
///
/// Its lights are drawn once and shown from an image (WardLightImages) when
/// the shape and the fill are ones the images cover; otherwise live.
struct WardReliefFace<S: InsettableShape>: View {
    let shape: S
    var lift: WardLift = .mid
    var inset = false
    var flat = false
    var fill: AnyShapeStyle
    /// The fill when it is a plain colour, the only fill the images cover.
    var fillColor: Color?
    var control = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.wardUnlit) private var unlit

    init(shape: S, lift: WardLift = .mid, inset: Bool = false, flat: Bool = false, fill: Color = .wardSurface,
         control: Bool = false) {
        self.shape = shape
        self.lift = lift
        self.inset = inset
        self.flat = flat
        self.fill = AnyShapeStyle(fill)
        self.fillColor = fill
        self.control = control
    }

    /// Any fill: drawn live, since the images cover colours only.
    init(shape: S, lift: WardLift = .mid, inset: Bool = false, flat: Bool = false, fill: AnyShapeStyle,
         control: Bool = false) {
        self.shape = shape
        self.lift = lift
        self.inset = inset
        self.flat = flat
        self.fill = fill
        self.fillColor = nil
        self.control = control
    }

    var body: some View {
        let dark: Bool = scheme == .dark
        let strong: Bool = contrast == .increased
        let spec: WardReliefSpec = inset ? WardRelief.inset(lift, dark: dark, highContrast: strong, control: control)
                                         : WardRelief.raised(lift, dark: dark, highContrast: strong, control: control)
        let live = WardReliefDrawing(shape: shape, lift: lift, inset: inset, flat: flat, fill: fill, control: control,
                                     dark: dark, strong: strong, unlit: unlit)
        // lit: it has lights to draw, and draws them
        let lit: Bool = !(flat || (unlit && !spec.inner)) && (spec.highlight.lit || spec.shade.lit)
        if lit, let fillColor, let kind = WardFaceShape(shape) {
            WardLitFace(kind: kind, look: inset ? .inset : .raised, lift: lift, control: control,
                        dark: dark, strong: strong, fill: fillColor, reach: WardLightSlice.reach(spec),
                        inner: spec.inner, live: live) { outline, dark in
                AnyView(WardReliefDrawing(shape: outline, lift: lift, inset: inset, flat: flat, fill: fill,
                                          control: control, dark: dark, strong: strong, unlit: unlit))
            }
        } else {
            live
        }
    }
}

/// A raised or inset face's drawing: the one drawing code, run live or into
/// an image (WardLitFace).
private struct WardReliefDrawing<S: InsettableShape>: View {
    let shape: S
    let lift: WardLift
    let inset: Bool
    let flat: Bool
    let fill: AnyShapeStyle
    let control: Bool
    let dark: Bool
    let strong: Bool
    let unlit: Bool

    var body: some View {
        let spec: WardReliefSpec = inset ? WardRelief.inset(lift, dark: dark, highContrast: strong, control: control)
                                         : WardRelief.raised(lift, dark: dark, highContrast: strong, control: control)
        ZStack {
            if flat || (unlit && !spec.inner) {
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
                shape.strokeBorder(Color.wardEdgeInk.opacity(spec.edgeAlpha), lineWidth: 1)
            }
        }
        .compositingGroup()
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

/// Where a page moves the top of the paper's opening down to, in window
/// points; nil keeps it at the frame. The home page sets it to just under
/// its header (HomeMasthead), so the grid runs on from the window's top and
/// the opening starts there with the frame's own corners.
@MainActor
@Observable
final class WardPaperTop {
    static let shared = WardPaperTop()
    var y: CGFloat?
}

/// Still ECG paper around the screen; content scrolls beneath the open panel.
/// With the opening moved down (WardPaperTop), the paper fills its top
/// corners as well; the paper above it is the page's own band, under the
/// content. The outer opening has no ink outline; controls keep theirs.
struct WardPaperFrame: View {
    var body: some View {
        // One sheet from the first full warm-up frame through home at rest.
        // Warming a separate Canvas left the animated mask unrendered until
        // the reveal. Keeping this sheet also avoids swapping renderers when
        // the opening ends. Its picture and paths change only with geometry
        // or appearance; the hand-off changes only the mask's transform.
        WardPaperCutStage()
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// What the opening's hand-off asks of the paper at this frame.
struct WardPaperCut: Equatable {
    /// The opening's pose once it has arrived (scale about its middle, and
    /// how far below its place); (1, 0) while warming and at rest, nil before
    /// the reveal, when the paper runs whole over it as on the launch screen.
    var scale: CGFloat?
    var drop: CGFloat = 0
    /// The top of the page's opening (WardPaperTop).
    var top: CGFloat?
    var dark: Bool
    var highContrast: Bool

    /// The paper's opening, as a path in the window.
    static func hole(_ p: WardPaperPanel) -> Path {
        RoundedRectangle(cornerRadius: CGFloat(p.radius), style: .continuous)
            .path(in: CGRect(x: p.x, y: p.y, width: p.width, height: p.height))
    }
}

/// Reads the opening's frame from LaunchStage, for the sheet.
private struct WardPaperCutStage: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let stage = LaunchStage.shared
        // Infinity is the full, masked home in BOTH warm-up and rest. Do not
        // hide this layer during warm-up: assigning contents alone does not
        // exercise the reveal's mask and image composition.
        let pose = stage.openingPose()
        #if canImport(UIKit)
        WardPaperCutSheet(cut: WardPaperCut(scale: pose?.scale, drop: pose?.drop ?? 0,
                                            top: WardPaperTop.shared.y, dark: scheme == .dark,
                                            highContrast: contrast == .increased))
        #endif
    }
}

#if canImport(UIKit)
/// Home's paper in Core Animation, including warm-up and rest: the picture
/// covers all but the page's own band, with the opening cut out by a mask.
/// Each animation frame poses that mask without drawing another picture.
private struct WardPaperCutSheet: UIViewRepresentable {
    var cut: WardPaperCut

    func makeUIView(context: Context) -> WardPaperCutView { WardPaperCutView() }

    func updateUIView(_ view: WardPaperCutView, context: Context) {
        view.cut = cut
    }
}

final class WardPaperCutView: UIView {
    var cut: WardPaperCut? {
        didSet { if cut != oldValue { apply() } }
    }

    private let root = CALayer()         // the same sheet throughout warm-up, reveal and rest
    private let sheet = CALayer()        // the paper: holds the picture, masked by the band
    private let band = CAShapeLayer()    // all of the window but the page's own band
    private let cutHolder = CALayer()    // masked by the posed opening
    private let hole = CAShapeLayer()    // everything but the opening, posed
    /// What the sheet was last built for.
    private var built: (size: CGSize, top: CGFloat?, dark: Bool, highContrast: Bool)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sheet.mask = band
        cutHolder.addSublayer(sheet)
        root.addSublayer(cutHolder)
        // The mask is posed about the opening's middle; its path is drawn
        // around that position, at no size.
        hole.fillRule = .evenOdd
        hole.bounds = .zero
        layer.addSublayer(root)
        CATransaction.commit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
    }

    private func apply() {
        guard let cut else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard bounds.width > 0, bounds.height > 0 else { return }
        let w = Double(bounds.width), h = Double(bounds.height)
        guard let panel = WardPaper.panel(width: w, height: h) else { return }
        let moved: WardPaperPanel? = cut.top.flatMap { WardPaper.panel(width: w, height: h, top: Double($0)) }
            .flatMap { $0.y > panel.y ? $0 : nil }
        let opening = moved ?? panel
        if built.map({ $0.size != bounds.size || $0.top != cut.top || $0.dark != cut.dark
            || $0.highContrast != cut.highContrast }) ?? true {
            build(panel: panel, moved: moved, opening: opening, cut: cut)
        }
        // the posed opening: scaled about its middle, dropped below its place
        guard let scale = cut.scale else {
            cutHolder.mask = nil
            return
        }
        let mid = CGPoint(x: opening.x + opening.width / 2, y: opening.y + opening.height / 2)
        hole.position = CGPoint(x: mid.x, y: mid.y + cut.drop)
        hole.transform = CATransform3DMakeScale(scale, scale, 1)
        if cutHolder.mask !== hole { cutHolder.mask = hole }
    }

    /// The sheet's picture, band and opening, for this window and ink.
    private func build(panel: WardPaperPanel, moved: WardPaperPanel?, opening: WardPaperPanel, cut: WardPaperCut) {
        let size = bounds.size
        built = (size, cut.top, cut.dark, cut.highContrast)
        let ink = WardPaper.ink(dark: cut.dark, highContrast: cut.highContrast)
        let rect = CGRect(origin: .zero, size: size)
        root.frame = rect
        cutHolder.frame = rect
        // the picture from the window's top left at its own size, as the
        // rest drawing places it; the lines drawn once where it falls short
        let grid = ink.fine > 0 || ink.bold > 0
        let traits = traitCollection.modifyingTraits { $0.userInterfaceStyle = cut.dark ? .dark : .light }
        let picture = grid ? UIImage(named: "LaunchPaper", in: nil, compatibleWith: traits) : nil
        if let picture, picture.size.width >= size.width, picture.size.height >= size.height {
            sheet.frame = CGRect(origin: .zero, size: picture.size)
            sheet.contents = picture.cgImage
            sheet.contentsScale = picture.scale
            sheet.backgroundColor = nil
        } else if grid {
            sheet.frame = rect
            sheet.contents = Self.drawnPaper(size: size, ink: ink, dark: cut.dark,
                                             scale: traitCollection.displayScale)
            sheet.contentsScale = max(1, traitCollection.displayScale)
            sheet.backgroundColor = nil
        } else {
            sheet.frame = rect
            sheet.contents = nil
            let (r, g, b) = WardPalette.rgb(WardPalette.hex(.background, dark: cut.dark))
            sheet.backgroundColor = UIColor(red: r, green: g, blue: b, alpha: 1).cgColor
        }
        // all but the page's own band above the opening
        var paper = Path(rect)
        if let moved {
            paper = paper.subtracting(WardPaperCut.hole(panel).intersection(
                Path(CGRect(x: 0, y: 0, width: size.width, height: moved.y))))
        }
        band.frame = CGRect(origin: .zero, size: sheet.frame.size)
        band.path = paper.cgPath
        // the opening around its middle, so posing it is a transform; around
        // it, a window's width and height more than the window on every
        // side, which still covers it at the smallest pose (half size)
        let mid = CGPoint(x: opening.x + opening.width / 2, y: opening.y + opening.height / 2)
        let local = CGAffineTransform(translationX: -mid.x, y: -mid.y)
        let opened = WardPaperCut.hole(opening).applying(local)
        var around = Path(rect.insetBy(dx: -size.width, dy: -size.height).applying(local))
        around.addPath(opened)
        hole.path = around.cgPath
    }

    /// The paper's lines, drawn once, for a window the picture does not
    /// cover.
    @MainActor
    private static func drawnPaper(size: CGSize, ink: WardPaperInk, dark: Bool, scale: CGFloat) -> CGImage? {
        let (r, g, b) = WardPalette.rgb(ink.hex)
        let color = Color(red: r, green: g, blue: b)
        let renderer = ImageRenderer(content: Canvas { context, size in
            WardPaperInk.drawPaper(in: &context, size: size, from: .zero, ink: ink, color: color)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = max(1, scale)
        return renderer.cgImage
    }
}
#endif

extension WardPaperInk {
    /// The base, then the frame's grid over `size`, for a canvas whose top
    /// left corner sits at `origin` in the window, so its lines fall on the
    /// frame's. tools/make_launch_paper.py draws the same paper, line for
    /// line, for the launch screen (LaunchPaper): a change here goes there.
    static func drawPaper(in context: inout GraphicsContext, size: CGSize, from origin: CGPoint,
                          ink: WardPaperInk, color: Color) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.wardBackground))
        guard ink.fine > 0 || ink.bold > 0 else { return }
        func drawLine(_ line: Path, bold: Bool) {
            if ink.fine > 0 {
                context.fill(line, with: .color(color.opacity(ink.fine)))
            }
            if bold && ink.bold > 0 {
                context.fill(line, with: .color(color.opacity(ink.bold)))
            }
        }
        // the down lines, then the across ones over them
        for line in WardPaper.lines(Double(size.width), from: Double(origin.x)) {
            drawLine(Path(CGRect(x: line.at, y: 0, width: WardPaper.line, height: size.height)), bold: line.bold)
        }
        for line in WardPaper.lines(Double(size.height), from: Double(origin.y)) {
            drawLine(Path(CGRect(x: 0, y: line.at, width: size.width, height: WardPaper.line)), bold: line.bold)
        }
    }
}

/// ECG paper in a band from the top of the window down to `bottom` (window
/// points), its lines on the frame's grid and in its ink, ending in a line
/// in the frame's edge ink: the home page's header stands on it (the owner,
/// 9 Oct: "the grid from upwards till under the stethoscore word"). Below
/// `bottom` it draws nothing. Under Increase Contrast the ink has no grid,
/// so the band is the plain base with its edge.
struct WardPaperBand: View {
    var bottom: CGFloat
    var grid = true
    var edge = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var origin: CGPoint = .zero

    var body: some View {
        Group {
            Canvas { context, size in
                let height: CGFloat = min(size.height, bottom - origin.y)
                guard height > 0 else { return }
                var ink = WardPaper.ink(dark: scheme == .dark, highContrast: contrast == .increased)
                if !grid { ink.fine = 0; ink.bold = 0 }
                let (r, g, b) = WardPalette.rgb(ink.hex)
                let color = Color(red: r, green: g, blue: b)
                var band = context
                band.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: height)))
                WardPaperInk.drawPaper(in: &band, size: CGSize(width: size.width, height: height),
                                       from: origin, ink: ink, color: color)
                if edge {
                    let w = CGFloat(WardPaper.edgeWidth)
                    context.fill(Path(CGRect(x: 0, y: height - w, width: size.width, height: w)),
                              with: .color(color.opacity(ink.edge)))
                }
            }
        }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The bar area of a page, solid: from the top of the window down to the
/// page's safe area, in the base colour, so what scrolls up passes under it
/// and is cut there instead of fading under iOS's soft scroll edge (the
/// owner, 9 Oct: no fading). The bars' own buttons and fields stay on top.
struct WardMasthead: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectHidden(true, for: .top)
            .overlay(alignment: .top) {
                // nothing tall at the safe area's top, and from there up to
                // the window's top the base
                Color.clear
                    .frame(height: 0)
                    .background(alignment: .bottom) {
                        Color.wardBackground.ignoresSafeArea(edges: .top)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
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

/// A List or Form row as a soft tile raised low off the base, with a
/// control's ink edge: a row is tapped. A cell clips what it draws, so the
/// tile keeps clear of the cell's edges by more than its lights reach and no
/// cut shows; between rows that clearance is the gap soft tiles stand apart
/// by. Pressed in, it marks the chosen row.
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
                       lift: .low, inset: inset, control: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            // with its row, at the opening's hand-off (LaunchStage)
            .launchEntrance(inOpening: true)
    }
}

/// The line where what scrolls is cut by a solid bar: the paper frame's edge
/// ink across the panel, out to the frame's line on both sides, as the
/// home's grid band ends. Without it a card cut there read as two things
/// overlapping (the owner, 9 Oct: "some ui elements overlap").
struct WardScrollEdgeLine: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = WardPaper.ink(dark: scheme == .dark, highContrast: contrast == .increased)
        let (r, g, b) = WardPalette.rgb(ink.hex)
        Rectangle()
            .fill(Color(red: r, green: g, blue: b).opacity(ink.edge))
            .frame(height: CGFloat(WardPaper.edgeWidth))
            // the page sits sideInset in from the window (SkyRoot); the
            // frame covers what runs on past its line
            .padding(.horizontal, -WardPaper.sideInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The scroll edge's line along the top of what scrolls, once any of it has
/// gone under what stands above it (the bar area, a study header); at rest
/// at its top, no line.
private struct WardScrollTopEdge: ViewModifier {
    @State private var scrolled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0.5 } action: { _, now in
                scrolled = now
            }
            .overlay(alignment: .top) {
                if scrolled { WardScrollEdgeLine().transition(.identity) }
            }
    }
}

extension View {
    /// A line where what scrolls is cut at the top of its frame, once it
    /// has scrolled (WardScrollEdgeLine). On the scroll view, or on what
    /// holds it with nothing above it.
    func wardScrollTopEdge() -> some View {
        modifier(WardScrollTopEdge())
    }

    /// A solid strip under a bar, with the scroll edge's line along its top:
    /// it hides and blocks the rows beneath, and nothing fades. The room
    /// above the bar is for its lights (a raised `.high` slab's reach about
    /// 20 pt; a flat one, or a row of buttons, casts nothing up). The line is
    /// drawn over the bar, since a flat slab that starts at the strip's top
    /// would hide it along the slab's width. Hidden, it takes no room; shown
    /// or hidden, the bar keeps its identity, so a fold never cross-fades it.
    func wardBarBase(room: CGFloat = 24, shown: Bool = true) -> some View {
        self.padding(.top, shown ? room : 0)
            .background {
                if shown {
                    Color.wardBackground
                        .ignoresSafeArea(edges: [.horizontal, .bottom])
                        .transition(.identity)
                }
            }
            .overlay(alignment: .top) {
                if shown { WardScrollEdgeLine().transition(.identity) }
            }
    }

    func wardCard(padding: CGFloat = WardSpace.gutter, lift: WardLift = .mid) -> some View {
        modifier(WardCardStyle(padding: padding, lift: lift))
    }

    /// Containers stand off the base unless they hold a Ward control; then
    /// only the control is raised and the container keeps its fill (and its
    /// edge). `control` for a control's own body (a segmented control's
    /// capsule): it takes the control's ink edge.
    func wardRaised<S: InsettableShape>(in shape: S, lift: WardLift = .mid, fill: Color = .wardSurface,
                                        control: Bool = false) -> some View {
        backgroundPreferenceValue(WardHoldsControl.self) { holdsControl in
            WardReliefFace(shape: shape, lift: lift, flat: holdsControl, fill: fill, control: control)
        }
    }

    /// Pressed into the base: fields, tracks, wells and whatever is chosen.
    /// `control` for a field or a switch's track: it takes the ink edge.
    func wardInset<S: InsettableShape>(in shape: S, lift: WardLift = .low, fill: Color = .wardSurface,
                                       control: Bool = false) -> some View {
        background { WardReliefFace(shape: shape, lift: lift, inset: true, fill: fill, control: control) }
    }

    /// Raised at rest; glides into a hollow at the same lift while held or
    /// chosen. A control, with its ink edge, unless `control` is false (an
    /// icon tile that only shows a choice).
    func wardRelief<S: InsettableShape>(in shape: S, lift: WardLift = .low, pressed: Bool,
                                        control: Bool = true) -> some View {
        background { WardPressFace(shape: shape, lift: lift, pressed: pressed, control: control) }
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

    /// A page's bar area solid in the base colour, in place of iOS 26's soft
    /// top scroll edge, which blurs and fades what passes under the bars
    /// (not `.hard`: it takes no colour and flashes dark under a forced
    /// colour scheme).
    func wardMasthead() -> some View {
        modifier(WardMasthead())
    }

    /// A screen in the soft UI: the matte base under it, a solid bar area
    /// and its controls.
    func wardScreen() -> some View {
        self
            .wardMasthead()
            .background(WardBackground())
            .wardControls()
    }

    /// A Form or List in the soft UI: its own grey ground hidden for the
    /// base, a solid bar area with the scroll edge's line under it once the
    /// rows have moved, rows tall enough for their tiles, and the controls.
    func wardForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .wardScrollTopEdge()
            .wardMasthead()
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
