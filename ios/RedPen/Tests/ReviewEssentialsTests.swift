// The Anki review essentials: daily limits, suspend and bury, undo that
// survives a sync, and the optional FSRS-5 scheduler - plus the report
// outbox and the review-prompt rule, which are decisions of the same kind:
// easy to get subtly wrong, invisible on screen until it matters.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double, _ b: Double, _ tol: Double = 1e-3) -> Bool { abs(a - b) <= tol }

struct Deck: ReviewDeck {
    var deckID = UUID()
    var deckName: String
    var deckCards: [AnkiCard]
}

func card(_ front: String) -> AnkiCard {
    AnkiCard(type: .qa, front: front, bullets: ["answer"])
}

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
// 2023-11-14 22:13:20 UTC
let now = Date(timeIntervalSince1970: 1_700_000_000)
let day: Double = 86_400

// MARK: FSRS-5 itself

check("FSRS: recall is 90% after exactly one stability",
      near(FSRS.retrievability(elapsedDays: 10, stability: 10), 0.9))
check("FSRS: the interval at 90% retention is the stability",
      near(FSRS.intervalDays(stability: 7.5), 7.5, 1e-6))
check("FSRS: a first Good starts at w2 (3.173 days)",
      near(FSRS.initialStability(3), 3.173))
check("FSRS: first difficulty falls from Again to Easy",
      FSRS.initialDifficulty(1) > FSRS.initialDifficulty(3) && FSRS.initialDifficulty(3) > FSRS.initialDifficulty(4))
check("FSRS: a first Good's difficulty is w4 - e^(2 w5) + 1",
      near(FSRS.initialDifficulty(3), 7.1949 - exp(2 * 0.5345) + 1))
let s0 = FSRS.State(stability: 10, difficulty: 5)
let goodOnTime = FSRS.next(s0, grade: 3, elapsedDays: 10)
let easyOnTime = FSRS.next(s0, grade: 4, elapsedDays: 10)
let hardOnTime = FSRS.next(s0, grade: 2, elapsedDays: 10)
let againOnTime = FSRS.next(s0, grade: 1, elapsedDays: 10)
check("FSRS: Good on time grows stability", goodOnTime.stability > 10, "\(goodOnTime.stability)")
check("FSRS: Hard < Good < Easy in stability",
      hardOnTime.stability < goodOnTime.stability && goodOnTime.stability < easyOnTime.stability)
check("FSRS: Again never leaves more stability than the card had",
      againOnTime.stability <= 10, "\(againOnTime.stability)")
check("FSRS: Again makes it harder, Easy easier",
      againOnTime.difficulty > 5 && easyOnTime.difficulty < 5)
check("FSRS: difficulty stays within 1...10",
      (1...10).contains(FSRS.nextDifficulty(9.99, grade: 1)) && (1...10).contains(FSRS.nextDifficulty(1, grade: 4)))
let sameDay = FSRS.next(s0, grade: 3, elapsedDays: 0.01)
check("FSRS: a same-day Good uses the short-term step (x e^(w17 w18))",
      near(sameDay.stability, 10 * exp(0.51655 * 0.6621), 1e-6), "\(sameDay.stability)")
let late = FSRS.next(s0, grade: 3, elapsedDays: 40)
check("FSRS: a Good remembered later earns more than one on time",
      late.stability > goodOnTime.stability)

// MARK: FSRS through the schedule

let fresh = ReviewRecord(due: now, intervalMin: 0)
let plan = ReviewPlan.fsrsPlan(fresh, now: now)
check("FSRS plan: Again is a one-minute step", plan[.again]?.minutes == 1)
check("FSRS plan: a new card's Good is the ten-minute step", plan[.good]?.minutes == 10)
check("FSRS plan: a new card's Easy graduates to about 16 days",
      plan[.easy]?.minutes == 16 * 1440, "\(plan[.easy]?.minutes ?? -1)")
