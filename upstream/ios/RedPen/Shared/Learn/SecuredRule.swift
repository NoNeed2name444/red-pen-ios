import Foundation

/// "Lock it in": a question counts as secured once it has been answered
/// correctly on three separate days.
///
/// Successive relearning (Rawson & Dunlosky): getting something right once in
/// each of three spaced sessions keeps far more of it a week later than
/// getting it right three times in one sitting. So the days count, not the
/// answers - three right answers this afternoon are one day.
///
/// A wrong answer starts the count again, so an item that slips drops back
/// into practice until it meets the rule once more. Nothing new is stored:
/// it is read from the dated answer log (AnswerEvent), which sync already
/// carries.
///
/// Foundation only.
enum SecuredRule {
    /// Correct days needed.
    static let daysNeeded = 3

    /// Where one question stands.
    enum Standing: Hashable {
        /// Never answered.
        case new
        /// Right on this many separate days (0...2) since its last wrong
        /// answer.
        case building(Int)
        case secured

        var isSecured: Bool { self == .secured }

        /// Correct days so far, 0...3.
        var days: Int {
            switch self {
            case .new: return 0
            case .building(let n): return n
            case .secured: return SecuredRule.daysNeeded
            }
        }
    }

    /// Every question in the log, and where it stands. Events may come in any
    /// order; they are read oldest first.
    static func standings(_ events: [AnswerEvent],
                          calendar: Calendar = .current) -> [UUID: Standing] {
        let byQuestion = Dictionary(grouping: events, by: { (e: AnswerEvent) in e.questionId })
        var out: [UUID: Standing] = [:]
        for (id, list) in byQuestion {
            out[id] = standing(of: list, calendar: calendar)
        }
        return out
    }

    /// One question's standing from its own answers.
    static func standing(of events: [AnswerEvent], calendar: Calendar = .current) -> Standing {
        guard !events.isEmpty else { return .new }
        let ordered = events.sorted { $0.date < $1.date }
        var days: Set<Date> = []
        for event in ordered {
            if event.correct {
                // right with the attending's hint: neither a day towards
                // locking in nor a slip
                if event.hinted != true { days.insert(calendar.startOfDay(for: event.date)) }
            } else {
                // slipped: the count starts again
                days.removeAll()
            }
        }
        if days.count >= daysNeeded { return .secured }
        return .building(days.count)
    }

    /// One subject's ring: secured, building and not yet tried.
    struct Ring: Hashable, Identifiable {
        var subject: String
        var secured: Int
        var building: Int
        var new: Int
        var id: String { subject }
        var total: Int { secured + building + new }
        var fraction: Double { total == 0 ? 0 : Double(secured) / Double(total) }
    }

    /// Rings per subject for the questions in `subjects` (question id to
    /// subject), in subject order.
    static func rings(subjects: [UUID: String], standings: [UUID: Standing]) -> [Ring] {
        var rings: [String: Ring] = [:]
        for (id, subject) in subjects {
            var ring = rings[subject] ?? Ring(subject: subject, secured: 0, building: 0, new: 0)
            switch standings[id] ?? .new {
            case .secured: ring.secured += 1
            // tried, even if only got wrong so far
            case .building: ring.building += 1
            case .new: ring.new += 1
            }
            rings[subject] = ring
        }
        return rings.values.sorted { $0.subject.localizedCaseInsensitiveCompare($1.subject) == .orderedAscending }
    }

    /// Of `ids`, those one or two days short - the ones most worth a
    /// question today. Two first, then one.
    static func closeToSecure(_ ids: [UUID], standings: [UUID: Standing]) -> [UUID] {
        let two = ids.filter { standings[$0] == .building(2) }
        let one = ids.filter { standings[$0] == .building(1) }
        return two + one
    }

    /// Whether a correct answer today would move this question on: it was
    /// not already answered correctly today.
    static func countsToday(_ id: UUID, events: [AnswerEvent], now: Date,
                            calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        let todays = events.filter { $0.questionId == id && calendar.startOfDay(for: $0.date) == today }
        let latest = todays.max { $0.date < $1.date }
        return latest?.correct != true
    }
}
