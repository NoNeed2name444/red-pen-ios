import SwiftUI

// The top of the Vitals screen (docs/design/targets-2026-10-01.md §1,
// "Progress as vitals"): the study rhythm on a dark monitor, four rings, and
// the subjects that need a consult with the one button that treats them.
// AnalyticsView puts them above its Focus next, readiness, trends, mistakes,
// subjects and time; the numbers are its own.

/// The monitor, laid out like a bedside monitor (the owner, 22 Oct: "make it
/// like the monitor"): a status strip along the top - "Study rhythm · Sinus ·
/// Regular" on the left, the streak with its heart on the right where a
/// monitor shows the heart rate's beat - then the screen itself, the last two
/// weeks as a green trace (a beat for each day studied) filling the channel
/// on the left, and the parameter column on the right, each readout its
/// label over its big number in the parameter's own colour, parted by thin
/// rules: readiness, accuracy, and questions today against the day's target.
/// The line under them says what the trace means. A dark panel in both
/// modes, its colours the ten hexes'. At the accessibility text sizes the
/// column moves under the trace.
struct RhythmMonitor: View {
    let reading: RhythmReading.Reading
    /// 0...1, or nil before there is an estimate.
    let readiness: Double?
    /// The last 30 days, 0...1, or nil with no answers.
    let accuracy: Double?
    let today: Int
    let target: Int
    let streak: Int

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The trace's height when the column stands under it (the accessibility
    /// sizes). Beside the column, the trace and its divider take the column's
    /// own height at every text size.
    static let channel: CGFloat = 112
    /// The parameter column's width.
    static let column: CGFloat = 112

    var body: some View {
        // a List row: the bezel as low as the tiles round it
        MonitorCard(lift: .low) {
            VStack(alignment: .leading, spacing: WardSpace.m) {
                statusStrip
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: WardSpace.m) {
                        trace
                            .frame(height: RhythmMonitor.channel)
                        readouts
                    }
                } else {
                    // as tall as the readouts, whatever the text size: the
                    // row takes the column's height and the trace and the
                    // divider fill it
                    HStack(alignment: .top, spacing: WardSpace.m) {
                        trace
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Rectangle()
                            .fill(Color.wardHairline)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                        readouts
                            .frame(width: RhythmMonitor.column)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text(reading.line)
                    .font(.footnote)
                    .foregroundStyle(Color.wardInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The monitor's top line: what the trace is, and the beat.
    private var statusStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: WardSpace.s) {
            Text("Study rhythm \u{00B7} " + reading.words)
                .wardSmallCaps()
            Spacer(minLength: WardSpace.s)
            streakReading
        }
    }

    /// The trace; its height is set where it stands.
    private var trace: some View {
        RhythmTrace(beats: reading.beats)
            .stroke(Color.wardSuccess, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    /// The parameter column: each readout a label over its number, parted by
    /// thin rules, as a monitor stacks its parameters.
    private var readouts: some View {
        VStack(alignment: .leading, spacing: WardSpace.xs) {
            MonitorReading(label: "RDY", value: RhythmMonitor.percent(readiness), tint: Color.wardBeam)
            Rectangle().fill(Color.wardHairline).frame(height: 1)
            MonitorReading(label: "ACC", value: RhythmMonitor.percent(accuracy), tint: Color.wardSuccess)
            Rectangle().fill(Color.wardHairline).frame(height: 1)
            MonitorReading(label: "Q/D", value: "\(today)/\(target)", tint: Color.wardInk)
        }
    }

    private var streakReading: some View {
        let words: String = streak > 0 ? "\(streak) day streak" : "No streak yet"
        return HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .foregroundStyle(Color.wardEcg)
            Text(words)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
        }
    }

    private var spoken: String {
        var parts: [String] = [reading.spoken]
        if let readiness { parts.append("Readiness \(Int((readiness * 100).rounded())) percent") }
        if let accuracy { parts.append("Accuracy \(Int((accuracy * 100).rounded())) percent over 30 days") }
        parts.append("\(today) of \(target) studied today")
        if streak > 0 { parts.append("\(streak)-day streak") }
        return parts.joined(separator: ". ")
    }

    /// "68%", or a dash with nothing to show.
    static func percent(_ value: Double?) -> String {
        guard let value else { return "\u{2013}" }
        return "\(Int((value * 100).rounded()))%"
    }
}

/// One parameter on the monitor: its label at the top left and its number
/// large at the right, both in the parameter's colour.
private struct MonitorReading: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2.weight(.semibold))
            Text(value)
                .font(WardType.obsLarge)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(tint)
    }
}

