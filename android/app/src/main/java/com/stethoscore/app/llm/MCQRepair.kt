package com.stethoscore.app.llm

import com.stethoscore.app.accuracy.AccuracyRules
import com.stethoscore.app.data.MCQQuestion

/**
 * An explanation that names an option by its place - "option B", "the
 * second option", "the correct answer is C" - rewritten to name it by its
 * words. Port of iOS Shared/MCQRepair.swift (T0234).
 *
 * The options are shown shuffled, so a place written when the question was
 * made points at whichever option happens to sit there on screen. The prompt
 * forbids it (MCQPrompt, rule 6), and small models write it anyway: a 4B
 * on-device writer did in five explanations out of five on the same prompt.
 * Naming the option by its own words is what the prompt asked for in the first
 * place, and it stays right in any order.
 *
 * It is careful about what it touches, because clinical English is full of
 * "choice" and "option":
 *  - only a capital letter is a letter reference, so "the drug of choice a
 *    decade ago" is left alone, and only one of this question's letters;
 *  - a number counts only after "option" or "choice", from 1 up (never
 *    "option 0"), and only when what follows reads as the end of a
 *    reference ("option 2 is...", "option 2,") - so "the drug of choice
 *    2 weeks after" stays as written;
 *  - an ordinal counts only when it ends the reference in the same way, so
 *    "the second choice after metformin" and "the first option for
 *    hypertension" stay as written;
 *  - the letter of "choice B" is the B, not the first a-to-e letter in the
 *    phrase.
 *
 * An explanation whose stated answer disagrees with the key is left exactly
 * as it is: the accuracy rules read the stored text, and rewriting "Option C
 * is correct" on a question keyed B into the option's words would hide the
 * one sentence that shows the key is wrong (AccuracyRules'
 * key-explanation-conflict, which grades the set).
 *
 * Lengths are not touched here: padding a distractor to hide a length
 * giveaway would put filler into a revision question, and
 * MCQPrompt.isValidQuestion already turns those questions away.
 *
 * Nothing is dropped and no key is changed: a question that cannot be
 * repaired comes back as it went in, for the accuracy rules to flag. As on
 * iOS, a missing explanation stays empty.
 *
 * No Android types, so it is tested on the JVM.
 */
object MCQRepair {

    data class Result(
        val text: String,
        /** How many references were rewritten. */
        val rewritten: Int,
    )

    private class Edit(val start: Int, val end: Int, val text: String, val count: Int)

    /** The question with its explanation's position references rewritten. */
    fun repaired(question: MCQQuestion): MCQQuestion =
        question.copy(explanation = rewrite(question.explanation, question.options, question.correctIndex).text)

    fun rewrite(explanation: String, options: List<String>, correctIndex: Int): Result {
        val unchanged = Result(explanation, 0)
        if (explanation.isEmpty() || options.size < 2) return unchanged
        val said = AccuracyRules.explainedAnswer(explanation, options)
        if (said != null && said != correctIndex) return unchanged
        val names = shortNames(options)
        val edits = mutableListOf<Edit>()

        fun unclaimed(start: Int, end: Int): Boolean = edits.none { it.start < end && start < it.end }
        fun quoted(index: Int): String = "\"" + names[index] + "\""

        // 1. a list: "Options B and C", "options A, C or D"
        for (m in found(LIST, explanation)) {
            if (!unclaimed(m.start, m.end)) continue
            val letters = m.groups[1] ?: continue
            val tokens = found(LETTER_TOKEN, letters)
            val indices: List<Int?> = tokens.map { letterIndex(it.groups[1], options.size) }
            if (tokens.isEmpty() || indices.any { it == null }) continue
            val out = StringBuilder(letters)
            for (i in tokens.indices.reversed()) out.replace(tokens[i].start, tokens[i].end, quoted(indices[i] ?: 0))
            edits += Edit(m.start, m.end, out.toString(), tokens.size)
        }
        // 2. the answer stated: "the correct answer is C", "Answer: (C)" -
        //    the words before the letter stay
        for (m in found(STATED, explanation)) {
            if (!unclaimed(m.start, m.end)) continue
            val index = letterIndex(m.groups[2], options.size) ?: continue
            edits += Edit(m.start, m.end, (m.groups[1] ?: "") + quoted(index), 1)
        }
        // 3. one letter: "option B", "the choice (B)", "answer B"
        for (m in found(LETTER, explanation)) {
            if (!unclaimed(m.start, m.end)) continue
            val index = letterIndex(m.groups[1], options.size) ?: continue
            edits += Edit(m.start, m.end, quoted(index), 1)
        }
        // 4. a number: "option 2", models count from 1
        for (m in found(NUMBER, explanation)) {
            if (!unclaimed(m.start, m.end)) continue
            val n = m.groups[1]?.toIntOrNull() ?: continue
            if (n < 1 || n > options.size) continue
            edits += Edit(m.start, m.end, quoted(n - 1), 1)
        }
        // 5. an ordinal: "the second option", "the last choice"
        for (m in found(ORDINAL, explanation)) {
            if (!unclaimed(m.start, m.end)) continue
            val word = (m.groups[1] ?: "").lowercase()
            val index = if (word == "last") options.size - 1 else ordinals.indexOf(word).let { if (it < 0) options.size else it }
            if (index >= options.size) continue
            edits += Edit(m.start, m.end, quoted(index), 1)
        }

        if (edits.isEmpty()) return unchanged
        val out = StringBuilder(explanation)
        for (edit in edits.sortedByDescending { it.start }) out.replace(edit.start, edit.end, edit.text)
        return Result(out.toString(), edits.sumOf { it.count })
    }

