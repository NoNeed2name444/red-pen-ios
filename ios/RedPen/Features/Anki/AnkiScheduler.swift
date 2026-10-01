import Foundation

/// A line-for-line port of the web app's Anki scheduling — see the comment
/// block above `var ANKI_MIN` in red-pen-content.html. Every rating
/// schedules the card's next appearance at real wall-clock now+interval and
/// reinserts it into the queue, which stays sorted by due time ascending;
/// intervals escalate per-card on repeat presses (Hard/Good/Easy grow the
/// interval; Again always resets to 1 minute), loosely mirroring real
/// Anki's learning-step feel. Kept as free functions/constants (not tied to
/// any view) so it's trivially testable and exactly matches the web
/// version's behavior for the same rating sequence.
enum AnkiRating: String, CaseIterable {
    case again, hard, good, easy
}

enum AnkiScheduler {
    /// Minutes — matches the web app's `ANKI_MIN` object exactly.
    static let baseMinutes: [AnkiRating: Double] = [
        .again: 1,
        .hard: 5,
        .good: 10,
        .easy: 4 * 24 * 60,
    ]

    /// The longest any card is put away: a hundred years. Without a ceiling
    /// repeated Easy ratings multiply an interval past the year 9999, which
    /// a stored date cannot round-trip, and past what an Int can hold, which
    /// traps the rating buttons' label.
    static let maxIntervalMin: Double = 36_500 * 1440

    /// Matches `formatInterval()`: minutes -> "N min" / "N hr" / "N d".
    static func formatInterval(_ minutes: Double) -> String {
        // clamped before any Int conversion: a runaway interval (or a stored
        // infinity) must not crash the label
        let m: Double = minutes.isFinite ? min(maxIntervalMin, max(1, minutes)) : maxIntervalMin
        if m < 60 { return "\(Int(m.rounded())) min" }
        if m < 1440 { return "\(Int((m / 60).rounded())) hr" }
        return "\(Int((m / 1440).rounded())) d"
    }

    /// Matches the `el.ankiRateGrid` click handler's `next` computation, and
    /// never longer than maxIntervalMin.
    static func nextInterval(rating: AnkiRating, currentIntervalMin: Double) -> Double {
        let cur: Double = currentIntervalMin.isFinite ? currentIntervalMin : maxIntervalMin
        let next: Double
        switch rating {
        case .again: next = baseMinutes[.again]!
        case .hard: next = max(baseMinutes[.hard]!, cur * 1.2)
        case .good: next = max(baseMinutes[.good]!, cur * 2.5)
        case .easy: next = max(baseMinutes[.easy]!, cur * 4)
        }
        return min(maxIntervalMin, next)
    }

    /// Matches `updateAnkiRateLabels()` — the four "in N min/hr/d" previews
    /// shown on the rating buttons before the user picks one.
    ///
    /// Read through the same exam cap the schedule stores (ExamCap), so a
    /// button never promises "in 30 d" for a card that will be back before
    /// an exam in twelve.
    static func previewLabels(currentIntervalMin: Double, now: Date = Date(),
                              exam: Date? = ExamCap.storedDate()) -> [AnkiRating: String] {
        var out: [AnkiRating: String] = [:]
        for rating in AnkiRating.allCases {
            let plain: Double = nextInterval(rating: rating, currentIntervalMin: currentIntervalMin)
            out[rating] = "in " + formatInterval(ExamCap.capped(plain, now: now, exam: exam))
        }
        return out
    }

    /// Seeds a fresh session queue from a card deck — matches
    /// `openAnkiReview()` setting `state.ankiQueue` from `state.ankiCards`,
    /// every card due immediately with a zero starting interval.
    static func seedQueue(cards: [AnkiCard]) -> [AnkiQueueItem] {
        let now = Date()
        return cards.map { AnkiQueueItem(card: $0, due: now, intervalMin: 0) }
    }

    /// Applies a rating to a queue item and reinserts it into the queue,
    /// re-sorted by due date ascending — matches the click handler's
    /// `item.intervalMin = next; item.due = Date.now() + next * 60000` plus
    /// the queue re-sort in `showNextAnkiCard()`.
    static func apply(rating: AnkiRating, to item: AnkiQueueItem, in queue: inout [AnkiQueueItem]) {
        guard let idx = queue.firstIndex(where: { $0.id == item.id }) else { return }
        let next = nextInterval(rating: rating, currentIntervalMin: queue[idx].intervalMin)
        queue[idx].intervalMin = next
        queue[idx].due = Date().addingTimeInterval(next * 60)
        queue.sort { $0.due < $1.due }
    }
}
