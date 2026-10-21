import Foundation

// The discharge summary after a case, worked out from the case and the run:
// what was missed that could kill, whether the diagnosis was right and what
// separates it from the runner-up, the key findings found, the turning point
// against when the student's ladder actually moved, the time and the
// low-yield steps, and the teaching. Also the cards made from what was missed
// and the note for Ideas.
//
// Feedback on the reasoning, not only the answer (Bowen 2006): the turning
// point shows where the case should have tipped, beside where the student's
// thinking did.
//
// Foundation only; tested in the "cases" suite.

struct CaseDebrief {
    let file: CaseFile
    let run: CaseRun

    /// A step, and whether the student took it.
    struct Item: Hashable {
        var step: CaseStep
        var found: Bool
    }

    /// Where the case turned, against where the student's ladder did.
    enum Turning: Equatable {
        /// The ladder led with the diagnosis by the turning step, or at it.
        case onTime(turning: String, led: String)
        /// The ladder led with it, but only after a later step.
        case late(turning: String, led: String)
        /// The turning step was taken, but the ladder never led with it.
        case never(turning: String)
        /// The turning step was never taken.
        case missedStep(turning: String)
        /// The ladder led with it only at the decision, after the last step.
        case atDecision(turning: String)
    }

    private var taken: Set<String> { Set(run.taken.map(\.stepID)) }

    // MARK: the parts of the summary, in order

    /// Red flags not found, the must-not-miss first.
    var missedRedFlags: [CaseStep] {
        let missed: [CaseStep] = file.redFlagSteps.filter { !taken.contains($0.id) }
        return missed.filter(\.mustNotMiss) + missed.filter { !$0.mustNotMiss }
    }

    var diagnosisRight: Bool { run.decision.map { file.isDiagnosis($0.diagnosis) } ?? false }

    var nextStepRight: Bool { run.decision?.nextStep == file.nextStep.key }

    var chosenDiagnosis: String { run.decision?.diagnosis ?? "" }

    var chosenNextStep: String? {
        guard let i = run.decision?.nextStep, file.nextStep.options.indices.contains(i) else { return nil }
        return file.nextStep.options[i]
    }

    var rightNextStep: String {
        file.nextStep.options.indices.contains(file.nextStep.key) ? file.nextStep.options[file.nextStep.key] : ""
    }

    /// The findings that tell the diagnosis from the runner-up: the steps for
    /// the diagnosis that argue against the runner-up, else the ones for the
    /// diagnosis that the runner-up does not share. At most four.
    var separating: [Item] {
        guard let dx = file.diagnosisDifferential else { return [] }
        let other: Differential? = file.runnerUp
        let against: Set<String> = Set(other?.againstBy ?? [])
        let shared: Set<String> = Set(other?.supportedBy ?? [])
        var ids: [String] = dx.supportedBy.filter { against.contains($0) }
        if ids.isEmpty { ids = dx.supportedBy.filter { !shared.contains($0) } }
        if ids.isEmpty { ids = dx.supportedBy }
        return ids.prefix(4).compactMap { id in file.step(id).map { Item(step: $0, found: taken.contains(id)) } }
    }

    var keyFindings: [Item] {
        file.keySteps.map { Item(step: $0, found: taken.contains($0.id)) }
    }

    var keyFound: Int { keyFindings.filter(\.found).count }

    var turning: Turning {
        let turning: String = file.step(file.turningStep)?.label ?? file.turningStep
        guard let at = run.turningIndex(in: file) else { return .missedStep(turning: turning) }
        if let led = run.firstLed(in: file) {
            let label: String = file.step(run.taken[led].stepID)?.label ?? ""
            return led <= at ? .onTime(turning: turning, led: label) : .late(turning: turning, led: label)
        }
        if let top = run.ladder.first, file.isDiagnosis(top) { return .atDecision(turning: turning) }
        return .never(turning: turning)
    }

