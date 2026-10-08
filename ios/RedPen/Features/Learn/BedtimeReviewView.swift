import SwiftUI

/// Bedtime lock-in: a calm re-read of today's misses, each as the answer and
/// one line to remember. Not a test - nothing to tap, nothing scored.
///
/// A short re-read just before sleep is consolidated overnight better than
/// the same material read earlier. Dim and large, so it is easy on the eyes
/// in a dark room, and the whole screen is drawn dark whatever the phone's
/// setting. Tomorrow morning's check (MorningCheckView) asks the same items.
struct BedtimeReviewView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let picks: [QuestionPick] = store.bedtimePicks()
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today\u{2019}s misses").font(.largeTitle.weight(.semibold)).foregroundStyle(Color.wardInk)
                    Text(subtitle(picks.count))
                        .font(.title3)
                        .foregroundStyle(Color.wardInkSecondary)
                }
                ForEach(picks, id: \.question.id) { pick in
                    BedtimeItem(pick: pick, rule: store.ruleSheet[pick.question.id]?.text)
                }
                Text("That\u{2019}s all. Good night \u{2014} tomorrow morning, two minutes on these.")
                    .font(.title3)
                    .foregroundStyle(Color.wardInkSecondary)
                Button("Good night") { dismiss() }
                    .buttonStyle(.wardSecondary)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.wardBackground.ignoresSafeArea())
        .tint(Color.wardPrimary)
        .environment(\.colorScheme, .dark)
        .environment(\.modeTint, Color.wardPrimary)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.wardBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func subtitle(_ count: Int) -> String {
        if count == 0 { return "Nothing missed today. Sleep well." }
        let plural: String = count == 1 ? "" : "es"
        return "\(count) miss\(plural), with the answer. Just read them."
    }
}

private struct BedtimeItem: View {
    let pick: QuestionPick
    /// The rule-sheet line, when there is one.
    let rule: String?

    var body: some View {
        let q: MCQQuestion = pick.question
        let answer: String = q.options.indices.contains(q.correctIndex) ? q.options[q.correctIndex] : ""
        let line: String = rule ?? RuleWriter.firstSentence(of: q.explanation)
        VStack(alignment: .leading, spacing: 10) {
            Text(q.stem)
                .font(.body)
                .foregroundStyle(Color.wardInkSecondary)
                .lineLimit(4)
            Text(answer)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.wardInk)
            if !line.isEmpty {
                Text(line)
                    .font(.title3)
                    .foregroundStyle(Color.wardInk.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The morning check: yesterday's misses, re-asked, before anything new.
/// Two minutes - at most ten questions.
struct MorningCheckView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var quiz: StudySet?

    private static func note(_ count: Int) -> String {
        if count == 0 { return "Nothing from yesterday to re-ask. On with the day." }
        let plural: String = count == 1 ? "" : "s"
        return "\(count) question\(plural) you missed yesterday. About two minutes, before anything new \u{2014} asking again after a night\u{2019}s sleep is what fixes them."
    }

    var body: some View {
        let count: Int = min(10, store.morningPicks().count)
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: "sunrise.fill")
                .scaledFont(52, relativeTo: .largeTitle, maxSize: 80)
                .foregroundStyle(Color.wardBeam)
                .accessibilityHidden(true)
            Text("Morning check").font(.largeTitle.weight(.bold)).foregroundStyle(Color.wardInk)
            Text(Self.note(count))
                .font(.body)
                .foregroundStyle(Color.wardInkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wardScreen()
        .studyBar {
            if count > 0 {
                Button {
                    LearnMarks.markMorningDone()
                    quiz = store.morningCheckQuiz()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.wardPrimary)
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(.wardSecondary)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $quiz) { MCQQuizView(set: $0, keepsProgress: false) }
    }
}
