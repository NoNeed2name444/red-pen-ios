package com.stethoscore.app.data

import java.io.InputStream
import java.util.zip.ZipInputStream

// The logic under the library's editors (iOS Features/Library, fed0105), ported
// from the files that hold it: CardStyle and DiagramCards (Shared/CardStyle.swift),
// MCQCoverage.suggestedCount (CardQuality.clozeHoles is in QuizFromCards.kt)
// (Shared/MCQCoverage.swift), MCQGenerator.maxQuestionsTotal, ReadSource
// (LecturePDFSection.swift), and the words and counts of LecturePDFSection and
// LectureWriterSection. Pure Kotlin (MCQCoverageTest, LibraryEditorsTest).

/** What kind of cards to make from a lecture. */
enum class CardStyle(val title: String) {
    mixed("Mixed (all types)"), qa("Question & answer"), cloze("Cloze deletion"), image("Image occlusion");

    /** Whether the writer writes any text cards for this style. */
    val writesText: Boolean get() = this != image
    /** Whether the lecture's labelled diagrams become cards. */
    val usesDiagrams: Boolean get() = this == mixed || this == image
}

/** Cards made from the lecture's labelled diagrams, with the pictures they point into. */
data class DiagramCards(val cards: List<AnkiCard> = emptyList(), val images: List<String> = emptyList(), val included: Boolean = false)

object MCQCoverage {
    /** How many questions a source of this many characters can support: about a paragraph each. */
    fun suggestedCount(forCharacters: Int, perQuestion: Int = 320, floor: Int = 5, ceiling: Int = 200): Int {
        if (forCharacters <= 0) return floor
        return minOf(ceiling, maxOf(floor, forCharacters / perQuestion))
    }
}

object MCQGenerator {
    /** The most questions one set is written with. */
    const val maxQuestionsTotal = 10_000
}

/** What a file gave us, kept so that what is written later can be cited back to its page. */
data class ReadSource(val name: String, val pages: List<SourcePage>, val kind: String = "pdf", val fileBlob: String? = null) {
    /** The whole text, pages in order. */
    val text: String get() = pages.map { it.text }.filter { it.isNotBlank() }.joinToString("\n\n")
    /** Pages read by OCR. */
    val recognisedPages: Int get() = pages.count { it.recognised }
    /** The keepable form, to store on the set; blank pages are kept so citations keep their numbers. */
    fun doc(): SourceDoc = SourceDoc(name = name, kind = kind, pages = pages, fileBlob = fileBlob)
}

/** The words and counts of the lecture sections of New set (LecturePDFSection, LectureWriterSection). */
object LectureForms {
    /** LecturePDFSection.kind(of:): what kind of document, by its extension. */
    fun kind(extension: String): String = when (extension.lowercase()) {
        "pdf" -> "pdf"
        "docx", "doc" -> "word"
        "pptx", "ppt" -> "powerpoint"
        else -> "text"
    }

    /** LectureWriterSection.fileKind: PDF, PowerPoint or Word. */
    fun writerFileKind(extension: String): String = when (extension) {
        "pdf" -> "pdf"
        "pptx" -> "powerpoint"
        else -> "word"
    }

    /** The count a lecture proposes to the writer: a page in three for a textbook, about a card for every two slides. */
    fun writerCount(book: Boolean, pages: Int): Int =
        if (book) minOf(30, maxOf(1, pages / 3)) else minOf(80, maxOf(8, (pages / 2 + 3) / 4 * 4))

    /** What reading a lecture file found, under the file button (LecturePDFSection.summary). */
    fun pdfSummary(pages: Int, ocr: Int, figures: Int, cards: Int, questionCount: Int): String {
        val pagePlural = if (pages == 1) "" else "s"
        val recognised = if (ocr > 0) ", $ocr by OCR" else ""
        val figurePlural = if (figures == 1) "" else "s"
        val found = if (cards == 0) "" else ", $figures labelled diagram$figurePlural"
        return "Read $pages page$pagePlural$recognised$found. $questionCount questions suits this much material."
    }

