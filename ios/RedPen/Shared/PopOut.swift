import SwiftUI
import UIKit

// MARK: - Pop-out: the UI stands OUT of the glass
//
// Not shadows. The screen is treated as a pane of glass with things at
// different heights on either side of it:
//
//   deep      the backdrop, BEHIND the glass - it moves WITH the viewer's eye
//   screen    rows, cards, text, canvases - ON the glass, never moved
//   raised    tiles, chips, headers, text fields, secondary buttons
//   floating  the dock, bottom slabs, switchers, tool clusters, composers
//   hero      the one primary action on a screen
//
// Anything above the glass slides AWAY from the eye as the device tilts (the
// higher, the further), leans a degree or two towards the viewer, shows a
// thin slab side on the viewer's side, carries a sheen that slides with the
// light, and sits over a tight contact shade that only says "this is higher".
// Parallax between the planes is what makes the eye read real depth.
//
// One rule decides what rises: only what you can touch leaves the glass.
//
// The motion comes from ONE shared source (PopOutMotion, see
// PopOutMotion.swift). Only the modifiers in this file read it, and only
// while their surface is on screen and actually lifted, so a screen's own
// body is never re-rendered by the motion.

/// How high a surface stands out of the glass.
enum PopOutPlane: Int, Comparable, Sendable {
    case deep = -1, screen = 0, raised = 1, floating = 2, hero = 3

    static func < (lhs: PopOutPlane, rhs: PopOutPlane) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Every number the pop-out uses, in one place, for tuning on a device.
enum PopOutTuning {
    /// How far a face moves, in points, when the eye is a full unit off-axis.
    static func lift(_ plane: PopOutPlane) -> CGFloat {
        switch plane {
        case .deep, .screen: return 0
        case .raised: return 3
        case .floating: return 5.5
        case .hero: return 8
        }
    }

    /// The most a surface leans towards the viewer, in degrees.
    static func leanDegrees(_ plane: PopOutPlane) -> Double {
        switch plane {
        case .deep, .screen: return 0
        case .raised: return 1.5
        case .floating: return 2.5
        case .hero: return 3.5
        }
    }

    static func sheenAlpha(_ plane: PopOutPlane) -> Double {
        switch plane {
        case .deep, .screen: return 0
        case .raised: return 0.10
        case .floating: return 0.16
        case .hero: return 0.22
        }
    }

    static func rimAlpha(_ plane: PopOutPlane) -> Double {
        switch plane {
        case .deep, .screen: return 0
        case .raised: return 0.30
        case .floating: return 0.40
        case .hero: return 0.50
        }
    }

    static func contactBlur(_ plane: PopOutPlane) -> CGFloat {
        switch plane {
        case .deep, .screen: return 0
        case .raised: return 3
        case .floating: return 5
        case .hero: return 7
        }
    }

    static func contactAlpha(_ plane: PopOutPlane) -> Double {
        switch plane {
        case .deep, .screen: return 0
        case .raised: return 0.10
        case .floating: return 0.13
        case .hero: return 0.16
        }
    }

    /// Bigger windows get a little more depth.
    static func spanScale(_ span: WindowSpan) -> CGFloat {
        switch span {
        case .slim: return 1.0
        case .middling: return 1.1
        case .broad: return 1.2
        }
    }

