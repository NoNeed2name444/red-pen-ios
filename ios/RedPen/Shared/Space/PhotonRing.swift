import SwiftUI

// MARK: - Photon rings
//
// The 3D map's black-hole look, in daily use: a score or readiness ring is a
// thin photon ring running from deep ember through orange and gold to
// white-gold as it fills (the map's own palette, GraphArt), over a soft glow
// of itself, brighter on the right - the Doppler side, as the map's disks
// fake it - with a hot tip where the fill ends.
//
// Colour is never the only cue: the fill's length and the number in the
// middle say the same thing. With Increase Contrast it is a plain solid arc
// without the glow; in light mode the palette stops at a deeper gold, as
// white-gold vanishes on a pale page.

enum PhotonPalette {
    static func colour(_ c: SIMD3<Float>) -> Color {
        Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }

    static var ember: Color { colour(GraphArt.ember) }
    static var orange: Color { colour(GraphArt.orange) }
    static var gold: Color { colour(GraphArt.gold) }
    static var whiteHot: Color { colour(GraphArt.whiteHot) }
    static let deepGold = Color(red: 0.86, green: 0.58, blue: 0.08)

    /// Around the whole ring, 0 at the start of the fill.
    static func stops(dark: Bool) -> [Gradient.Stop] {
        let top: Color = dark ? whiteHot : deepGold
        let high: Color = dark ? gold : Color(red: 0.93, green: 0.52, blue: 0.05)
        return [
            Gradient.Stop(color: ember, location: 0),
            Gradient.Stop(color: orange, location: 0.35),
            Gradient.Stop(color: high, location: 0.72),
            Gradient.Stop(color: top, location: 1)
        ]
    }
}

/// The arc of a photon ring, filled to `fraction`, drawn inside its frame
/// (the stroke never spills past the edge).
struct PhotonArc: View {
    let fraction: Double
    let lineWidth: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark: Bool = scheme == .dark
        let strong: Bool = contrast == .increased
        let shown: Double = min(1, max(0, fraction))
        let stops: [Gradient.Stop] = PhotonPalette.stops(dark: dark)
        let gradient = AngularGradient(stops: stops, center: .center,
                                       startAngle: .degrees(0), endAngle: .degrees(360))
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        let glowStyle = StrokeStyle(lineWidth: lineWidth * 2.4, lineCap: .round)
        let glowAlpha: Double = dark ? 0.55 : 0.28
        let doppler: Double = dark ? 0.35 : 0.18
        let tipSize: CGFloat = lineWidth * 1.9
        ZStack {
            if !strong {
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(gradient, style: glowStyle)
                    .rotationEffect(.degrees(-90))
                    .blur(radius: lineWidth * 1.2)
                    .opacity(glowAlpha)
            }
            Circle()
                .trim(from: 0, to: shown)
                .stroke(strong ? AnyShapeStyle(PhotonPalette.orange) : AnyShapeStyle(gradient), style: style)
                .rotationEffect(.degrees(-90))
            if !strong {
                // the Doppler side: the right half a touch brighter
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(Color.white.opacity(doppler), style: StrokeStyle(lineWidth: lineWidth * 0.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .mask {
                        LinearGradient(colors: [Color.clear, Color.white], startPoint: .center, endPoint: .trailing)
                    }
                PhotonTip(size: tipSize, dark: dark)
                    .opacity(shown > 0.02 ? 1 : 0)
                    .rotationEffect(.degrees(shown * 360))
            }
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// The hot spot at the end of the fill: at the top of its frame, so a
/// rotation by the fill angle puts it at the tip.
private struct PhotonTip: View {
    let size: CGFloat
    let dark: Bool

    var body: some View {
        let core: Color = dark ? PhotonPalette.whiteHot : PhotonPalette.deepGold
        Circle()
            .fill(RadialGradient(colors: [core, core.opacity(0)], center: .center,
                                 startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .offset(y: -size / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .blendMode(dark ? .plusLighter : .normal)
    }
}

// MARK: - The aurora on a strong finish

/// Two or three curtains across the top of a finish screen: anisotropic
/// noise - slow sideways, fast along the rays - oxygen green (557.7 nm) at
/// the foot fading to red (630 nm) at the top. It moves for 2.5 s at 20 fps
/// at SpaceQuality.full, then holds still; otherwise it is drawn still.
struct AuroraCurtain: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.spaceQuality) private var quality
    @State private var start = Date()
    @State private var running = true

    static let playFor: TimeInterval = 2.5

    var body: some View {
        let dark: Bool = scheme == .dark
        let moving: Bool = quality.isFull && running
        let start: Date = self.start
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !moving)) { timeline in
            let elapsed: Double = moving ? timeline.date.timeIntervalSince(start) : AuroraCurtain.playFor
            let t: Double = min(AuroraCurtain.playFor, elapsed)
            Canvas { context, size in
                AuroraCurtain.draw(t: t, dark: dark, in: &context, size: size)
            }
        }
        .mask {
            LinearGradient(colors: [Color.clear, Color.white, Color.white, Color.clear],
                           startPoint: .leading, endPoint: .trailing)
        }
        .opacity(dark ? 0.85 : 0.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            start = Date()
            let wait: UInt64 = UInt64(AuroraCurtain.playFor * 1_000_000_000)
            try? await Task.sleep(nanoseconds: wait)
            running = false
        }
    }

    static func draw(t: Double, dark: Bool, in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        var glow = context
        glow.blendMode = dark ? .plusLighter : .normal
        let green = Color(red: 0.30, green: 1.0, blue: 0.62)
        let red = Color(red: 0.95, green: 0.28, blue: 0.42)
        let step: CGFloat = 3
        let columns: Int = Int(size.width / step) + 1
        for curtain in 0..<3 {
            let c: Double = Double(curtain)
            let shift: Double = t * (0.25 + 0.08 * c)
            for column in 0..<columns {
                let x: CGFloat = CGFloat(column) * step
                let sx: Double = Double(x) / Double(size.width)
                let broad: Double = sin(sx * 4.1 + c * 1.9 + shift)
                let ripple: Double = sin(sx * 9.3 - shift * 1.3 + c)
                let sway: Double = broad + 0.5 * ripple
                let footShare: Double = 0.62 + 0.10 * sway
                let foot: CGFloat = size.height * CGFloat(footShare)
                let rayA: Double = sin(sx * 61 + c * 17 + t * 1.7)
                let rayB: Double = sin(sx * 23 - c * 5 + t * 0.9)
                let ray: Double = max(0, 0.55 + 0.3 * rayA + 0.25 * rayB)
                let tallShare: Double = 0.28 + 0.30 * ray
                let tall: CGFloat = size.height * CGFloat(tallShare)
                let strength: Double = ray * (0.20 - 0.04 * c)
                guard strength > 0.01 else { continue }
                let top: CGFloat = foot - tall
                let rect = CGRect(x: x, y: top, width: step + 0.5, height: tall)
                let colours: [Color] = [red.opacity(0), red.opacity(strength * 0.5),
                                        green.opacity(strength), green.opacity(0)]
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: colours), startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: foot))
                glow.fill(Path(rect), with: shading)
            }
        }
    }
}

/// How strong a finish was (0...1), reported upwards by a score ring so the
/// finish around it can celebrate a good one.
struct FinishScoreKey: PreferenceKey {
    static let defaultValue: Double? = nil
    static func reduce(value: inout Double?, nextValue: () -> Double?) {
        if let next = nextValue() { value = next }
    }
}
