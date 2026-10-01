import SwiftUI

/// What More > Report a problem is about: the item on screen, in its set.
struct QuestionReport: Identifiable {
    let id = UUID()
    let set: StudySet
    let item: AccuracyItem
}

/// "Report a problem" for the question or card on screen: a reason, an
/// optional note, Send. Queued on the device and delivered when it can be
/// (SupportSender), so it works offline and signed out alike. It goes to the
/// accuracy engine's reports, which is where a wrong question gets fixed.
struct QuestionReportSheet: View {
    let report: QuestionReport
    @Environment(\.dismiss) private var dismiss
    @State private var reason: SupportReason = .wrongAnswer
    @State private var note = ""
    @State private var sending = false
    @State private var outcome: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Reporting") {
                    Text(preview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }
                Section("What\u{2019}s wrong?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(SupportReason.allCases) { r in
                            Text(r.title).tag(r)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("reportNote")
                } footer: {
                    Text("Only this \(report.item.kind.noun), the reason and your note are sent. Nothing else from your library.")
                }
                if let outcome {
                    Section {
                        Label(outcome, systemImage: "checkmark.circle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outcome == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if outcome == nil {
                        Button("Send") { Task { await send() } }
                            .disabled(sending)
                            .accessibilityIdentifier("reportSend")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var preview: String {
        let item: AccuracyItem = report.item
        let head: String = item.stem.isEmpty ? item.text : item.stem
        return Highlight.plain(head)
    }

    private func send() async {
        sending = true
        outcome = await SupportSender.shared.report(report.item, reason: reason, note: note)
        sending = false
    }
}
