import SwiftUI

/// The backdrop of the pages that belong to no one mode: the same slow mesh
/// as every mode's screen, as it is.
struct LibraryBackdrop: View {
    var body: some View {
        AppBackdrop(tint: nil)
    }
}

/// A one-field naming sheet used for new folders, combined sets and renames -
/// the native stand-in for the web app's inline save forms.
///
/// One field on the backdrop rather than a one-row Form: the field is the
/// only thing to touch, so it stands a little out of the glass - moving only
/// sideways with the tilt, never leaning, so the caret holds still under the
/// eye. Return saves; Cancel and the confirm button sit in the system's own
/// places at the top.
struct NameSheet: View {
    let title: String
    let prompt: String
    let initial: String
    let confirm: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    init(title: String, prompt: String, initial: String, confirm: String,
         onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.prompt = prompt
        self.initial = initial
        self.confirm = confirm
        self.onConfirm = onConfirm
    }

    private var blank: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                field
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LibraryBackdrop())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm, action: submit)
                        .disabled(blank)
                }
            }
            .onAppear { name = initial; focused = true }
        }
        .presentationDetents([.height(220), .medium])
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return TextField(prompt, text: $name)
            .focused($focused)
            .submitLabel(.done)
            .onSubmit(submit)
            .padding(14)
            .background(.regularMaterial, in: shape)
            .popOut(.raised, in: shape, cues: .translateOnly)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
        dismiss()
    }
}
