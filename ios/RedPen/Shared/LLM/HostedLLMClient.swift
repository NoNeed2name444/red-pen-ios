import Foundation

/// A hosted model the student has added: where it lives, which API shape it
/// speaks, and which model to ask for. The API key is not in here - it lives
/// in the keychain, on this device only, and is never built into the app.
struct HostedProvider: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// `/chat/completions`: OpenAI, OpenRouter, Groq, Together, Hugging
        /// Face's router and Inference Endpoints, vLLM, Ollama and a llama.cpp
        /// server all speak this.
        case openAICompatible
        case anthropic
        case gemini

        var id: String { rawValue }
        var title: String {
            switch self {
            case .openAICompatible: return "OpenAI-compatible"
            case .anthropic: return "Anthropic (Claude)"
            case .gemini: return "Google Gemini"
            }
        }
    }

    var id: UUID = UUID()
    var name: String
    var kind: Kind
    var baseURL: String
    var model: String
    /// A self-hosted server with no key (llama.cpp, Ollama on a home machine).
    var needsKey: Bool = true

    var keychainAccount: String { "llm.provider.\(id.uuidString)" }

    var apiKey: String? {
        Keychain.data(for: keychainAccount).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Starting points for the add screen. Every field stays editable: model
    /// names change faster than an app update ships.
    static let presets: [HostedProvider] = [
        HostedProvider(name: "Baichuan-M2-32B (Hugging Face)", kind: .openAICompatible,
                       baseURL: "https://router.huggingface.co/v1",
                       model: "baichuan-inc/Baichuan-M2-32B"),
        HostedProvider(name: "Doctor-R1 / MedVAL on my server", kind: .openAICompatible,
                       baseURL: "http://192.168.1.10:8080/v1",
                       model: "doctor-r1", needsKey: false),
        HostedProvider(name: "OpenRouter", kind: .openAICompatible,
                       baseURL: "https://openrouter.ai/api/v1",
                       model: "baichuan-inc/baichuan-m2-32b"),
        HostedProvider(name: "OpenAI", kind: .openAICompatible,
                       baseURL: "https://api.openai.com/v1", model: "gpt-4.1-mini"),
        HostedProvider(name: "Claude", kind: .anthropic,
                       baseURL: "https://api.anthropic.com/v1", model: "claude-sonnet-5"),
        HostedProvider(name: "Gemini", kind: .gemini,
                       baseURL: "https://generativelanguage.googleapis.com/v1beta",
                       model: "gemini-2.5-flash"),
    ]

    /// CramDown Cloud: our own worker, the student's session as the key, and
    /// a model name per job that the worker maps to whatever it currently runs
    /// (Baichuan-M2-32B by default). Pro only - the worker checks with Apple.
    static func cloud(for role: LLMRole) -> HostedProvider {
        HostedProvider(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C10D")!,
                       name: "CramDown Cloud", kind: .openAICompatible,
                       baseURL: AuthAPI.baseURL.absoluteString + "/v1",
                       model: role == .writer ? "cramdown-writer" : "cramdown-checker",
                       needsKey: false)
    }

    private static let storeKey = "llm.providers"

    static func loadAll() -> [HostedProvider] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let list = try? JSONDecoder().decode([HostedProvider].self, from: data)
        else { return [] }
        return list
    }

    static func saveAll(_ list: [HostedProvider]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}

/// Talks to a hosted model. Same `LLMBackend` interface as the on-device
/// models, so a device too small for Doctor-R1 or MedVAL uses one of these and
/// nothing else in the app changes.
struct HostedLLMClient: LLMBackend {
    let provider: HostedProvider
    /// Used instead of a stored key: CramDown Cloud's session token.
    var bearer: String? = nil

    var label: String { provider.name }
    var isOnDevice: Bool { false }
    var promptBudgetChars: Int { 40_000 }

    func complete(_ turns: [ChatTurn], maxTokens: Int, temperature: Double) async throws -> String {
        let key = bearer ?? provider.apiKey ?? ""
        if bearer == nil && provider.needsKey && key.isEmpty { throw LLMError.missingKey(provider.name) }
        var request: URLRequest
        switch provider.kind {
        case .openAICompatible: request = try openAIRequest(turns, key: key, maxTokens: maxTokens, temperature: temperature)
        case .anthropic: request = try anthropicRequest(turns, key: key, maxTokens: maxTokens, temperature: temperature)
        case .gemini: request = try geminiRequest(turns, key: key, maxTokens: maxTokens, temperature: temperature)
        }
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // our worker and most providers put a readable reason in "message"
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = object?["message"] as? String
                ?? (object?["error"] as? [String: Any])?["message"] as? String
                ?? String(data: data, encoding: .utf8) ?? ""
            throw LLMError.http(http.statusCode, message)
        }
        let text = LLMText.stripThinking(try parse(data))
        guard !text.isEmpty else { throw LLMError.emptyReply }
        return text
    }

    // MARK: requests

    private func url(_ path: String) throws -> URL {
        var base = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + path) else {
            throw LLMError.notReady("\(provider.name) has an address the app can't read.")
        }
        return url
    }

    private func body(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func openAIRequest(_ turns: [ChatTurn], key: String, maxTokens: Int,
                               temperature: Double) throws -> URLRequest {
        var request = URLRequest(url: try url("/chat/completions"))
        request.httpMethod = "POST"
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try body([
            "model": provider.model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "messages": turns.map { ["role": $0.role.rawValue, "content": $0.text] },
        ])
        return request
    }

    private func anthropicRequest(_ turns: [ChatTurn], key: String, maxTokens: Int,
                                  temperature: Double) throws -> URLRequest {
        var request = URLRequest(url: try url("/messages"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let system = turns.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
        var object: [String: Any] = [
            "model": provider.model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "messages": turns.filter { $0.role != .system }
                .map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        if !system.isEmpty { object["system"] = system }
        request.httpBody = try body(object)
        return request
    }

    private func geminiRequest(_ turns: [ChatTurn], key: String, maxTokens: Int,
                               temperature: Double) throws -> URLRequest {
        var request = URLRequest(url: try url("/models/\(provider.model):generateContent"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let system = turns.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
        var object: [String: Any] = [
            "contents": turns.filter { $0.role != .system }.map {
                ["role": $0.role == .assistant ? "model" : "user", "parts": [["text": $0.text]]]
            },
            "generationConfig": ["maxOutputTokens": maxTokens, "temperature": temperature],
        ]
        if !system.isEmpty { object["systemInstruction"] = ["parts": [["text": system]]] }
        request.httpBody = try body(object)
        return request
    }

    // MARK: responses

    private func parse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.badResponse
        }
        switch provider.kind {
        case .openAICompatible:
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { throw LLMError.badResponse }
            return content
        case .anthropic:
            guard let blocks = json["content"] as? [[String: Any]] else { throw LLMError.badResponse }
            return blocks.compactMap { $0["text"] as? String }.joined()
        case .gemini:
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { throw LLMError.badResponse }
            return parts.compactMap { $0["text"] as? String }.joined()
        }
    }
}
