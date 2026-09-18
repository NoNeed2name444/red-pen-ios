import Foundation
import Combine

/// Who is signed in, and how they got there.
///
/// One object so that every screen asks the same question of the same place.
/// The session itself lives in the keychain; this holds it in memory while the
/// app runs and keeps the two in step.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var state: AccountState = .signedOut
    @Published var busy = false
    @Published var trouble: String?

    /// When a code was last sent, so the resend button can say no for a moment
    /// rather than letting somebody mail themselves ten codes.
    @Published private(set) var codeSentAt: Date?
    @Published var pendingEmail: String?

    private let apple = AppleSignIn()
    private let google = GoogleSignIn()

    init(session: Session? = nil) {
        if let session {
            state = .signedIn(session)
        } else if let stored = Keychain.session(), stored.isValid() {
            state = .signedIn(stored)
        }
    }

    var isSignedIn: Bool { state.isSignedIn }
    var account: Account? { state.account }

    // MARK: signing in

    func signInWithApple() async {
        await attempt { try await self.apple.run() }
    }

    func signInWithGoogle() async {
        await attempt { try await self.google.run() }
    }

    /// Sends a code. The answer is the same whether or not the address is
    /// already known - telling somebody "no account with that address" turns
    /// the sign-in form into a way of finding out who has one.
    func sendCode(to rawEmail: String) async -> Bool {
        guard let email = AuthRules.normalisedEmail(rawEmail) else {
            trouble = "That doesn't look like an email address."
            return false
        }
        guard AuthRules.canResend(lastSentAt: codeSentAt) else { return false }
        busy = true
        trouble = nil
        defer { busy = false }
        do {
            try await AuthAPI.requestCode(email: email)
            pendingEmail = email
            codeSentAt = Date()
            return true
        } catch {
            trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func verifyCode(_ raw: String) async {
        guard let email = pendingEmail else { return }
        guard let code = AuthRules.normalisedCode(raw) else {
            trouble = "A code is six digits."
            return
        }
        await attempt { try await AuthAPI.verifyCode(email: email, code: code) }
    }

    private func attempt(_ work: @escaping () async throws -> Session) async {
        busy = true
        trouble = nil
        defer { busy = false }
        do {
            let session = try await work()
            adopt(session)
        } catch is CancellationError {
            // backing out of a sign-in sheet is not a problem to report
        } catch {
            trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func adopt(_ session: Session) {
        Keychain.save(session)
        pendingEmail = nil
        codeSentAt = nil
        state = .signedIn(session)
    }

    // MARK: staying signed in

    /// Renews the session before it dies rather than after, so nothing fails
    /// halfway through. A refresh that cannot reach the server is left alone:
    /// the session is still valid for now, and signing somebody out because
    /// their train went into a tunnel would be absurd.
    func refreshIfNeeded() async {
        guard let session = state.session, session.needsRefresh(),
              let refreshToken = session.refreshToken else { return }
        do {
            adopt(try await AuthAPI.refresh(refreshToken))
        } catch AuthAPI.Failure.offline {
            return
        } catch {
            // the server refused the refresh token: that session is genuinely
            // over, and pretending otherwise only delays the sign-in screen
            if !session.isValid() { signOut() }
        }
    }

    // MARK: leaving

    func signOut() {
        Keychain.clearSession()
        pendingEmail = nil
        codeSentAt = nil
        state = .signedOut
    }

    /// Deleting the account, from inside the app.
    ///
    /// The App Store requires this of any app that can create an account, and
    /// it is right anyway: somebody who signed up in two taps should not have
    /// to email support to leave. The student's decks are not touched - they
    /// were never on the server to delete.
    func deleteAccount() async -> Bool {
        guard let session = state.session else { return false }
        busy = true
        trouble = nil
        defer { busy = false }
        do {
            try await AuthAPI.deleteAccount(token: session.token)
            signOut()
            return true
        } catch {
            trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
