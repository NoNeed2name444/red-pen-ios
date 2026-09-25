import Foundation

/// What the exam tools remember on this device: the twins waiting to come
/// back, twins still to be written (asked for while offline), the attending's
/// hints once written, and past mock sittings.
///
/// Kept in UserDefaults as small JSON blobs. The twin QUESTIONS themselves live
/// in the library (a "Twins" set per subject), so they sync, can be flagged and
/// have an answer history like any other; only their due dates are here.
@MainActor
final class ExamStore: ObservableObject {
    static let shared = ExamStore()

    private static let twinsKey = "exam.twins"
    private static let pendingKey = "exam.twins.pending"
    private static let hintsKey = "exam.hints"
    private static let mocksKey = "exam.mocks"

    @Published private(set) var twins: TwinQueue
    /// Twins asked for but not yet written.
    @Published private(set) var pending: [PendingTwin]
    @Published private(set) var hints: HintCache
    @Published private(set) var mocks: [MockRecord]

    private init() {
        twins = Self.load(TwinQueue.self, Self.twinsKey) ?? TwinQueue()
        pending = Self.load([PendingTwin].self, Self.pendingKey) ?? []
        hints = Self.load(HintCache.self, Self.hintsKey) ?? HintCache()
        mocks = Self.load([MockRecord].self, Self.mocksKey) ?? []
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func keep<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: twins

    func addTwin(_ id: UUID, parent: UUID, confident: Bool, guessed: Bool) {
        twins.add(twin: id, parent: parent, confident: confident, guessed: guessed)
        pending.removeAll { $0.parentId == parent }
        Self.keep(twins, Self.twinsKey)
        Self.keep(pending, Self.pendingKey)
    }

    func twinAnswered(_ id: UUID, correct: Bool) {
        guard twins.isTwin(id) else { return }
        twins.answered(id, correct: correct)
        Self.keep(twins, Self.twinsKey)
    }

    func queueForLater(_ request: PendingTwin) {
        guard !pending.contains(where: { $0.parentId == request.parentId }) else { return }
        pending.append(request)
        if pending.count > 30 { pending.removeFirst(pending.count - 30) }
        Self.keep(pending, Self.pendingKey)
    }

    func dropPending(_ parent: UUID) {
        pending.removeAll { $0.parentId == parent }
        Self.keep(pending, Self.pendingKey)
    }

    func isTwinOnTheWay(for parent: UUID) -> Bool {
        twins.hasTwin(for: parent) || pending.contains { $0.parentId == parent }
    }

    /// Forgets twins whose question has left the library.
    func prune(_ store: Store) {
        var ids: Set<UUID> = []
        for set in store.library where set.kind == .mcq {
            for q in set.questions { ids.insert(q.id) }
        }
        let before: Int = twins.entries.count
        twins.prune(keeping: ids)
        if twins.entries.count != before { Self.keep(twins, Self.twinsKey) }
    }

    // MARK: hints

    func hint(for id: UUID) -> String? { hints.hint(for: id) }

    func keepHint(_ text: String, for id: UUID) {
        hints.store(text, for: id)
        Self.keep(hints, Self.hintsKey)
    }

    // MARK: mocks

    func record(_ mock: MockRecord) {
        mocks.insert(mock, at: 0)
        if mocks.count > 50 { mocks.removeLast(mocks.count - 50) }
        Self.keep(mocks, Self.mocksKey)
    }
}

/// A twin asked for while it could not be written - no network, the model
/// busy - kept so it can be written the next time a quiz opens.
struct PendingTwin: Codable, Hashable {
    var parentId: UUID
    var picked: Int?
    var reason: String?
    var confident: Bool
    var guessed: Bool
}

/// One mock sitting, as remembered.
struct MockRecord: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String
    var track: String
    var correct: Int
    var total: Int
    var wanted: Int
    var passMark: Double
    var minutesUsed: Int

    var fraction: Double { total == 0 ? 0 : Double(correct) / Double(total) }
}

// MARK: - the library side

@MainActor
extension Store {
    /// The library's Twins set for `subject`, made when first needed.
    func twinsSet(subject: String) -> StudySet {
        let name: String = "Twins \u{00B7} " + subject
        if let found = library.first(where: { $0.kind == .mcq && $0.name == name }) { return found }
        let made = StudySet(name: name, subject: subject, kind: .mcq)
        addSet(made)
        return made
    }

    /// Puts a written twin into its subject's Twins set.
    func addTwin(_ twin: MCQQuestion, subject: String) {
        var set: StudySet = twinsSet(subject: subject)
        set.questions.append(twin)
        update(set)
    }

