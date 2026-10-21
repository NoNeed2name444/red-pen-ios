package com.stethoscore.app.data

import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// A port of upstream/ios/RedPen/Shared/Insight (InsightModels' StudyRule,
// Readiness, RuleWriter, and StoreInsight's CalibrationRow, RuleGroup and
// ReasonShare) and of HeatLevel (Shared/AccessibilityText.swift): the sums
// the Vitals screen and the rule sheet are built on. Pure Kotlin, so they
// can be tested on the JVM. The store's side (which questions, which
// answers) is ui/vitals/StoreInsight.kt.

/**
 * One line on the rule sheet: what to remember so a missed question is got
 * right next time. Keeps its own copy of the question's stem, answer and
 * explanation, so the rule outlives the set it came from.
 */
data class StudyRule(
    /** The question's id: one rule per question. */
    val id: String,
    val subject: String,
    /** The one-line rule itself. */
    val text: String,
    /** A sentence of support under it - the first of the explanation. */
    val detail: String,
    val stem: String,
    val answer: String,
    val explanation: String,
    val byAI: Boolean = false,
    val date: Long = System.currentTimeMillis(),
    val isExample: Boolean? = null,
) {
    /** The rule as the library file keeps it (iOS's StudyRule keys). */
    fun json(): JSONObject = JSONObject().put("id", id).put("subject", subject).put("text", text).put("detail", detail)
        .put("stem", stem).put("answer", answer).put("explanation", explanation).put("byAI", byAI)
        .putDate("date", date).also { o -> isExample?.let { o.put("isExample", it) } }

    companion object {
        fun from(id: String, o: JSONObject): StudyRule = StudyRule(
            id = o.text("id", id), subject = o.text("subject"), text = o.text("text"), detail = o.text("detail"),
            stem = o.text("stem"), answer = o.text("answer"), explanation = o.text("explanation"),
            byAI = o.optBoolean("byAI"), date = StudyJson.date(o.opt("date")),
            isExample = if (o.has("isExample") && !o.isNull("isExample")) o.optBoolean("isExample") else null,
        )
    }
}

/**
 * A rough estimate of the score the student would get if they sat the paper
 * today, and the subjects that would move it most. It is an estimate and
 * says so.
 */
data class ReadinessEstimate(
    /** The middle of the estimate, 0..1. */
    val center: Double,
    val low: Double,
    val high: Double,
    /** Answers the estimate is built on. */
    val answers: Int,
    /** Recent weighted accuracy before anything was taken off. */
    val recentAccuracy: Double,
    /** What was taken off for thinly practised subjects, 0..1. */
    val coveragePenalty: Double,
    /** What was taken off for review cards waiting, 0..1. */
    val reviewPenalty: Double,
    /** Subjects with fewer than [Readiness.thinSubjectAnswers] answers. */
    val thinSubjects: List<String>,
    val dueCards: Int,
    val passMark: Double,
    /** Up to three subjects where the most marks are being lost. */
    val levers: List<Lever>,
) {
    data class Lever(
        val subject: String,
        /** This subject's share of the questions in the library. */
        val share: Double,
        /** Accuracy so far, or null when it has not been tried. */
        val accuracy: Double?,
        /** share x (1 - accuracy): the marks there are to gain. */
        val weight: Double,
    )
}

object Readiness {
    /** Below this there is not enough to say anything useful. */
    const val minimumAnswers = 20
    /** How many of the latest answers are read. */
    const val window = 200
    /** A subject with fewer answers than this counts as thinly covered. */
    const val thinSubjectAnswers = 10
    /** Each answer counts this much less than the one after it. */
    const val decay = 0.99

    /** [recent] is right/wrong newest first; only the first [window] are read. */
    fun estimate(recent: List<Boolean>, subjects: List<BedPlan.Topic>, dueCards: Int, passMark: Double): ReadinessEstimate? {
        val sample = recent.take(window)
        if (sample.size < minimumAnswers) return null

        // recency-weighted accuracy, and how many answers' worth of evidence
        // the weighting leaves (Kish's effective sample size)
        var sumW = 0.0
        var sumW2 = 0.0
        var sumRight = 0.0
        var weight = 1.0
        for (right in sample) {
            sumW += weight
            sumW2 += weight * weight
            if (right) sumRight += weight
            weight *= decay
        }
        val p = sumRight / sumW
        val n = max(1.0, (sumW * sumW) / sumW2)

        // Wilson score interval at about 90%
        val z = 1.645
        val z2 = z * z
        val denominator = 1 + z2 / n
        val middle = (p + z2 / (2 * n)) / denominator
        val variance = p * (1 - p) / n + z2 / (4 * n * n)
        val half = z * sqrt(variance) / denominator

        // subjects barely practised are assumed to go ten points worse
        val totalQuestions = subjects.sumOf { it.questions }
        val thin = subjects.filter { it.answered < thinSubjectAnswers && it.questions > 0 }
        val thinQuestions = thin.sumOf { it.questions }
        val thinShare = if (totalQuestions == 0) 0.0 else thinQuestions.toDouble() / totalQuestions
        val coverage = 0.10 * thinShare

        // a point off for every twenty cards waiting, at most five
        val review = min(0.05, max(0, dueCards) * 0.0005)

        val off = coverage + review
        fun clamp(x: Double): Double = min(1.0, max(0.0, x))

        val levers = mutableListOf<ReadinessEstimate.Lever>()
        if (totalQuestions > 0) {
            for (s in subjects) {
                if (s.questions <= 0) continue
                val share = s.questions.toDouble() / totalQuestions
                val accuracy: Double? = if (s.answered > 0) s.accuracy else null
                val gain = share * (1 - (accuracy ?: p))
                if (gain <= 0) continue
                levers.add(ReadinessEstimate.Lever(s.name, share, accuracy, gain))
            }
        }
        levers.sortByDescending { it.weight }

        return ReadinessEstimate(
            center = clamp(p - off), low = clamp(middle - half - off), high = clamp(middle + half - off),
            answers = sample.size, recentAccuracy = p,
            coveragePenalty = coverage, reviewPenalty = review,
            thinSubjects = thin.map { it.name }.sorted(), dueCards = max(0, dueCards),
            passMark = passMark, levers = levers.take(3),
        )
    }
}

