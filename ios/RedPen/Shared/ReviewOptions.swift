import Foundation

// The Anki review essentials, as decisions: daily limits, suspend and bury,
// undo, and the optional FSRS scheduler. Foundation only, and stated on
// ReviewPlan's own types, so every rule here runs in a test on a runner.
// ReviewStore remembers what these decide; the screens only ask.

/// Which scheduler rates cards. Classic is the app's own (the web app's
/// port, AnkiScheduler) and stays the default.
enum ReviewScheduler: String, CaseIterable, Identifiable {
    case classic, fsrs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .fsrs: return "FSRS"
        }
    }
}

/// How many cards a day. Zero means no limit, which is the default: a deck
/// generated from tonight's lecture should all be reviewable tonight unless
/// the student says otherwise.
struct ReviewLimits: Equatable {
    var newPerDay: Int
    var reviewsPerDay: Int

    static let unlimited = ReviewLimits(newPerDay: 0, reviewsPerDay: 0)

    var isUnlimited: Bool { newPerDay <= 0 && reviewsPerDay <= 0 }
}

/// Where the review options are kept (Settings > Review).
enum ReviewSettings {
    static let newPerDayKey = "review.newPerDay"
    static let reviewsPerDayKey = "review.reviewsPerDay"
    static let schedulerKey = "review.scheduler"

    static func limits(_ defaults: UserDefaults = .standard) -> ReviewLimits {
        let new: Int = max(0, defaults.integer(forKey: newPerDayKey))
        let reviews: Int = max(0, defaults.integer(forKey: reviewsPerDayKey))
        return ReviewLimits(newPerDay: new, reviewsPerDay: reviews)
    }

    static func scheduler(_ defaults: UserDefaults = .standard) -> ReviewScheduler {
        let raw: String = defaults.string(forKey: schedulerKey) ?? ""
        return ReviewScheduler(rawValue: raw) ?? .classic
    }
}

/// A study day, as Anki counts one: it turns over at 4 in the morning, so a
/// late night's reviews still count for the day they were started.
enum ReviewDay {
    static let rolloverHours: Double = 4

    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        let shift: Double = rolloverHours * 3600
        let day: Date = calendar.startOfDay(for: date.addingTimeInterval(-shift))
        return day.addingTimeInterval(shift)
    }

    /// When "bury until tomorrow" ends: the next day's start.
    static func next(after date: Date, calendar: Calendar = .current) -> Date {
        let today: Date = start(of: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }
}

extension ReviewPlan {

    // MARK: held cards

    /// Suspended, or buried until a time not yet come.
    static func isHeld(_ record: ReviewRecord?, now: Date) -> Bool {
        guard let record else { return false }
        if record.suspended == true { return true }
        if let until = record.buriedUntil, until > now { return true }
        return false
    }

    /// Where a card stands, for the limits: never rated, still on its
    /// learning steps (under a day), or a real review.
    enum Stage { case new, learning, review }

    static func stage(_ record: ReviewRecord?) -> Stage {
        guard let record, record.reviews > 0 else { return .new }
        return record.intervalMin < ExamCap.day ? .learning : .review
    }

    // MARK: today's counts

    struct DayCounts: Equatable {
        var newCards = 0
        var reviews = 0
    }

    /// New cards first rated today, and review cards rated today. Read from
    /// the schedule itself, so a sitting on another device counts once it has
    /// synced, and an undone rating stops counting.
    static func counts(_ records: [UUID: ReviewRecord], now: Date,
                       calendar: Calendar = .current) -> DayCounts {
        let start: Date = ReviewDay.start(of: now, calendar: calendar)
        var out = DayCounts()
        for record in records.values where record.reviews > 0 && record.ratedAt >= start {
            // a schedule from before introducedAt existed: one rating today
            // was its first
            let newToday: Bool = record.introducedAt.map { $0 >= start } ?? (record.reviews == 1)
            if newToday { out.newCards += 1 } else { out.reviews += 1 }
        }
        return out
    }

    /// What is left of today's limits. Learning cards are never limited, as
    /// in Anki: a card half-learned must come back when it is due.
    struct Allowance {
        var newLeft: Int?
        var reviewsLeft: Int?

