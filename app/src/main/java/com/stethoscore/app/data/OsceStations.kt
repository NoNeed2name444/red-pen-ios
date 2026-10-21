package com.stethoscore.app.data

import com.stethoscore.app.quiz.ExamTrack

// A port of upstream/ios/RedPen/Models/OsceChecklist.swift (OsceRun: one run
// through a station, in order), Shared/OsceStations.swift (tidying written
// stations and the text format they come back in), the OSCE and card lines of
// Shared/PlainTextImport.swift (OsceText, until the Library batch ports the
// whole file), OsceGenerator's limits and words, and ExamTrack's station
// minutes and OSCE style. Plain Kotlin, tested on the JVM (OsceTest).

/**
 * One run through a station, in order. The steps of a station are done in a
 * fixed order, so there is no marking a step wrong and carrying on: either
 * the step was got ("I got it", on to the next) or the attempt is over and
 * the station starts again from step 1 ("Start over").
 *
 * Every start over is kept as a miss on the step it happened at, so a step
 * that keeps tripping somebody up still shows once the station is done.
 */
class OsceRun(stepCount: Int, stepIndex: Int = 0, misses: List<Int> = emptyList(), complete: Boolean = false) {
    val stepCount: Int = maxOf(0, stepCount)
    /** The step being recalled now, from 0. */
    val stepIndex: Int = minOf(maxOf(0, stepIndex), maxOf(0, stepCount - 1))
    /** The step each start over happened at, in the order they happened. A step can appear more than once. */
    val misses: List<Int> = misses.filter { it >= 0 && it < stepCount }
    /** Every step got, in order, in one attempt. */
    val complete: Boolean = complete || stepCount == 0

    /** How many times the station was started over. */
    val restarts: Int get() = misses.size

    /** Where a set is picked back up. */
    data class Resume(val station: Int, val step: Int, val misses: List<Int>)

    /**
     * Where to pick a set back up after this run of station [station] (of
     * [count]): here, part way through; the next station from its first
     * step once this one is done; null once the last is done.
     */
    fun resumePoint(station: Int, count: Int): Resume? {
        if (!complete) return Resume(station, stepIndex, misses)
        if (station + 1 >= count) return null
        return Resume(station + 1, 0, emptyList())
    }

    /** Got the step: on to the next one, or done after the last. */
    fun gotIt(): OsceRun {
        if (complete) return this
        return if (stepIndex >= stepCount - 1) OsceRun(stepCount, stepIndex, misses, complete = true)
        else OsceRun(stepCount, stepIndex + 1, misses)
    }

    /** Missed the step: note it, and go back to step 1. */
    fun startOver(): OsceRun {
        if (complete || stepCount <= 0) return this
        return OsceRun(stepCount, 0, misses + stepIndex)
    }

    /** A step that caused a start over, and how often. */
    data class Weak(val step: Int, val times: Int)

    /** The steps that caused a start over, most often first, then in station order. */
    val weakSteps: List<Weak> get() = misses.groupingBy { it }.eachCount()
        .map { Weak(it.key, it.value) }
        .sortedWith(compareByDescending<Weak> { it.times }.thenBy { it.step })

    override fun equals(other: Any?): Boolean = other is OsceRun && other.stepCount == stepCount &&
        other.stepIndex == stepIndex && other.misses == misses && other.complete == complete
    override fun hashCode(): Int = listOf(stepCount, stepIndex, misses, complete).hashCode()
    override fun toString(): String = "OsceRun(step $stepIndex of $stepCount, misses $misses, complete $complete)"
}

/**
 * Turning a model's answer into stations worth drilling, and back into the
 * text format the new-set screen understands. Everything here is about what
 * makes a checklist usable in an exam: steps that are actions rather than
 * essays, in the order they would be performed, with nothing repeated.
 */
object OsceStations {
    /** Longest a step may be before it stops being a step. */
    const val maxStepLength = 160
    const val maxSteps = 30

