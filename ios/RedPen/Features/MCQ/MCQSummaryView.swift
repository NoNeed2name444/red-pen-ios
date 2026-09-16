import SwiftUI

/// End-of-quiz results — matches the web app's `openSummary()` view: final
/// score plus a per-question review list.
struct MCQSummaryView: View {
    let set: StudySet
    let answers: [MCQAnswer]
    @Environment(\.dismiss) private var dismiss

    private var correctCount: Int {
        answers.enumerated().filter { $0.element.selected == set.questions[$0.offset].correctIndex }.count
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("\(correctCount) / \(set.questions.count)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("correct").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Review") {
                ForEach(set.questions.indices, id: \.self) { i in
                    let q = set.questions[i]
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
