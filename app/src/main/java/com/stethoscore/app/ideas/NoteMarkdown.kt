package com.stethoscore.app.ideas

// A port of NoteMarkdown (Features/Notes/NoteMarkdown.swift, fed0105): Markdown into
// blocks, and a line's inline styling, with `[[Title]]` and `[[Title|shown]]` as links
// to other notes. iOS reads the inline part with AttributedString's inline-only
// Markdown; here [inline] reads the same marks (bold, italic, code, strikethrough, links).

object NoteMarkdown {
    const val SCHEME = "vignette-note"
    const val EMPTY = "Nothing written yet."

    sealed class Block {
        data class Heading(val level: Int, val text: String) : Block()
        data class Bullet(val depth: Int, val marker: String, val text: String) : Block()
        data class Quote(val text: String) : Block()
        data class Code(val text: String) : Block()
        object Rule : Block()
        data class Paragraph(val text: String) : Block()
    }

    fun blocks(text: String): List<Block> {
        val out = ArrayList<Block>()
        val paragraph = ArrayList<String>()
        var code: MutableList<String>? = null
        fun flush() {
            if (paragraph.isNotEmpty()) out.add(Block.Paragraph(paragraph.joinToString(" ")))
            paragraph.clear()
        }
        for (raw in text.split("\n")) {
            val trimmed = raw.trim { it == ' ' || it == '\t' }
            if (trimmed.startsWith("```")) {
                val open = code
                if (open != null) { out.add(Block.Code(open.joinToString("\n"))); code = null } else { flush(); code = ArrayList() }
                continue
            }
            val open = code
            if (open != null) { open.add(raw); continue }
            if (trimmed.isEmpty()) { flush(); continue }
            val block = lineBlock(raw, trimmed)
            if (block != null) { flush(); out.add(block) } else paragraph.add(trimmed)
        }
        code?.let { out.add(Block.Code(it.joinToString("\n"))) }
        flush()
        return out
    }

    /** A heading, list item, quote or rule; null for plain text. */
    private fun lineBlock(raw: String, trimmed: String): Block? {
        if (trimmed == "---" || trimmed == "***" || trimmed == "___") return Block.Rule
        val hashes = trimmed.takeWhile { it == '#' }.length
        if (hashes in 1..6 && trimmed.drop(hashes).startsWith(" ")) return Block.Heading(hashes, trimmed.drop(hashes + 1))
        if (trimmed.startsWith("> ")) return Block.Quote(trimmed.drop(2))
        val indent = raw.takeWhile { it == ' ' || it == '\t' }.length
        val depth = minOf(indent / 2, 4)
        for (mark in listOf("- ", "* ", "+ ", "• ")) if (trimmed.startsWith(mark)) return Block.Bullet(depth, "•", trimmed.drop(mark.length))
        val digits = trimmed.takeWhile { it.isDigit() }
        if (digits.isNotEmpty() && digits.length <= 3) {
            val after = trimmed.drop(digits.length)
            if (after.startsWith(". ") || after.startsWith(") ")) return Block.Bullet(depth, "$digits.", after.drop(2))
        }
        return null
    }

    /** One run of a line, with its marks. [link] is a note's title for `[[...]]`, or a URL. */
    data class Span(val text: String, val bold: Boolean = false, val italic: Boolean = false, val code: Boolean = false,
                    val strike: Boolean = false, val noteLink: String? = null, val url: String? = null)

    /** Bold, italic, `code`, ~~strike~~ and links; `[[Title]]` becomes a link to that note. */
    fun inline(line: String): List<Span> {
        val spans = ArrayList<Span>()
        parse(line, Span(""), spans)
        // neighbours with the same marks run together
        val merged = ArrayList<Span>()
        for (s in spans) {
            if (s.text.isEmpty()) continue
            val last = merged.lastOrNull()
            if (last != null && last.copy(text = "") == s.copy(text = "")) merged[merged.size - 1] = last.copy(text = last.text + s.text) else merged.add(s)
        }
        return merged
    }

    private fun parse(text: String, marks: Span, out: MutableList<Span>) {
        val plain = StringBuilder()
        fun emit() { if (plain.isNotEmpty()) { out.add(marks.copy(text = plain.toString())); plain.clear() } }
        var i = 0
        while (i < text.length) {
            val rest = text.substring(i)
            when {
                rest.startsWith("\\") && rest.length > 1 && rest[1] in "\\`*_[]()#+-.!~|" -> { plain.append(rest[1]); i += 2 }
                rest.startsWith("[[") && rest.indexOf("]]", 2) > 2 -> {
                    val close = rest.indexOf("]]", 2)
                    val inner = rest.substring(2, close)
                    val parts = inner.split("|", limit = 2)
                    val title = parts[0].trim { it == ' ' || it == '\t' }
                    val shown = if (parts.size > 1) parts[1].trim { it == ' ' || it == '\t' } else title
                    emit()
                    out.add(marks.copy(text = shown.ifEmpty { title }, noteLink = title))
                    i += close + 2
                }
                rest.startsWith("`") && rest.indexOf('`', 1) > 0 -> {
                    val close = rest.indexOf('`', 1)
                    emit(); out.add(marks.copy(text = rest.substring(1, close), code = true)); i += close + 1
                }
                rest.startsWith("**") || rest.startsWith("__") -> {
                    val mark = rest.substring(0, 2)
                    val close = rest.indexOf(mark, 2)
                    if (close > 2) { emit(); parse(rest.substring(2, close), marks.copy(bold = true), out); i += close + 2 } else { plain.append(mark); i += 2 }
                }
                rest.startsWith("~~") -> {
                    val close = rest.indexOf("~~", 2)
                    if (close > 2) { emit(); parse(rest.substring(2, close), marks.copy(strike = true), out); i += close + 2 } else { plain.append("~~"); i += 2 }
                }
                (rest.startsWith("*") || rest.startsWith("_")) && rest.length > 1 && rest[1] != ' ' -> {
                    val mark = rest[0]
                    val close = rest.indexOf(mark, 1)
                    if (close > 1 && rest[close - 1] != ' ') { emit(); parse(rest.substring(1, close), marks.copy(italic = true), out); i += close + 1 } else { plain.append(mark); i++ }
                }
                rest.startsWith("[") -> {
                    val close = rest.indexOf("](")
                    val end = if (close > 0) rest.indexOf(')', close + 2) else -1
                    if (close > 0 && end > close) {
                        emit()
                        val url = rest.substring(close + 2, end)
                        parse(rest.substring(1, close), marks.copy(url = url), out)
                        i += end + 1
                    } else { plain.append('['); i++ }
                }
                else -> { plain.append(rest[0]); i++ }
            }
        }
        emit()
    }
}
