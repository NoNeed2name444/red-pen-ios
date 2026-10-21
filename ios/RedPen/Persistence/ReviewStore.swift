import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

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
/// buttons stutter. This file holds a few dates and counters per card, and is
/// written a moment after the last change, off the main thread, so a run of
/// ratings is one write.
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
    /// The file was there at launch and could not be read: a launch before
    /// the first unlock after a restart (iOS prewarms the app) finds it still
    /// protected. That is not an empty schedule, so nothing is written over
    /// it until `reloadIfUnread()` has read it.
    private(set) var unreadable = false
    /// A change not yet handed to a write.
    private var dirty = false
    /// Whether the last write failed (the disk is full, the file is
    /// protected): the change stays dirty, to be written again, and
    /// `flushed()` says so, so sync records nothing as safely here.
    private var writeFailed = false
    private var writesInFlight = 0
    private var flushWaiters: [CheckedContinuation<Void, Never>] = []
    /// The delayed write waiting to run, if any.
    private var pendingWrite: Task<Void, Never>?
    /// Set up with the first change rather than at init: a store opened only
    /// to read the schedule (an export from Shortcuts) never writes.
    private var lifecycleObservers: [NSObjectProtocol] = []

    /// Encoding and writing happen here, off the main thread, one at a time
    /// and in order, so a later write can never land before an earlier one.
    private static let writeQueue = DispatchQueue(label: "redpen.reviews.write", qos: .utility)
    /// How long a change waits for more before the schedule is written: a
    /// fast review rates a card or two a second.
    private static let saveDelayNanoseconds: UInt64 = 1_000_000_000

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
        let data: Data
        switch StoreFiles.read(fileURL) {
        case .data(let read):
            data = read
        case .missing:
            unreadable = false
            return
        case .unreadable:
            unreadable = true
            // read again once the app is in front, the device unlocked
            observeLifecycle()
            return
        }
        unreadable = false
        // card by card: a record this version cannot read costs only itself,
        // not the whole schedule
        guard let read = RecoveryFiles.records(ReviewRecord.self, from: data, decoder: .redPen) else {
            // put aside before the next rating writes an empty schedule over it
            RecoveryFiles.putAside(fileURL, as: "reviews-unreadable")
            return
        }
        // the records left out survive in a copy (Settings > Your data)
        if read.skipped > 0 { RecoveryFiles.putAside(fileURL, as: "reviews-partly-unreadable") }
        records = read.values
    }

    /// Reads again a schedule that could not be read at launch, once the app
    /// is in front (the device is unlocked by then). Anything taken in
    /// meanwhile (a sync that ran first) is merged into what is read, card by
    /// card, so neither is lost.
    func reloadIfUnread() {
        guard unreadable else { return }
        let here: [UUID: ReviewRecord] = records
        load()
        guard !unreadable else { return }
        merge(here)
    }

    private func save() {
        dirty = true
        observeLifecycle()
        guard pendingWrite == nil else { return }
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(nanoseconds: ReviewStore.saveDelayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.pendingWrite = nil
            self.write()
        }
    }

    /// Writes anything outstanding now: for the moment the app leaves the
    /// foreground, and for sync (`flushed()`).
    ///
    /// `wait` blocks until the bytes are on disk - only for the app being
    /// ended, when nothing queued would get the chance to run.
    func flush(wait: Bool = false) {
        pendingWrite?.cancel()
        pendingWrite = nil
        write()
        if wait { Self.writeQueue.sync {} }
    }

    /// Writes anything outstanding and returns once it is on disk, without
    /// holding the main thread while it is written. Sync waits for it before
    /// a bookmark says a merged schedule is safely here.
    ///
    /// False when the schedule is not on disk: its write failed, or it could
    /// not be read at launch and nothing is written over it.
    @discardableResult
    func flushed() async -> Bool {
        flush()
        if writesInFlight > 0 {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                flushWaiters.append(done)
            }
        }
        return !writeFailed && !unreadable
    }

    /// Takes a copy of the schedule (cheap: it is a value) and encodes and
    /// writes it on the write queue.
    private func write() {
        guard dirty, !unreadable else { return }
        dirty = false
        writesInFlight += 1
        let job = ReviewWriteJob(records: records, url: fileURL)
        #if canImport(UIKit)
        // a write started just before the app is backgrounded still finishes
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "Saving reviews", expirationHandler: nil)
        Self.writeQueue.async { [weak self] in
            let landed = job.run()
            Task { @MainActor in
                self?.writeFinished(landed)
                if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
            }
        }
        #else
        Self.writeQueue.async { [weak self] in
            let landed = job.run()
            Task { @MainActor in
                self?.writeFinished(landed)
            }
        }
        #endif
    }

    /// Back on the main actor after a write: a schedule that did not land is
    /// dirty again, and whoever waits in `flushed()` is let go.
    private func writeFinished(_ landed: Bool) {
        writesInFlight -= 1
        writeFailed = !landed
        if !landed {
            dirty = true
            Diagnostics.record(.error, area: .app, message: "reviews.write_failed")
        }
        if writesInFlight == 0 {
            let waiting = flushWaiters
            flushWaiters = []
            for done in waiting { done.resume() }
        }
    }

    /// Writes anything outstanding when the app leaves the foreground, where
    /// it may be suspended or ended before a delayed write would run; and
    /// reads again a schedule that was still protected at launch, once the
    /// app is in front.
    private func observeLifecycle() {
        #if canImport(UIKit)
        guard lifecycleObservers.isEmpty else { return }
        let names: [Notification.Name] = [UIApplication.didEnterBackgroundNotification,
                                          UIApplication.willTerminateNotification]
        for name in names {
            let ending = name == UIApplication.willTerminateNotification
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush(wait: ending) }
            }
            lifecycleObservers.append(token)
        }
        let active = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfUnread() }
        }
        lifecycleObservers.append(active)
        #endif
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

/// One write of the schedule, carried to the write queue: a copy of the
/// records and where they go. Only values, so it is safe to hand over.
private struct ReviewWriteJob: @unchecked Sendable {
    var records: [UUID: ReviewRecord]
    var url: URL

    /// Whether it landed: false when encoding or the write failed (the disk
    /// is full, the file is protected).
    func run() -> Bool {
        // an encoder of its own, not the shared one, as the library's write does
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return false }
        return StoreFiles.write(data, to: url) == nil
    }
}
