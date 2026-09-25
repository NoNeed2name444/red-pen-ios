import Foundation

/// The streak's rules, apart from where the days are kept (StudyLog), so
/// the Linux tests can run them.
///
/// A day counts when anything was studied on it - a card, a question, an
/// OSCE step - or a ward round's clock ran on it. A missed day does not end
/// the streak if it is the week's one free rest day: a single missed day
/// between two days of study (or before today, while today is still young)
/// is covered as long as no other rest day was used in the 7 days before
/// it. Two missed days in a row always end it, and use no rest day - one
/// that saved nothing would only block the next.
///
/// Rest days are not stored: they fall out of the days themselves, worked
/// out from the oldest day forward, so a restored backup or another device's
/// days give the same answer everywhere. There is nothing to buy.
enum StudyStreak {
    struct Summary: Equatable {
        /// Days studied in the current run - rest days keep it going but do
        /// not add to it.
        var streak: Int
        /// The missed days covered as rest days, keyed like StudyLog.
        var restDays: Set<String>
        /// Whether a missed day now would be covered.
        var restReady: Bool

        static let empty = Summary(streak: 0, restDays: [], restReady: true)
    }

    /// How far apart two rest days must be, in days.
    static let restEvery: Int = 7

    /// The streak as of `today`, from the keys of the days anything was done.
    static func summary(active: Set<String>, today: Date, calendar: Calendar) -> Summary {
        let todayKey: String = key(for: today, calendar: calendar)
        guard let todayNumber = dayNumber(todayKey, calendar: calendar) else { return .empty }
        var studied: Set<Int> = []
        for day in active {
            if let number = dayNumber(day, calendar: calendar), number <= todayNumber { studied.insert(number) }
        }
        let result = run(studied: studied, today: todayNumber)
        var keys: Set<String> = []
        for number in result.rests {
            if let date = date(ofDay: number, calendar: calendar) { keys.insert(key(for: date, calendar: calendar)) }
        }
        return Summary(streak: result.streak, restDays: keys, restReady: result.restReady)
    }

    /// The rule itself, on plain day numbers: `studied` are the days with
    /// something done, `today` is today's number.
    static func run(studied: Set<Int>, today: Int) -> (streak: Int, rests: [Int], restReady: Bool) {
        guard let first = studied.min() else { return (0, [], true) }
        var streak: Int = 0
        var lastRest: Int?
        var rests: [Int] = []
        var day: Int = first
        while day < today {
            if studied.contains(day) {
                streak += 1
            } else if streak > 0 {
                // only a gap of one day that the student came back after (or
                // that today can still close) is worth a rest day
                let next: Int = day + 1
                let bridged: Bool = studied.contains(next) || next == today
                let allowed: Bool = lastRest.map { day - $0 >= restEvery } ?? true
                if bridged && allowed {
                    lastRest = day
                    rests.append(day)
                } else {
                    streak = 0
                }
            }
            day += 1
        }
        if studied.contains(today) { streak += 1 }
        let ready: Bool = lastRest.map { today - $0 >= restEvery } ?? true
        return (streak, rests, ready)
    }

    // MARK: days

    /// `yyyy-MM-dd` in the phone's own calendar and time zone (StudyLog's
    /// key): a day is the student's day, not UTC's.
    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A day key as a count of days, so days can be stepped through with
    /// plain arithmetic. Noon of the day, in its own time zone offset, so a
    /// change to or from summer time never makes two days one.
    static func dayNumber(_ key: String, calendar: Calendar) -> Int? {
        let parts: [Int] = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let wanted = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let noon = calendar.date(from: wanted) else { return nil }
        let offset: Int = calendar.timeZone.secondsFromGMT(for: noon)
        let local: Double = noon.timeIntervalSinceReferenceDate + Double(offset)
        return Int((local / 86_400).rounded(.down))
    }

    /// The noon of a day number, for turning it back into a key.
    static func date(ofDay number: Int, calendar: Calendar) -> Date? {
        let guess = Date(timeIntervalSinceReferenceDate: Double(number) * 86_400 + 43_200)
        let offset: Int = calendar.timeZone.secondsFromGMT(for: guess)
        return guess.addingTimeInterval(Double(-offset))
    }
}

/// Today against the daily goal: "32 / 50 today".
struct GoalProgress: Equatable {
    var done: Int
    var goal: Int

    /// How far round the ring is, 0 to 1.
    var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(max(0, done)) / Double(goal))
    }

    var met: Bool { goal > 0 && done >= goal }

    var label: String { "\(done) / \(goal) today" }
}