    /// The slab side runs from this fraction of the face's shift to the face,
    /// so a slab is thinner than its hover height.
    static let slabStart: CGFloat = 0.45
    /// The "held naturally" pose: faces sit slightly up-screen, with the slab
    /// side and the contact shade showing below.
    static let restEye = CGPoint(x: 0, y: 0.4)
    static let deepShift: CGFloat = 14
    static let deepOverscan: CGFloat = 1.08
    static let perspective: CGFloat = 0.45
    static let faceGain: CGFloat = 1.35
    /// No surface ever moves further than this, so hit areas stay put.
    static let maxShift: CGFloat = 9.6
    /// The eye is only republished when it moved at least this much.
    static let publishStep: CGFloat = 0.004
    /// Flip after the on-device check if slabs turn AWAY from the viewer.
    static let leanSign: Double = 1.0
    /// Flip an axis after the on-device check if moving the head right does
    /// not give eye.x > 0 (or down does not give eye.y > 0).
    static let faceAxes = CGPoint(x: 1, y: 1)
    /// 0 = translate only, if glass under rotation3DEffect proves costly.
    static let leanScale: Double = 1.0
    /// Cut the face out of the slab side so translucent glass never darkens.
    static let cutsSlab = true
}

/// The Settings toggles' storage.
enum PopOutSettings {
    /// Bool, default true: "Pop-out effect".
    static let enabledKey = "vignette.popOut"
    /// Bool, default false: "Pop-out with face tracking".
    static let faceKey = "vignette.popOut.face"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var wantsFace: Bool {
        UserDefaults.standard.object(forKey: faceKey) as? Bool ?? false
    }
}

/// Which physical cues a surface shows. Translation is always on.
struct PopOutCues: OptionSet, Sendable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let lean = PopOutCues(rawValue: 1)
    static let sheen = PopOutCues(rawValue: 2)
    static let edge = PopOutCues(rawValue: 4)
    static let contact = PopOutCues(rawValue: 8)
    static let all: PopOutCues = [.lean, .sheen, .edge, .contact]
    /// For text fields and anything with a caret: no lean, no sheen.
    static let translateOnly: PopOutCues = [.edge, .contact]
}

// MARK: - Nesting

private struct PopOutBaseKey: EnvironmentKey {
    static let defaultValue: PopOutPlane = .screen
}

extension EnvironmentValues {
    /// The plane the surrounding surface already stands on. A popOut inside
    /// another only adds the DIFFERENCE, so offsets never double-stack.
    var popOutBase: PopOutPlane {
        get { self[PopOutBaseKey.self] }
        set { self[PopOutBaseKey.self] = newValue }
    }
}

// MARK: - Public API

extension View {
    /// Lifts this surface to `plane`. Apply AFTER the surface's glass or
    /// background (so the whole surface moves) and BEFORE `.disabled` (so a
    /// disabled control sits flat).
    func popOut<S: InsettableShape>(_ plane: PopOutPlane, in shape: S, tint: Color? = nil,
                                    pressed: Bool = false, cues: PopOutCues = .all) -> some View {
        modifier(PopOutModifier(plane: plane, shape: shape, tint: tint, pressed: pressed, cues: cues))
    }

    /// Lifts this surface to `plane`, in a 20-point rounded rectangle.
    func popOut(_ plane: PopOutPlane) -> some View {
        popOut(plane, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// The deep plane: behind the glass, moving WITH the eye. AppBackdrop's
    /// sky only (mesh, nebula and stars).
    func deepParallax() -> some View {
        modifier(DeepParallax())
    }

    /// Holds the still pose while this screen is showing (PencilKit).
    func popOutFrozen() -> some View {
        modifier(PopOutToken(kind: .freeze))
    }

    /// Keeps the camera off while this screen is showing (voice, recording,
    /// drawing). Tilt keeps working.
    func popOutFacePaused() -> some View {
        modifier(PopOutToken(kind: .pauseFace))
    }

    /// Once, on the app's root: follows the scene phase, and with the
    /// `-popOutDebug` launch argument shows the live eye position.
    func popOutLifecycle() -> some View {
        modifier(PopOutLifecycle())
    }

    /// The floating bottom slab for any screen; the content scrolls under it.
    func studyBar<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let bar = StudyActionBar(content: content)
        return safeAreaInset(edge: .bottom, spacing: 0) { bar }
    }

    /// A text field (or anything with a caret) as its own slab on the raised
    /// plane. It slides with the tilt and shows its side, but never leans or
    /// glints, and nothing moves while the keyboard is up
    /// (PopOutMotion.keyboardUp), so the caret stays steady.
    /// `insets` is the room inside the slab around the field; pass a tighter
    /// one when the slab holds its own keys (CountField's minus and plus).
    func popField(cornerRadius: CGFloat = 12, insets: EdgeInsets = PopOutField.insets) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return padding(insets)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: shape)
            .popOut(.raised, in: shape, cues: .translateOnly)
    }

    /// popField as a Form row of its own: the row's own background goes, so
    /// the field reads as a slab standing on the form, not a cell in it.
    func popFieldRow(cornerRadius: CGFloat = 12) -> some View {
        popField(cornerRadius: cornerRadius)
            .listRowBackground(Color.clear)
            .listRowInsets(PopOutField.rowInsets)
    }

    /// A multi-line TextEditor as a raised slab (create and edit forms). The
    /// editor's own background is hidden so the slab's material shows.
    func popEditor(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return scrollContentBackground(.hidden)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: shape)
            .popOut(.raised, in: shape, cues: .translateOnly)
    }

    /// popEditor as a Form row of its own.
    func popEditorRow(cornerRadius: CGFloat = 12) -> some View {
        popEditor(cornerRadius: cornerRadius)
            .listRowBackground(Color.clear)
            .listRowInsets(PopOutField.rowInsets)
    }
}

