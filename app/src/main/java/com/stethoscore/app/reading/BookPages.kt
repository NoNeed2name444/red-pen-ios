package com.stethoscore.app.reading

// A port of ios/RedPen/Shared/BookPages.swift (fed0105): a textbook set's
// Markdown split into pages at its `#` and `##` headings, and each page read
// into blocks (headings, bullets with their numbers, table rows with their
// header, callouts, flowcharts and pictures). Pure Kotlin (ReadingTest).

/** A textbook page: the web app's Markdown, split into pages at headings. */
data class BookPage(val id: Int, val title: String, val markdown: String)

/** Swift's `.whitespaces`: spaces and tabs, not line ends. */
internal fun String.trimSpaces(): String =
    trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }

object BookPages {
    private val pageHeading = Regex("^#{1,2}\\s+")
    private val anyHeading = Regex("^#{1,6}\\s+")
    private val listMarker = Regex("^([-*•]|\\d+[.)])\\s+")
    private val calloutKind = Regex("^\\*\\*([^*]{2,24}?):?\\*\\*:?\\s*")

    /**
     * How many pages [split] would make, remembered: the library shows a
     * textbook's page count on its row, and splitting the whole book on
     * every redraw is the slowest thing there.
     */
    fun pageCount(markdown: String): Int {
        synchronized(pageCounts) { pageCounts[markdown]?.let { return it } }
        val fresh = split(markdown).size
        synchronized(pageCounts) {
            // a handful of books at most; forgetting them all is simpler than keeping an order
            if (pageCounts.size >= 64) pageCounts.clear()
            pageCounts[markdown] = fresh
        }
        return fresh
    }

    private val pageCounts = HashMap<String, Int>()

    /**
     * Every `#` or `##` heading starts a page; text before the first heading
     * is a page of its own called "Introduction".
     */
    fun split(markdown: String): List<BookPage> {
        val pages = mutableListOf<BookPage>()
        var title = "Introduction"
        val body = mutableListOf<String>()
        fun flush() {
            val text = body.joinToString("\n").trim()
            if (text.isNotEmpty()) pages += BookPage(pages.size, title, text)
            body.clear()
        }
        for (line in markdown.split("\n")) {
            val m = pageHeading.find(line)
            if (m != null) {
                flush()
                title = line.substring(m.range.last + 1).trimSpaces()
                body += line
            } else {
                body += line
            }
        }
        flush()
        return pages
    }

    /** One block of a page. */
    sealed class Block {
        data class Heading(val level: Int, val text: String) : Block()
        data class Bullet(val text: String, val marker: String?) : Block()
        data class Paragraph(val text: String) : Block()
        /** A table row; [header] for the row above the |---| line. */
        data class Row(val cells: List<String>, val header: Boolean = false) : Block()
        /** A boxed aside: "Key point", "Exam tip", "Red flag", "Mnemonic"... */
        data class Callout(val kind: String, val text: String) : Block()
        /** A pathway drawn as boxes and arrows, one step per line. */
        data class Flow(val steps: List<String>) : Block()
        /** A picture of the set (an index into StudySet.images) and its caption. */
        data class Image(val index: Int, val caption: String) : Block()
    }

    private fun isSeparator(line: String): Boolean =
        line.startsWith("|") && line.replace(" ", "").split("|").filter { it.isNotEmpty() }
            .all { cell -> cell.all { it == '-' || it == ':' } }

    fun blocks(markdown: String): List<Block> {
        val out = mutableListOf<Block>()
        val para = mutableListOf<String>()
        var flow: MutableList<String>? = null
        fun flushPara() {
            val t = para.joinToString(" ").trimSpaces()
            if (t.isNotEmpty()) out += Block.Paragraph(t)
            para.clear()
        }
        val lines = markdown.split("\n").map { it.trimSpaces() }
        for ((i, line) in lines.withIndex()) {
            // a flowchart: ```flow ... ```
            val open = flow
            if (open != null) {
                if (line.startsWith("```")) {
                    out += Block.Flow(open.filter { it.isNotEmpty() })
                    flow = null
                } else {
                    open += line.replace(listMarker, "")
                }
                continue
            }
            if (line.startsWith("```")) {
                flushPara()
                val lower = line.lowercase()
                if (lower.contains("flow") || lower.contains("mermaid")) flow = mutableListOf()
                continue
            }
            if (line.isEmpty()) { flushPara(); continue }
            val picture = BookFigures.parse(line)
            val heading = anyHeading.find(line)
            val bullet = listMarker.find(line)
            when {
                picture != null -> {
                    flushPara()
                    out += Block.Image(picture.first, picture.second)
                }
                line.startsWith(">") -> {
                    flushPara()
                    var text = line.dropWhile { it == '>' || it == ' ' }
                    var kind = "Note"
                    val m = calloutKind.find(text)
                    if (m != null) {
                        kind = m.value.replace("*", "").trim { it == ':' || it == ' ' }
                        text = text.substring(m.range.last + 1)
                    }
                    out += Block.Callout(kind, text)
                }
                heading != null -> {
                    flushPara()
                    val level = heading.range.last + 1 - 1
                    out += Block.Heading(minOf(level, 3), line.substring(heading.range.last + 1))
                }
                bullet != null -> {
                    flushPara()
                    val marker = line.substring(0, bullet.range.last + 1).trimSpaces()
                    val numbered = marker.firstOrNull()?.isDigit() == true
                    out += Block.Bullet(line.substring(bullet.range.last + 1), if (numbered) marker else null)
                }
                line.startsWith("|") -> {
                    flushPara()
                    if (isSeparator(line)) continue
                    val cells = line.split("|").drop(1).dropLast(1).map { it.trimSpaces() }
                    val header = i + 1 < lines.size && isSeparator(lines[i + 1])
                    out += Block.Row(cells, header)
                }
                else -> para += line
            }
        }
        flow?.let { out += Block.Flow(it.filter { step -> step.isNotEmpty() }) }
        flushPara()
        return out
    }

    /**
     * One written page made fit for the reader: exactly one page heading
     * ("## "), every other heading a section inside it ("### "), and only
     * the pictures this page was given, with any it did not place added at
     * the end.
     */
    fun tidyPage(written: String, fallbackTitle: String, figures: List<Int>): String {
        var titled = false
        val placed = mutableSetOf<Int>()
        val lines = written.trim().split("\n").mapNotNull { raw ->
            val line = raw.trimSpaces()
            val m = anyHeading.find(line)
            if (m != null) {
                val text = line.substring(m.range.last + 1)
                val level = m.range.last + 1 - 1
                if (!titled && level <= 2) { titled = true; return@mapNotNull "## $text" }
                return@mapNotNull (if (level <= 3) "### " else "#### ") + text
            }
            val picture = BookFigures.parse(line)
            if (picture != null) {
                // a picture the page was not given is a number the model made up
                if (picture.first !in figures || picture.first in placed) return@mapNotNull null
                placed += picture.first
            }
            raw
        }.toMutableList()
        if (!titled) { lines.add(0, "## $fallbackTitle"); lines.add(1, "") }
        val unplaced = figures.filter { it !in placed }
        if (unplaced.isNotEmpty()) {
            lines += listOf("", "### Figures from the lecture")
            lines += unplaced.map { "![Figure from the lecture](${BookFigures.reference(it)})" }
        }
        return lines.joinToString("\n")
    }
}
