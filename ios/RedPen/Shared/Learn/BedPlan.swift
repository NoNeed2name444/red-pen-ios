import Foundation

/// Today's ward round on the home screen: the patients in the beds, in the
/// order they are best seen, worked out from what the library already keeps.
///
/// A bed is one thing to study, opened with one tap. The round holds at most
/// four, in this order:
///
/// 1. the run-up's own priority, when the exam-week planner has one that the
///    other beds do not already hold (ExamWeekPlanner.mission): the exam-day
///    kit, the morning check of yesterday's misses, the mock in its window,
///    confident errors, mistakes, questions close to locked in, flagged ones;
/// 2. the cards due today, because spacing only works if they are done on
///    the day;
/// 3. the weakest topic: the first of `weakSpots`, the subjects that need a
///    consult, so the topic the Vitals screen names is always on the round;
/// 4. the newest set nothing has been done in yet (never in exam week, when
///    nothing new goes in), or new questions when the planner asks for them;
/// 5. an OSCE station: one part way through first, else the newest.
///
/// On exam day the round is the kit alone. Nothing here is stored: the round
/// is worked out again whenever the home is drawn, so tomorrow's round is
/// made from tomorrow's numbers.
///
/// A set can only take a bed in a mode `Mode` names, so a mode the round does
/// not offer can never appear in it.
///
/// Foundation only, so the choice is tested on Linux (BedPlanTests).
enum BedPlan {

    /// The most beds a round holds.
    static let most = 4
    /// A subject needs a consult below this accuracy...
    static let consultBelow = 0.75
    /// ...once it has at least this many answers to judge it by (the Vitals
    /// screen's Focus next uses the same two numbers).
    static let consultAnswers = 5
    /// A review card, on average.
    static let secondsPerCard = 10
    /// A textbook page.
    static let secondsPerPage = 180
    /// How much of a new set the first sitting is reckoned to cover, and how
    /// many questions a drill or a quiz built on the spot holds.
    static let firstSitting = 20
    static let firstPages = 3

    // MARK: what the round is made from

    /// A subject as the answer history sees it (Store.subjectStats).
    struct Topic: Hashable {
        var name: String
        /// Questions in the library under it.
        var questions: Int
        /// Answers checked, a question answered twice counting twice.
        var answered: Int
        var correct: Int

        var accuracy: Double { answered == 0 ? 0 : Double(correct) / Double(answered) }
        /// 48 for 0.48.
        var percent: Int { Int((accuracy * 100).rounded()) }
    }

    /// The modes a set can take a bed in.
    enum Mode: Hashable {
        case questions, cards, textbook

        /// "MCQ", as a set's row says it.
        var label: String {
            switch self {
            case .questions: return "MCQ"
            case .cards: return "Cards"
            case .textbook: return "Textbook"
            }
        }

        var noun: String {
            switch self {
            case .questions: return "question"
            case .cards: return "card"
            case .textbook: return "page"
            }
        }
    }

    /// A set nothing has been done in yet (the caller decides "started").
    struct FreshSet: Hashable {
        var id: UUID
        var name: String
        var subject: String
        var mode: Mode
        var items: Int
        var createdAt: Date
    }

    /// An OSCE station a bed can open: its set opens on it.
    struct Station: Hashable {
        var setID: UUID
        var title: String
        /// Part way through: opening the set carries on from there.
        var resumes: Bool
        var createdAt: Date
    }

    struct Input {
        /// The one most useful session now, by the exam-week planner.
        var mission: ExamWeekPlanner.Mission = .nothing
        var phase: ExamWeekPlanner.Phase = .noDate
        var dueCards: Int = 0
        /// The subjects the due cards come from, most cards first.
        var dueFrom: [String] = []
        /// Every subject, as Store.subjectStats lists them.
        var topics: [Topic] = []
        var fresh: [FreshSet] = []
        var stations: [Station] = []
        /// Questions never answered, for the planner's "new questions".
        var untried: Int = 0
        /// Seconds an exam question gets (ExamTrack.secondsPerQuestion).
        var secondsPerQuestion: Int = 75
        /// Minutes in one of the exam's clinical stations (ExamTrack).
        var stationMinutes: Int = 8
        /// Minutes the exam's paper runs (ExamWeekPlanner.paper).
        var mockMinutes: Int = 60
    }

