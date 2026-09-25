import SwiftUI

/// The end of a mock: the score against the exam's rough pass mark, marks by
/// subject (weakest first), the pace, and every question with its answer -
/// the feedback the paper held back.
struct MockResultsView: View {
    let result: MockResult
    let sitting: MockSitting
    let selected: [UUID: Int]
    let minutesUsed: Int
    let onDone: () -> Void

    @State private var practising: StudySet?
    @State private var showAll = false

    private var percent: Int { Int((result.fraction * 100).rounded()) }

    private var verdict: String {
        let mark: Int = Int((result.passMark * 100).rounded())
        let side: String = result.passed ? "above" : "below"
        return "\(side.capitalized) the rough pass mark of about \(mark)%. Pass marks move from sitting to sitting, so read it as a guide."
    }

    /// Every question sat, in paper order, with where it came from.
    private var allPicks: [QuestionPick] { sitting.picks.flatMap { $0 } }

    private var missed: [QuestionPick] {
        allPicks.filter { selected[$0.question.id] != $0.question.correctIndex }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FinishHero(title: "\(result.correct) of \(result.total) right", message: verdict) {
                    ScoreRing(fraction: result.fraction, label: "\(percent)%", sublabel: "score")
                }
                .contentCard()
                if result.total < sitting.wanted {
                    Label("A shortened paper: \(result.total) of the real \(sitting.wanted) questions.",
                          systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                facts
                subjects
                review
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .studyBar { bar }
        .navigationDestination(item: $practising) { set in
            MCQQuizView(set: set, keepsProgress: false)
        }
    }

    private var facts: some View {
        let pace: Int = Int(result.secondsPerQuestion.rounded())
        let flaggedCount: Int = result.marks.filter(\.flagged).count
        return VStack(alignment: .leading, spacing: 8) {
            factRow("Unanswered", "\(result.unanswered)", symbol: "circle.dashed")
            factRow("Flagged", "\(flaggedCount)", symbol: "flag")
            factRow("Time used", MockPaperView.hours(max(1, minutesUsed)), symbol: "timer")
            factRow("Average per question", "\(pace) s", symbol: "speedometer")
        }
        .contentCard()
    }

    private func factRow(_ title: String, _ value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer(minLength: 8)
            Text(value).font(.body.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subjects: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By subject, weakest first")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(result.bySubject) { row in
                subjectRow(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }

    private func subjectRow(_ row: MockSubjectScore) -> some View {
        let share: Int = Int((row.fraction * 100).rounded())
        let line: String = "\(row.correct) of \(row.total)"
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.subject).font(.body)
                Spacer(minLength: 8)
                Text(line + " \u{00B7} \(share)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ThinProgress(fraction: row.fraction)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: every answer, explained

    private var review: some View {
        let shown: [QuestionPick] = showAll ? allPicks : missed
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(showAll ? "Every question" : "The ones you missed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(showAll ? "Missed only" : "Show all") {
                    withAnimation(.snappy) { showAll.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
            if shown.isEmpty {
                Text("Nothing missed. Well done.").foregroundStyle(.secondary)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, pick in
                reviewRow(pick)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }

    private func reviewRow(_ pick: QuestionPick) -> some View {
        let q: MCQQuestion = pick.question
        let chosen: Int? = selected[q.id]
        let right: Bool = chosen == q.correctIndex
        let answer: String = q.options.indices.contains(q.correctIndex) ? q.options[q.correctIndex] : ""
        let yours: String = chosen.flatMap { q.options.indices.contains($0) ? q.options[$0] : nil } ?? "No answer"
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(q.stem).font(.subheadline)
                Label("Answer: " + answer, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if !right {
                    Label("You: " + yours, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                Text(q.explanation).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(right ? Color.green : Color.red)
                    .accessibilityHidden(true)
                Text(q.stem).lineLimit(2).font(.subheadline)
            }
        }
    }

    // MARK: the bar

    private var bar: some View {
        HStack(spacing: 12) {
            if !missed.isEmpty {
                Button {
                    practising = Store.temporaryQuiz(named: "Mock mistakes", subject: "Mock mistakes",
                                                     from: missed)
                } label: {
                    Label("Practise missed", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bigCompanion)
            }
            Button(action: onDone) {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [])
        }
    }
}
