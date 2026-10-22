import Foundation

// Twin questions after a miss.
//
// A wrong answer - above all a confident wrong one - earns two things: one
// immediate re-test of the same question a few items later in the sitting, and
// a "twin", a new question that tests the same discriminating fact in a
// different patient, which comes back one to three days later. The twin checks
// that the fix transfers, not just that the old wording is recognised.
//
// Foundation only, so the queue and the prompt can be tested on Linux.

/// One twin waiting in the queue.
struct TwinEntry: Codable, Hashable, Identifiable {
    /// The twin question's own id (it lives in the library's Twins set).
    var id: UUID
    /// The question that was missed.
    var parentId: UUID
    var createdAt: Date
    var dueAt: Date
    /// Set once the twin has been answered; answered twins stay for the record.
    var answeredAt: Date?
    var answeredCorrectly: Bool?
}

/// The twins, due dates and all.
struct TwinQueue: Codable, Hashable {
    var entries: [TwinEntry] = []

    /// How long after the miss a twin comes back: a day for a confident
    /// mistake (the hypercorrection window, before the old belief returns),
    /// three for a guess, two otherwise.
    static func delayDays(confident: Bool, guessed: Bool) -> Int {
        if confident { return 1 }
        if guessed { return 3 }
        return 2
    }

    /// The start of the day `days` days after `now`, on the student's
    /// calendar: "tomorrow" for a miss at nine at night is tomorrow morning,
    /// not nine tomorrow night.
    static func dueDate(after now: Date, days: Int, calendar: Calendar = .current) -> Date {
        let today: Date = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: days, to: today) ?? now.addingTimeInterval(Double(days) * 86_400)
    }

    /// Adds a twin; one per missed question - a newer twin replaces an
    /// unanswered older one for the same parent.
    mutating func add(twin id: UUID, parent: UUID, now: Date = Date(), confident: Bool = false,
                      guessed: Bool = false, calendar: Calendar = .current) {
        entries.removeAll { $0.parentId == parent && $0.answeredAt == nil }
        let days: Int = Self.delayDays(confident: confident, guessed: guessed)
        let due: Date = Self.dueDate(after: now, days: days, calendar: calendar)
        entries.append(TwinEntry(id: id, parentId: parent, createdAt: now, dueAt: due))
    }

    /// Twins waiting and due by `now`, the longest-waiting first.
    func due(now: Date = Date()) -> [TwinEntry] {
        entries.filter { $0.answeredAt == nil && $0.dueAt <= now }
            .sorted { $0.dueAt < $1.dueAt }
    }

    /// Twins not yet answered, due or not.
    var waiting: [TwinEntry] { entries.filter { $0.answeredAt == nil } }

    /// Whether a question already has a twin on the way.
    func hasTwin(for parent: UUID) -> Bool {
        entries.contains { $0.parentId == parent && $0.answeredAt == nil }
    }

    func isTwin(_ id: UUID) -> Bool { entries.contains { $0.id == id } }

    /// Records the twin's answer. A missed twin comes back once more, a day
    /// later, rather than leaving the queue.
    mutating func answered(_ id: UUID, correct: Bool, now: Date = Date(), calendar: Calendar = .current) {
        guard let i = entries.firstIndex(where: { $0.id == id && $0.answeredAt == nil }) else { return }
        if correct {
            entries[i].answeredAt = now
            entries[i].answeredCorrectly = true
        } else if entries[i].answeredCorrectly == false {
            // second miss: stays answered-wrong; the ordinary mistakes queue has it
            entries[i].answeredAt = now
        } else {
            entries[i].answeredCorrectly = false
            entries[i].dueAt = Self.dueDate(after: now, days: 1, calendar: calendar)
        }
    }

    /// Drops entries whose twin is no longer in the library.
    mutating func prune(keeping ids: Set<UUID>) {
        entries.removeAll { !ids.contains($0.id) }
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

/// What this device keeps about twins (ExamStore saves it): the queue and
/// the twins still to be written. Plain values, so the whole flow - written,
/// waiting, due, answered, reloaded after a relaunch - is tested on Linux.
struct TwinBook: Codable, Hashable {
    var queue = TwinQueue()
    var pending: [PendingTwin] = []

    /// The most twins kept waiting to be written.
    static let pendingLimit = 30

    /// What the Twins tile says while no twin is due.
    static let nothingYet: String = "When you miss a question, tap \u{201C}Write a twin\u{201D} under it. The twin - the same point in a different patient - waits here for a day or two."

    /// A written twin joins the queue; its request is no longer pending.
    mutating func added(_ id: UUID, parent: UUID, confident: Bool, guessed: Bool,
                        now: Date = Date(), calendar: Calendar = .current) {
        queue.add(twin: id, parent: parent, now: now, confident: confident, guessed: guessed, calendar: calendar)
        pending.removeAll { $0.parentId == parent }
    }

    /// A twin that could not be written now waits, once per question.
    mutating func later(_ request: PendingTwin) {
        guard !pending.contains(where: { $0.parentId == request.parentId }) else { return }
        pending.append(request)
        if pending.count > Self.pendingLimit { pending.removeFirst(pending.count - Self.pendingLimit) }
    }

    mutating func dropPending(_ parent: UUID) {
        pending.removeAll { $0.parentId == parent }
    }

    func isOnTheWay(for parent: UUID) -> Bool {
        queue.hasTwin(for: parent) || pending.contains { $0.parentId == parent }
    }

    /// A twin of this question is already written or waiting to be: one twin per miss.
    static let alreadyOnTheWay: String = "A twin of this question is already on the way, under Questions \u{2192} Twins."

    /// A twin was ever written for this question, answered or not.
    func hasWritten(for parent: UUID) -> Bool {
        queue.entries.contains { $0.parentId == parent }
    }

    /// Whether Write a twin should write another: not while one is written or waiting.
    func canWrite(for parent: UUID) -> Bool {
        !hasWritten(for: parent) && !isOnTheWay(for: parent)
    }
}

/// The words of the library's Nothing here yet alert, whichever tile opened it.
enum NothingYetAlert {
    static let title: String = "Nothing here yet"
    static let done: String = "Done"
}

/// What came of asking for a twin.
enum TwinOutcome: Equatable {
    case made
    /// Nothing can write one on this device; said once, plainly.
    case unavailable(String)
    /// Couldn't write it now; it waits and is tried again later.
    case later(String)
}

/// What Write a twin works with, given by the app (TwinWriter) or by a test:
/// the twin book and where it is kept, the library, and the writer.
struct TwinDesk {
    var book: () -> TwinBook
    var keep: (TwinBook) -> Void
    /// The missed question and its subject, or nil once it has left the library.
    var question: (UUID) -> (question: MCQQuestion, subject: String)?
    /// The writer, asked with (system, input); nil when none is set up.
    var complete: ((String, String) async throws -> String)?
    /// The cloud writer's job path (source, subject), when the direct call gave nothing.
    var viaJob: ((String, String) async throws -> [MCQQuestion])?
    var parse: (String) -> [MCQQuestion]
    /// Puts a written twin into its subject's Twins set.
    var shelve: (MCQQuestion, String) -> Void
    var style: String
    var noWriter: String
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current
}

/// Write a twin without the app around it (iOS TwinWriter, Android TwinWriter).
@MainActor
enum TwinWriting {
    static let later: String = "Couldn\u{2019}t write the twin just now. It will be tried again next time you practise."
    static let gone: String = "This question is no longer in the library."

    static func write(_ request: PendingTwin, desk: TwinDesk) async -> TwinOutcome {
        guard let found = desk.question(request.parentId) else {
            var book = desk.book()
            book.dropPending(request.parentId)
            desk.keep(book)
            return .unavailable(gone)
        }
        // one twin per miss: never a second for a question that has one
        if desk.book().hasWritten(for: request.parentId) { return .unavailable(TwinBook.alreadyOnTheWay) }
        guard let complete = desk.complete else { return .unavailable(desk.noWriter) }
        let q: MCQQuestion = found.question
        let input: String = TwinPrompt.input(stem: q.stem, options: q.options, correctIndex: q.correctIndex,
                                             explanation: q.explanation, picked: request.picked,
                                             reason: request.reason)
        let system: String = TwinPrompt.instructions(style: desk.style)
        var questions: [MCQQuestion] = []
        if let reply = try? await complete(system, input) { questions = desk.parse(reply) }
        if questions.isEmpty, let viaJob = desk.viaJob {
            questions = (try? await viaJob(system + "\n\n" + input, found.subject)) ?? []
        }
        guard let twin = TwinDraft.pick(questions, missed: q) else {
            var book = desk.book()
            book.later(request)
            desk.keep(book)
            return .later(later)
        }
        // read again after the wait: the book may have changed meanwhile
        var book = desk.book()
        if book.hasWritten(for: q.id) { return .unavailable(TwinBook.alreadyOnTheWay) }
        desk.shelve(twin, found.subject)
        book.added(twin.id, parent: q.id, confident: request.confident, guessed: request.guessed,
                   now: desk.now(), calendar: desk.calendar)
        desk.keep(book)
        return .made
    }

    /// Writes the twins asked for while offline, quietly, one at a time.
    static func retryPending(desk: TwinDesk) async {
        for request in desk.book().pending.prefix(3) {
            if Task.isCancelled { return }
            if case .made = await write(request, desk: desk) { continue }
            return
        }
    }
}

/// The twin a writer's questions give, or nil when none will do: the first
/// that is not the missed question again, with an id of its own and where
/// it came from.
enum TwinDraft {
    static func pick(_ found: [MCQQuestion], missed: MCQQuestion, id: UUID = UUID()) -> MCQQuestion? {
        guard var twin = found.first(where: { !TwinPrompt.isTooClose($0.stem, to: missed.stem) }) else { return nil }
        twin.id = id
        twin.source = missed.source.map { "Twin of a question from " + $0 } ?? "Twin of a missed question"
        return twin
    }

    /// What the quiz says under the question once the twin is written.
    static func madeNote(days: Int) -> String {
        let when: String = days == 1 ? "tomorrow" : "in \(days) days"
        return "Twin written. It comes back \(when), under Questions \u{2192} Twins."
    }
}

/// Where the immediate re-test goes: a few questions on, or at the end when
/// the quiz is nearly over. `current` and `count` are positions in the quiz.
enum TwinRetest {
    static let gap = 3

    static func slot(after current: Int, count: Int) -> Int {
        min(current + 1 + gap, count)
    }

    /// The slots of a sitting that are a question's first showing; a
    /// re-test repeats an id already seen.
    static func firstShowings(_ ids: [UUID]) -> [Int] {
        var seen = Set<UUID>()
        return ids.indices.filter { seen.insert(ids[$0]).inserted }
    }

    /// A sitting with its re-tests taken out: each question's first answer
    /// and option order, in the set's own order, and the position as the
    /// next of the set's own questions. A re-test is practice straight after
    /// a miss, not a second question: it must not score, and the place it
    /// leaves is the set's, so a sitting with one in can still be resumed.
    static func collapse<Answer>(ids: [UUID], answers: [Answer], orders: [[Int]],
                                 current: Int) -> (answers: [Answer], orders: [[Int]], current: Int) {
        let keep: [Int] = firstShowings(ids).filter { $0 < answers.count && $0 < orders.count }
        let at: Int = keep.filter { $0 < current }.count
        return (keep.map { answers[$0] }, keep.map { orders[$0] }, min(at, max(0, keep.count - 1)))
    }
}

/// The prompt that writes a twin, and the checks on what comes back.
enum TwinPrompt {
    /// What the writer is told. The discriminating fact is kept; the
    /// patient, setting and wording change.
    static func instructions(style: String) -> String {
        let rules: [String] = [
            style,
            "Write ONE new single-best-answer question - a \"twin\" - that tests exactly the same discriminating fact as the question below, but in a different clinical vignette: change the patient's age and sex, the setting and the presentation, and do not reuse its sentences.",
            "The correct answer may be the same concept, but the student must have to apply it, not recognise the old wording. Use five options with one clearly best answer; make the distractor the student chose a plausible option again.",
            "Reply with JSON only, in this shape: {\"questions\":[{\"stem\":\"...\",\"options\":[\"...\",\"...\",\"...\",\"...\",\"...\"],\"correctIndex\":0,\"explanation\":\"...\"}]}"
        ]
        return rules.joined(separator: "\n\n")
    }

    /// The missed question, what was chosen, and why it was missed.
    static func input(stem: String, options: [String], correctIndex: Int, explanation: String,
                      picked: Int?, reason: String?) -> String {
        let answer: String = options.indices.contains(correctIndex) ? options[correctIndex] : ""
        var lines: [String] = ["Missed question:", stem, "", "Options:"]
        for o in options { lines.append("- " + o) }
        lines.append("")
        lines.append("Correct answer: " + answer)
        if let picked, options.indices.contains(picked), picked != correctIndex {
            lines.append("The student chose: " + options[picked])
        }
        if let reason, !reason.isEmpty { lines.append("Why they missed it: " + reason) }
        lines.append("Explanation: " + explanation)
        return lines.joined(separator: "\n")
    }

    /// A twin is no good if it is the same question again: too many of the
    /// stem's words shared.
    static func isTooClose(_ twinStem: String, to stem: String) -> Bool {
        let a: Set<String> = words(twinStem)
        let b: Set<String> = words(stem)
        guard !a.isEmpty, !b.isEmpty else { return false }
        let shared: Double = Double(a.intersection(b).count)
        let smaller: Double = Double(min(a.count, b.count))
        return shared / smaller > 0.8
    }

    static func words(_ text: String) -> Set<String> {
        let lowered: String = text.lowercased()
        let parts: [Substring] = lowered.split { !$0.isLetter && !$0.isNumber }
        return Set(parts.filter { $0.count > 3 }.map(String.init))
    }
}