/// Shared numbers for raised fields.
enum PopOutField {
    /// Room above and below a field row for its slab side and contact shade.
    static let rowInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
    /// Room inside a field's slab: a multi-line field never touches its edge.
    static let insets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
}

/// A tile that stands out of the glass and sinks under the finger. Disabled
/// tiles sit flat.
struct PopTileStyle: ButtonStyle {
    var cornerRadius: CGFloat = 20
    var plane: PopOutPlane = .raised
    var tint: Color? = nil

    init(cornerRadius: CGFloat = 20, plane: PopOutPlane = .raised, tint: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.plane = plane
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        PopTileFace(label: configuration.label, isPressed: configuration.isPressed,
                    cornerRadius: cornerRadius, plane: plane, tint: tint)
    }
}

extension ButtonStyle where Self == PopTileStyle {
    static var popTile: PopTileStyle { PopTileStyle() }
}

private struct PopTileFace: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let cornerRadius: CGFloat
    let plane: PopOutPlane
    let tint: Color?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let scale: CGFloat = isPressed ? 0.975 : 1
        let sunk: Bool = isPressed || !isEnabled
        label
            .contentShape(shape)
            .scaleEffect(scale)
            .popOut(plane, in: shape, tint: tint, pressed: sunk)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.lift)
    }
}

extension Color {
    /// The same colour with its brightness lowered by `amount` (0...1). Used
    /// for slab sides.
    func darkened(_ amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        let lowered: Double = Double(b) - amount
        let brightness: Double = min(1, max(0, lowered))
        return Color(hue: Double(h), saturation: Double(s), brightness: brightness, opacity: Double(a))
    }
}

// MARK: - The pose of one surface

/// Everything a surface needs to draw itself for the current eye position,
/// worked out once per update as plain typed values.
struct PopOutPose {
    var face: CGSize = .zero
    var lean: Angle = .zero
    var axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (x: 1, y: 0, z: 0)
    var sheenCenter = UnitPoint(x: 0.5, y: 0.25)
    var sheenAlpha: Double = 0
    var rimAlpha: Double = 0
    var contact: CGSize = .zero
    var contactBlur: CGFloat = 0
    var contactAlpha: Double = 0
    var slabFrom: CGSize = .zero
    var showsSlab = false

    /// The eye to draw with. Reads the live eye ONLY when it matters, so a
    /// flat, still or off-screen surface never updates per frame.
    @MainActor
    private static func eye(style: PopOutMotion.Style, live: Bool) -> (CGPoint, CGFloat) {
        if live {
            let motion = PopOutMotion.shared
            return (motion.eye, motion.gain)
        }
        if style == .off { return (.zero, 1) }
        return (PopOutTuning.restEye, 1)
    }

    @MainActor
    static func make(_ setup: PopOutSetup) -> PopOutPose {
        make(plane: setup.plane, base: setup.base, span: setup.span, pressed: setup.pressed,
             enabled: setup.enabled, cues: setup.cues, onScreen: setup.onScreen)
    }

