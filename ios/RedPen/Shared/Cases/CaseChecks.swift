import Foundation

// What a case must be before it can be played, checked without a model:
//
// - the history written out as the clerking note (the patient is never
//   questioned: no step asks them anything);
// - 8 to 20 steps, covering both groups, examine and test;
// - at least two key steps (a case turns on a few findings: Page & Bordage);
// - the diagnosis is among the differentials, and each differential has a
//   step that supports it;
// - the turning step is a key step;
// - the clock's budget covers the key steps plus about 30 percent;
// - the next step's options are four or five, keyed, and the key is not the
//   one option that stands out by length (MCQGenerator.lengthBalanced);
// - no severe hit from the accuracy engine's rules on what the case asserts
//   (lab values that cannot be, doses outside any usual range, retired
//   practice, look-alike drugs: AccuracyRules).
//
// Then the verification layer takes it, as an item of kind "case". Also here:
// the H and L flags on the arrival observations and the results.
//
// Foundation only; tested in the "cases" suite.

enum CaseChecks {
    static let stepRange: ClosedRange<Int> = 8...20
    static let minimumKeySteps = 2
    /// The budget must cover the key steps' minutes times this.
    static let budgetMargin = 1.3

    enum Problem: Equatable, Sendable {
        case stepCount(Int)
        case missingGroup(CaseStep.Group)
        case duplicateStep(String)
        case fewKeySteps(Int)
        case diagnosisNotInDifferentials
        case unsupported(String)
        case unknownStep(String)
        case turningStepNotKey
        case budgetShort(have: Int, need: Int)
        case nextStepOptions
        case nextStepUnbalanced
        case teaching
        case noClerking
        case blank
        case accuracy(String)

        /// In words, for a log line or a held case's reason.
        var said: String {
            switch self {
            case .stepCount(let n): return "\(n) steps (8 to 20 wanted)"
            case .missingGroup(let g): return "no \(g.label.lowercased()) steps"
            case .duplicateStep(let id): return "step \(id) twice"
            case .fewKeySteps(let n): return "\(n) key step\(n == 1 ? "" : "s") (2 wanted)"
            case .diagnosisNotInDifferentials: return "the diagnosis is not among the differentials"
            case .unsupported(let name): return "nothing supports \(name)"
            case .unknownStep(let id): return "names a step that is not there (\(id))"
            case .turningStepNotKey: return "the turning step is not a key step"
            case .budgetShort(let have, let need): return "\(have) min budget, \(need) needed"
            case .nextStepOptions: return "the next step needs four or five options and a key"
            case .nextStepUnbalanced: return "the right next step stands out by its length"
            case .teaching: return "no teaching points"
            case .noClerking: return "no written history"
            case .blank: return "no complaint or diagnosis"
            case .accuracy(let detail): return detail
            }
        }
    }

