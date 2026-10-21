package com.stethoscore.app.data

// The discharge summary after a case, worked out from the case and the run:
// what was missed that could kill, whether the diagnosis was right and what
// separates it from the runner-up, the key findings found, the turning point
// against when the student's ladder actually moved, the time and the
// low-yield steps, and the teaching. Also the cards made from what was missed
// and the note for Ideas. Port of iOS Shared/Cases/CaseDebrief.swift.
//
// Feedback on the reasoning, not only the answer (Bowen 2006): the turning
// point shows where the case should have tipped, beside where the student's
// thinking did.

class CaseDebrief(val file: CaseFile, val run: CaseRun) {

    /** A step, and whether the student took it. */
    data class Item(val step: CaseStep, val found: Boolean)

    /** Where the case turned, against where the student's ladder did. */
    sealed class Turning {
        /** The ladder led with the diagnosis by the turning step, or at it. */
        data class OnTime(val turning: String, val led: String) : Turning()
        /** The ladder led with it, but only after a later step. */
        data class Late(val turning: String, val led: String) : Turning()
        /** The turning step was taken, but the ladder never led with it. */
        data class Never(val turning: String) : Turning()
        /** The turning step was never taken. */
        data class MissedStep(val turning: String) : Turning()
        /** The ladder led with it only at the decision, after the last step. */
        data class AtDecision(val turning: String) : Turning()
    }

    private val taken: Set<String> get() = run.taken.map { it.stepID }.toSet()

    // MARK: the parts of the summary, in order

    /** Red flags not found, the must-not-miss first. */
    val missedRedFlags: List<CaseStep> get() {
        val missed = file.redFlagSteps.filter { it.id !in taken }
        return missed.filter { it.mustNotMiss } + missed.filter { !it.mustNotMiss }
    }

    val diagnosisRight: Boolean get() = run.decision?.let { file.isDiagnosis(it.diagnosis) } ?: false

    val nextStepRight: Boolean get() = run.decision?.nextStep == file.nextStep.key

    val chosenDiagnosis: String get() = run.decision?.diagnosis ?: ""

    val chosenNextStep: String? get() {
        val i = run.decision?.nextStep ?: return null
        return file.nextStep.options.getOrNull(i)
    }

    val rightNextStep: String get() = file.nextStep.options.getOrNull(file.nextStep.key) ?: ""

    /**
     * The findings that tell the diagnosis from the runner-up: the steps for
     * the diagnosis that argue against the runner-up, else the ones for the
     * diagnosis that the runner-up does not share. At most four.
     */
    val separating: List<Item> get() {
        val dx = file.diagnosisDifferential ?: return emptyList()
        val other = file.runnerUp
        val against = (other?.againstBy ?: emptyList()).toSet()
        val shared = (other?.supportedBy ?: emptyList()).toSet()
        var ids = dx.supportedBy.filter { it in against }
        if (ids.isEmpty()) ids = dx.supportedBy.filter { it !in shared }
        if (ids.isEmpty()) ids = dx.supportedBy
        return ids.take(4).mapNotNull { id -> file.step(id)?.let { Item(it, id in taken) } }
    }

    val keyFindings: List<Item> get() = file.keySteps.map { Item(it, it.id in taken) }

    val keyFound: Int get() = keyFindings.count { it.found }

    val turning: Turning get() {
        val turning = file.step(file.turningStep)?.label ?: file.turningStep
        val at = run.turningIndex(file) ?: return Turning.MissedStep(turning)
        val led = run.firstLed(file)
        if (led != null) {
            val label = file.step(run.taken[led].stepID)?.label ?: ""
            return if (led <= at) Turning.OnTime(turning, label) else Turning.Late(turning, label)
        }
        val top = run.ladder.firstOrNull()
        if (top != null && file.isDiagnosis(top)) return Turning.AtDecision(turning)
        return Turning.Never(turning)
    }

    /** The turning point in a sentence. */
    val turningSaid: String get() = when (val t = turning) {
        is Turning.OnTime -> "The diagnosis should have led after “${t.turning}”. Your ladder put it first after “${t.led}”, in time."
        is Turning.Late -> "The diagnosis should have led after “${t.turning}”. Your ladder put it first only after “${t.led}”."
        is Turning.Never -> "The diagnosis should have led after “${t.turning}”. Your ladder never put it first."
        is Turning.MissedStep -> "The case turned on “${t.turning}”, which you did not do."
        is Turning.AtDecision -> "The diagnosis should have led after “${t.turning}”. Your ladder put it first only at the decision."
    }

    val minutesUsed: Int get() = run.minutesUsed

    val overBudget: Boolean get() = run.isOver(file)

    /** The low-yield steps taken, each with why it added little here. */
    val lowYield: List<CaseStep> get() = CaseScore.lowYieldTaken(run, file)

    val score: CaseScore get() = run.score ?: CaseScore.of(run, file)

    // MARK: what the buttons make

    /** The missed key findings and red flags, once each, in the case's order. */
    val missed: List<CaseStep> get() = file.steps.filter { it.id !in taken && (it.value == CaseStep.Yield.key || it.redFlag) }

    /**
     * One basic card per missed key finding or red flag: the patient and the
     * step on the front, what it shows on the back, why it matters as the
     * card's "why". Tagged so they can be found together.
     */
    val cards: List<AnkiCard> get() {
        val who = listOf(file.patient.ageSex, file.complaint).filter { it.isNotEmpty() }.joinToString(", ")
        return missed.map { step ->
            var why = step.note
            if (step.mustNotMiss) why = "Must not miss. $why"
            AnkiCard(
                type = AnkiCardType.QA,
                front = "${who.ifEmpty { file.title }} — ${step.label}: what do you find, and why does it matter?",
                bullets = listOf(step.finding) + step.results.map { it.said },
                why = why.trimSpaces(),
                tags = listOf("Cases", file.diagnosis.name).filter { it.isNotEmpty() },
            )
        }
    }

    /** The note for Ideas, in Markdown: the patient, the diagnosis and what separates it, the red flags, and the teaching with its source. */
    val ideaText: String get() {
        val lines = mutableListOf<String>()
        lines += "**${file.patient.ageSex}** · ${file.setting.label} · “${file.complaint}”"
        lines += ""
        lines += "**Diagnosis:** ${file.diagnosis.name}"
        file.runnerUp?.let { lines += "**Runner-up:** ${it.name}" }
        val telling = separating
        if (telling.isNotEmpty()) {
            lines += ""
            lines += "What tells them apart:"
            for (item in telling) lines += "- ${item.step.label}: ${item.step.finding}"
        }
        val flags = file.redFlagSteps
        if (flags.isNotEmpty()) {
            lines += ""
            lines += "Red flags:"
            for (step in flags) lines += "- ${step.label}: ${step.finding}"
        }
        if (rightNextStep.isNotEmpty()) {
            lines += ""
            lines += "**Next step:** $rightNextStep. ${file.nextStep.why}"
        }
        if (file.teaching.isNotEmpty()) {
            lines += ""
            for (point in file.teaching) lines += "- $point"
            val cited = file.source.cited
            if (cited.isNotEmpty()) { lines += ""; lines += "_Source: ${cited}_" }
        }
        return lines.joinToString("\n")
    }

    /** The idea's title: "Case: <diagnosis>". */
    val ideaTitle: String get() = "Case: " + file.diagnosis.name.ifEmpty { file.title }
}
