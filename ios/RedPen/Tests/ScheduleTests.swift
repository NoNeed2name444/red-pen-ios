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

// Rated ahead of time, a card grows by the time that actually passed, not by
// the whole interval it was given. Easy on Monday, then Easy again each day
// while studying ahead, used to be 4 days, 16, 64, 256: gone for months.
let dayMin: Double = 1440
let monday = now
var ahead4 = ReviewPlan.after(rating: .easy, record: ReviewRecord(due: monday, intervalMin: 0), now: monday)
for day in 1...3 {
    let today = monday.addingTimeInterval(Double(day) * 86_400)
    ahead4 = ReviewPlan.after(rating: .easy, record: ahead4, now: today)
}
let thursday = monday.addingTimeInterval(3 * 86_400)
check("studying ahead every day does not compound the interval",
      ahead4.intervalMin <= 4 * dayMin + 1, "\(ahead4.intervalMin / dayMin) d")
check("so a card seen on Thursday is back within days, not months",
      ahead4.due.timeIntervalSince(thursday) <= 4 * 86_400 + 60,
      "\(ahead4.due.timeIntervalSince(thursday) / 86_400) d")

let earnedMonth = ReviewRecord(due: now.addingTimeInterval(28 * 86_400), intervalMin: 30 * dayMin,
                               reviews: 4, lapses: 0, ratedAt: now.addingTimeInterval(-2 * 86_400))
let earlyGood = ReviewPlan.after(rating: .good, record: earnedMonth, now: now)
check("an early Good never shortens the interval a card had earned",
      earlyGood.intervalMin >= earnedMonth.intervalMin, "\(earlyGood.intervalMin / dayMin) d")
check("and does not multiply it as if the month had passed",
      earlyGood.intervalMin < 30 * dayMin * 2.5, "\(earlyGood.intervalMin / dayMin) d")
let earlyHard = ReviewPlan.after(rating: .hard, record: earnedMonth, now: now)
check("an early Hard brings it closer, by at most 40%",
      earlyHard.intervalMin >= 0.6 * 30 * dayMin - 1 && earlyHard.intervalMin <= 30 * dayMin,
      "\(earlyHard.intervalMin / dayMin) d")
let earlyAgain = ReviewPlan.after(rating: .again, record: earnedMonth, now: now)
check("an early Again is still a lapse", earlyAgain.intervalMin == 1 && earlyAgain.lapses == 1)
let rightOnTime = ReviewPlan.after(rating: .good, record: earnedMonth, now: earnedMonth.due)
check("rated when due, the interval grows as before",
      rightOnTime.intervalMin == 75 * dayMin, "\(rightOnTime.intervalMin / dayMin) d")

// a sitting still moves a card on: Good at 10 minutes, shown again a minute
// later and rated Good, leaves the sitting instead of looping at 10 minutes
let stepped = ReviewPlan.after(rating: .good, record: ReviewRecord(due: now, intervalMin: 0), now: now)
let steppedAgain = ReviewPlan.after(rating: .good, record: stepped, now: now.addingTimeInterval(60))
check("a learning step shown early still moves on", steppedAgain.intervalMin == 25, "\(steppedAgain.intervalMin)")

// the buttons promise what an early rating stores
let promisedEarly = ReviewPlan.previewLabels(for: earnedMonth, now: now, exam: nil)
check("an early review's buttons promise what it will store",
      promisedEarly[.good] == "in " + AnkiScheduler.formatInterval(earlyGood.intervalMin),
      "\(promisedEarly[.good] ?? "-") vs \(AnkiScheduler.formatInterval(earlyGood.intervalMin))")
// and the exam cap still holds an early review back before the paper
let examSoon = now.addingTimeInterval(10 * 86_400)
let cappedEarly = ReviewPlan.after(rating: .easy, record: earnedMonth, now: now, exam: examSoon)
check("the exam cap still applies to an early review",
      cappedEarly.due < examSoon, "\(cappedEarly.due.timeIntervalSince(now) / 86_400) d")

// MARK: no runaway intervals

var runaway = ReviewRecord(due: now, intervalMin: 0)
var clock = now
for _ in 0..<60 {
    runaway = ReviewPlan.after(rating: .easy, record: runaway, now: clock)
    clock = runaway.due
}
check("sixty Easy ratings stop at the ceiling",
      runaway.intervalMin <= AnkiScheduler.maxIntervalMin, "\(runaway.intervalMin)")
check("and the label for it does not crash",
      AnkiScheduler.formatInterval(runaway.intervalMin) == "36500 d", AnkiScheduler.formatInterval(runaway.intervalMin))
check("nor for an interval already stored out of range",
      AnkiScheduler.formatInterval(1e30) == "36500 d" && AnkiScheduler.formatInterval(.infinity) == "36500 d")
check("the buttons for a runaway card do not crash",
      AnkiScheduler.previewLabels(currentIntervalMin: 1e300, exam: nil)[.easy] == "in 36500 d")

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
// a copy of a deck that kept its cards' ids (a sync conflict copy, a file
// imported twice): one card in two decks is two rows, not one identity twice
let copied = Deck(deckName: "Immunology (from another device)", deckCards: cards)
let twice = ReviewPlan.dueAcross([immunology, copied], records: records, now: now)
check("the same card in two decks is two distinct rows",
      Set(twice.map(\.id)).count == twice.count && twice.count == 2, "\(twice.map(\.id))")
var remaining = twice
if let first = twice.first { remaining.removeAll { $0.id == first.id } }
check("and removing one leaves the other", remaining.count == 1)

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
