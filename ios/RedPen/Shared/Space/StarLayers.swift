import SwiftUI
import simd

// MARK: - Stars at three depths
//
// The shared sky (SkyChart) seen flat, split by brightness into three
// layers - far (faint), mid, near (bright, with a soft glow) - so they can
// slide at different speeds:
//
//   scroll  each layer moves by offset x depth (far 0.02, mid 0.06, near
//           0.12), eased to at most 36 points, so stars drift, not scroll
//   tilt    inside the deep plane (which already moves WITH the eye), the
//           nearer layers move back against it: near -8, mid -4 points at a
//           full unit of eye, so the far stars read as furthest away
//
// Each layer is one Canvas drawn once per size (a few hundred dots), and
// only its offset changes afterwards. The ~40 twinkling stars have their own
// small Canvas on a 20 fps clock, only at SpaceQuality.full.
//
// Tilt comes from PopOutMotion - the app's one motion source - never a
// second CMMotionManager.

enum StarDepth: Int, CaseIterable {
    case far, mid, near

    var scrollFactor: CGFloat {
        switch self {
        case .far: return 0.02
        case .mid: return 0.06
        case .near: return 0.12
        }
    }

    /// Points moved back against the deep plane at a full unit of eye.
    var tiltBack: CGFloat {
        switch self {
        case .far: return 0
        case .mid: return 4
        case .near: return 8
        }
    }
}

/// One star as the flat screen sees it, in tan space (SkyChart.project).
struct FlatStar: Sendable {
    var at: SIMD2<Float>
    var radius: CGFloat
    var alpha: Double
    var tint: Int
}

/// The flat sky, worked out once from the shared chart. Pure data, safe on
/// any thread.
nonisolated enum FlatSky {
    /// How far out in tan space a star is kept (past the edges, for the
    /// parallax and for wide windows).
    static let reach: Float = 1.0

    static let far: [FlatStar] = layer(.far)
    static let mid: [FlatStar] = layer(.mid)
    static let near: [FlatStar] = layer(.near)
    static let twinklers: [FlatStar] = pickTwinklers()

    static func stars(_ depth: StarDepth) -> [FlatStar] {
        switch depth {
        case .far: return far
        case .mid: return mid
        case .near: return near
        }
    }

    private static func layer(_ depth: StarDepth) -> [FlatStar] {
        var out: [FlatStar] = []
        for star in SkyChart.stars {
            let shine: Float = star.shine
            let which: StarDepth
            if shine < 0.12 {
                which = .far
            } else if shine < 0.5 {
                which = .mid
            } else {
                which = .near
            }
            guard which == depth, let at = SkyChart.project(star.dir) else { continue }
            guard abs(at.x) < reach && abs(at.y) < reach else { continue }
            let brightness: Double = 0.42 + Double(shine) * 0.95
            let alpha: Double = min(1, brightness)
            let radius: CGFloat = FlatSky.radius(depth)
            out.append(FlatStar(at: at, radius: radius, alpha: alpha, tint: star.tint))
        }
        return out
    }

    private static func radius(_ depth: StarDepth) -> CGFloat {
        switch depth {
        case .far: return 0.55
        case .mid: return 0.85
        case .near: return 1.2
        }
    }

    /// Every seventh near star, up to 40.
    private static func pickTwinklers() -> [FlatStar] {
        var out: [FlatStar] = []
        for (index, star) in near.enumerated() where index % 7 == 3 {
            out.append(star)
            if out.count >= 40 { break }
        }
        return out
    }

    static func colour(_ tint: Int) -> Color {
        let tints: [SIMD3<Float>] = SkyChart.starTints
        let t: SIMD3<Float> = tints[tint % tints.count]
        return Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))
    }
}

// MARK: - Scroll

/// The scroll offset of whatever list is on screen, for the stars. Only the
/// star layers' offset modifiers read it, so no screen re-renders with it.
@MainActor
@Observable
final class SkyScroll {
    static let shared = SkyScroll()
    var offset: CGFloat = 0
    private init() {}
}

extension View {
    /// Lets the backdrop's stars drift as this scroll view (or List/Form)
    /// scrolls. Put it on the scrolling view itself.
    func skyScroll() -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, now in
            SkyScroll.shared.offset = now
        }
    }
}

// MARK: - The layers

/// The three star layers, the band and the map's nebula clouds.
struct SkyStars: View {
    let night: Bool
    let quality: SpaceQuality

