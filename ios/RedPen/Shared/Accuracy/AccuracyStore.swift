import Foundation
import Combine

/// The accuracy engine on this device: what has been found about every item
/// (the ledger, kept on disk by content hash), the model weights it is scored
/// with, and the loop that checks the library.
///
/// New and just-edited content is checked first, in the foreground; the rest
/// of the library in the background, low priority, most-studied first, a
/// batch at a time with a pause between, and only while it is free: the
/// server's own per-account shares and daily limits decide, and a "that's
/// today's" answer stops that kind of check until the next UTC day. An item
/// is never sent twice unless it is edited. Checks need Vignette Cloud (Pro);
/// without it the rule checks still run on the phone, and they can Flag an
/// item but never Verify one.
@MainActor
final class AccuracyStore: ObservableObject {
    static let shared = AccuracyStore()

    @Published private(set) var ledger = AccuracyLedger()
    @Published private(set) var weights: AccuracyWeights = AccuracyModel.bundled
    /// Item hashes being checked right now, for "Checking…".
    @Published private(set) var inFlight: Set<String> = []
    /// Check the whole library in the background (Settings > AI models).
    @Published var background: Bool {
        didSet { UserDefaults.standard.set(background, forKey: Self.backgroundKey) }
    }
    /// Why checking stopped, in words, for Settings; nil while all is well.
    @Published private(set) var pausedReason: String?

    private weak var store: Store?
    private var itemCache: [UUID: (stamp: Date, items: [AccuracyItem])] = [:]
    private var building: Set<UUID> = []
    private var memo: [String: AccuracyAssessment] = [:]
    private var running: Task<Void, Never>?
    private var kickTask: Task<Void, Never>?
    private var observer: AnyCancellable?
    private var saveTask: Task<Void, Never>?
    private var blockedUntil: [String: Date] = [:]

    private static let backgroundKey = "accuracy.background"
    private static let weightsKey = "accuracy.weights"
    private static let weightsCheckedKey = "accuracy.weightsChecked"
    /// A pause between background batches: the free limits are per minute too.
    static let backgroundPause: Duration = .seconds(20)

    private init() {
        let defaults = UserDefaults.standard
        background = defaults.object(forKey: Self.backgroundKey) as? Bool ?? true
        if let data = defaults.data(forKey: Self.weightsKey),
           let w = try? JSONDecoder().decode(AccuracyWeights.self, from: data), w.isValid {
            weights = w
        }
        ledger = Self.load()
    }

    // MARK: wiring

    /// Called once by the app: every change to the library is a reason to
    /// look for something new to check.
    func attach(_ store: Store) {
        guard self.store == nil else { return }
        self.store = store
        observer = store.$library
            .dropFirst()
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { _ in Task { @MainActor in AccuracyStore.shared.kick() } }
        kick()
        Task { await refreshWeights() }
    }

