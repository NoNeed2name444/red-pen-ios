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

    /// Answers per day, keyed by the local calendar date.
    @Published private(set) var days: [String: Int] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        days = defaults.dictionary(forKey: Self.storageKey) as? [String: Int] ?? [:]
    }

    /// Counts one piece of study against today.
    func record(_ count: Int = 1) {
        guard count > 0 else { return }
        let key = Self.key(for: Date())
        days[key, default: 0] += count
        prune()
        defaults.set(days, forKey: Self.storageKey)
    }

    /// How much has been done today.
    var today: Int { days[Self.key(for: Date())] ?? 0 }

    /// Days in a row with something done, ending today - or ending yesterday
    /// when nothing has been done yet today, so a streak does not read as
    /// broken at breakfast before the day's first card.
    var streak: Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        if (days[Self.key(for: day)] ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var run = 0
        while (days[Self.key(for: day)] ?? 0) > 0 {
            run += 1
            guard let before = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = before
        }
        return run
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
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
