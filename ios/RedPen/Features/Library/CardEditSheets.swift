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
                    Section("Sentence") {
                        TextEditor(text: $working.clozeText).frame(minHeight: 90)
                        Text("Wrap the tested words in {{c1::...}}.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .qa:
                    Section("Question") {
                        TextEditor(text: $working.front).frame(minHeight: 70)
                    }
                    Section("Answer") {
                        TextEditor(text: $bullets).frame(minHeight: 90)
                        Text("One bullet per line.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .occlusion:
                    Section("Question") {
                        TextField("What is labelled here?", text: $working.front)
                    }
                    Section("Answer") {
                        TextEditor(text: $bullets).frame(minHeight: 60)
                        Text("The label this card's mask covers. The mask itself is set where the card was made.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Why / how") {
                    TextEditor(text: $working.why).frame(minHeight: 70)
                }
                if let source = working.source, !source.isEmpty {
                    Section("From") {
                        Text(source).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
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
/// cannot end up pointing at an option that no longer exists.
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
                }
                Section("Options") {
                    ForEach(working.options.indices, id: \.self) { index in
                        HStack(spacing: 10) {
                            Button { working.correctIndex = index } label: {
                                Image(systemName: working.correctIndex == index
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(working.correctIndex == index ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            TextField("Option", text: $working.options[index], axis: .vertical)
                        }
                    }
                    .onDelete { offsets in
                        working = Self.removing(offsets, from: working)
                    }
                    Button("Add an option", systemImage: "plus") { working.options.append("") }
                        .font(.footnote)
                }
                Section("Explanation") {
                    TextEditor(text: $working.explanation).frame(minHeight: 90)
                }
                if let source = working.source, !source.isEmpty {
                    Section("From") {
                        Text(source).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(Self.tidied(working))
                        dismiss()
                    }
                    .disabled(working.options.count < 2)
                }
            }
        }
    }

    /// The key is remembered by its TEXT before anything is removed, then found
    /// again afterwards.
    ///
    /// Every one of these operations shifts the positions after it, and
    /// correctIndex is a position. Falling back to 0 when the maths goes wrong
    /// does not fail loudly - it silently marks the first option correct, and
    /// the student finds out when the app tells them they got it wrong.
    static func removing(_ offsets: IndexSet, from question: MCQQuestion) -> MCQQuestion {
        var out = question
        let key = out.options.indices.contains(out.correctIndex)
            ? out.options[out.correctIndex] : nil
        out.options.remove(atOffsets: offsets)
        out.correctIndex = key.flatMap { out.options.firstIndex(of: $0) } ?? 0
        return out
    }

    /// Blank options are dropped on the way out, which moves positions too.
    static func tidied(_ question: MCQQuestion) -> MCQQuestion {
        var out = question
        let key = out.options.indices.contains(out.correctIndex)
            ? out.options[out.correctIndex].trimmingCharacters(in: .whitespaces) : nil
        out.options = out.options
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        out.correctIndex = key.flatMap { out.options.firstIndex(of: $0) } ?? 0
        return out
    }
}