let first = ReviewPlan.after(rating: .good, record: fresh, now: now, exam: nil, scheduler: .fsrs)
check("FSRS rating keeps the memory on the record", first.stability != nil && first.difficulty != nil)
check("FSRS rating marks when the card was introduced", first.introducedAt == now)
let second = ReviewPlan.after(rating: .good, record: first, now: now.addingTimeInterval(600),
                              exam: nil, scheduler: .fsrs)
check("FSRS: Good on the last learning step graduates it", second.intervalMin >= 1440, "\(second.intervalMin)")
let later = now.addingTimeInterval(second.intervalMin * 60)
let reviewPlan = ReviewPlan.fsrsPlan(second, now: later)
let h = reviewPlan[.hard]!.minutes, g = reviewPlan[.good]!.minutes, e = reviewPlan[.easy]!.minutes
check("FSRS plan: Hard < Good < Easy for a review card", h < g && g < e, "\(h) \(g) \(e)")
check("FSRS plan: every review interval is whole days", h.truncatingRemainder(dividingBy: 1440) == 0)
let labels = ReviewPlan.previewLabels(for: second, now: later, exam: nil, scheduler: .fsrs)
let stored = ReviewPlan.after(rating: .good, record: second, now: later, exam: nil, scheduler: .fsrs)
check("FSRS: the Good button promises what is stored",
      labels[.good] == "in " + AnkiScheduler.formatInterval(stored.intervalMin),
      "\(labels[.good] ?? "") vs \(stored.intervalMin)")
let lapsed = ReviewPlan.after(rating: .again, record: stored, now: later, exam: nil, scheduler: .fsrs)
check("FSRS: Again on a review card is a lapse, back in a minute",
      lapsed.lapses == stored.lapses + 1 && lapsed.intervalMin == 1)
let exam = now.addingTimeInterval(5 * day)
let capped = ReviewPlan.after(rating: .easy, record: fresh, now: now, exam: exam, scheduler: .fsrs)
check("FSRS respects the exam cap", capped.due < exam)
let classic = ReviewPlan.after(rating: .good, record: stored, now: stored.due, exam: nil, scheduler: .classic)
check("Classic stays the web app's rule and drops FSRS memory",
      classic.stability == nil && classic.intervalMin == max(10, stored.intervalMin * 2.5))
check("Classic is the default scheduler",
      ReviewSettings.scheduler(UserDefaults(suiteName: "reviewtests.\(UUID().uuidString)")!) == .classic)
let legacy = ReviewRecord(due: now, intervalMin: 4 * 1440, reviews: 3, lapses: 1, ratedAt: now.addingTimeInterval(-4 * day))
let fromClassic = ReviewPlan.fsrsPlan(legacy, now: now)
check("FSRS can take over a Classic card (Good grows from its interval)",
      fromClassic[.good]!.minutes > 4 * 1440, "\(fromClassic[.good]!.minutes)")

// MARK: the study day

let start = ReviewDay.start(of: now, calendar: utc)
check("a study day turns over at 4 am", utc.component(.hour, from: start) == 4)
let early = Date(timeIntervalSince1970: 1_700_020_000) // 03:46 the next day
check("3 am still counts as the day before",
      ReviewDay.start(of: early, calendar: utc) == start)
check("bury lasts until the next day's start",
      ReviewDay.next(after: now, calendar: utc) == start.addingTimeInterval(day))

// MARK: limits

let cards = (0..<10).map { card("c\($0)") }
let deck = Deck(deckName: "Cardio", deckCards: cards)
var records: [UUID: ReviewRecord] = [:]
check("no limits: every due card is in the queue",
      ReviewPlan.dailyQueue(for: cards, records: records, now: now, limits: .unlimited).count == 10)
let limits = ReviewLimits(newPerDay: 3, reviewsPerDay: 2)
check("new cards stop at the day's limit",
      ReviewPlan.dailyQueue(for: cards, records: records, now: now, limits: limits).count == 3)
// two new cards rated today already
for c in cards.prefix(2) {
    records[c.id] = ReviewPlan.after(rating: .easy, record: fresh, now: now.addingTimeInterval(-60), exam: nil)
}
let counted = ReviewPlan.counts(records, now: now, calendar: utc)
check("today's counts read new cards from the schedule", counted.newCards == 2 && counted.reviews == 0,
      "\(counted)")
