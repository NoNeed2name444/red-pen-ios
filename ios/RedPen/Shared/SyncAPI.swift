import Foundation

/// The wire protocol for keeping two devices in step.
///
/// Four calls, and the shape of them is the design: a cursor-based changes
/// feed, a batched push that reports per-document conflicts rather than
/// failing the whole batch, and blob transfer that asks first so the same
/// picture is never uploaded twice.
enum SyncAPI {

    // MARK: pulling

    struct Changes: Codable {
        var docs: [SyncDoc]
        /// The revision to ask from next time.
        var cursor: Int
        /// True when the server had more than one page of them, so the client
        /// knows to come straight back rather than waiting for the next sync.
        var more: Bool
    }

    /// Everything that has changed since `cursor`.
    ///
    /// Paged, because a new device's first sync is the entire library and a
    /// single response holding all of it is a response that times out on a
    /// train.
    static func changes(since cursor: Int, token: String, limit: Int = 200) async throws -> Changes {
        struct Ask: Encodable { var since: Int; var limit: Int }
        let data = try await AuthAPI.send("/sync/changes",
                                          body: Ask(since: cursor, limit: limit),
                                          token: token, timeout: 60)
        guard let changes = try? JSONDecoder.redPen.decode(Changes.self, from: data) else {
            throw AuthAPI.Failure.server("The server sent something unexpected.")
        }
        return changes
    }

    // MARK: pushing

    struct Push: Codable {
        var docs: [SyncDoc]
    }

    struct PushResult: Codable {
        /// Accepted documents, carrying the revision the server gave them.
        var accepted: [SyncDoc]
        /// Documents the server refused because it had moved on since the
        /// revision we were working from - with its current copy, so the
        /// client can merge and try again. A conflict is an answer, not an
        /// error: one document being stale must not throw away the other
        /// nineteen in the batch.
        var conflicts: [SyncDoc]
    }

    static func push(_ docs: [SyncDoc], token: String) async throws -> PushResult {
        let data = try await AuthAPI.send("/sync/push", body: Push(docs: docs),
                                          token: token, timeout: 60)
        guard let result = try? JSONDecoder.redPen.decode(PushResult.self, from: data) else {
            throw AuthAPI.Failure.server("The server sent something unexpected.")
        }
        return result
    }

    // MARK: blobs

    /// Which of these the server has not got.
    ///
    /// Asking is far cheaper than sending: a device that reinstalls the app has
    /// every picture already on the server, and this turns what would be a
    /// hundred-megabyte upload into one small request.
    static func missingBlobs(_ names: [String], token: String) async throws -> [String] {
        struct Ask: Encodable { var names: [String] }
        struct Answer: Decodable { var missing: [String] }
        guard !names.isEmpty else { return [] }
        let data = try await AuthAPI.send("/blobs/missing", body: Ask(names: names), token: token)
        return (try? JSONDecoder.redPen.decode(Answer.self, from: data))?.missing ?? []
    }

    /// Sends one blob, under the name that is its own hash.
    ///
    /// Raw bytes rather than JSON: base64 inside a JSON body would add a third
    /// again to every upload, and these are the big things.
    static func putBlob(_ data: Data, name: String, token: String) async throws {
        var request = URLRequest(url: AuthAPI.baseURL.appendingPathComponent("/blobs/\(name)"))
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        let (_, response) = try await send(request, body: data)
        try check(response)
    }

    static func getBlob(_ name: String, token: String) async throws -> Data {
        var request = URLRequest(url: AuthAPI.baseURL.appendingPathComponent("/blobs/\(name)"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        let (data, response) = try await send(request, body: nil)
        try check(response)
        // What came back is checked against the name it was asked for. A blob
        // that does not hash to its own address is either corruption in flight
        // or the wrong file, and either way storing it would make a picture
        // that can never be found again.
        guard BlobRefs.name(for: data) == name else {
            throw AuthAPI.Failure.server("A picture arrived damaged.")
        }
        return data
    }

    private static func send(_ request: URLRequest, body: Data?) async throws -> (Data, URLResponse) {
        do {
            if let body {
                return try await URLSession.shared.upload(for: request, from: body)
            }
            return try await URLSession.shared.data(for: request)
        } catch {
            throw AuthAPI.Failure.offline
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AuthAPI.Failure.offline }
        switch http.statusCode {
        case 200...299: return
        case 401, 403: throw AuthAPI.Failure.signedOut
        case 429: throw AuthAPI.Failure.tooManyTries
        case 402: throw AuthAPI.Failure.needsPro("Syncing between devices is part of Pro.")
        default: throw AuthAPI.Failure.server("The server refused that (\(http.statusCode)).")
        }
    }
}
