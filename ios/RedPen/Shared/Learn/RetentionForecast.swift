import Foundation

/// How much of the deck the student would remember on exam day, and how many
/// reviews it takes to get that to 90%.
///
/// A card's interval stands in for its stability: the number of days after
/// which it is still recalled nine times in ten. Recall then fades on the
/// power curve FSRS uses, R = (1 + t / 9S)^-1, so R is exactly 0.9 when t
/// equals S. A card forgotten again and again is less stable than its
/// interval says, so each lapse takes a little off.
///
/// It is an estimate from one scheduler's intervals, not a measurement, and
/// the screens say so. Foundation only: numbers in, numbers out.
enum RetentionForecast {

    /// The recall aimed for on exam day.
    static let target: Double = 0.9
    /// Each lapse leaves a card this much of its stability.
    static let lapseFactor: Double = 0.85
    /// Never less stable than this, in days (about 15 minutes), so a card
    /// seen once still counts for something within the hour.
    static let floorDays: Double = 0.01
    /// A review simulation never plans more than this many for one card.
    static let maxPlanned = 24

    /// One card's stability in days.
    static func stabilityDays(_ record: ReviewRecord) -> Double {
        let days: Double = record.intervalMin / ExamCap.day
        let lapses: Double = Double(max(0, record.lapses))
        let kept: Double = pow(lapseFactor, lapses)
        return max(floorDays, days * kept)
    }

    /// Recall after `elapsedDays` for a card of stability `stability`.
    static func recall(elapsedDays: Double, stability: Double) -> Double {
        let t: Double = max(0, elapsedDays)
        let s: Double = max(floorDays, stability)
        return 1 / (1 + t / (9 * s))
    }

    /// One card's recall at `date`. Nil for a card never rated: it has not
    /// been learned, so there is nothing yet to forget.
    static func recall(_ record: ReviewRecord?, at date: Date) -> Double? {
        guard let record, record.reviews > 0 else { return nil }
        let elapsed: Double = date.timeIntervalSince(record.ratedAt) / 86_400
        return recall(elapsedDays: elapsed, stability: stabilityDays(record))
    }

    /// The whole forecast.
    struct Forecast: Hashable {
        /// Cards rated at least once, which the percentages are about.
        var studied: Int
        /// Cards never rated.
        var unseen: Int
        /// Average recall of the studied cards now, 0...1.
        var today: Double
        /// Average recall on exam day if nothing more were done.
        var onExamDay: Double
        /// Reviews that would bring every studied card to the target on the
        /// day (unseen cards not included).
        var reviewsNeeded: Int
        /// Whole days left to do them in, at least 1.
        var days: Int
        var perDay: Int { reviewsNeeded == 0 ? 0 : Int((Double(reviewsNeeded) / Double(max(1, days))).rounded(.up)) }
        /// Whether the exam-day recall is already at the target.
        var onCourse: Bool { studied > 0 && onExamDay >= RetentionForecast.target }
    }

    /// The forecast for `cards` against `exam` (nil forecasts for today only,
    /// with no review plan).
    static func forecast(cardIDs: [UUID], records: [UUID: ReviewRecord],
                         now: Date, exam: Date?) -> Forecast {
        let when: Date = (exam.map { $0 > now ? $0 : now }) ?? now
        var studied = 0, unseen = 0, needed = 0
        var sumToday = 0.0, sumExam = 0.0
        for id in cardIDs {
            guard let record = records[id], record.reviews > 0 else {
                unseen += 1
                continue
            }
            studied += 1
            sumToday += recall(record, at: now) ?? 0
            sumExam += recall(record, at: when) ?? 0
            if exam != nil { needed += reviewsToTarget(record, now: now, exam: when) }
        }
        let n: Double = Double(max(1, studied))
        let seconds: Double = when.timeIntervalSince(now)
        let days: Int = max(1, Int((seconds / 86_400).rounded(.up)))
        return Forecast(studied: studied, unseen: unseen,
                        today: studied == 0 ? 0 : sumToday / n,
                        onExamDay: studied == 0 ? 0 : sumExam / n,
                        reviewsNeeded: needed, days: days)
    }

    /// How many reviews one card needs before `exam` for its recall on the
    /// day to reach the target, reviewing it when it falls due (never after
    /// the exam's cap) and assuming each is answered "Good".
    ///
    /// Recall on the day is at least 0.9 exactly when the last review is no
    /// more than one stability before the exam, so it plans reviews until
    /// that holds.
    static func reviewsToTarget(_ record: ReviewRecord, now: Date, exam: Date) -> Int {
        var interval: Double = record.intervalMin
        var stability: Double = stabilityDays(record)
        var last: Date = record.ratedAt
        var due: Date = max(record.due, now)
        var count = 0
        while count < maxPlanned {
            let gap: Double = exam.timeIntervalSince(last) / 86_400
            if gap <= stability { return count }
            // the review, when it falls due - but never later than the day
            // before the exam
            let latest: Date = max(now, exam.addingTimeInterval(-86_400))
            let at: Date = min(due, latest)
            let next: Double = AnkiScheduler.nextInterval(rating: .good, currentIntervalMin: interval)
            // what the review earned is the whole interval; the cap only
            // brings the next sitting forward, it does not weaken the memory
            stability = max(floorDays, next / ExamCap.day)
            interval = ExamCap.capped(next, now: at, exam: exam)
            last = at
            due = at.addingTimeInterval(interval * 60)
            count += 1
        }
        return count
    }

    /// Cards falling due on each of the next `days` days (index 0 is today,
    /// counting everything already overdue), for the forward chart.
    static func dueByDay(cardIDs: [UUID], records: [UUID: ReviewRecord], now: Date,
                         days: Int, calendar: Calendar = .current) -> [Int] {
        guard days > 0 else { return [] }
        var out = Array(repeating: 0, count: days)
        let start: Date = calendar.startOfDay(for: now)
        for id in cardIDs {
            guard let record = records[id] else {
                out[0] += 1
                continue
            }
            let offset: Int = calendar.dateComponents([.day], from: start,
                                                      to: calendar.startOfDay(for: record.due)).day ?? 0
            let slot: Int = max(0, offset)
            if slot < days { out[slot] += 1 }
        }
        return out
    }

    /// "~71%".
    static func percent(_ x: Double) -> String {
        "\(Int((min(1, max(0, x)) * 100).rounded()))%"
    }
}
