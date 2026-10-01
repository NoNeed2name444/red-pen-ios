#if canImport(SwiftUI)
import SwiftUI

/// A readiness ring: a hairline track and the tone's arc, the number in the
/// middle in SF Mono so it reads as an observation.
struct WardRing: View {
    let value: Double
    var tone: WardTone = .blue
    var label: String?
    var lineWidth: CGFloat = 8
    @ScaledMetric(relativeTo: .title2) private var numeral: CGFloat = 26

    var body: some View {
        let v: Double = max(0, min(1, value))
        ZStack {
            Circle().stroke(Color.wardHairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: v)
                .stroke(tone.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((v * 100).rounded()))%")
                    .font(.system(size: numeral, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.wardInk)
                if let label { Text(label).font(.caption2).foregroundStyle(Color.wardInkSecondary) }
            }
            .padding(lineWidth)
            .minimumScaleFactor(0.5)
        }
        .padding(lineWidth / 2)
        .animation(.easeOut(duration: 0.6), value: v)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Progress")
        .accessibilityValue("\(Int((v * 100).rounded())) percent")
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
/// goes on: a hairline track and a Pager Amber beam.
struct EcgStrip: View {
    let progress: Double
    var tone: Color = .wardBeam

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.wardHairline)
                Capsule().fill(tone).frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: 4)
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
