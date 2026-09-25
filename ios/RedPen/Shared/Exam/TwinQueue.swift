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

    /// Adds a twin; one per missed question - a newer twin replaces an
    /// unanswered older one for the same parent.
    mutating func add(twin id: UUID, parent: UUID, now: Date = Date(), confident: Bool = false,
                      guessed: Bool = false) {
        entries.removeAll { $0.parentId == parent && $0.answeredAt == nil }
        let days: Int = Self.delayDays(confident: confident, guessed: guessed)
        let due: Date = now.addingTimeInterval(Double(days) * 86_400)
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
    mutating func answered(_ id: UUID, correct: Bool, now: Date = Date()) {
        guard let i = entries.firstIndex(where: { $0.id == id && $0.answeredAt == nil }) else { return }
        if correct {
            entries[i].answeredAt = now
            entries[i].answeredCorrectly = true
        } else if entries[i].answeredCorrectly == false {
            // second miss: stays answered-wrong; the ordinary mistakes queue has it
            entries[i].answeredAt = now
        } else {
            entries[i].answeredCorrectly = false
            entries[i].dueAt = now.addingTimeInterval(86_400)
        }
    }

    /// Drops entries whose twin is no longer in the library.
    mutating func prune(keeping ids: Set<UUID>) {
        entries.removeAll { !ids.contains($0.id) }
    }
}

/// Where the immediate re-test goes: a few questions on, or at the end when
/// the quiz is nearly over. `current` and `count` are positions in the quiz.
enum TwinRetest {
    static let gap = 3

    static func slot(after current: Int, count: Int) -> Int {
        min(current + 1 + gap, count)
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