    /// The twins due now, as a quiz; the longest-waiting first.
    func twinsQuiz(limit: Int = 20) -> StudySet {
        ExamStore.shared.prune(self)
        let due: [TwinEntry] = ExamStore.shared.twins.due()
        let order: [UUID] = due.map(\.id)
        let wanted: Set<UUID> = Set(order)
        let picks: [QuestionPick] = mcqPicks { wanted.contains($0.question.id) }
        let pairs: [(UUID, Int)] = order.enumerated().map { ($0.element, $0.offset) }
        let rank: [UUID: Int] = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        let sorted: [QuestionPick] = picks.sorted { (rank[$0.question.id] ?? 0) < (rank[$1.question.id] ?? 0) }
        return Self.temporaryQuiz(named: "Twin questions", subject: "Twins", from: Array(sorted.prefix(limit)))
    }

    /// The set a question lives in, for its subject and pictures.
    func pick(for questionId: UUID) -> QuestionPick? {
        mcqPicks { $0.question.id == questionId }.first
    }
}

// MARK: - writing twins

/// What came of asking for a twin.
enum TwinOutcome: Equatable {
    case made
    /// Nothing can write one on this device; said once, plainly.
    case unavailable(String)
    /// Couldn't write it now; it waits and is tried again later.
    case later(String)
}

@MainActor
enum TwinWriter {
    static let noWriter: String = "Twins are written by a question writer: turn on Apple Intelligence, or choose one in AI models."

    /// Writes a twin for `question` and puts it in the queue.
    static func write(_ request: PendingTwin, store: Store) async -> TwinOutcome {
        guard let pick = store.pick(for: request.parentId) else {
            ExamStore.shared.dropPending(request.parentId)
            return .unavailable("This question is no longer in the library.")
        }
        guard let backend = LocalLLMService.shared.writerOrApple() else {
            return .unavailable(noWriter)
        }
        let q: MCQQuestion = pick.question
        let input: String = TwinPrompt.input(stem: q.stem, options: q.options, correctIndex: q.correctIndex,
                                             explanation: q.explanation, picked: request.picked,
                                             reason: request.reason)
        let system: String = TwinPrompt.instructions(style: ExamTrack.current.mcqStyle)
        var found: [MCQQuestion] = []
        do {
            let reply: String = try await backend.complete([.system(system), .user(input)],
                                                           maxTokens: 1_400, temperature: 0.8)
            found = MedicalGenerate.parseQuestions(reply)
        } catch {
            found = []
        }
        // the cloud writer's own job path, when the direct call gave nothing
        if found.isEmpty, CloudJobs.endpoint(for: backend) != nil {
            let source: String = system + "\n\n" + input
            let subject: String = Store.subjectName(pick.set)
            found = (try? await MedicalGenerate.mcq(sourceText: source, count: 1, subject: subject,
                                                    highYield: false, using: backend)) ?? []
        }
        guard var twin = found.first(where: { !TwinPrompt.isTooClose($0.stem, to: q.stem) }) else {
            ExamStore.shared.queueForLater(request)
            return .later("Couldn\u{2019}t write the twin just now. It will be tried again next time you practise.")
        }
        twin.id = UUID()
        twin.source = q.source.map { "Twin of a question from " + $0 } ?? "Twin of a missed question"
        let subject: String = Store.subjectName(pick.set)
        store.addTwin(twin, subject: subject)
        ExamStore.shared.addTwin(twin.id, parent: q.id, confident: request.confident, guessed: request.guessed)
        return .made
    }

    /// Writes the twins asked for while offline, quietly, one at a time.
    static func retryPending(store: Store) async {
        let waiting: [PendingTwin] = ExamStore.shared.pending
        for request in waiting.prefix(3) {
            if Task.isCancelled { return }
            let outcome: TwinOutcome = await write(request, store: store)
            if case .later = outcome { return }
            if case .unavailable = outcome { return }
        }
    }
}

// MARK: - the attending's hint

@MainActor
enum HintWriter {
    /// The hint for an item: kept from before, written now, or made from its
    /// differential when there is no writer or the written one gave the
    /// answer away. Never throws: a hint is always there.
    static func hint(id: UUID, stem: String, options: [String], answer: String,
                     differential: DifferentialTiers?) async -> String {
        if let kept = ExamStore.shared.hint(for: id) { return kept }
        let others: [String] = options.filter { $0 != answer }
        let fallback: String = AttendingHint.fallback(answer: answer, stem: stem, options: options,
                                                      differential: differential)
        guard let backend = LocalLLMService.shared.writerOrApple() else { return fallback }
        let input: String = AttendingHint.input(stem: stem, options: options, answer: answer,
                                                differential: differential)
        let reply: String? = try? await backend.complete([.system(AttendingHint.instructions), .user(input)],
                                                         maxTokens: 160, temperature: 0.4)
        guard let reply, let good = AttendingHint.accept(reply, answer: answer, stem: stem, otherOptions: others) else {
            return fallback
        }
        ExamStore.shared.keepHint(good, for: id)
        return good
    }
}