    @MainActor
    static func make(plane: PopOutPlane, base: PopOutPlane, span: WindowSpan, pressed: Bool,
                     enabled: Bool, cues: PopOutCues, onScreen: Bool) -> PopOutPose {
        let style: PopOutMotion.Style = PopOutMotion.shared.style
        let top: PopOutPlane = max(plane, base)
        let ownLift: CGFloat = PopOutTuning.lift(top)
        let baseLift: CGFloat = PopOutTuning.lift(base)
        let rawLift: CGFloat = max(0, ownLift - baseLift)
        let ownLean: Double = PopOutTuning.leanDegrees(top)
        let baseLean: Double = PopOutTuning.leanDegrees(base)
        let rawLean: Double = max(0, ownLean - baseLean)
        let off: Bool = style == .off
        let flat: Bool = pressed || !enabled || off
        let live: Bool = style == .live && onScreen && rawLift > 0 && !flat
        let (eye, gain) = PopOutPose.eye(style: style, live: live)

        var pose = PopOutPose()
        let scale: CGFloat = PopOutTuning.spanScale(span)
        let scaled: CGFloat = rawLift * scale * gain
        let rel: CGFloat = flat ? 0 : min(PopOutTuning.maxShift, scaled)
        let rest: CGPoint = PopOutTuning.restEye
        let dx: CGFloat = off ? 0 : eye.x - rest.x
        let dy: CGFloat = off ? 0 : eye.y - rest.y
        let mag: CGFloat = (dx * dx + dy * dy).squareRoot()

        // raised things slide AWAY from the eye
        pose.face = CGSize(width: -eye.x * rel, height: -eye.y * rel)

        if cues.contains(.lean) && !flat && mag > 0.001 {
            let reach: Double = Double(min(1, mag))
            let degrees: Double = rawLean * reach * PopOutTuning.leanSign * PopOutTuning.leanScale
            pose.lean = .degrees(degrees)
            pose.axis = (x: -dy / mag, y: dx / mag, z: 0)
        }

        if cues.contains(.sheen) && !off {
            let half: Double = flat ? 0.5 : 1
            pose.sheenAlpha = PopOutTuning.sheenAlpha(plane) * half
            pose.rimAlpha = PopOutTuning.rimAlpha(plane) * half
            let cx: CGFloat = 0.5 - 0.5 * dx
            let cy: CGFloat = 0.25 - 0.5 * dy
            pose.sheenCenter = UnitPoint(x: cx, y: cy)
        }

        if cues.contains(.contact) && rel > 0 {
            let across: CGFloat = 0.3 * rel * dx
            let tilt: CGFloat = 0.3 * dy
            let drop: CGFloat = (0.35 + tilt) * rel
            pose.contact = CGSize(width: across, height: drop)
            pose.contactBlur = PopOutTuning.contactBlur(plane)
            pose.contactAlpha = PopOutTuning.contactAlpha(plane)
        }

        if cues.contains(.edge) && rel > 0 {
            let start: CGFloat = PopOutTuning.slabStart
            pose.slabFrom = CGSize(width: pose.face.width * start, height: pose.face.height * start)
            pose.showsSlab = true
        }
        return pose
    }
}

// MARK: - The modifier
//
// Split in two so the per-frame work is transform-only:
//
//   PopOutModifier  reads the environment (tint, scheme, contrast, enabled)
//                   and works out the slab colour. It never reads the eye, so
//                   it re-runs only when those change or the surface is
//                   pressed - never per frame.
//   PopOutLive      reads the live eye. Per frame it only changes offsets, a
//                   rotation and two gradient end points: no path is rebuilt,
//                   no colour converted, and the content's own body is never
//                   re-evaluated.

/// The slab side's colour, worked out once per environment change. It is
/// drawn opaque and faded as one layer, so overlapping stamps never darken.
struct PopOutBand: Equatable {
    var color: Color
    var alpha: Double

    /// The surface's own colour, darker, or a neutral shade.
    static func make(tint: Color?, strong: Bool, dark: Bool) -> PopOutBand {
        if strong {
            if let tint { return PopOutBand(color: tint.darkened(0.40), alpha: 1) }
            return PopOutBand(color: .black, alpha: 0.55)
        }
        if let tint { return PopOutBand(color: tint.darkened(0.28), alpha: 1) }
        let neutral: Double = dark ? 0.42 : 0.20
        return PopOutBand(color: .black, alpha: neutral)
    }
}

private struct PopOutModifier<S: InsettableShape>: ViewModifier {
    let plane: PopOutPlane
    let shape: S
    let tint: Color?
    let pressed: Bool
    let cues: PopOutCues

