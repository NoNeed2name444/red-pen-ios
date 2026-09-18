import Foundation

/// One card's standing in the schedule, as remembered between sessions.
struct ReviewRecord: Codable, Equatable {
    var due: Date
    var intervalMin: Double
    /// How many times it has been rated, and how many of those were "Again".
    /// A card with several lapses is one the student keeps forgetting.
    var reviews: Int = 0
    var lapses: Int = 0
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
    /// drift apart.
    static func after(rating: AnkiRating, record kept: ReviewRecord,
                      now: Date = Date()) -> ReviewRecord {
        let next = AnkiScheduler.nextInterval(rating: rating,
                                              currentIntervalMin: kept.intervalMin)
        return ReviewRecord(due: now.addingTimeInterval(next * 60),
                            intervalMin: next,
                            reviews: kept.reviews + 1,
                            lapses: kept.lapses + (rating == .again ? 1 : 0))
    }

    /// When the next card in a deck comes back.
    static func nextDue(for cards: [AnkiCard], records: [UUID: ReviewRecord]) -> Date? {
        cards.compactMap { records[$0.id]?.due }.min()
    }

    // MARK: across the whole library

    /// One due card, and the deck it belongs to.
    struct Due: Identifiable {
        var setID: UUID
        var setName: String
        var card: AnkiCard
        var due: Date
        var id: UUID { card.id }
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