    /** The file button of the question form. */
    fun pdfPickTitle(reading: Boolean, hasFile: Boolean): String = when {
        reading -> "Reading the file…"
        !hasFile -> "Choose a lecture file"
        else -> "Add another file"
    }

    /** The file button of the card and textbook form. */
    fun writerPickTitle(reading: Boolean, hasFile: Boolean): String = when {
        reading -> "Reading…"
        !hasFile -> "Choose a lecture file"
        else -> "Choose a different file"
    }

    /** Make's words in the card and textbook form. */
    fun writerActionTitle(book: Boolean, style: CardStyle, count: Int, diagrams: Int): String {
        if (!book && style == CardStyle.image) return "Add $diagrams image card${if (diagrams == 1) "" else "s"}"
        val noun = if (book) "page" else "card"
        return "Make $count $noun${if (count == 1) "" else "s"}"
    }

    /** The note under the card type when diagrams are used. */
    fun diagramNote(found: Int): String =
        if (found == 0) "No labelled diagrams were found in this file." else "$found picture card${if (found == 1) "" else "s"} from the file's diagrams."

    /** Whether there is enough to write from: more than 200 characters. */
    fun hasSource(text: String): Boolean = text.trim().length > 200
}

/**
 * Reading a Word or PowerPoint file's words on the device (iOS OfficeIngest's
 * text): a .docx is one page of paragraphs, a .pptx one page per slide.
 * Both are zips of XML, so nothing beyond the platform is needed.
 */
object OfficeText {
    class Unreadable(message: String) : Exception(message)

    /** The pages of a .docx or .pptx, by [extension]. */
    fun read(stream: InputStream, extension: String): List<SourcePage> {
        val entries = mutableMapOf<String, String>()
        ZipInputStream(stream).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = entry.name
                val wanted = name == "word/document.xml" || Regex("ppt/slides/slide\\d+\\.xml").matches(name)
                if (wanted) entries[name] = zip.readBytes().toString(Charsets.UTF_8)
            }
        }
        return when (extension.lowercase()) {
            "docx" -> {
                val xml = entries["word/document.xml"] ?: throw Unreadable("That file could not be read as a Word document.")
                listOf(SourcePage(1, paragraphs(xml, "w")))
            }
            "pptx" -> {
                val slides = entries.keys.mapNotNull { key -> Regex("ppt/slides/slide(\\d+)\\.xml").matchEntire(key)?.let { it.groupValues[1].toInt() to key } }
                    .sortedBy { it.first }
                if (slides.isEmpty()) throw Unreadable("That file could not be read as a PowerPoint deck.")
                slides.mapIndexed { i, (_, key) -> SourcePage(i + 1, paragraphs(entries.getValue(key), "a")) }
            }
            else -> throw Unreadable("PDF, Word or PowerPoint files only.")
        }
    }

    /** The text of each `<p>` in the namespace [ns], one line each, blanks dropped. */
    fun paragraphs(xml: String, ns: String): String {
        val paragraph = Regex("<$ns:p[ >][\\s\\S]*?</$ns:p>|<$ns:p>[\\s\\S]*?</$ns:p>")
        val run = Regex("<$ns:t(?:\\s[^>]*)?>([\\s\\S]*?)</$ns:t>|<$ns:tab/>|<$ns:br/>")
        return paragraph.findAll(xml).map { p ->
            run.findAll(p.value).joinToString("") { m ->
                when {
                    m.value.startsWith("<$ns:tab") -> "\t"
                    m.value.startsWith("<$ns:br") -> "\n"
                    else -> unescape(m.groupValues[1])
                }
            }.trim()
        }.filter { it.isNotEmpty() }.joinToString("\n")
    }

    private fun unescape(text: String): String = text
        .replace(Regex("&#(\\d+);")) { it.groupValues[1].toIntOrNull()?.let { c -> String(Character.toChars(c)) } ?: it.value }
        .replace(Regex("&#x([0-9a-fA-F]+);")) { it.groupValues[1].toIntOrNull(16)?.let { c -> String(Character.toChars(c)) } ?: it.value }
        .replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")
}
