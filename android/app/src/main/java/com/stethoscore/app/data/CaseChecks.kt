package com.stethoscore.app.data

import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.accuracy.AccuracyRules
import kotlin.math.ceil

// What a case must be before it can be played, checked without a model
// (port of iOS Shared/Cases/CaseChecks.swift):
//
// - the history written out as the clerking note (no step asks the patient anything);
// - 8 to 20 steps, covering both groups, examine and test;
// - at least two key steps (a case turns on a few findings: Page & Bordage);
// - the diagnosis is among the differentials, and each differential has a
//   step that supports it;
// - the turning step is a key step;
// - the clock's budget covers the key steps plus about 30 percent;
// - the next step's options are four or five, keyed, and the key is not the
//   one option that stands out by length;
// - no severe hit from the accuracy engine's rules on what the case asserts.
//
// Also here: the H and L flags on the arrival observations and the results.

object CaseChecks {
    val stepRange: IntRange = 8..20
    const val minimumKeySteps = 2
    /** The budget must cover the key steps' minutes times this. */
    const val budgetMargin = 1.3

    sealed class Problem {
        data class StepCount(val count: Int) : Problem()
        data class MissingGroup(val group: CaseStep.Group) : Problem()
        data class DuplicateStep(val id: String) : Problem()
        data class FewKeySteps(val count: Int) : Problem()
        data object DiagnosisNotInDifferentials : Problem()
        data class Unsupported(val name: String) : Problem()
        data class UnknownStep(val id: String) : Problem()
        data object TurningStepNotKey : Problem()
        data class BudgetShort(val have: Int, val need: Int) : Problem()
        data object NextStepOptions : Problem()
        data object NextStepUnbalanced : Problem()
        data object Teaching : Problem()
        data object NoClerking : Problem()
        data object Blank : Problem()
        data class Accuracy(val detail: String) : Problem()

        /** In words, for a log line or a held case's reason. */
        val said: String get() = when (this) {
            is StepCount -> "$count steps (8 to 20 wanted)"
            is MissingGroup -> "no ${group.label.lowercase()} steps"
            is DuplicateStep -> "step $id twice"
            is FewKeySteps -> "$count key step${if (count == 1) "" else "s"} (2 wanted)"
            DiagnosisNotInDifferentials -> "the diagnosis is not among the differentials"
            is Unsupported -> "nothing supports $name"
            is UnknownStep -> "names a step that is not there ($id)"
            TurningStepNotKey -> "the turning step is not a key step"
            is BudgetShort -> "$have min budget, $need needed"
            NextStepOptions -> "the next step needs four or five options and a key"
            NextStepUnbalanced -> "the right next step stands out by its length"
            Teaching -> "no teaching points"
            NoClerking -> "no written history"
            Blank -> "no complaint or diagnosis"
            is Accuracy -> detail
        }
    }

    /** Every problem with a case; empty means it can be played. */
    fun problems(file: CaseFile): List<Problem> {
        val out = mutableListOf<Problem>()
        if (file.complaint.trimSpaces().isEmpty() || file.diagnosis.name.trimSpaces().isEmpty()) out += Problem.Blank
        if (file.clerking.presenting.trimSpaces().isEmpty() || file.clerking.history.trimSpaces().isEmpty()) out += Problem.NoClerking
        if (file.steps.size !in stepRange) out += Problem.StepCount(file.steps.size)
        for (group in CaseStep.Group.entries) if (file.steps.none { it.group == group }) out += Problem.MissingGroup(group)
        val ids = mutableSetOf<String>()
        for (step in file.steps) {
            if (step.id in ids) out += Problem.DuplicateStep(step.id)
            ids += step.id
        }
        val key = file.keySteps
        if (key.size < minimumKeySteps) out += Problem.FewKeySteps(key.size)
        if (file.diagnosisDifferential == null) out += Problem.DiagnosisNotInDifferentials
        for (d in file.differentials) {
            for (id in d.supportedBy + d.againstBy) if (id !in ids) out += Problem.UnknownStep(id)
            if (d.supportedBy.none { it in ids }) out += Problem.Unsupported(d.name)
        }
        if (file.step(file.turningStep)?.value != CaseStep.Yield.key) out += Problem.TurningStepNotKey
        val need = budgetNeeded(file)
        if (file.budgetMinutes < need) out += Problem.BudgetShort(file.budgetMinutes, need)
        val next = file.nextStep
        if (next.options.size !in 4..5 || next.key !in next.options.indices || next.options.any { it.trimSpaces().isEmpty() }) {
            out += Problem.NextStepOptions
        } else if (!lengthBalanced(next.options, next.key)) {
            out += Problem.NextStepUnbalanced
        }
        if (file.teaching.none { it.trimSpaces().isNotEmpty() }) out += Problem.Teaching
        for (hit in severeHits(file)) out += Problem.Accuracy(hit.detail)
        return out
    }

