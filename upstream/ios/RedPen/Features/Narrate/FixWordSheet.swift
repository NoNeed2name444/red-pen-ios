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
                        .foregroundStyle(Color.wardDanger)
                        .underline(true, color: Color.wardDanger.opacity(0.5))
                        .textSelection(.enabled)
                }
                field("Should be") {
                    TextField("the correct spelling", text: $spelling)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit { if usable { save() } }
                        .wardField()
                }
                // Said plainly up front, because the student is about to change
                // more of the transcript than the word they tapped.
                Label("Every other word that sounds the same is fixed too, and remembered for next time.",
                      systemImage: "wand.and.sparkles")
                    .font(.footnote)
                    .foregroundStyle(Color.wardInkSecondary)
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 0)
            }
            .padding()
            .wardScreen()
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
                    .buttonStyle(.wardQuiet)
                }
                .sharedBackgroundVisibility(.hidden)
                // kept for a hardware keyboard and for habit; the bar below
                // is the one the thumb finds
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fix") { save() }
                    .buttonStyle(.wardCompact).disabled(!usable)
                }
                .sharedBackgroundVisibility(.hidden)
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
                .wardSmallCaps()
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
                .foregroundStyle(Color.wardSuccess)
                .accessibilityHidden(true)
            Text(summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.wardInk)
            Spacer(minLength: 0)
            Button("Undo", action: onUndo)
                .buttonStyle(.wardCompact)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // a soft slip floating over the transcript
        .wardRaised(in: Capsule(), lift: .high)
        .padding(.horizontal)
        .transition(.slideIn(.bottom))
    }
}