    /**
     * Tidies one station's steps: numbering stripped (the position is the
     * number), repeats dropped case-insensitively but for a closing repeat
     * ("Wash hands" at the start and again at the end are two marks),
     * blanks, stubs and paragraphs dropped, at most [maxSteps].
     */
    fun clean(steps: List<String>): List<String> {
        val seen = HashSet<String>()
        val out = ArrayList<String>()
        val tidied = steps.map { raw ->
            stripLeadingMarker(raw.trim()).replace("\n", " ").trim()
        }.filter { it.length in 3..maxStepLength }
        for ((index, step) in tidied.withIndex()) {
            val key = step.lowercase()
            if (key in seen) {
                val closing = index == tidied.size - 1 && out.lastOrNull()?.lowercase() != key
                if (!closing || out.size >= maxSteps) continue
            }
            seen.add(key)
            out.add(step)
            if (out.size >= maxSteps) break
        }
        return out
    }

    private val markers = listOf(
        Regex("""^\s*step\s*\d+\s*[:.)-]\s*""", RegexOption.IGNORE_CASE),
        Regex("""^\s*\d{1,3}\s*(?:[.)]\s+|[.)](?=[^\W\d_])|:\s+)""", RegexOption.IGNORE_CASE),
        Regex("""^\s*[-–—•*]\s*""", RegexOption.IGNORE_CASE),
    )

    /**
     * Removes "1.", "1)", "-", "•", "Step 2:" and the like from the front. A
     * number is list numbering only when its "." or ")" is followed by a
     * space or straight by a letter, or its ":" by a space; never a number
     * joined to more of itself ("12-lead ECG", "0.9% saline", "3.5 mmol/L").
     */
    fun stripLeadingMarker(step: String): String {
        var text = step
        for (pattern in markers) {
            val match = pattern.find(text) ?: continue
            text = text.removeRange(match.range)
        }
        return text.trim { it == ' ' || it == '\t' }
    }

    /** Whether a station is worth keeping: a title and at least three steps. */
    fun isUsable(checklist: OsceChecklist): Boolean =
        checklist.title.trim().isNotEmpty() && checklist.steps.size >= 3

    /** Cleans and drops the unusable and the repeated titles, keeping the order they arrived in. */
    fun tidy(checklists: List<OsceChecklist>): List<OsceChecklist> {
        val seenTitles = HashSet<String>()
        val out = ArrayList<OsceChecklist>()
        for (checklist in checklists) {
            val kept = checklist.copy(title = stripLeadingMarker(checklist.title.trim()), steps = clean(checklist.steps))
            if (!isUsable(kept)) continue
            val key = kept.title.lowercase()
            if (key in seenTitles) continue
            seenTitles.add(key)
            out.add(kept)
        }
        return out
    }

    /** What the writer is asked for. */
    fun prompt(sourceText: String, count: Int, subject: String, alreadyWritten: List<String>,
               exam: ExamTrack = ExamTrack.general): String {
        val lines = mutableListOf(
            "You write OSCE station checklists for a medical student revising ${if (subject.isEmpty()) "clinically" else subject}.",
            "",
            "From the source below, write $count station checklist${if (count == 1) "" else "s"}.",
            "",
            "Each station is a clinical task a student could be examined on: an examination, a procedure, a history, a counselling or handover task.",
            "Each step is one thing the candidate DOES or SAYS, in the order it happens, phrased as an examiner's tick-box.",
            "Write between 6 and 20 steps. Keep every step under 20 words.",
            "Include the marks students actually lose: introducing yourself, consent, exposure, hand hygiene, and saying what you would do to finish.",
            "Use only what the source supports. Do not invent a procedure the source never mentions.",
            "Do not number the steps; the order is the number.",
        )
        exam.osceStyle?.let(lines::add)
        if (alreadyWritten.isNotEmpty()) {
            lines.add("")
            lines.add("You have already written these stations - write different ones:")
            lines.addAll(alreadyWritten.map { "- $it" })
        }
        lines.add("")
        lines.add("SOURCE:")
        lines.add(sourceText)
        return lines.joinToString("\n")
    }

    /** Back into the "## Station / one step per line" format the new-set screen parses. */
    fun format(checklists: List<OsceChecklist>): String =
        checklists.joinToString("\n\n") { (listOf("## " + it.title) + it.steps).joinToString("\n") }
}

/** The OSCE and card lines of iOS's PlainTextImport. */
object OsceText {
    /** The text's lines, whichever line endings it was written with. */
    fun lines(text: String, keepingEmpty: Boolean = false): List<String> {
        val all = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        return if (keepingEmpty) all else all.filter { it.isNotEmpty() }
    }

    private fun String.trimSpaces() = trim { it == ' ' || it == '\t' }

