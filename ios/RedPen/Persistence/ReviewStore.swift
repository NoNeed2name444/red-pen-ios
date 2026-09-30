import Foundation
import Combine

/// Only decks of cards have a schedule; a textbook or a transcript answers with
/// nothing, which is what keeps them out of the day's queue.
extension StudySet: ReviewDeck {
    var deckID: UUID { id }
    var deckName: String { name }
    var deckCards: [AnkiCard] { kind == .anki ? cards : [] }
}

/// Where the schedule lives between sessions.
///
/// Deliberately a file of its own rather than another field in the library
/// snapshot. The library carries every set's images as base64 inside its JSON,
/// so it can run to tens of megabytes; rewriting all of it every time a card is
/// rated - four times a second, in a fast review - would make the rating
/// buttons stutter. This file holds a date and two counters per card and stays
/// a few kilobytes however big the library gets.
///
/// The decisions are all in ReviewPlan, which is pure and tested. This only
/// remembers them.
@MainActor
final class ReviewStore: ObservableObject {
    @Published private(set) var records: [UUID: ReviewRecord] = [:] { didSet { changeCount &+= 1 } }
    /// Moves on every change to the schedule, so a screen can tell cheaply
    /// that figures built on it are out of date.
    private(set) var changeCount = 0

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = dir.appendingPathComponent("redpen-reviews.json")
        }
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let stored = try? JSONDecoder.redPen.decode([UUID: ReviewRecord].self, from: data) else {
            // put aside before the next rating writes an empty schedule over it
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("reviews-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: aside)
            return
        }
        records = stored
    }

    private func save() {
        guard let data = try? JSONEncoder.redPen.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: what the review screens ask for

    /// Today's queue for one deck: due, not suspended or buried, and within
    /// the daily limits in Settings > Review.
    func queue(for cards: [AnkiCard], now: Date = Date()) -> [AnkiQueueItem] {
        let limits: ReviewLimits = ReviewSettings.limits()
        return ReviewPlan.dailyQueue(for: cards, records: records, now: now, limits: limits,
                                     today: today(now, limits: limits))
    }

    /// Today's counts, worked out once per change to the schedule (and per
    /// study day) rather than once per deck row; nil with no limits set,
    /// when nothing needs them.
    private func today(_ now: Date, limits: ReviewLimits) -> ReviewPlan.DayCounts? {
        guard !limits.isUnlimited else { return nil }
        let day: Date = ReviewDay.start(of: now)
        if let cached = dayCounts, cached.change == changeCount, cached.day == day { return cached.counts }
        let counted: ReviewPlan.DayCounts = ReviewPlan.counts(records, now: now)
        dayCounts = DayCountsCache(change: changeCount, day: day, counts: counted)
        return counted
    }

    private struct DayCountsCache {
        let change: Int
        let day: Date
        let counts: ReviewPlan.DayCounts
    }

    private var dayCounts: DayCountsCache?

    /// Study ahead: the whole deck except suspended cards.
    func everything(_ cards: [AnkiCard], now: Date = Date()) -> [AnkiQueueItem] {
        ReviewPlan.studyAhead(cards, records: records, now: now)
    }

    /// How many of these cards today's queue holds - counted, not built.
    func dueCount(for cards: [AnkiCard], now: Date = Date()) -> Int {
        let limits: ReviewLimits = ReviewSettings.limits()
        return ReviewPlan.dueCount(for: cards, records: records, now: now, limits: limits,
                                   today: today(now, limits: limits))
    }

    func nextDue(for cards: [AnkiCard]) -> Date? {
        ReviewPlan.nextDue(for: cards, records: records)
    }

    func dueAcross(_ sets: [StudySet], now: Date = Date()) -> [ReviewPlan.Due] {
        let limits: ReviewLimits = ReviewSettings.limits()
        return ReviewPlan.dueToday(sets, records: records, now: now, limits: limits,
                                   today: today(now, limits: limits))
    }

    /// Cards the student has suspended.
    var suspendedCount: Int {
        records.values.filter { $0.suspended == true }.count
    }

    /// Settings > Review changed a limit or the scheduler: every due count
    /// on screen is out of date.
    func settingsChanged() {
        objectWillChange.send()
        changeCount &+= 1
    }

    // MARK: what a rating changes

    /// Records a rating and returns the card's new standing.
    @discardableResult
    func rate(_ rating: AnkiRating, card: AnkiCard, now: Date = Date()) -> ReviewRecord {
        let kept = ReviewPlan.record(for: card, in: records, now: now)
        let next = ReviewPlan.after(rating: rating, record: kept, now: now,
                                    exam: ExamCap.storedDate(),
                                    scheduler: ReviewSettings.scheduler())
        lastRating = UndoableRating(cardID: card.id, previous: records[card.id], rating: rating, at: now)
        records[card.id] = next
        save()
        return next
    }

    // MARK: undo, suspend, bury

    /// The rating that Undo would take back: the card and its record from
    /// before. One step, as in Anki's review screen.
    struct UndoableRating: Equatable {
        var cardID: UUID
        var previous: ReviewRecord?
        var rating: AnkiRating
        var at: Date
    }

    private(set) var lastRating: UndoableRating?

    /// Takes back the last rating. Returns the card it was, or nil when there
    /// is nothing to undo.
    @discardableResult
    func undoLast(now: Date = Date()) -> UndoableRating? {
        guard let last = lastRating else { return nil }
        lastRating = nil
        records[last.cardID] = ReviewPlan.restoring(last.previous, now: now)
        save()
        return last
    }

    /// Out of every queue until let back in (Settings > Review).
    func suspend(_ card: AnkiCard, now: Date = Date()) {
        records[card.id] = ReviewPlan.suspending(card, true, in: records, now: now)
        if lastRating?.cardID == card.id { lastRating = nil }
        save()
    }

    /// Out of today's queues, back tomorrow.
    func bury(_ card: AnkiCard, now: Date = Date()) {
        records[card.id] = ReviewPlan.burying(card, in: records, now: now)
        if lastRating?.cardID == card.id { lastRating = nil }
        save()
    }

    /// Every suspended card back into its deck's schedule.
    func unsuspendAll(now: Date = Date()) {
        var kept = records
        for (id, record) in records where record.suspended == true {
            var back = record
            back.suspended = nil
            back.changedAt = now
            kept[id] = back
        }
        guard kept != records else { return }
        records = kept
        save()
    }

    /// A card that was deleted loses its place.
    func forget(_ cardID: UUID) {
        guard records[cardID] != nil else { return }
        records[cardID] = nil
        save()
    }

    /// Several cards at once - a deck deleted here or on another device -
    /// with one write.
    ///
    /// By card rather than by what the library holds: a schedule for a deck
    /// this device has not received yet (a first sync is part way through) or
    /// cannot read is still somebody's schedule, and must not be taken for
    /// one whose deck is gone.
    func forget(_ cardIDs: [UUID]) {
        var kept = records
        for id in cardIDs { kept[id] = nil }
        guard kept.count != records.count else { return }
        records = kept
        save()
    }

    /// Takes in a schedule from another device, card by card.
    ///
    /// Merged, never replaced. A phone that reviewed twenty cards this morning
    /// and a laptop that reviewed five others this afternoon must end up with
    /// all twenty-five; last-write-wins would throw one of those sittings away
    /// without saying so, which is the worst way for a study app to fail.
    func merge(_ incoming: [UUID: ReviewRecord]) {
        guard !incoming.isEmpty else { return }
        let merged = SyncDocuments.mergeRecords(records, incoming)
        guard merged != records else { return }
        records = merged
        save()
    }

    /// Drops records for cards that no longer exist in any set.
    ///
    /// Only safe with every deck in hand - not during a sync, which may not
    /// have brought a deck yet, and not when the library left out a set it
    /// could not read. Deleting a deck forgets its own cards instead
    /// (`forget(_:)` with the deck's cards), which never needs this.
    func prune(keeping sets: [StudySet]) {
        let kept = ReviewPlan.pruned(records, keeping: sets)
        guard kept.count != records.count else { return }
        records = kept
        save()
    }
}