    fun isPlayable(file: CaseFile): Boolean = problems(file).isEmpty()

    /** The key steps' minutes plus the margin, rounded up. */
    fun budgetNeeded(file: CaseFile): Int {
        val key = file.keySteps.sumOf { maxOf(0, it.minutes) }
        return ceil(key.toDouble() * budgetMargin).toInt()
    }

    /**
     * MCQGenerator.lengthBalanced on iOS (the Questions port owns that file):
     * refuse a key that is both the single longest option and meaningfully
     * longer than the rest, so "pick the longest" stays a losing strategy.
     */
    fun lengthBalanced(options: List<String>, correctIndex: Int): Boolean {
        val lens = options.map { it.trim().codePointCount(0, it.trim().length) }
        if (correctIndex !in lens.indices) return false
        val correctLen = lens[correctIndex]
        val others = lens.filterIndexed { i, _ -> i != correctIndex }
        if (others.isEmpty()) return false
        val maxOther = others.max()
        val avgOther = others.sum().toDouble() / others.size
        return !(correctLen > maxOther && correctLen.toDouble() > avgOther * 1.3)
    }

    // MARK: the accuracy engine

    /** The case as the accuracy engine reads it: one item of kind "case", whose text is what the case asserts. */
    fun item(file: CaseFile, source: String = ""): AccuracyItem = AccuracyItem.caseFile(file, source)

    fun severeHits(file: CaseFile): List<AccuracyRules.Hit> = AccuracyRules.hits(item(file)).filter { it.isSevere }

    // MARK: before playing

    /**
     * What a writer's case needs before the checks, fixed where the fix is
     * mechanical and changes no medicine: steps with no id are numbered, a
     * budget short of the key steps is raised to cover them, the next step's
     * options are trimmed, and a turning step that names nothing falls to the
     * first key step.
     */
    fun tidied(file: CaseFile): CaseFile {
        val used = mutableSetOf<String>()
        val steps = file.steps.mapIndexed { i, step ->
            var id = step.id.trimSpaces()
            if (id.isEmpty() || id in used) id = "s${i + 1}"
            while (id in used) id += "x"
            used += id
            step.copy(id = id, minutes = step.minutes.coerceIn(1, 60))
        }
        var out = file.copy(
            steps = steps,
            nextStep = file.nextStep.copy(options = file.nextStep.options.map { it.trim() }),
            teaching = file.teaching.map { it.trim() }.filter { it.isNotEmpty() },
        )
        if (out.step(out.turningStep) == null) out.keySteps.firstOrNull()?.let { out = out.copy(turningStep = it.id) }
        return out.copy(budgetMinutes = maxOf(out.budgetMinutes, budgetNeeded(out)))
    }

    data class Dropped(val title: String, val why: List<String>)
    data class Screened(val kept: List<CaseFile>, val dropped: List<Dropped>)

