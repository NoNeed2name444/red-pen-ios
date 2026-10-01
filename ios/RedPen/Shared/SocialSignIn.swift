import Foundation
import UIKit
import AuthenticationServices

/// Sign in with Google, through the system browser rather than an SDK.
///
/// Two reasons for doing it this way. There is no third-party dependency to
/// add, update or trust. And the system browser is where the student's existing
/// Google session already is, so signing in is usually one tap rather than a
/// password.
///
/// PKCE is what makes it safe without an app secret: the app keeps a random
/// verifier, sends only its hash, and the code that comes back is worthless to
/// anyone who does not hold the original. The client secret stays on the
/// server, which is the only place it can live safely - anything shipped inside
/// an app can be read out of it.
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {

    /// Read from the app's Info.plist so the client id is configuration rather
    /// than source, and an unconfigured build says so instead of opening a
    /// broken page.
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
