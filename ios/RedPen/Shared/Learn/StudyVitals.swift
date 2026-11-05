import Foundation

/// The study rhythm and the streak, read from one set of days, so the two
/// never disagree: Vitals once said "Studied 10 of the last 10 days" beside
/// "No streak yet", the rhythm counted from the study log with the dated
/// answers and the streak from the study log alone (T0211 A4). Android
/// reads both from the same days too (VitalsNumbers, HomeRound.studyDays).
///
/// `days` are StudyLog's keys (`yyyy-MM-dd`, the phone's calendar) with a
/// count each, as RhythmReading.merged makes them. `minutes` are a ward
/// round's focus minutes by day: a day with minutes and nothing else counts
/// as one day studied, as it does for StudyLog's streak and Android's
/// studyDays. Both readings let a day with nothing yet today stand until it
/// is over. Foundation only, so the agreement is tested on Linux
/// (StudyVitalsTests).
enum StudyVitals {
    struct Reading: Equatable {
        /// The strip of the last fourteen days and its word.
        var rhythm: RhythmReading.Reading
        /// The streak, its rest days and whether a rest day is ready.
        var streak: StudyStreak.Summary
    }

    /// The days both readings take: `days`, with each day of minutes and no
    /// count as one.
    static func studied(days: [String: Int], minutes: [String: Int]) -> [String: Int] {
        var out: [String: Int] = days
        for (day, count) in minutes where count > 0 && (out[day] ?? 0) <= 0 { out[day] = 1 }
        return out
    }

    static func read(days: [String: Int], minutes: [String: Int] = [:], now: Date,
                     calendar: Calendar = .current) -> Reading {
        let all: [String: Int] = studied(days: days, minutes: minutes)
        let active: Set<String> = Set(all.filter { $0.value > 0 }.map { $0.key })
        return Reading(rhythm: RhythmReading.read(days: all, now: now, calendar: calendar),
                       streak: StudyStreak.summary(active: active, today: now, calendar: calendar))
    }
}
