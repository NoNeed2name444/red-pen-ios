import Foundation

/// How someone proved who they are.
enum AuthProvider: String, Codable, CaseIterable {
    case apple, google, email

    var label: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .email: return "Email"
        }
    }
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
    var account: Account
    var token: String
    var refreshToken: String?
    var expiresAt: Date

    func isValid(now: Date = Date()) -> Bool { expiresAt > now }

    /// Refreshed before it actually expires, so a session never dies in the
    /// middle of something.
    func needsRefresh(now: Date = Date(), margin: TimeInterval = 300) -> Bool {
        expiresAt.timeIntervalSince(now) < margin
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
