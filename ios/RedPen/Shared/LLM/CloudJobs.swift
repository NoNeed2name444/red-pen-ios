import Foundation

/// A backend that can hand a whole generation to the server to finish:
/// Vignette Cloud's writer. `jobs` is where, and the session to ask with.
protocol CloudJobBackend {
    var jobs: (base: URL, bearer: String)? { get }
}

/// Generation that carries on when the app is closed.
///
/// With Vignette Cloud writing, the app does not make the model calls itself:
/// it sends the server every prompt it would have sent, written exactly as
/// before (the lecture once, as `{{SOURCE}}`; what is already written as
/// `{{ALREADY}}`, filled in by the server batch by batch), and watches the
/// server work through them. Lock the phone or swipe the app away and the
/// server keeps going; the finished job is collected the next time the app
/// opens (CloudJobCollector) and becomes a set in the library.
enum CloudJobs {
    /// What the screen that started the generation needs to turn the replies
    /// into a set on its own, if the app is closed before they are ready.
    @TaskLocal static var recipe: Data?

    struct Step: Encodable {
        var system: String
        var user: String
        var source: Int = 0
        var maxTokens: Int
        var temperature: Double
    }

    struct Spec: Encodable {
        var title: String
        /// "loop": prompts taken in turn until `count` items; "each": every
        /// prompt once, in order (a textbook's pages).
        var mode: String
        /// How the server counts a reply's items: lines, questions, stations, pages.
        var extract: String
        var count: Int
        var sources: [String]
        var steps: [Step]
        var minFields = 2
        var keyFields = 1
        var cloze = false
        var patience = 3
    }

    struct Status: Codable, Equatable {
        var id: String
        var title: String
        var status: String
        var done: Int
        var total: Int
        var error: String?
    }

    /// A job this device started and has not collected yet, kept on disk so a
    /// closed app can pick it up again.
    struct Pending: Codable {
        var id: String
        var title: String
        var started: Date
        var recipe: Data?
        /// Anything else the generator needs afterwards (a textbook's figure placement).
        var extra: Data?
        /// The run of the app that is watching it; another run collects it.
        var launch: UUID?
        var done = 0
        var total = 0
        /// Already announced by a background check.
        var notified: Bool?

        /// "Your 40 questions", from "Writing 40 questions".
        var what: String {
            "Your " + (title.hasPrefix("Writing ") ? String(title.dropFirst("Writing ".count)) : title.lowercased())
        }
    }

    /// This run of the app.
    static let launch = UUID()

    /// Vignette Cloud's jobs endpoint for this backend, or nil to generate as before.
    static func endpoint(for backend: LLMBackend) -> (base: URL, bearer: String)? {
        (backend as? CloudJobBackend)?.jobs
    }

    /// Sends the job and waits for it, reporting progress. The replies come
    /// back in the order they were written. Cancelling stops the job on the
    /// server too.
    static func run(_ spec: Spec, at endpoint: (base: URL, bearer: String), extra: Data? = nil,
                    onProgress: @escaping (Int, Int) -> Void) async throws -> [String] {
        let created: Created = try await call("POST", "jobs", at: endpoint, body: try JSONEncoder().encode(spec))
        let id = created.job.id
        var pending = Pending(id: id, title: spec.title, started: Date(), recipe: recipe, extra: extra,
                              launch: launch, done: 0, total: spec.count)
        save(pending)
        onProgress(0, spec.count)
        var misses = 0
        do {
            while true {
                try await Task.sleep(nanoseconds: 2_500_000_000)
                let status: Status
                do {
                    status = try await self.status(id, at: endpoint)
                    misses = 0
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    misses += 1
                    if misses >= 30 {
                        // the server still has it: collected when the app next opens
                        pending.launch = nil
                        save(pending)
                        throw LLMError.notReady("Lost the connection. The cloud is still writing \u{2014} it will be in your library when it is done.")
                    }
                    continue
                }
                onProgress(status.done, status.total)
                if status.done != pending.done {
                    pending.done = status.done
                    pending.total = status.total
                    save(pending)
                }
                switch status.status {
                case "done":
                    let outputs = try await self.outputs(id, at: endpoint)
                    remove(id)
                    await forget(id, at: endpoint)
                    return outputs
                case "failed":
                    remove(id)
                    await forget(id, at: endpoint)
                    throw LLMError.notReady(status.error ?? "The cloud model could not write this.")
                default:
                    continue
                }
            }
        } catch is CancellationError {
            remove(id)
            // from a task of its own: this one is cancelled, and its requests with it
            await Task.detached { await CloudJobs.forget(id, at: endpoint) }.value
            throw CancellationError()
        }
    }

    // MARK: the server

    private struct Created: Decodable { var job: Status }
    private struct Fetched: Decodable { var job: Status; var outputs: [String]? }

    static func status(_ id: String, at endpoint: (base: URL, bearer: String)) async throws -> Status {
        let fetched: Fetched = try await call("GET", "jobs/\(id)", at: endpoint)
        return fetched.job
    }

    static func outputs(_ id: String, at endpoint: (base: URL, bearer: String)) async throws -> [String] {
        let fetched: Fetched = try await call("GET", "jobs/\(id)?outputs=1", at: endpoint)
        return fetched.outputs ?? []
    }

    /// Stops a job, or clears a collected one off the server.
    static func forget(_ id: String, at endpoint: (base: URL, bearer: String)) async {
        struct Done: Decodable {}
        _ = try? await call("DELETE", "jobs/\(id)", at: endpoint) as Done
    }

    private static func call<T: Decodable>(_ method: String, _ path: String,
                                           at endpoint: (base: URL, bearer: String), body: Data? = nil) async throws -> T {
        guard let url = URL(string: endpoint.base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path) else {
            throw LLMError.badResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("Bearer \(endpoint.bearer)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw LLMError.http(http.statusCode, object?["message"] as? String ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: kept on this device

    private static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cloud-jobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ pending: Pending) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: folder.appendingPathComponent(pending.id + ".json"), options: .atomic)
    }

    static func remove(_ id: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(id + ".json"))
    }

    static func pending() -> [Pending] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Pending.self, from: Data(contentsOf: $0)) }
            .sorted { $0.started < $1.started }
    }
}
