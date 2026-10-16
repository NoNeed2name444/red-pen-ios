#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
struct WardPressFace<S: InsettableShape>: View {
    let shape: S
    var lift: WardLift = .mid
    var pressed: Bool
    var fill = AnyShapeStyle(Color.wardSurface)
    var control = true
    /// Lies flat, with no rim: a face that must never read as lifted (a
    /// wrong pick, whose face is lighter than the cards at night).
    var flat = false
    /// The ring's ink, where it is not the section's (a wrong pick's, in
    /// the faded ink).
    var edge: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.wardUnlit) private var unlit
    @Environment(\.wardHeld) private var held

    var body: some View {
        // how far to dark the shift is, this frame (WardLookStore)
        let night: Double = WardLookStore.shared.glide.night(dark: scheme == .dark, held: held)
        WardPressRelief(shape: shape, lift: lift, depth: pressed ? 1 : 0, fill: fill,
                        night: night, strong: contrast == .increased, control: control,
                        unlit: unlit, flat: flat, edge: edge)
            .animation(reduceMotion ? nil : .wardShade(down: pressed), value: pressed)
            .preference(key: WardHoldsControl.self, value: true)
    }
}

extension WardPressFace {
    init(shape: S, lift: WardLift = .mid, pressed: Bool, fill: Color, control: Bool = true,
         flat: Bool = false, edge: Color? = nil) {
        self.init(shape: shape, lift: lift, pressed: pressed, fill: AnyShapeStyle(fill), control: control,
                  flat: flat, edge: edge)
    }
}

private struct WardPressRelief<S: InsettableShape>: View, Animatable {
    let shape: S
    let lift: WardLift
    var depth: Double
    let fill: AnyShapeStyle
    let night: Double
    let strong: Bool
    let control: Bool
    var unlit = false
    var flat = false
    var edge: Color?

    var animatableData: Double {
        get { depth }
        set { depth = newValue }
    }

