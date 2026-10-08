import SwiftUI
import UIKit

// MARK: - Pop-out: soft UI depth, and the tilt that moves it
//
// The screen is one matte base, and every surface is shaped out of it by two
// lights from the top left (WardRelief, drawn by WardSurfaces). A surface's
// plane says how it is shaped:
//
//   deep      pressed into the base: a well (and the backdrop's parallax)
//   screen    the base itself: text, card contents, canvases - no relief
//   raised    tiles, chips, headers, secondary buttons: a soft extrude
//   floating  the dock, bottom slabs, switchers, tool clusters: stronger
//   hero      the one primary action on a screen: the strongest
//
// Held, a raised surface sinks into the base, one lift nearer it; disabled,
// it lies low and faint. Anything raised also slides away from the eye as the
// device tilts (the higher, the further) and leans a degree or two towards
// the viewer, its relief going with it: parallax between the planes is what
// makes the eye read the depth. At rest everything sits where it was laid
// out.
//
// One rule decides what rises: only what you can touch leaves the base.
//
// The motion comes from ONE shared source (PopOutMotion, see
// PopOutMotion.swift). Only the modifiers in this file read it, and only
// while their surface is on screen and actually lifted, so a screen's own
// body is never re-rendered by the motion.

/// How high a surface stands off the base.
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

    /// How far a plane's relief stands off the base (the deep plane's is
    /// pressed in); the screen plane has none.
    static func relief(_ plane: PopOutPlane) -> WardLift? {
        switch plane {
        case .deep: return .low
        case .screen: return nil
        case .raised: return .mid
        case .floating: return .high
        case .hero: return .peak
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

    /// The "held naturally" pose: where the eye sits while the device is
    /// held still, and where a face sits exactly as it was laid out.
    static let restEye = CGPoint(x: 0, y: 0.4)
    static let deepShift: CGFloat = 14
    static let deepOverscan: CGFloat = 1.08
    static let perspective: CGFloat = 0.45
    static let faceGain: CGFloat = 1.35
    /// No surface ever moves further than this, so hit areas stay put.
    static let maxShift: CGFloat = 9.6
    /// The eye is only republished when it moved at least this much.
    static let publishStep: CGFloat = 0.004
    /// Flip after the on-device check if faces lean AWAY from the viewer.
    static let leanSign: Double = 1.0
    /// Flip an axis after the on-device check if moving the head right does
    /// not give eye.x > 0 (or down does not give eye.y > 0).
    static let faceAxes = CGPoint(x: 1, y: 1)
    /// 0 = translate only, if rotation3DEffect proves costly.
    static let leanScale: Double = 1.0
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

/// Which cues a surface shows. Sliding with the tilt is always on; `lean`
/// tilts it towards the viewer, and `edge` or `contact` draw its relief.
/// `sheen` is kept for older callers: the soft UI's highlight is part of
/// the relief.
struct PopOutCues: OptionSet, Sendable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let lean = PopOutCues(rawValue: 1)
    static let sheen = PopOutCues(rawValue: 2)
    static let edge = PopOutCues(rawValue: 4)
    static let contact = PopOutCues(rawValue: 8)
    static let all: PopOutCues = [.lean, .sheen, .edge, .contact]
    /// For anything with a caret: the relief, but no lean.
    static let translateOnly: PopOutCues = [.edge, .contact]

    /// Whether the surface draws its relief.
    var shapesRelief: Bool { !isDisjoint(with: [.edge, .contact]) }
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
    /// Shapes this surface out of the base at `plane`, in `shape`, and lets
    /// it slide and lean with the tilt. The surface draws no background of
    /// its own: the relief is its face. Apply BEFORE `.disabled` (so a
    /// disabled control lies low). `pressed` sinks it into the base.
    /// `tint` is accepted for callers written for the glass slabs; every
    /// face is shaped from the base, so a tint says itself on the content.
    /// `lift` stands the relief lower (or higher) than the plane's own
    /// where there is no room for it; the surface still moves as its plane.
    func popOut<S: InsettableShape>(_ plane: PopOutPlane, in shape: S, tint: Color? = nil,
                                    pressed: Bool = false, cues: PopOutCues = .all,
                                    lift: WardLift? = nil) -> some View {
        modifier(PopOutModifier(plane: plane, shape: shape, pressed: pressed, cues: cues, lift: lift))
    }

    /// Shapes this surface at `plane`, in a 20-point rounded rectangle.
    func popOut(_ plane: PopOutPlane) -> some View {
        popOut(plane, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// The deep plane's parallax: the backdrop moves WITH the eye.
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

    /// A text field (or anything with a caret) as a well pressed into the
    /// base. It never moves, so the caret stays steady. `insets` is the
    /// room inside the well around the field; pass a tighter one when the
    /// well holds its own keys (CountField's minus and plus).
    func popField(cornerRadius: CGFloat = 12, insets: EdgeInsets = PopOutField.insets) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return padding(insets)
            .frame(minHeight: 44)
            .wardInset(in: shape)
    }

    /// popField as a Form row of its own: the row's own background goes, so
    /// the well is pressed into the form's base, not into a cell.
    func popFieldRow(cornerRadius: CGFloat = 12) -> some View {
        popField(cornerRadius: cornerRadius)
            .listRowBackground(Color.clear)
            .listRowInsets(PopOutField.rowInsets)
    }

    /// A multi-line TextEditor as a well pressed into the base (create and
    /// edit forms). The editor's own background is hidden so the well shows.
    func popEditor(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return scrollContentBackground(.hidden)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minHeight: 44)
            .wardInset(in: shape)
    }

    /// popEditor as a Form row of its own.
    func popEditorRow(cornerRadius: CGFloat = 12) -> some View {
        popEditor(cornerRadius: cornerRadius)
            .listRowBackground(Color.clear)
            .listRowInsets(PopOutField.rowInsets)
    }
}

/// Shared numbers for fields.
enum PopOutField {
    /// Room round a field row: its well's edges where the tiles' are (8 in
    /// from the cell) and, with `insets`, its words where theirs are.
    static let rowInsets = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    /// Room inside a field's well: a multi-line field never touches its wall.
    static let insets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
}

/// A tile raised off the base that sinks into it under the finger, and
/// stays pressed in while `selected`. A disabled tile lies low and faint.
/// The label draws no background of its own: the relief is its face.
struct PopTileStyle: ButtonStyle {
    var cornerRadius: CGFloat = 20
    var plane: PopOutPlane = .raised
    /// Accepted for older callers (see popOut); not drawn.
    var tint: Color? = nil
    /// The chosen one of a set: pressed in until another is chosen.
    var selected = false
    /// The relief's lift in place of the plane's: `.low` for a tile in a
    /// List row, which cuts anything that reaches further.
    var lift: WardLift? = nil

    init(cornerRadius: CGFloat = 20, plane: PopOutPlane = .raised, tint: Color? = nil, selected: Bool = false,
         lift: WardLift? = nil) {
        self.cornerRadius = cornerRadius
        self.plane = plane
        self.tint = tint
        self.selected = selected
        self.lift = lift
    }

    func makeBody(configuration: Configuration) -> some View {
        PopTileFace(label: configuration.label, isPressed: configuration.isPressed,
                    selected: selected, cornerRadius: cornerRadius, plane: plane, lift: lift)
    }
}

extension ButtonStyle where Self == PopTileStyle {
    static var popTile: PopTileStyle { PopTileStyle() }
}

private struct PopTileFace: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let selected: Bool
    let cornerRadius: CGFloat
    let plane: PopOutPlane
    let lift: WardLift?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        label
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(shape)
            .popOut(plane, in: shape, pressed: isPressed || selected, lift: lift)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
    }
}

