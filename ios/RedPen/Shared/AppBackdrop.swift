import Combine
import SwiftUI

/// The one background every screen sits on: the library, each mode, sign-in
/// and the terms.
///
/// It is the same slow mesh everywhere - pale mint, lavender and warm cream by
/// day, deep indigo, teal and soft violet at night - so moving from the library
/// into a set and back is moving around one room rather than between six. A
/// mode adds its own colour over the top, faintly; the "All" shelf and the
/// screens that belong to no mode show the mesh as it is.
///
/// It moves, but slowly - a full drift takes the better part of a minute - so
/// it reads as alive rather than as something to watch. The earlier versions
/// taught two things about how NOT to do that:
///
/// - A repeat-forever animation started on appear is a transaction, and it
///   caught whatever else changed at the same moment: lists and text wobbled
///   along with it. Here the movement comes from a TimelineView and is worked
///   out from the clock, so nothing else on the screen is ever animated by it.
/// - Stacked blurred blobs are expensive to redraw and banded on the way. One
///   3x3 mesh and one still vignette are two cheap draws.
///
/// With Reduce Motion on, or in Low Power Mode, it is drawn still.
struct AppBackdrop: View {
    /// The mode colour laid over the mesh, or nil for the mesh alone.
    let tint: Color?

    /// How long a change of colour takes.
    static let fade: TimeInterval = 0.6

    /// The colour the last backdrop on screen was showing, so a screen pushed
    /// on top begins in the colour of the one it covers and eases into its
    /// own, instead of sliding in already a different colour.
    private static var lastShown: BackdropTone?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Where the current fade started from, and when.
    @State private var fadeFrom: BackdropTone?
    @State private var fadeStart: Date

    init(tint: Color? = nil) {
        self.tint = tint
        _fadeFrom = State(initialValue: AppBackdrop.lastShown)
        _fadeStart = State(initialValue: Date())
    }

    private var still: Bool { reduceMotion || lowPower }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
                mesh(at: context.date)
            }
            vignette
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear { AppBackdrop.lastShown = BackdropTone(tint) }
        .onChange(of: tint) { old, new in
            // start the fade from whatever is showing right now, so a second
            // change half way through the first does not jump
            let now = Date()
            fadeFrom = tone(at: now, target: BackdropTone(old))
            fadeStart = now
            AppBackdrop.lastShown = BackdropTone(new)
        }
        .onReceive(NotificationCenter.default
            .publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    /// A still darkening towards the edges, so the eye settles in the middle
    /// where the rows are. Drawn once; it does not move with the mesh.
    private var vignette: some View {
        let edge: Double = scheme == .dark ? 0.28 : 0.05
        let colors: [Color] = [Color.clear, Color.black.opacity(edge)]
        return RadialGradient(colors: colors, center: .center, startRadius: 120, endRadius: 720)
    }

    /// The mode colour as it stands at `date`, part way through a fade or not.
    private func tone(at date: Date, target: BackdropTone) -> BackdropTone {
        guard let from = fadeFrom, !still else { return target }
        let elapsed: Double = date.timeIntervalSince(fadeStart) / AppBackdrop.fade
        let t: Double = min(1, max(0, elapsed))
        // ease in and out, so the change has no visible start or end
        let eased: Double = t * t * (3 - 2 * t)
        return from.mixed(with: target, eased)
    }

    /// The mesh's own colours, corner to corner, before any mode is laid over.
    private static let day: [BackdropColor] = [
        BackdropColor(r: 0.99, g: 0.955, b: 0.905),   // warm cream
        BackdropColor(r: 0.885, g: 0.960, b: 0.930),  // pale mint
        BackdropColor(r: 0.920, g: 0.905, b: 0.985),  // lavender
        BackdropColor(r: 0.935, g: 0.915, b: 0.985),
        BackdropColor(r: 0.985, g: 0.978, b: 0.962),  // near white, behind the text
        BackdropColor(r: 0.900, g: 0.965, b: 0.945),
        BackdropColor(r: 0.890, g: 0.940, b: 0.970),  // mint going blue
        BackdropColor(r: 0.990, g: 0.940, b: 0.905),  // cream going peach
        BackdropColor(r: 0.910, g: 0.890, b: 0.975),
    ]
    private static let night: [BackdropColor] = [
        BackdropColor(r: 0.100, g: 0.100, b: 0.245),  // deep indigo
        BackdropColor(r: 0.045, g: 0.175, b: 0.195),  // teal
        BackdropColor(r: 0.180, g: 0.110, b: 0.265),  // soft violet
        BackdropColor(r: 0.055, g: 0.150, b: 0.180),
        BackdropColor(r: 0.065, g: 0.068, b: 0.100),  // ink, behind the text
        BackdropColor(r: 0.100, g: 0.100, b: 0.225),
        BackdropColor(r: 0.160, g: 0.100, b: 0.245),
        BackdropColor(r: 0.045, g: 0.160, b: 0.180),
        BackdropColor(r: 0.090, g: 0.100, b: 0.235),
    ]

    private func mesh(at date: Date) -> MeshGradient {
        let dark = scheme == .dark
        let base: [BackdropColor] = dark ? AppBackdrop.night : AppBackdrop.day
        let mode = tone(at: date, target: BackdropTone(tint))
        // low saturation: the mode's colour, pulled a third of the way to grey
        let hue = mode.color.mixed(with: BackdropColor(r: 0.5, g: 0.5, b: 0.52), 0.35)

        // Measured from a fixed moment rather than from when this screen
        // appeared, so every screen is at the same point in the drift and a
        // push does not show the mesh jumping to a new shape.
        let s: Double = still ? 0 : date.timeIntervalSinceReferenceDate
        func wave(_ period: Double, _ phase: Double) -> Double {
            let angle: Double = 2 * Double.pi * s / period + phase
            return sin(angle)
        }
        // one edge or middle coordinate: 0.5, moved by at most `a`
        let a: Double = 0.11
        func drift(_ period: Double, _ phase: Double) -> Float {
            let moved: Double = 0.5 + a * wave(period, phase)
            return Float(moved)
        }

        // Only the middle point moves freely; the edge points slide along
        // their edge and the corners stay put, so the mesh always covers the
        // whole screen. Spelled out point by point: one nested literal of
        // nine converted points is slow for the compiler to type.
        let top: Float = drift(29, 0.0)
        let left: Float = drift(37, 1.3)
        let midX: Float = drift(23, 2.1)
        let midY: Float = drift(31, 0.7)
        let right: Float = drift(33, 2.9)
        let bottom: Float = drift(27, 4.2)
        var points: [SIMD2<Float>] = []
        points.append(SIMD2<Float>(0, 0))
        points.append(SIMD2<Float>(top, 0))
        points.append(SIMD2<Float>(1, 0))
        points.append(SIMD2<Float>(0, left))
        points.append(SIMD2<Float>(midX, midY))
        points.append(SIMD2<Float>(1, right))
        points.append(SIMD2<Float>(0, 1))
        points.append(SIMD2<Float>(bottom, 1))
        points.append(SIMD2<Float>(1, 1))

        // How much of the mode's colour each point takes: most in the corners,
        // least in the middle where the text is. Each breathes a little on its
        // own period, so the colour and not only the shape is alive.
        let strength: [Double] = [0.30, 0.18, 0.26,
                                  0.16, 0.05, 0.18,
                                  0.24, 0.16, 0.30]
        let darkScale: Double = dark ? 0.75 : 1.0
        let scale: Double = darkScale * mode.amount
        var colors: [Color] = []
        colors.reserveCapacity(base.count)
        for i in base.indices {
            let index = Double(i)
            let period: Double = 21 + index * 2.3
            let breathe: Double = 0.82 + 0.18 * wave(period, index * 0.9)
            let amount: Double = strength[i] * scale * breathe
            colors.append(base[i].mixed(with: hue, amount).color)
        }

        return MeshGradient(width: 3, height: 3, points: points, colors: colors, smoothsColors: true)
    }
}