        init(limits: ReviewLimits, counts: DayCounts) {
            newLeft = limits.newPerDay > 0 ? max(0, limits.newPerDay - counts.newCards) : nil
            reviewsLeft = limits.reviewsPerDay > 0 ? max(0, limits.reviewsPerDay - counts.reviews) : nil
        }

        /// Takes one card of `stage` if the day allows it.
        mutating func take(_ stage: Stage) -> Bool {
            switch stage {
            case .learning:
                return true
            case .new:
                guard let left = newLeft else { return true }
                guard left > 0 else { return false }
                newLeft = left - 1
                return true
            case .review:
                guard let left = reviewsLeft else { return true }
                guard left > 0 else { return false }
                reviewsLeft = left - 1
                return true
            }
        }
    }

    // MARK: queues that respect all of it

    /// One deck's queue for today: due, not held, within the day's limits.
    ///
    /// `today` is the day's counts when the caller already has them; with no
    /// limits set (the default) they are never worked out at all.
    static func dailyQueue(for cards: [AnkiCard], records: [UUID: ReviewRecord],
                           now: Date, limits: ReviewLimits,
                           today: DayCounts? = nil) -> [AnkiQueueItem] {
        var budget: Allowance = Self.allowance(limits, records: records, now: now, today: today)
        var due: [(item: AnkiQueueItem, stage: Stage)] = []
        for card in cards {
            let stored: ReviewRecord? = records[card.id]
            if isHeld(stored, now: now) { continue }
            let kept: ReviewRecord = record(for: card, in: records, now: now)
            guard kept.due <= now else { continue }
            let item = AnkiQueueItem(card: card, due: kept.due, intervalMin: kept.intervalMin)
            due.append((item, stage(stored)))
        }
        due.sort { $0.item.due < $1.item.due }
        var out: [AnkiQueueItem] = []
        for entry in due where budget.take(entry.stage) { out.append(entry.item) }
        return out
    }

    /// How many cards `dailyQueue` would hold, without building or sorting
    /// it: a count needs only how many of each stage are due, since the
    /// limits take from each stage alone. For a library row (once per deck
    /// on every redraw) and the evening reminder (every deck at once, so
    /// the library's limits apply once).
    static func dueCount(for cards: [AnkiCard], records: [UUID: ReviewRecord],
                         now: Date, limits: ReviewLimits,
                         today: DayCounts? = nil) -> Int {
        var learning: Int = 0
        var fresh: Int = 0
        var reviewing: Int = 0
        for card in cards {
            let stored: ReviewRecord? = records[card.id]
            if isHeld(stored, now: now) { continue }
            let kept: ReviewRecord = record(for: card, in: records, now: now)
            guard kept.due <= now else { continue }
            switch stage(stored) {
            case .learning: learning += 1
            case .new: fresh += 1
            case .review: reviewing += 1
            }
        }
        if limits.isUnlimited { return learning + fresh + reviewing }
        let left: Allowance = Self.allowance(limits, records: records, now: now, today: today)
        let newShown: Int = left.newLeft.map { min($0, fresh) } ?? fresh
        let reviewsShown: Int = left.reviewsLeft.map { min($0, reviewing) } ?? reviewing
        return learning + newShown + reviewsShown
    }

    /// What the day allows. With no limits, today's counts are skipped:
    /// working them out walks every record in the schedule.
    static func allowance(_ limits: ReviewLimits, records: [UUID: ReviewRecord],
                          now: Date, today: DayCounts?) -> Allowance {
        if limits.isUnlimited { return Allowance(limits: limits, counts: DayCounts()) }
        let counted: DayCounts = today ?? counts(records, now: now)
        return Allowance(limits: limits, counts: counted)
    }