    var body: some View {
        ZStack {
            ForEach(StarDepth.allCases, id: \.rawValue) { depth in
                ZStack {
                    StarLayerCanvas(depth: depth, night: night)
                    if depth == .near && quality.isFull {
                        TwinkleCanvas(night: night)
                    }
                }
                .modifier(StarShift(depth: depth, quality: quality))
            }
        }
        // day: stars only in the top third, where the dawn sky is deepest
        .mask {
            if night {
                Color.white
            } else {
                LinearGradient(colors: [Color.white, Color.white.opacity(0)],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.38))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Slides one layer with the scroll and (at .full) against the tilt. Reads
/// the live values, so only this modifier - a transform - updates with them.
private struct StarShift: ViewModifier {
    let depth: StarDepth
    let quality: SpaceQuality

    private static let scrollCap: CGFloat = 36

    @MainActor
    private func shift() -> CGSize {
        var x: CGFloat = 0
        var y: CGFloat = 0
        if quality.drifts {
            let raw: CGFloat = SkyScroll.shared.offset * depth.scrollFactor
            let cap: CGFloat = StarShift.scrollCap
            let eased: Double = tanh(Double(raw / cap))
            y -= cap * CGFloat(eased)
        }
        let motion = PopOutMotion.shared
        if quality.isFull && motion.style == .live && depth.tiltBack > 0 {
            let rest: CGPoint = PopOutTuning.restEye
            let eye: CGPoint = motion.eye
            x -= (eye.x - rest.x) * depth.tiltBack
            y -= (eye.y - rest.y) * depth.tiltBack
        }
        return CGSize(width: x, height: y)
    }

    func body(content: Content) -> some View {
        content.offset(shift())
    }
}

/// One layer's stars, drawn once per size.
private struct StarLayerCanvas: View {
    let depth: StarDepth
    let night: Bool

    /// Past each edge, so a sliding layer never shows a bare strip.
    static let overscan: CGFloat = 56

    var body: some View {
        let depth: StarDepth = self.depth
        let night: Bool = self.night
        Canvas { context, size in
            StarLayerCanvas.draw(depth, night: night, in: &context, size: size)
        }
        .padding(-StarLayerCanvas.overscan)
    }

    static func draw(_ depth: StarDepth, night: Bool, in context: inout GraphicsContext, size: CGSize) {
        let height: CGFloat = max(1, size.height - 2 * overscan)
        let scale: CGFloat = CGFloat(SkyChart.scale(height: Float(height)))
        let cx: CGFloat = size.width / 2
        let cy: CGFloat = size.height / 2
        if depth == .far {
            drawBand(in: &context, size: size, scale: scale, night: night)
            drawClouds(in: &context, size: size, scale: scale, night: night)
        }
        let dim: Double = night ? 1 : 0.85
        for star in FlatSky.stars(depth) {
            let x: CGFloat = cx + CGFloat(star.at.x) * scale
            let y: CGFloat = cy + CGFloat(star.at.y) * scale
            guard x > -4 && y > -4 && x < size.width + 4 && y < size.height + 4 else { continue }
            let r: CGFloat = star.radius
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            let colour: Color = night ? FlatSky.colour(star.tint) : Color.white
            context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(star.alpha * dim)))
            if depth == .near && night {
                let g: CGFloat = r * 3.2
                let halo = CGRect(x: x - g, y: y - g, width: 2 * g, height: 2 * g)
                context.fill(Path(ellipseIn: halo), with: .color(colour.opacity(0.08)))
            }
        }
        if depth == .near {
            drawGlowStars(in: &context, size: size, scale: scale, night: night)
        }
    }

    /// The Milky Way: a soft band along the line where the map's band
    /// crosses the opening view.
    private static func drawBand(in context: inout GraphicsContext, size: CGSize,
                                 scale: CGFloat, night: Bool) {
        let cx: CGFloat = size.width / 2
        let cy: CGFloat = size.height / 2
        let slope: Double = Double(SkyChart.bandSlope)
        let offset: CGFloat = CGFloat(SkyChart.bandOffset) * scale
        let angle: Double = atan(slope)
        let half: CGFloat = 0.30 * scale
        let long: CGFloat = 4 * max(size.width, size.height)
        let glow: Color = night
            ? Color(red: 0.30, green: 0.36, blue: 0.66).opacity(0.20)
            : Color.white.opacity(0.22)
        var band = context
        band.translateBy(x: cx, y: cy + offset)
        band.rotate(by: .radians(angle))
        let rect = CGRect(x: -long / 2, y: -half, width: long, height: 2 * half)
        let colours: [Color] = [glow.opacity(0), glow, glow.opacity(0)]
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: colours), startPoint: CGPoint(x: 0, y: -half), endPoint: CGPoint(x: 0, y: half))
        band.fill(Path(rect), with: shading)
    }

    /// The map's own nebula clouds, where they fall in this view.
    private static func drawClouds(in context: inout GraphicsContext, size: CGSize,
                                   scale: CGFloat, night: Bool) {
        let cx: CGFloat = size.width / 2
        let cy: CGFloat = size.height / 2
        var glow = context
        glow.blendMode = night ? .plusLighter : .normal
        let boost: Double = night ? 2.2 : 1.2
        for cloud in SkyChart.clouds {
            guard let at = SkyChart.project(cloud.centre) else { continue }
            let x: CGFloat = cx + CGFloat(at.x) * scale
            let y: CGFloat = cy + CGFloat(at.y) * scale
            let r: CGFloat = CGFloat(cloud.reach) * scale
            guard x > -r && y > -r && x < size.width + r && y < size.height + r else { continue }
            let c: SIMD3<Float> = cloud.colour
            let red: Double = min(1, Double(c.x) * boost)
            let green: Double = min(1, Double(c.y) * boost)
            let blue: Double = min(1, Double(c.z) * boost)
            let hue = Color(red: red, green: green, blue: blue)
            let core: Color = night ? hue : hue.opacity(0.35)
            let colours: [Color] = [core, core.opacity(0)]
            let centre = CGPoint(x: x, y: y)
            let shading = GraphicsContext.Shading.radialGradient(
                Gradient(colors: colours), center: centre, startRadius: 0, endRadius: r)
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            glow.fill(Path(ellipseIn: rect), with: shading)
        }
    }

    /// The few bright blue-white stars with a small glow.
    private static func drawGlowStars(in context: inout GraphicsContext, size: CGSize,
                                      scale: CGFloat, night: Bool) {
        let cx: CGFloat = size.width / 2
        let cy: CGFloat = size.height / 2
        let tint: Color = night ? Color(red: 0.78, green: 0.85, blue: 1.0) : Color.white
        for star in SkyChart.glowStars {
            guard let at = SkyChart.project(star.dir) else { continue }
            let x: CGFloat = cx + CGFloat(at.x) * scale
            let y: CGFloat = cy + CGFloat(at.y) * scale
            guard x > 0 && y > 0 && x < size.width && y < size.height else { continue }
            let r: CGFloat = 7
            let colours: [Color] = [tint.opacity(0.55), tint.opacity(0)]
            let centre = CGPoint(x: x, y: y)
            let shading = GraphicsContext.Shading.radialGradient(
                Gradient(colors: colours), center: centre, startRadius: 0, endRadius: r)
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            context.fill(Path(ellipseIn: rect), with: shading)
            let dot = CGRect(x: x - 1.3, y: y - 1.3, width: 2.6, height: 2.6)
            context.fill(Path(ellipseIn: dot), with: .color(tint))
        }
    }
}