extension Color {
    /// The same colour with its brightness lowered by `amount` (0...1).
    func darkened(_ amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        let lowered: Double = Double(b) - amount
        let brightness: Double = min(1, max(0, lowered))
        return Color(hue: Double(h), saturation: Double(s), brightness: brightness, opacity: Double(a))
    }
}

// MARK: - The pose of one surface

/// Where a surface sits for the current eye position, worked out once per
/// update as plain typed values.
struct PopOutPose {
    var face: CGSize = .zero
    var lean: Angle = .zero
    var axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (x: 1, y: 0, z: 0)

    /// The eye to draw with. Reads the live eye ONLY when it matters, so a
    /// flat, still or off-screen surface never updates per frame.
    @MainActor
    private static func eye(style: PopOutMotion.Style, live: Bool) -> (CGPoint, CGFloat) {
        if live {
            let motion = PopOutMotion.shared
            return (motion.eye, motion.gain)
        }
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
        let flat: Bool = pressed || !enabled || style == .off
        let live: Bool = style == .live && onScreen && rawLift > 0 && !flat
        var pose = PopOutPose()
        // still, flat or off screen: exactly where it was laid out
        guard live else { return pose }
        let (eye, gain) = PopOutPose.eye(style: style, live: live)

        let scale: CGFloat = PopOutTuning.spanScale(span)
        let rel: CGFloat = min(PopOutTuning.maxShift, rawLift * scale * gain)
        let rest: CGPoint = PopOutTuning.restEye
        let dx: CGFloat = eye.x - rest.x
        let dy: CGFloat = eye.y - rest.y
        let mag: CGFloat = (dx * dx + dy * dy).squareRoot()

        // raised things slide AWAY from the eye, from where they rest
        pose.face = CGSize(width: -dx * rel, height: -dy * rel)

        if cues.contains(.lean) && mag > 0.001 {
            let reach: Double = Double(min(1, mag))
            let degrees: Double = rawLean * reach * PopOutTuning.leanSign * PopOutTuning.leanScale
            pose.lean = .degrees(degrees)
            pose.axis = (x: -dy / mag, y: dx / mag, z: 0)
        }
        return pose
    }
}