    // MARK: what the round shows

    /// What a bed holds, and so what a tap on it starts.
    enum Kind: Hashable {
        case priority(ExamWeekPlanner.Mission)
        case dueCards(Int)
        case weakest(Topic)
        case freshSet(FreshSet)
        case station(Station)
    }

    /// The chip at the end of a bed's row.
    enum Status: String, Hashable {
        case due = "Due"
        case new = "New"
        case weak = "Weak"
        case timed = "Timed"
        case today = "Today"
    }

    struct Bed: Hashable, Identifiable {
        var number: Int
        var kind: Kind
        /// After "Bed 1 ·" in the small-caps line: "Cardiology", "Morning check".
        var ward: String
        var title: String
        var detail: String
        var status: Status?
        var minutes: Int

        /// "Bed 1 · Cardiology", in the source's own case; the row shows it
        /// in small caps.
        var overline: String { "Bed \(number) \u{00B7} \(ward)" }

        /// What VoiceOver reads for the whole row.
        var spoken: String {
            var parts: [String] = ["Bed \(number), \(ward)", title, detail, BedPlan.aboutMinutes(minutes)]
            if let status { parts.append(status.rawValue) }
            return parts.joined(separator: ". ")
        }

        /// The same bed keeps its identity as the beds before it come and go.
        var id: String {
            switch kind {
            case .priority: return "priority"
            case .dueCards: return "due"
            case .weakest(let topic): return "weakest-" + topic.name
            case .freshSet(let set): return "fresh-" + set.id.uuidString
            case .station(let station): return "station-" + station.setID.uuidString
            }
        }
    }

    // MARK: the choice

    /// The subjects that need a consult, weakest first: tried often enough
    /// to judge, and below `consultBelow`.
    static func weakSpots(_ topics: [Topic]) -> [Topic] {
        let judged: [Topic] = topics.filter { $0.answered >= consultAnswers && $0.accuracy < consultBelow }
        return judged.sorted { a, b in
            if a.accuracy != b.accuracy { return a.accuracy < b.accuracy }
            if a.answered != b.answered { return a.answered > b.answered }
            return a.name < b.name
        }
    }

    /// The line under the weak spots on the Vitals screen: what the ward
    /// round does about them, said only as far as `beds` makes it true (the
    /// weakest spot has a bed on every round but exam day's; BedPlanTests
    /// checks the sentence against the round).
    static func consultNote(_ spots: [Topic], phase: ExamWeekPlanner.Phase, anyJudged: Bool) -> String {
        let line: Int = Int((consultBelow * 100).rounded())
        guard let first = spots.first else {
            if anyJudged {
                return "Nothing needs a consult: every subject with \(consultAnswers) or more answers is at \(line)% or better."
            }
            return "A subject shows here once it has \(consultAnswers) answers and is under \(line)%."
        }
        if phase == .examDay {
            return "Exam day: today\u{2019}s ward round is your kit alone, so these can wait."
        }
        return "\(first.name), the weakest, is on today\u{2019}s ward round automatically."
    }

    /// Today's beds, numbered from 1.
    static func beds(_ input: Input) -> [Bed] {
        var kinds: [Kind] = []
        if input.phase == .examDay {
            // nothing to learn today: the kit, and nothing else
            kinds = [.priority(.examKit)]
        } else {
            if let mission = priority(input.mission) { kinds.append(.priority(mission)) }
            if input.dueCards > 0 { kinds.append(.dueCards(input.dueCards)) }
            if let topic = weakest(input) { kinds.append(.weakest(topic)) }
            if !input.phase.holdsNewMaterial {
                if let set = newest(input.fresh) {
                    kinds.append(.freshSet(set))
                } else if input.mission == .newQuestions && input.untried > 0 {
                    kinds.append(.priority(.newQuestions))
                }
            }
            if let station = station(input.stations) { kinds.append(.station(station)) }
        }
        let kept: [Kind] = Array(kinds.prefix(most))
        var out: [Bed] = []
        for (index, kind) in kept.enumerated() {
            out.append(bed(kind, number: index + 1, input))
        }
        return out
    }

