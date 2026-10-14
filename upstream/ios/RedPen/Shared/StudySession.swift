import Foundation

// MARK: - The ward round
//
// A focus session in rounds: 25 or 50 minutes on, a 5- or 10-minute break,
// four rounds. Started from the exam plan (WardRoundTile), shown as a small
// chip over the whole app while it runs (WardRoundOverlay) and on the Lock
// Screen in the Xcode build (WardRoundAttributes).
//
// Everything here is worked out from dates, never from a ticking counter:
// the phone may be locked half way through a round, and when it comes back
// the clock simply runs forward to now (advance(to:)) and says what ended on
// the way. That is also why nothing here needs a timer at all - the screens
// redraw once a second while they are showing, and WardRoundClock sleeps
// until the next phase is due to end.
//
// Foundation only, so the Linux tests (WardRoundTests.swift) run it.

/// How a ward round is set up.
struct WardRoundPlan: Codable, Hashable {
    var focusMinutes: Int
    var breakMinutes: Int
    var rounds: Int

    static let focusChoices: [Int] = [25, 50]
    static let breakChoices: [Int] = [5, 10]
    static let standard = WardRoundPlan(focusMinutes: 25, breakMinutes: 5)

    /// Held to sane values, so a stored choice from an older build never
    /// makes a zero-length or day-long round.
    init(focusMinutes: Int, breakMinutes: Int, rounds: Int = 4) {
        self.focusMinutes = min(max(focusMinutes, 1), 120)
        self.breakMinutes = min(max(breakMinutes, 1), 30)
        self.rounds = min(max(rounds, 1), 8)
    }

    var focusLength: TimeInterval { TimeInterval(focusMinutes * 60) }
    var breakLength: TimeInterval { TimeInterval(breakMinutes * 60) }
}

/// One ward round under way, as a value: where it is, and what it has
/// counted so far.
struct WardRound: Codable, Equatable {
    enum Phase: String, Codable {
        /// The clock is running on a round.
        case focus
        /// The break after `round`.
        case rest
        /// The break is over; the next round waits for the student to start
        /// it, so a phone left on the desk does not rack up rounds nobody sat.
        case ready
        /// Every round done, or stopped.
        case done
    }

    /// What happened as the clock moved on, for WardRoundClock to act on.
    enum Event: Equatable {
        /// A round's focus ended - ran out, or was cut short - after
        /// `seconds` of it, at `end`.
        case focusEnded(round: Int, seconds: TimeInterval, end: Date)
        /// The break after `round` is over.
        case restEnded(round: Int)
        /// The whole ward round is over.
        case finished
    }

    let plan: WardRoundPlan
    let startedAt: Date
    /// 1-based. During a break, the round just finished.
    private(set) var round: Int
    private(set) var phase: Phase
    /// When the running phase's clock reaches zero (focus and rest only).
    private(set) var phaseEnds: Date
    /// The time left, held still, while paused.
    private(set) var pausedLeft: TimeInterval?
    /// Cards, questions and steps studied while a round's clock ran.
    private(set) var items: Int
    /// Focus time sat so far, in seconds, across every round.
    private(set) var focusSeconds: TimeInterval

    static func begin(_ plan: WardRoundPlan, at now: Date) -> WardRound {
        WardRound(plan: plan, startedAt: now, round: 1, phase: .focus,
                  phaseEnds: now.addingTimeInterval(plan.focusLength),
                  pausedLeft: nil, items: 0, focusSeconds: 0)
    }

    var isPaused: Bool { pausedLeft != nil }

    /// Whether a clock is counting down (or held) right now.
    var isTimed: Bool { phase == .focus || phase == .rest }

    /// Whether a screen showing this needs to redraw every second.
    var ticks: Bool { isTimed && !isPaused }

    /// The full length of the phase showing.
    var phaseLength: TimeInterval {
        switch phase {
        case .focus: return plan.focusLength
        case .rest: return plan.breakLength
        case .ready, .done: return 0
        }
    }

    /// Seconds left on the clock.
    func remaining(at now: Date) -> TimeInterval {
        guard isTimed else { return 0 }
        if let pausedLeft { return pausedLeft }
        return max(0, phaseEnds.timeIntervalSince(now))
    }

