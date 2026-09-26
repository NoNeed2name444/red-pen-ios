import SwiftUI

/// Fixing a misheard word, from the transcript itself.
///
/// The student is mid-lecture, so the whole interaction is one tap and one
/// short answer: tap the word, type what it should say, done. What happens
/// next is deliberately shown rather than hidden - the fix spreads to every
/// other word in the transcript that SOUNDS the same, which is a long reach
/// for one tap, so the count is reported and a single Undo takes all of it back.
struct FixTarget: Identifiable {
    var id: String { "\(segment).\(word)" }
    let segment: Int
    let word: Int
    let heard: String
}

struct FixWordSheet: View {
    let target: FixTarget
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var spelling = ""
    @FocusState private var typing: Bool

    private var usable: Bool {
        !spelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                field("Heard as") {
                    Text(target.heard)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                }
                field("Should be") {
                    TextField("the correct spelling", text: $spelling)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit { if usable { save() } }
                        .popField()
                }
                // Said plainly up front, because the student is about to change
                // more of the transcript than the word they tapped.
                Label("Every other word that sounds the same is fixed too, and remembered for next time.",
                      systemImage: "wand.and.sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 0)
            }
            .padding()
            // the one action, under the thumb and standing out of the glass;
            // it rides above the keyboard while the spelling is typed
            .studyBar {
                Button("Fix", action: save)
                    .buttonStyle(.bigPrimary)
                    .disabled(!usable)
            }
            .navigationTitle("Fix this word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // kept for a hardware keyboard and for habit; the bar below
                // is the one the thumb finds
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fix") { save() }.disabled(!usable)
                }
            }
            .onAppear { typing = true }
        }
        // taller than before by the bar at the bottom
        .presentationDetents([.height(390)])
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func save() {
        let wanted = spelling.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return }
        onSave(wanted)
        dismiss()
    }
}

/// What a correction did, shown until it is dismissed or undone.
///
/// A toast rather than an alert: the student is reading, and a correction that
/// interrupts the lecture to congratulate itself is worse than one that does
/// not report at all.
struct FixReport: View {
    let summary: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
            Text(summary).font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        // a floating surface, on the same plane as the bar it sits above
        .popOut(.floating, in: Capsule())
        .padding(.horizontal)
        .transition(.slideFade(.bottom))
    }
}
