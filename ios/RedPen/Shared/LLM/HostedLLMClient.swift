import Foundation

/// Talks to CramDown Cloud's writer route (WriterRoute): the one writer every
/// role uses, with the account's session or the owner key as the bearer. The
/// same `LLMBackend` interface as any other model, so a mode never knows more.
struct HostedLLMClient: LLMBackend {
    var role: LLMRole = .writer
    let bearer: String

    var label: String { "\(Brand.name) Cloud" }
    var isOnDevice: Bool { false }
    var promptBudgetChars: Int { 40_000 }

    func complete(_ turns: [ChatTurn], maxTokens: Int, temperature: Double) async throws -> String {
        var request = try WriterRoute.request(turns, role: role, server: AuthAPI.baseURL, bearer: bearer,
                                              maxTokens: maxTokens, temperature: temperature)
        request.timeoutInterval = 180
        VignetteHeaders.apply(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // the worker puts a readable reason in "message"
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = object?["message"] as? String
                ?? (object?["error"] as? [String: Any])?["message"] as? String
                ?? String(data: data, encoding: .utf8) ?? ""
            // a server error, or a request the worker could not read (a
            // bug on this side); refusals like Pro or quota are not failures
            if http.statusCode >= 500 || [400, 404, 422].contains(http.statusCode) {
                Diagnostics.record(.error, area: .ai, message: "hosted.http_status", code: http.statusCode)
            }
            throw LLMError.http(http.statusCode, message)
        }
        let text = LLMText.stripThinking(try WriterRoute.reply(data))
        guard !text.isEmpty else {
            Diagnostics.record(.warning, area: .ai, message: "hosted.empty_reply")
            throw LLMError.emptyReply
        }
        return text
    }
}

/// The writer route can take a whole job and finish it on the server
/// (CloudJobs).
extension HostedLLMClient: CloudJobBackend {
    var jobs: (base: URL, bearer: String)? {
        bearer.isEmpty ? nil : (AuthAPI.baseURL, bearer)
    }
}
