import Foundation

/// One card's standing in the schedule, as remembered between sessions.
struct ReviewRecord: Codable, Equatable {
    var due: Date
    var intervalMin: Double
    /// How many times it has been rated, and how many of those were "Again".
    /// A card with several lapses is one the student keeps forgetting.
    var reviews: Int = 0
    var lapses: Int = 0
    /// When this rating was actually made.
    ///
    /// Here for sync. Two phones reviewing two different decks must not have
    /// one phone's afternoon overwrite the other's: the schedule is merged card
    /// by card, and this is what says which rating of a given card is the
    /// later one. Without it a whole day of reviews can vanish silently, which
    /// is the worst way for a study app to fail.
    var ratedAt: Date = Date()
}

/// A deck, as the schedule needs to see one.
///
/// StudySet conforms to this, but the schedule is stated in terms of the
/// protocol so it can be compiled and run without the rest of the app - a
/// StudySet reaches through five other types and two of them need UIKit, which
/// would make this untestable on a runner. Only decks of cards have a schedule;
/// everything else answers with no cards.
protocol ReviewDeck {
    var deckID: UUID { get }
    var deckName: String { get }
    var deckCards: [AnkiCard] { get }
}

/// When cards come back.
///
/// Review used to be seeded from scratch every time a deck was opened - every
/// card due now, interval zero. Rating a card "Easy, in 4 days" held only until
/// the screen closed. That was a faithful port of the web app, where a session
/// was one browser tab and it did not matter; in something opened daily for a
/// term it means the spacing in spaced repetition never happened.
enum ReviewPlan {

    /// A card nobody has rated is due immediately, which is what makes a
    /// freshly generated deck reviewable the moment it exists.
    static func record(for card: AnkiCard, in records: [UUID: ReviewRecord],
                       now: Date = Date()) -> ReviewRecord {
        records[card.id] ?? ReviewRecord(due: now, intervalMin: 0)
    }

    static func isDue(_ card: AnkiCard, in records: [UUID: ReviewRecord],
                      now: Date = Date()) -> Bool {
        record(for: card, in: records, now: now).due <= now
    }

    /// One deck's queue: what is due, soonest first.
    ///
    /// Cards not yet due are left out rather than shown anyway - otherwise
    /// finishing a deck and reopening it hands back the same cards, which is
    /// the behaviour being fixed.
    static func queue(for cards: [AnkiCard], records: [UUID: ReviewRecord],
                      now: Date = Date()) -> [AnkiQueueItem] {
        cards.compactMap { card -> AnkiQueueItem? in
            let kept = record(for: card, in: records, now: now)
            guard kept.due <= now else { return nil }
            return AnkiQueueItem(card: card, due: kept.due, intervalMin: kept.intervalMin)
        }.sorted { $0.due < $1.due }
    }

    /// Everything in the deck regardless of when it is due, for a student who
    /// wants to go through it anyway. Studying ahead must not move the real
    /// schedule backwards, so each card keeps the interval it has earned.
    static func everything(_ cards: [AnkiCard], records: [UUID: ReviewRecord],
                           now: Date = Date()) -> [AnkiQueueItem] {
        cards.map { card in
            let kept = record(for: card, in: records, now: now)
            return AnkiQueueItem(card: card, due: min(kept.due, now),
                                 intervalMin: kept.intervalMin)
        }
    }

    /// What a rating leaves behind. The interval comes from AnkiScheduler, so
    /// the buttons' promised "in N days" and what is actually stored cannot
    /// drift apart (previewLabels reads the same `earned`).
    ///
    /// With an exam date, no interval runs past the exam: a card that would
    /// next come back after the paper comes back a day or two before it
    /// instead (ExamCap), so everything is seen once more while it counts.
    static func after(rating: AnkiRating, record kept: ReviewRecord,
                      now: Date = Date(), exam: Date? = nil) -> ReviewRecord {
        let plain = earned(rating: rating, record: kept, now: now)
        let next = ExamCap.capped(plain, now: now, exam: exam)
        return ReviewRecord(due: now.addingTimeInterval(next * 60),
                            intervalMin: next,
                            reviews: kept.reviews + 1,
                            lapses: kept.lapses + (rating == .again ? 1 : 0),
                            ratedAt: now)
    }

    /// The interval a rating earns, before any exam cap.
    ///
    /// On time, AnkiScheduler's growth on the interval the card had. Early -
    /// studying ahead, a card rated before it was due - the growth is on the
    /// time that has ACTUALLY passed, as Anki does for early reviews. Grown on
    /// the whole interval instead, a card rated Easy on Monday (4 days) and
    /// again each day it was studied ahead came back in 16 days, then 64,
    /// then 256: seen on Thursday before the exam, gone for eight months.
    /// Good and Easy never shorten what the card had earned; Hard can, by
    /// at most 40%, as Anki's early Hard does. Again is a lapse whenever it
    /// comes. Learning steps (under a day) are left as they are, so a sitting
    /// still moves a card on when it is shown again before its minutes are up.
    static func earned(rating: AnkiRating, record kept: ReviewRecord, now: Date) -> Double {
        let plain: Double = AnkiScheduler.nextInterval(rating: rating, currentIntervalMin: kept.intervalMin)
        let remaining: Double = kept.due.timeIntervalSince(now) / 60
        guard rating != .again, remaining > 0, kept.intervalMin >= ExamCap.day else { return plain }
        let elapsed: Double = max(0, kept.intervalMin - remaining)
        let grown: Double = AnkiScheduler.nextInterval(rating: rating, currentIntervalMin: elapsed)
        let floor: Double = rating == .hard ? kept.intervalMin * 0.6 : kept.intervalMin
        return min(AnkiScheduler.maxIntervalMin, max(grown, floor))
    }