    private fun found(pattern: String, text: String): List<AccuracyRules.Found> = AccuracyRules.find(pattern, text)

    // MARK: naming an option

    /**
     * What each option is called in a rewritten explanation: its short
     * name, or its whole text when two options' short names are the same -
     * look-alike distractors are what the prompt asks for, so "Hyperkalaemia
     * with peaked T waves" and "...with flattened T waves" both shorten to
     * "Hyperkalaemia", and a name two options share names neither.
     */
    fun shortNames(options: List<String>): List<String> {
        val short = options.map(::shortName)
        return options.indices.map { i ->
            val key = short[i].lowercase()
            val clash = short.indices.any { it != i && short[it].lowercase() == key }
            if (clash) whole(options[i]) else short[i]
        }
    }

    /**
     * The leading phrase that names an option: cut at the first clause
     * ("..., which", "... with", "... that"), at most six words, and never
     * ending on a word that cannot end a phrase - a six-word cut once gave
     * "The malar rash is chronic and".
     */
    fun shortName(option: String): String {
        val full = whole(option)
        var text = full
        val cut = AccuracyRules.find(CLAUSE, text, caseless = true).firstOrNull()
        if (cut != null && cut.start > 0) text = text.substring(0, cut.start)
        val words = splitWhere(text) { it.isWhitespace() }.toMutableList()
        while (words.size > 6) words.removeAt(words.size - 1)
        while (words.isNotEmpty() && words.last().lowercase() in dangling) words.removeAt(words.size - 1)
        return if (words.isEmpty()) full else words.joinToString(" ")
    }

    /** The pieces of [text] between characters that satisfy [isSeparator], empty pieces left out (Swift's split(whereSeparator:)). */
    private fun splitWhere(text: String, isSeparator: (Char) -> Boolean): List<String> {
        val out = mutableListOf<String>()
        var from = -1
        for (i in text.indices) {
            if (isSeparator(text[i])) {
                if (from >= 0) { out += text.substring(from, i); from = -1 }
            } else if (from < 0) {
                from = i
            }
        }
        if (from >= 0) out += text.substring(from)
        return out
    }

    private fun whole(option: String): String = option.trim().trimEnd('.')

    private val dangling: Set<String> = setOf(
        "and", "or", "but", "with", "without", "that", "which", "is", "are",
        "was", "were", "the", "a", "an", "in", "of", "to", "for", "from",
        "on", "at", "by", "as", "its", "it", "this", "these",
    )

    // MARK: reading a reference

    private val ordinals: List<String> = listOf("first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth")

    /** A capital letter's option, or null when the question has no such option. */
    private fun letterIndex(letter: String?, count: Int): Int? {
        if (letter == null || letter.length != 1) return null
        val value = letter[0].code
        if (value < 65 || value > 74) return null
        val index = value - 65
        return if (index < count) index else null
    }

    /** Where the first clause of an option ends: ", ", "; ", ": " or " with", " that", " due to"... */
    private const val CLAUSE = """[,;:]\s|\s+(?:with|without|that|which|who|whose|where|because|due\s+to)\b"""

    /**
     * What may follow a number or an ordinal for it to be a reference:
     * the end, punctuation (not a decimal point), or a word a sentence
     * about an option goes on with. "option 2 weeks" is not one.
     */
    private const val ENDS = """(?=\s*$|\s*[,;:!?)\]]|\.(?!\d)|\s+(?:is|was|would|does|did|can|could|may|might|has|had|and|or|but|because|since|as|describes|refers|represents|correctly|incorrectly|also|alone|here|do|are|were|will|should|must)\b)"""

    // "C. difficile" and "E. coli" are not options C and E
    private const val LETTER_END = """(?![A-Za-z0-9\-])(?!\.\s?[a-z])"""

    private const val LIST = """\b[Oo]ptions\s+(\(?[A-J]\)?(?:(?:\s*,\s*|,?\s+(?:and|or)\s+)\(?[A-J]\)?)+)""" + LETTER_END
    private const val LETTER_TOKEN = """\(?([A-J])\)?"""
    private const val STATED =
        """\b((?:[Tt]he\s+)?(?:(?:correct|right|best)\s+)?(?:[Aa]nswer|[Oo]ption|[Cc]hoice)(?:\s+is\s+|\s*:\s*))(?:[Oo]ption\s+)?\(?([A-J])\)?""" + LETTER_END
    private const val LETTER = """\b(?:[Tt]he\s+)?(?:[Oo]ption|[Cc]hoice|[Aa]nswer)\s+\(?([A-J])\)?""" + LETTER_END
    private const val NUMBER = """\b(?:[Tt]he\s+)?(?:[Oo]ption|[Cc]hoice)\s+\(?([0-9])\)?""" + ENDS
    private const val ORDINAL =
        """\b[Tt]he\s+(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|last)\s+(?:option|choice|answer)""" + ENDS
}
