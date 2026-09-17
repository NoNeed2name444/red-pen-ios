import SwiftUI

/// End-of-quiz results — matches the web app's `openSummary()` view: final
/// score plus a per-question review list.
struct MCQSummaryView: View {
    let studySet: StudySet
    let answers: [MCQAnswer]
    var onRetake: (() -> Void)? = nil
    let isUnsaved: Bool
    var saved: Binding<Bool>
    let onSave: (() -> Void)?

    init(set studySet: StudySet, answers: [MCQAnswer], onRetake: (() -> Void)? = nil,
         isUnsaved: Bool = false, saved: Binding<Bool> = .constant(false), onSave: (() -> Void)? = nil) {
        self.studySet = studySet
        self.answers = answers
        self.onRetake = onRetake
        self.isUnsaved = isUnsaved
        self.saved = saved
        self.onSave = onSave
    }
    @Environment(\.dismiss) private var dismiss

    private var correctCount: Int {
        answers.enumerated().filter { $0.element.selected == studySet.questions[$0.offset].correctIndex }.count
    }
    private var total: Int { studySet.questions.count }
    private var fraction: Double { total == 0 ? 0 : Double(correctCount) / Double(total) }

    private var verdict: String {
        switch fraction {
        case 0.9...: return "Excellent — exam ready."
        case 0.7..<0.9: return "Solid. A few to revisit."
        case 0.5..<0.7: return "Getting there — review the misses."
        default: return "Worth another pass before moving on."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    ScoreRing(fraction: fraction,
                              label: "\(Int((fraction * 100).rounded()))%",
                              sublabel: "\(correctCount) of \(total) correct")
                    Text(verdict)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentCard()

                // matches the web app's save-form on the summary screen — only
                // shown for a just-generated set that hasn't been saved yet
                if isUnsaved {
                    Button {
                        onSave?(); withAnimation(.snappy) { saved.wrappedValue = true }
                    } label: {
                        Label(saved.wrappedValue ? "Saved to library" : "Save to library",
                              systemImage: saved.wrappedValue ? "checkmark" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(saved.wrappedValue)
                }

                if let onRetake {
                    // matches the web app's "Retake this set" button
                    Button {
                        onRetake(); dismiss()
                    } label: {
                        Label("Retake this set", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Review")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 10)
                    ForEach(studySet.questions.indices, id: \.self) { i in
                        let q = studySet.questions[i]
                        let correct = answers[i].selected == q.correctIndex
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(correct ? .green : .red)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(q.stem).font(.subheadline).lineSpacing(2)
                                if !correct, q.options.indices.contains(q.correctIndex) {
                                    Text("Answer: \(q.options[q.correctIndex])")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .padding(.vertical, 10)
                        if i < studySet.questions.count - 1 { Divider() }
                    }
                }
                .contentCard()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .modeScreen(.mcq)
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.buttonStyle(.glassProminent)
            }
        }
    }
}
