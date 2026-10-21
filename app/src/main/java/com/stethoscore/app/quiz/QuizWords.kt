package com.stethoscore.app.quiz

import java.util.regex.Pattern

// The smaller pieces the question screen uses, each a port of its iOS file:
// ExamTrack (Shared/ExamTrack.swift: the exam's pace, for timed mode),
// AnswerConfidence and MistakeReason (Shared/Insight/InsightModels.swift),
// StemKeyWords (Shared/Insight/StemKeyWords.swift: the slow reading drill's
// marked words) and SpokenText's option and result lines
// (Shared/AccessibilityText.swift). Plain Kotlin, tested on the JVM.

/** The exam the student is sitting; here, what the timed paper and the lab units need of it. */
@Suppress("EnumEntryName")
enum class ExamTrack(val rawValue: String) {
    general("general"), usmle("usmle"), plab("plab"), mrcp("mrcp"), mrcs("mrcs");

    val title: String get() = when (this) {
        general -> "General revision"
        usmle -> "USMLE Step 1 / Step 2 CK"
        plab -> "PLAB 1 & 2"
        mrcp -> "MRCP(UK) Part 1, 2 & PACES"
        mrcs -> "MRCS Part A & B"
    }

    /** Seconds a question gets in this exam's written paper, for timed exam mode. */
    val secondsPerQuestion: Int get() = when (this) {
        general -> 75
        usmle -> 90   // 40 questions in an hour-long block
        plab -> 60    // 180 questions in three hours
        mrcp -> 108   // 100 questions in three hours
        mrcs -> 60    // Part A's pace, near enough
    }

    companion object {
        /** Where the student's pick is kept (SharedPreferences, as iOS's UserDefaults). */
        const val storageKey = "examTrack"
        fun from(raw: String?): ExamTrack = entries.firstOrNull { it.rawValue == raw } ?: general
    }
}

/** How sure the student said they were before checking an answer. */
@Suppress("EnumEntryName")
enum class AnswerConfidence(val rawValue: String, val title: String) {
    sure("sure", "Sure"), maybe("maybe", "Maybe"), guess("guess", "Guess");
    companion object { fun from(raw: String?): AnswerConfidence? = entries.firstOrNull { it.rawValue == raw } }
}

/** Why a mark was lost, in the student's own judgement, picked with one tap after a wrong answer. */
@Suppress("EnumEntryName")
enum class MistakeReason(val rawValue: String, val title: String) {
    didntKnow("didntKnow", "Didn’t know it"),
    misread("misread", "Misread the question"),
    changedAnswer("changedAnswer", "Changed a right answer"),
    outOfTime("outOfTime", "Ran out of time"),
    lookalikes("lookalikes", "Mixed up lookalikes");
    companion object { fun from(raw: String?): MistakeReason? = entries.firstOrNull { it.rawValue == raw } }
}

/** Settings > Review: whether to show the Sure / Maybe / Guess row (on unless turned off). */
object ConfidenceSetting {
    const val key = "quiz.askConfidence"
}

/**
 * The words in a question stem that change the answer, for the slow reading
 * drill: what is being asked, negatives that are easy to skim past, time
 * course, and the numbers. Deliberately simple: a list of patterns, no model.
 */
object StemKeyWords {
    private val patterns: List<String> = listOf(
        // what is being asked
        """\b(most likely|most appropriate|most common|next best|next step|best initial|initial|first[- ]line|definitive|gold standard|least likely|contraindicated|except|not|least)\b""",
        // negatives and time course that flip the picture
        """\b(no|denies|without|never|absent|normal|sudden|acute|chronic|recurrent|bilateral|unilateral|painless|painful|pregnant)\b""",
        // ages and numbers with units
        """\b\d+(\.\d+)?[- ]?(year|month|week|day|hour)s?[- ]old\b""",
        """\b\d+(\.\d+)?\s?(%|mmHg|mg/dL|mmol/L|\x{00B5}mol/L|g/L|g/dL|bpm|/min|\x{00B0}C|\x{00B0}F|kg|years?|months?|weeks?|days?|hours?|minutes?)""",
    )

    private val expressions: List<Pattern> = patterns.mapNotNull {
        runCatching { Pattern.compile(it, Pattern.CASE_INSENSITIVE or Pattern.UNICODE_CASE) }.getOrNull()
    }

    /** The ranges of [stem] to mark, as [start, end) offsets, in order, not overlapping. */
    fun ranges(stem: String): List<IntRange> {
        val found = mutableListOf<IntRange>()
        for (expression in expressions) {
            val m = expression.matcher(stem)
            while (m.find()) {
                val range = m.start() until m.end()
                if (range.isEmpty()) continue
                if (found.any { maxOf(it.first, range.first) <= minOf(it.last, range.last) }) continue
                found += range
            }
        }
        return found.sortedBy { it.first }
    }
}

/** What TalkBack says about an option and an answer (SpokenText's quiz lines). */
object SpokenText {
    /** After the option's text: chosen, or - once checked - right or wrong. */
    fun optionState(checked: Boolean, isCorrect: Boolean, isChosen: Boolean): String {
        if (!checked) return if (isChosen) "Chosen" else ""
        if (isCorrect && isChosen) return "Correct, your answer"
        if (isCorrect) return "Correct answer"
        if (isChosen) return "Your answer, incorrect"
        return ""
    }

    /** Said as soon as an answer is checked: "Correct." or "Incorrect. The answer is C: Aortic stenosis." */
    fun answerResult(correct: Boolean, letter: String, answer: String): String {
        if (correct) return "Correct."
        val text = answer.trim()
        if (letter.isEmpty()) return "Incorrect."
        if (text.isEmpty()) return "Incorrect. The answer is $letter."
        return "Incorrect. The answer is $letter: $text."
    }
}
