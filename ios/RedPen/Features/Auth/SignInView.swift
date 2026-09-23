import SwiftUI
import AuthenticationServices

/// The way in.
///
/// Two doors. Apple first because on this platform it is one tap and gives away
/// the least; Google because most students are already signed in to it in
/// Safari, so it is usually one tap too.
///
/// What this screen does not do is ask for a password. Nothing here stores one,
/// so nothing here can leak one.
struct SignInView: View {
    @EnvironmentObject var account: AccountStore

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LibraryBackdrop()
            ScrollView {
                VStack(spacing: 22) {
                    masthead
                    buttons
                    smallPrint
                }
                .padding(.horizontal, 28)
                .padding(.top, 64)
                .padding(.bottom, 32)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .alert("Couldn't sign in", isPresented: Binding(
            get: { account.trouble != nil }, set: { if !$0 { account.trouble = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(account.trouble ?? "")
        }
    }

    private var masthead: some View {
        VStack(spacing: 10) {
            HStack(spacing: -10) {
                ForEach([StudySetKind.mcq, .anki, .qa], id: \.self) { kind in
                    ModeTile(kind: kind, size: 52)
                        .rotationEffect(.degrees(kind == .anki ? 0 : (kind == .mcq ? -10 : 10)))
                }
            }
            Text("Red Pen").font(.largeTitle.weight(.bold))
            Text("Your lectures, turned into questions and cards \u{2014} on every device you study on.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 10)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            // Personal build: straight in, no Apple or Google account and no
            // server. First, because it is the one that works on its own.
            Button {
                account.useThisDeviceOnly(name: "")
            } label: {
                doorLabel("Use on this device only", symbol: "iphone.gen3")
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.78, green: 0.16, blue: 0.16)))
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("localSignIn")

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
                request.nonce = account.beginApple()
            } onCompletion: { result in
                Task { await account.finishApple(result) }
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Drawn to match Apple's button - same height, corners, weight and
            // colours - so the three read as one set of choices.
            Button {
                Task { await account.signInWithGoogle() }
            } label: {
                doorLabel("Sign in with Google", symbol: "globe", busy: account.busy)
                    .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(scheme == .dark ? Color.white : Color.black))
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(account.busy)

            Text("\u{201C}This device only\u{201D} needs no account: your sets stay here and aren\u{2019}t synced.")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func doorLabel(_ title: String, symbol: String, busy: Bool = false) -> some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small) } else { Image(systemName: symbol).font(.system(size: 17, weight: .semibold)) }
            Text(title).font(.system(size: 19, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
    }

    private var smallPrint: some View {
        Text("Your account carries your decks between your devices. Nothing is shared with anyone else.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }
}
