import Foundation
import CryptoKit

/// Everything about signing in that is a decision rather than a network call.
///
/// Kept pure so it can be run on a test machine. None of it needs a phone, and
/// all of it is the kind of thing that fails quietly in front of somebody who
/// cannot get in.
enum AuthRules {

    /// A fresh verifier: the secret the app keeps while the browser is away.
    ///
    /// PKCE is what makes signing in through the system browser safe without an
    /// app secret. The app sends a hash out and keeps the original; whoever
    /// intercepts the redirect has the code but not the secret that redeems it.
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Base64 as a URL is allowed to carry it: no +, no /, no padding. A stray
    /// one of those is a sign-in that fails for one user in ten and works on
    /// the developer's machine.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The one-time value tying a sign-in request to its answer.
    static func nonce() -> String { verifier() }

    /// Apple wants the nonce hashed, so the raw one never leaves the device.
    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Pulls the authorisation code out of the redirect the browser comes back
    /// with, and refuses it unless the state matches the one we sent.
    ///
    /// The state check is not ceremony: without it, anything that can open a
    /// URL in this app can hand it someone else's authorisation code.
    static func code(fromRedirect url: URL, expectedState: String) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard let state = value("state"), state == expectedState,
              let code = value("code"), !code.isEmpty else { return nil }
        return code
    }
}