    /// The planner's mission when it is a bed of its own; nil when another
    /// bed already holds it (cards due, the weakest subject, something new)
    /// or there is nothing to do.
    static func priority(_ mission: ExamWeekPlanner.Mission) -> ExamWeekPlanner.Mission? {
        switch mission {
        case .examKit, .morningCheck, .mock, .confidentErrors, .mistakes, .lockIn, .flagged:
            return mission
        case .dueCards, .weakest, .newQuestions, .nothing:
            return nil
        }
    }

    /// The weakest subject that needs a consult; failing that, the subject
    /// the planner itself would drill.
    static func weakest(_ input: Input) -> Topic? {
        if let first = weakSpots(input.topics).first { return first }
        if case .weakest(let name) = input.mission {
            return input.topics.first { $0.name == name && $0.questions > 0 }
        }
        return nil
    }

    static func newest(_ fresh: [FreshSet]) -> FreshSet? {
        let usable: [FreshSet] = fresh.filter { $0.items > 0 }
        return usable.max { a, b in
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.name > b.name
        }
    }

    /// A station part way through first, else the newest.
    static func station(_ stations: [Station]) -> Station? {
        stations.max { a, b in
            if a.resumes != b.resumes { return !a.resumes }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.title > b.title
        }
    }

    // MARK: each bed's words and minutes

    static func bed(_ kind: Kind, number: Int, _ input: Input) -> Bed {
        let q: Int = input.secondsPerQuestion
        switch kind {
        case .priority(let mission):
            return priorityBed(mission, number: number, input)
        case .dueCards(let count):
            let one: Bool = input.dueFrom.count == 1
            let ward: String = one ? input.dueFrom[0] : "Spaced review"
            let detail: String = input.dueFrom.count > 1 ? "From \(input.dueFrom.count) subjects" : "Spaced review"
            return Bed(number: number, kind: kind, ward: ward, title: counted(count, "card") + " due",
                       detail: detail, status: .due, minutes: minutes(seconds: count * secondsPerCard))
        case .weakest(let topic):
            let drill: Int = min(firstSitting, max(1, topic.questions))
            return Bed(number: number, kind: kind, ward: topic.name,
                       title: "Weakest topic \u{00B7} \(topic.percent)%",
                       detail: "\(drill) MCQ\(drill == 1 ? "" : "s"), missed ones first", status: .weak,
                       minutes: minutes(seconds: drill * q))
        case .freshSet(let set):
            let subject: String = set.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let ward: String = subject.isEmpty || subject == "General" ? set.mode.label : subject
            let detail: String = "\(set.mode.label) \u{00B7} \(counted(set.items, set.mode.noun)) \u{00B7} not started"
            return Bed(number: number, kind: kind, ward: ward, title: set.name, detail: detail,
                       status: .new, minutes: firstSittingMinutes(set, secondsPerQuestion: q))
        case .station(let station):
            var detail: String = "\(input.stationMinutes) min timed"
            if station.resumes { detail += " \u{00B7} carry on where you left off" }
            return Bed(number: number, kind: kind, ward: "OSCE station", title: station.title,
                       detail: detail, status: nil, minutes: max(1, input.stationMinutes))
        }
    }

