import SwiftUI
import Charts

// The pictures on the Analytics page, kept apart so each can be read (and
// reused) on its own. All of them are drawn in the accent colour at a few
// strengths rather than in a spread of colours, so the page stays calm, and
// each one reads to VoiceOver as a single sentence rather than a pile of
// shapes.

/// One arc of a segmented ring: part of a whole, in its own colour.
struct RingSegment: Identifiable, Hashable {
    var value: Double
    var color: Color
    var label: String
    var id: String { label }
}

/// A circular progress bar with something in the middle and a label under it.
///
/// Filled to `value` out of `total` with a rounded end, or, when `segments`
/// is not empty, split into those parts one after another instead. `marker`
/// puts a small tick at a fraction of the way round - the pass mark on the
/// readiness ring. The fill sweeps in when it first appears, unless Reduce
/// Motion is on.
struct ProgressRing<Centre: View>: View {
    var value: Double
    var total: Double
    var segments: [RingSegment]
    var tint: Color
    var label: String
    /// Where the tick goes, 0...1, or nil for none.
    var marker: Double?
    /// What VoiceOver reads after the label, like "62 percent".
    var spoken: String
    var size: CGFloat
    var lineWidth: CGFloat
    /// A ring that can be pressed: it sits on a frosted disc that stands a
    /// little out of the glass (see `RingButtonStyle`). The ring itself and
    /// its fill never move on their own.
    var raised: Bool
    let centre: Centre

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ringPressed) private var pressed
    @State private var shown = false

    init(value: Double, total: Double = 1, segments: [RingSegment] = [], tint: Color = .accentColor,
         label: String, marker: Double? = nil, spoken: String = "", size: CGFloat = 64,
         lineWidth: CGFloat = 7, raised: Bool = false, @ViewBuilder centre: () -> Centre) {
        self.value = value
        self.total = total
        self.segments = segments
        self.tint = tint
        self.label = label
        self.marker = marker
        self.spoken = spoken
        self.size = size
        self.lineWidth = lineWidth
        self.raised = raised
        self.centre = centre()
    }

    /// How far round the plain fill goes, 0...1.
    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }

    /// Each segment's start and end as fractions of the way round.
    private var arcs: [RingArc] {
        var whole: Double = 0
        for segment in segments { whole += max(0, segment.value) }
        guard whole > 0 else { return [] }
        var start = 0.0
        var out: [RingArc] = []
        for segment in segments {
            let share: Double = max(0, segment.value) / whole
            let end: Double = start + share
            out.append(RingArc(segment: segment, start: start, end: end))
            start = end
        }
        return out
    }

    var body: some View {
        let grow: Double = (shown || reduceMotion) ? 1.0 : 0.0
        let filled: Double = fraction * grow
        let inset: CGFloat = lineWidth / 2
        let markerAngle: Double = min(1, max(0, marker ?? 0)) * 360
        let markerHeight: CGFloat = lineWidth + 6
        let markerOffset: CGFloat = -(size - lineWidth) / 2
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
                    .padding(inset)
                if segments.isEmpty {
                    Circle()
                        .trim(from: 0, to: filled)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                } else {
                    ForEach(arcs) { arc in
                        Circle()
                            .trim(from: arc.start * grow, to: arc.end * grow)
                            .stroke(arc.segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .padding(inset)
                    }
                }
                if let marker {
                    Capsule()
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: 2, height: markerHeight)
                        .offset(y: markerOffset)
                        .rotationEffect(.degrees(markerAngle))
                }
                centre
            }
            .frame(width: size, height: size)
            .modifier(RingDisc(raised: raised, pressed: pressed))
            if !label.isEmpty {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .onAppear {
            guard !shown else { return }
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.easeOut(duration: 0.9)) { shown = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken.isEmpty ? label : "\(label), \(spoken)")
    }
}

/// A pressable ring's disc: a frosted face under the ring, raised out of the
/// glass, sinking flat while pressed. A plain ring is left as it is.
private struct RingDisc: ViewModifier {
    let raised: Bool
    let pressed: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if raised {
            content
                .padding(3)
                .background(.regularMaterial, in: Circle())
                .popOut(.raised, in: Circle(), pressed: pressed)
        } else {
            content
        }
    }
}

private struct RingPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the button a raised ring belongs to is being pressed.
    var ringPressed: Bool {
        get { self[RingPressedKey.self] }
        set { self[RingPressedKey.self] = newValue }
    }
}

/// A ring (with `raised: true`) as a button: its disc sinks under the
/// finger, and the ring and its label lift under the pointer.
struct RingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return configuration.label
            .environment(\.ringPressed, configuration.isPressed)
            .contentShape(shape)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.lift)
    }
}

/// Where one segment of a ring starts and ends, as fractions of the way round.
struct RingArc: Identifiable {
    var segment: RingSegment
    var start: Double
    var end: Double
    var id: String { segment.id }
}

/// The number in the middle of a ring, with an optional small line under it.
struct RingCentre: View {
    var value: String
    var caption: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
            if let caption {
                Text(caption).font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 8)
    }
}

/// One day's accuracy on a sparkline.
struct SparkPoint: Identifiable, Hashable {
    var day: Date
    /// 0...1.
    var accuracy: Double
    var id: Date { day }
}

/// A tiny line of accuracy day by day, with no axes: the shape, not the numbers.
struct Sparkline: View {
    var points: [SparkPoint]
    var tint: Color = .accentColor

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Day", point.day), y: .value("Right", point.accuracy))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0.0...1.0)
        .frame(width: 90, height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard let first = points.first, let last = points.last else { return "No recent answers" }
        let from = Int((first.accuracy * 100).rounded())
        let to = Int((last.accuracy * 100).rounded())
        return "Last two weeks: from \(from) to \(to) percent right"
    }
}

