import Foundation

/// What the run-up to the exam asks for, day by day, and the one most useful
/// session right now.
///
/// Far out, the job is learning and keeping what is learned. Ten to seven
/// days out, one full mock under exam conditions shows what is left. In the
/// last week nothing new goes in: only the mistakes, the confident errors,
/// the rule sheet and the cards falling due. On the morning, a calm kit.
///
/// Foundation only, so the choice can be tested without a screen.
enum ExamWeekPlanner {

    /// Where the student is in the run-up.
    enum Phase: Hashable {
        /// No exam date set.
        case noDate
        /// More than ten days to go: learn and keep.
        case building(days: Int)
        /// Ten to eight days out: time for a full mock (still offered at
        /// seven if it was not sat).
        case mockWindow(days: Int)
        /// Seven to one days out: nothing new.
        case examWeek(days: Int)
        case examDay
        case after

        /// Days left, when there is a date still to come.
        var days: Int? {
            switch self {
            case .building(let d), .mockWindow(let d), .examWeek(let d): return d
            case .examDay: return 0
            case .noDate, .after: return nil
            }
        }

        /// Whether this is the window for a full mock.
        var isMockWindow: Bool {
            if case .mockWindow = self { return true }
            return false
        }

        /// Whether new material should be held back.
        var holdsNewMaterial: Bool {
            switch self {
            case .examWeek, .examDay: return true
            default: return false
            }
        }

        /// A short headline for the phase.
        var headline: String {
            switch self {
            case .noDate: return "No exam date set"
            case .building: return "Learn and keep"
            case .mockWindow: return "Mock week"
            case .examWeek: return "Exam week \u{2014} nothing new"
            case .examDay: return "Exam day"
            case .after: return "Exam done"
            }
        }

        /// One line of advice for the phase.
        var advice: String {
            switch self {
            case .noDate:
                return "Set your exam date and the plan works back from it."
            case .building:
                return "New material, then reviews as they fall due. Aim to lock each question in on three separate days."
            case .mockWindow:
                return "Sit one full mock under exam timing now. What it shows is what the last week is for."
            case .examWeek:
                return "No new topics. Your mistakes, your confident errors and the rule sheet, then sleep \u{2014} sleep beats cramming."
            case .examDay:
                return "Nothing to learn today. Eat, check the kit, pace yourself, flag and move on."
            case .after:
                return "Your exam date has passed. Set the next one when you know it."
            }
        }
    }