    var body: some View {
        let spec = WardPress.spec(lift, depth: depth, night: night, highContrast: strong, control: control)
        // a button keeps its small rim even where the page is unlit: the
        // one soft light the app allows (WardRelief.rim)
        let lit: Bool = (control || !unlit) && !flat
        ZStack {
            ZStack {
                if lit && (spec.outerShade.lit || spec.outerHighlight.lit) {
                    if spec.outerHighlight.lit {
                        shape.fill(fill.shadow(.ward(spec.outerHighlight, inner: false)))
                    }
                    shape.fill(fill.shadow(.ward(spec.outerShade, inner: false)))
                } else {
                    shape.fill(fill)
                }
                if spec.innerShade.lit || spec.innerHighlight.lit {
                    shape.fill(innerFill(spec))
                }
            }
            .compositingGroup()
            .blur(radius: unlit || spec.blur == 0 ? 0 : spec.blur)
            if spec.edgeAlpha > 0 {
                shape.strokeBorder((edge ?? Color.wardEdgeInk).opacity(spec.edgeAlpha), lineWidth: 1)
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
struct WardReliefFace<S: InsettableShape>: View {
    let shape: S
    var lift: WardLift = .mid
    var inset = false
    var flat = false
    var fill = AnyShapeStyle(Color.wardSurface)
    var control = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.wardUnlit) private var unlit
    @Environment(\.wardHeld) private var held

    var body: some View {
        // how far to dark the shift is, this frame (WardLookStore)
        let night: Double = WardLookStore.shared.glide.night(dark: scheme == .dark, held: held)
        let strong: Bool = contrast == .increased
        // a raised control (a row to tap, a segmented control) stands on its
        // small rim, as a button does, lit or not; a card keeps its relief
        let rim: Bool = control && !inset && !flat
        let spec: WardReliefSpec = inset ? WardRelief.inset(lift, night: night, highContrast: strong, control: control)
                                 : rim ? WardRelief.rim(lift, night: night, highContrast: strong)
                                       : WardRelief.raised(lift, night: night, highContrast: strong, control: control)
        ZStack {
            if flat || (unlit && !spec.inner && !rim) {
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

extension WardReliefFace {
    init(shape: S, lift: WardLift = .mid, inset: Bool = false, flat: Bool = false, fill: Color,
         control: Bool = false) {
        self.init(shape: shape, lift: lift, inset: inset, flat: flat, fill: AnyShapeStyle(fill), control: control)
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

/// Each window owns this store. A sheet inherits it, but its edges do not
/// match the root page, so it never borrows the window's frame.
@MainActor
@Observable
final class WardEdgeStore {
    struct Entry: Identifiable {
        let id: UUID
        let host: CGRect
        let page: CGRect
        let panel: WardPaperPanel
        let sides: WardIsland.Sides
        let join: WardEdgeJoin

        var local: WardEdgeJoin {
            WardIsland.local(join, origin: SIMD2(Double(host.minX), Double(host.minY)))
        }
    }

    private struct Request: Equatable {
        var frame: CGRect
        var shown: Bool
    }

    private(set) var entries: [UUID: Entry] = [:]
    private(set) var window: CGRect = .zero
    private(set) var page: CGRect = .zero
    @ObservationIgnored private var requests: [UUID: Request] = [:]
    @ObservationIgnored private var panel: WardPaperPanel?
    @ObservationIgnored private var outline: [SIMD2<Double>] = []
    @ObservationIgnored private var covered = false

    func setPage(_ frame: CGRect, covered: Bool) {
        guard page != frame || self.covered != covered else { return }
        page = frame
        self.covered = covered
        refresh()
    }

    func setWindow(_ frame: CGRect, pad: Bool, top: CGFloat?) {
        let next = WardPaper.panel(width: frame.width, height: frame.height,
                                   top: Double(top ?? 0) - frame.minY, pad: pad)
        guard window != frame || panel != next else { return }
        window = frame
        panel = next
        // The solver sees the very path the frame strokes, including the
        // system's continuous corners. Flattening is only for the solver.
        outline = next.map { WardPanelPath.flatten(WardPanelPath.hole($0)) } ?? []
        refresh()
    }

    func update(_ id: UUID, frame: CGRect, shown: Bool, transaction: Transaction) {
        let request = Request(frame: frame, shown: shown)
        guard requests[id] != request else { return }
        requests[id] = request
        var t = transaction
        if !shown || entries[id] == nil { t.animation = nil; t.disablesAnimations = true }
        withTransaction(t) { resolve(id, request) }
    }

    func remove(_ id: UUID) {
        requests[id] = nil
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { entries[id] = nil }
    }

    private func refresh() {
        for (id, request) in requests { resolve(id, request) }
    }

    private func resolve(_ id: UUID, _ request: Request) {
        let sides = WardIsland.sides(host: request.frame, page: page, covered: covered)
        guard request.shown, sides.any, let panel else { entries[id] = nil; return }
        let host = request.frame.offsetBy(dx: -window.minX, dy: -window.minY)
        let page = page.offsetBy(dx: -window.minX, dy: -window.minY)
        // No geometry is solved by a Canvas or an animation's draw callback.
        let previous = entries[id]
        let unchanged = previous?.panel == panel && previous?.sides == sides &&
            previous?.host.minY == host.minY && previous?.host.minX == host.minX && previous?.host.maxX == host.maxX
        let solved = unchanged ? previous?.join : WardEdge.join(outline: outline,
            y: host.minY + WardPaper.edgeWidth / 2, radius: panel.radius, left: sides.left, right: sides.right)
        guard let join = solved else {
            entries[id] = nil
            return
        }
        entries[id] = Entry(id: id, host: host, page: page, panel: panel, sides: sides, join: join)
    }
}

private enum WardEdgeStoreKey: EnvironmentKey {
    static let defaultValue: WardEdgeStore? = nil
}
private enum WardIslandEntryKey: EnvironmentKey {
    static let defaultValue: WardEdgeStore.Entry? = nil
}
private enum WardFoldInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
extension EnvironmentValues {
    var wardEdgeStore: WardEdgeStore? {
        get { self[WardEdgeStoreKey.self] }
        set { self[WardEdgeStoreKey.self] = newValue }
    }
    var wardIslandEntry: WardEdgeStore.Entry? {
        get { self[WardIslandEntryKey.self] }
        set { self[WardIslandEntryKey.self] = newValue }
    }
    var wardFoldInset: CGFloat {
        get { self[WardFoldInsetKey.self] }
        set { self[WardFoldInsetKey.self] = newValue }
    }
}

private enum WardPanelPath {
    @MainActor
    static var pad: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    static func hole(_ panel: WardPaperPanel) -> Path {
        RoundedRectangle(cornerRadius: panel.radius, style: .continuous)
            .path(in: CGRect(x: panel.x, y: panel.y, width: panel.width, height: panel.height))
    }

    static func flatten(_ path: Path) -> [SIMD2<Double>] {
        var points: [SIMD2<Double>] = [], current = SIMD2<Double>.zero, first = current
        func point(_ p: CGPoint) -> SIMD2<Double> { SIMD2(Double(p.x), Double(p.y)) }
        path.cgPath.applyWithBlock { pointer in
            let e = pointer.pointee
            switch e.type {
            case .moveToPoint:
                current = point(e.points[0]); first = current; points.append(current)
            case .addLineToPoint:
                current = point(e.points[0]); points.append(current)
            case .addQuadCurveToPoint:
                let start = current, control = point(e.points[0]), end = point(e.points[1])
                for i in 1...64 {
                    let t = Double(i) / 64, u = 1 - t
                    points.append(u * u * start + 2 * u * t * control + t * t * end)
                }
                current = end
            case .addCurveToPoint:
                let start = current, a = point(e.points[0]), b = point(e.points[1]), end = point(e.points[2])
                for i in 1...64 {
                    let t = Double(i) / 64, u = 1 - t
                    points.append(u * u * u * start + 3 * u * u * t * a + 3 * u * t * t * b + t * t * t * end)
                }
                current = end
            case .closeSubpath: points.append(first); current = first
            @unknown default: break
            }
        }
        return points
    }
}

/// All thirteen coordinates interpolate together. Both canvases and the
/// strip mask receive the same solved endpoints and the same transaction.
private struct WardEdgeVector: VectorArithmetic {
    var values: [Double]
    static var zero: Self { Self(values: Array(repeating: 0, count: 13)) }
    static func + (lhs: Self, rhs: Self) -> Self { Self(values: zip(lhs.values, rhs.values).map(+)) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(values: zip(lhs.values, rhs.values).map(-)) }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

private struct WardIslandPath: Shape {
    var data: WardEdgeVector
    var left: Bool
    var right: Bool
    var filled = false

    init(join: WardEdgeJoin, from: Double, to: Double, filled: Bool = false) {
        func numbers(_ c: WardEdgeCorner?) -> [Double] {
            guard let c else { return [0, 0, 0, 0, 0] }
            return [c.center.x, c.center.y, c.radius, c.join.x, c.join.y]
        }
        data = WardEdgeVector(values: [join.y, join.fromX ?? from, join.toX ?? to] + numbers(join.left) + numbers(join.right))
        left = join.left != nil; right = join.right != nil; self.filled = filled
    }

    var animatableData: WardEdgeVector {
        get { data }
        set { data = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let v = data.values
        var p = Path()
        let start = CGPoint(x: left ? v[6] : v[1], y: left ? v[7] : v[0])
        p.move(to: start)
        if left {
            p.addArc(center: CGPoint(x: v[3], y: v[4]), radius: v[5],
                     startAngle: .radians(atan2(v[7] - v[4], v[6] - v[3])),
                     endAngle: .radians(3 * .pi / 2), clockwise: false)
        }
        p.addLine(to: CGPoint(x: v[2], y: v[0]))
        if right {
            p.addArc(center: CGPoint(x: v[8], y: v[9]), radius: v[10],
                     startAngle: .radians(-.pi / 2),
                     endAngle: .radians(atan2(v[12] - v[9], v[11] - v[8])), clockwise: false)
        }
        if filled {
            p.addLine(to: CGPoint(x: right ? v[11] : v[2], y: rect.maxY))
            p.addLine(to: CGPoint(x: start.x, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

/// Only the four-point clearance, never over the page or the frame stroke.
/// The enclosing group applies the edge opacity once to the resulting ink.
private struct WardClearanceInk: View, Animatable {
    var shape: WardIslandPath
    let entry: WardEdgeStore.Entry
    let color: Color
    var animatableData: WardEdgeVector {
        get { shape.data }
        set { shape.data = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            var bands = Path()
            for band in WardIsland.clearance(panel: entry.panel, page: entry.page, sides: entry.sides) {
                bands.addRect(band)
            }
            context.clip(to: bands, style: FillStyle(antialiased: false))
            var outsideStroke = Path(rect)
            outsideStroke.addPath(WardPanelPath.hole(entry.panel).strokedPath(StrokeStyle(lineWidth: WardPaper.edgeWidth)))
            context.clip(to: outsideStroke, style: FillStyle(eoFill: true, antialiased: false))
            context.stroke(shape.path(in: rect), with: .color(color), lineWidth: WardPaper.edgeWidth)
        }
        .transition(.identity)
    }
}

/// Still ECG paper around the screen; content scrolls beneath the open panel.
/// With the opening moved down (WardPaperTop), the paper fills its top
/// corners as well, and its edge is drawn there instead of at the frame's
/// top; the paper above it is the page's own band, under the content.
struct WardPaperFrame: View {
    let edges: WardEdgeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.wardHeld) private var held
    /// read so the end of every shift redraws it (WardRestLookTrait)
    @Environment(\.wardRestLook) private var restLook
    @State private var window: CGRect = .zero

    var body: some View {
        let top = WardPaperTop.shared.y
        // the section's ink and the base, this frame of the shift
        let ink = WardPaper.ink(look: .drawn(rest: restLook, live: WardLookStore.shared.glide), dark: scheme == .dark, held: held,
                                highContrast: contrast == .increased)
        let (r, g, b) = WardPalette.rgb(ink.hex)
        let color = Color(red: r, green: g, blue: b)
        let base: Color = .wardBackground
        GeometryReader { geometry in
            let size = geometry.size
            if let panel = WardPaper.panel(width: size.width, height: size.height, pad: WardPanelPath.pad),
               let moved = WardPaper.panel(width: size.width, height: size.height,
                                          top: Double(top ?? 0) - window.minY, pad: WardPanelPath.pad) {
                let frameHole = WardPanelPath.hole(panel)
                let hole = WardPanelPath.hole(moved)
                ZStack {
                    Canvas { context, _ in
                        var frame = Path(CGRect(origin: .zero, size: size))
                        frame.addPath(frameHole)
                        context.drawLayer { layer in
                            layer.clip(to: frame, style: FillStyle(eoFill: true))
                            WardPaperInk.drawPaper(in: &layer, size: size, from: .zero, ink: ink, color: color, base: base)
                        }
                        if moved.y > panel.y {
                            let strip = Path(CGRect(x: moved.x, y: moved.y, width: moved.width, height: moved.radius))
                            var corners = strip
                            corners.addPath(hole)
                            context.drawLayer { layer in
                                layer.clip(to: strip)
                                layer.clip(to: corners, style: FillStyle(eoFill: true))
                                WardPaperInk.drawPaper(in: &layer, size: size, from: .zero, ink: ink, color: color, base: base)
                            }
                        }
                    }
                    ZStack {
                        Canvas { context, _ in
                            context.stroke(hole, with: .color(color), lineWidth: WardPaper.edgeWidth)
                        }
                        ForEach(edges.entries.values.sorted { $0.id.uuidString < $1.id.uuidString }) { entry in
                            WardClearanceInk(shape: WardIslandPath(join: entry.join,
                                                                  from: entry.host.minX, to: entry.host.maxX),
                                             entry: entry, color: color)
                        }
                    }
                    .compositingGroup()
                    .opacity(ink.edge)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    window = frame
                    edges.setWindow(frame, pad: WardPanelPath.pad, top: top)
                }
                .onChange(of: top) { _, now in edges.setWindow(window, pad: WardPanelPath.pad, top: now) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension WardPaperInk {
    /// The base, then the frame's grid over `size`, for a canvas whose top
    /// left corner sits at `origin` in the window, so its lines fall on the
    /// frame's.
    static func drawPaper(in context: inout GraphicsContext, size: CGSize, from origin: CGPoint,
                          ink: WardPaperInk, color: Color, base: Color) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
        guard ink.fine > 0 || ink.bold > 0 else { return }
        func drawLine(_ line: Path, bold: Bool) {
            if ink.fine > 0 {
                context.fill(line, with: .color(color.opacity(ink.fine)))
            }
            if bold && ink.bold > 0 {
                context.fill(line, with: .color(color.opacity(ink.bold)))
            }
        }
        for line in WardPaper.lines(Double(size.width), from: Double(origin.x)) {
            drawLine(Path(CGRect(x: line.at, y: 0, width: WardPaper.line, height: size.height)),
                     bold: line.bold)
        }
        for line in WardPaper.lines(Double(size.height), from: Double(origin.y)) {
            drawLine(Path(CGRect(x: 0, y: line.at, width: size.width, height: WardPaper.line)),
                     bold: line.bold)
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
    @Environment(\.wardHeld) private var held
    /// read so the end of every shift redraws it (WardRestLookTrait)
    @Environment(\.wardRestLook) private var restLook
    @State private var origin: CGPoint = .zero

    var body: some View {
        // the section's ink and the base, this frame of the shift
        let paper = WardPaper.ink(look: .drawn(rest: restLook, live: WardLookStore.shared.glide), dark: scheme == .dark, held: held,
                                  highContrast: contrast == .increased)
        let ink = WardPaperInk(hex: paper.hex, fine: grid ? paper.fine : 0, bold: grid ? paper.bold : 0, edge: paper.edge)
        let base: Color = .wardBackground
        Canvas { context, size in
            let height: CGFloat = min(size.height, bottom - origin.y)
            guard height > 0 else { return }
            let (r, g, b) = WardPalette.rgb(ink.hex)
            let color = Color(red: r, green: g, blue: b)
            var band = context
            band.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: height)))
            WardPaperInk.drawPaper(in: &band, size: CGSize(width: size.width, height: height),
                                   from: origin, ink: ink, color: color, base: base)
            if edge {
                let w = CGFloat(WardPaper.edgeWidth)
                context.fill(Path(CGRect(x: 0, y: height - w, width: size.width, height: w)),
                             with: .color(color.opacity(ink.edge)))
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
            .wardHeld(.dark)
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

    /// A tiled row's insets: the tile's clearance (8 on every side) plus
    /// the room its content keeps inside it (8 above and below, 12 at the
    /// sides), all on the scale (WardScale).
    static let insets = EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
    /// A row that is one big raised button: its face where the tiles' are,
    /// with room for its rim (WardRelief.rimReach, under 8), so the cell
    /// never cuts it.
    static let buttonInsets = EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8)
    /// A row that is a card of its own, raised as low as the tiles: its
    /// edges where the tiles' are, its lights clear of the cell's.
    static let cardInsets = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

    var body: some View {
        WardReliefFace(shape: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous),
                       lift: .low, inset: inset, control: true)
            .padding(.horizontal, WardSpace.s)
            .padding(.vertical, WardSpace.s)
    }
}

/// A transaction is captured without publishing state during view updates.
/// Geometry callbacks forward it to the window's copy of the same curve.
private final class WardEdgeTransaction {
    var value = Transaction(animation: nil)
}

private struct WardEdgeHost: ViewModifier {
    let shown: Bool
    let strip: Bool
    @Environment(\.wardEdgeStore) private var store
    @State private var id = UUID()
    @State private var frame: CGRect = .zero
    @State private var clock = WardEdgeTransaction()

    func body(content: Content) -> some View {
        let entry = store?.entries[id]
        content
            .environment(\.wardIslandEntry, entry)
            .background(alignment: .top) {
                if strip && shown {
                    if let entry {
                        GeometryReader { geometry in
                            WardIslandPath(join: entry.local, from: -WardPaper.sideInset,
                                           to: entry.host.width + WardPaper.sideInset, filled: true)
                                .fill(Color.wardBackground)
                                .frame(height: max(geometry.size.height, entry.panel.y + entry.panel.height - entry.host.minY + WardPaper.frame))
                        }
                        .transition(.identity)
                    } else {
                        Color.wardBackground.ignoresSafeArea(edges: [.horizontal, .bottom]).transition(.identity)
                    }
                }
            }
            .overlay(alignment: .top) {
                if shown {
                    WardScrollEdgeLine(entry: entry, pockets: !strip).transition(.identity)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { now in
                frame = now
                store?.update(id, frame: now, shown: shown, transaction: clock.value)
            }
            .onChange(of: shown, initial: true) { _, now in
                store?.update(id, frame: frame, shown: now, transaction: clock.value)
            }
            .onDisappear { store?.remove(id) }
            .transaction { clock.value = $0 }
    }
}

/// One stroked path, including its true circular arcs, in the frame's ink.
/// The pockets under a header are the complement of the island's fill.
struct WardScrollEdgeLine: View {
    var entry: WardEdgeStore.Entry?
    var pockets = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.wardHeld) private var held
    /// read so the end of every shift redraws it (WardRestLookTrait)
    @Environment(\.wardRestLook) private var restLook

    var body: some View {
        let ink = WardPaper.ink(look: .drawn(rest: restLook, live: WardLookStore.shared.glide), dark: scheme == .dark, held: held,
                                highContrast: contrast == .increased)
        let (r, g, b) = WardPalette.rgb(ink.hex)
        let color = Color(red: r, green: g, blue: b).opacity(ink.edge)
        Group {
            if let entry {
                WardPageEdge(shape: WardIslandPath(join: WardIsland.local(entry.local, origin: SIMD2(-WardPaper.sideInset, 0)),
                                                   from: 0, to: entry.host.width + 2 * WardPaper.sideInset),
                             panel: entry.panel,
                             origin: CGPoint(x: entry.host.minX - WardPaper.sideInset, y: entry.host.minY),
                             pockets: pockets, color: color)
                    .frame(height: max(entry.local.left?.join.y ?? 0, entry.local.right?.join.y ?? 0) + WardPaper.edgeWidth)
                    .padding(.horizontal, -WardPaper.sideInset)
            } else {
                Rectangle().fill(color)
                    .frame(height: WardPaper.edgeWidth)
                    .padding(.horizontal, -WardPaper.sideInset)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WardPageEdge: View, Animatable {
    var shape: WardIslandPath
    let panel: WardPaperPanel
    var origin: CGPoint
    let pockets: Bool
    let color: Color
    var animatableData: AnimatablePair<WardEdgeVector, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shape.data, AnimatablePair(origin.x, origin.y)) }
        set {
            shape.data = newValue.first
            origin = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    var body: some View {
        let base = Color.wardBackground
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            if pockets {
                var island = shape
                island.filled = true
                var outside = Path(rect)
                outside.addPath(island.path(in: rect))
                context.drawLayer { layer in
                    layer.clip(to: Path(rect))
                    layer.clip(to: outside, style: FillStyle(eoFill: true))
                    layer.fill(Path(rect), with: .color(base))
                }
            }
            // A low deck can meet a bottom corner inside the page itself.
            // The frame owns its stroke there, just as it does in the gap.
            let hole = WardPanelPath.hole(panel).applying(CGAffineTransform(translationX: -origin.x, y: -origin.y))
            var outsideStroke = Path(rect)
            outsideStroke.addPath(hole.strokedPath(StrokeStyle(lineWidth: WardPaper.edgeWidth)))
            context.clip(to: outsideStroke, style: FillStyle(eoFill: true, antialiased: false))
            context.stroke(shape.path(in: rect), with: .color(color), lineWidth: WardPaper.edgeWidth)
        }
    }
}

private struct WardScrollTopEdge: ViewModifier {
    @State private var scrolled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0.5 } action: { _, now in
                var t = Transaction(animation: nil)
                t.disablesAnimations = true
                withTransaction(t) { scrolled = now }
            }
            .modifier(WardEdgeHost(shown: scrolled, strip: false))
    }
}

/// Circular top corners stay inside the island. The bottom keeps the
/// continuous 24-point corners of the original slab, including its relief.
private struct WardDeckShape: InsettableShape {
    var left: CGFloat
    var right: CGFloat
    var joined: Bool
    var insetAmount: CGFloat = 0
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(left, right) }
        set { left = newValue.first; right = newValue.second }
    }
    func inset(by amount: CGFloat) -> Self {
        var copy = self; copy.insetAmount += amount; return copy
    }
    func path(in rect: CGRect) -> Path {
        guard joined else {
            return RoundedRectangle(cornerRadius: WardRadius.bar, style: .continuous)
                .inset(by: insetAmount).path(in: rect)
        }
        let b = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let top = b.minY + WardPaper.edgeWidth / 2
        let l = max(0, min(left - insetAmount, b.width / 2))
        let r = max(0, min(right - insetAmount, b.width / 2))
        let bottom = max(0, min(WardRadius.bar - insetAmount, b.width / 3.05732966))
        var p = Path()
        p.move(to: CGPoint(x: b.minX, y: top + l))
        p.addArc(center: CGPoint(x: b.minX + l, y: top + l), radius: l,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: b.maxX - r, y: top))
        p.addArc(center: CGPoint(x: b.maxX - r, y: top + r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        p.addLine(to: CGPoint(x: b.maxX, y: b.maxY - 1.52866483 * bottom))
        // The same continuous bottom corners used by WardEdge's outline.
        for rightSide in [true, false] {
            let x = rightSide ? b.maxX : b.minX
            let sign: CGFloat = rightSide ? -1 : 1
            func q(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                CGPoint(x: x + sign * u * bottom, y: b.maxY - v * bottom)
            }
            if rightSide {
                p.addCurve(to: q(0.074911, 0.63149399), control1: q(0, 1.08849299), control2: q(0, 0.86840701))
                p.addCurve(to: q(0.63149399, 0.074911), control1: q(0.16905501, 0.37282401), control2: q(0.37282401, 0.16905501))
                p.addCurve(to: q(1.52866483, 0), control1: q(0.86840701, 0), control2: q(1.08849299, 0))
                p.addLine(to: CGPoint(x: b.minX + 1.52866483 * bottom, y: b.maxY))
            } else {
                p.addCurve(to: q(0.63149399, 0.074911), control1: q(1.08849299, 0), control2: q(0.86840701, 0))
                p.addCurve(to: q(0.074911, 0.63149399), control1: q(0.37282401, 0.16905501), control2: q(0.16905501, 0.37282401))
                p.addCurve(to: q(0, 1.52866483), control1: q(0, 0.86840701), control2: q(0, 1.08849299))
            }
        }
        p.closeSubpath()
        return p
    }
}

struct WardDeckSlab: ViewModifier {
    @Environment(\.wardIslandEntry) private var entry
    @Environment(\.wardEdgeStore) private var store
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        let slab = frame.offsetBy(dx: -(store?.window.minX ?? 0), dy: -(store?.window.minY ?? 0))
        let join = frame.width > 0 ? entry?.join : nil
        let left = WardEdge.slabTopRadius(join?.left, slabSide: slab.minX, leading: true)
        let right = WardEdge.slabTopRadius(join?.right, slabSide: slab.maxX, leading: false)
        let shape = WardDeckShape(left: left, right: right, joined: join != nil)
        let inset = join.map { WardIsland.foldInset(slab: slab, join: $0) } ?? 0
        let face = content
            .environment(\.wardFoldInset, CGFloat(inset))
            .wardRaised(in: shape, lift: .high)
        Group {
            if let join {
                face.clipShape(shape)
                    .mask {
                        // Near the bottom corner the join can pass the circle's
                        // widest point; the island, too, must cut the slab there.
                        WardIslandPath(join: WardIsland.local(join, origin: SIMD2(slab.minX, slab.minY)),
                                       from: -WardPaper.sideInset, to: slab.width + WardPaper.sideInset, filled: true)
                    }
                    .transition(.identity)
            } else {
                face.transition(.identity)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
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
            .modifier(WardEdgeHost(shown: shown, strip: true))
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
    func wardInset<S: InsettableShape>(in shape: S, lift: WardLift = .low, fill: Color = .wardWell,
                                       control: Bool = false) -> some View {
        background { WardReliefFace(shape: shape, lift: lift, inset: true, fill: fill, control: control) }
    }

    /// Raised at rest; glides into a hollow at the same lift while held or
    /// chosen. A control, with its ink edge, unless `control` is false (an
    /// icon tile that only shows a choice). `edge` overrides the ring ink.
    func wardRelief<S: InsettableShape>(in shape: S, lift: WardLift = .low, pressed: Bool,
                                        control: Bool = true, edge: Color? = nil) -> some View {
        background { WardPressFace(shape: shape, lift: lift, pressed: pressed, control: control, edge: edge) }
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
            .lineSpacing(WardSpace.leading)
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
            .listSectionSpacing(WardSpace.section)
            .lineSpacing(WardSpace.leading)
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
