package com.stethoscore.app.data

import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.roundToInt

// One go at a case: which steps were taken and when on the case's clock, the
// differential ladder after each of them, and the decision at the end. Port
// of iOS Shared/Cases/CaseRun.swift.
//
// The ladder is copied after every step, so the debrief can show how it moved
// and when (if ever) the right diagnosis went to the top. Nothing here asks the
// student to update it: a ladder left alone is copied as it stands.
//
// The acting functions change the run in place, as Swift's mutating ones do;
// every list is replaced, never edited, so a copy() is a true copy for the
// screens to hold as state.

data class CaseRun(
    val caseID: String,
    var started: Long = System.currentTimeMillis(),
    var taken: List<Taken> = emptyList(),
    /** The ladder as it stands now, the leading diagnosis first. */
    var ladder: List<String> = emptyList(),
    /** The ladder after each step taken: `ladders[i]` is how it stood once `taken[i]` was done. */
    var ladders: List<List<String>> = emptyList(),
    var decision: Decision? = null,
    var finished: Long? = null,
    var score: CaseScore? = null,
) {
    /** One step taken, and the case clock's minutes once it was done. */
    data class Taken(val stepID: String, val at: Int)

    data class Decision(
        /** The leading diagnosis, as confirmed. */
        val diagnosis: String,
        /** The chosen next step, an index into the case's options. */
        val nextStep: Int,
        /** The optional one-line reason. */
        val reason: String = "",
    )

    /** Where a case stands for the list. */
    sealed class State {
        data object New : State()
        data object Seen : State()
        data class Discharged(val score: Int) : State()
    }

    // MARK: the clock

    /** Minutes used on the case's clock. */
    val minutesUsed: Int get() = taken.lastOrNull()?.at ?: 0

    fun isOver(file: CaseFile): Boolean = minutesUsed > file.budgetMinutes

    fun hasTaken(stepID: String): Boolean = taken.any { it.stepID == stepID }

    val isFinished: Boolean get() = finished != null

    // MARK: acting

    /**
     * Takes a step: spends its minutes and copies the ladder. False (and
     * nothing changes) when it was taken already, is not in the case, or the
     * case is over. Going past the budget is allowed; the debrief counts it.
     */
    fun take(stepID: String, file: CaseFile): Boolean {
        if (isFinished || hasTaken(stepID)) return false
        val step = file.step(stepID) ?: return false
        taken = taken + Taken(stepID, minutesUsed + maxOf(0, step.minutes))
        ladders = ladders + listOf(ladder)
        return true
    }

    /** Sets the ladder: the names in order, each once, at most three. */
    @JvmName("rankLadder") // the name iOS uses; the JVM name keeps clear of the property's setter
    fun setLadder(names: List<String>) {
        if (isFinished) return
        val seen = mutableSetOf<String>()
        val out = mutableListOf<String>()
        for (name in names) {
            val trimmed = name.trim()
            val key = CaseNames.normal(trimmed)
            if (key.isEmpty() || key in seen) continue
            seen += key
            out += trimmed
            if (out.size == RUNGS) break
        }
        ladder = out
    }

    /** Puts a name on the ladder: picked from the list, or typed and matched to the case's own name for it. A full ladder drops its last rung. */
    fun add(name: String, file: CaseFile) {
        val named = file.resolve(name) ?: name.trim()
        if (ladder.any { CaseNames.same(it, named) }) return
        val next = ladder.toMutableList()
        if (next.size >= RUNGS) next.removeAt(next.lastIndex)
        next += named
        setLadder(next)
    }

    fun remove(name: String) = setLadder(ladder.filter { !CaseNames.same(it, name) })

    /** Moves a rung up (towards the lead) or down. */
    fun move(name: String, up: Boolean) {
        val at = ladder.indexOfFirst { CaseNames.same(it, name) }
        if (at < 0) return
        val to = if (up) at - 1 else at + 1
        if (to !in ladder.indices) return
        val next = ladder.toMutableList()
        next[at] = ladder[to]; next[to] = ladder[at]
        setLadder(next)
    }

    /** The decision: the leading diagnosis confirmed, the next step and the reason. Scores the run and closes it. */
    fun decide(decision: Decision, file: CaseFile, at: Long = System.currentTimeMillis()) {
        if (isFinished) return
        this.decision = decision
        finished = at
        score = CaseScore.of(this, file)
    }

    val state: State get() {
        val score = score
        if (score != null && isFinished) return State.Discharged(score.total)
        return if (taken.isEmpty() && ladder.isEmpty()) State.New else State.Seen
    }

    // MARK: how the ladder moved

    /** The index into `taken` after which the ladder first led with the diagnosis; null if no copy did. */
    fun firstLed(file: CaseFile): Int? =
        ladders.indexOfFirst { l -> l.firstOrNull()?.let { file.isDiagnosis(it) } ?: false }.takeIf { it >= 0 }

    /** The index into `taken` of the case's turning step; null if never taken. */
    fun turningIndex(file: CaseFile): Int? = taken.indexOfFirst { it.stepID == file.turningStep }.takeIf { it >= 0 }

    // MARK: kept on the device, in the shape iOS's JSONEncoder writes

    fun toJson(): JSONObject {
        val o = JSONObject()
            .put("caseID", caseID)
            .put("started", swiftDate(started))
            .put("taken", JSONArray(taken.map { JSONObject().put("stepID", it.stepID).put("at", it.at) }))
            .put("ladder", JSONArray(ladder))
            .put("ladders", JSONArray(ladders.map { JSONArray(it) }))
        decision?.let { o.put("decision", JSONObject().put("diagnosis", it.diagnosis).put("nextStep", it.nextStep).put("reason", it.reason)) }
        finished?.let { o.put("finished", swiftDate(it)) }
        score?.let { o.put("score", it.toJson()) }
        return o
    }

    companion object {
        /** The most diagnoses on the ladder at once. */
        const val RUNGS = 3

        private const val SWIFT_EPOCH_MS = 978307200000L
        private fun swiftDate(ms: Long): Double = (ms - SWIFT_EPOCH_MS) / 1000.0

        /** A kept run; null when the text is not one (an older Android session, say). */
        fun fromJson(text: String?): CaseRun? = runCatching {
            val o = JSONObject(text ?: return null)
            val id = o.optString("caseID").takeIf { it.isNotEmpty() } ?: return null
            fun strings(a: JSONArray?): List<String> = a?.let { (0 until it.length()).map { i -> it.optString(i) } } ?: emptyList()
            val taken = o.optJSONArray("taken")?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map { Taken(it.optString("stepID"), it.optInt("at")) } } ?: emptyList()
            val ladders = o.optJSONArray("ladders")?.let { a -> (0 until a.length()).map { strings(a.optJSONArray(it)) } } ?: emptyList()
            val decision = o.optJSONObject("decision")?.let { Decision(it.optString("diagnosis"), it.optInt("nextStep"), it.optString("reason")) }
            CaseRun(
                caseID = id,
                started = StudyJson.date(o.opt("started")),
                taken = taken,
                ladder = strings(o.optJSONArray("ladder")),
                ladders = ladders,
                decision = decision,
                finished = if (o.has("finished") && !o.isNull("finished")) StudyJson.date(o.opt("finished")) else null,
                score = o.optJSONObject("score")?.let(CaseScore::fromJson),
            )
        }.getOrNull()
    }
}

