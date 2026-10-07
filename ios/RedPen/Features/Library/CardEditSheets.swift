import SwiftUI

/// Editing one card.
///
/// Only the fields belonging to the card's own type are shown. A cloze card has
/// no bullets and a question card has no cloze sentence, and offering both
/// invites someone to fill in the one that will never be read.
struct CardEditSheet: View {
    let card: AnkiCard
    /// The library's tags, most used first, offered under the tag field.
    let knownTags: [(tag: String, count: Int)]
    let onSave: (AnkiCard) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var working: AnkiCard
    @State private var bullets: String

    init(card: AnkiCard, knownTags: [(tag: String, count: Int)] = [], onSave: @escaping (AnkiCard) -> Void) {
        self.card = card
        self.knownTags = knownTags
        self.onSave = onSave
        _working = State(initialValue: card)
        _bullets = State(initialValue: card.bullets.joined(separator: "\n"))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch working.type {
                case .cloze:
                    // every box you type into is its own field; the hints
                    // sit under them as footers, on the grid
                    Section {
                        TextEditor(text: $working.clozeText).frame(minHeight: 90)
                            .popEditorRow()
                    } header: {
                        Text("Sentence")
                    } footer: {
                        // Done waits for one, as the question sheet waits for
                        // a key: a cloze with nothing deleted has nothing to ask
                        Text(clozeHasNoDeletion
                             ? "Nothing is hidden yet \u{2014} wrap the tested words in {{c1::...}}."
                             : "Wrap the tested words in {{c1::...}}.")
                    }
                    .wardRowBackground()
                case .qa:
                    Section("Question") {
                        TextEditor(text: $working.front).frame(minHeight: 70)
                            .popEditorRow()
                    }
                    .wardRowBackground()
                    Section {
                        TextEditor(text: $bullets).frame(minHeight: 90)
                            .popEditorRow()
                    } header: {
                        Text("Answer")
                    } footer: {
                        Text("One bullet per line.")
                    }
                    .wardRowBackground()
                case .occlusion:
                    Section("Question") {
                        TextField("What is labelled here?", text: $working.front)
                            .popFieldRow()
                    }
                    .wardRowBackground()
                    Section {
                        TextEditor(text: $bullets).frame(minHeight: 60)
                            .popEditorRow()
                    } header: {
                        Text("Answer")
                    } footer: {
                        Text("The label this card's mask covers. The mask itself is set where the card was made.")
                    }
                    .wardRowBackground()
                }
                Section("Why / how") {
                    TextEditor(text: $working.why).frame(minHeight: 70)
                        .popEditorRow()
                }
                .wardRowBackground()
                Section {
                    TagChipsField(tags: $working.tags, known: knownTags)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("For finding it again: search for #tag. Tags go with the card to Anki.")
                }
                if let source = working.source, !source.isEmpty {
                    Section("From") {
                        Text(source).font(.footnote).foregroundStyle(Color.wardInkSecondary)
                    }
                    .wardRowBackground()
                }
            }
            .wardForm()
            .navigationTitle("Edit card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: commit).disabled(clozeHasNoDeletion)
                }
            }
        }
    }

    /// A cloze sentence whose braces were edited away: it would study as a
    /// card with nothing to recall, and export to Anki as a plain note.
    private var clozeHasNoDeletion: Bool {
        working.type == .cloze && CardQuality.clozeHoles(working.clozeText).isEmpty
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
    /// The library's tags, most used first, offered under the tag field.
    let knownTags: [(tag: String, count: Int)]
    let onSave: (MCQQuestion) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var working: MCQQuestion

    init(question: MCQQuestion, knownTags: [(tag: String, count: Int)] = [], onSave: @escaping (MCQQuestion) -> Void) {
        self.question = question
        self.knownTags = knownTags
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
                .wardRowBackground()
                Section {
                    ForEach(working.options.indices, id: \.self) { index in
                        optionRow(index)
                    }
                    .onDelete { offsets in working = MCQEdit.removing(offsets, from: working) }
                    Button("Add an option", systemImage: "plus") { working.options.append("") }
                        .buttonStyle(.bigSecondary)
                        .wardButtonRow()
                } header: {
                    Text("Options")
                } footer: {
                    // the keyed option emptied or deleted: nothing is marked,
                    // and Done waits for the right answer to be picked
                    Text(MCQEdit.hasKey(working)
                         ? "Tap the circle beside the right answer."
                         : "No answer is marked correct \u{2014} tap the circle beside the right one.")
                }
                Section("Explanation") {
                    TextEditor(text: $working.explanation).frame(minHeight: 90)
                        .popEditorRow()
                }
                .wardRowBackground()
                Section("Tags") {
                    TagChipsField(tags: $working.tags, known: knownTags)
                        .listRowBackground(Color.clear)
                }
                if let source = working.source, !source.isEmpty {
                    Section("From") {
                        Text(source).font(.footnote).foregroundStyle(Color.wardInkSecondary)
                    }
                    .wardRowBackground()
                }
            }
            .wardForm()
            .navigationTitle("Edit question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard let saved = MCQEdit.tidied(working) else { return }
                        onSave(saved)
                        dismiss()
                    }
                    // two options with words, one of them marked correct
                    .disabled(MCQEdit.tidied(working) == nil)
                }
            }
        }
    }

    /// One option: the circle that marks it correct, its words, and a minus
    /// that removes it (also by holding the circle, and by swiping).
    private func optionRow(_ index: Int) -> some View {
        let correct: Bool = working.correctIndex == index
        let mark: String = correct ? "checkmark.circle.fill" : "circle"
        let ink: Color = correct ? Color.wardSuccess : Color.wardInkSecondary
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
            // the words are a field of their own between the two buttons;
            // the row itself is clear, so the field sits on the grid
            TextField("Option", text: optionText(index), axis: .vertical)
                .popField()
            Button { removeOption(index) } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.wardDanger)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Delete option")
        }
        .wardWellRow()
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