    /// Days from `now` to `exam`, by calendar day.
    static func daysLeft(to exam: Date, now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                to: calendar.startOfDay(for: exam)).day ?? 0
    }

    static func phase(exam: Date?, now: Date, calendar: Calendar = .current) -> Phase {
        guard let exam else { return .noDate }
        let days = daysLeft(to: exam, now: now, calendar: calendar)
        if days < 0 { return .after }
        if days == 0 { return .examDay }
        if days <= 7 { return .examWeek(days: days) }
        if days <= 10 { return .mockWindow(days: days) }
        return .building(days: days)
    }

    // MARK: the one button

    /// What is waiting, as counts, for choosing the session.
    struct Situation: Hashable {
        var phase: Phase
        var dueCards: Int = 0
        /// Questions got wrong while sure.
        var confidentErrors: Int = 0
        /// Questions whose last answer was wrong.
        var missed: Int = 0
        var flagged: Int = 0
        /// Questions right on one or two days, not yet three.
        var closeToSecure: Int = 0
        /// Questions never answered.
        var untried: Int = 0
        /// Items from yesterday's misses still to re-ask this morning.
        var morningCheck: Int = 0
        /// Whether a mock has been sat in the mock window.
        var mockDone: Bool = false
        /// The weakest subject, when there is one.
        var weakestSubject: String?
    }

    /// The session the lift-off button starts.
    enum Mission: Hashable {
        case examKit
        case morningCheck(Int)
        case dueCards(Int)
        case mock
        case confidentErrors(Int)
        case mistakes(Int)
        case lockIn(Int)
        case flagged(Int)
        case weakest(String)
        case newQuestions
        case nothing

        var title: String {
            switch self {
            case .examKit: return "Open your exam-day kit"
            case .morningCheck(let n): return "Morning check \u{00B7} \(n) from yesterday"
            case .dueCards(let n): return "Study \(n) due card\(n == 1 ? "" : "s")"
            case .mock: return "Sit a mock paper"
            case .confidentErrors(let n): return "Fix \(n) confident error\(n == 1 ? "" : "s")"
            case .mistakes(let n): return "Redo \(n) missed question\(n == 1 ? "" : "s")"
            case .lockIn(let n): return "Lock in \(n) question\(n == 1 ? "" : "s")"
            case .flagged(let n): return "Practise \(n) flagged question\(n == 1 ? "" : "s")"
            case .weakest(let s): return "Drill \(s)"
            case .newQuestions: return "Try new questions"
            case .nothing: return "All done for now"
            }
        }

        var symbol: String {
            switch self {
            case .examKit: return "checklist"
            case .morningCheck: return "sunrise.fill"
            case .dueCards: return "play.fill"
            case .mock: return "timer"
            case .confidentErrors: return "exclamationmark.triangle.fill"
            case .mistakes: return "arrow.uturn.backward"
            case .lockIn: return "lock.fill"
            case .flagged: return "flag.fill"
            case .weakest: return "scope"
            case .newQuestions: return "sparkles"
            case .nothing: return "checkmark.circle.fill"
            }
        }
    }

    /// The most useful session now.
    ///
    /// Always first: the exam-day kit on the day, and a morning check of
    /// yesterday's misses (two minutes, before anything new). Cards due come
    /// next in every phase, because the schedule only works if they are done
    /// on the day. After that the phase decides: the mock in its window;
    /// confident errors, mistakes and the half-secured in exam week; and far
    /// out, locking in, then the weakest subject, then something new.
    static func mission(_ s: Situation) -> Mission {
        if s.phase == .examDay { return .examKit }
        if s.morningCheck > 0 { return .morningCheck(s.morningCheck) }
        if s.dueCards > 0 { return .dueCards(s.dueCards) }
        switch s.phase {
        case .mockWindow:
            if !s.mockDone { return .mock }
        case .examWeek(let days):
            // a mock missed in its window can still be sat at T-7
            if days == 7 && !s.mockDone { return .mock }
            if s.confidentErrors > 0 { return .confidentErrors(s.confidentErrors) }
            if s.missed > 0 { return .mistakes(s.missed) }
            if s.closeToSecure > 0 { return .lockIn(s.closeToSecure) }
            if s.flagged > 0 { return .flagged(s.flagged) }
            // no new material this week, so nothing else to offer
            return .nothing
        default:
            break
        }
        if s.confidentErrors > 0 { return .confidentErrors(s.confidentErrors) }
        if s.closeToSecure > 0 { return .lockIn(s.closeToSecure) }
        if s.flagged > 0 { return .flagged(s.flagged) }
        if let weakest = s.weakestSubject { return .weakest(weakest) }
        if s.untried > 0 { return .newQuestions }
        return .nothing
    }

    // MARK: the exam-day kit

    /// One pacing checkpoint: be at question `question` by `minute`.
    struct Checkpoint: Hashable {
        var minute: Int
        var question: Int
    }

    /// The paper the kit paces, for a track.
    struct Paper: Hashable {
        var name: String
        var questions: Int
        var minutes: Int
        /// Whether the numbers are the exam's own published format rather
        /// than a pace worked out from ExamTrack.
        var published: Bool
    }

    /// The paper for each track. PLAB 1 is 180 questions in three hours;
    /// an MRCP(UK) Part 1 paper is 100 in three hours; a USMLE block is up to
    /// 40 in an hour. MRCS Part A's papers have changed format more than
    /// once, so it (and general revision) gets an hour-long pace from the
    /// track's seconds per question and the kit says to check the count.
    static func paper(for track: ExamTrack) -> Paper {
        switch track {
        case .plab: return Paper(name: "PLAB 1", questions: 180, minutes: 180, published: true)
        case .mrcp: return Paper(name: "MRCP(UK) Part 1 paper", questions: 100, minutes: 180, published: true)
        case .usmle: return Paper(name: "USMLE block", questions: 40, minutes: 60, published: true)
        case .mrcs, .general:
            let perHour: Int = max(1, 3600 / max(1, track.secondsPerQuestion))
            return Paper(name: "An hour of questions", questions: perHour, minutes: 60, published: false)
        }
    }

    /// Where to be as time passes: each hour for a long paper, each quarter
    /// of it for a paper of an hour or less. The last checkpoint is the end.
    static func checkpoints(for paper: Paper) -> [Checkpoint] {
        guard paper.minutes > 0, paper.questions > 0 else { return [] }
        let step: Int = paper.minutes > 60 ? 60 : max(1, paper.minutes / 4)
        var out: [Checkpoint] = []
        var minute = step
        while minute <= paper.minutes {
            let share: Double = Double(minute) / Double(paper.minutes)
            let q: Int = Int((share * Double(paper.questions)).rounded())
            out.append(Checkpoint(minute: minute, question: min(paper.questions, max(1, q))))
            minute += step
        }
        if out.last?.minute != paper.minutes {
            out.append(Checkpoint(minute: paper.minutes, question: paper.questions))
        }
        return out
    }

    /// "1:00" for 60 minutes.
    static func clock(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