    /**
     * The writers' cases sorted: the playable kept, marked passed; the rest
     * dropped with their reasons. A kept case is held only when the
     * verification layer's checkers later grade it Flagged.
     */
    fun screen(files: List<CaseFile>): Screened {
        val kept = mutableListOf<CaseFile>()
        val dropped = mutableListOf<Dropped>()
        for (raw in files) {
            val file = tidied(raw)
            val found = problems(file)
            if (found.isEmpty()) kept += file.copy(verification = CaseFile.Verification.passed)
            else dropped += Dropped(file.title, found.map { it.said })
        }
        return Screened(kept, dropped)
    }

    /** The status line after writing: how many were kept, and why any were not. */
    fun note(kept: Int, dropped: Int): String {
        if (dropped <= 0) return " Structure and accuracy checks passed."
        val plural = if (dropped == 1) "" else "s"
        return " $dropped case$plural failed the structure or accuracy checks and ${if (dropped == 1) "was" else "were"} left out."
    }

    /** Whether a case is kept off the list: held by the checks, or graded Flagged by the verification layer. */
    fun isHeld(file: CaseFile, flagged: Set<String>): Boolean =
        file.verification == CaseFile.Verification.held || file.id.uppercase() in flagged || file.id in flagged
}

/** The H and L marks on the chart. */
object CaseChart {
    enum class Flag(val rawValue: String, val spoken: String) { high("H", "high"), low("L", "low") }

    /**
     * The same thresholds the question screen's chart flags observations by,
     * so a patient reads the same in Cases and in a question: heart rate
     * 60-100, breathing 12-20, systolic 90-139 with diastolic under 90,
     * temperature 35-37.9, saturation from 94.
     */
    fun flag(obs: CaseFile.Obs): Flag? {
        val v = obs.value
        return when (obs.sign) {
            CaseFile.Obs.Sign.hr -> if (v > 100) Flag.high else if (v < 60) Flag.low else null
            CaseFile.Obs.Sign.rr -> if (v > 20) Flag.high else if (v < 12) Flag.low else null
            CaseFile.Obs.Sign.spo2 -> if (v < 94) Flag.low else null
            CaseFile.Obs.Sign.temp -> if (v >= 38) Flag.high else if (v < 35) Flag.low else null
            CaseFile.Obs.Sign.bp -> if (v >= 140 || (obs.second ?: 0.0) >= 90) Flag.high else if (v < 90) Flag.low else null
            CaseFile.Obs.Sign.gcs -> if (v < 15) Flag.low else null
        }
    }

    /**
     * A result against the accuracy engine's own reference range for that
     * test in that unit (read as the question screen's chart reads it,
     * PatientChart.labFlag on iOS), else against the range the case gives;
     * null when neither says.
     */
    fun flag(result: CaseStep.LabResult): Flag? {
        labFlag(result.name, result.value, result.unit)?.let { return it }
        val range = referenceRange(result) ?: return null
        if (result.value > range.second) return Flag.high
        if (result.value < range.first) return Flag.low
        return null
    }

    /** PatientChart.labFlag: high or low against AccuracyRules' range for the analyte in that unit; null when the table does not know it. */
    fun labFlag(name: String, value: Double, unit: String): Flag? {
        val analyte = AccuracyRules.labNames[name.lowercase()] ?: return null
        val u = unit.lowercase().replace("μ", "µ").replace(" ", "")
        val normal = AccuracyRules.unitAliases[u] ?: return null
        val r = AccuracyRules.labs[analyte]?.get(normal) ?: return null
        if (r.size != 4) return null
        if (value < r[2]) return Flag.low
        if (value > r[3]) return Flag.high
        return null
    }

    fun referenceRange(result: CaseStep.LabResult): Pair<Double, Double>? {
        val name = result.name.lowercase().trimSpaces()
        val unit = result.unit.lowercase().replace("μ", "µ").trimSpaces()
        val analyte = AccuracyRules.labNames[name]
        val row = analyte?.let { AccuracyRules.labs[it] }?.get(AccuracyRules.unitAliases[unit] ?: unit)
        if (row != null && row.size == 4) return row[2] to row[3]
        val low = result.low; val high = result.high
        if (low != null && high != null && high > low) return low to high
        return null
    }
}
