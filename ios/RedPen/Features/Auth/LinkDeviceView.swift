import SwiftUI

/// Putting the same library on a second device: this one shows a code, the
/// other types it. No Apple or Google account needed on either.
///
/// The one button - Show a code, or Join once a code is being typed - sits
/// in the bar at the bottom, so it rides above the keyboard. A typed code
/// joins by itself once all eight characters are in.
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
    /// The last code sent, so a wrong one is not sent again on its own.
    @State private var tried = ""
    @FocusState private var typing: Bool
    @Environment(\.windowSpan) private var span

    private static let field = RoundedRectangle(cornerRadius: 14, style: .continuous)

    /// A centred sheet: on a wide iPad the bar must centre under the form
    /// rather than hug the trailing edge as it does on a full-width screen.
    private var sheetSpan: WindowSpan { min(span, WindowSpan.middling) }

    var body: some View {
        NavigationStack {
            Form {
                if !joinOnly { showSection }
                joinSection
                statusRows
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .navigationTitle("Link another device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .studyBar { primary }
        }
        .environment(\.windowSpan, sheetSpan)
    }

    // MARK: This device shows a code

    private var showSection: some View {
        Section {
            if let code, let expires {
                PairingCodeSlab(code: code, expires: expires)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
        } header: {
            Text("Add another device")
        } footer: {
            Text("Part of Pro. On your other iPhone or iPad, open \(Brand.name) and choose \u{201C}I have a code\u{201D} (or Account \u{2192} Link another device), then type this code. Your library, folders and review schedule then stay the same on both.")
        }
    }

    // MARK: This device types one

    private var joinSection: some View {
        Section {
            TextField("Code", text: $typed)
                .font(.title3.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.join)
                .focused($typing)
                .onSubmit { Task { await join() } }
                .onChange(of: typed) { _, new in typedChanged(new) }
                // the field on its own raised surface, standing out of the
                // glass like the code slab above it; no lean, for the caret
                .padding(12)
                .background(.regularMaterial, in: LinkDeviceView.field)
                .popOut(.raised, in: LinkDeviceView.field, cues: .translateOnly)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        } header: {
            Text(joinHeader)
        } footer: {
            Text(joinFooter)
        }
    }

    private var joinHeader: String {
        if joinOnly { return "Code from your other device" }
        return "Join another device's library"
    }

    private var joinFooter: String {
        if joinOnly { return "On the device you already use: Account \u{2192} Link another device \u{2192} Show a code." }
        return "What is on this device is kept and added to that library."
    }

    @ViewBuilder
    private var statusRows: some View {
        if account.busy {
            Section { ProgressView().frame(maxWidth: .infinity) }
        }
        if let trouble = account.trouble {
            Section { Text(trouble).foregroundStyle(.red) }
        }
        if joined {
            Section {
                Label("Linked. Your library is syncing.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: The one button

    /// Join once there is a code in the field, and always when joining is all
    /// this screen does; otherwise showing a code. Not on focus alone: the
    /// form has no way to put the keyboard away, so an empty focused field
    /// must leave Show a code in reach.
    private var joining: Bool { joinOnly || !typed.isEmpty }

    private var showTitle: String {
        if code == nil { return "Show a code" }
        return "Make a new code"
    }

    @ViewBuilder
    private var primary: some View {
        if joining {
            Button { Task { await join() } } label: {
                Label("Join", systemImage: "link")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(typed.count != 8 || account.busy)
        } else {
            Button { Task { await makeCode() } } label: {
                Label(showTitle, systemImage: "number.square")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(account.busy)
        }
    }

    // MARK: Doing it

    /// Letters and digits only, upper case, eight at most; all eight joins.
    private func typedChanged(_ new: String) {
        let clean: String = LinkDeviceView.cleaned(new)
        if clean != new {
            typed = clean
            return
        }
        if clean.count == 8 && clean != tried && !account.busy {
            Task { await join() }
        }
    }

    static func cleaned(_ text: String) -> String {
        let kept: String = text.uppercased().filter { $0.isLetter || $0.isNumber }
        return String(kept.prefix(8))
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
        guard typed.count == 8, !account.busy else { return }
        tried = typed
        guard await account.join(code: typed) else { return }
        typing = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        joined = true
        // the code works once: clear it, so neither Join nor Return can send
        // it again under the green row
        typed = ""
        tried = ""
        await syncFresh()
        if joinOnly { dismiss() }
    }

    /// A new account under this library: everything is sent and fetched afresh.
    /// Linking is how the student said this library belongs with that account,
    /// so it goes up without being asked about again.
    private func syncFresh() async {
        sync.forgetEverythingSynced(libraryNowBelongsTo: account.account?.id)
        await sync.syncNow()
    }
}

/// The code to type on the other device, on a slab that stands out of the
/// glass, with how long it still works.
private struct PairingCodeSlab: View {
    let code: String
    let expires: Date

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(spacing: 10) {
            Text(PairingCodeSlab.spaced(code))
                .scaledFont(40, relativeTo: .largeTitle, weight: .bold, design: .monospaced)
                .textSelection(.enabled)
                .accessibilityLabel(PairingCodeSlab.spoken(code))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(PairingCodeSlab.countdown(until: expires, now: context.date))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: shape)
        .popOut(.raised, in: shape)
    }

    /// "ABCD – EFGH", with thin spaces round the dash.
    static func spaced(_ code: String) -> String {
        let head: String = String(code.prefix(4))
        let tail: String = String(code.suffix(4))
        let dash: String = "\u{2009}\u{2013}\u{2009}"
        return head + dash + tail
    }

    /// One character at a time, for VoiceOver.
    static func spoken(_ code: String) -> String {
        let letters: [String] = code.map { String($0) }
        return letters.joined(separator: " ")
    }

    static func countdown(until expires: Date, now: Date) -> String {
        let left: Int = max(0, Int(expires.timeIntervalSince(now)))
        guard left > 0 else { return "Expired \u{2014} make a new one" }
        let minutes: Int = left / 60
        let seconds: String = String(format: "%02d", left % 60)
        return "Works once, for \(minutes):\(seconds)"
    }
}
