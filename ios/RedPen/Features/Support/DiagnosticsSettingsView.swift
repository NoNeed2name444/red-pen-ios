import SwiftUI
import UIKit

/// Settings > AI models > Crash and failure reports: the on/off switch and
/// exactly what is sent. In the owner's personal build, also the developer
/// tools: what is waiting and what was sent, "Send now", "Copy report", and
/// buttons that make a failure, a hang or a real crash to test the pipeline.
struct DiagnosticsSettingsView: View {
    @AppStorage(Diagnostics.enabledKey) private var enabled = true
    @EnvironmentObject private var account: AccountStore
    @State private var queued: [DiagEvent] = []
    @State private var recent: [DiagEvent] = []
    @State private var sentToday = 0
    @State private var status = ""
    @State private var sending = false
    @State private var confirmCrash = false

    var body: some View {
        Form {
            Section {
                Toggle("Send crash and failure reports", isOn: $enabled)
            } footer: {
                Text(Self.privacyText)
            }
            if PersonalBuild.isOn {
                developerSection
                eventsSection("Waiting to send", queued)
                eventsSection("Sent lately", recent)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle("Diagnostics")
        .diagnosticsScreen("screen:diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .onChange(of: enabled) { _, on in
            // off: nothing already waiting goes later either
            if !on { Diagnostics.center.clear() }
            reload()
        }
        .confirmationDialog("Crash the app now?", isPresented: $confirmCrash, titleVisibility: .visible) {
            Button("Crash", role: .destructive) { DiagnosticsRuntime.simulateCrash() }
        } message: {
            Text("The app closes at once. Open it again: the crash is reported at that launch, with the screens that led to it.")
        }
    }

    static let privacyText: String =
        "When the app crashes, freezes or something fails, a short technical report goes to our server so it can be fixed: which part of the app, a fixed error code, the names of the last screens you opened, and your device model, iOS and app version, memory, free space, temperature state and graphics setting. It never includes your notes, questions, lectures, recordings, name or email. At most 40 reports a day; they are stored with your account and deleted with it."

    private var developerSection: some View {
        Section {
            LabeledContent("Waiting", value: "\(queued.count)")
            LabeledContent("Sent today", value: "\(sentToday)")
            Button {
                Task { await sendNow() }
            } label: {
                HStack {
                    if sending { ProgressView().controlSize(.small) }
                    Text(account.state.session?.isLocalOnly == true
                         ? "Send now (gives this device a server account)" : "Send now")
                }
            }
            .disabled(sending || !enabled)
            Button("Copy report", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = DiagReportText.text(queued + recent, device: Diagnostics.center.device())
                status = "Copied."
            }
            Button("Simulate a failure") {
                DiagnosticsRuntime.simulateFailure()
                reload()
            }
            Button("Simulate a hang (4 seconds)") { DiagnosticsRuntime.simulateHang() }
            Button("Simulate a crash", role: .destructive) { confirmCrash = true }
            if !status.isEmpty {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Developer \u{00B7} personal build")
        } footer: {
            Text("Reports become GitHub issues each day (diagnostics-triage workflow). Crashes and hangs come from MetricKit on the next launch, only with Share With App Developers on; an app killed while open is reported by itself.")
        }
    }

    @ViewBuilder
    private func eventsSection(_ title: String, _ events: [DiagEvent]) -> some View {
        if !events.isEmpty {
            Section(title) {
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DiagFingerprint.title(event, binary: event.device?.binary ?? "RedPen"))
                            .font(.footnote.weight(.semibold))
                        Text(detail(event)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func detail(_ event: DiagEvent) -> String {
        let when: String = Date(timeIntervalSince1970: TimeInterval(event.at)).formatted(date: .abbreviated, time: .shortened)
        let times: String = event.count > 1 ? " \u{00B7} \u{00D7}\(event.count)" : ""
        return "\(event.kind.rawValue) \u{00B7} \(when)\(times) \u{00B7} \(event.fingerprint)"
    }

    private func reload() {
        let snapshot = Diagnostics.center.snapshot()
        queued = snapshot.queued
        recent = snapshot.recent
        sentToday = snapshot.sentToday
        if status.isEmpty { status = DiagnosticsRuntime.lastStatus }
    }

    /// The personal build signs in "on this device only", with no server
    /// account: sending asks for one first (the same as linking a device).
    private func sendNow() async {
        sending = true
        defer { sending = false }
        var token: String? = account.token
        if account.state.session?.isLocalOnly == true {
            token = await account.ensureServerSession()?.token
        }
        status = await DiagnosticsRuntime.sendIfDue(token: token, force: true)
        reload()
    }
}
