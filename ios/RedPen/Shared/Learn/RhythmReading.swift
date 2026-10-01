import Foundation

/// How regularly the studying has gone lately, read the way a monitor reads a
/// rhythm strip: the last fourteen days, each one a beat (something studied
/// that day) or a flat line (a day off), and a word for the pattern.
///
/// The words are a ward's, never a verdict: a steady habit is "regular", an
/// uneven one "irregular" (sinus arrhythmia is harmless), a week with nothing
/// in it "resting", and before the first day of study there is "no trace
/// yet". None of them is red; none of them scolds.
///
/// - Regular: something on at least 70% of the days the strip covers, and no
///   more than two days off in a row.
/// - Resting: nothing in the last seven days of the strip.
/// - Irregular: anything else with a beat in the last week.
///
/// The strip covers the days since studying began, at most fourteen. A day
/// with nothing yet today does not count against the strip until it is over,
/// so the reading never sags at breakfast (StudyLog.streak does the same).
///
/// Days are StudyLog's: `yyyy-MM-dd` in the phone's own calendar, a count per
/// day. Foundation only, so the reading is tested on Linux (BedPlanTests).
enum RhythmReading {

    /// Days on the strip.
    static let window = 14
    /// Share of days with a beat for a regular rhythm.
    static let regularShare = 0.7
    /// The longest run of days off a regular rhythm allows.
    static let regularGap = 2
    /// Days with no beat, at the end of the strip, that read as resting.
    static let restingDays = 7

    enum Rhythm: String, Hashable {
        case regular, irregular, resting, noTrace
    }

    struct Reading: Hashable {
        var rhythm: Rhythm
        /// The strip, oldest day first, `window` long: true where something
        /// was studied.
        var beats: [Bool]
        /// Days with a beat among the days the strip counts.
        var activeDays: Int
        /// Days the strip counts: from the first day ever studied, at most
        /// `window`.
        var span: Int

        /// After "Study rhythm ·" on the monitor, in the source's own case:
        /// "Sinus · regular".
        var words: String {
            switch rhythm {
            case .regular: return "Sinus \u{00B7} regular"
            case .irregular: return "Sinus \u{00B7} irregular"
            case .resting: return "Sinus \u{00B7} resting"
            case .noTrace: return "No trace yet"
            }
        }

        /// One plain line about the strip.
        var line: String {
            switch rhythm {
            case .regular, .irregular:
                let days: String = span == 1 ? "day" : "\(span) days"
                return "Studied \(activeDays) of the last \(days)."
            case .resting:
                return "Nothing in the last \(RhythmReading.restingDays) days. Pick it up whenever you\u{2019}re ready."
            case .noTrace:
                return "Study on a few days and your rhythm shows here."
            }
        }

        /// What VoiceOver reads for the strip.
        var spoken: String {
            let word: String
            switch rhythm {
            case .regular: word = "regular"
            case .irregular: word = "irregular"
            case .resting: word = "resting"
            case .noTrace: word = "no trace yet"
            }
            return "Study rhythm, \(word). " + line
        }
    }

    /// StudyLog's key for a day: `yyyy-MM-dd` in the given calendar.
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let parts: DateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func read(days: [String: Int], now: Date, calendar: Calendar = .current) -> Reading {
        let active: Set<String> = Set(days.filter { $0.value > 0 }.map { $0.key })
        let today: Date = calendar.startOfDay(for: now)
        // a day with nothing in it yet is not over: the strip ends yesterday
        var end: Date = today
        if !active.contains(key(today, calendar: calendar)),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            end = yesterday
        }
        var keys: [String] = []
        for back in stride(from: window - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: end) else { continue }
            keys.append(key(day, calendar: calendar))
        }
        let beats: [Bool] = keys.map { active.contains($0) }
        // the keys sort as dates do, so the first day ever studied is the least
        guard let first = active.min() else {
            return Reading(rhythm: .noTrace, beats: beats, activeDays: 0, span: 0)
        }
        var counted: [Bool] = []
        for (index, day) in keys.enumerated() where day >= first {
            counted.append(beats[index])
        }
        let activeDays: Int = counted.filter { $0 }.count
        let span: Int = counted.count
        let trailing: Int = offAtEnd(beats)
        let rhythm: Rhythm
        if activeDays == 0 || trailing >= restingDays {
            rhythm = .resting
        } else if Double(activeDays) >= regularShare * Double(span) && longestOff(counted) <= regularGap {
            rhythm = .regular
        } else {
            rhythm = .irregular
        }
        return Reading(rhythm: rhythm, beats: beats, activeDays: activeDays, span: span)
    }

    /// Days off at the end of the strip.
    static func offAtEnd(_ beats: [Bool]) -> Int {
        var run = 0
        for beat in beats.reversed() {
            if beat { break }
            run += 1
        }
        return run
    }

    /// The longest run of days off anywhere on the strip.
    static func longestOff(_ beats: [Bool]) -> Int {
        var longest = 0
        var run = 0
        for beat in beats {
            run = beat ? 0 : run + 1
            longest = max(longest, run)
        }
        return longest
    }
}
