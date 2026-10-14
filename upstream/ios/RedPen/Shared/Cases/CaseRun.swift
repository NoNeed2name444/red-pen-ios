import Foundation

// One go at a case: which steps were taken and when on the case's clock, the
// differential ladder after each of them, and the decision at the end.
//
// The ladder is copied after every step, so the debrief can show how it moved
// and when (if ever) the right diagnosis went to the top. Nothing here asks the
// student to update it: a ladder left alone is copied as it stands.
//
// Foundation only; tested in the "cases" suite.

struct CaseRun: Codable, Hashable, Sendable {

    /// One step taken, and the case clock's minutes once it was done.
    struct Taken: Codable, Hashable, Sendable {
        var stepID: String
        var at: Int
    }

    struct Decision: Codable, Hashable, Sendable {
        /// The leading diagnosis, as confirmed.
        var diagnosis: String
        /// The chosen next step, an index into the case's options.
        var nextStep: Int
        /// The optional one-line reason.
        var reason: String = ""
    }

    /// Where a case stands for the list.
    enum State: Equatable, Sendable {
        case new
        case seen
        case discharged(score: Int)
    }

    /// The most diagnoses on the ladder at once.
    static let rungs = 3

    var caseID: UUID
    var started: Date
    var taken: [Taken] = []
    /// The ladder as it stands now, the leading diagnosis first.
    var ladder: [String] = []
    /// The ladder after each step taken: `ladders[i]` is how it stood once
    /// `taken[i]` was done.
    var ladders: [[String]] = []
    var decision: Decision? = nil
    var finished: Date? = nil
    var score: CaseScore? = nil

    init(caseID: UUID, started: Date = Date()) {
        self.caseID = caseID
        self.started = started
    }

    // MARK: the clock

    /// Minutes used on the case's clock.
    var minutesUsed: Int { taken.last?.at ?? 0 }

    func isOver(_ file: CaseFile) -> Bool { minutesUsed > file.budgetMinutes }

    func hasTaken(_ stepID: String) -> Bool { taken.contains { $0.stepID == stepID } }

    var isFinished: Bool { finished != nil }

    // MARK: acting

    /// Takes a step: spends its minutes and copies the ladder. False (and
    /// nothing changes) when it was taken already, is not in the case, or
    /// the case is over. Going past the budget is allowed; the debrief
    /// counts it.
    @discardableResult
    mutating func take(_ stepID: String, in file: CaseFile) -> Bool {
        guard !isFinished, !hasTaken(stepID), let step = file.step(stepID) else { return false }
        taken.append(Taken(stepID: stepID, at: minutesUsed + max(0, step.minutes)))
        ladders.append(ladder)
        return true
    }

    /// Sets the ladder: the names in order, each once, at most three.
    mutating func setLadder(_ names: [String]) {
        guard !isFinished else { return }
        var seen: Set<String> = []
        var out: [String] = []
        for name in names {
            let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key: String = CaseNames.normal(trimmed)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(trimmed)
            if out.count == Self.rungs { break }
        }
        ladder = out
    }

    /// Puts a name on the ladder: picked from the list, or typed and matched
    /// to the case's own name for it. A full ladder drops its last rung.
    mutating func add(_ name: String, in file: CaseFile) {
        let named: String = file.resolve(name) ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ladder.contains(where: { CaseNames.same($0, named) }) else { return }
        var next: [String] = ladder
        if next.count >= Self.rungs { next.removeLast() }
        next.append(named)
        setLadder(next)
    }

    mutating func remove(_ name: String) {
        setLadder(ladder.filter { !CaseNames.same($0, name) })
    }

    /// Moves a rung up (towards the lead) or down.
    mutating func move(_ name: String, up: Bool) {
        guard let at = ladder.firstIndex(where: { CaseNames.same($0, name) }) else { return }
        let to: Int = up ? at - 1 : at + 1
        guard ladder.indices.contains(to) else { return }
        var next = ladder
        next.swapAt(at, to)
        setLadder(next)
    }

    /// The decision: the leading diagnosis confirmed, the next step and the
    /// reason. Scores the run and closes it.
    mutating func decide(_ decision: Decision, in file: CaseFile, at date: Date = Date()) {
        guard !isFinished else { return }
        self.decision = decision
        finished = date
        score = CaseScore.of(self, in: file)
    }

    var state: State {
        if let score, isFinished { return .discharged(score: score.total) }
        return taken.isEmpty && ladder.isEmpty ? .new : .seen
    }

    // MARK: how the ladder moved

    /// The index into `taken` after which the ladder first led with the
    /// diagnosis; nil if no copy did.
    func firstLed(in file: CaseFile) -> Int? {
        ladders.firstIndex { ($0.first).map(file.isDiagnosis) ?? false }
    }

    /// The index into `taken` of the case's turning step; nil if never taken.
    func turningIndex(in file: CaseFile) -> Int? {
        taken.firstIndex { $0.stepID == file.turningStep }
    }
}

/// Where a case stands, for a run that may not exist.
extension Optional where Wrapped == CaseRun {
    var caseState: CaseRun.State { self?.state ?? .new }
}
