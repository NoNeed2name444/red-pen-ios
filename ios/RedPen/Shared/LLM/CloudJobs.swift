import Foundation

/// A backend that can hand a whole generation to the server to finish:
/// Vignette Cloud's writer. `jobs` is where, and the session to ask with.
protocol CloudJobBackend {
    var jobs: (base: URL, bearer: String)? { get }
    /// Vignette Cloud's checker: a cloud job can be checked on the server.
    var checksOnServer: Bool { get }
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
    @TaskLocal static var context: Context?
    static var recipe: Data? { context?.recipe }

    /// Set by the screen that starts a generation, for the jobs under it.
    struct Context: Sendable {
        var recipe: Data?
        /// Check every item on the server (the chosen checker is Vignette Cloud's).
        var serverCheck = false
        /// Progress through the check: checked, of how many.
        var checking: (@Sendable (Int, Int) -> Void)?
        /// Where a finished job's replies and verdicts are handed over, for
        /// this generation alone. With one, the job is kept - on this device
        /// and on the server - until `finish`; without one it is let go as
        /// soon as its replies are read.
        var delivery: Delivery? = nil
    }

    /// What finished jobs handed to one generation: their checker verdicts
    /// (read through CloudChecks), and the jobs to let go once the screen is
    /// done with them.
    ///
    /// Held rather than let go at once because the replies are not a set yet.
    /// The screen still checks them - minutes, with a checker on the phone -
    /// and saves them; an app closed in between used to lose a paid
    /// generation, gone from the phone and the server both. Kept, the next
    /// launch collects it (CloudJobCollector).
    final class Delivery: @unchecked Sendable {
        private let lock = NSLock()
        private var byKey: [String: String] = [:]
        private var evidence: [String: [EvidenceRef]] = [:]
        private var held: [(id: String, base: URL, bearer: String)] = []

        init() {}

        func receive(_ verdicts: [Verdict]) {
            lock.lock(); defer { lock.unlock() }
            for verdict in verdicts {
                byKey[verdict.key] = verdict.reply
                if let refs = verdict.evidence, !refs.isEmpty { evidence[verdict.key] = refs }
            }
        }

        var tables: (byKey: [String: String], evidence: [String: [EvidenceRef]]) {
            lock.lock(); defer { lock.unlock() }
            return (byKey, evidence)
        }

        func hold(_ id: String, at endpoint: (base: URL, bearer: String)) {
            lock.lock(); defer { lock.unlock() }
            held.append((id: id, base: endpoint.base, bearer: endpoint.bearer))
        }

        func takeHeld() -> [(id: String, base: URL, bearer: String)] {
            lock.lock(); defer { lock.unlock() }
            let out = held
            held = []
            return out
        }
    }

    /// The screen is done with what its jobs handed back - saved it, shown it,
    /// or thrown it away on purpose: their records here and their copies on
    /// the server go. Called when the screen's generation ends, however it
    /// ends (a `defer`), so nothing waits for it.
    static func finish(_ delivery: Delivery?) {
        guard let delivery else { return }
        for job in delivery.takeHeld() {
            remove(job.id)
            // from a task of its own: the generation's may be cancelled
            let endpoint: (base: URL, bearer: String) = (base: job.base, bearer: job.bearer)
            Task.detached { await CloudJobs.forget(job.id, at: endpoint) }
        }
    }