/// The four rings: Readiness (Pager Amber), Accuracy over 30 days (Discharge
/// Green), Syllabus covered (ECG Red) and Today against the day's target
/// (the section's accent). Each is a button into what is behind it. Four across;
/// two by two at the largest text sizes.
struct VitalsRings: View {
    let readiness: ReadinessEstimate?
    let accuracy: Double?
    /// Answers the accuracy is over.
    let answered: Int
    /// The share of the exam's topics covered, once the check has run.
    let syllabus: Double?
    let syllabusSpoken: String
    let today: Int
    let target: Int
    let onReadiness: () -> Void
    let onAccuracy: () -> Void
    let onSyllabus: () -> Void
    let onToday: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let count: Int = typeSize.isAccessibilitySize ? 2 : 4
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: WardSpace.s), count: count)
        LazyVGrid(columns: columns, spacing: WardSpace.m) {
            ringButton(readinessRing, hint: "Shows the readiness estimate", action: onReadiness)
            ringButton(accuracyRing, hint: "Shows accuracy subject by subject", action: onAccuracy)
            ringButton(syllabusRing, hint: "Opens the syllabus check", action: onSyllabus)
            ringButton(todayRing, hint: "Opens the cards due today", action: onToday)
        }
    }

    private func ringButton<Ring: View>(_ ring: Ring, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ring
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 120)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressableRow)
        .accessibilityHint(hint)
    }

    private var readinessRing: WardRing {
        let spoken: String
        if let readiness {
            let centre: Int = Int((readiness.center * 100).rounded())
            let mark: Int = Int((readiness.passMark * 100).rounded())
            spoken = "estimated \(centre) percent, pass mark about \(mark) percent"
        } else {
            spoken = "answer at least \(Readiness.minimumAnswers) questions for an estimate"
        }
        return WardRing(value: readiness?.center ?? 0, tone: .amber, label: "Readiness",
                        centre: readiness == nil ? "\u{2013}" : nil, spoken: spoken)
    }

    private var accuracyRing: WardRing {
        let spoken: String
        if let accuracy {
            spoken = "\(Int((accuracy * 100).rounded())) percent of \(answered) answers right, last 30 days"
        } else {
            spoken = "no answers yet"
        }
        return WardRing(value: accuracy ?? 0, tone: .green, label: "Accuracy",
                        centre: accuracy == nil ? "\u{2013}" : nil, spoken: spoken)
    }

    private var syllabusRing: WardRing {
        WardRing(value: syllabus ?? 0, tone: .red, label: "Syllabus",
                 centre: syllabus == nil ? "\u{2026}" : nil, spoken: syllabusSpoken)
    }

    private var todayRing: WardRing {
        let share: Double = target > 0 ? Double(today) / Double(target) : 0
        return WardRing(value: share, tone: .blue, label: "Today",
                        centre: "\(today)", spoken: "\(today) of \(target) studied today")
    }
}

/// "Weak topics": the weakest subjects as chips with their percentage,
/// each a drill of that subject; a line saying what today's revision does
/// about them (BedPlan.consultNote); and "Practise weak topics", the drill
/// of the weakest - the same drill as Drill weakest and the Weakest topic
/// tile.
struct ConsultCard: View {
    let spots: [BedPlan.Topic]
    let note: String
    let onDrill: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.m) {
            Text("Weak topics")
                .wardSmallCaps()
                .accessibilityAddTraits(.isHeader)
            if !spots.isEmpty {
                ConsultFlow(spacing: WardSpace.s) {
                    ForEach(spots, id: \.name) { spot in
                        chip(spot)
                    }
                }
            }
            Text(note)
                .font(.footnote)
                .foregroundStyle(Color.wardInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let first = spots.first {
                treatButton(first)
            }
        }
        // a List row: as low as the tiles round it, the button proud of it
        .wardCard(lift: .low)
    }

    private func chip(_ spot: BedPlan.Topic) -> some View {
        Button { onDrill(spot.name) } label: {
            WardChip(text: "\(spot.name) \(spot.percent)%", tone: .danger)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressableRow)
        .accessibilityLabel("\(spot.name), \(spot.percent) percent")
        .accessibilityHint("Opens a drill of \(spot.name)")
    }

    private func treatButton(_ first: BedPlan.Topic) -> some View {
        Button { onDrill(first.name) } label: {
            Label("Practise weak topics", systemImage: "cross.case.fill")
        }
        .buttonStyle(.wardPrimary)
        .accessibilityHint("Up to 20 questions from \(first.name), the ones you got wrong first")
        .accessibilityIdentifier("treatWeakSpots")
    }
}

/// Chips laid left to right, wrapping onto new lines; a chip wider than the
/// line is given the line's width, so a long subject wraps inside its chip
/// rather than running off the card.
struct ConsultFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit: CGFloat = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size: CGSize = ConsultFlow.size(of: view, limit: limit)
            if x > 0 && x + size.width > limit {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, limit), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var line: CGFloat = 0
        for view in subviews {
            let size: CGSize = ConsultFlow.size(of: view, limit: bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }

    /// A chip's own size, but never wider than the line.
    private static func size(of view: LayoutSubview, limit: CGFloat) -> CGSize {
        let natural: CGSize = view.sizeThatFits(.unspecified)
        guard limit.isFinite, natural.width > limit else { return natural }
        return view.sizeThatFits(ProposedViewSize(width: limit, height: nil))
    }
}
