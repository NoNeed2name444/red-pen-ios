import Foundation
import CryptoKit

/// Everything about signing in that is a decision rather than a network call.
///
/// Kept pure so it can be run on a test machine: an address the server will
/// reject, a code typed with a space in it, a PKCE challenge that does not
/// match its verifier. None of that needs a phone, and all of it is the kind of
/// thing that fails quietly in front of a user who cannot get in.
enum AuthRules {

    // MARK: email

    /// An address, tidied, or nil if it could not be one.
    ///
    /// Deliberately loose. The only test that matters is whether the code sent
    /// to it arrives; a clever regex here mostly serves to turn away people
    /// with unusual but perfectly real addresses. So this catches typing
    /// mistakes - no at-sign, no dot after it, spaces in the middle - and
    /// leaves the rest to the mail server.
    static func normalisedEmail(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 254,
              !trimmed.contains(" ") else { return nil }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix("."),
              !domain.contains(".."), domain.count >= 3 else { return nil }
        return trimmed
    }

    static let codeLength = 6

    /// A six-digit code, however it was typed or pasted.
    ///
    /// People paste the code with a space in the middle, or with the whole
    /// sentence around it. Pulling the digits out is kinder than refusing it.
    static func normalisedCode(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        return digits.count == codeLength ? digits : nil
    }

    /// How long a code is worth trying, and how often one may be asked for.
    static let codeLifetime: TimeInterval = 10 * 60
    static let resendAfter: TimeInterval = 30

    static func canResend(lastSentAt: Date?, now: Date = Date()) -> Bool {
        guard let lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) >= resendAfter
    }

    // MARK: PKCE, for the Google round trip

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

    /// Base64 as a URL is allowed to carry it: no +, no /, no padding.
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
