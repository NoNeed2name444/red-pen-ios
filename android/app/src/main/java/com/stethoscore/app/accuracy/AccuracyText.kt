package com.stethoscore.app.accuracy

import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.OsceChecklist
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.TextSlicing
import com.stethoscore.app.quiz.DifferentialEntry
import com.stethoscore.app.quiz.DifferentialTiers

/**
 * What a checker is shown for an item, and the source text it is checked
 * against - for the verification layer, Explain it back and voice marking.
 * Port of iOS Shared/Accuracy/AccuracyText.swift (with CheckedQuestion's
 * lettering from Shared/LLM/LLMParsing.swift and DifferentialTiers.checkText
 * from Models/Differential.swift, which Android's models do not have).
 */
object AccuracyText {

    const val noSourceNote = "No source document was provided. Judge the output against standard, current medical teaching for students; treat any claim that contradicts it as a fabricated claim."

    /**
     * What the checker is shown for a question - here and on the server alike.
     * Lettered A, B, C ... for any number of options, so a sixth option is not
     * a second "E" and a key of -1 cannot crash it.
     */
    fun checkText(q: MCQQuestion): String =
        checkedQuestion(q.stem, q.options, q.correctIndex, q.explanation) + differentialBlock(DifferentialTiers.fromQuestionJson(q.rawJson))

    /** "A", "B" ... "Z" for any number of options, the same lettering the deck and the quiz show; past Z, the option's number. */
    fun letter(index: Int): String = if (index in 0 until 26) ('A' + index).toString() else (index + 1).toString()

    /**
     * A question as the checker reads it (iOS CheckedQuestion.text). A key that
     * points at no option (a hand-written or imported file's -1) is said to be
     * missing rather than read out of range.
     */
    fun checkedQuestion(stem: String, options: List<String>, correctIndex: Int, explanation: String): String {
        val lines = options.mapIndexed { i, option -> letter(i) + ". " + option }
        val key = if (correctIndex in options.indices) letter(correctIndex) else "none keyed"
        return stem + "\n" + lines.joinToString("\n") + "\nAnswer: " + key + "\nExplanation: " + explanation
    }

    /** The writer's differential, for the reasoning checks to test the keyed answer against - the same block jobs.js adds on the server. */
    fun differentialBlock(d: DifferentialTiers?): String {
        if (d == null || d.isEmpty) return ""
        return "\nDifferential:\n" + differentialText(d)
    }

    /** The differential as one block of text, a line a tier - the same wording as the server's jobs.js differentialText (iOS DifferentialTiers.checkText). */
    fun differentialText(d: DifferentialTiers): String {
        val lines = mutableListOf<String>()
        for ((title, entries) in listOf("Most likely" to d.mostLikely, "Expanded" to d.expanded, "Can’t miss" to d.cantMiss)) {
            if (entries.isEmpty()) continue
            lines += "- " + title + ": " + entries.joinToString("; ") { describe(it) }
        }
        return lines.joinToString("\n")
    }

    private fun describe(e: DifferentialEntry): String {
        val parts = mutableListOf<String>()
        if (e.supporting.isNotEmpty()) parts += "for: " + e.supporting.joinToString(", ")
        if (e.against.isNotEmpty()) parts += "against: " + e.against.joinToString(", ")
        if (e.test.isNotEmpty()) parts += "test: " + e.test
        return if (parts.isEmpty()) e.name else e.name + " (" + parts.joinToString("; ") + ")"
    }

    fun checkText(station: OsceChecklist): String = station.title + "\n" + station.steps.joinToString("\n") { "- $it" }

    /**
     * The pages of a set's sources that share the most words with [text], up to
     * [limit] characters. A check against the right page is a real check; a
     * check against the first 8,000 characters of a 300-page lecture is a coin
     * toss.
     *
     * A page bigger than what is left of [limit] - a whole Word lecture is one
     * page - is cut to its own nearest paragraphs (TextSlicing.nearestPages)
     * rather than skipped, so a Word source is still checked against. Null when
     * the set has no source or no page shares a word with [text].
     */
    fun reference(text: String, set: StudySet, limit: Int): String? {
        val pages = set.sources.flatMap { doc -> doc.pages.map { page -> "${doc.name}, ${page.number}:\n" to page.text } }
        if (pages.isEmpty()) return null
        return TextSlicing.nearestPages(pages, text, limit)
    }
}
