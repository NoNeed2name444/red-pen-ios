#if canImport(SwiftUI)
import SwiftUI

/// A readiness ring: the tone's arc running in a groove pressed into the
/// base, the number in the middle in SF Mono so it reads as an observation.
///
/// `centre` stands in for the percentage when the ring counts something
/// else (Today: 18) or has nothing to show yet (a dash), and `spoken` for
/// "68 percent" when it does.
struct WardRing: View {
    let value: Double
    var tone: WardTone = .blue
    var label: String?
    var lineWidth: CGFloat = 8
    var centre: String?
    var spoken: String?
    @ScaledMetric(relativeTo: .title2) private var numeral: CGFloat = 26

    init(value: Double, tone: WardTone = .blue, label: String? = nil, lineWidth: CGFloat = 8,
         centre: String? = nil, spoken: String? = nil) {
        self.value = value
        self.tone = tone
        self.label = label
        self.lineWidth = lineWidth
        self.centre = centre
        self.spoken = spoken
    }

    var body: some View {
        let v: Double = max(0, min(1, value))
        let percent: Int = Int((v * 100).rounded())
        let shown: String = centre ?? "\(percent)%"
        // the groove is the arc's width and a little clearance either side
        let clear: CGFloat = min(2, lineWidth / 3)
        ZStack {
            Circle()
                .trim(from: 0, to: v)
                .stroke(tone.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(shown)
                    .font(.system(size: numeral, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.wardInk)
                if let label { Text(label).font(.caption2).lineLimit(1).foregroundStyle(Color.wardInkSecondary) }
            }
            .padding(lineWidth)
            .minimumScaleFactor(0.5)
        }
        .padding(lineWidth / 2 + clear)
        .background {
            WardReliefFace(shape: WardAnnulus(width: lineWidth + 2 * clear), lift: .low, inset: true)
        }
        .animation(.easeOut(duration: 0.6), value: v)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Progress")
        .accessibilityValue(spoken ?? "\(percent) percent")
    }
}

/// A ring `width` wide just inside the frame's circle: a shape with a hole,
/// the two circles drawn in opposite directions, so a fill (and the lights a
/// groove is drawn with) covers the ring alone.
struct WardAnnulus: InsettableShape {
    var width: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer: CGFloat = min(rect.width, rect.height) / 2 - insetAmount
        let hole: CGFloat = min(rect.width, rect.height) / 2 - width + insetAmount
        var p = Path()
        guard outer > 0 else { return p }
        p.addArc(center: centre, radius: outer, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()
        if hole > 0 && hole < outer {
            p.move(to: CGPoint(x: centre.x + hole, y: centre.y))
            p.addArc(center: centre, radius: hole, startAngle: .degrees(360), endAngle: .degrees(0), clockwise: true)
            p.closeSubpath()
        }
        return p
    }

    func inset(by amount: CGFloat) -> WardAnnulus {
        var ring = self
        ring.insetAmount += amount
        return ring
    }
}

/// One ECG complex, for the app name and the vitals tile.
struct EcgSquiggle: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, mid = rect.midY
        let points: [(CGFloat, CGFloat)] = [
            (0, 0), (0.30, 0), (0.36, -0.12), (0.42, 0), (0.48, 0.10), (0.54, -0.50),
            (0.60, 0.30), (0.66, 0), (0.78, -0.14), (0.88, 0), (1, 0),
        ]
        var p = Path()
        for (i, pt) in points.enumerated() {
            let q = CGPoint(x: rect.minX + pt.0 * w, y: mid + pt.1 * h)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }
}

/// The amber strip under a study screen's title that fills as the paper
/// goes on: a Pager Amber beam in a groove pressed into the base.
struct EcgStrip: View {
    let progress: Double
    var tone: Color = .wardBeam

    var body: some View {
        WardGroove(fraction: progress, tint: tone, height: 6)
            .animation(.easeOut(duration: 0.3), value: progress)
            .accessibilityHidden(true)
    }
}

/// An observation: a small-caps label over a mono value, flagged high or low.
struct ObsValue: View {
    enum Flag { case high, low }
    let label: String
    let value: String
    var flag: Flag?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).wardSmallCaps()
            HStack(spacing: 4) {
                Text(value).font(WardType.obs.weight(.semibold)).foregroundStyle(flag == nil ? Color.wardInk : Color.wardDanger)
                if let flag {
                    Image(systemName: flag == .high ? "arrow.up" : "arrow.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.wardDanger)
                        .accessibilityLabel(flag == .high ? "high" : "low")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A spinner for "working": a squiggle that draws itself, still under
/// Reduce Motion.
struct EcgLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    var body: some View {
        EcgSquiggle()
            .trim(from: 0, to: reduceMotion ? 1 : drawn)
            .stroke(Color.wardEcg, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 64, height: 24)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) { drawn = 1 }
            }
            .accessibilityLabel("Working")
    }
}
#endif