// MARK: - The modifier
//
// Split in two so the per-frame work is transform-only:
//
//   PopOutModifier  reads the environment (enabled, Reduce Motion) and
//                   draws the relief. It never reads the eye, so it re-runs
//                   only when those change or the surface is pressed -
//                   never per frame.
//   PopOutLive      reads the live eye. Per frame it only changes an offset
//                   and a rotation: no shadow is redrawn, and the content's
//                   own body is never re-evaluated.

private struct PopOutModifier<S: InsettableShape>: ViewModifier {
    let plane: PopOutPlane
    let shape: S
    let pressed: Bool
    let cues: PopOutCues
    let lift: WardLift?

    @Environment(\.popOutBase) private var base
    @Environment(\.windowSpan) private var span
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = false

    func body(content: Content) -> some View {
        let nextBase: PopOutPlane = max(plane, base)
        let setup = PopOutSetup(plane: plane, base: base, span: span, pressed: pressed,
                                enabled: isEnabled, cues: cues, onScreen: onScreen)
        let shows: Bool = cues.shapesRelief
        return content
            .environment(\.popOutBase, nextBase)
            // under the content and moving with it
            .background {
                if shows {
                    PopOutRelief(shape: shape, plane: plane, pressed: pressed, enabled: isEnabled, chosenLift: lift)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .modifier(PopOutLive(setup: setup))
            // Reduce Motion: pressed in at once, no settling
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: pressed)
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

/// A surface's relief, by its plane: a well on the deep plane, nothing on
/// the screen plane, raised above it, higher with each plane (or as high as
/// `chosenLift`). Held, it sinks one lift nearer the base; disabled, it
/// lies low and faint.
private struct PopOutRelief<S: InsettableShape>: View {
    let shape: S
    let plane: PopOutPlane
    let pressed: Bool
    let enabled: Bool
    let chosenLift: WardLift?

    private var reliefLift: WardLift? {
        guard let own = PopOutTuning.relief(plane) else { return nil }
        return chosenLift ?? own
    }

    var body: some View {
        if let lift = reliefLift {
            if plane == .deep {
                WardReliefFace(shape: shape, lift: lift, inset: true)
            } else if !enabled {
                WardReliefFace(shape: shape, lift: .low)
                    .opacity(0.5)
            } else {
                WardReliefFace(shape: shape, lift: pressed ? lift.lower : lift, inset: pressed)
            }
        }
    }
}

/// The only part that reads the live eye.
private struct PopOutLive: ViewModifier {
    let setup: PopOutSetup

    func body(content: Content) -> some View {
        let pose = PopOutPose.make(setup)
        return content
            .offset(pose.face)
            .rotation3DEffect(pose.lean, axis: pose.axis, anchor: .center, anchorZ: 0,
                              perspective: PopOutTuning.perspective)
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
