import Foundation

// The shape every model in the app is spoken to through - on the device, in
// CramDown Cloud, or a student's own provider. Foundation only, so the
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

/// Anything that can finish a conversation. The on-device models and every
/// hosted provider sit behind this, so a mode never knows which one it got.
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
    case missingKey(String)

    var errorDescription: String? {
        switch self {
        case .notReady(let why): return why
        case .emptyReply: return "The model returned nothing usable \u{2014} try again."
        case .http(402, let body), .http(429, let body):
            return String(body.prefix(200))
        case .http(let code, let body):
            return "The hosted model refused the request (HTTP \(code)). \(body.prefix(160))"
        case .badResponse: return "The hosted model answered in a shape the app doesn't understand."
        case .missingKey(let name): return "Add an API key for \(name) in AI models."
        }
    }
}
