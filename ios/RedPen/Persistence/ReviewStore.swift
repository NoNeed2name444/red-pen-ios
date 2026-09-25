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

    func queue(for cards: [AnkiCard], now: Date = Date()) -> [AnkiQueueItem] {
        ReviewPlan.queue(for: cards, records: records, now: now)
    }

    func everything(_ cards: [AnkiCard], now: Date = Date()) -> [AnkiQueueItem] {
        ReviewPlan.everything(cards, records: records, now: now)
    }

    func dueCount(for cards: [AnkiCard], now: Date = Date()) -> Int {
        cards.filter { ReviewPlan.isDue($0, in: records, now: now) }.count
    }

    func nextDue(for cards: [AnkiCard]) -> Date? {
        ReviewPlan.nextDue(for: cards, records: records)
    }

    func dueAcross(_ sets: [StudySet], now: Date = Date()) -> [ReviewPlan.Due] {
        ReviewPlan.dueAcross(sets, records: records, now: now)
    }

    // MARK: what a rating changes

    /// Records a rating and returns the card's new standing.
    @discardableResult
    func rate(_ rating: AnkiRating, card: AnkiCard, now: Date = Date()) -> ReviewRecord {
        let kept = ReviewPlan.record(for: card, in: records, now: now)
        let next = ReviewPlan.after(rating: rating, record: kept, now: now,
                                    exam: ExamCap.storedDate())
        records[card.id] = next
        save()
        return next
    }

    /// A card that was deleted loses its place.
    func forget(_ cardID: UUID) {
        guard records[cardID] != nil else { return }
        records[cardID] = nil
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

    /// Drops records for cards that no longer exist in any set. Otherwise every
    /// card ever deleted keeps its schedule for good.
    func prune(keeping sets: [StudySet]) {
        let kept = ReviewPlan.pruned(records, keeping: sets)
        guard kept.count != records.count else { return }
        records = kept
        save()
    }
}
