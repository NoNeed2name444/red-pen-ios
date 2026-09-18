import Foundation

/// Everything the app asks the server for.
///
/// The server exists for one reason: a phone cannot send an email. Apple and
/// Google sign-in would work with no server at all, but a verification code has
/// to come from somewhere, and that somewhere has to be able to reach a mail
/// provider and remember which code it sent.
///
/// It is given as little as possible. It learns an account id, an address if
/// the student gave one, and which plan they are on. It never sees a deck, a
/// recording, a transcript or a pronunciation - those stay on the phone, which
/// is what the app promises on its own empty screen.
///
/// The whole worker is in server/ in this repository, so what it does with all
/// this is readable rather than assumed.
enum AuthAPI {

    /// Where the worker lives. Overridable so a test build can point at a
    /// local one without a rebuild of the app.
    static var baseURL: URL {
        if let override = Bundle.main.object(forInfoDictionaryKey: "RedPenAuthBaseURL") as? String,
           let url = URL(string: override), !override.isEmpty {
            return url
        }
        return URL(string: "https://auth.redpen.app")!
    }

    enum Failure: LocalizedError, Equatable {
        case offline
        case badCode
        case tooManyTries
        case notConfigured
        case server(String)

        var errorDescription: String? {
            switch self {
            case .offline:
                return "No connection. Signing in needs one \u{2014} studying does not."
            case .badCode:
                return "That code doesn't match. Check it, or ask for a new one."
            case .tooManyTries:
                return "Too many tries. Wait a minute and ask for a new code."
            case .notConfigured:
                return "Sign-in isn't set up in this build yet."
            case .server(let message):
                return message
            }
        }
    }

    // MARK: what comes back

    private struct SessionResponse: Decodable {
        var userId: String
        var email: String?
        var displayName: String?
        var provider: String
        var token: String
        var refreshToken: String?
        var expiresIn: TimeInterval
    }

    private struct Problem: Decodable { var error: String?; var message: String? }

    // MARK: the calls

    /// Apple hands the app a signed identity token; the server checks its
    /// signature against Apple's own keys and tells us who it belongs to. The
    /// app never decides that for itself - a token this side of the wire is
    /// just a string a caller could have made up.
    static func signInWithApple(identityToken: String, nonce: String,
                                fullName: String?) async throws -> Session {
        try await session(at: "/auth/apple", body: [
            "identityToken": identityToken, "nonce": nonce,
            "fullName": fullName ?? "",
        ])
    }

    /// The browser comes back with a one-time code; the server exchanges it
    /// with Google, which is where the client secret lives.
    static func signInWithGoogle(code: String, verifier: String,
                                 redirect: String) async throws -> Session {
        try await session(at: "/auth/google", body: [
            "code": code, "codeVerifier": verifier, "redirectUri": redirect,
        ])
    }

    /// Asks for a code. Says nothing about whether the address is already known:
    /// answering that question is how a sign-in form becomes a way to find out
    /// who has an account.
    static func requestCode(email: String) async throws {
        _ = try await post("/auth/email/request", body: ["email": email])
    }

    static func verifyCode(email: String, code: String) async throws -> Session {
        try await session(at: "/auth/email/verify", body: ["email": email, "code": code])
    }

    static func refresh(_ refreshToken: String) async throws -> Session {
        try await session(at: "/auth/refresh", body: ["refreshToken": refreshToken])
    }

    /// Required by the App Store if an app can create accounts, and the right
    /// thing regardless: someone who signed up must be able to leave from
    /// inside the app rather than by writing to support.
    static func deleteAccount(token: String) async throws {
        _ = try await post("/account/delete", body: [:], token: token)
    }

    /// Tells the server which plan a verified purchase is on, so a second phone
    /// signing in already knows. The App Store remains the authority; this is a
    /// convenience, not the source of truth.
    static func recordSubscription(token: String, plan: String,
                                   expiresAt: Date) async throws {
        _ = try await post("/account/subscription", body: [
            "plan": plan,
            "expiresAt": ISO8601DateFormatter().string(from: expiresAt),
        ], token: token)
    }

    // MARK: the plumbing

    private static func session(at path: String, body: [String: String]) async throws -> Session {
        let data = try await post(path, body: body)
        guard let decoded = try? JSONDecoder().decode(SessionResponse.self, from: data),
              let provider = AuthProvider(rawValue: decoded.provider) else {
            throw Failure.server("The server sent something unexpected.")
        }
        return Session(
            account: Account(id: decoded.userId, provider: provider,
                             email: decoded.email, displayName: decoded.displayName),
            token: decoded.token, refreshToken: decoded.refreshToken,
            expiresAt: Date().addingTimeInterval(decoded.expiresIn))
    }

    @discardableResult
    private static func post(_ path: String, body: [String: String],
                             token: String? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.offline }
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw Failure.badCode
        case 404:
            throw Failure.notConfigured
        case 429:
            throw Failure.tooManyTries
        default:
            let problem = try? JSONDecoder().decode(Problem.self, from: data)
            throw Failure.server(problem?.message ?? problem?.error
                                 ?? "Something went wrong signing in.")
        }
    }
}