check("so only one more new card today",
      ReviewPlan.dailyQueue(for: cards, records: records, now: now, limits: limits).count == 1)
// four review cards due, one learning card due
for c in cards[2..<6] {
    records[c.id] = ReviewRecord(due: now.addingTimeInterval(-day), intervalMin: 3 * 1440, reviews: 2,
                                 ratedAt: now.addingTimeInterval(-4 * day))
}
records[cards[6].id] = ReviewRecord(due: now.addingTimeInterval(-60), intervalMin: 10, reviews: 1,
                                    ratedAt: now.addingTimeInterval(-11 * 60))
let q = ReviewPlan.dailyQueue(for: cards, records: records, now: now, limits: limits)
let reviewIDs = Set(cards[2..<6].map(\.id))
check("reviews stop at the day's limit", q.filter { reviewIDs.contains($0.id) }.count == 2)
check("a learning card is never held back by a limit", q.contains { $0.id == cards[6].id })
let across = ReviewPlan.dueToday([deck], records: records, now: now, limits: limits)
check("Due today counts the same limits", across.count == q.count, "\(across.count) vs \(q.count)")
check("the count matches the queue, limits set",
      ReviewPlan.dueCount(for: cards, records: records, now: now, limits: limits) == q.count)
check("the count matches the queue, no limits",
      ReviewPlan.dueCount(for: cards, records: records, now: now, limits: .unlimited)
      == ReviewPlan.dailyQueue(for: cards, records: records, now: now, limits: .unlimited).count)
check("counts handed in are used, not worked out again",
      ReviewPlan.dueCount(for: cards, records: records, now: now, limits: limits,
                          today: ReviewPlan.DayCounts(newCards: 3, reviews: 2)) == 1)
let twoDecks = ReviewPlan.dueCount(for: cards + [card("x1"), card("x2")], records: records, now: now, limits: limits)
check("two decks together share one day's limits", twoDecks == q.count, "\(twoDecks)")

// MARK: suspend and bury

var held = records
held[cards[2].id] = ReviewPlan.suspending(cards[2], true, in: held, now: now)
held[cards[9].id] = ReviewPlan.burying(cards[9], in: held, now: now, calendar: utc)
let unlimited = ReviewPlan.dailyQueue(for: cards, records: held, now: now, limits: .unlimited)
check("a suspended card leaves the queue", !unlimited.contains { $0.id == cards[2].id })
check("a buried new card leaves the queue", !unlimited.contains { $0.id == cards[9].id })
let tomorrow = start.addingTimeInterval(day + 60)
check("a buried card is back the next day",
      ReviewPlan.dailyQueue(for: cards, records: held, now: tomorrow, limits: .unlimited).contains { $0.id == cards[9].id })
check("a suspended card is still out the next day",
      !ReviewPlan.dailyQueue(for: cards, records: held, now: tomorrow, limits: .unlimited).contains { $0.id == cards[2].id })
check("study ahead skips suspended cards only",
      ReviewPlan.studyAhead(cards, records: held, now: now).count == 9)
let back = ReviewPlan.suspending(cards[2], false, in: held, now: now)
check("unsuspending clears the flag", back.suspended == nil && !ReviewPlan.isHeld(back, now: now))
let ratedWhileSuspended = ReviewPlan.after(rating: .good, record: held[cards[2].id]!, now: now, exam: nil)
check("rating a suspended card (study ahead) keeps it suspended", ratedWhileSuspended.suspended == true)

// MARK: old schedules, and the merge

