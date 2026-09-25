import Foundation

/// The small daily rhythm around the main sessions: a question of the day on
/// the lock screen, a calm evening re-read of the day's misses, and a
/// two-minute morning check of the same items.
///
/// All of it is opt-in (ReminderSettings) and all of it is local
/// notifications - no server. This file holds the choices and the wording;
/// LearnNotifications does the scheduling.
///
/// Foundation only.
enum StudyRhythm {

    // MARK: the day's misses

    /// Questions whose latest answer on `day` was wrong, in the order they
    /// were last missed.
    static func missed(on day: Date, events: [AnswerEvent], calendar: Calendar = .current) -> [UUID] {
        let start = calendar.startOfDay(for: day)
        var latest: [UUID: AnswerEvent] = [:]
        for e in events where calendar.startOfDay(for: e.date) == start && e.isExample != true {
            if let kept = latest[e.questionId], kept.date > e.date { continue }
            latest[e.questionId] = e
        }
        return latest.values.filter { !$0.correct }.sorted { $0.date < $1.date }.map(\.questionId)
    }

    /// The morning check: yesterday's misses not already answered today.
    static func morningItems(now: Date, events: [AnswerEvent], calendar: Calendar = .current) -> [UUID] {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return [] }
        let today = calendar.startOfDay(for: now)
        let answeredToday = Set(events.filter { calendar.startOfDay(for: $0.date) == today }.map(\.questionId))
        return missed(on: yesterday, events: events, calendar: calendar).filter { !answeredToday.contains($0) }
    }

    // MARK: question of the day

    /// One question the notification can ask.
    struct Candidate: Hashable {
        var id: UUID
        var subject: String
        /// Options, so a question with more than five (the notification has
        /// room for A to E) can be left out.
        var optionCount: Int
    }

    /// The day's question: from the weakest subject that has one, preferring
    /// a question one or two days from secured, then one never tried, then
    /// any. The same all day (seeded by the date), different tomorrow.
    static func questionOfTheDay(_ candidates: [Candidate], weakestFirst subjects: [String],
                                 standings: [UUID: SecuredRule.Standing], day: Date,
                                 calendar: Calendar = .current) -> UUID? {
        let usable = candidates.filter { $0.optionCount >= 2 && $0.optionCount <= 5 }
        guard !usable.isEmpty else { return nil }
        let order = subjects + Array(Set(usable.map(\.subject)).subtracting(subjects)).sorted()
        let seed = daySeed(day, calendar: calendar)
        for subject in order {
            let pool = usable.filter { $0.subject == subject }
            guard !pool.isEmpty else { continue }
            let close = pool.filter { c in
                if case .building(let n) = standings[c.id] ?? .new { return n > 0 }
                return false
            }
            let fresh = pool.filter { (standings[$0.id] ?? .new) == .new }
            let slipped = pool.filter { standings[$0.id] == .building(0) }
            for tier in [close, slipped, fresh, pool] where !tier.isEmpty {
                let sorted = tier.sorted { $0.id.uuidString < $1.id.uuidString }
                return sorted[Int(seed % UInt64(sorted.count))].id
            }
        }
        return nil
    }

    /// A number that is the same all day.
    static func daySeed(_ day: Date, calendar: Calendar = .current) -> UInt64 {
        let p = calendar.dateComponents([.year, .month, .day], from: day)
        let n = (p.year ?? 0) * 10_000 + (p.month ?? 0) * 100 + (p.day ?? 0)
        return UInt64(max(0, n)) &* 2_654_435_761
    }

    /// "A", "B", ...
    static func letter(_ i: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        return letters.indices.contains(i) ? letters[i] : "\(i + 1)"
    }

    /// An option cut to fit a notification button.
    static func abbreviated(_ option: String, limit: Int = 34) -> String {
        let s = option.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > limit else { return s }
        return String(s.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// The notification's body: the stem, cut to fit, then the options.
    static func questionBody(stem: String, options: [String], stemLimit: Int = 320) -> String {
        var s = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > stemLimit { s = String(s.prefix(stemLimit - 1)) + "\u{2026}" }
        let lines = options.enumerated().map { "\(letter($0.offset))  \(abbreviated($0.element, limit: 60))" }
        return ([s, ""] + lines + ["", "Hold to answer."]).joined(separator: "\n")
    }

    /// The reply after an answer from the notification.
    static func verdict(correct: Bool, rightLetter: String, rightText: String) -> (title: String, body: String) {
        if correct { return ("Correct \u{2014} \(rightLetter)", "\(abbreviated(rightText, limit: 80)). Tap for why.") }
        return ("It was \(rightLetter)", "\(abbreviated(rightText, limit: 80)). Tap for why.")
    }

    // MARK: evening and morning

    static func bedtimeBody(misses: Int, examDays: Int?) -> String {
        let plural = misses == 1 ? "" : "es"
        var s = "\(misses) of today\u{2019}s miss\(plural), with the answer and one line each. A calm read, not a test."
        if let d = examDays, d >= 0, d <= 7 { s += " Then sleep \u{2014} it does more than cramming this week." }
        return s
    }

    static func morningBody(items: Int) -> String {
        let plural = items == 1 ? "" : "s"
        return "Two minutes: \(items) question\(plural) you missed yesterday, before anything new."
    }
}

/// The reminder choices, kept on this device.
enum ReminderSettings {
    static let questionKey = "reminder.qotd"
    static let questionTimeKey = "reminder.qotd.minutes"
    static let bedtimeKey = "reminder.bedtime"
    static let bedtimeTimeKey = "reminder.bedtime.minutes"
    static let morningKey = "reminder.morning"
    static let morningTimeKey = "reminder.morning.minutes"

    /// Minutes after midnight.
    static let defaultQuestionTime = 12 * 60 + 30
    static let defaultBedtime = 22 * 60
    static let defaultMorning = 7 * 60 + 30

    static func minutes(_ key: String, default value: Int, _ defaults: UserDefaults = .standard) -> Int {
        guard let stored = defaults.object(forKey: key) as? Int, stored >= 0, stored < 1440 else { return value }
        return stored
    }

    static var questionOn: Bool { UserDefaults.standard.bool(forKey: questionKey) }
    static var bedtimeOn: Bool { UserDefaults.standard.bool(forKey: bedtimeKey) }
    static var morningOn: Bool { UserDefaults.standard.bool(forKey: morningKey) }

    /// The next time at `minutes` past midnight after `now` (today's if it
    /// is still ahead by a few minutes, else tomorrow's).
    static func next(_ minutes: Int, after now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        let today = calendar.date(byAdding: .minute, value: minutes, to: start) ?? now
        if today > now.addingTimeInterval(120) { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
