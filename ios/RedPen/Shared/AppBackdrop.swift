import SwiftUI
import UIKit

/// The one background every screen sits on: the library, each mode, sign-in
/// and the terms.
///
/// Deep space, the same everywhere, so moving from the library into a set and
/// back is moving around one sky rather than between six rooms - and the
/// same sky the 3D note map flies through (SkyChart), so opening the map
/// looks like this sky gaining depth. Back to front:
///
///   deep plane (moves WITH the eye, behind the glass; see PopOut.swift)
///     mesh      ink to indigo, violet, teal and an H-alpha rose corner at
///               night; a "high-altitude dawn" by day - pale indigo zenith
///               to a peach horizon - unless "Always night sky" is on
///     nebula    baked once (NebulaBaker: runtime Metal, CPU fallback,
///               cached in Caches), laid on with screen (gas) and multiply
///               (dust), taking a little of the mode's colour; it drifts a
///               few points on slow sines
///     stars     the shared sky's far/mid/near layers, the galactic band and
///               the map's nebula clouds (StarLayers); they drift with the
///               scroll and the near ones hold back against the tilt
///   ink column  a darkening behind the text, so the nebula never reaches
///               more than 0.35 of its strength behind a content column
///   vignette
///   warp        the lift-off streak, only while one runs (WarpEffect)
///
/// A mode adds its own colour over the mesh, faintly; the "All" shelf and
/// the screens that belong to no mode show the sky as it is.
///
/// It moves, but slowly - on a 15 fps clock: a 40-point drift over half a
/// minute moves less than a point a frame, so the lower rate cannot be seen,
/// and it halves how often the glass above has to re-sample it. The earlier
/// versions taught two things about how NOT to do that:
///
/// - A repeat-forever animation started on appear is a transaction, and it
///   caught whatever else changed at the same moment: lists and text wobbled
///   along with it. Here the movement comes from a TimelineView and is worked
///   out from the clock, so nothing else on the screen is ever animated by it.
/// - Stacked blurred blobs are expensive to redraw and banded on the way. The
///   mesh is one draw, the nebula two pre-baked pictures, the stars canvases
///   drawn once per size.
///
/// How alive it is comes from SpaceQuality: drift at .full and .reduced,
/// twinkle and tilt at .full only, one still frame at .still (Reduce Motion,
/// Low Power Mode, a hot device).
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
    @Environment(\.spaceQuality) private var quality
    @Environment(\.colorSchemeContrast) private var contrast
    /// Where the current fade started from, and when.
    @State private var fadeFrom: BackdropTone?
    @State private var fadeStart: Date

    init(tint: Color? = nil) {
        self.tint = tint
        _fadeFrom = State(initialValue: AppBackdrop.lastShown)
        _fadeStart = State(initialValue: Date())
    }

    private var still: Bool { !quality.drifts }

    /// Night palette. "Always night sky" holds the whole app dark at the
    /// root (SkyRoot), so the scheme alone decides - text stays readable.
    private var night: Bool { scheme == .dark }

    private var strong: Bool { contrast == .increased }

    var body: some View {
        let night: Bool = self.night
        let quality: SpaceQuality = self.quality
        ZStack {
            // The deepest plane: behind the glass, so it moves WITH the eye
            // while everything raised moves against it. The vignette and the
            // ink column stay put, as the edge of the device's glass.
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 15, paused: still)) { context in
                    sky(at: context.date)
                }
                SkyStars(night: night, quality: quality)
            }
            .deepParallax()
            inkColumn
            vignette
            WarpStreaks(night: night)
        }
        .ignoresSafeArea()
        // the parallax overscans the sky; never let it spill past the screen
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear {
            AppBackdrop.lastShown = BackdropTone(tint)
            SkyNebula.shared.prepare()
        }
        .onChange(of: tint) { old, new in
            // start the fade from whatever is showing right now, so a second
            // change half way through the first does not jump
            let now = Date()
            fadeFrom = tone(at: now, target: BackdropTone(old))
            fadeStart = now
            AppBackdrop.lastShown = BackdropTone(new)
        }
    }

    /// One frame of the moving part: the mesh and the nebula over it.
    private func sky(at date: Date) -> some View {
        let mode: BackdropTone = tone(at: date, target: BackdropTone(tint))
        return ZStack {
            mesh(at: date, mode: mode)
            nebula(at: date, mode: mode)
        }
    }

    /// A still darkening towards the edges, so the eye settles in the middle
    /// where the rows are. Drawn once; it does not move with the sky.
    private var vignette: some View {
        let edge: Double = night ? 0.42 : 0.05
        let colors: [Color] = [Color.clear, Color.black.opacity(edge)]
        return RadialGradient(colors: colors, center: .center, startRadius: 120, endRadius: 720)
    }

    /// Dark ink behind the text column at night (a soft light behind it by
    /// day), stronger with Increase Contrast.
    private var inkColumn: some View {
        let base: Double = night ? 0.30 : 0.16
        let alpha: Double = strong ? base + 0.2 : base
        let ink: Color = night ? SkyPalette.ink : Color.white
        let stops: [Gradient.Stop] = [
            Gradient.Stop(color: ink.opacity(0), location: 0),
            Gradient.Stop(color: ink.opacity(alpha), location: 0.22),
            Gradient.Stop(color: ink.opacity(alpha), location: 0.78),
            Gradient.Stop(color: ink.opacity(0), location: 1)
        ]
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
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

    /// Seconds on the shared clock: measured from a fixed moment rather than
    /// from when this screen appeared, so every screen is at the same point
    /// in the drift and a push does not show the sky jumping.
    private func clock(_ date: Date) -> Double {
        still ? 0 : date.timeIntervalSinceReferenceDate
    }

    private static func wave(_ s: Double, _ period: Double, _ phase: Double) -> Double {
        let angle: Double = 2 * Double.pi * s / period + phase
        return sin(angle)
    }

    // MARK: The nebula

    @ViewBuilder
    private func nebula(at date: Date, mode: BackdropTone) -> some View {
        let s: Double = clock(date)
        let dx: CGFloat = CGFloat(18 * AppBackdrop.wave(s, 53, 0.4))
        let dy: CGFloat = CGFloat(14 * AppBackdrop.wave(s, 67, 1.9))
        let turn: Double = 1.2 * AppBackdrop.wave(s, 89, 0.8)
        let contrastScale: Double = strong ? 0.5 : 1
        let gasAlpha: Double = (night ? 0.70 : 0.15) * contrastScale
        let dustAlpha: Double = (night ? 0.55 : 0.12) * contrastScale
        // the gas takes a little of the mode's colour
        let white = BackdropColor(r: 1, g: 1, b: 1)
        let wash: Color = white.mixed(with: mode.color, 0.28 * mode.amount).color
        let baked = SkyNebula.shared
        if let gas = baked.gas {
            SkyPicture(image: gas, dx: dx, dy: dy, turn: turn)
                .colorMultiply(wash)
                .mask { SkyPalette.columnMask }
                .opacity(gasAlpha)
                .blendMode(night ? .screen : .normal)
        }
        if let dust = baked.dust {
            SkyPicture(image: dust, dx: dx * 1.2, dy: dy * 1.2, turn: turn)
                .mask { SkyPalette.columnMask }
                .opacity(dustAlpha)
                .blendMode(.multiply)
        }
    }

    // MARK: The mesh

    private func mesh(at date: Date, mode: BackdropTone) -> MeshGradient {
        let base: [BackdropColor] = night ? SkyPalette.night : SkyPalette.dawn
        // low saturation: the mode's colour, pulled a third of the way to grey
        let hue = mode.color.mixed(with: BackdropColor(r: 0.5, g: 0.5, b: 0.52), 0.35)

        let s: Double = clock(date)
        // one edge or middle coordinate: 0.5, moved by at most `a`
        let a: Double = 0.11
        func drift(_ period: Double, _ phase: Double) -> Float {
            let moved: Double = 0.5 + a * AppBackdrop.wave(s, period, phase)
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
        let darkScale: Double = night ? 0.7 : 1.0
        let scale: Double = darkScale * mode.amount
        var colors: [Color] = []
        colors.reserveCapacity(base.count)
        for i in base.indices {
            let index = Double(i)
            let period: Double = 21 + index * 2.3
            let breathe: Double = 0.82 + 0.18 * AppBackdrop.wave(s, period, index * 0.9)
            let amount: Double = strength[i] * scale * breathe
            colors.append(base[i].mixed(with: hue, amount).color)
        }

        return MeshGradient(width: 3, height: 3, points: points, colors: colors, smoothsColors: true)
    }
}

/// One baked nebula picture, filling the screen and sliding by (dx, dy)
/// with a slight turn. An overlay on a clear view, so its overscan never
/// changes the layout.
private struct SkyPicture: View {
    let image: Image
    let dx: CGFloat
    let dy: CGFloat
    let turn: Double

    var body: some View {
        Color.clear
            .overlay {
                image
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.14)
                    .rotationEffect(.degrees(turn))
                    .offset(x: dx, y: dy)
            }
    }
}