    /// Every problem with a case; empty means it can be played.
    static func problems(_ file: CaseFile) -> [Problem] {
        var out: [Problem] = []
        if file.complaint.trimmingCharacters(in: .whitespaces).isEmpty
            || file.diagnosis.name.trimmingCharacters(in: .whitespaces).isEmpty { out.append(.blank) }
        if file.clerking.presenting.trimmingCharacters(in: .whitespaces).isEmpty
            || file.clerking.history.trimmingCharacters(in: .whitespaces).isEmpty { out.append(.noClerking) }
        if !stepRange.contains(file.steps.count) { out.append(.stepCount(file.steps.count)) }
        for group in CaseStep.Group.allCases where !file.steps.contains(where: { $0.group == group }) {
            out.append(.missingGroup(group))
        }
        var ids: Set<String> = []
        for step in file.steps {
            if ids.contains(step.id) { out.append(.duplicateStep(step.id)) }
            ids.insert(step.id)
        }
        let key: [CaseStep] = file.keySteps
        if key.count < minimumKeySteps { out.append(.fewKeySteps(key.count)) }
        if file.diagnosisDifferential == nil { out.append(.diagnosisNotInDifferentials) }
        for d in file.differentials {
            for id in d.supportedBy + d.againstBy where !ids.contains(id) { out.append(.unknownStep(id)) }
            if !d.supportedBy.contains(where: ids.contains) { out.append(.unsupported(d.name)) }
        }
        if file.step(file.turningStep)?.value != .key { out.append(.turningStepNotKey) }
        let need: Int = budgetNeeded(file)
        if file.budgetMinutes < need { out.append(.budgetShort(have: file.budgetMinutes, need: need)) }
        let next = file.nextStep
        if !(4...5).contains(next.options.count) || !next.options.indices.contains(next.key)
            || next.options.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            out.append(.nextStepOptions)
        } else if !MCQGenerator.lengthBalanced(next.options, correctIndex: next.key) {
            out.append(.nextStepUnbalanced)
        }
        if file.teaching.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).isEmpty { out.append(.teaching) }
        for hit in severeHits(file) { out.append(.accuracy(hit.detail)) }
        return out
    }

    static func isPlayable(_ file: CaseFile) -> Bool { problems(file).isEmpty }

    /// The key steps' minutes plus the margin, rounded up.
    static func budgetNeeded(_ file: CaseFile) -> Int {
        let key: Int = file.keySteps.reduce(0) { $0 + max(0, $1.minutes) }
        return Int((Double(key) * budgetMargin).rounded(.up))
    }

    // MARK: the accuracy engine

    /// The case as the accuracy engine reads it: one item of kind "case",
    /// whose text is what the case asserts (CaseFile.assertedText).
    static func item(_ file: CaseFile, source: String = "") -> AccuracyItem {
        AccuracyItem.caseFile(file, source: source)
    }

    static func severeHits(_ file: CaseFile) -> [AccuracyRules.Hit] {
        AccuracyRules.hits(item(file)).filter(\.isSevere)
    }

    // MARK: before playing

    /// What a writer's case needs before the checks, fixed where the fix is
    /// mechanical and changes no medicine: steps with no id are numbered, a
    /// budget short of the key steps is raised to cover them, the next step's
    /// options are trimmed, and a turning step that names nothing falls to
    /// the first key step.
    static func tidied(_ file: CaseFile) -> CaseFile {
        var out = file
        var used: Set<String> = []
        for i in out.steps.indices {
            var id: String = out.steps[i].id.trimmingCharacters(in: .whitespaces)
            if id.isEmpty || used.contains(id) { id = "s\(i + 1)" }
            while used.contains(id) { id += "x" }
            used.insert(id)
            out.steps[i].id = id
            out.steps[i].minutes = min(max(out.steps[i].minutes, 1), 60)
        }
        out.nextStep.options = out.nextStep.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        out.teaching = out.teaching.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if out.step(out.turningStep) == nil, let first = out.keySteps.first { out.turningStep = first.id }
        out.budgetMinutes = max(out.budgetMinutes, budgetNeeded(out))
        return out
    }

    /// The writers' cases sorted: the playable kept, marked passed; the rest
    /// dropped with their reasons. A severe rule hit is a problem here, so a
    /// kept case is held only when the verification layer's checkers later
    /// grade it Flagged (AccuracyHolds).
    static func screen(_ files: [CaseFile]) -> (kept: [CaseFile], dropped: [(title: String, why: [String])]) {
        var kept: [CaseFile] = []
        var dropped: [(title: String, why: [String])] = []
        for raw in files {
            var file: CaseFile = tidied(raw)
            let found: [Problem] = problems(file)
            if found.isEmpty {
                file.verification = .passed
                kept.append(file)
            } else {
                dropped.append((file.title, found.map(\.said)))
            }
        }
        return (kept, dropped)
    }

    /// The status line after writing: how many were kept, and why any were not.
    static func note(kept: Int, dropped: Int) -> String {
        guard dropped > 0 else { return " Structure and accuracy checks passed." }
        let plural: String = dropped == 1 ? "" : "s"
        return " \(dropped) case\(plural) failed the structure or accuracy checks and \(dropped == 1 ? "was" : "were") left out."
    }

    /// Whether a case is kept off the list: held by the checks, or graded
    /// Flagged by the verification layer.
    static func isHeld(_ file: CaseFile, flagged: Set<String>) -> Bool {
        file.verification == .held || flagged.contains(file.id.uuidString)
    }
}

/// The H and L marks on the chart.
enum CaseChart {
    enum Flag: String, Sendable {
        case high = "H", low = "L"

        var spoken: String { self == .high ? "high" : "low" }
    }

    /// The same thresholds the question screen's chart flags observations
    /// by (PatientChart), so a patient reads the same in Cases and in a
    /// question: heart rate 60-100, breathing 12-20, systolic 90-139 with
    /// diastolic under 90, temperature 35-37.9, saturation from 94.
    static func flag(_ obs: CaseFile.Obs) -> Flag? {
        let v: Double = obs.value
        switch obs.sign {
        case .hr: return v > 100 ? .high : (v < 60 ? .low : nil)
        case .rr: return v > 20 ? .high : (v < 12 ? .low : nil)
        case .spo2: return v < 94 ? .low : nil
        case .temp: return v >= 38 ? .high : (v < 35 ? .low : nil)
        case .bp: return v >= 140 || (obs.second ?? 0) >= 90 ? .high : (v < 90 ? .low : nil)
        case .gcs: return v < 15 ? .low : nil
        }
    }

    /// A result against the accuracy engine's own reference range for that
    /// test in that unit (AccuracyRules.labs, read as the question screen's
    /// chart reads it: PatientChart.labFlag), else against the range the case
    /// gives; nil when neither says.
    static func flag(_ result: CaseStep.LabResult) -> Flag? {
        if let known = PatientChart.labFlag(name: result.name, value: result.value, unit: result.unit) {
            return known == .high ? .high : .low
        }
        guard let range = referenceRange(result) else { return nil }
        if result.value > range.high { return .high }
        if result.value < range.low { return .low }
        return nil
    }

    static func referenceRange(_ result: CaseStep.LabResult) -> (low: Double, high: Double)? {
        let name: String = result.name.lowercased().trimmingCharacters(in: .whitespaces)
        let unit: String = result.unit.lowercased().replacingOccurrences(of: "\u{03BC}", with: "\u{00B5}")
            .trimmingCharacters(in: .whitespaces)
        if let analyte = AccuracyRules.labNames[name],
           let table = AccuracyRules.labs[analyte],
           let row = table[AccuracyRules.unitAliases[unit] ?? unit], row.count == 4 {
            return (row[2], row[3])
        }
        if let low = result.low, let high = result.high, high > low { return (low, high) }
        return nil
    }
}
