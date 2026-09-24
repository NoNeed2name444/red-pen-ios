import SwiftUI

/// Editing one card.
///
/// Only the fields belonging to the card's own type are shown. A cloze card has
/// no bullets and a question card has no cloze sentence, and offering both
/// invites someone to fill in the one that will never be read.
struct CardEditSheet: View {
    let card: AnkiCard
    let onSave: (AnkiCard) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var working: AnkiCard
    @State private var bullets: String

    init(card: AnkiCard, onSave: @escaping (AnkiCard) -> Void) {
        self.card = card
        self.onSave = onSave
        _working = State(initialValue: card)
        _bullets = State(initialValue: card.bullets.joined(separator: "\n"))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch working.type {
                case .cloze:
                    // every box you type into is its own raised slab; the
                    // hints sit under them as footers, on the glass
                    Section {
                        TextEditor(text: $working.clozeText).frame(minHeight: 90)
                            .popEditorRow()
                    } header: {
                        Text("Sentence")
                    } footer: {
                        Text("Wrap the tested words in {{c1::...}}.")
                    }
                case .qa:
                    Section("Question") {
                        TextEditor(text: $working.front).frame(minHeight: 70)
                            .popEditorRow()
                    }
                    Section {
                        TextEditor(text: $bullets).frame(minHeight: 90)
                            .popEditorRow()
                    } header: {
                        Text("Answer")
                    } footer: {
                        Text("One bullet per line.")
                    }
                case .occlusion:
                    Section("Question") {
                        TextField("What is labelled here?", text: $working.front)
                            .popFieldRow()
                    }
                    Section {
                        TextEditor(text: $bullets).frame(minHeight: 60)
                            .popEditorRow()
                    } header: {
                        Text("Answer")
                    } footer: {
                        Text("The label this card's mask covers. The mask itself is set where the card was made.")
                    }
                }
                Section("Why / how") {
                    TextEditor(text: $working.why).frame(minHeight: 70)
                        .popEditorRow()
                }
                if let source = working.source, !source.isEmpty {
                    Section("From") {
                        Text(source).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .navigationTitle("Edit card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: commit) }
            }
        }
    }

    private func commit() {
        var edited = working
        edited.bullets = bullets.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onSave(edited)
        dismiss()
    }
}

/// Editing one question. The correct answer is picked rather than typed, so it
/// cannot point at an option that no longer exists; the index bookkeeping that
/// keeps that true is in MCQEdit, where it is tested.
struct QuestionEditSheet: View {
    let question: MCQQuestion
    let onSave: (MCQQuestion) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var working: MCQQuestion

    init(question: MCQQuestion, onSave: @escaping (MCQQuestion) -> Void) {
        self.question = question
        self.onSave = onSave
        _working = State(initialValue: question)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Stem") {
                    TextEditor(text: $working.stem).frame(minHeight: 90)
                        .popEditorRow()
                }
                Section {
                    ForEach(working.options.indices, id: \.self) { index in
                        optionRow(index)
                    }
                    .onDelete { offsets in working = MCQEdit.removing(offsets, from: working) }
                    Button("Add an option", systemImage: "plus") { working.options.append("") }
                        .buttonStyle(.bigSecondary)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Options")
                } footer: {
                    Text("Tap the circle beside the right answer.")
                }
                Section("Explanation") {
                    TextEditor(text: $working.explanation).frame(minHeight: 90)
                        .popEditorRow()
                }
                if let source = working.source, !source.isEmpty {
                    Section("From") {
                        Text(source).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .navigationTitle("Edit question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(MCQEdit.tidied(working))
                        dismiss()
                    }
                    .disabled(working.options.count < 2)
                }
            }
        }
    }

    /// One option: the circle that marks it correct, its words, and a minus
    /// that removes it (also by holding the circle, and by swiping).
    private func optionRow(_ index: Int) -> some View {
        let correct: Bool = working.correctIndex == index
        let mark: String = correct ? "checkmark.circle.fill" : "circle"
        let ink: Color = correct ? Color.green : Color.secondary
        let traits: AccessibilityTraits = correct ? .isSelected : []
        return HStack(spacing: 6) {
            // plain buttons, so in a Form row each takes only its own tap
            Button { working.correctIndex = index } label: {
                Image(systemName: mark)
                    .font(.title3)
                    .foregroundStyle(ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            // on the circle rather than the whole row, so holding the words
            // still selects text
            .contextMenu {
                Button("Mark correct", systemImage: "checkmark.circle") { working.correctIndex = index }
                Button("Delete", systemImage: "trash", role: .destructive) { removeOption(index) }
            }
            .accessibilityLabel("Mark correct")
            .accessibilityAddTraits(traits)
            // the words are a raised field of their own between the two
            // buttons; the row itself is clear, so the slabs sit on the glass
            TextField("Option", text: optionText(index), axis: .vertical)
                .popField()
            Button { removeOption(index) } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Delete option")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(PopOutField.rowInsets)
    }

    /// The words of one option, checked against the list each time, so a row
    /// that has just been deleted reads as empty instead of past the end.
    private func optionText(_ index: Int) -> Binding<String> {
        Binding<String>(
            get: {
                guard working.options.indices.contains(index) else { return "" }
                return working.options[index]
            },
            set: { new in
                guard working.options.indices.contains(index) else { return }
                working.options[index] = new
            }
        )
    }

    private func removeOption(_ index: Int) {
        guard working.options.indices.contains(index) else { return }
        working = MCQEdit.removing(IndexSet(integer: index), from: working)
    }
}
