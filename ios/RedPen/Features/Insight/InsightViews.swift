import SwiftUI

/// A quiz opened from the Progress screen, with the way it is to be sat:
/// normally, as a slow reading drill, or against the clock.
struct InsightQuiz: Identifiable, Hashable {
    var set: StudySet
    /// Seconds before each answer can be checked; 0 for none.
    var minReadSeconds = 0
    /// Starts in timed exam mode.
    var timed = false
    var id: UUID { self.set.id }
}

/// The top card of the Progress screen: the estimated score as a range,
/// against a typical pass mark, and the subjects that would move it most.
struct ReadinessCard: View {
    let estimate: ReadinessEstimate?
    /// Answers so far, for the "answer a few more" state.
    let answered: Int
    let includesExamples: Bool
    /// Opens a drill of one subject.
    var onDrill: (String) -> Void = { _ in }

    private static func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Readiness estimate", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if includesExamples {
                    Text("Example data").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if let estimate {
                filled(estimate)
            } else {
                empty
            }
        }
        .padding(.vertical, 6)
    }

    private var empty: some View {
        let needed = Readiness.minimumAnswers
        return VStack(alignment: .leading, spacing: 8) {
            Text("Answer at least \(needed) questions and an estimated score will show here.")
                .font(.subheadline).foregroundStyle(.secondary)
            ThinProgress(fraction: Double(min(answered, needed)) / Double(needed))
            Text("\(min(answered, needed)) of \(needed)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func filled(_ e: ReadinessEstimate) -> some View {
        let track = ExamTrack.current
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.percent(e.center))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
            VStack(alignment: .leading, spacing: 1) {
                Text("likely \(Self.percent(e.low))\u{2013}\(Self.percent(e.high))")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                Text(verdict(e)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)

        RangeBar(low: e.low, center: e.center, high: e.high, mark: e.passMark)

        let exam: String = track == .general ? "" : " for " + track.rawValue.uppercased()
        let passLine: String = "Typical pass mark\(exam): \(Self.percent(e.passMark)) \u{00B7} approximate"
        Text(passLine)
            .font(.caption).foregroundStyle(.secondary)

        Text(basis(e))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if !e.levers.isEmpty {
            Divider()
            Text("What would move it most")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(e.levers) { lever in
                Button { onDrill(lever.subject) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "scope").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(lever.subject).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(leverLine(lever)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    // the whole 44 points answer a tap, not just the words
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 10, style: .continuous))
                .hoverEffect(.highlight)
                .accessibilityHint("Opens a drill of \(lever.subject)")
            }
        }
    }

    private func verdict(_ e: ReadinessEstimate) -> String {
        if e.low >= e.passMark { return "Likely above the pass mark" }
        if e.high < e.passMark { return "Below the pass mark for now" }
        return "Around the pass mark"
    }

    /// What the estimate rests on and what was taken off, in plain words.
    private func basis(_ e: ReadinessEstimate) -> String {
        var parts = ["An estimate, not a prediction: your last \(e.answers) answers, the latest counting most."]
        if e.coveragePenalty >= 0.005 {
            let n = e.thinSubjects.count
            parts.append("\(Int((e.coveragePenalty * 100).rounded())) off for \(n) subject\(n == 1 ? "" : "s") with under \(Readiness.thinSubjectAnswers) answers.")
        }
        if e.reviewPenalty >= 0.005 {
            parts.append("\(Int((e.reviewPenalty * 100).rounded())) off for \(e.dueCards) card\(e.dueCards == 1 ? "" : "s") waiting for review.")
        }
        return parts.joined(separator: " ")
    }

    private func leverLine(_ lever: ReadinessEstimate.Lever) -> String {
        let share = "\(Self.percent(lever.share)) of your questions"
        guard let accuracy = lever.accuracy else { return share + " \u{00B7} not tried yet" }
        return share + " \u{00B7} \(Self.percent(accuracy)) right"
    }
}

/// Where RangeBar's pieces go, worked out in plain typed steps rather than
/// inside the view builder, where mixed Double and CGFloat sums are slow for
/// the compiler to type.
private struct RangeBarLayout {
    var rangeWidth: CGFloat
    var rangeX: CGFloat
    var centerX: CGFloat
    var markX: CGFloat