/** One subject's rules on the rule sheet. */
data class RuleGroup(val subject: String, val rules: List<StudyRule>)

/**
 * How much was studied on one day of the study calendar, as one of five
 * steps (AccessibilityText's HeatLevel): the shade, the dot it carries when
 * colour cannot be relied on, and the word TalkBack hears.
 */
@Suppress("EnumEntryName")
enum class HeatLevel(val rawValue: Int) {
    none(0), light(1), some(2), lots(3), most(4);

    /** 0..1: how strongly the cell is shaded, and how big its dot is. */
    val strength: Double get() = rawValue / 4.0

    val word: String get() = when (this) {
        none -> "nothing"
        light -> "a little"
        some -> "some"
        lots -> "a lot"
        most -> "the most"
    }

    companion object {
        /** Where [count] sits against the busiest day shown. */
        fun of(count: Int, busiest: Int): HeatLevel {
            if (count <= 0 || busiest <= 0) return none
            val share = min(1.0, count.toDouble() / busiest)
            if (share <= 0.25) return light
            if (share <= 0.5) return some
            if (share < 1) return lots
            return most
        }
    }
}

/**
 * Turns a missed question into one line worth remembering (RuleWriter).
 * Without a model the line is mechanical but honest: the question being
 * asked, an arrow, and the right answer, with the explanation's first
 * sentence under it. Android has no writer model, so [prompt] and [parse]
 * wait for one.
 */
object RuleWriter {
    /** Questions sent to the model in one call. */
    const val batchSize = 10

    /** A rule for one question, built from its own words. */
    fun plainRule(question: MCQQuestion, subject: String): StudyRule {
        val answer = question.options.getOrNull(question.correctIndex) ?: ""
        val text = "${askedPart(question.stem)} → $answer"
        return StudyRule(question.id, subject, text, firstSentence(question.explanation),
            question.stem, answer, question.explanation)
    }

    private fun isWhite(c: Char): Boolean = c.isWhitespace()

    /** The sentence the stem ends by asking, or its first twelve words when it asks nothing in so many words. */
    fun askedPart(stem: String): String {
        val text = stem.trim()
        val mark = text.lastIndexOf('?')
        if (mark >= 0) {
            val before = text.substring(0, mark)
            // back to the end of the sentence before it
            val stop = before.indexOfLast { it in ".!?\n" }
            val start = if (stop >= 0) stop + 1 else 0
            val asked = text.substring(start, mark + 1).trim()
            if (asked.length >= 8) return asked
        }
        val words = text.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val head = words.take(12).joinToString(" ")
        return if (words.size > 12) "$head…" else head
    }

    /** Up to and including the first full stop that ends a sentence. */
    fun firstSentence(text: String): String {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return ""
        for (i in trimmed.indices) {
            val ch = trimmed[i]
            if (ch in ".!?" && (i + 1 == trimmed.length || isWhite(trimmed[i + 1]))) return trimmed.substring(0, i + 1)
        }
        return trimmed
    }

    /** The request for one batch: every question numbered, with its answer and explanation, and the reply's shape spelled out. */
    fun prompt(rules: List<StudyRule>): String {
        val lines = mutableListOf(
            "You are helping a medical student build a rule sheet for their exam.",
            "For each question below, write ONE precise, exam-style rule line (at most 25 words) that would let the student answer this kind of question correctly next time. State the discriminating clue and the answer, e.g. \"Painless jaundice + palpable gallbladder → pancreatic head carcinoma\". No preamble, no numbering inside the rule, no hedging.",
            "Reply with JSON only, in exactly this shape, with one rule per question in the same order: {\"rules\": [\"...\", \"...\"]}",
            "",
        )
        rules.forEachIndexed { i, rule ->
            lines.add("Question ${i + 1}: ${rule.stem}")
            lines.add("Correct answer: ${rule.answer}")
            if (rule.explanation.isNotEmpty()) lines.add("Explanation: ${rule.explanation.take(600)}")
            lines.add("")
        }
        return lines.joinToString("\n")
    }

    /** The rule lines in a reply, in order, or null when it is not the JSON asked for. */
    fun parse(raw: String): List<String>? {
        val text = raw.replace(Regex("(?s)<think>.*?</think>"), "")
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start < 0 || end <= start) return null
        val rules = runCatching { JSONObject(text.substring(start, end + 1)).getJSONArray("rules") }.getOrNull() ?: return null
        return (0 until rules.length()).map { rules.optString(it).trim() }
    }
}