    /// Everything due across the library today, within the day's limits
    /// (which are the library's, not each deck's), soonest first.
    static func dueToday<D: ReviewDeck>(_ decks: [D], records: [UUID: ReviewRecord],
                                        now: Date, limits: ReviewLimits,
                                        cap: Int = 500, today: DayCounts? = nil) -> [Due] {
        var budget: Allowance = Self.allowance(limits, records: records, now: now, today: today)
        var found: [(due: Due, stage: Stage)] = []
        for deck in decks {
            for card in deck.deckCards {
                let stored: ReviewRecord? = records[card.id]
                if isHeld(stored, now: now) { continue }
                let kept: ReviewRecord = record(for: card, in: records, now: now)
                guard kept.due <= now else { continue }
                let entry = Due(setID: deck.deckID, setName: deck.deckName, card: card, due: kept.due)
                found.append((entry, stage(stored)))
            }
        }
        found.sort { $0.due.due < $1.due.due }
        var out: [Due] = []
        for entry in found {
            guard out.count < cap else { break }
            if budget.take(entry.stage) { out.append(entry.due) }
        }
        return out
    }

    /// Study ahead: the whole deck, except what the student suspended.
    static func studyAhead(_ cards: [AnkiCard], records: [UUID: ReviewRecord],
                           now: Date) -> [AnkiQueueItem] {
        let kept: [AnkiCard] = cards.filter { records[$0.id]?.suspended != true }
        return everything(kept, records: records, now: now)
    }

    // MARK: suspend, bury, undo

    /// The card suspended (or let back in). A card never rated gets a record
    /// to carry it.
    static func suspending(_ card: AnkiCard, _ on: Bool, in records: [UUID: ReviewRecord],
                           now: Date) -> ReviewRecord {
        var out: ReviewRecord = record(for: card, in: records, now: now)
        out.suspended = on ? true : nil
        out.changedAt = now
        return out
    }

    /// The card out of today's queues, back at the next day's start.
    static func burying(_ card: AnkiCard, in records: [UUID: ReviewRecord], now: Date,
                        calendar: Calendar = .current) -> ReviewRecord {
        var out: ReviewRecord = record(for: card, in: records, now: now)
        out.buriedUntil = ReviewDay.next(after: now, calendar: calendar)
        out.changedAt = now
        return out
    }

    /// What undoing a rating writes back: the record from before it, stamped
    /// now so the merge takes the undo over the rating it cancels (which may
    /// already be on the server). A card that had no record gets a fresh,
    /// never-rated one for the same reason - removing it would let the synced
    /// rating come straight back.
    static func restoring(_ previous: ReviewRecord?, now: Date) -> ReviewRecord {
        var out: ReviewRecord = previous ?? ReviewRecord(due: now, intervalMin: 0, ratedAt: now)
        out.changedAt = now
        return out
    }

    // MARK: the scheduler switch

    /// A rating, under the chosen scheduler.
    static func after(rating: AnkiRating, record kept: ReviewRecord, now: Date,
                      exam: Date?, scheduler: ReviewScheduler) -> ReviewRecord {
        switch scheduler {
        case .classic:
            var out: ReviewRecord = after(rating: rating, record: kept, now: now, exam: exam)
            out.stability = nil
            out.difficulty = nil
            return out
        case .fsrs:
            return fsrsAfter(rating: rating, record: kept, now: now, exam: exam)
        }
    }

    /// The four buttons' labels, under the chosen scheduler.
    static func previewLabels(for kept: ReviewRecord, now: Date, exam: Date?,
                              scheduler: ReviewScheduler) -> [AnkiRating: String] {
        guard scheduler == .fsrs else { return previewLabels(for: kept, now: now, exam: exam) }
        let plan: [AnkiRating: FSRSStep] = fsrsPlan(kept, now: now)
        var out: [AnkiRating: String] = [:]
        for rating in AnkiRating.allCases {
            let plain: Double = plan[rating]?.minutes ?? 1
            let capped: Double = ExamCap.capped(plain, now: now, exam: exam)
            out[rating] = "in " + AnkiScheduler.formatInterval(capped)
        }
        return out
    }

    // MARK: FSRS

    /// One rating's outcome under FSRS: the interval and the memory after it.
    struct FSRSStep: Equatable {
        var minutes: Double
        var state: FSRS.State
    }

    static func grade(_ rating: AnkiRating) -> Int {
        switch rating {
        case .again: return 1
        case .hard: return 2
        case .good: return 3
        case .easy: return 4
        }
    }