    init(width: CGFloat, low: Double, center: Double, high: Double, mark: Double) {
        let w: Double = Double(width)
        let span: Double = (high - low) * w
        rangeWidth = CGFloat(max(8, span))
        let lowX: Double = max(0, low * w)
        rangeX = CGFloat(min(lowX, max(0, w - 8)))
        let middle: Double = max(0, center * w - 6)
        centerX = CGFloat(min(middle, w - 12))
        let tick: Double = max(0, mark * w - 1)
        markX = CGFloat(min(tick, w - 2))
    }
}

/// 0-100% with the estimate's range shaded, its middle marked, and a tick
/// at the pass mark.
private struct RangeBar: View {
    let low: Double, center: Double, high: Double, mark: Double

    var body: some View {
        GeometryReader { geo in
            let layout = RangeBarLayout(width: geo.size.width, low: low, center: center,
                                        high: high, mark: mark)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
                Capsule().fill(Color.accentColor.opacity(0.35))
                    .frame(width: layout.rangeWidth, height: 8)
                    .offset(x: layout.rangeX)
                Circle().fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .offset(x: layout.centerX)
                Rectangle().fill(Color.primary.opacity(0.6))
                    .frame(width: 2, height: 18)
                    .offset(x: layout.markX)
            }
            .frame(height: 18)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// A list of questions with their answers, for the reasons that call for
/// reading rather than a quiz: changed answers and lookalikes, and the
/// confident mistakes. Once they are read, Quiz these - in the slab at the
/// bottom, under the thumb - asks the same questions again.
struct InsightQuestionList: View {
    let title: String
    let tip: String?
    let picks: [QuestionPick]
    @State private var quiz: StudySet?

    var body: some View {
        // the list never changes under the screen, so the slab is either
        // there from the start or not at all
        Group {
            if picks.isEmpty {
                questions
            } else {
                questions
                    .studyBar { quizButton }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $quiz) { set in
            MCQQuizView(set: set, keepsProgress: false)
        }
    }

    private var questions: some View {
        let count: Int = picks.count
        let plural: String = count == 1 ? "" : "s"
        let footer: String = "\(count) question\(plural). Tap one to see its answer."
        return List {
            if let tip {
                Section {
                    Label(tip, systemImage: "lightbulb")
                        .font(.subheadline)
                }
            }
            if picks.isEmpty {
                Section {
                    Text("Nothing here at the moment.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(picks, id: \.question.id) { pick in
                        InsightQuestionRow(pick: pick)
                    }
                } footer: {
                    Text(footer)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
    }

    private var quizButton: some View {
        let capped: Bool = picks.count > Self.quizLimit
        let hint: String = capped
            ? "A quiz of \(Self.quizLimit) of these questions, in a new order, not saved to your library"
            : "A quiz of these questions, in a new order, not saved to your library"
        return Button {
            quiz = Self.makeQuiz(named: title, from: picks)
        } label: {
            Label("Quiz these", systemImage: "list.bullet.rectangle")
        }
        .buttonStyle(.bigPrimary)
        .keyboardShortcut(.defaultAction)
        .accessibilityHint(hint)
    }

    /// The most questions Quiz these asks - the same cap as the confident
    /// mistakes quiz.
    static let quizLimit: Int = 20

    /// These questions as a quiz of their own: one subject's name when they
    /// all share it, "Mixed" otherwise. Shuffled and capped, like
    /// `confidentMistakesQuiz`, so it is not asked in the order just read.
    @MainActor
    static func makeQuiz(named name: String, from picks: [QuestionPick]) -> StudySet {
        let chosen: [QuestionPick] = Array(picks.shuffled().prefix(quizLimit))
        let subjects: Set<String> = Set(chosen.map { Store.subjectName($0.set) })
        let subject: String = subjects.count == 1 ? (subjects.first ?? "Mixed") : "Mixed"
        return Store.temporaryQuiz(named: name, subject: subject, from: chosen)
    }
}

/// One question, folded: the stem and its subject, opening on a tap to the
/// right answer and why.
private struct InsightQuestionRow: View {
    let pick: QuestionPick

    var body: some View {
        let q = pick.question
        let hasAnswer: Bool = q.options.indices.contains(q.correctIndex)
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if hasAnswer {
                    Label(q.options[q.correctIndex], systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                }
                if !q.explanation.isEmpty {
                    Text(q.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(q.stem)
                    .font(.subheadline)
                    .lineLimit(3)
                Text(Store.subjectName(pick.set))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .hoverEffect(.highlight)
    }
}