    /// How much of the phase is left, 1 at its start and 0 at its end: the
    /// orbit ring's length.
    func leftFraction(at now: Date) -> Double {
        let length: TimeInterval = phaseLength
        guard length > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / length))
    }

    /// Whole minutes of focus sat so far.
    var focusMinutes: Int { Int(focusSeconds / 60) }

    // MARK: moving on

    /// Runs the clock forward to `now`: every phase whose time has run out
    /// ends, in order, each at the moment it ran out.
    mutating func advance(to now: Date) -> [Event] {
        var events: [Event] = []
        while ticks && phaseEnds <= now {
            events += finishPhase(at: phaseEnds)
        }
        return events
    }

    /// Ends the running phase now: a round cut short (the time sat still
    /// counts) goes to its break, a skipped break to the next round's start.
    mutating func skip(at now: Date) -> [Event] {
        guard isTimed else { return [] }
        return finishPhase(at: now)
    }

    /// Starts the next round - after a break, or in place of the rest of it.
    mutating func startNext(at now: Date) {
        guard phase == .ready || phase == .rest, round < plan.rounds else { return }
        round += 1
        phase = .focus
        pausedLeft = nil
        phaseEnds = now.addingTimeInterval(plan.focusLength)
    }

    mutating func pause(at now: Date) {
        guard isTimed, !isPaused else { return }
        pausedLeft = remaining(at: now)
    }

    mutating func resume(at now: Date) {
        guard let left = pausedLeft else { return }
        phaseEnds = now.addingTimeInterval(left)
        pausedLeft = nil
    }

    /// Stops the whole ward round now. A round under way still counts for
    /// the time sat in it.
    mutating func stop(at now: Date) -> [Event] {
        guard phase != .done else { return [] }
        var events: [Event] = []
        if phase == .focus {
            let spent: TimeInterval = plan.focusLength - remaining(at: now)
            focusSeconds += spent
            events.append(.focusEnded(round: round, seconds: spent, end: now))
        }
        phase = .done
        pausedLeft = nil
        events.append(.finished)
        return events
    }

    /// Something studied: counted only while a round's clock is on - not
    /// in a break, and not while the round is paused.
    mutating func noteStudied(_ count: Int) {
        guard phase == .focus, !isPaused, count > 0 else { return }
        items += count
    }

    private mutating func finishPhase(at end: Date) -> [Event] {
        switch phase {
        case .focus:
            let spent: TimeInterval = plan.focusLength - remaining(at: end)
            focusSeconds += spent
            pausedLeft = nil
            var events: [Event] = [.focusEnded(round: round, seconds: spent, end: end)]
            if round >= plan.rounds {
                phase = .done
                events.append(.finished)
            } else {
                phase = .rest
                phaseEnds = end.addingTimeInterval(plan.breakLength)
            }
            return events
        case .rest:
            pausedLeft = nil
            phase = .ready
            return [.restEnded(round: round)]
        case .ready, .done:
            return []
        }
    }

    // MARK: what it says

    /// "12:40": minutes and seconds, rounded up, so a fresh round reads
    /// 25:00 and the last second 0:01.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole: Int = Int(seconds.rounded(.up))
        let minutes: Int = whole / 60
        let rest: Int = whole % 60
        return String(format: "%d:%02d", minutes, rest)
    }

    static func cardWords(_ count: Int) -> String {
        count == 1 ? "1 card" : "\(count) cards"
    }

    /// "Round 2 of 4".
    var roundWords: String { "Round \(round) of \(plan.rounds)" }

    /// One line for the chip's label, the panel and the Lock Screen:
    /// "Round 2 of 4 · 12:40 · 38 cards".
    func caption(at now: Date) -> String {
        let dot: String = " \u{00B7} "
        let cards: String = Self.cardWords(items)
        let time: String = Self.clock(remaining(at: now))
        switch phase {
        case .focus:
            return roundWords + dot + time + dot + cards
        case .rest:
            return "Break" + dot + time + dot + cards
        case .ready:
            return "Round \(round + 1) of \(plan.rounds) when you\u{2019}re ready" + dot + cards
        case .done:
            return "Ward round done" + dot + "\(focusMinutes) min" + dot + cards
        }
    }

    // MARK: notifications

    /// A heads-up for when the app is not in front.
    struct Alarm: Equatable {
        var id: String
        var date: Date
        var title: String
        var body: String
    }

    /// The phase ends still to come, as the notifications to leave with the
    /// system: the end of this round, and the end of the break after it.
    /// None while paused - there is no end to announce.
    func alarms(at now: Date) -> [Alarm] {
        guard ticks else { return [] }
        var out: [Alarm] = []
        if phase == .focus {
            if round >= plan.rounds {
                let body: String = "\(plan.rounds) rounds sat. Well done."
                out.append(Alarm(id: "wardround-focus", date: phaseEnds, title: "Ward round done", body: body))
                return out
            }
            let body: String = "Take \(plan.breakMinutes) minutes away from the screen."
            out.append(Alarm(id: "wardround-focus", date: phaseEnds, title: roundWords + " done", body: body))
            let breakEnds: Date = phaseEnds.addingTimeInterval(plan.breakLength)
            let next: String = "Round \(round + 1) of \(plan.rounds) is ready when you are."
            out.append(Alarm(id: "wardround-rest", date: breakEnds, title: "Break over", body: next))
        } else {
            let next: String = "Round \(round + 1) of \(plan.rounds) is ready when you are."
            out.append(Alarm(id: "wardround-rest", date: phaseEnds, title: "Break over", body: next))
        }
        return out.filter { $0.date > now }
    }

    static let alarmIDs: [String] = ["wardround-focus", "wardround-rest"]
}
