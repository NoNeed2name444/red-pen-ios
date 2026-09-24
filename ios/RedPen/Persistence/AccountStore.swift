import Foundation
import Combine
import AuthenticationServices

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

    private let google = GoogleSignIn()
    /// The raw nonce for a sign-in in progress. Apple is given only its hash,
    /// and the server is told both - which is what stops a token captured from
    /// one sign-in being replayed into another.
    private var appleNonce = ""

    init(session: Session? = nil) {
        if let session {
            state = .signedIn(session)
        } else if let stored = Keychain.session(), stored.isValid() {
            state = .signedIn(stored)
        }
    }

    var isSignedIn: Bool { state.isSignedIn }
    var account: Account? { state.account }
    var token: String? { state.session?.token }

    // MARK: Apple

    /// Called as Apple's own button builds its request; returns the hashed
    /// nonce it should carry.
    func beginApple() -> String {
        appleNonce = AuthRules.nonce()
        return AuthRules.sha256Hex(appleNonce)
    }

    func finishApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            trouble = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8) else {
                trouble = "Apple didn't return a usable sign-in."
                return
            }
            // Apple gives the name ONCE, on the very first sign-in, and never
            // again - so it goes straight through rather than being asked for
            // later, when it no longer exists.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            let nonce = appleNonce
            await attempt {
                try await AuthAPI.signInWithApple(identityToken: token, nonce: nonce,
                                                  fullName: name.isEmpty ? nil : name)
            }
        }
    }

    // MARK: Google

    func signInWithGoogle() async {
        await attempt { try await self.google.run() }
    }

    // MARK: the shared plumbing

    private func attempt(_ work: @escaping () async throws -> Session) async {
        busy = true
        trouble = nil
        defer { busy = false }
        do {
            adopt(try await work())
        } catch is CancellationError {
            // backing out of a sign-in sheet is not a problem to report
        } catch {
            trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: personal build

    /// Personal build only: sign in as yourself with no Apple or Google
    /// account and no server. The session never expires and never syncs;
    /// the library stays on this device.
    func useThisDeviceOnly(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        adopt(Session(
            account: Account(id: "local-" + UUID().uuidString, provider: .email,
                             email: nil, displayName: trimmed.isEmpty ? "Me" : trimmed),
            token: Session.localToken, refreshToken: nil,
            expiresAt: Date.distantFuture))
    }

    // MARK: linking devices

    /// The session to sync with, making a server account for a device that
    /// started "on this device only" (its name kept). Nil with a reason in
    /// `trouble` when the server cannot be reached.
    func ensureServerSession() async -> Session? {
        guard let current = state.session else { return nil }
        guard current.isLocalOnly else { return current }
        busy = true
        trouble = nil
        defer { busy = false }
        do {
            var made = try await AuthAPI.deviceAccount(claim: OwnerClaim.bundled)
            made.account.displayName = current.account.displayName
            carryAgreement(from: current, to: made)
            adopt(made)
            return made
        } catch {
            trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Joins the account another device shows a code for. True when it worked.
    func join(code: String) async -> Bool {
        let before = state.session
        busy = true
        trouble = nil
        defer { busy = false }
        do {
            let joined = try await AuthAPI.pair(code: code)
            if let before { carryAgreement(from: before, to: joined) }
            adopt(joined)
            return true
        } catch {
            trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Someone who already agreed to the recording terms on this device is
    /// not asked again just because the account under it changed.
    private func carryAgreement(from old: Session, to new: Session) {
        if RecordingTerms.accepted(by: old.account.id) { RecordingTerms.accept(for: new.account.id) }
    }

    private func adopt(_ session: Session) {
        Keychain.save(session)
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

    /// Signing out leaves the library on this device exactly where it is. It is
    /// still on the server too, so signing back in brings the two together
    /// again rather than starting from nothing.
    func signOut() {
        Keychain.clearSession()
        state = .signedOut
    }

    /// Deleting the account, from inside the app.
    ///
    /// The App Store requires this of any app that can create an account, and
    /// it is right anyway: somebody who signed up in two taps should not have
    /// to email support to leave.
    @discardableResult
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
