import Foundation
import Combine

/// How much was studied on each day, and the streak that makes of it.
///
/// One number a day: every question checked, every card rated and every OSCE
/// step graded adds one. It is deliberately cruder than the schedule or the
/// answer history - it is not there to judge the work, only to show that some
/// happened, because "five days in a row" is what gets somebody to open the
/// app on the sixth.
///
/// Kept in UserDefaults rather than the library file: it is small, it is about
/// this device's habits rather than the material, and writing the whole
/// library out again for every tap would be a heavy way to count to one.
@MainActor
final class StudyLog: ObservableObject {
    static let shared = StudyLog()

    /// Where the counts live, as `["2026-09-24": 32]`.
    static let storageKey = "study.log"

    /// Where the ward round's minutes live, keyed the same way.
    static let minutesKey = "study.minutes"

    /// Answers per day, keyed by the local calendar date.
    @Published private(set) var days: [String: Int] = [:]

    /// Minutes of ward round focus per day (WardRoundClock). A day with
    /// only these in it still counts for the streak.
    @Published private(set) var minutes: [String: Int] = [:]

    /// Every count as it is recorded, for a ward round to add to its own.
    let recorded = PassthroughSubject<Int, Never>()

    private let defaults: UserDefaults

    /// The streak and its rest days, worked out once per change and per day
    /// rather than on every redraw of the Today card.
    private var summaryCache: (day: String, version: Int, value: StudyStreak.Summary)?
    private var version: Int = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        days = defaults.dictionary(forKey: Self.storageKey) as? [String: Int] ?? [:]
        minutes = defaults.dictionary(forKey: Self.minutesKey) as? [String: Int] ?? [:]
    }

    /// Counts one piece of study against today.
    func record(_ count: Int = 1) {
        guard count > 0 else { return }
        let key = Self.key(for: Date())
        days[key, default: 0] += count
        prune()
        version += 1
        defaults.set(days, forKey: Self.storageKey)
        recorded.send(count)
    }

    /// Minutes of ward round focus, against the day they ended on.
    func recordMinutes(_ count: Int, on date: Date = Date()) {
        guard count > 0 else { return }
        minutes[Self.key(for: date), default: 0] += count
        if minutes.count > 730 {
            let keep = Set(minutes.keys.sorted().suffix(730))
            minutes = minutes.filter { keep.contains($0.key) }
        }
        version += 1
        defaults.set(minutes, forKey: Self.minutesKey)
    }

    /// Days from a backup joined to this log: the larger count for each day,
    /// so restoring never shortens a streak.
    func merge(_ other: [String: Int]) {
        var joined = days
        for (day, count) in other where count > (joined[day] ?? 0) { joined[day] = count }
        guard joined != days else { return }
        days = joined
        prune()
        version += 1
        defaults.set(days, forKey: Self.storageKey)
    }

    /// How much has been done today.
    var today: Int { days[Self.key(for: Date())] ?? 0 }

    /// Days in a row with something done, ending today - or ending yesterday
    /// when nothing has been done yet today, so a streak does not read as
    /// broken at breakfast before the day's first card. A missed day can be
    /// the week's free rest day (StudyStreak), which keeps the run going.
    var streak: Int { summary.streak }

    /// Missed days that were covered as rest days, for the moon on the
    /// study calendar.
    var restDaysUsed: Set<String> { summary.restDays }

    /// Whether a day off now would be covered.
    var restDayReady: Bool { summary.restReady }

    /// Whether today already counts for the streak: something studied, or a
    /// ward round's minutes.
    var studiedToday: Bool {
        let key: String = Self.key(for: Date())
        return (days[key] ?? 0) > 0 || (minutes[key] ?? 0) > 0
    }

    private var summary: StudyStreak.Summary {
        let now = Date()
        let day: String = Self.key(for: now)
        if let cached = summaryCache, cached.day == day, cached.version == version { return cached.value }
        var active: Set<String> = Set(days.filter { $0.value > 0 }.keys)
        active.formUnion(minutes.filter { $0.value > 0 }.keys)
        let value = StudyStreak.summary(active: active, today: now, calendar: .current)
        summaryCache = (day, version, value)
        return value
    }

    /// Two years is a longer streak than anybody will have, and the log
    /// should not grow for as long as the app is installed.
    private func prune() {
        guard days.count > 730 else { return }
        let keep = Set(days.keys.sorted().suffix(730))
        days = days.filter { keep.contains($0.key) }
    }

    /// `yyyy-MM-dd` in the phone's own calendar and time zone: a day is the
    /// student's day, not UTC's.
    static func key(for date: Date) -> String {
        StudyStreak.key(for: date, calendar: .current)
    }
}