/// Why marks were lost, as a donut with a legend under it.
struct ReasonDonut: View {
    var shares: [ReasonShare]

    /// The accent at a strength that steps down with each reason, commonest
    /// strongest.
    private func shade(_ index: Int) -> Color {
        let strength: Double = 0.9 - Double(index) * 0.16
        return Color.accentColor.opacity(max(0.25, strength))
    }

    var body: some View {
        let total: Int = shares.reduce(0) { (sum: Int, share: ReasonShare) -> Int in sum + share.count }
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Chart {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        SectorMark(angle: .value("Answers", share.count),
                                   innerRadius: .ratio(0.62), angularInset: 1.5)
                            .cornerRadius(3)
                            .foregroundStyle(shade(index))
                    }
                }
                VStack(spacing: 0) {
                    Text("\(total)").font(.title3.weight(.bold).monospacedDigit())
                    Text(total == 1 ? "reason" : "reasons").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(height: 150)

            ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(shade(index)).frame(width: 12, height: 12)
                    Label(share.reason.title, systemImage: share.reason.symbol)
                        .font(.caption)
                    Spacer(minLength: 8)
                    Text("\(Int((share.share * 100).rounded()))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let parts = shares.map { "\($0.reason.title) \(Int(($0.share * 100).rounded())) percent" }
        return "Why you lose marks: " + parts.joined(separator: ", ")
    }
}

/// How often each confidence level was right, against where it should be:
/// "Sure" right nearly every time, "Guess" about at chance.
struct CalibrationChart: View {
    var rows: [CalibrationRow]

    /// Roughly where a well-calibrated student would sit, in percent.
    static func ideal(_ confidence: AnswerConfidence) -> Double {
        switch confidence {
        case .sure: return 95
        case .maybe: return 65
        case .guess: return 25
        }
    }

    var body: some View {
        Chart {
            ForEach(rows) { row in
                BarMark(x: .value("Confidence", row.confidence.title),
                        y: .value("Right", row.accuracy * 100))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .cornerRadius(4)
            }
            ForEach(rows) { row in
                LineMark(x: .value("Confidence", row.confidence.title),
                         y: .value("Ideal", Self.ideal(row.confidence)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary)
                PointMark(x: .value("Confidence", row.confidence.title),
                          y: .value("Ideal", Self.ideal(row.confidence)))
                    .foregroundStyle(Color.secondary)
                    .symbolSize(20)
            }
        }
        .chartYScale(domain: 0.0...100.0)
        .chartYAxis {
            AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    Text("\(Int(value.as(Double.self) ?? 0))%")
                }
            }
        }
        .frame(height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let parts = rows.map { row in
            "\(row.confidence.title): \(Int((row.accuracy * 100).rounded())) percent right, ideal about \(Int(Self.ideal(row.confidence)))"
        }
        return "Accuracy by confidence. " + parts.joined(separator: ". ")
    }
}

/// Twelve weeks of study as a calendar grid, a column a week, shaded by how
/// much was done each day, with today outlined.
struct StudyHeatmap: View {
    /// Amount studied per day, keyed like StudyLog (`yyyy-MM-dd`).
    var counts: [String: Int]
    var weeks: Int = 12

    private struct Cell: Identifiable {
        var date: Date
        var key: String
        var count: Int
        var isToday: Bool
        var isFuture: Bool
        var id: String { key }
    }

    /// Columns of seven days, oldest week first, starting on the calendar's
    /// first weekday.
    private var columns: [[Cell]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let first = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisWeek) ?? thisWeek
        var out: [[Cell]] = []
        for column in 0..<weeks {
            var cells: [Cell] = []
            for row in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: column * 7 + row, to: first) else { continue }
                let key = StudyLog.key(for: date)
                cells.append(Cell(date: date, key: key, count: counts[key] ?? 0,
                                  isToday: calendar.isDate(date, inSameDayAs: today),
                                  isFuture: date > today))
            }
            out.append(cells)
        }
        return out
    }

    private static let legendLevels: [Double] = [0.0, 0.3, 0.6, 1.0]

    private static func legendShade(_ level: Double) -> Color {
        guard level > 0 else { return Color.primary.opacity(0.07) }
        let strength: Double = 0.25 + 0.7 * level
        return Color.accentColor.opacity(strength)
    }

    private func shade(_ count: Int, busiest: Int) -> Color {
        guard count > 0, busiest > 0 else { return Color.primary.opacity(0.07) }
        let level: Double = Double(count) / Double(busiest)
        let strength: Double = 0.25 + 0.7 * min(1, level)
        return Color.accentColor.opacity(strength)
    }

    var body: some View {
        let grid = columns
        let cells = grid.flatMap { $0 }.filter { !$0.isFuture }
        let busiest = cells.map(\.count).max() ?? 0
        let studied = cells.filter { $0.count > 0 }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: 3) {
                        ForEach(column) { cell in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cell.isFuture ? Color.clear : shade(cell.count, busiest: busiest))
                                .overlay {
                                    if cell.isToday {
                                        RoundedRectangle(cornerRadius: 3)
                                            .strokeBorder(Color.primary.opacity(0.7), lineWidth: 1.5)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            .frame(maxWidth: 320)
            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(Self.legendLevels, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.legendShade(level))
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Study calendar, last \(weeks) weeks: something studied on \(studied) day\(studied == 1 ? "" : "s"), at most \(busiest) in a day.")
    }
}
