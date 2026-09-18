import Foundation
import AuthenticationServices

/// Sign in with Apple.
///
/// The nonce is the point of the ceremony. The app makes a random one, sends
/// Apple its hash, and Apple puts that hash inside the signed identity token.
/// The server then checks the token's signature AND that the hash inside it
/// matches the nonce the app says it used - so a token captured from one
/// sign-in cannot be replayed into another.
@MainActor
final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate,
                         ASAuthorizationControllerPresentationContextProviding {

    private var waiting: CheckedContinuation<Session, Error>?
    private var nonce = ""

    func run() async throws -> Session {
        nonce = AuthRules.nonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AuthRules.sha256Hex(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            waiting = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            finish(.failure(AuthAPI.Failure.server("Apple didn't return a usable sign-in.")))
            return
        }
        // Apple gives the name ONCE, on the very first sign-in, and never
        // again - so it is passed straight through rather than being asked for
        // later, when it no longer exists.
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")
        let sent = nonce
        Task {
            do {
                let session = try await AuthAPI.signInWithApple(
                    identityToken: token, nonce: sent,
                    fullName: name.isEmpty ? nil : name)
                finish(.success(session))
            } catch {
                finish(.failure(error))
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        // Backing out of the sheet is not an error worth showing anybody.
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(error))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<Session, Error>) {
        waiting?.resume(with: result)
        waiting = nil
    }
}

/// Sign in with Google, through the system browser rather than an SDK.
///
/// Two reasons for doing it this way. There is no third-party dependency to
/// add, update or trust. And the system browser is where the student's existing
/// Google session already is, so signing in is usually one tap rather than a
/// password.
///
/// PKCE is what makes it safe without an app secret: the app keeps a random
/// verifier, sends only its hash, and the code that comes back is worthless to
/// anyone who does not hold the original.
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {

    /// Filled in from the app's Info.plist so the client id is configuration
    /// rather than source, and an unconfigured build says so instead of opening
    /// a broken page.
    static var clientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "RedPenGoogleClientID") as? String
    }
    static let scheme = "redpen"
    static var redirect: String { "\(scheme)://auth" }

    private var session: ASWebAuthenticationSession?

    func run() async throws -> Session {
        guard let clientID = Self.clientID, !clientID.isEmpty else {
            throw AuthAPI.Failure.notConfigured
        }
        let verifier = AuthRules.verifier()
        let state = AuthRules.nonce()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: Self.redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: AuthRules.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        guard let url = components.url else { throw AuthAPI.Failure.notConfigured }

        let redirected: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: Self.scheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? AuthAPI.Failure.offline)
                }
            }
            session.presentationContextProvider = self
            // a shared cookie jar is the whole convenience: the student is
            // usually signed in to Google already
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        guard let code = AuthRules.code(fromRedirect: redirected, expectedState: state) else {
            throw AuthAPI.Failure.server("Google's answer didn't match the request.")
        }
        return try await AuthAPI.signInWithGoogle(code: code, verifier: verifier,
                                                  redirect: Self.redirect)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}
