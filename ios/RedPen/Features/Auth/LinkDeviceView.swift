import SwiftUI

/// Putting the same library on a second device: this one shows a code, the
/// other types it. No Apple or Google account needed on either.
struct LinkDeviceView: View {
    /// Only the "enter a code" half, for the sign-in screen of a new device.
    var joinOnly = false

    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss

    @State private var code: String?
    @State private var expires: Date?
    @State private var typed = ""
    @State private var joined = false

    var body: some View {
        NavigationStack {
            Form {
                if !joinOnly {
                    Section {
                        if let code, let expires {
                            VStack(spacing: 10) {
                                Text(String(code.prefix(4)) + "\u{2009}\u{2013}\u{2009}" + String(code.suffix(4)))
                                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                                    .textSelection(.enabled)
                                    .accessibilityLabel(code.map(String.init).joined(separator: " "))
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    let left = max(0, Int(expires.timeIntervalSince(context.date)))
                                    Text(left > 0 ? "Works once, for \(left / 60):\(String(format: "%02d", left % 60))" : "Expired \u{2014} make a new one")
                                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        Button(code == nil ? "Show a code" : "Make a new code") { Task { await makeCode() } }
                            .disabled(account.busy)
                    } header: {
                        Text("Add another device")
                    } footer: {
                        Text("Part of Pro. On your other iPhone or iPad, open \(Brand.name) and choose \u{201C}I have a code\u{201D} (or Account \u{2192} Link another device), then type this code. Your library, folders and review schedule then stay the same on both.")
                    }
                }

                Section {
                    TextField("Code", text: $typed)
                        .font(.title3.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: typed) { _, new in
                            let clean = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
                            if clean != new { typed = clean }
                        }
                    Button("Join") { Task { await join() } }
                        .disabled(typed.count != 8 || account.busy)
                } header: {
                    Text(joinOnly ? "Code from your other device" : "Join another device's library")
                } footer: {
                    Text(joinOnly
                         ? "On the device you already use: Account \u{2192} Link another device \u{2192} Show a code."
                         : "What is on this device is kept and added to that library.")
                }

                if account.busy {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
                if let trouble = account.trouble {
                    Section { Text(trouble).foregroundStyle(.red) }
                }
                if joined {
                    Section { Label("Linked. Your library is syncing.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Link another device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func makeCode() async {
        // a this-device-only library gets an account first, and goes up
        let newAccount = account.state.session?.isLocalOnly == true
        guard let session = await account.ensureServerSession() else { return }
        do {
            let made = try await AuthAPI.pairingCode(token: session.token)
            code = made.code
            expires = Date().addingTimeInterval(TimeInterval(made.expiresIn))
            if newAccount { Task { await syncFresh() } }
        } catch {
            account.trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func join() async {
        guard await account.join(code: typed) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        joined = true
        await syncFresh()
        if joinOnly { dismiss() }
    }

    /// A new account under this library: everything is sent and fetched afresh.
    private func syncFresh() async {
        sync.forgetEverythingSynced()
        await sync.syncNow()
    }
}
