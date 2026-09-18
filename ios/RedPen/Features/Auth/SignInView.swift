import SwiftUI
import AuthenticationServices

/// The way in.
///
/// Three doors, in the order people actually use them. Apple first because on
/// this platform it is one tap and gives away the least; Google because most
/// students are already signed in to it in Safari; email last because it is the
/// one that involves waiting for something to arrive.
///
/// What this screen does not do is ask for a password. Nothing here stores one,
/// so nothing here can leak one.
struct SignInView: View {
    @EnvironmentObject var account: AccountStore
    @State private var email = ""
    @State private var showingCode = false

    var body: some View {
        ZStack {
            LibraryBackdrop()
            ScrollView {
                VStack(spacing: 22) {
                    masthead
                    buttons
                    emailBox
                    smallPrint
                }
                .padding(.horizontal, 28)
                .padding(.top, 48)
                .padding(.bottom, 32)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingCode) { EmailCodeView() }
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
            Text("Your lectures, turned into questions and cards \u{2014} on this phone.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 6)
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
                    Image(systemName: "globe")
                    Text("Continue with Google").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.glass)
            .disabled(account.busy)
        }
    }

    private var emailBox: some View {
        VStack(spacing: 10) {
            HStack {
                Rectangle().fill(.quaternary).frame(height: 1)
                Text("or").font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            .padding(.vertical, 4)

            TextField("you@university.edu", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .submitLabel(.send)
                .onSubmit { send() }

            Button {
                send()
            } label: {
                HStack {
                    if account.busy { ProgressView().controlSize(.small) }
                    Text("Email me a code")
                }
                .frame(maxWidth: .infinity).frame(height: 46)
            }
            .buttonStyle(.glassProminent)
            .disabled(account.busy || AuthRules.normalisedEmail(email) == nil)
        }
    }

    private var smallPrint: some View {
        Text("Your decks, recordings and transcripts stay on this phone. An account carries your subscription, nothing else.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }

    private func send() {
        Task {
            if await account.sendCode(to: email) { showingCode = true }
        }
    }
}
