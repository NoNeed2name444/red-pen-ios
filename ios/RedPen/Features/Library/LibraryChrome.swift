import SwiftUI

/// The library's own backdrop: a warm paper tone with a whisper of pen red,
/// matching the web app's cream-and-red identity.
struct LibraryBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            RadialGradient(colors: [StudySetKind.mcq.tint.opacity(scheme == .dark ? 0.22 : 0.14), .clear],
                           center: .init(x: 1.0, y: 0.0), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [StudySetKind.anki.tint.opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                           center: .init(x: 0.0, y: 1.0), startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
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