    /** OSCE: one or more stations, each a "## Title" line followed by one step per line until the next "## " or the end. */
    fun parseOsce(text: String): List<OsceChecklist> {
        val checklists = ArrayList<OsceChecklist>()
        var title = ""
        var steps = ArrayList<String>()
        fun flush() {
            val t = title.trimSpaces()
            val s = steps.map { it.trimSpaces() }.filter { it.isNotEmpty() }
            if (t.isNotEmpty() && s.isNotEmpty()) checklists.add(OsceChecklist(title = t, steps = s))
            steps = ArrayList()
        }
        for (line in lines(text, keepingEmpty = true)) {
            val bare = line.trimSpaces()
            if (bare.startsWith("##")) {
                flush()
                title = bare.trim('#').trimSpaces()
            } else if (bare.isNotEmpty()) {
                steps.add(line)
            }
        }
        flush()
        return checklists
    }

    /** Cards, one per line: "Front | bullet; bullet | why", or a cloze sentence with "{{c1::...}}" and its why. */
    fun parseAnkiQA(text: String): List<AnkiCard> = lines(text).mapNotNull { raw ->
        val line = raw.trimSpaces()
        if (line.isEmpty()) return@mapNotNull null
        val parts = line.split("|").map { it.trimSpaces() }
        if (parts[0].contains("{{c") && parts[0].contains("::") && parts[0].contains("}}"))
            return@mapNotNull AnkiCard(type = AnkiCardType.CLOZE, clozeText = parts[0], why = if (parts.size >= 2) parts[1] else "")
        if (parts.size < 2) return@mapNotNull null
        val bullets = parts[1].split(";").map { it.trimSpaces() }.filter { it.isNotEmpty() }
        if (bullets.isEmpty()) return@mapNotNull null
        AnkiCard(type = AnkiCardType.QA, front = parts[0], bullets = bullets, why = if (parts.size >= 3) parts[2] else "")
    }
}

/**
 * Writing stations from a lecture or a mark sheet (iOS OsceGenerator). iOS
 * writes them with a writer chosen in AI models or Apple's on-device model;
 * Android has neither yet, so [writer] finds none and the form says so.
 */
object OsceGenerator {
    const val maxStationsTotal = 1_000

    /** A writer of stations; none on Android yet. */
    fun interface Writer { suspend fun stations(sourceText: String, count: Int, subject: String): List<OsceChecklist> }

    fun writer(): Writer? = null

    /** Why nothing can be written, in the student's words. */
    fun noWriter(): String = "Stations are written by an AI writer, and none is set up on this phone yet."

    const val nothingUsable = "Nothing in that source reads like a station. A skills lecture or a mark sheet works best — a slide deck of facts usually has no procedure in it."
}

/** Minutes with the patient in one of this exam's clinical stations, for the OSCE station timer. */
val ExamTrack.stationMinutes: Int get() = when (this) {
    ExamTrack.plab -> 8     // PLAB 2
    ExamTrack.mrcp -> 10    // a PACES encounter
    ExamTrack.mrcs -> 9     // MRCS Part B
    ExamTrack.usmle, ExamTrack.general -> 15
}

/** What is added to the OSCE writer's instructions: how this exam's clinical stations are run and marked. */
val ExamTrack.osceStyle: String? get() = when (this) {
    ExamTrack.general -> null
    ExamTrack.usmle -> "Write each station as a USMLE-style patient encounter: focused history, focused physical examination, counselling, and the patient note (history, examination, differential diagnosis with supporting findings, first investigations)."
    ExamTrack.plab -> "Write each station as a PLAB 2 station: 8 minutes with the patient after 1.5 minutes' reading, set in UK practice, marked on data gathering, clinical management and interpersonal skills. Include safety-netting, checking understanding, and follow-up that a UK foundation doctor would arrange."
    ExamTrack.mrcp -> "Write each station as an MRCP PACES station (history taking, communication and ethics, or a clinical examination station), marked on the PACES skills: physical examination, identifying physical signs, clinical communication, differential diagnosis, clinical judgement, managing patients' concerns and maintaining patient welfare."
    ExamTrack.mrcs -> "Write each station as an MRCS Part B OSCE station (anatomy and surgical pathology, applied physiology and critical care, clinical and procedural skills, or communication skills), with the surgical-safety steps examiners mark: consent, WHO checklist items, asepsis and documentation."
}
