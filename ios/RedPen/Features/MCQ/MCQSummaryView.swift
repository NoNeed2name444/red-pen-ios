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
    @EnvironmentObject private var store: Store
    @State private var mistakesSaved = false
    /// The percentage as shown: it counts up from nothing as the ring fills,
    /// rather than sitting there finished before the ring has started.
    @State private var shownPercent = 0

    /// The questions answered wrongly, for a set of their own.
    private var mistakes: [MCQQuestion] {
        studySet.questions.indices.filter {
            answers.indices.contains($0) && answers[$0].selected != studySet.questions[$0].correctIndex
        }.map { studySet.questions[$0] }
    }

    /// "Mistakes - Cardiology": one per set, topped up each time, so the
    /// questions still getting wrong collect in one place to practise.
    private func saveMistakes() {
        let name = "Mistakes \u{2013} \(studySet.name.replacingOccurrences(of: "Mistakes \u{2013} ", with: ""))"
        if var existing = store.library.first(where: { $0.kind == .mcq && $0.name == name }) {
            let known = Set(existing.questions.map(\.stem))
            existing.questions += mistakes.filter { !known.contains($0.stem) }
            existing.updatedAt = Date()
            store.update(existing)
        } else {
            var set = StudySet(name: name, subject: studySet.subject, kind: .mcq)
            set.questions = mistakes
            set.sources = studySet.sources
            set.folderId = studySet.folderId
            store.addSet(set)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy) { mistakesSaved = true }
    }

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
                              label: "\(shownPercent)%",
                              sublabel: "\(correctCount) of \(total) correct")
                        .onAppear {
                            withAnimation(.smooth(duration: 0.9)) {
                                shownPercent = Int((fraction * 100).rounded())
                            }
                        }
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

                if !mistakes.isEmpty && !isUnsaved {
                    Button(action: saveMistakes) {
                        Label(mistakesSaved ? "In your library as \u{201C}Mistakes\u{201D}"
                                            : "Practise the \(mistakes.count) I got wrong",
                              systemImage: mistakesSaved ? "checkmark" : "arrow.uturn.backward.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(mistakesSaved)
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
            .readableColumn()
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