    @Environment(\.popOutBase) private var base
    @Environment(\.windowSpan) private var span
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @State private var onScreen = false

    func body(content: Content) -> some View {
        let strong: Bool = contrast == .increased
        let dark: Bool = scheme == .dark
        let band: PopOutBand = PopOutBand.make(tint: tint, strong: strong, dark: dark)
        let nextBase: PopOutPlane = max(plane, base)
        let look = PopOutLook(solid: reduceTransparency, strong: strong, band: band)
        let setup = PopOutSetup(plane: plane, base: base, span: span, pressed: pressed,
                                enabled: isEnabled, cues: cues, onScreen: onScreen)
        let live = PopOutLive(shape: shape, setup: setup, look: look)
        return content
            .environment(\.popOutBase, nextBase)
            .modifier(live)
            .animation(.snappy(duration: 0.18), value: pressed)
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
    }
}

/// What decides a surface's pose, apart from the eye.
struct PopOutSetup: Equatable {
    var plane: PopOutPlane
    var base: PopOutPlane
    var span: WindowSpan
    var pressed: Bool
    var enabled: Bool
    var cues: PopOutCues
    var onScreen: Bool
}

/// How a surface's cues are painted, fixed between environment changes.
struct PopOutLook: Equatable {
    var solid: Bool
    var strong: Bool
    var band: PopOutBand
}

/// The only part that reads the live eye.
private struct PopOutLive<S: InsettableShape>: ViewModifier {
    let shape: S
    let setup: PopOutSetup
    let look: PopOutLook

    func body(content: Content) -> some View {
        let pose = PopOutPose.make(setup)
        let sheen = PopOutSheen(shape: shape, pose: pose, solid: look.solid, strong: look.strong)
        let footing = PopOutFooting(shape: shape, pose: pose, band: look.band)
        return content
            .overlay {
                sheen
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .offset(pose.face)
            .rotation3DEffect(pose.lean, axis: pose.axis, anchor: .center, anchorZ: 0,
                              perspective: PopOutTuning.perspective)
            // attached after the offset, so it is drawn at the footprint
            .background {
                footing
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// The light on a raised face: a soft band that slides with the tilt, and a
/// rim lit from the same side.
private struct PopOutSheen<S: InsettableShape>: View {
    let shape: S
    let pose: PopOutPose
    let solid: Bool
    let strong: Bool

    private var sheenFill: AnyShapeStyle {
        if solid || pose.sheenAlpha <= 0 { return AnyShapeStyle(Color.clear) }
        let c = pose.sheenCenter
        let start = UnitPoint(x: c.x - 0.45, y: c.y - 0.45)
        let end = UnitPoint(x: c.x + 0.45, y: c.y + 0.45)
        let glint = Color.white.opacity(pose.sheenAlpha)
        let colors: [Color] = [Color.clear, glint, Color.clear]
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: start, endPoint: end))
    }

    private var rimStyle: AnyShapeStyle {
        if pose.rimAlpha <= 0 { return AnyShapeStyle(Color.clear) }
        if strong { return AnyShapeStyle(Color.primary.opacity(0.6)) }
        if solid { return AnyShapeStyle(Color.primary.opacity(0.35)) }
        let c = pose.sheenCenter
        let far = UnitPoint(x: 1 - c.x, y: 1 - c.y)
        let lit = Color.white.opacity(pose.rimAlpha)
        let colors: [Color] = [lit, Color.clear]
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: c, endPoint: far))
    }

    private var rimWidth: CGFloat { strong || solid ? 1 : 0.75 }

    var body: some View {
        ZStack {
            shape.fill(sheenFill)
            shape.strokeBorder(rimStyle, lineWidth: rimWidth)
        }
    }
}

/// What sits under a raised face, at its footprint: a tight contact shade,
/// and the slab side between the glass and the face.
private struct PopOutFooting<S: InsettableShape>: View {
    let shape: S
    let pose: PopOutPose
    let band: PopOutBand

    var body: some View {
        let shade = Color.black.opacity(pose.contactAlpha)
        let slabAlpha: Double = pose.showsSlab ? 1 : 0
        ZStack {
            shape.fill(shade)
                .blur(radius: pose.contactBlur)
                .offset(pose.contact)
            PopOutSlab(shape: shape, from: pose.slabFrom, to: pose.face, band: band)
                .opacity(slabAlpha)
        }
    }
}

