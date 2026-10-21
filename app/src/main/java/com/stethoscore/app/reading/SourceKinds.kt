package com.stethoscore.app.reading

import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage

// What ios/RedPen/Models/SourceDoc.swift (fed0105) knows about a lecture that
// Android's SourceDoc (data/Models.kt, where kind is kept as its raw string)
// does not say itself: its kind's label and page noun, a page's heading, and
// the page by its number. Provenance.label, how a citation is written, too.

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

/** How a citation is written (iOS Provenance.label): "Lupus, p. 14", or "p. 14" for a lecture with no name. */
object Provenance {
    fun label(name: String, page: Int): String = if (name.isEmpty()) "p. $page" else "$name, p. $page"
}
