import SwiftUI

/// Editing what is in a set, one item at a time.
///
/// Until now a set was all or nothing: if the model wrote one bad distractor,
/// or the figure detector masked a caption instead of a label, the only choice
/// was to keep the whole thing or delete the whole thing. That gets worse the
/// better generation gets, because the decks get bigger.
///
/// Deleting a card also forgets its place in the schedule - see ReviewStore -
/// so a deleted card does not linger as a record for a card that is gone.
struct CardsEditorView: View {
    let set: StudySet
    @EnvironmentObject var store: Store
    @EnvironmentObject var reviews: ReviewStore
    @Environment(\.dismiss) private var dismiss

    @State private var working: StudySet
    @State private var editingCard: AnkiCard?
    @State private var editingQuestion: MCQQuestion?

    init(set: StudySet) {
        self.set = set
        _working = State(initialValue: set)
    }

    var body: some View {
        NavigationStack {
            List {
                if working.kind == .anki {
                    ForEach(working.cards) { card in
                        Button { editingCard = card } label: { cardRow(card) }
                            .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteCards)
                } else {
                    ForEach(working.questions) { question in
                        Button { editingQuestion = question } label: { questionRow(question) }
                            .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteQuestions)
                }
            }
            .navigationTitle("Edit \(working.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .sheet(item: $editingCard) { card in
                CardEditSheet(card: card) { edited in replace(edited) }
            }
            .sheet(item: $editingQuestion) { question in
                QuestionEditSheet(question: question) { edited in replace(edited) }
            }
        }
    }

    private func cardRow(_ card: AnkiCard) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.type == .cloze ? card.clozeText : card.displayFront)
                .font(.subheadline).lineLimit(2)
            HStack(spacing: 6) {
                Text(card.type.rawValue).font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                if let source = card.source, !source.isEmpty {
                    Text(source).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func questionRow(_ question: MCQQuestion) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(question.stem).font(.subheadline).lineLimit(2)
            HStack(spacing: 6) {
                if question.options.indices.contains(question.correctIndex) {
                    Text(question.options[question.correctIndex])
                        .font(.caption2).foregroundStyle(.green).lineLimit(1)
                }
                if let source = question.source, !source.isEmpty {
                    Text(source).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: changes

    private func deleteCards(_ offsets: IndexSet) {
        for index in offsets { reviews.forget(working.cards[index].id) }
        working.cards.remove(atOffsets: offsets)
    }

    private func deleteQuestions(_ offsets: IndexSet) {
        working.questions.remove(atOffsets: offsets)
    }

    private func replace(_ card: AnkiCard) {
        guard let index = working.cards.firstIndex(where: { $0.id == card.id }) else { return }
        working.cards[index] = card
    }

    private func replace(_ question: MCQQuestion) {
        guard let index = working.questions.firstIndex(where: { $0.id == question.id })
        else { return }
        working.questions[index] = question
    }

    /// Edits are held until Save, so backing out of the sheet changes nothing.
    private func save() {
        store.update(working)
        reviews.prune(keeping: store.library)
        dismiss()
    }
}
