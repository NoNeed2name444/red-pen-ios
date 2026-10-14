import Foundation

/// How someone proved who they are.
enum AuthProvider: String, Codable, CaseIterable {
    case apple, google, email
    /// No Apple or Google account: a device linked by code (pair.js).
    case device

    var label: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .email: return "Email"
        case .device: return "a linked device"
        }
    }

    /// Whether deleting the account leaves the app listed under Sign in with
    /// Apple in the student's Settings. The server only ever sees Apple's
    /// identity token, never one it could revoke with Apple, so that last
    /// step is the student's (TN3194; launch checklist GAP 1).
    var listedInSettingsAfterDeletion: Bool { self == .apple }
}

/// A person, as far as Red Pen is concerned.
///
/// Deliberately thin. The account exists to carry an identity and a
/// subscription; a student's decks, recordings and learned pronunciations stay
/// on the phone and are never uploaded. That is not a limitation to be fixed
/// later - it is the promise the app makes on its own empty screen, and it also
/// means there is no database of anyone's study material to lose.
struct Account: Codable, Equatable, Identifiable {
    var id: String
    var provider: AuthProvider
    /// Apple lets someone hide their address, in which case this is the relay
    /// address or nothing at all. Nothing depends on having it.
    var email: String?
    var displayName: String?
    var createdAt: Date = Date()
    /// Whether the server says this is the app owner's account (session
    /// responses and /account/me). Optional on purpose: synthesised Decodable
    /// ignores default values, so a non-optional field would make every
    /// session saved in the keychain before it existed fail to decode - and
    /// sign everybody out.
    var owner: Bool? = nil

    var isOwner: Bool { owner == true }

    var shownName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let email, !email.isEmpty { return email }
        return "Signed in with \(provider.label)"
    }
}

/// A signed-in session: who, and the token that proves it.
///
/// The tokens live in the keychain rather than beside the library, which is
/// the whole reason this is its own type - a bearer token in a JSON file next
/// to the flashcards is a bearer token in every backup that file lands in.
struct Session: Codable, Equatable {
    /// The token a this-device-only session carries (personal build). It is
    /// never sent anywhere: sync skips a session that has it.
    static let localToken = "local-only"
    var isLocalOnly: Bool { token == Session.localToken }

    var account: Account
    var token: String
    var refreshToken: String?
    var expiresAt: Date

    func isValid(now: Date = Date()) -> Bool { expiresAt > now }

    /// Refreshed a day before it actually expires, so a session never dies in
    /// the middle of something. A day rather than minutes: the app only asks
    /// when it is opened, brought back or syncs, and a margin of five minutes
    /// is one those moments almost never land in.
    func needsRefresh(now: Date = Date(), margin: TimeInterval = 86_400) -> Bool {
        expiresAt.timeIntervalSince(now) < margin
    }

    /// Worth keeping at launch: still valid, or expired but carrying the
    /// refresh token that renews it. Throwing an expired session away unread
    /// signs out a student whose refresh token still works - and a linked
    /// device's account has no other way back in at all.
    func canResume(now: Date = Date()) -> Bool {
        isValid(now: now) || !(refreshToken ?? "").isEmpty
    }
}

/// What the app is allowed to do right now.
enum AccountState: Equatable {
    case signedOut
    case signedIn(Session)

    var session: Session? {
        if case .signedIn(let session) = self { return session }
        return nil
    }
    var account: Account? { session?.account }
    var isSignedIn: Bool { session != nil }
}

/// What /account/me says about the signed-in account: the owner flag and the
/// consent versions it has agreed to, beside the versions now in force.
/// Every field but the id is optional, so an older or newer worker that
/// leaves one out still decodes.
struct AccountMe: Decodable, Equatable {
    struct Legal: Decodable, Equatable {
        var privacy: Int?
        var terms: Int?
        var aiConsent: Int?
        var rules: Int?
        var effective: String?
    }

    var userId: String
    var owner: Bool?
    var termsVersion: Int?
    var aiConsent: Int?
    var rulesVersion: Int?
    var legal: Legal?

    var isOwner: Bool { owner == true }

    /// The account agreed to an older version of the terms than the one now
    /// in force. False when the server did not say.
    var termsOutdated: Bool {
        guard let current = legal?.terms else { return false }
        return (termsVersion ?? 0) < current
    }

    /// Cloud AI consent is missing or older than the one now in force.
    var aiConsentOutdated: Bool {
        guard let current = legal?.aiConsent else { return false }
        return (aiConsent ?? 0) < current
    }
}

/// What a worker reply's status and `code` mean, before any message is
/// attached (plan R14). Kept beside Account, and Foundation-only, so the
/// account suite checks it without the network code around it.
///
/// A body with a `code` is a business answer ("that group is full"), never a
/// signed-out session, whatever its status - except the four statuses that
/// always mean the same thing: 401 signed out, 402 needs Pro, 428 needs a
/// consent, 429 slow down. Without a code, 403 is still signed out and 404
/// "not set up", as before.
enum ServerVerdict: Equatable {
    case ok
    case signedOut
    case needsPro
    case needsConsent(String)
    case tooManyTries
    case refused(String)
    case notFound
    case gone
    case server

    static func of(status: Int, code: String?) -> ServerVerdict {
        if (200...299).contains(status) { return .ok }
        let trimmed: String = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case 401: return .signedOut
        case 402: return .needsPro
        case 428: return .needsConsent(trimmed)
        case 429: return .tooManyTries
        default: break
        }
        if !trimmed.isEmpty { return .refused(trimmed) }
        switch status {
        case 403: return .signedOut
        case 404: return .notFound
        case 410: return .gone
        default: return .server
        }
    }

    /// The `code`, `message` and `error` of a worker's JSON error body; each
    /// nil when missing or not a string.
    static func problem(in data: Data) -> (code: String?, message: String?, error: String?) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (nil, nil, nil)
        }
        let code: String? = object["code"] as? String
        let message: String? = object["message"] as? String
        let error: String? = object["error"] as? String
        return (code, message, error)
    }
}
