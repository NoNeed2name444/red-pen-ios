import Foundation

// MARK: - What the widgets show
//
// The app writes one small JSON file into the App Group container each time
// the numbers change; the widgets, the Control and the Live Activity only
// ever read it. A widget never opens the library or the schedule itself:
// those files are large, live in the app's own container, and a widget has a
// few megabytes and a few milliseconds.
//
// Foundation only. This file is compiled into the app, the Playgrounds
// package (where nothing reads it) and the widget extension
// (ios/StethoscoreWidgets, listed in project.yml), and it is tested on Linux
// (PlatformTests).

struct GlanceDigest: Codable, Equatable {
    /// One deck with cards waiting.
    struct DueDeck: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var count: Int
    }

    static let currentVersion: Int = 1

    var version: Int = GlanceDigest.currentVersion
    /// When the app worked this out.
    var madeAt: Date
    /// Cards due now, within the day's limits.
    var dueNow: Int
    /// The decks with the most due, at most three.
    var topDecks: [DueDeck]
    /// When the next card not yet due comes due, if any.
    var nextDue: Date?
    /// The exam's name and day, when the student set one.
    var examName: String?
    var examDate: Date?
    /// Cards and questions done today, and the streak of days.
    var today: Int
    var streak: Int

    /// Nothing known yet: the gallery preview and a fresh install.
    static let empty = GlanceDigest(madeAt: Date(timeIntervalSince1970: 0), dueNow: 0, topDecks: [],
                                    nextDue: nil, examName: nil, examDate: nil, today: 0, streak: 0)

    /// What the widget gallery shows.
    static let sample = GlanceDigest(
        madeAt: Date(timeIntervalSince1970: 0), dueNow: 24,
        topDecks: [DueDeck(id: UUID(), name: "Cardiology", count: 14),
                   DueDeck(id: UUID(), name: "Renal", count: 10)],
        nextDue: nil, examName: "PLAB 1", examDate: Date().addingTimeInterval(38 * 86_400),
        today: 32, streak: 6)

    /// Whole days from `now` to the exam, counted in the student's calendar:
    /// 0 on the day, negative after it, nil without a date.
    func daysToExam(now: Date, calendar: Calendar = .current) -> Int? {
        guard let examDate else { return nil }
        let start: Date = calendar.startOfDay(for: now)
        let end: Date = calendar.startOfDay(for: examDate)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    /// The same numbers, whenever they were worked out. The app only writes
    /// the file (and only asks the widgets to reload) when this is false.
    func sameContent(as other: GlanceDigest) -> Bool {
        var a = self
        var b = other
        a.madeAt = Date(timeIntervalSince1970: 0)
        b.madeAt = Date(timeIntervalSince1970: 0)
        return a == b
    }

    /// The count to show at `now`: a digest from yesterday says nothing
    /// about today, except that the cards it counted are still waiting.
    func dueShown(at now: Date) -> Int {
        guard let nextDue, nextDue <= now else { return dueNow }
        // something more has come due since; the app will say how much when
        // it next runs, and meanwhile "at least" is honest
        return max(dueNow, 1)
    }

    /// Whether the streak is still alive at `now` (anything today, or a
    /// streak that ended yesterday and can still be kept tonight).
    func streakShown(at now: Date, calendar: Calendar = .current) -> Int {
        let made: Date = calendar.startOfDay(for: madeAt)
        let day: Date = calendar.startOfDay(for: now)
        let gap: Int = calendar.dateComponents([.day], from: made, to: day).day ?? 0
        if gap <= 0 { return streak }
        if gap == 1 && today > 0 { return streak }
        return 0
    }

    /// The count done today at `now`: a digest written yesterday reads 0.
    func todayShown(at now: Date, calendar: Calendar = .current) -> Int {
        calendar.isDate(madeAt, inSameDayAs: now) ? today : 0
    }

    /// Worked out from the app's figures. `due` is every due card's deck id
    /// and name, in any order; the decks are counted and the busiest kept.
    static func make(now: Date, due: [(id: UUID, name: String)], nextDue: Date?,
                     examName: String?, examDate: Date?, today: Int, streak: Int) -> GlanceDigest {
        var counts: [UUID: Int] = [:]
        var names: [UUID: String] = [:]
        for one in due {
            counts[one.id, default: 0] += 1
            names[one.id] = one.name
        }
        var decks: [DueDeck] = []
        for (id, count) in counts {
            decks.append(DueDeck(id: id, name: names[id] ?? "", count: count))
        }
        decks.sort { a, b in a.count != b.count ? a.count > b.count : a.name < b.name }
        let exam: Date? = (examDate ?? now) >= Calendar.current.startOfDay(for: now) ? examDate : nil
        return GlanceDigest(madeAt: now, dueNow: due.count, topDecks: Array(decks.prefix(3)),
                            nextDue: nextDue, examName: exam == nil ? nil : examName, examDate: exam,
                            today: today, streak: streak)
    }
}

// MARK: - Where it is kept

/// The shared file. The App Group's name comes from Info.plist
/// (`RedPenAppGroup`, set in project.yml) so the Swift never spells a team's
/// group; a build without one (Playgrounds, an unsigned CI build) keeps the
/// file in its own caches, where nothing else reads it and nothing breaks.
enum GlanceShelf {
    static let infoKey = "RedPenAppGroup"
    static let fileName = "glance-digest.json"

    static var groupID: String? {
        let value: String? = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    static var fileURL: URL? {
        let manager = FileManager.default
        #if canImport(Darwin)
        if let group = groupID, let shared = manager.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return shared.appendingPathComponent(fileName)
        }
        #endif
        let caches: URL? = manager.urls(for: .cachesDirectory, in: .userDomainMask).first
        return caches?.appendingPathComponent(fileName)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func read() -> GlanceDigest? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> GlanceDigest? {
        guard let digest = try? decoder.decode(GlanceDigest.self, from: data) else { return nil }
        // a newer app's file the widget cannot read is shown as nothing, not garbage
        return digest.version <= GlanceDigest.currentVersion ? digest : nil
    }

    @discardableResult
    static func write(_ digest: GlanceDigest) -> Bool {
        guard let url = fileURL, let data = try? encoder.encode(digest) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - When the exam-day Live Activity runs

/// From 6 pm the evening before the exam until the end of the exam day, in
/// the student's own calendar. A date with no time (midnight, as the date
/// picker stores it) has no start time to count down to.
enum ExamDayWindow {
    static let eveningHour: Int = 18

    static func start(exam: Date, calendar: Calendar = .current) -> Date {
        let day: Date = calendar.startOfDay(for: exam)
        let before: Date = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        return calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: before) ?? before
    }

    static func end(exam: Date, calendar: Calendar = .current) -> Date {
        let day: Date = calendar.startOfDay(for: exam)
        return calendar.date(byAdding: .day, value: 1, to: day) ?? day
    }

    static func contains(_ now: Date, exam: Date, calendar: Calendar = .current) -> Bool {
        now >= start(exam: exam, calendar: calendar) && now < end(exam: exam, calendar: calendar)
    }

    /// The paper's start, when the stored date carries a time of day.
    static func startsAt(exam: Date, calendar: Calendar = .current) -> Date? {
        let parts = calendar.dateComponents([.hour, .minute], from: exam)
        let hour: Int = parts.hour ?? 0
        let minute: Int = parts.minute ?? 0
        return (hour == 0 && minute == 0) ? nil : exam
    }
}
