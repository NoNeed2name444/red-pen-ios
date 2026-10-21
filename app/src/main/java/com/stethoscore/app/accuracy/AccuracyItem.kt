package com.stethoscore.app.accuracy

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.CaseFile
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.OsceChecklist
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind

/**
 * What the accuracy engine checks: one question, card, case, OSCE station,
 * textbook page, stretch of a narrated lecture's facts, or - only when the
 * student asks - one of their own notes. Port of iOS Shared/Accuracy/AccuracyItem.swift.
 */
@Suppress("EnumEntryName")
enum class AccuracyKind(val rawValue: String, val noun: String) {
    mcq("mcq", "question"), card("card", "card"), case("case", "case"), osce("osce", "station"),
    page("page", "page"), fact("fact", "passage"), note("note", "note"),
}

/**
 * One item as the server's /accuracy/check reads it: a question's parts, or
 * the text of anything else, and the lecture excerpt it is checked against.
 */
data class AccuracyItem(
    /** Which item in the app this is: a question's, card's, case's or station's id. */
    val id: String,
    val kind: AccuracyKind,
    val stem: String = "",
    val options: List<String> = emptyList(),
    val key: Int = -1,
    val explanation: String = "",
    val text: String = "",
    val source: String = "",
) {
    /** The words the checker, the cache and the rules see - the same as itemText in server/accuracy-rules.js. */
    val checkedText: String get() {
        if (kind != AccuracyKind.mcq) return text.trim()
        val lines = mutableListOf(stem)
        options.forEachIndexed { i, option -> lines += letter(i) + ". " + option }
        val keyed = if (key in options.indices) letter(key) + ". " + options[key] else "none"
        lines += "Keyed answer: $keyed"
        lines += "Explanation: $explanation"
        return lines.joinToString("\n").trim()
    }

    /** The cache key: the item's content and its source excerpt. FNV-1a, twice with different seeds. */
    val contentHash: String get() {
        val body = "v1|" + kind.rawValue + "|" + checkedText + "|" + source.trim()
        return fnv(body, 0xcbf29ce484222325uL) + fnv(body, 0x84222325cbf29ce4uL)
    }

    companion object {
        const val sourceLimit = 1400

        fun letter(index: Int): String = if (index in 0 until 26) (65 + index).toChar().toString() else "?"

        fun fnv(text: String, seed: ULong): String {
            var hash = seed
            for (byte in text.toByteArray(Charsets.UTF_8)) {
                hash = hash xor byte.toUByte().toULong()
                hash *= 0x100000001b3uL
            }
            return hash.toString(16).padStart(16, '0')
        }

        fun mcq(q: MCQQuestion, source: String = ""): AccuracyItem =
            AccuracyItem(q.id, AccuracyKind.mcq, stem = q.stem, options = q.options, key = q.correctIndex, explanation = q.explanation, source = source.take(sourceLimit))

        /** A card as question and answer; an image-occlusion card with no words has nothing to check and gives null. */
        fun card(c: AnkiCard, source: String = ""): AccuracyItem? {
            val lines = mutableListOf<String>()
            if (c.type == AnkiCardType.CLOZE) {
                lines += "Cloze: " + c.clozeText
            } else {
                val front = c.front.trim()
                if (c.type == AnkiCardType.OCCLUSION && front.isEmpty()) return null
                lines += "Q: $front"
                if (c.bullets.isNotEmpty()) lines += "A: " + c.bullets.joinToString("; ")
            }
            val why = c.why.trim()
            if (why.isNotEmpty()) lines += "Why: $why"
            val text = lines.joinToString("\n")
            if (text.length <= 8) return null
            return AccuracyItem(c.id, AccuracyKind.card, text = text, source = source.take(sourceLimit))
        }

        fun osce(s: OsceChecklist, source: String = ""): AccuracyItem =
            AccuracyItem(s.id, AccuracyKind.osce, text = s.title + "\n" + s.steps.joinToString("\n") { "- $it" }, source = source.take(sourceLimit))

        /** A patient case: what it asserts (CaseFile.assertedText), as one item. */
        fun caseFile(f: CaseFile, source: String = ""): AccuracyItem =
            AccuracyItem(f.id, AccuracyKind.case, text = f.assertedText, source = source.take(sourceLimit))

        /** A student's own note, checked only when they ask. */
        fun note(id: String, title: String, body: String): AccuracyItem =
            AccuracyItem(id, AccuracyKind.note, text = (title + "\n" + body).take(3400))

        /**
         * Every checkable item of a set, in the set's own order. `source` finds
         * the lecture excerpt for an item's words; null means the set has no
         * source. Textbook pages and narrated facts come with their own batches
         * (9 and 12); until then those sets give no items here.
         */
        fun items(set: StudySet, source: (String) -> String? = { null }): List<AccuracyItem> {
            fun src(words: String): String = source(words) ?: ""
            return when (set.kind) {
                StudySetKind.MCQ -> set.questions.map { q -> mcq(q, src(mcq(q).checkedText)) }
                StudySetKind.ANKI -> set.cards.mapNotNull { c -> card(c)?.let { base -> card(c, src(base.checkedText)) } }
                StudySetKind.OSCE -> set.osceChecklists.map { s -> osce(s, src(osce(s).checkedText)) }
                StudySetKind.CASES -> set.caseFiles.map { f -> caseFile(f, src(f.assertedText)) }
                StudySetKind.BOOK, StudySetKind.NARRATE -> emptyList()
            }
        }
    }
}
