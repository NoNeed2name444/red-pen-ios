import SwiftUI

/// Typing the six digits that arrived by email.
///
/// Pasting is the normal way this gets filled in, so the field accepts whatever
/// comes off the clipboard and pulls the digits out of it - people paste "Your
/// Red Pen code is 482913", or the code with a space in the middle, and being
/// refused for that is maddening.
///
/// It also submits itself once six digits are in. Nobody wants to type a code
/// and then look for a button.
struct EmailCodeView: View {
    @EnvironmentObject var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var now = Date()
    @FocusState private var focused: Bool

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Check your email")
                    .font(.title2.weight(.bold))
                Text("We sent a six-digit code to \(account.pendingEmail ?? "your address").")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("000000", text: $typed)
                    .font(.system(.largeTitle, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .padding(.vertical, 10)
                    .background(.thinMaterial,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: typed) { _, value in
                        // filled in by paste or by the keyboard's own
                        // suggestion: either way, do not make them hunt for a
                        // button afterwards
                        if AuthRules.normalisedCode(value) != nil { verify() }
                    }

                Button {
                    verify()
                } label: {
                    HStack {
                        if account.busy { ProgressView().controlSize(.small) }
                        Text("Sign in")
                    }
                    .frame(maxWidth: .infinity).frame(height: 46)
                }
                .buttonStyle(.glassProminent)
                .disabled(account.busy || AuthRules.normalisedCode(typed) == nil)

                resend

                if let trouble = account.trouble {
                    Text(trouble).font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
            .onReceive(tick) { now = $0 }
            .onChange(of: account.isSignedIn) { _, signedIn in
                if signedIn { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var resend: some View {
        let ready = AuthRules.canResend(lastSentAt: account.codeSentAt, now: now)
        Button(ready ? "Send another code" : "Send another code in \(secondsLeft)s") {
            Task { _ = await account.sendCode(to: account.pendingEmail ?? "") }
        }
        .font(.footnote)
        .disabled(!ready || account.busy)
    }

    private var secondsLeft: Int {
        guard let sent = account.codeSentAt else { return 0 }
        return max(0, Int(AuthRules.resendAfter - now.timeIntervalSince(sent).rounded()))
    }

    private func verify() {
        Task { await account.verifyCode(typed) }
    }
}
