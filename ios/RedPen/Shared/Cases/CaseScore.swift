import Foundation

// The score out of 100, always shown with its parts and never as a rank:
//
//   diagnosis right            30
//   next step right            20
//   key findings found         25, in proportion
//   red flags found            15, in proportion
//   time                       10: full within the budget with at most one
//                              low-yield step; 2 off for each further one;
//                              5 off over the budget
//
// A must-not-miss red flag left unfound caps the whole at 60, however well
// the rest went: missing what kills is not made up for elsewhere.
//
// Foundation only; tested in the "cases" suite.

struct CaseScore: Codable, Hashable, Sendable {
    static let diagnosisPoints = 30
    static let nextStepPoints = 20
    static let keyPoints = 25
    static let redFlagPoints = 15
    static let timePoints = 10
    static let lowYieldAllowed = 1
    static let lowYieldCost = 2
    static let overBudgetCost = 5
    static let missedMustNotMissCap = 60

    var diagnosis: Int
    var nextStep: Int
    var keyFindings: Int
    var redFlags: Int
    var time: Int
    /// Whether a missed must-not-miss red flag capped the total.
    var capped: Bool

    var sum: Int { diagnosis + nextStep + keyFindings + redFlags + time }

    var total: Int { capped ? min(sum, Self.missedMustNotMissCap) : sum }

    /// The parts, in the order the debrief lists them.
    var parts: [(label: String, points: Int, of: Int)] {
        [("Diagnosis", diagnosis, Self.diagnosisPoints),
         ("Next step", nextStep, Self.nextStepPoints),
         ("Key findings", keyFindings, Self.keyPoints),
         ("Red flags", redFlags, Self.redFlagPoints),
         ("Time", time, Self.timePoints)]
    }

    static func of(_ run: CaseRun, in file: CaseFile) -> CaseScore {
        let taken: Set<String> = Set(run.taken.map(\.stepID))
        let rightDiagnosis: Bool = run.decision.map { file.isDiagnosis($0.diagnosis) } ?? false
        let rightNext: Bool = run.decision.map { $0.nextStep == file.nextStep.key } ?? false

        let key: [CaseStep] = file.keySteps
        let keyFound: Int = key.filter { taken.contains($0.id) }.count
        let flags: [CaseStep] = file.redFlagSteps
        let flagsFound: Int = flags.filter { taken.contains($0.id) }.count

        let missedMustNotMiss: Bool = file.steps.contains { $0.mustNotMiss && !taken.contains($0.id) }

        return CaseScore(diagnosis: rightDiagnosis ? diagnosisPoints : 0,
                         nextStep: rightNext ? nextStepPoints : 0,
                         keyFindings: share(keyFound, of: key.count, points: keyPoints),
                         redFlags: share(flagsFound, of: flags.count, points: redFlagPoints),
                         time: timePart(run, in: file),
                         capped: missedMustNotMiss)
    }

    /// Points in proportion, rounded to the nearest; all of them when there
    /// was nothing of the kind to find.
    static func share(_ found: Int, of total: Int, points: Int) -> Int {
        guard total > 0 else { return points }
        let exact: Double = Double(points) * Double(min(found, total)) / Double(total)
        return Int(exact.rounded())
    }

    static func timePart(_ run: CaseRun, in file: CaseFile) -> Int {
        let lowYield: Int = lowYieldTaken(run, in: file).count
        var points: Int = timePoints - lowYieldCost * max(0, lowYield - lowYieldAllowed)
        if run.isOver(file) { points -= overBudgetCost }
        return max(0, points)
    }

    /// The low-yield steps taken, in the order they were taken.
    static func lowYieldTaken(_ run: CaseRun, in file: CaseFile) -> [CaseStep] {
        run.taken.compactMap { file.step($0.stepID) }.filter { $0.value == .low }
    }
}