let oldJSON = #"{"due":"2023-11-14T00:00:00Z","intervalMin":1440,"reviews":2,"lapses":0,"ratedAt":"2023-11-13T00:00:00Z"}"#
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let old = try? decoder.decode(ReviewRecord.self, from: Data(oldJSON.utf8))
check("a record written before these fields still decodes",
      old != nil && old?.suspended == nil && old?.stability == nil)
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.sortedKeys]
if let old, let data = try? encoder.encode(old), let text = String(data: data, encoding: .utf8) {
    check("an untouched record encodes without the new keys (no spurious sync)",
          !text.contains("suspended") && !text.contains("changedAt"), text)
}
let c = cards[3]
let rated = ReviewPlan.after(rating: .good, record: records[c.id]!, now: now, exam: nil)
let undone = ReviewPlan.restoring(records[c.id], now: now.addingTimeInterval(5))
let mergedA = ReviewPlan.merging([c.id: undone], [c.id: rated])
let mergedB = ReviewPlan.merging([c.id: rated], [c.id: undone])
check("an undo beats the rating it cancelled, whichever side has it",
      mergedA[c.id] == undone && mergedB[c.id] == undone)
let suspendedThere = ReviewPlan.suspending(c, true, in: [c.id: rated], now: now.addingTimeInterval(30))
check("a suspend on another device wins over an older rating",
      ReviewPlan.merging([c.id: rated], [c.id: suspendedThere])[c.id]?.suspended == true)
let ratedLater = ReviewPlan.after(rating: .good, record: rated, now: now.addingTimeInterval(60), exam: nil)
check("a later rating still wins over an older suspend",
      ReviewPlan.merging([c.id: suspendedThere], [c.id: ratedLater])[c.id]?.ratedAt == ratedLater.ratedAt)
let firstUndo = ReviewPlan.restoring(nil, now: now)
check("undoing a first rating leaves a never-rated card, due now",
      firstUndo.reviews == 0 && firstUndo.due == now && ReviewPlan.stage(firstUndo) == .new)

// MARK: the report outbox

var box = SupportOutbox()
let r1 = PendingSupport(kind: .question, reason: SupportReason.wrongAnswer.rawValue, note: "  key says B  ",
                        itemJSON: "{}", createdAt: now)
box.add(r1, now: now)
check("a report is queued", box.pending.count == 1)
check("the reason leads the note sent", box.pending[0].sentNote == "[Wrong answer] key says B")
box.add(r1, now: now)
check("the same report twice is queued once", box.pending.count == 1)
box.failed(r1.id, now: now)
check("a failed send waits before the next try", box.due(now: now).isEmpty)
check("and is tried again later", box.due(now: now.addingTimeInterval(3600)).count == 1)
box.sent(r1.id)
check("a sent report leaves the outbox", box.pending.isEmpty)
for i in 0..<(SupportOutbox.maxPending + 5) {
    box.add(PendingSupport(kind: .contact, reason: "other", note: "n\(i)", itemJSON: nil, createdAt: now), now: now)
}
check("the outbox never grows past its cap", box.pending.count == SupportOutbox.maxPending)
var stale = SupportOutbox()
stale.add(PendingSupport(kind: .contact, reason: "other", note: "old", itemJSON: nil,
                         createdAt: now.addingTimeInterval(-40 * day)), now: now.addingTimeInterval(-40 * day))
stale.prune(now: now)
check("a month-old unsent message is let go", stale.pending.isEmpty)

// MARK: when to ask for a rating

let fresh7 = ReviewPromptRules.State(asked: false, lastTrouble: nil)
check("a 7-day streak asks", ReviewPromptRules.shouldAsk(.streak(7), state: fresh7, now: now))
check("a 3-day streak does not", !ReviewPromptRules.shouldAsk(.streak(3), state: fresh7, now: now))
check("a first finished mock asks", ReviewPromptRules.shouldAsk(.mockFinished, state: fresh7, now: now))
check("never twice",
      !ReviewPromptRules.shouldAsk(.streak(9), state: .init(asked: true, lastTrouble: nil), now: now))
check("never just after something went wrong",
      !ReviewPromptRules.shouldAsk(.mockFinished, state: .init(asked: false, lastTrouble: now.addingTimeInterval(-60)), now: now))

if failures.isEmpty {
    print("all review essentials checks passed")
} else {
    print("\(failures.count) FAILED")
    exit(1)
}
