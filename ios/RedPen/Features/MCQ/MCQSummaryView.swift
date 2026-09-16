import SwiftUI

/// End-of-quiz results — matches the web app's `openSummary()` view: final
/// score plus a per-question review list.
struct MCQSummaryView: View {
    let studySet: StudySet
    let answers: [MCQAnswer]

    init(set studySet: StudySet, answers: [MCQAnswer]) {
        self.studySet = studySet
        self.answers = answers
    }
    @Environment(\.dismiss) private var dismiss

    private var correctCount: Int {
        answers.enumerated().filter { $0.element.selected == studySet.questions[$0.offset].correctIndex }.count
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("\(correctCount) / \(studySet.questions.count)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("correct").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Review") {
                ForEach(studySet.questions.indices, id: \.self) { i in
                    let q = studySet.questions[i]
                    let correct = answers[i].selected == q.correctIndex
                    HStack(alignment: .top) {
                        Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(correct ? .green : .red)
                        Text(q.stem).font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
