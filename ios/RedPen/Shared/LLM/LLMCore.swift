import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The shape every model in the app is spoken to through: CramDown Cloud's
// writer route, or a live test's own server. Foundation only, so the
// generators built on it can be compiled and run against real models on a
// Mac (Tests/LiveModelTests.swift) as well as on the phone.

/// One turn of a conversation with a model, in the shape every backend -
/// llama.cpp on the device, or any of the hosted APIs - can be given.
struct ChatTurn: Codable, Hashable {
    enum Role: String, Codable { case system, user, assistant }
    var role: Role
    var text: String

    static func system(_ text: String) -> ChatTurn { ChatTurn(role: .system, text: text) }
    static func user(_ text: String) -> ChatTurn { ChatTurn(role: .user, text: text) }
    static func assistant(_ text: String) -> ChatTurn { ChatTurn(role: .assistant, text: text) }
}

/// Anything that can finish a conversation: the writer route (and a test's
/// stand-in) sit behind this, so a mode never knows which one it got.
protocol LLMBackend: Sendable {
    var label: String { get }
    /// True when this backend runs on the device and sends nothing anywhere.
    var isOnDevice: Bool { get }
    /// How much source text is worth putting in one prompt. On a phone the
    /// context window is small; a hosted model can take a whole lecture.
    var promptBudgetChars: Int { get }
    func complete(_ turns: [ChatTurn], maxTokens: Int, temperature: Double) async throws -> String
}

enum LLMError: LocalizedError {
    case notReady(String)
    case emptyReply
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notReady(let why): return why
        case .emptyReply: return "The model returned nothing usable \u{2014} try again."
        // the server's own refusals (Pro, quota, a subscription on another
        // account, an app too old) are sentences meant for the student
        case .http(let code, let body) where LLMError.plainRefusals.contains(code) && LLMError.readable(body):
            return String(body.prefix(200))
        case .http(let code, let body):
            return "The hosted model refused the request (HTTP \(code)). \(body.prefix(160))"
        case .badResponse: return "The hosted model answered in a shape the app doesn't understand."
        }
    }

    static let plainRefusals: Set<Int> = [401, 402, 403, 409, 410, 429]

    /// A message a person can read, not a JSON or HTML error page.
    static func readable(_ body: String) -> Bool {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && !text.hasPrefix("{") && !text.hasPrefix("<")
    }
}

/// The job a model does in the app: `writer` writes questions, stations,
/// cards, textbook pages, twins, hints and answers. Checking is the
/// verification layer's, not a model's.
enum LLMRole: String, CaseIterable, Identifiable {
    case writer
    var id: String { rawValue }
    var title: String { "Writer" }
}

/// What a generate screen does when Make is tapped (the owner, 23 Oct: "Lock
/// it"): the writer route writes, or nothing does. There is no model on the
/// phone and no free one behind it, so without a writer (not Pro, not signed
/// in, the cloud out of reach) the job is never started and the reason comes
/// back for the screen to show beside See Pro.
enum WriterGate {
    /// The things the app writes from a lecture.
    enum Job: String, CaseIterable { case questions, cases, stations }

    /// Runs `write` with the writer, or throws `noWriter` with nothing run.
    static func write<T>(_ job: Job, with writer: LLMBackend?, noWriter: String,
                         _ write: (LLMBackend) async throws -> T) async throws -> T {
        guard let writer else { throw LLMError.notReady(noWriter) }
        return try await write(writer)
    }
}

/// The app's one writer (the owner, 22 Oct): every role goes to the worker's
/// writer route, with the account's session or the owner key as the bearer.
/// The worker decides what answers it - its hosted writer, behind PRO_PAYS
/// and its spend caps - so the app has nothing to choose and never holds a
/// model's key.
enum WriterRoute {
    /// The model name the worker maps to its writer.
    static let model = "cramdown-writer"

    /// Why the writer can't be used, or nil when it can: Pro first, then a
    /// bearer, naming only the sign-in doors this build shows.
    static func blocker(isPro: Bool, bearer: String?, brand: String, google: Bool) -> String? {
        if !isPro { return "\(brand) Cloud is part of Pro." }
        if bearer == nil {
            return google
                ? "Sign in with Apple or Google to use \(brand) Cloud."
                : "Sign in with Apple to use \(brand) Cloud."
        }
        return nil
    }

    /// The worker's chat endpoint under `server`.
    static func endpoint(_ server: URL) -> URL {
        server.appendingPathComponent("v1").appendingPathComponent("chat").appendingPathComponent("completions")
    }

    /// The request a role's turns are sent as: the same route and model for
    /// every role.
    static func request(_ turns: [ChatTurn], role: LLMRole, server: URL, bearer: String,
                        maxTokens: Int, temperature: Double) throws -> URLRequest {
        var request = URLRequest(url: endpoint(server))
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "messages": turns.map { ["role": $0.role.rawValue, "content": $0.text] },
        ] as [String: Any])
        return request
    }

    /// The text of the worker's reply (its first choice's message).
    static func reply(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw LLMError.badResponse }
        return content
    }
}