    /// The four buttons' "in N min / hr / d" for a card as it stands - the
    /// same `earned` and exam cap `after` stores, so an early review's
    /// buttons promise what it will actually get.
    static func previewLabels(for kept: ReviewRecord, now: Date = Date(),
                              exam: Date? = ExamCap.storedDate()) -> [AnkiRating: String] {
        var out: [AnkiRating: String] = [:]
        for rating in AnkiRating.allCases {
            let plain: Double = earned(rating: rating, record: kept, now: now)
            out[rating] = "in " + AnkiScheduler.formatInterval(ExamCap.capped(plain, now: now, exam: exam))
        }
        return out
    }

    /// When the next card in a deck comes back.
    static func nextDue(for cards: [AnkiCard], records: [UUID: ReviewRecord]) -> Date? {
        cards.compactMap { records[$0.id]?.due }.min()
    }

    // MARK: across the whole library

    /// One due card, and the deck it belongs to.
    ///
    /// Identified by deck AND card: a set copied with its cards' ids (a sync
    /// conflict copy, a re-imported file) puts the same card id in two decks,
    /// and an id of the card alone gave a list two rows with one identity and
    /// made removing one remove both.
    struct Due: Identifiable {
        var setID: UUID
        var setName: String
        var card: AnkiCard
        var due: Date
        var id: String { setID.uuidString + "/" + card.id.uuidString }
    }

    /// Everything due right now, from every deck, soonest first.
    ///
    /// Twenty lectures means twenty decks, and nobody remembers which of them
    /// has cards waiting. This is the question actually being asked: what do I
    /// owe today?
    static func dueAcross<D: ReviewDeck>(_ decks: [D], records: [UUID: ReviewRecord],
                                         now: Date = Date(), limit: Int = 500) -> [Due] {
        var found: [Due] = []
        for deck in decks {
            for card in deck.deckCards {
                let kept = record(for: card, in: records, now: now)
                guard kept.due <= now else { continue }
                found.append(Due(setID: deck.deckID, setName: deck.deckName,
                                 card: card, due: kept.due))
            }
        }
        return Array(found.sorted { $0.due < $1.due }.prefix(limit))
    }

    /// Merging two versions of a deck's schedule, card by card.
    ///
    /// Never last-write-wins. A phone that reviewed twenty cards this morning
    /// and a laptop that reviewed five different ones this afternoon must end
    /// up with all twenty-five, not the laptop's five. For a card both of them
    /// rated, the later rating is the truer one - it is what the student most
    /// recently told the app about their own memory.
    static func merging(_ mine: [UUID: ReviewRecord],
                        _ theirs: [UUID: ReviewRecord]) -> [UUID: ReviewRecord] {
        var out = mine
        for (id, record) in theirs {
            guard let existing = out[id] else {
                out[id] = record
                continue
            }
            if record.ratedAt > existing.ratedAt { out[id] = record }
        }
        return out
    }

    /// Records for cards that no longer exist anywhere are dropped.
    ///
    /// Deleting a card would otherwise leave its schedule behind for ever, and
    /// a card deleted and regenerated gets a new id anyway, so nothing is lost
    /// by forgetting.
    static func pruned<D: ReviewDeck>(_ records: [UUID: ReviewRecord],
                                      keeping decks: [D]) -> [UUID: ReviewRecord] {
        var live = Set<UUID>()
        for deck in decks { for card in deck.deckCards { live.insert(card.id) } }
        return records.filter { live.contains($0.key) }
    }
}

/// Keeps every interval inside the run-up to the exam.
///
/// Spacing is about remembering on the day that matters. An interval that
/// ends after the exam is a review the student never gets before the paper,
/// so a card due after it is brought forward to land one to three days
/// before - close enough to count, far enough to leave the last day calm.
///
/// Foundation only, and here beside ReviewPlan so the schedule and the
/// rating buttons' "in N d" read the same cap.
enum ExamCap {
    /// Where the exam date is kept: the same key as ExamTrack.dateKey
    /// (seconds since 1970, 0 for none). Spelled out so the schedule compiles
    /// without ExamTrack; a test checks the two stay equal.
    static let dateKey = "exam.date"

    /// The exam date the student set, or nil.
    static func storedDate(_ defaults: UserDefaults = .standard) -> Date? {
        let stamp = defaults.double(forKey: dateKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Minutes in a day.
    static let day: Double = 1440

    /// `minutes` unless it would carry the card past the exam; then the
    /// interval that brings it back before it. Short learning steps (under a
    /// day) are never touched, and nothing changes once the exam has passed.
    static func capped(_ minutes: Double, now: Date, exam: Date?) -> Double {
        guard let exam else { return minutes }
        let untilExam: Double = exam.timeIntervalSince(now) / 60
        guard untilExam > 0, minutes >= day else { return minutes }
        // lands at least a day before the exam already: fine as it is
        guard minutes > untilExam - day else { return minutes }
        // back two days before, or halfway there when the exam is closer
        let lead: Double = min(2 * day, untilExam / 2)
        let fits: Double = untilExam - lead
        return max(10, min(minutes, fits))
    }
}
