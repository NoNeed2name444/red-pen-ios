import Foundation

// Reports and messages a student sends to us, kept until they are delivered.
//
// "Report this question" and "Contact us" must work on a train with no signal:
// the student says what is wrong once, and the app delivers it when it can.
// This file is the decisions only - what is queued, what is retried when, what
// is let go - so it is tested on a runner. SupportSender does the sending.

/// What is wrong with a question or card, picked from a short list.
enum SupportReason: String, Codable, CaseIterable, Identifiable {
    case wrongAnswer, wrongExplanation, unclear, outdated, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wrongAnswer: return "Wrong answer"
        case .wrongExplanation: return "Explanation is wrong"
        case .unclear: return "Typo or unclear"
        case .outdated: return "Out of date"
        case .other: return "Something else"
        }
    }
}

/// What a message to us is about.
enum ContactTopic: String, Codable, CaseIterable, Identifiable {
    case problem, idea, account, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .problem: return "Something isn\u{2019}t working"
        case .idea: return "An idea"
        case .account: return "Account or subscription"
        case .other: return "Something else"
        }
    }
}

/// One report or message waiting to be delivered.
struct PendingSupport: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case question, contact }

    var id = UUID()
    var kind: Kind
    /// A SupportReason (question) or ContactTopic (contact) raw value.
    var reason: String
    var note: String
    /// The reported item as the server reads it (an AccuracyItem, encoded).
    var itemJSON: String?
    var createdAt: Date
    var attempts: Int = 0
    var nextTry: Date?

    /// The reason's words.
    var reasonTitle: String {
        switch kind {
        case .question: return SupportReason(rawValue: reason)?.title ?? reason
        case .contact: return ContactTopic(rawValue: reason)?.title ?? reason
        }
    }

    /// The note as sent: the reason first, so a report reads on its own.
    var sentNote: String {
        let body: String = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let head: String = "[" + reasonTitle + "]"
        return body.isEmpty ? head : head + " " + body
    }

    /// Two copies of the same report are the same report.
    func sameAs(_ other: PendingSupport) -> Bool {
        kind == other.kind && reason == other.reason && itemJSON == other.itemJSON
            && sentNote == other.sentNote
    }
}

/// The queue itself. Oldest first; bounded; retried with a growing pause.
struct SupportOutbox: Codable, Equatable {
    static let maxPending = 50
    /// An unsent message older than this is let go: by then it is stale.
    static let maxAge: TimeInterval = 30 * 86_400
    /// The longest pause between tries.
    static let maxPause: TimeInterval = 6 * 3600

    var pending: [PendingSupport] = []

    mutating func add(_ item: PendingSupport, now: Date) {
        prune(now: now)
        if pending.contains(where: { $0.sameAs(item) }) { return }
        pending.append(item)
        let extra: Int = pending.count - Self.maxPending
        if extra > 0 { pending.removeFirst(extra) }
    }

    /// What may be tried now.
    func due(now: Date) -> [PendingSupport] {
        pending.filter { ($0.nextTry ?? .distantPast) <= now }
    }

    mutating func sent(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    /// A try that did not get through: wait 2, 4, 8... minutes, at most six
    /// hours.
    mutating func failed(_ id: UUID, now: Date) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        let tries: Int = pending[i].attempts + 1
        let pause: TimeInterval = min(Self.maxPause, 60 * pow(2, Double(min(tries, 12))))
        pending[i].attempts = tries
        pending[i].nextTry = now.addingTimeInterval(pause)
    }

    mutating func prune(now: Date) {
        pending.removeAll { now.timeIntervalSince($0.createdAt) > Self.maxAge }
    }
}

/// When to ask for an App Store rating: once, after something went well,
/// never straight after something went wrong.
enum ReviewPromptRules {
    enum Milestone: Equatable {
        /// A study streak of this many days.
        case streak(Int)
        /// A mock paper sat to the end.
        case mockFinished
    }

    struct State: Equatable {
        var asked: Bool
        var lastTrouble: Date?
    }

    static let streakDays = 7
    /// No asking for this long after an error was shown.
    static let quiet: TimeInterval = 30 * 60

    static let askedKey = "reviewPrompt.asked"
    static let troubleKey = "reviewPrompt.lastTrouble"

    static func shouldAsk(_ milestone: Milestone, state: State, now: Date) -> Bool {
        guard !state.asked else { return false }
        if let trouble = state.lastTrouble, now.timeIntervalSince(trouble) < quiet { return false }
        switch milestone {
        case .streak(let days): return days >= streakDays
        case .mockFinished: return true
        }
    }

    static func stored(_ defaults: UserDefaults = .standard) -> State {
        let stamp: Double = defaults.double(forKey: troubleKey)
        let trouble: Date? = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        return State(asked: defaults.bool(forKey: askedKey), lastTrouble: trouble)
    }

    /// Something went wrong on screen: hold any rating request for a while.
    static func noteTrouble(_ defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(now.timeIntervalSince1970, forKey: troubleKey)
    }
}