    /// Look for work, soon; a running pass carries on.
    func kick() {
        kickTask?.cancel()
        kickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            if self.running == nil { self.running = Task { await self.run(); self.running = nil } }
        }
    }

    // MARK: what the screens ask

    /// Every checkable item of a set, worked out off the main thread the
    /// first time (finding each item's lecture excerpt reads the sources), and
    /// nil until then.
    func items(for set: StudySet) -> [AccuracyItem]? {
        if let hit = itemCache[set.id], hit.stamp == set.updatedAt { return hit.items }
        build(set)
        return nil
    }

    private func build(_ set: StudySet) {
        guard !building.contains(set.id) else { return }
        building.insert(set.id)
        Task.detached(priority: .utility) { [set] in
            let items: [AccuracyItem] = AccuracyItem.items(in: set) { words in
                AccuracyChecker.reference(for: words, in: set, limit: AccuracyItem.sourceLimit)
            }
            await MainActor.run {
                AccuracyStore.shared.itemCache[set.id] = (stamp: set.updatedAt, items: items)
                AccuracyStore.shared.building.remove(set.id)
                AccuracyStore.shared.objectWillChange.send()
            }
        }
    }

    func item(_ id: String, in set: StudySet) -> AccuracyItem? {
        items(for: set)?.first { $0.id == id }
    }

    func assessment(of item: AccuracyItem) -> AccuracyAssessment {
        let key: String = item.contentHash + "|" + weights.version
        if let hit = memo[key] { return hit }
        let a: AccuracyAssessment = ledger.assess(item, weights: weights)
        memo[key] = a
        return a
    }

    func isChecking(_ item: AccuracyItem) -> Bool { inFlight.contains(item.contentHash) }

    func summary(for set: StudySet) -> AccuracySummary? {
        guard let items = items(for: set), !items.isEmpty else { return nil }
        var s = AccuracySummary()
        for item in items { s.add(assessment(of: item).grade) }
        return s
    }

    // MARK: checking

    private var cloudToken: String? {
        let llm = LocalLLMService.shared
        return llm.cloudBlocker == nil ? llm.cloudToken : nil
    }

    private func run() async {
        guard let store else { return }
        var waits = 0
        while !Task.isCancelled {
            guard let token = cloudToken else {
                pausedReason = LocalLLMService.shared.cloudBlocker
                return
            }
            let sets: [StudySet] = store.library
            let ready: [StudySet] = sets.filter { items(for: $0) != nil }
            let cached: [UUID: [AccuracyItem]] = itemCache.mapValues(\.items)
            let plan: [AccuracyBatch] = AccuracySchedule.plan(sets: ready, items: { cached[$0.id] ?? [] },
                                                             ledger: ledger, studied: studied(store), limit: 8)
            let now = Date()
            let allowed: [AccuracyBatch] = plan.filter { batch in
                if batch.priority == "background" && !background { return false }
                return (blockedUntil[batch.priority] ?? .distantPast) < now
            }
            guard let batch = allowed.first else {
                // sets still being read will kick again when they are ready
                if ready.count < sets.count && waits < 12 {
                    waits += 1
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }
                prune(sets: sets)
                return
            }
            let outcome: Outcome = await send(batch, token: token)
            switch outcome {
            case .done:
                pausedReason = nil
            case .dayUsed:
                blockedUntil[batch.priority] = Self.nextUTCMidnight(after: now)
                if batch.priority == "foreground" { blockedUntil["background"] = Self.nextUTCMidnight(after: now) }
                pausedReason = "Today's free checks are used. Checking carries on after midnight UTC."
            case .notPro(let why):
                pausedReason = why
                return
            case .offline:
                pausedReason = "Offline: checking carries on when there is a connection."
                return
            }
            let pause: Duration = batch.priority == "background" ? Self.backgroundPause : .seconds(1)
            try? await Task.sleep(for: pause)
        }
    }

    enum Outcome { case done, dayUsed, notPro(String), offline }

    struct CheckReply: Decodable {
        struct Item: Decodable {
            var id: String?
            var votes: [AccuracyVote]?
            var evidence: [AccuracyEvidence]?
            var fix: AccuracySuggestion?
            var features: [String: Double]?
            var reason: String?
        }
        var items: [Item]?
        var limit: String?
        var message: String?
    }

    private func send(_ batch: AccuracyBatch, token: String) async -> Outcome {
        let hashes: [String] = batch.items.map(\.contentHash)
        inFlight.formUnion(hashes)
        defer { inFlight.subtract(hashes) }
        struct Body: Encodable { var items: [AccuracyItem]; var priority: String }
        let body = Body(items: batch.items, priority: batch.priority)
        guard let (data, status) = await post("/accuracy/check", body: body, token: token) else { return .offline }
        let reply = try? JSONDecoder().decode(CheckReply.self, from: data)
        if status == 402 { return .notPro(reply?.message ?? "The accuracy check is part of Pro.") }
        if status == 401 { return .notPro("Sign in again to check accuracy.") }
        record(reply, for: batch.items)
        if status == 429 || reply?.limit == "day" { return .dayUsed }
        return status == 200 ? .done : .offline
    }

    private func record(_ reply: CheckReply?, for items: [AccuracyItem]) {
        let now = Date()
        for (n, item) in items.enumerated() {
            let hash: String = item.contentHash
            guard let got = reply?.items?[safe: n], let votes = got.votes, !votes.isEmpty else {
                if reply?.limit != "day" { ledger.failed[hash] = now }
                continue
            }
            let noSource: Bool = (got.features?["no_source"] ?? 1) > 0
            let match: Double? = noSource ? nil : got.features?["source_match"]
            ledger.add(votes: votes, evidence: got.evidence ?? [], sourceMatch: match, fix: got.fix, for: hash, at: now)
        }
        memo.removeAll()
        scheduleSave()
    }

    /// One item now, for the student who asked ("Check now", a note).
    func checkNow(_ item: AccuracyItem) async -> String? {
        guard let token = cloudToken else {
            return LocalLLMService.shared.cloudBlocker ?? "Sign in to check accuracy."
        }
        let outcome: Outcome = await send(AccuracyBatch(setID: UUID(), items: [item], priority: "foreground"), token: token)
        switch outcome {
        case .done: return ledger.isChecked(item.contentHash) ? nil : "The checkers are busy. Try again in a minute."
        case .dayUsed: return "Today's free checks are used. Try again after midnight UTC."
        case .notPro(let why): return why
        case .offline: return "Couldn't reach the server. Check your connection."
        }
    }

    /// "Report an error": kept on the server by the item's hash for the next
    /// training run, and on this device so the item is never shown as
    /// Verified to this student again.
    func report(_ item: AccuracyItem, note: String) async -> String? {
        ledger.markReported(item.contentHash)
        memo.removeAll()
        scheduleSave()
        guard let token = LocalLLMService.shared.cloudToken else {
            return "Saved on this device. Sign in to send reports to \(Brand.name)."
        }
        struct Body: Encodable { var item: AccuracyItem; var note: String }
        guard let (_, status) = await post("/accuracy/report", body: Body(item: item, note: note), token: token) else {
            return "Saved on this device; it couldn't be sent (offline)."
        }
        return status == 200 ? nil : "Saved on this device; the server didn't take it (\(status))."
    }

    private func post<B: Encodable>(_ path: String, body: B, token: String?) async -> (Data, Int)? {
        var request = URLRequest(url: AuthAPI.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONEncoder().encode(body)
        request.timeoutInterval = 180
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (data, http.statusCode)
    }

    /// The newest trained weights, asked for at most once a day.
    func refreshWeights(force: Bool = false) async {
        let defaults = UserDefaults.standard
        let last: Date = defaults.object(forKey: Self.weightsCheckedKey) as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) > 86_400 else { return }
        struct Empty: Encodable {}
        struct Reply: Decodable { var weights: AccuracyWeights }
        guard let (data, status) = await post("/accuracy/model", body: Empty(), token: nil), status == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.weights.isValid,
              reply.weights.features.allSatisfy({ AccuracyModel.features.contains($0) }) else { return }
        defaults.set(Date(), forKey: Self.weightsCheckedKey)
        guard reply.weights != weights else { return }
        weights = reply.weights
        memo.removeAll()
        if let data = try? JSONEncoder().encode(reply.weights) { defaults.set(data, forKey: Self.weightsKey) }
    }

    // MARK: bookkeeping

    /// How much each set is studied: the answers recorded for its questions,
    /// and whether it has reading or quiz progress.
    private func studied(_ store: Store) -> [UUID: Int] {
        var out: [UUID: Int] = [:]
        for set in store.library {
            var n: Int = set.questions.reduce(0) { $0 + (store.answerHistory[$1.id]?.count ?? 0) }
            if store.quizProgress[set.id] != nil { n += 5 }
            if store.readingProgress[set.id] != nil { n += 5 }
            if store.osceProgress[set.id] != nil { n += 5 }
            if n > 0 { out[set.id] = n }
        }
        return out
    }

    /// Records only for items that still exist - or checked in the last month
    /// (a note, a set being edited back).
    private func prune(sets: [StudySet]) {
        var live = Set<String>()
        for set in sets { for item in itemCache[set.id]?.items ?? [] { live.insert(item.contentHash) } }
        let recent: Date = Date().addingTimeInterval(-30 * 86_400)
        for (hash, record) in ledger.records where record.checkedAt > recent { live.insert(hash) }
        let before: Int = ledger.records.count
        ledger.prune(keeping: live)
        if ledger.records.count != before { scheduleSave() }
    }

    static func nextUTCMidnight(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let start: Date = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }

    nonisolated private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("accuracy-ledger.json")
    }

    nonisolated private static func load() -> AccuracyLedger {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let ledger = try? JSONDecoder().decode(AccuracyLedger.self, from: data) else { return AccuracyLedger() }
        return ledger
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot: AccuracyLedger = ledger
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let url = AccuracyStore.fileURL,
                  let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
