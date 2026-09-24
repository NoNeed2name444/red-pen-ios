import Foundation

/// Everything the app asks the server about who somebody is.
///
/// The server holds an account id, whichever provider proved it, an address if
/// one was offered, and - separately, through SyncAPI - the student's own
/// library so it can follow them between devices. It is their data on their
/// account; it is not shared with anyone and nothing is inferred from it.
///
/// The whole worker is in server/ in this repository, so what it does with all
/// this is readable rather than assumed.
enum AuthAPI {

    /// Where the worker lives. Configuration rather than source, so a test
    /// build can point at a local one without touching Swift.
    static var baseURL: URL {
        if let override = Bundle.main.object(forInfoDictionaryKey: "RedPenAuthBaseURL") as? String,
           let url = URL(string: override), !override.isEmpty {
            return url
        }
        // builds without an Info.plist (Swift Playgrounds) use the deployed worker
        return URL(string: "https://redpen-auth.vv7sh4rnnw.workers.dev")!
    }

    enum Failure: LocalizedError, Equatable {
        case offline
        case signedOut
        case tooManyTries
        case notConfigured
        case server(String)

        var errorDescription: String? {
            switch self {
            case .offline:
                return "No connection. Signing in needs one \u{2014} studying does not."
            case .signedOut:
                return "Please sign in again."
            case .tooManyTries:
                return "Too many requests just now. Try again in a moment."
            case .notConfigured:
                return "Sign-in isn't set up in this build yet."
            case .server(let message):
                return message
            }
        }
    }

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

    /// An account for a device that has none, so its library can sync.
    static func deviceAccount() async throws -> Session {
        try await session(at: "/auth/device", body: [:])
    }

    /// Joins the account a code from another device belongs to.
    static func pair(code: String) async throws -> Session {
        try await session(at: "/auth/pair", body: ["code": code])
    }

    /// A one-time code, shown on this device, for another device to join with.
    static func pairingCode(token: String) async throws -> (code: String, expiresIn: Int) {
        struct Reply: Decodable { var code: String; var expiresIn: Int }
        let data = try await send("/pair/start", body: [String: String](), token: token)
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw Failure.server("The server sent something unexpected.")
        }
        return (reply.code, reply.expiresIn)
    }

    static func refresh(_ refreshToken: String) async throws -> Session {
        try await session(at: "/auth/refresh", body: ["refreshToken": refreshToken])
    }

    /// Required by the App Store if an app can create accounts, and the right
    /// thing regardless. This takes the synced library with it - it is the
    /// student's data, and leaving it behind after they asked to be forgotten
    /// would be the opposite of deleting the account.
    static func deleteAccount(token: String) async throws {
        _ = try await send("/account/delete", body: [String: String](), token: token)
    }

    // MARK: the plumbing, shared with SyncAPI

    private static func session(at path: String, body: [String: String]) async throws -> Session {
        let data = try await send(path, body: body)
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

    /// One POST, one set of rules about what went wrong. Everything that talks
    /// to the worker goes through here so that "no signal" and "signed out"
    /// cannot be told apart differently in two places.
    @discardableResult
    static func send<Body: Encodable>(_ path: String, body: Body,
                                      token: String? = nil,
                                      timeout: TimeInterval = 20) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONEncoder.sync.encode(body)
        request.timeoutInterval = timeout

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.offline }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw Failure.signedOut
        case 404: throw Failure.notConfigured
        case 429: throw Failure.tooManyTries
        default:
            let problem = try? JSONDecoder().decode(Problem.self, from: data)
            throw Failure.server(problem?.message ?? problem?.error
                                 ?? "Something went wrong talking to the server.")
        }
    }
}
