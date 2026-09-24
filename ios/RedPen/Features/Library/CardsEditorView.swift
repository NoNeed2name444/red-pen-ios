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
///
/// A row is deleted by swiping it, by holding it (Delete in its menu) or with
/// Edit at the top. Nothing is kept until Save changes, which appears at the
/// bottom, under the thumb, once there is something to save; Cancel leaves
/// the set as it was.
struct CardsEditorView: View {
    let set: StudySet
    @EnvironmentObject var store: Store
    @EnvironmentObject var reviews: ReviewStore
    @Environment(\.dismiss) private var dismiss

    @State private var working: StudySet
    @State private var editingCard: AnkiCard?
    @State private var editingQuestion: MCQQuestion?
    /// Whether anything has been changed since the editor opened.
    @State private var changed = false

    init(set: StudySet) {
        self.set = set
        _working = State(initialValue: set)
    }

    private var title: String {
        working.kind == .anki ? "Edit cards" : "Edit questions"
    }

    var body: some View {
        NavigationStack {
            rows
                .scrollContentBackground(.hidden)
                .background(LibraryBackdrop())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if changed { saveBar }
                }
                .animation(.snappy(duration: 0.25), value: changed)
                .sheet(item: $editingCard) { card in
                    CardEditSheet(card: card) { edited in replace(edited) }
                }
                .sheet(item: $editingQuestion) { question in
                    QuestionEditSheet(question: question) { edited in replace(edited) }
                }
        }
    }

    private var rows: some View {
        List {
            if working.kind == .anki {
                ForEach(working.cards) { card in
                    Button { editingCard = card } label: { cardRow(card) }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(card) }
                        }
                }
                .onDelete(perform: deleteCards)
            } else {
                ForEach(working.questions) { question in
                    Button { editingQuestion = question } label: { questionRow(question) }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(question) }
                        }
                }
                .onDelete(perform: deleteQuestions)
            }
        }
    }

    /// The one main button, once there is something to save.
    private var saveBar: some View {
        StudyActionBar {
            Button { save() } label: {
                Label("Save changes", systemImage: "checkmark")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut("s", modifiers: .command)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

    /// Only from the working copy: the schedule forgets a card at Save, so
    /// Cancel really does leave everything as it was.
    private func deleteCards(_ offsets: IndexSet) {
        working.cards.remove(atOffsets: offsets)
        changed = true
    }

    private func deleteQuestions(_ offsets: IndexSet) {
        working.questions.remove(atOffsets: offsets)
        changed = true
    }

    private func delete(_ card: AnkiCard) {
        guard let index = working.cards.firstIndex(where: { $0.id == card.id }) else { return }
        deleteCards(IndexSet(integer: index))
    }

    private func delete(_ question: MCQQuestion) {
        guard let index = working.questions.firstIndex(where: { $0.id == question.id }) else { return }
        deleteQuestions(IndexSet(integer: index))
    }

    private func replace(_ card: AnkiCard) {
        guard let index = working.cards.firstIndex(where: { $0.id == card.id }) else { return }
        working.cards[index] = card
        changed = true
    }

    private func replace(_ question: MCQQuestion) {
        guard let index = working.questions.firstIndex(where: { $0.id == question.id })
        else { return }
        working.questions[index] = question
        changed = true
    }

    /// Edits are held until Save, so backing out of the sheet changes nothing.
    private func save() {
        let kept = Set(working.cards.map(\.id))
        for card in set.cards where !kept.contains(card.id) { reviews.forget(card.id) }
        store.update(working)
        reviews.prune(keeping: store.library)
        dismiss()
    }
}