    private static func priorityBed(_ mission: ExamWeekPlanner.Mission, number: Int, _ input: Input) -> Bed {
        let q: Int = input.secondsPerQuestion
        let kind: Kind = .priority(mission)
        switch mission {
        case .examKit:
            return Bed(number: number, kind: kind, ward: "Exam day", title: "Your exam-day kit",
                       detail: "What to bring, the pacing, and calm", status: .today, minutes: 5)
        case .morningCheck(let n):
            return Bed(number: number, kind: kind, ward: "Morning check", title: counted(n, "question") + " from yesterday",
                       detail: "Yesterday\u{2019}s misses, before anything new", status: .due,
                       minutes: minutes(seconds: min(n, 10) * q))
        case .mock:
            return Bed(number: number, kind: kind, ward: "Mock week", title: "Sit a mock paper",
                       detail: "Once, under exam timing", status: .timed, minutes: max(1, input.mockMinutes))
        case .confidentErrors(let n):
            return Bed(number: number, kind: kind, ward: "Sure but wrong", title: counted(n, "confident error"),
                       detail: "Facts learned wrongly, put right first", status: .weak,
                       minutes: minutes(seconds: min(n, firstSitting) * q))
        case .mistakes(let n):
            return Bed(number: number, kind: kind, ward: "Your mistakes", title: counted(n, "missed question"),
                       detail: "The ones you got wrong last time", status: .weak,
                       minutes: minutes(seconds: min(n, 30) * q))
        case .lockIn(let n):
            return Bed(number: number, kind: kind, ward: "Lock it in", title: counted(n, "question") + " close to secure",
                       detail: "One more right day each", status: .due,
                       minutes: minutes(seconds: min(n, firstSitting) * q))
        case .flagged(let n):
            return Bed(number: number, kind: kind, ward: "Flagged", title: counted(n, "flagged question"),
                       detail: "The ones you marked to come back to", status: .due,
                       minutes: minutes(seconds: n * q))
        case .newQuestions:
            return Bed(number: number, kind: kind, ward: "New questions", title: "\(input.untried) not tried yet",
                       detail: "Up to \(firstSitting), mixed across your sets", status: .new,
                       minutes: minutes(seconds: min(input.untried, firstSitting) * q))
        case .dueCards(let n):
            return bed(.dueCards(n), number: number, input)
        case .weakest(let name):
            let topic: Topic = input.topics.first { $0.name == name }
                ?? Topic(name: name, questions: firstSitting, answered: 0, correct: 0)
            return bed(.weakest(topic), number: number, input)
        case .nothing:
            return Bed(number: number, kind: kind, ward: "All quiet", title: "Nothing is waiting",
                       detail: "Come back later", status: nil, minutes: 0)
        }
    }

    /// A new set's first sitting: twenty questions or cards, three pages.
    static func firstSittingMinutes(_ set: FreshSet, secondsPerQuestion: Int) -> Int {
        switch set.mode {
        case .questions: return minutes(seconds: min(set.items, firstSitting) * secondsPerQuestion)
        case .cards: return minutes(seconds: min(set.items, firstSitting) * secondsPerCard)
        case .textbook: return minutes(seconds: min(set.items, firstPages) * secondsPerPage)
        }
    }

    // MARK: the round as a whole

    /// The round's minutes: each bed's, added up.
    static func minutes(_ beds: [Bed]) -> Int {
        beds.reduce(0) { $0 + $1.minutes }
    }

    /// "4 patients · 45 min".
    static func summary(_ beds: [Bed]) -> String {
        guard !beds.isEmpty else { return "No patients waiting" }
        return counted(beds.count, "patient") + " \u{00B7} \(minutes(beds)) min"
    }

    /// The round's heading as VoiceOver reads it: "Today's ward round: 4
    /// patients, about 45 minutes."
    static func spokenSummary(_ beds: [Bed]) -> String {
        guard !beds.isEmpty else { return "Today\u{2019}s ward round: no patients waiting." }
        let about: String = aboutMinutes(minutes(beds)).lowercased()
        return "Today\u{2019}s ward round: " + counted(beds.count, "patient") + ", " + about + "."
    }

    /// "About 1 minute", "About 12 minutes".
    static func aboutMinutes(_ minutes: Int) -> String {
        "About \(counted(max(1, minutes), "minute"))"
    }

    /// Whole minutes, rounded up, never under one.
    static func minutes(seconds: Int) -> Int {
        max(1, (max(0, seconds) + 59) / 60)
    }

    /// "1 card", "12 cards".
    static func counted(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
