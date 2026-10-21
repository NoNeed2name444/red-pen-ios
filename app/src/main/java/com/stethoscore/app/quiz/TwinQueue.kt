package com.stethoscore.app.quiz

import java.time.Instant
import java.time.ZoneId

// A port of upstream/ios/RedPen/Shared/Exam/TwinQueue.swift.
//
// Twin questions after a miss. A wrong answer - above all a confident wrong
// one - earns two things: one immediate re-test of the same question a few
// items later in the sitting, and a "twin", a new question that tests the
// same discriminating fact in a different patient, which comes back one to
// three days later. Plain Kotlin, so the queue and the prompt are tested on
// the JVM. Times are epoch milliseconds; iOS's Calendar is a ZoneId here.

/** One twin waiting in the queue. */
data class TwinEntry(
    /** The twin question's own id (it lives in the library's Twins set). */
    val id: String,
    /** The question that was missed. */
    val parentId: String,
    val createdAt: Long,
    val dueAt: Long,
    /** Set once the twin has been answered; answered twins stay for the record. */
    val answeredAt: Long? = null,
    val answeredCorrectly: Boolean? = null,
)

/** The twins, due dates and all. */
data class TwinQueue(val entries: List<TwinEntry> = emptyList()) {

    companion object {
        /**
         * How long after the miss a twin comes back: a day for a confident
         * mistake, three for a guess, two otherwise.
         */
        fun delayDays(confident: Boolean, guessed: Boolean): Int = if (confident) 1 else if (guessed) 3 else 2

        /** The start of the day [days] days after [now], on the student's calendar. */
        fun dueDate(now: Long, days: Int, zone: ZoneId = ZoneId.systemDefault()): Long {
            val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
            return today.plusDays(days.toLong()).atStartOfDay(zone).toInstant().toEpochMilli()
        }
    }

    /** Adds a twin; one per missed question - a newer twin replaces an unanswered older one for the same parent. */
    fun add(twin: String, parent: String, now: Long = System.currentTimeMillis(), confident: Boolean = false,
            guessed: Boolean = false, zone: ZoneId = ZoneId.systemDefault()): TwinQueue {
        val kept = entries.filterNot { it.parentId == parent && it.answeredAt == null }
        val due = dueDate(now, delayDays(confident, guessed), zone)
        return TwinQueue(kept + TwinEntry(twin, parent, now, due))
    }

    /** Twins waiting and due by [now], the longest-waiting first. */
    fun due(now: Long = System.currentTimeMillis()): List<TwinEntry> =
        entries.filter { it.answeredAt == null && it.dueAt <= now }.sortedBy { it.dueAt }

    /** Twins not yet answered, due or not. */
    val waiting: List<TwinEntry> get() = entries.filter { it.answeredAt == null }

    /** Whether a question already has a twin on the way. */
    fun hasTwin(parent: String): Boolean = entries.any { it.parentId == parent && it.answeredAt == null }

    fun isTwin(id: String): Boolean = entries.any { it.id == id }

    /** Records the twin's answer. A missed twin comes back once more, a day later, rather than leaving the queue. */
    fun answered(id: String, correct: Boolean, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): TwinQueue {
        val i = entries.indexOfFirst { it.id == id && it.answeredAt == null }
        if (i < 0) return this
        val e = entries[i]
        val next = when {
            correct -> e.copy(answeredAt = now, answeredCorrectly = true)
            // second miss: stays answered-wrong; the ordinary mistakes queue has it
            e.answeredCorrectly == false -> e.copy(answeredAt = now)
            else -> e.copy(answeredCorrectly = false, dueAt = dueDate(now, 1, zone))
        }
        return TwinQueue(entries.toMutableList().also { it[i] = next })
    }

    /** Drops entries whose twin is no longer in the library. */
    fun prune(keeping: Set<String>): TwinQueue = TwinQueue(entries.filter { it.id in keeping })
}

/** Where the immediate re-test goes: a few questions on, or at the end when the quiz is nearly over. */
object TwinRetest {
    const val gap = 3

    fun slot(after: Int, count: Int): Int = minOf(after + 1 + gap, count)

    /** The slots of a sitting that are a question's first showing; a re-test repeats an id already seen. */
    fun firstShowings(ids: List<String>): List<Int> {
        val seen = HashSet<String>()
        return ids.indices.filter { seen.add(ids[it]) }
    }

    data class Collapsed<A>(val answers: List<A>, val orders: List<List<Int>>, val current: Int)

    /**
     * A sitting with its re-tests taken out: each question's first answer
     * and option order, in the set's own order, and the position as the
     * next of the set's own questions. A re-test is practice straight after
     * a miss, not a second question: it must not score, and the place it
     * leaves is the set's, so a sitting with one in can still be resumed.
     */
    fun <A> collapse(ids: List<String>, answers: List<A>, orders: List<List<Int>>, current: Int): Collapsed<A> {
        val keep = firstShowings(ids).filter { it < answers.size && it < orders.size }
        val at = keep.count { it < current }
        return Collapsed(keep.map { answers[it] }, keep.map { orders[it] }, minOf(at, maxOf(0, keep.size - 1)))
    }
}

/** The prompt that writes a twin, and the checks on what comes back. */
object TwinPrompt {
    /** What the writer is told. The discriminating fact is kept; the patient, setting and wording change. */
    fun instructions(style: String): String = listOf(
        style,
        "Write ONE new single-best-answer question - a \"twin\" - that tests exactly the same discriminating fact as the question below, but in a different clinical vignette: change the patient's age and sex, the setting and the presentation, and do not reuse its sentences.",
        "The correct answer may be the same concept, but the student must have to apply it, not recognise the old wording. Use five options with one clearly best answer; make the distractor the student chose a plausible option again.",
        "Reply with JSON only, in this shape: {\"questions\":[{\"stem\":\"...\",\"options\":[\"...\",\"...\",\"...\",\"...\",\"...\"],\"correctIndex\":0,\"explanation\":\"...\"}]}",
    ).joinToString("\n\n")

    /** The missed question, what was chosen, and why it was missed. */
    fun input(stem: String, options: List<String>, correctIndex: Int, explanation: String, picked: Int?, reason: String?): String {
        val answer = options.getOrNull(correctIndex) ?: ""
        val lines = mutableListOf("Missed question:", stem, "", "Options:")
        for (o in options) lines += "- $o"
        lines += ""
        lines += "Correct answer: $answer"
        if (picked != null && picked in options.indices && picked != correctIndex) lines += "The student chose: " + options[picked]
        if (!reason.isNullOrEmpty()) lines += "Why they missed it: $reason"
        lines += "Explanation: $explanation"
        return lines.joinToString("\n")
    }

    /** A twin is no good if it is the same question again: too many of the stem's words shared. */
    fun isTooClose(twinStem: String, stem: String): Boolean {
        val a = words(twinStem)
        val b = words(stem)
        if (a.isEmpty() || b.isEmpty()) return false
        val shared = a.intersect(b).size.toDouble()
        val smaller = minOf(a.size, b.size).toDouble()
        return shared / smaller > 0.8
    }

    fun words(text: String): Set<String> =
        text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.codePointCount(0, it.length) > 3 }.toSet()
}
