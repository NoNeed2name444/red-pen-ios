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
    @Environment(\.windowSpan) private var span
    @EnvironmentObject private var store: Store
    @State private var mistakesSaved = false
    /// How many rules the button below just added, once it has been pressed.
    @State private var rulesAdded: Int?
    /// The percentage as shown: it counts up from nothing as the ring fills,
    /// rather than sitting there finished before the ring has started.
    @State private var shownPercent = 0
    /// The Mistakes set, once "Practise mistakes" has made it and opened it.
    @State private var practising: StudySet?

    /// The questions answered wrongly, for a set of their own.
    private var mistakes: [MCQQuestion] {
        studySet.questions.indices.filter { !isRight($0) }.map { studySet.questions[$0] }
    }

    /// The questions answered and checked wrongly - not the ones skipped,
    /// which there is nothing to learn a rule from.
    private var checkedMistakes: [MCQQuestion] {
        studySet.questions.indices.filter {
            answers.indices.contains($0) && answers[$0].checked && !isRight($0)
        }.map { studySet.questions[$0] }
    }

    /// "Add 3 rules", then a way to the sheet. Short on screen, so it sits
    /// beside Try again on a phone without wrapping; the full wording is
    /// what VoiceOver reads.
    @ViewBuilder
    private var ruleSheetButton: some View {
        if rulesAdded != nil {
            NavigationLink {
                RuleSheetView()
            } label: {
                Label("Rule sheet", systemImage: "list.bullet.rectangle")
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.bigSecondary)
            .accessibilityLabel("Open your rule sheet")
        } else {
            let fresh = store.questionsWithoutRules(checkedMistakes).count
            if fresh > 0 {
                let plural: String = fresh == 1 ? "" : "s"
                Button {
                    let added = store.addRules(for: checkedMistakes, subject: Store.subjectName(studySet))
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.snappy) { rulesAdded = added }
                } label: {
                    Label("Add \(fresh) rule\(plural)", systemImage: "text.badge.plus")
                        .frame(maxHeight: .infinity)
                }
                .buttonStyle(.bigSecondary)
                .accessibilityLabel("Add \(fresh) rule\(plural) to your rule sheet")
            }
        }
    }

    /// What adding rules did, said once above the buttons, so the button
    /// itself can stay short.
    @ViewBuilder
    private var rulesAddedNote: some View {
        if let added = rulesAdded, added > 0 {
            let plural: String = added == 1 ? "" : "s"
            Label("\(added) rule\(plural) added to your rule sheet", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// "Mistakes - Cardiology": one per set, topped up each time, so the
    /// questions still getting wrong collect in one place to practise.
    private static func mistakesName(for set: StudySet) -> String {
        "Mistakes \u{2013} " + set.name.replacingOccurrences(of: "Mistakes \u{2013} ", with: "")
    }

    private func saveMistakes() {
        let name = Self.mistakesName(for: studySet)
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

    /// Whether question `i` was answered right: checked, and the option
    /// chosen (an index into the question's own options, as the quiz hands
    /// them over) is the key. The same test as the running score and the
    /// answer history, so the results never disagree with either.
    private func isRight(_ i: Int) -> Bool {
        guard answers.indices.contains(i), studySet.questions.indices.contains(i) else { return false }
        return answers[i].isCorrect(for: studySet.questions[i])
    }

    private var correctCount: Int {
        studySet.questions.indices.filter { isRight($0) }.count
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

    /// The one big thing to do next. Saving comes first for a quiz that is
    /// not in the library yet, then practising what went wrong, then Done.
    private enum Next { case save, practise, done }
    private var next: Next {
        if isUnsaved && !saved.wrappedValue { return .save }
        if !mistakes.isEmpty && !isUnsaved && !mistakesSaved { return .practise }
        return .done
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FinishHero(title: "\(correctCount) of \(total) right", message: verdict) {
                    ScoreRing(fraction: fraction,
                              label: "\(shownPercent)%",
                              sublabel: "correct")
                        .onAppear {
                            withAnimation(.smooth(duration: 0.9)) {
                                shownPercent = Int((fraction * 100).rounded())
                            }
                        }
                }
                .contentCard()

                otherActions
                reviewList
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .studyBar { barButtons }
        .modeScreen(.mcq)
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $practising) { set in
            MCQQuizView(set: set)
        }
    }

    // MARK: the one main button, and the smaller ones

    /// The bar: the one main button at the trailing end, and - whenever that
    /// is not Done already - Done beside it, so there is only ever one Done.
    private var barButtons: some View {
        HStack(spacing: 12) {
            if next != .done {
                Button("Done") { dismiss() }
                    .buttonStyle(.bigCompanion)
                if span == .broad { Spacer(minLength: 16) }
            }
            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch next {
        case .save:
            Button {
                onSave?(); withAnimation(.snappy) { saved.wrappedValue = true }
            } label: {
                Label("Save to library", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [])
        case .practise:
            Button(action: practiseMistakes) {
                Label("Practise mistakes (\(mistakes.count))", systemImage: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityHint("Saves the questions you got wrong as a set called Mistakes, and opens it")
        case .done:
            Button("Done") { dismiss() }
                .buttonStyle(.bigPrimary)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    /// Everything else the results offer, smaller, under the score: what
    /// has been saved, then one row of the two second choices.
    @ViewBuilder
    private var otherActions: some View {
        VStack(spacing: 12) {
            if isUnsaved && saved.wrappedValue {
                Label("Saved to library", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if mistakesSaved {
                Label("In your library as \u{201C}Mistakes\u{201D}", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            rulesAddedNote

            // the two slabs match in height even if one label wraps
            HStack(spacing: 12) {
                ruleSheetButton
                retakeButton
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Matches the web app's "Retake this set" button.
    @ViewBuilder
    private var retakeButton: some View {
        if let onRetake {
            Button {
                onRetake(); dismiss()
            } label: {
                Label("Try again", systemImage: "arrow.counterclockwise")
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.bigSecondary)
            .accessibilityLabel("Try this set again")
        }
    }

    /// Every question with a tick or a cross, and the right answer under the
    /// ones that were missed.
    private var reviewList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your answers")
                .font(.headline)
                .padding(.bottom, 8)
            ForEach(studySet.questions.indices, id: \.self) { i in
                reviewRow(i)
                if i < studySet.questions.count - 1 { Divider() }
            }
        }
        .contentCard()
    }

    private func reviewRow(_ i: Int) -> some View {
        let q = studySet.questions[i]
        let correct = isRight(i)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(correct ? Color.green : Color.red)
                .font(.title3)
                .accessibilityLabel(correct ? "Right" : "Wrong")
            VStack(alignment: .leading, spacing: 4) {
                Text(q.stem).font(.body).lineSpacing(2)
                if !correct, q.options.indices.contains(q.correctIndex) {
                    Text("Answer: \(q.options[q.correctIndex])")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// Saves the mistakes as their own set, then opens it straight away - the
    /// button says "Practise", so it should start the practice.
    private func practiseMistakes() {
        saveMistakes()
        let name = Self.mistakesName(for: studySet)
        if let set = store.library.first(where: { $0.kind == .mcq && $0.name == name }) {
            practising = set
        }
    }
}