/// The visible side of a slab, composited on the GPU instead of built from
/// path booleans: the shape stamped at the glass end, halfway and at the
/// face, then the face punched out (destinationOut) so the side never
/// darkens translucent glass. The stamps are drawn opaque and the group is
/// faded as one layer, so overlaps never double up. Per frame only the
/// offsets change.
private struct PopOutSlab<S: InsettableShape>: View {
    let shape: S
    let from: CGSize
    let to: CGSize
    let band: PopOutBand

    private var mid: CGSize {
        let x: CGFloat = (from.width + to.width) * 0.5
        let y: CGFloat = (from.height + to.height) * 0.5
        return CGSize(width: x, height: y)
    }

    var body: some View {
        let fill: Color = band.color
        ZStack {
            shape.fill(fill).offset(from)
            shape.fill(fill).offset(mid)
            shape.fill(fill).offset(to)
            if PopOutTuning.cutsSlab {
                shape.fill(Color.black)
                    .offset(to)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .opacity(band.alpha)
    }
}

// MARK: - The deep plane

private struct DeepParallax: ViewModifier {
    @Environment(\.windowSpan) private var span
    @State private var onScreen = false

    @MainActor
    private static func shift(span: WindowSpan, onScreen: Bool) -> CGSize {
        let motion = PopOutMotion.shared
        guard motion.style == .live, onScreen else { return .zero }
        // covered by the 3D map: nothing to move, and nothing read live
        if SpaceQualityCenter.shared.skyCovered { return .zero }
        let eye: CGPoint = motion.eye
        let rest: CGPoint = PopOutTuning.restEye
        let reach: CGFloat = PopOutTuning.deepShift * PopOutTuning.spanScale(span)
        let x: CGFloat = (eye.x - rest.x) * reach
        let y: CGFloat = (eye.y - rest.y) * reach
        return CGSize(width: x, height: y)
    }

    func body(content: Content) -> some View {
        let moved: CGSize = DeepParallax.shift(span: span, onScreen: onScreen)
        return content
            .scaleEffect(PopOutTuning.deepOverscan)
            .offset(moved)
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
    }
}

// MARK: - Screen-level switches

private struct PopOutToken: ViewModifier {
    enum Kind { case freeze, pauseFace }
    let kind: Kind
    @State private var token = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onAppear {
                switch kind {
                case .freeze: PopOutMotion.shared.freeze(token)
                case .pauseFace: PopOutMotion.shared.pauseFace(token)
                }
            }
            .onDisappear {
                switch kind {
                case .freeze: PopOutMotion.shared.unfreeze(token)
                case .pauseFace: PopOutMotion.shared.resumeFace(token)
                }
            }
    }
}

private struct PopOutLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var phase
    private static let debug: Bool = ProcessInfo.processInfo.arguments.contains("-popOutDebug")

    func body(content: Content) -> some View {
        // the sky's root: SpaceQuality, the tiles' zoom namespace and
        // "Always night sky" (Space/SpaceQuality.swift)
        SkyRoot(content: content)
            .overlay(alignment: .topLeading) {
                if PopOutLifecycle.debug {
                    PopOutDebugLabel()
                        .allowsHitTesting(false)
                }
            }
            .onAppear { PopOutMotion.shared.refresh() }
            .onChange(of: phase) { _, now in
                PopOutMotion.shared.noteScene(active: now == .active)
            }
    }
}

/// `-popOutDebug` only: the style, the eye and where it comes from.
private struct PopOutDebugLabel: View {
    var body: some View {
        let motion = PopOutMotion.shared
        let eye: CGPoint = motion.eye
        let x: String = String(format: "%.2f", Double(eye.x))
        let y: String = String(format: "%.2f", Double(eye.y))
        let style: String = String(describing: motion.style)
        let source: String = motion.source.rawValue
        let line: String = "\(style)  x \(x)  y \(y)  \(source)"
        Text(line)
            .font(.caption2.monospaced())
            .padding(6)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.white)
            .padding(.top, 50)
            .padding(.leading, 8)
    }
}
