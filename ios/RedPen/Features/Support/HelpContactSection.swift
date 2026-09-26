import SwiftUI

/// "Contact us" for the Help page, as one List/Form section: a topic, a
/// message, Send. Delivered to the server's POST /support/message through the
/// same offline outbox as question reports, so it can be written on a train.
///
/// Drop into HelpPage's List: `HelpContactSection()`.
struct HelpContactSection: View {
    @ObservedObject private var sender = SupportSender.shared
    @State private var topic: ContactTopic = .problem
    @State private var message = ""
    @State private var sending = false
    @State private var outcome: String?
    @FocusState private var writing: Bool

    private var canSend: Bool {
        !sending && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    var body: some View {
        Section {
            Picker("About", selection: $topic) {
                ForEach(ContactTopic.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.menu)
            TextField("Your message", text: $message, axis: .vertical)
                .lineLimit(3...8)
                .focused($writing)
                .accessibilityIdentifier("contactMessage")
            Button {
                Task { await send() }
            } label: {
                Label(sending ? "Sending\u{2026}" : "Send", systemImage: "paperplane")
            }
            .disabled(!canSend)
            .accessibilityIdentifier("contactSend")
            if let outcome {
                Label(outcome, systemImage: "checkmark.circle")
                    .font(.footnote)
            }
            if sender.waiting > 0 && outcome == nil {
                Label("\(sender.waiting) waiting to send", systemImage: "tray.and.arrow.up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(l10n: "Contact us")
        } footer: {
            Text("A wrong question or card? Open it and use More \u{2192} Report a problem, so we know exactly which one. Messages include the app version, nothing from your library.")
        }
    }

    private func send() async {
        sending = true
        writing = false
        let text: String = message
        outcome = await SupportSender.shared.contact(topic, message: text)
        message = ""
        sending = false
    }
}
