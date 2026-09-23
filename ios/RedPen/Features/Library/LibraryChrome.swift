import SwiftUI

/// The library's own backdrop: the brand's pen red with indigo and teal, or
/// the colours of the mode whose tab is open, so switching tabs changes the
/// room you are in.
struct LibraryBackdrop: View {
    var kind: StudySetKind? = nil
    var body: some View {
        if let kind {
            ModeBackdrop(kind: kind)
        } else {
            LivingBackdrop(hues: [StudySetKind.mcq.tint, StudySetKind.anki.tint, StudySetKind.book.tint])
        }
    }
}

/// A one-field naming sheet used for new folders, combined sets and renames -
/// the native stand-in for the web app's inline save forms.
struct NameSheet: View {
    let title: String
    let prompt: String
    let initial: String
    let confirm: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(prompt, text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm, action: submit)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = initial; focused = true }
        }
        .presentationDetents([.height(180)])
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
        dismiss()
    }
}
