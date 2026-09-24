import SwiftUI

/// The library's backdrop: the same slow mesh as every mode's screen, as it is
/// on the "All" shelf and faintly in a mode's colour on that mode's shelf,
/// easing from one to the other as the dock moves.
///
/// It was made still and grey once, because the old one was a loud three-colour
/// gradient that flickered when it was redrawn on every tab switch. The shared
/// backdrop is quiet enough to move, and fades rather than redraws.
struct LibraryBackdrop: View {
    var kind: StudySetKind? = nil
    var body: some View {
        AppBackdrop(tint: kind?.tint)
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