/// About forty near stars that twinkle: two sines at unrelated rates each,
/// on a 20 fps clock. Only at SpaceQuality.full.
private struct TwinkleCanvas: View {
    let night: Bool

    var body: some View {
        let night: Bool = self.night
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            let t: Double = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                TwinkleCanvas.draw(t: t, night: night, in: &context, size: size)
            }
        }
        .padding(-StarLayerCanvas.overscan)
    }

    static func draw(t: Double, night: Bool, in context: inout GraphicsContext, size: CGSize) {
        let height: CGFloat = max(1, size.height - 2 * StarLayerCanvas.overscan)
        let scale: CGFloat = CGFloat(SkyChart.scale(height: Float(height)))
        let cx: CGFloat = size.width / 2
        let cy: CGFloat = size.height / 2
        for (index, star) in FlatSky.twinklers.enumerated() {
            let x: CGFloat = cx + CGFloat(star.at.x) * scale
            let y: CGFloat = cy + CGFloat(star.at.y) * scale
            guard x > 0 && y > 0 && x < size.width && y < size.height else { continue }
            let i: Double = Double(index)
            let slow: Double = sin(t * (0.7 + 0.05 * i) + i * 1.7)
            let fast: Double = sin(t * (2.3 + 0.11 * i) + i * 0.9)
            let wave: Double = max(0, slow * fast)
            let alpha: Double = 0.75 * wave
            guard alpha > 0.02 else { continue }
            let r: CGFloat = 1.6
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            let colour: Color = night ? FlatSky.colour(star.tint) : Color.white
            context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(alpha)))
            let g: CGFloat = 4.5
            let halo = CGRect(x: x - g, y: y - g, width: 2 * g, height: 2 * g)
            context.fill(Path(ellipseIn: halo), with: .color(colour.opacity(alpha * 0.18)))
        }
    }
}
