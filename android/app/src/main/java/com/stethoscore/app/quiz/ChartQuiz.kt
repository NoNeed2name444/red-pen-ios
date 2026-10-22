package com.stethoscore.app.quiz

import java.util.Locale

// A port of ios/RedPen/Features/MCQ/ChartQuiz.swift.
//
// The question screen as a patient's chart (docs/design/targets-2026-10-01.md
// §1): the header's words, what the chart card shows of a stem, how options
// are marked, the bar's words and what TalkBack hears. Plain Kotlin, so
// ChartQuizTest runs it on the JVM; ui/MCQQuizScreen.kt draws it.
object ChartQuiz {
    // MARK: the header

    /** The title: the set's subject, else its name. */
    fun title(subject: String, name: String): String {
        val s = subject.trim()
        val n = name.trim()
        return if (s.isNotEmpty()) s else if (n.isEmpty()) "Questions" else n
    }

    /** "Patient 7 of 20": each question is a patient on the round. */
    fun status(current: Int, total: Int): String = "Patient ${current + 1} of $total"

    /**
     * Under it: in a timed paper only how many are answered (the score is
     * what it holds back); the resume question; a first nudge; the score.
     */
    fun detail(examMode: Boolean, resuming: Boolean, correct: Int, checked: Int): String {
        if (examMode) return "$checked answered"
        if (resuming) return "Pick up where you left off?"
        return if (checked == 0) "Tap the answer you think is right" else "$correct of $checked right so far"
    }

    /** How far the amber strip under the title has filled. */
    fun fraction(current: Int, total: Int): Double = current.toDouble() / maxOf(1, total).toDouble()

    /** The chip beside PATIENT CHART. */
    fun kindChip(retest: Boolean): String = if (retest) "Second try" else "Best answer"

    /** The exam clock, "12:30" or "1:05:00". */
    fun clock(seconds: Int): String {
        val s = maxOf(0, seconds)
        val h = s / 3600
        val m = s % 3600 / 60
        return if (h > 0) String.format(Locale.ROOT, "%d:%02d:%02d", h, m, s % 60)
        else String.format(Locale.ROOT, "%d:%02d", m, s % 60)
    }

    /** The clock as TalkBack reads it. */
    fun spokenClock(seconds: Int): String = "${seconds / 60} minutes ${seconds % 60} seconds left"

    // MARK: the chart card

    /**
     * What the card shows of a stem. One with no vital signs or results
     * stays plain text - the whole stem as written, no chips, no empty grid
     * or table; otherwise the chart's parts, the story and, in bold, the
     * question.
     */
    data class Layout(
        val plain: Boolean,
        val chips: List<String> = emptyList(),
        val vitals: List<PatientChart.Vital> = emptyList(),
        val labs: List<PatientChart.Lab> = emptyList(),
        val story: String,
        val question: String = "",
    )

    fun layout(stem: String): Layout {
        val c = PatientChart.read(stem)
        if (!c.hasObservations) return Layout(plain = true, story = stem)
        return Layout(plain = false, chips = c.chips, vitals = c.vitals, labs = c.labs, story = c.story, question = c.question)
    }

    /** The highlighter keeps one set of marked pieces a question; on a chart the story's pieces keep their numbers and the question's start here. */
    const val questionMarks: Int = 10_000

    /** One part's marks, numbered from 0. */
    fun marks(all: Set<Int>, question: Boolean): Set<Int> {
        if (!question) return all.filter { it < questionMarks }.toSet()
        return all.filter { it >= questionMarks }.map { it - questionMarks }.toSet()
    }

    /** [all] with one part's marks replaced by [part]. */
    fun merging(part: Set<Int>, question: Boolean, into: Set<Int>): Set<Int> {
        val other = into.filter { if (question) it < questionMarks else it >= questionMarks }.toSet()
        return other + (if (question) part.map { it + questionMarks }.toSet() else part)
    }

    /** A reading flagged high or low is drawn in Resus Red, beside its arrow or its H or L. */
    enum class Tone { ink, danger }

    fun tone(flag: PatientChart.Flag?): Tone = if (flag == null) Tone.ink else Tone.danger

    private val signs: Map<String, String> = mapOf(
        "BP" to "Blood pressure", "HR" to "Heart rate", "RR" to "Respiratory rate",
        "Temp" to "Temperature", "SpO2" to "Oxygen saturation",
    )

    /** Readings as TalkBack says them: "Blood pressure 128 over 82, high", "Albumin 22 g/L, low". */
    fun spoken(vital: PatientChart.Vital): String {
        val name = signs[vital.label] ?: vital.label
        return name + " " + vital.value.replace("/", " over ") + flagWord(vital.flag)
    }

    fun spoken(lab: PatientChart.Lab): String = lab.name + " " + lab.value + " " + lab.unit + flagWord(lab.flag)

    private fun flagWord(flag: PatientChart.Flag?): String = when (flag) {
        null -> ""
        PatientChart.Flag.high -> ", high"
        PatientChart.Flag.low -> ", low"
    }

    // MARK: the options and the bar

    /**
     * How an option row is drawn: chosen or idle until it is checked; then
     * right (a check, in the section's colour), wrong (the pick: faded grey,
     * struck, a cross) or past. A timed paper keeps right and wrong for the
     * results.
     */
    enum class Mark { idle, chosen, right, wrong, past }

    fun mark(slot: Int, selected: Int?, correct: Int, checked: Boolean, examMode: Boolean): Mark {
        if (!checked || examMode) return if (slot == selected) Mark.chosen else Mark.idle
        if (slot == correct) return Mark.right
        return if (slot == selected) Mark.wrong else Mark.past
    }

    /**
     * A crossed-out option lies low, except the right answer once it shows;
     * once checked, so does every option neither picked nor right.
     */
    fun liesLow(struck: Boolean, mark: Mark): Boolean = mark == Mark.past || (struck && mark != Mark.right)

    /** What TalkBack adds to a marked option, so colour is never the only sign. */
    fun spoken(mark: Mark): String? {
        if (mark == Mark.right) return "Correct answer"
        return if (mark == Mark.wrong) "Your answer, wrong" else null
    }

    /** The main button's words: what to do next, never a grey button with no reason given. */
    fun primaryTitle(checked: Boolean, picked: Boolean, holding: Boolean, examMode: Boolean, last: Boolean): String {
        if (holding && !checked) return "Keep reading"
        // a paper is sat as on the day: a question can be skipped and come
        // back to, and nothing is marked until the paper is handed in
        if (examMode && !checked) return if (last) "Finish paper" else if (picked) "Next patient" else "Skip for now"
        if (!checked && !picked) return "Pick an answer"
        if (!checked) return "Check answer"
        return if (last) "See results" else "Next patient"
    }

    /** Explain sits beside Next patient once the explanation shows; a timed paper keeps explanations for the end. */
    fun explains(checked: Boolean, examMode: Boolean): Boolean = checked && !examMode
}