    /// All four ratings' outcomes at once, so the buttons and the stored
    /// schedule read the same numbers, and Hard < Good < Easy always holds.
    ///
    /// Learning steps are Anki's defaults (1 and 10 minutes): Again comes back
    /// in a minute, a new card's Good in ten, and Good on the last step (or
    /// Easy at any time) graduates it to the interval its stability earns.
    /// The sitting therefore behaves as it does under Classic.
    static func fsrsPlan(_ kept: ReviewRecord, now: Date) -> [AnkiRating: FSRSStep] {
        let seen: Bool = kept.reviews > 0
        let elapsed: Double = seen ? max(0, now.timeIntervalSince(kept.ratedAt)) / 86_400 : 0
        let prior: FSRS.State? = seen ? memory(of: kept) : nil
        let learning: Bool = !seen || kept.intervalMin < ExamCap.day
        let lastStep: Bool = seen && kept.intervalMin >= 10

        var states: [AnkiRating: FSRS.State] = [:]
        for rating in AnkiRating.allCases {
            states[rating] = FSRS.next(prior, grade: grade(rating), elapsedDays: elapsed)
        }
        let hardS: FSRS.State = states[.hard]!
        let goodS: FSRS.State = states[.good]!
        let easyS: FSRS.State = states[.easy]!

        var hard: Double
        var good: Double
        if learning {
            hard = lastStep ? 10 : 6
            good = lastStep ? graduated(goodS) : 10
        } else {
            hard = graduated(hardS)
            good = max(graduated(goodS), hard + ExamCap.day)
        }
        let easyFloor: Double = good >= ExamCap.day ? good + ExamCap.day : ExamCap.day
        let easy: Double = min(AnkiScheduler.maxIntervalMin, max(graduated(easyS), easyFloor))
        hard = min(AnkiScheduler.maxIntervalMin, hard)
        good = min(AnkiScheduler.maxIntervalMin, good)
        return [
            .again: FSRSStep(minutes: 1, state: states[.again]!),
            .hard: FSRSStep(minutes: hard, state: hardS),
            .good: FSRSStep(minutes: good, state: goodS),
            .easy: FSRSStep(minutes: easy, state: easyS),
        ]
    }

    /// The card's FSRS memory, or one estimated from its Classic interval.
    static func memory(of kept: ReviewRecord) -> FSRS.State {
        if let s = kept.stability, let d = kept.difficulty, s > 0 {
            return FSRS.State(stability: s, difficulty: d)
        }
        return FSRS.estimated(intervalDays: kept.intervalMin / ExamCap.day, lapses: kept.lapses)
    }

    /// Whole days, at least one, for recall to fall to 90%.
    static func graduated(_ state: FSRS.State) -> Double {
        let days: Double = FSRS.intervalDays(stability: state.stability)
        let whole: Double = max(1, days.rounded())
        return min(AnkiScheduler.maxIntervalMin, whole * ExamCap.day)
    }

    /// An FSRS rating. The stored interval is the graduated one, so
    /// RetentionForecast (which reads an interval as stability) sees FSRS's
    /// memory without knowing FSRS exists.
    static func fsrsAfter(rating: AnkiRating, record kept: ReviewRecord,
                          now: Date, exam: Date?) -> ReviewRecord {
        let plan: [AnkiRating: FSRSStep] = fsrsPlan(kept, now: now)
        let step: FSRSStep = plan[rating] ?? FSRSStep(minutes: 1, state: memory(of: kept))
        let next: Double = ExamCap.capped(step.minutes, now: now, exam: exam)
        let lapse: Int = rating == .again && kept.reviews > 0 ? 1 : 0
        var out = ReviewRecord(due: now.addingTimeInterval(next * 60),
                               intervalMin: next,
                               reviews: kept.reviews + 1,
                               lapses: kept.lapses + lapse,
                               ratedAt: now)
        out.stability = step.state.stability
        out.difficulty = step.state.difficulty
        out.introducedAt = kept.reviews == 0 ? now : kept.introducedAt
        out.suspended = kept.suspended
        return out
    }
}

/// Settings > Review: the Sure / Maybe / Guess row under a question's
/// options. On unless turned off; the answers feed Progress's calibration.
enum ConfidenceSetting {
    static let key = "quiz.askConfidence"
}