    /// The turning point in a sentence.
    var turningSaid: String {
        switch turning {
        case .onTime(let t, let led):
            return "The diagnosis should have led after \u{201C}\(t)\u{201D}. Your ladder put it first after \u{201C}\(led)\u{201D}, in time."
        case .late(let t, let led):
            return "The diagnosis should have led after \u{201C}\(t)\u{201D}. Your ladder put it first only after \u{201C}\(led)\u{201D}."
        case .never(let t):
            return "The diagnosis should have led after \u{201C}\(t)\u{201D}. Your ladder never put it first."
        case .missedStep(let t):
            return "The case turned on \u{201C}\(t)\u{201D}, which you did not do."
        case .atDecision(let t):
            return "The diagnosis should have led after \u{201C}\(t)\u{201D}. Your ladder put it first only at the decision."
        }
    }

    var minutesUsed: Int { run.minutesUsed }

    var overBudget: Bool { run.isOver(file) }

    /// The low-yield steps taken, each with why it added little here.
    var lowYield: [CaseStep] { CaseScore.lowYieldTaken(run, in: file) }

    var score: CaseScore { run.score ?? CaseScore.of(run, in: file) }

    // MARK: what the buttons make

    /// The missed key findings and red flags, once each, in the case's order.
    var missed: [CaseStep] {
        file.steps.filter { !taken.contains($0.id) && ($0.value == .key || $0.redFlag) }
    }

    /// One basic card per missed key finding or red flag: the patient and the
    /// step on the front, what it shows on the back, why it matters as the
    /// card's "why". Tagged so they can be found together.
    var cards: [AnkiCard] {
        let who: String = [file.patient.ageSex, file.complaint].filter { !$0.isEmpty }.joined(separator: ", ")
        return missed.map { step in
            var card = AnkiCard(type: .qa)
            card.front = "\(who.isEmpty ? file.title : who) \u{2014} \(step.label): what do you find, and why does it matter?"
            card.bullets = [step.finding] + step.results.map(\.said)
            var why: String = step.note
            if step.mustNotMiss { why = "Must not miss. " + why }
            card.why = why.trimmingCharacters(in: .whitespaces)
            card.tags = ["Cases", file.diagnosis.name].filter { !$0.isEmpty }
            return card
        }
    }

    /// The note for Ideas, in Markdown: the patient, the diagnosis and what
    /// separates it, the red flags, and the teaching with its source.
    var ideaText: String {
        var lines: [String] = []
        lines.append("**\(file.patient.ageSex)** \u{00B7} \(file.setting.label) \u{00B7} \u{201C}\(file.complaint)\u{201D}")
        lines.append("")
        lines.append("**Diagnosis:** \(file.diagnosis.name)")
        if let other = file.runnerUp {
            lines.append("**Runner-up:** \(other.name)")
        }
        let telling: [Item] = separating
        if !telling.isEmpty {
            lines.append("")
            lines.append("What tells them apart:")
            for item in telling { lines.append("- \(item.step.label): \(item.step.finding)") }
        }
        let flags: [CaseStep] = file.redFlagSteps
        if !flags.isEmpty {
            lines.append("")
            lines.append("Red flags:")
            for step in flags { lines.append("- \(step.label): \(step.finding)") }
        }
        if !rightNextStep.isEmpty {
            lines.append("")
            lines.append("**Next step:** \(rightNextStep). \(file.nextStep.why)")
        }
        if !file.teaching.isEmpty {
            lines.append("")
            for point in file.teaching { lines.append("- \(point)") }
            let cited: String = file.source.cited
            if !cited.isEmpty { lines.append("") ; lines.append("_Source: \(cited)_") }
        }
        return lines.joined(separator: "\n")
    }

    /// The idea's title: "Case: <diagnosis>".
    var ideaTitle: String { "Case: " + (file.diagnosis.name.isEmpty ? file.title : file.diagnosis.name) }
}