/// The sky's colours.
enum SkyPalette {
    /// The ink behind the text: #05060F.
    static let ink = Color(red: 0.020, green: 0.024, blue: 0.060)

    /// The nebula at full strength at the edges, at most 0.45 of it across
    /// the content column (0.70 x 0.45 < 0.35 at night).
    static var columnMask: LinearGradient {
        let stops: [Gradient.Stop] = [
            Gradient.Stop(color: Color.white, location: 0),
            Gradient.Stop(color: Color.white.opacity(0.45), location: 0.24),
            Gradient.Stop(color: Color.white.opacity(0.45), location: 0.76),
            Gradient.Stop(color: Color.white, location: 1)
        ]
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    /// Night, corner to corner: ink and indigo, violet, teal, an H-alpha
    /// rose corner, and ink behind the text in the middle.
    static let night: [BackdropColor] = [
        BackdropColor(r: 0.055, g: 0.060, b: 0.165),  // indigo
        BackdropColor(r: 0.030, g: 0.034, b: 0.092),  // ink
        BackdropColor(r: 0.120, g: 0.062, b: 0.195),  // violet
        BackdropColor(r: 0.024, g: 0.092, b: 0.118),  // teal
        BackdropColor(r: 0.020, g: 0.024, b: 0.060),  // ink, behind the text
        BackdropColor(r: 0.062, g: 0.052, b: 0.150),
        BackdropColor(r: 0.150, g: 0.045, b: 0.098),  // H-alpha rose
        BackdropColor(r: 0.030, g: 0.036, b: 0.100),
        BackdropColor(r: 0.034, g: 0.098, b: 0.128),  // teal
    ]

    /// High-altitude dawn: a pale indigo zenith, lavender, and a peach
    /// horizon, with near white behind the text.
    static let dawn: [BackdropColor] = [
        BackdropColor(r: 0.585, g: 0.620, b: 0.850),  // zenith
        BackdropColor(r: 0.640, g: 0.670, b: 0.880),
        BackdropColor(r: 0.620, g: 0.615, b: 0.865),
        BackdropColor(r: 0.850, g: 0.835, b: 0.945),  // lavender
        BackdropColor(r: 0.975, g: 0.968, b: 0.975),  // near white, behind the text
        BackdropColor(r: 0.870, g: 0.840, b: 0.935),
        BackdropColor(r: 0.992, g: 0.868, b: 0.772),  // peach horizon
        BackdropColor(r: 0.996, g: 0.905, b: 0.830),
        BackdropColor(r: 0.988, g: 0.858, b: 0.800),
    ]
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
/// part way, and the backdrop needs to, fifteen times a second.
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
