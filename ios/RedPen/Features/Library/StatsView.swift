import SwiftUI

/// How the studying is going: the streak, and MCQ accuracy subject by subject.
///
/// The point of splitting it by subject is the button at the top. A single
/// overall percentage says "70%" and nothing about what to do next; by
/// subject it says renal is at 48%, and the drill goes straight there,
/// starting with the questions that were got wrong last time.
///
/// Built from the answer history the quiz keeps (Store.answerHistory), so it
/// only knows about questions answered since that history began, and only
/// about sets still in the library.
///
/// Above that sit the parts about how marks are lost: a readiness estimate,
/// how well confidence matches results, the reasons given for wrong answers
/// with one thing to do about each, and the rule sheet.
struct StatsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @ObservedObject private var log = StudyLog.shared
    /// The drill being taken, opened without being saved to the library.
    @State private var drill: StudySet?
    /// A quiz from the sections about lost marks, with how it is to be sat.
    @State private var insightQuiz: InsightQuiz?

    var body: some View {
        let stats = store.subjectStats()
        let tried = stats.filter { $0.answered > 0 }
        let due = reviews.dueAcross(store.library).count
        List {
            Section {
                ReadinessCard(estimate: store.readiness(dueCards: due),
                              answered: store.recentAnswers.count,
                              includesExamples: store.includesExampleData) { subject in
                    let set = store.drill(subject: subject)
                    if !set.questions.isEmpty { drill = set }
                }
            }

            Section { overview(tried) }

            if let weakest = tried.first {
                Section {
                    Button {
                        let set = store.drill(subject: weakest.subject)
                        if !set.questions.isEmpty { drill = set }
                    } label: {
                        Label("Drill weakest: \(weakest.subject)", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Up to 20 questions from \(weakest.subject): the ones you got wrong while sure first, then the rest you got wrong last time.")
                }
            }

            confidenceSection
            reasonsSection

            Section {
                NavigationLink {
                    RuleSheetView()
                } label: {
                    HStack {
                        Label("Rule sheet", systemImage: "list.bullet.rectangle")
                        Spacer(minLength: 8)
                        if !store.ruleSheet.isEmpty {
                            Text("\(store.ruleSheet.count)")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("One line to remember for each question you got wrong, by subject.")
            }

            if stats.isEmpty {
                Section {
                    Text("Make an MCQ set and answer a few questions, and how you are doing in each subject will show here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(stats) { subject in
                        subjectRow(subject)
                            .contextMenu {
                                Button("Drill \(subject.subject)", systemImage: "scope") {
                                    let set = store.drill(subject: subject.subject)
                                    if !set.questions.isEmpty { drill = set }
                                }
                            }
                    }
                } header: {
                    Text("By subject")
                } footer: {
                    Text("Every answer you have checked counts, so a question answered twice counts twice. Weakest first.")
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $drill) { MCQQuizView(set: $0, keepsProgress: false) }
        .navigationDestination(item: $insightQuiz) { quiz in
            MCQQuizView(set: quiz.set, keepsProgress: false,
                        minReadSeconds: quiz.minReadSeconds, startsTimed: quiz.timed)
        }
    }

    /// Opens a quiz from the lost-marks sections, if it has any questions.
    private func startQuiz(_ set: StudySet, minReadSeconds: Int = 0, timed: Bool = false) {
        guard !set.questions.isEmpty else { return }
        insightQuiz = InsightQuiz(set: set, minReadSeconds: minReadSeconds, timed: timed)
    }

    // MARK: confidence

    /// Accuracy at each confidence level, and the questions got wrong while sure.
    @ViewBuilder
    private var confidenceSection: some View {
        let rows = store.calibration()
        let confidentWrong = store.confidentMistakePicks
        Section {
            if rows.isEmpty {
                Text("Pick Sure, Maybe or Guess before checking an answer, and how often each is right will show here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.confidence.title).font(.body.weight(.semibold))
                            Spacer(minLength: 8)
                            Text("\(Int((row.accuracy * 100).rounded()))% right")
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.tint)
                        }
                        AccuracyBar(fraction: row.accuracy, color: .accentColor)
                        Text("\(row.answered) answer\(row.answered == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
            if !confidentWrong.isEmpty {
                NavigationLink {
                    InsightQuestionList(
                        title: "Confident but wrong",
                        tip: "These felt certain and were not: usually a fact learned wrongly rather than one not learned. Read the explanation, then quiz them again.",
                        picks: confidentWrong)
                } label: {
                    HStack {
                        Label("Confident but wrong", systemImage: "exclamationmark.triangle")
                        Spacer(minLength: 8)
                        Text("\(confidentWrong.count)")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Button {
                    startQuiz(store.confidentMistakesQuiz())
                } label: {
                    Label("Confident mistakes quiz", systemImage: "scope")
                }
            }
        } header: {
            Text("Confidence")
        } footer: {
            if !rows.isEmpty {
                Text("\u{201C}Sure\u{201D} should be right nearly every time. Confident mistakes come first in every drill.")
            }
        }
    }

    // MARK: why marks are lost

    @ViewBuilder
    private var reasonsSection: some View {
        let shares = store.reasonShares()
        Section {
            if shares.isEmpty {
                Text("After a wrong answer, tap why you think you lost the mark. The reasons you give show here with something to do about each.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(shares) { share in
                    reasonRow(share)
                }
            }
        } header: {
            Text("Why you lose marks")
        } footer: {
            if !shares.isEmpty {
                Text("The last \(Store.reasonWindowDays) days, from the reason you picked after each wrong answer.")
            }
        }
    }

    private func reasonRow(_ share: ReasonShare) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(share.reason.title, systemImage: share.reason.symbol)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(Int((share.share * 100).rounded()))%")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tint)
            }
            AccuracyBar(fraction: share.share, color: .accentColor)
            reasonAction(share.reason, count: share.count)
        }
        .padding(.vertical, 2)
    }

    /// The one thing to do about each reason.
    @ViewBuilder
    private func reasonAction(_ reason: MistakeReason, count: Int) -> some View {
        let questions = "\(count) question\(count == 1 ? "" : "s")"
        switch reason {
        case .didntKnow:
            Button {
                startQuiz(store.reasonQuiz(.didntKnow, named: "Practise these"))
            } label: {
                Label("Practise these \u{00B7} \(questions)", systemImage: "arrow.right.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        case .misread:
            Button {
                startQuiz(store.reasonQuiz(.misread, named: "Slow reading drill"), minReadSeconds: 15)
            } label: {
                Label("Slow reading drill \u{00B7} key words marked, 15 s a question", systemImage: "arrow.right.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        case .changedAnswer:
            NavigationLink {
                InsightQuestionList(
                    title: "Changed a right answer",
                    tip: "Change an answer only when you find a clue in the stem you missed the first time, not because a second option starts to look good. Your first answer was right here.",
                    picks: store.picks(for: .changedAnswer))
            } label: {
                Text("A tip, and the \(questions)").font(.subheadline).foregroundStyle(.tint)
            }
        case .outOfTime:
            Button {
                startQuiz(store.timedDrill(), timed: true)
            } label: {
                Label("Timed drill \u{00B7} 10 questions at \(ExamTrack.current.secondsPerQuestion) s each",
                      systemImage: "arrow.right.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        case .lookalikes:
            NavigationLink {
                InsightQuestionList(
                    title: "Mixed up lookalikes",
                    tip: "For each, name the one feature that tells the right answer from the option you chose.",
                    picks: store.picks(for: .lookalikes))
            } label: {
                Text("See the \(questions)").font(.subheadline).foregroundStyle(.tint)
            }
        }
    }

    /// The streak, today, and everything answered so far.
    private func overview(_ tried: [SubjectStats]) -> some View {
        let answered = tried.reduce(0) { $0 + $1.answered }
        let correct = tried.reduce(0) { $0 + $1.correct }
        return HStack(spacing: 0) {
            figure("\(log.streak)", log.streak == 1 ? "day streak" : "days streak",
                   symbol: "flame.fill", color: .orange)
            figure("\(log.today)", "today", symbol: "checkmark.circle.fill", color: .accentColor)
            figure(answered == 0 ? "\u{2013}" : "\(Int((Double(correct) / Double(answered) * 100).rounded()))%",
                   "of \(answered) right", symbol: "target", color: .green)
        }
        .padding(.vertical, 4)
    }

    private func figure(_ value: String, _ caption: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color)
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(caption).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func subjectRow(_ s: SubjectStats) -> some View {
        let color = Self.color(for: s)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.subject).font(.body.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(s.answered == 0 ? "Not tried" : "\(Int((s.accuracy * 100).rounded()))%")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
            }
            AccuracyBar(fraction: s.answered == 0 ? 0 : s.accuracy, color: color)
            Text("\(s.answered) answered \u{00B7} \(s.questions) question\(s.questions == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Green from three in four, amber from half, red below; grey for a
    /// subject not tried yet, which is not the same thing as a bad one.
    private static func color(for s: SubjectStats) -> Color {
        guard s.answered > 0 else { return .secondary }
        switch s.accuracy {
        case 0.75...: return .green
        case 0.5..<0.75: return .orange
        default: return .red
        }
    }
}

/// A thin bar filled to a fraction, in a colour of its own - ThinProgress
/// always takes the screen's tint, and here the colour is the verdict.
private struct AccuracyBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
