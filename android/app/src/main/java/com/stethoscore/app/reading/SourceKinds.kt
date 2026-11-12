package com.stethoscore.app.reading

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.llm.MCQCoverage

// What ios/RedPen/Models/SourceDoc.swift (fed0105) knows about a lecture that
// Android's SourceDoc (data/Models.kt, where kind is kept as its raw string)
// does not say itself: its kind's label and page noun, a page's heading, and
// the page by its number. Provenance, how a citation is written and which page
// a generated question or card came off, too (ios/RedPen/Shared/Provenance.swift).

/** What a lecture was: a PDF, a Word file, slides or plain text. */
enum class SourceKind(val rawValue: String, val label: String) {
    pdf("pdf", "PDF"), word("word", "Word"), powerpoint("powerpoint", "Slides"), text("text", "Text");

    /** What a page of this is called: a deck of slides has slides. */
    val pageNoun: String get() = if (this == powerpoint) "Slide" else "Page"

    companion object {
        fun from(raw: String): SourceKind = entries.firstOrNull { it.rawValue == raw } ?: text
    }
}

val SourceDoc.sourceKind: SourceKind get() = SourceKind.from(kind)
val SourceDoc.pageCount: Int get() = pages.size
val SourceDoc.recognisedPages: Int get() = pages.count { it.recognised }
fun SourceDoc.page(number: Int): SourcePage? = pages.firstOrNull { it.number == number }

/** The first line with anything on it, for a page list. */
val SourcePage.heading: String get() {
    for (line in text.split("\n", "\r\n", "\r")) {
        val trimmed = line.trimSpaces()
        if (trimmed.isNotEmpty()) return trimmed.take(80)
    }
    return ""
}

val SourcePage.isBlank: Boolean get() = text.isBlank()

/**
 * Which page a generated question came off (iOS Shared/Provenance.swift).
 *
 * The model is not asked. Asking it to cite its own page invites it to invent
 * a plausible number, which is exactly the failure provenance exists to catch;
 * and a small on-device model asked to carry a citation through a long answer
 * usually drops it. So the attribution is made afterwards, by looking at which
 * page's text the question actually shares its words with. A question that
 * matches no page well gets no citation, which is itself worth seeing: it
 * means the question drifted from the source.
 *
 * iOS passes a SourceText.Document and the lecture's name; Android's pages are
 * [SourcePage] (what a ReadSource or SourceDoc holds), so these take the pages.
 */
object Provenance {

    /** How a citation is written: "Lupus, p. 14", or "p. 14" for a lecture with no name. */
    fun label(name: String, page: Int): String = if (name.isEmpty()) "p. $page" else "$name, p. $page"

    /**
     * The page sharing most of this text's own words, if any page shares
     * enough of them to be worth naming.
     *
     * Measured as a share of the QUESTION's words rather than the page's:
     * pages differ wildly in length, and dividing by the page would hand every
     * question to the shortest slide in the deck.
     */
    fun page(text: String, pages: List<SourcePage>, floor: Double = 0.3): Int? {
        val wanted = MCQCoverage.contentWords(text)
        if (wanted.isEmpty()) return null
        var bestShare = 0.0
        var bestPage: Int? = null
        for (page in pages) {
            val have = MCQCoverage.contentWords(page.text)
            if (have.isEmpty()) continue
            val share = (wanted intersect have).size.toDouble() / wanted.size
            if (share >= floor && (bestPage == null || share > bestShare)) {
                bestShare = share
                bestPage = page.number
            }
        }
        return bestPage
    }

    /**
     * Cites each question against the document it was generated from.
     *
     * The stem alone is not enough to go on - a vignette is written in the
     * model's own words - so the answer and explanation are weighed with it,
     * since those carry the source's terminology.
     */
    fun attribute(questions: List<MCQQuestion>, pages: List<SourcePage>, name: String): List<MCQQuestion> {
        if (pages.isEmpty()) return questions
        return questions.map { question ->
            val key = if (question.correctIndex in question.options.indices) question.options[question.correctIndex] else ""
            val material = listOf(question.stem, key, question.explanation).joinToString(" ")
            val found = page(material, pages)
            if (found != null) question.copy(source = label(name, found)) else question
        }
    }

    /** The same, for cards. */
    @JvmName("attributeCards")
    fun attribute(cards: List<AnkiCard>, pages: List<SourcePage>, name: String): List<AnkiCard> {
        if (pages.isEmpty()) return cards
        return cards.map { card ->
            // a figure card already knows its page exactly; nothing guessed
            // should overwrite something known
            if (card.source != null) return@map card
            val material = listOf(card.front, card.clozeText, card.bullets.joinToString(" "), card.why).joinToString(" ")
            val found = page(material, pages)
            if (found != null) card.copy(source = label(name, found)) else card
        }
    }
}