/** Where a case stands, for a run that may not exist. */
val CaseRun?.caseState: CaseRun.State get() = this?.state ?: CaseRun.State.New

// The score out of 100, always shown with its parts and never as a rank
// (port of iOS Shared/Cases/CaseScore.swift):
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

data class CaseScore(
    val diagnosis: Int,
    val nextStep: Int,
    val keyFindings: Int,
    val redFlags: Int,
    val time: Int,
    /** Whether a missed must-not-miss red flag capped the total. */
    val capped: Boolean,
) {
    data class Part(val label: String, val points: Int, val of: Int)

    val sum: Int get() = diagnosis + nextStep + keyFindings + redFlags + time

    val total: Int get() = if (capped) minOf(sum, MISSED_MUST_NOT_MISS_CAP) else sum

    /** The parts, in the order the debrief lists them. */
    val parts: List<Part> get() = listOf(
        Part("Diagnosis", diagnosis, DIAGNOSIS_POINTS),
        Part("Next step", nextStep, NEXT_STEP_POINTS),
        Part("Key findings", keyFindings, KEY_POINTS),
        Part("Red flags", redFlags, RED_FLAG_POINTS),
        Part("Time", time, TIME_POINTS),
    )

    fun toJson(): JSONObject = JSONObject().put("diagnosis", diagnosis).put("nextStep", nextStep).put("keyFindings", keyFindings)
        .put("redFlags", redFlags).put("time", time).put("capped", capped)

    companion object {
        const val DIAGNOSIS_POINTS = 30
        const val NEXT_STEP_POINTS = 20
        const val KEY_POINTS = 25
        const val RED_FLAG_POINTS = 15
        const val TIME_POINTS = 10
        const val LOW_YIELD_ALLOWED = 1
        const val LOW_YIELD_COST = 2
        const val OVER_BUDGET_COST = 5
        const val MISSED_MUST_NOT_MISS_CAP = 60

        fun fromJson(o: JSONObject): CaseScore = CaseScore(o.optInt("diagnosis"), o.optInt("nextStep"), o.optInt("keyFindings"),
            o.optInt("redFlags"), o.optInt("time"), o.optBoolean("capped"))

        fun of(run: CaseRun, file: CaseFile): CaseScore {
            val taken = run.taken.map { it.stepID }.toSet()
            val rightDiagnosis = run.decision?.let { file.isDiagnosis(it.diagnosis) } ?: false
            val rightNext = run.decision?.let { it.nextStep == file.nextStep.key } ?: false

            val key = file.keySteps
            val keyFound = key.count { it.id in taken }
            val flags = file.redFlagSteps
            val flagsFound = flags.count { it.id in taken }

            val missedMustNotMiss = file.steps.any { it.mustNotMiss && it.id !in taken }

            return CaseScore(
                diagnosis = if (rightDiagnosis) DIAGNOSIS_POINTS else 0,
                nextStep = if (rightNext) NEXT_STEP_POINTS else 0,
                keyFindings = share(keyFound, key.size, KEY_POINTS),
                redFlags = share(flagsFound, flags.size, RED_FLAG_POINTS),
                time = timePart(run, file),
                capped = missedMustNotMiss,
            )
        }

        /** Points in proportion, rounded to the nearest; all of them when there was nothing of the kind to find. */
        fun share(found: Int, of: Int, points: Int): Int {
            if (of <= 0) return points
            val exact = points.toDouble() * minOf(found, of).toDouble() / of.toDouble()
            return exact.roundToInt()
        }

        fun timePart(run: CaseRun, file: CaseFile): Int {
            val lowYield = lowYieldTaken(run, file).size
            var points = TIME_POINTS - LOW_YIELD_COST * maxOf(0, lowYield - LOW_YIELD_ALLOWED)
            if (run.isOver(file)) points -= OVER_BUDGET_COST
            return maxOf(0, points)
        }

        /** The low-yield steps taken, in the order they were taken. */
        fun lowYieldTaken(run: CaseRun, file: CaseFile): List<CaseStep> =
            run.taken.mapNotNull { file.step(it.stepID) }.filter { it.value == CaseStep.Yield.low }
    }
}
