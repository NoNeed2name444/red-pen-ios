// Whether a card actually stays away once you have said you know it.
//
// This is the behaviour that was missing entirely: ratings held until the
// screen closed and then every card was due again. Nothing about that was
// visible on screen, which is exactly why it needs a test.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

struct Deck: ReviewDeck {
    var deckID = UUID()
    var deckName: String
    var deckCards: [AnkiCard]
}

func card(_ front: String) -> AnkiCard {
    AnkiCard(type: .qa, front: front, bullets: ["answer"])
}

let now = Date(timeIntervalSince1970: 1_700_000_000)
let lupus = card("malar rash")
let renal = card("renal artery")
let cards = [lupus, renal]

// MARK: a deck nobody has touched

check("a brand new card is due at once",
      ReviewPlan.isDue(lupus, in: [:], now: now))
check("so a freshly generated deck is reviewable immediately",
      ReviewPlan.queue(for: cards, records: [:], now: now).count == 2)

// MARK: after a rating

var records: [UUID: ReviewRecord] = [:]
records[lupus.id] = ReviewPlan.after(rating: .easy,
                                     record: ReviewPlan.record(for: lupus, in: [:], now: now),
                                     now: now)

check("easy puts a card days away",
      records[lupus.id]!.intervalMin >= 4 * 24 * 60,
      "\(records[lupus.id]!.intervalMin)")
check("and it is not due an hour later",
      !ReviewPlan.isDue(lupus, in: records, now: now.addingTimeInterval(3600)))
// the whole point: this is what a restart looks like
check("nor the next day, which is what reopening the app used to undo",
      !ReviewPlan.isDue(lupus, in: records, now: now.addingTimeInterval(86_400)))
check("and it IS due once the interval is up",
      ReviewPlan.isDue(lupus, in: records, now: now.addingTimeInterval(5 * 86_400)))
check("the card nobody rated is still waiting",
      ReviewPlan.isDue(renal, in: records, now: now))

let queue = ReviewPlan.queue(for: cards, records: records, now: now)
check("a queue holds only what is due", queue.count == 1, "\(queue.count)")
check("and it is the right card", queue.first?.card.id == renal.id)

// MARK: again, and the counters

let lapsed = ReviewPlan.after(rating: .again, record: records[lupus.id]!, now: now)
check("again brings it straight back", lapsed.intervalMin == 1, "\(lapsed.intervalMin)")
check("and is counted as a lapse", lapsed.lapses == 1)
check("a rating is counted either way", lapsed.reviews == 2, "\(lapsed.reviews)")
let again = ReviewPlan.after(rating: .good, record: lapsed, now: now)
check("a card you get right is not a lapse", again.lapses == 1)

// MARK: studying ahead

let ahead = ReviewPlan.everything(cards, records: records, now: now)
check("studying ahead offers the whole deck", ahead.count == 2)
// the earned interval has to travel with the card, or studying ahead quietly
// resets everything it touches
check("and a card keeps the interval it earned",
      ahead.first { $0.card.id == lupus.id }?.intervalMin ?? 0 >= 4 * 24 * 60,
      "\(ahead.first { $0.card.id == lupus.id }?.intervalMin ?? -1)")

// MARK: the whole library at once

let anatomy = Deck(deckName: "Anatomy", deckCards: [card("femoral triangle")])
let immunology = Deck(deckName: "Immunology", deckCards: cards)
let everything = ReviewPlan.dueAcross([anatomy, immunology], records: records, now: now)
check("the day's queue spans every deck", everything.count == 2, "\(everything.count)")
check("and each card remembers which deck it came from",
      Set(everything.map(\.setName)) == ["Anatomy", "Immunology"],
      "\(everything.map(\.setName))")
check("a deck with nothing due contributes nothing",
      ReviewPlan.dueAcross([Deck(deckName: "Done", deckCards: [lupus])],
                           records: records, now: now).isEmpty)
check("an empty library is not an error",
      ReviewPlan.dueAcross([Deck](), records: records, now: now).isEmpty)

// MARK: forgetting

let pruned = ReviewPlan.pruned(records, keeping: [immunology])
check("a card still in a deck keeps its place", pruned[lupus.id] != nil)
let orphaned = ReviewPlan.pruned(records, keeping: [anatomy])
check("a deleted card's schedule is dropped", orphaned.isEmpty, "\(orphaned.count)")

// MARK: what the buttons promise is what gets stored

for rating in AnkiRating.allCases {
    let start = ReviewRecord(due: now, intervalMin: 30)
    let after = ReviewPlan.after(rating: rating, record: start, now: now)
    let promised = AnkiScheduler.nextInterval(rating: rating, currentIntervalMin: 30)
    check("\(rating.rawValue) stores the interval its button promised",
          after.intervalMin == promised, "\(after.intervalMin) vs \(promised)")
    check("\(rating.rawValue) sets the due date to match the interval",
          abs(after.due.timeIntervalSince(now) - promised * 60) < 0.001)
}

// MARK: two devices, one schedule

// the failure this prevents: a morning's reviews on the phone and an
// afternoon's on the laptop, and last-write-wins throws one of them away
// without saying anything
let morning: [UUID: ReviewRecord] = [
    lupus.id: ReviewRecord(due: now.addingTimeInterval(3600), intervalMin: 60,
                           reviews: 1, lapses: 0, ratedAt: now),
]
let afternoon: [UUID: ReviewRecord] = [
    renal.id: ReviewRecord(due: now.addingTimeInterval(7200), intervalMin: 120,
                           reviews: 1, lapses: 0, ratedAt: now.addingTimeInterval(3600)),
]
let both = ReviewPlan.merging(morning, afternoon)
check("both sittings survive a merge", both.count == 2, "\(both.count)")

// for a card they both rated, the later rating is what the student most
// recently said about their own memory
let laterSame: [UUID: ReviewRecord] = [
    lupus.id: ReviewRecord(due: now.addingTimeInterval(86_400), intervalMin: 1440,
                           reviews: 2, lapses: 0, ratedAt: now.addingTimeInterval(600)),
]
let settled = ReviewPlan.merging(morning, laterSame)
check("the later rating of the same card wins",
      settled[lupus.id]?.intervalMin == 1440, "\(settled[lupus.id]?.intervalMin ?? -1)")
check("and an older one does not overwrite a newer",
      ReviewPlan.merging(laterSame, morning)[lupus.id]?.intervalMin == 1440)
check("merging with nothing changes nothing",
      ReviewPlan.merging(morning, [:]) == morning)

print(failures.isEmpty ? "\nALL SCHEDULE TESTS PASS"
                       : "\n\(failures.count) SCHEDULE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
