package com.stethoscore.app.quiz

import org.json.JSONArray
import org.json.JSONObject

// A port of ios/RedPen/Shared/Exam/AttendingHint.swift, with the
// parts of Models/Differential.swift the hint reads.
//
// The attending's hint: the next step in the reasoning - what the key finding
// points to, which kind of option can be ruled out - without naming the
// answer. On iOS a model writes it when there is one, checked so it never
// gives the answer away; Android has no question writer yet, so the hint is
// always the fallback made from the item's own differential or a fixed nudge.

/** One diagnosis in a differential, with the case's own findings for and against it and the test that settles it. */
data class DifferentialEntry(
    val name: String,
    val supporting: List<String> = emptyList(),
    val against: List<String> = emptyList(),
    val test: String = "",
)

/** A differential in three tiers (Models/Differential.swift). */
data class DifferentialTiers(
    val mostLikely: List<DifferentialEntry> = emptyList(),
    val expanded: List<DifferentialEntry> = emptyList(),
    val cantMiss: List<DifferentialEntry> = emptyList(),
) {
    val isEmpty: Boolean get() = mostLikely.isEmpty() && expanded.isEmpty() && cantMiss.isEmpty()

    companion object {
        /** A question's differential, as iOS writes it into the question's JSON; null when there is none. */
        fun fromQuestionJson(raw: String): DifferentialTiers? = runCatching {
            val o = JSONObject(raw).optJSONObject("differential") ?: return null
            fun strings(a: JSONArray?) = a?.let { arr -> (0 until arr.length()).mapNotNull { arr.optString(it).takeIf { s -> s.isNotEmpty() } } } ?: emptyList()
            fun tier(key: String) = o.optJSONArray(key)?.let { a ->
                (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map {
                    DifferentialEntry(it.optString("name"), strings(it.optJSONArray("supporting")), strings(it.optJSONArray("against")), it.optString("test"))
                }
            } ?: emptyList()
            DifferentialTiers(tier("mostLikely"), tier("expanded"), tier("cantMiss")).takeIf { !it.isEmpty }
        }.getOrNull()
    }
}

object AttendingHint {

    /** Words too common in medicine to give an answer away on their own. */
    val commonWords: Set<String> = setOf(
        "acute", "chronic", "disease", "syndrome", "with", "without", "from", "into",
        "that", "this", "which", "the", "and", "primary", "secondary", "left", "right",
        "type", "deficiency", "infection", "failure", "test", "level", "levels", "blood",
        "oral", "intravenous", "dose", "start", "give", "refer", "urgent", "normal",
    )

    fun words(text: String): List<String> = text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }

    private fun length(s: String) = s.codePointCount(0, s.length)

    /**
     * Whether [hint] gives the answer away: it contains the answer whole, or
     * a distinctive word of it - one not in the stem and in no other option.
     */
    fun leaks(hint: String, answer: String, stem: String, otherOptions: List<String>): Boolean {
        val h = words(hint)
        val a = words(answer)
        if (a.isEmpty()) return false
        val hintLine = " " + h.joinToString(" ") + " "
        val answerLine = " " + a.joinToString(" ") + " "
        if (hintLine.contains(answerLine)) return true
        val elsewhere = words(stem).toMutableSet()
        for (o in otherOptions) elsewhere += words(o)
        val hintWords = h.toSet()
        for (w in a) {
            if (length(w) <= 3 || w in commonWords || w in elsewhere) continue
            if (w in hintWords) return true
            // "hyperthyroid" for "hyperthyroidism": a shared long stem
            val root = String(w.codePoints().limit(7).toArray(), 0, minOf(7, length(w)))
            if (length(root) == 7 && h.any { length(it) >= 7 && it.startsWith(root) }) return true
        }
        return false
    }

    /** The model's reply tidied to the nudge itself, or null when it is empty or gives the answer away. */
    fun accept(reply: String, answer: String, stem: String, otherOptions: List<String>): String? {
        var text = reply.trim()
        for (prefix in listOf("Hint:", "hint:", "Nudge:", "Attending:")) {
            if (text.startsWith(prefix)) text = AccuracyRules.trimSpaces(text.substring(prefix.length))
        }
        text = text.trim('"', '“', '”', ' ')
        if (length(text) < 12) return null
        if (length(text) > 400) text = String(text.codePoints().limit(400).toArray(), 0, 400) + "…"
        if (leaks(text, answer, stem, otherOptions)) return null
        return text
    }

    /** A nudge made from the differential, or a fixed one. Never names the answer: a finding that would give it away is passed over. */
    fun fallback(answer: String, stem: String, options: List<String>, differential: DifferentialTiers?): String {
        val others = options.filter { it != answer }
        if (differential != null) {
            // a can't-miss or alternative that is not the answer: what argues against it
            for (rival in differential.cantMiss + differential.expanded) {
                if (rival.against.isEmpty()) continue
                val line = "Before you settle, rule something out: what in the stem argues against ${rival.name}? Look at ${rival.against[0].lowercase()}."
                if (!leaks(line, answer, stem, others)) return line
            }
            for (entry in differential.mostLikely) {
                for (finding in entry.supporting) {
                    val line = "The finding that carries this question is ${finding.lowercase()}. What does it point to, and which options can't explain it?"
                    if (!leaks(line, answer, stem, others)) return line
                }
            }
        }
        return "Find the single most specific finding in the stem - the one that fits only one of the options - and ask what it points to. Then rule out any option that can't explain it."
    }
}

/**
 * Hints kept once written, so a question asks the model only once. Keyed by
 * the item's id and, when given, a version of its wording. The oldest go
 * first past the cap.
 */
class HintCache {
    companion object {
        const val cap = 400

        /** A short fingerprint of what the hint was written for. Stable across launches (FNV-1a). */
        fun version(stem: String, options: List<String>, answer: String): String {
            var hash = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
            for (byte in (listOf(stem) + options + listOf(answer)).joinToString("\u001F").toByteArray(Charsets.UTF_8)) {
                hash = hash xor (byte.toLong() and 0xFF)
                hash *= 0x100000001b3L
            }
            return java.lang.Long.toUnsignedString(hash, 16)
        }

        fun key(id: String, version: String): String = if (version.isEmpty()) id else "$id#$version"
    }

    val hints: MutableMap<String, String> = HashMap()
    val order: MutableList<String> = mutableListOf()

    fun hint(id: String, version: String = ""): String? = hints[key(id, version)]

    fun store(hint: String, id: String, version: String = "") {
        val key = key(id, version)
        if (hints[key] == null) order += key
        hints[key] = hint
        while (order.size > cap) hints.remove(order.removeAt(0))
    }
}
