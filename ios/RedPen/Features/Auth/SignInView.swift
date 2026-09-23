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

    @State private var localName = ""

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
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
                request.nonce = account.beginApple()
            } onCompletion: { result in
                Task { await account.finishApple(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                Task { await account.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    if account.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "globe")
                    }
                    Text("Continue with Google").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.glass)
            .disabled(account.busy)

            // Personal build: no Apple or Google account, no server.
            VStack(spacing: 8) {
                TextField("Your name", text: $localName)
                    .textContentType(.name)
                    .textFieldStyle(.roundedBorder)
                Button {
                    account.useThisDeviceOnly(name: localName)
                } label: {
                    Text("Use on this device only").fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.glassProminent)
                Text("No account needed. Your sets stay on this device and aren't synced.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)
        }
    }

    private var smallPrint: some View {
        Text("Your account carries your decks between your devices. Nothing is shared with anyone else.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }
}
