import Foundation

/// One OSCE station's checklist — a title plus the ordered steps an
/// examiner would tick off. Mirrors the checklist objects the web app
/// builds from a mark sheet (`state.osceChecklists`), just without the
/// PDF/vision generation step: here a set is authored as plain text.
struct OsceChecklist: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var steps: [String]
}

/// One run through a station, in order. The steps of a station are done in a
/// fixed order, so there is no marking a step wrong and carrying on: either
/// the step was got ("I got it", on to the next) or the attempt is over and
/// the station starts again from step 1 ("Start over").
///
/// Every start over is kept as a miss on the step it happened at, so a step
/// that keeps tripping somebody up still shows once the station is done.
struct OsceRun: Hashable {
    let stepCount: Int
    /// The step being recalled now, from 0.
    private(set) var stepIndex: Int
    /// The step each start over happened at, in the order they happened. A
    /// step can appear more than once.
    private(set) var misses: [Int]
    /// Every step got, in order, in one attempt.
    private(set) var complete: Bool

    init(stepCount: Int, stepIndex: Int = 0, misses: [Int] = [], complete: Bool = false) {
        self.stepCount = max(0, stepCount)
        self.stepIndex = min(max(0, stepIndex), max(0, stepCount - 1))
        self.misses = misses.filter { $0 >= 0 && $0 < stepCount }
        self.complete = complete || stepCount == 0
    }

    /// How many times the station was started over.
    var restarts: Int { misses.count }

    /// Got the step: on to the next one, or done after the last.
    mutating func gotIt() {
        guard !complete else { return }
        if stepIndex >= stepCount - 1 {
            complete = true
        } else {
            stepIndex += 1
        }
    }

    /// Missed the step: note it, and go back to step 1.
    mutating func startOver() {
        guard !complete, stepCount > 0 else { return }
        misses.append(stepIndex)
        stepIndex = 0
    }

    /// The steps that caused a start over, most often first, then in station
    /// order: `(step, times)`.
    var weakSteps: [(step: Int, times: Int)] {
        var counts: [Int: Int] = [:]
        for step in misses { counts[step, default: 0] += 1 }
        let pairs: [(step: Int, times: Int)] = counts.map { (step: $0.key, times: $0.value) }
        return pairs.sorted { a, b in
            if a.times != b.times { return a.times > b.times }
            return a.step < b.step
        }
    }
}