/// A mode colour and how much of it is showing - none, for a screen with no
/// mode - so "no colour" can be faded to and from like any other.
struct BackdropTone: Equatable {
    var color: BackdropColor
    var amount: Double

    init(color: BackdropColor, amount: Double) {
        self.color = color; self.amount = amount
    }

    init(_ tint: Color?) {
        if let tint {
            self.init(color: BackdropColor(tint), amount: 1)
        } else {
            self.init(color: BackdropColor(r: 0.5, g: 0.5, b: 0.52), amount: 0)
        }
    }

    /// `t` of the way to `other`. Fading to or from no colour keeps the hue of
    /// the side that has one, so a red screen fades out as red, not via grey.
    func mixed(with other: BackdropTone, _ t: Double) -> BackdropTone {
        let from: BackdropColor = amount == 0 ? other.color : color
        let to: BackdropColor = other.amount == 0 ? color : other.color
        let mixedAmount: Double = amount + (other.amount - amount) * t
        return BackdropTone(color: from.mixed(with: to, t), amount: mixedAmount)
    }
}

/// A plain RGB colour that can be mixed by hand. `Color` cannot be blended
/// part way, and the backdrop needs to, thirty times a second.
struct BackdropColor: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) {
            let red: Double = min(1, max(0, Double(r)))
            let green: Double = min(1, max(0, Double(g)))
            let blue: Double = min(1, max(0, Double(b)))
            self.init(r: red, g: green, b: blue)
        } else {
            self.init(r: 0.5, g: 0.5, b: 0.52)
        }
    }

    /// `t` of the way from this colour to `other`.
    func mixed(with other: BackdropColor, _ t: Double) -> BackdropColor {
        let red: Double = r + (other.r - r) * t
        let green: Double = g + (other.g - g) * t
        let blue: Double = b + (other.b - b) * t
        return BackdropColor(r: red, g: green, b: blue)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}
