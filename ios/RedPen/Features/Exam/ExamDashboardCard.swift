import SwiftUI

/// The chosen exam at a glance: the countdown, the predicted score against
/// the pass mark, the blueprint's biggest areas with how well the library
/// covers each, and what to study next - each a tap from a new question set
/// written to the exam's format.
///
/// Everything is worked out from the student's own library and answers
/// (ExamBlueprint over the coverage engine) and says it is an estimate.
struct ExamDashboardCard: View {
    @EnvironmentObject private var store: Store
    @State private var standings: [BlueprintStanding] = []
    @State private var picking = false
    @State private var preset: NewSetPreset?
    @State private var version = 0

    private var exam: TargetExam? { ExamChoice.current }

    /// Re-assess when the exam, the library or the answers change.
    private var key: String {
        let edited: Double = store.library.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let answers: Int = store.answerHistory.values.reduce(0) { $0 + $1.count }
        let chosen: String = (exam?.id ?? "-") + "/" + (ExamChoice.currentSecondary?.id ?? "-")
        return "\(chosen)-\(store.library.count)-\(edited)-\(answers)-\(version)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let exam {
                header(exam)
                if !standings.isEmpty {
                    scoreLine(exam)
                    bars
                    nextUp(exam)
                } else {
                    EcgLoader().frame(maxWidth: .infinity)
                }
                Text(ExamDashboardCard.sourceNote(exam))
                    .font(.caption2)
                    .foregroundStyle(Color.wardInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                chooseFirst
            }
        }
        .padding(.vertical, 6)
        .task(id: key) { await assess() }
        .sheet(isPresented: $picking) {
            NavigationStack { ExamPickerView(onDone: { version += 1 }) }
        }
        .sheet(item: $preset) { NewSetView(preset: $0) }
        .accessibilityIdentifier("examDashboard")
    }

    // MARK: - Pieces

    private var chooseFirst: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Which exam are you preparing for?", systemImage: "graduationcap")
                .font(.headline)
                .foregroundStyle(Color.wardInk)
            Text("Pick it and questions, the plan, the coverage map and mock papers follow its format and blueprint.")
                .font(.subheadline)
                .foregroundStyle(Color.wardInkSecondary)
            Button("Choose your exam") { picking = true }
                .buttonStyle(.wardCompact)
                .accessibilityIdentifier("examDashboardChoose")
        }
    }

    private func header(_ exam: TargetExam) -> some View {
        let days: Int? = ExamDashboardCard.daysLeft()
        let countdown: String = days.map { $0 <= 0 ? "Today" : "T-\($0)" } ?? "No date"
        let second: String? = ExamChoice.currentSecondary.map { "with \($0.shortName)" }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.name).font(.headline).foregroundStyle(Color.wardInk)
                if let second {
                    Text(second).font(.caption).foregroundStyle(Color.wardInkSecondary)
                }
            }
            Spacer(minLength: 8)
            WardPill(text: countdown)
                .monospacedDigit()
                .accessibilityLabel(days.map { "\($0) days to go" } ?? "No exam date")
            Button { picking = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color.wardPrimaryInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Change exam")
            .accessibilityIdentifier("examDashboardChange")
        }
    }

    private func scoreLine(_ exam: TargetExam) -> some View {
        let predicted: Double = ExamBlueprint.predictedScore(standings)
        let covered: Double = ExamBlueprint.weightedCoverage(standings)
        let above: Bool = predicted >= exam.passMark
        let line: String = "Predicted ~\(ExamDashboardCard.percent(predicted)) \u{00B7} pass mark ~\(ExamDashboardCard.percent(exam.passMark)) \u{00B7} blueprint covered \(ExamDashboardCard.percent(covered))"
        return VStack(alignment: .leading, spacing: 6) {
            WardProgressBar(value: predicted, label: "Predicted score")
            WardChip(text: above ? "Above the pass mark" : "Below the pass mark",
                     tone: above ? .green : .warning,
                     symbol: above ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(line)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.wardInkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The six biggest areas: share, coverage bar, readiness.
    private var bars: some View {
        let top: [BlueprintStanding] = Array(standings.filter { $0.area.percent > 0 }.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            WardSectionLabel("Blueprint")
            ForEach(top) { s in
                BlueprintBar(standing: s)
            }
        }
    }

    private func nextUp(_ exam: TargetExam) -> some View {
        let next: [BlueprintStanding] = ExamBlueprint.studyNext(standings, limit: 3)
        return VStack(alignment: .leading, spacing: 6) {
            WardSectionLabel("Study next")
            ForEach(next) { s in
                Button {
                    preset = NewSetPreset(blueprintArea: s.area.title, exam: exam)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(Color.wardPrimaryInk).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.area.title).foregroundStyle(Color.wardInk)
                            Text(ExamDashboardCard.why(s)).font(.caption).monospacedDigit()
                                .foregroundStyle(Color.wardInkSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "plus.circle").foregroundStyle(Color.wardPrimaryInk).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Makes a question set on it in \(exam.shortName) format")
            }
        }
    }

    // MARK: - Working it out

    private func assess() async {
        guard let exam else {
            standings = []
            return
        }
        let plan: [BlueprintArea] = ExamBlueprint.plan(primary: exam, secondary: ExamChoice.currentSecondary)
        let library: [StudySet] = store.library
        let history: [UUID: [Bool]] = store.answerHistory
        let result: [BlueprintStanding] = await Task.detached(priority: .utility) {
            let assessed: [AreaCoverage] = CoverageEngine.assess(library: library, history: history,
                                                                 areas: ExamBlueprint.syllabus(plan))
            return ExamBlueprint.standings(plan: plan, assessed: assessed)
        }.value
        guard !Task.isCancelled else { return }
        standings = result
    }

    // MARK: - Words

    static func daysLeft() -> Int? {
        guard let date = ExamCap.storedDate() else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                       to: calendar.startOfDay(for: date)).day
    }

    static func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

    /// "12% of the exam · 40% covered · 3 of 9 right".
    static func why(_ s: BlueprintStanding) -> String {
        var parts: [String] = []
        if s.area.percent > 0 {
            parts.append("\(Int(s.area.percent.rounded()))% of the exam")
        } else {
            parts.append("second exam")
        }
        parts.append("\(percent(s.coverage)) covered")
        if s.answered > 0 { parts.append("\(s.correct) of \(s.answered) right") }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func sourceNote(_ exam: TargetExam) -> String {
        let kind: String = exam.blueprintIsApproximate ? "Approximate weights" : "Weights"
        return "\(kind) from \(exam.blueprintSource). Readiness is an estimate from your own library and answers. \(exam.passNote)"
    }
}

/// One blueprint area: its share, its readiness, and a bar of how much is
/// covered.
struct BlueprintBar: View {
    let standing: BlueprintStanding

    var body: some View {
        let share: String = "\(Int(standing.area.percent.rounded()))%"
        let ready: String = ExamDashboardCard.percent(standing.readiness) + " ready"
        let readyTone: WardTone = standing.readiness >= 0.6 ? .green : (standing.readiness >= 0.45 ? .warning : .danger)
        let spoken: String = "\(standing.area.title), \(share) of the exam, \(ExamDashboardCard.percent(standing.coverage)) covered, readiness \(ExamDashboardCard.percent(standing.readiness))"
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(standing.area.title).font(.caption).lineLimit(1).foregroundStyle(Color.wardInk)
                Spacer(minLength: 6)
                Text(ready).font(.system(.caption2, design: .monospaced)).foregroundStyle(readyTone.color)
                Text(share).font(.system(.caption, design: .monospaced)).foregroundStyle(Color.wardInkSecondary)
            }
            WardProgressBar(value: standing.coverage, label: standing.area.title)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