    struct Check: Encodable {
        var template: String
        var limit: Int
    }

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
        var check: Check?
    }

    struct Status: Codable, Equatable {
        var id: String
        var title: String
        var status: String
        var done: Int
        var total: Int
        var error: String?
        var phase: String?
        var checked: Int?
        var checkTotal: Int?
        var checkError: String?
    }

    /// The checker's answer for one item, under the item's key (its stem or
    /// title, `CloudChecks.same`; "batch:3" or a page number otherwise).
    struct Verdict: Codable, Sendable {
        var key: String
        var reply: String
        /// What the server's evidence lookup found for this item and the
        /// checker read. Absent from older servers' verdicts.
        var evidence: [EvidenceRef]? = nil
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
        /// Whose job it is: the account id it was made under, or "owner" for
        /// the owner key. Jobs live with that identity on the server, and
        /// asking with another one finds nothing - which must not be taken
        /// for the job being gone.
        var identity: String? = nil
        /// Handed to the screen that started it, which has not finished with
        /// it yet (Delivery). A record like this found by another launch of
        /// the app is a generation the app was closed on.
        var delivered: Bool? = nil
        /// Its replies and verdicts, kept with it once delivered - so the set
        /// can still be made if the server has since let the job go.
        var outputs: [String]? = nil
        var checks: [Verdict]? = nil

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
        let bearer = endpoint.bearer
        let identity: String? = await MainActor.run { LocalLLMService.shared.cloudIdentity(for: bearer) }
        var pending = Pending(id: id, title: spec.title, started: Date(), recipe: recipe, extra: extra,
                              launch: launch, done: 0, total: spec.count)
        pending.identity = identity
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
                        Diagnostics.record(.warning, area: .cloudJobs, message: "cloud_job.lost_connection")
                        throw LLMError.notReady("Lost the connection. The cloud is still writing \u{2014} it will be in your library when it is done.")
                    }
                    continue
                }
                if status.phase == "checking" {
                    context?.checking?(status.checked ?? 0, status.checkTotal ?? 0)
                } else {
                    onProgress(status.done, status.total)
                }
                if status.done != pending.done {
                    pending.done = status.done
                    pending.total = status.total
                    save(pending)
                }
                switch status.status {
                case "done":
                    let fetched = try await self.result(id, at: endpoint)
                    // this generation's verdicts, not a global another job
                    // could replace while it is still reading them
                    CloudChecks.server(fetched.checks)
                    if let delivery = context?.delivery {
                        // kept until the screen is done with the replies
                        // (Delivery), and kept whole, in case the next launch
                        // has to make the set
                        pending.outputs = fetched.outputs
                        pending.checks = fetched.checks
                        pending.delivered = true
                        pending.notified = true
                        save(pending)
                        delivery.hold(id, at: endpoint)
                    } else {
                        remove(id)
                        // nothing waits on the server's copy going
                        Task.detached { await CloudJobs.forget(id, at: endpoint) }
                    }
                    return fetched.outputs
                case "failed":
                    Diagnostics.record(.error, area: .cloudJobs, message: "cloud_job.failed")
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
    private struct Fetched: Decodable { var job: Status; var outputs: [String]?; var checks: [Verdict]? }

    static func status(_ id: String, at endpoint: (base: URL, bearer: String)) async throws -> Status {
        let fetched: Fetched = try await call("GET", "jobs/\(id)", at: endpoint)
        return fetched.job
    }

    /// A finished job's replies, and the checker's verdicts if it was checked.
    static func result(_ id: String, at endpoint: (base: URL, bearer: String)) async throws -> (outputs: [String], checks: [Verdict]) {
        let fetched: Fetched = try await call("GET", "jobs/\(id)?outputs=1", at: endpoint)
        return (fetched.outputs ?? [], fetched.checks ?? [])
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

    /// Marks a job announced - only if its record still exists, as it is now
    /// on disk. False when it has gone (collected while a background check
    /// was asking about it), so the check neither writes it back nor
    /// announces a set that is already in the library.
    static func markNotified(_ id: String) -> Bool {
        let file = folder.appendingPathComponent(id + ".json")
        guard let data = try? Data(contentsOf: file),
              var current = try? JSONDecoder().decode(Pending.self, from: data) else { return false }
        guard current.notified != true else { return false }
        current.notified = true
        save(current)
        return true
    }
}

/// Verdicts the server's checker already gave, so the accuracy check does not
/// ask again for an item the cloud job checked (AccuracyChecker.check looks
/// here first).
enum CloudChecks {
    private static let lock = NSLock()
    private static var byKey: [String: String] = [:]
    private static var byOutput: [String: String] = [:]
    private static var evidenceByKey: [String: [EvidenceRef]] = [:]

    /// The key the server files a question or station under.
    static func same(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// A finished job's verdicts.
    ///
    /// Into the generation's own Delivery when there is one (CloudJobs.context),
    /// so a job collected in the meantime - the app coming back to the
    /// foreground while this one's replies are read - cannot put its verdicts
    /// on this one's cards. Otherwise they replace the last job's.
    static func server(_ verdicts: [CloudJobs.Verdict]) {
        if let delivery = CloudJobs.context?.delivery {
            delivery.receive(verdicts)
            return
        }
        lock.lock(); defer { lock.unlock() }
        byKey = Dictionary(verdicts.map { ($0.key, $0.reply) }, uniquingKeysWith: { _, last in last })
        var found: [String: [EvidenceRef]] = [:]
        for v in verdicts {
            if let refs = v.evidence, !refs.isEmpty { found[v.key] = refs }
        }
        evidenceByKey = found
    }

    /// The verdicts this generation reads: its own, or the last job's.
    private static var current: (byKey: [String: String], evidence: [String: [EvidenceRef]]) {
        if let delivery = CloudJobs.context?.delivery { return delivery.tables }
        lock.lock(); defer { lock.unlock() }
        return (byKey, evidenceByKey)
    }

    /// The evidence the server's check read for an item, if any.
    static func evidence(forKey key: String) -> [EvidenceRef] {
        current.evidence[key] ?? []
    }

    /// Questions with the evidence their check read attached to their
    /// differential, so "How to reach it" can cite it. Only what the lookup
    /// returned is ever attached; a question without a differential is left
    /// as it is.
    static func cite(_ questions: [MCQQuestion]) -> [MCQQuestion] {
        questions.map { q -> MCQQuestion in
            guard var tiers = q.differential else { return q }
            let refs: [EvidenceRef] = evidence(forKey: same(q.stem))
            guard !refs.isEmpty else { return q }
            tiers.evidence = refs
            var cited = q
            cited.differential = tiers
            return cited
        }
    }

    static func reply(forKey key: String) -> String? {
        current.byKey[key]
    }

    /// Every verdict of the job (a textbook's pages, a deck's batches).
    static var allReplies: [String] {
        Array(current.byKey.values)
    }

    /// The verdict for exactly this checked text.
    static func remember(_ reply: String, forOutput output: String) {
        lock.lock(); defer { lock.unlock() }
        byOutput[output] = reply
    }

    /// Used once: the next check of the same text asks the checker again.
    static func take(forOutput output: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return byOutput.removeValue(forKey: output)
    }
}
