package com.stethoscore.app.ui

/** The reader uses the same heading boundaries as the current iOS BookPages. */
internal data class ReadingPage(val title: String, val markdown: String)

internal fun splitReadingPages(markdown: String): List<ReadingPage> {
    val pages = mutableListOf<ReadingPage>()
    var title = "Introduction"
    val body = mutableListOf<String>()
    fun flush() {
        val text = body.joinToString("\n").trim()
        if (text.isNotBlank()) pages += ReadingPage(title, text)
        body.clear()
    }
    for (line in markdown.lines()) {
        val heading = Regex("^#{1,2}\\s+(.+)").find(line)
        if (heading != null) {
            flush()
            title = heading.groupValues[1].trim()
        }
        body += line
    }
    flush()
    return pages
}

internal enum class ReadingBlockKind { HEADING, PARAGRAPH, BULLET, CALLOUT, TABLE_ROW, CODE }
internal data class ReadingBlock(val kind: ReadingBlockKind, val text: String, val level: Int = 0)

/** A small native block reader; no remote HTML or JavaScript is executed. */
internal fun readingBlocks(markdown: String): List<ReadingBlock> {
    val blocks = mutableListOf<ReadingBlock>()
    val paragraph = mutableListOf<String>()
    var code = false
    fun flush() {
        if (paragraph.isNotEmpty()) blocks += ReadingBlock(ReadingBlockKind.PARAGRAPH, paragraph.joinToString(" "))
        paragraph.clear()
    }
    for (raw in markdown.lines()) {
        val line = raw.trim()
        val heading = Regex("^(#{1,6})\\s+(.+)").find(line)
        val bullet = Regex("^([-*•]|\\d+[.)])\\s+(.+)").find(line)
        when {
            line.startsWith("```") -> { flush(); code = !code }
            code -> { flush(); if (line.isNotBlank()) blocks += ReadingBlock(ReadingBlockKind.CODE, line) }
            line.isBlank() -> flush()
            heading != null -> { flush(); blocks += ReadingBlock(ReadingBlockKind.HEADING, heading.groupValues[2], heading.groupValues[1].length) }
            bullet != null -> { flush(); blocks += ReadingBlock(ReadingBlockKind.BULLET, "${bullet.groupValues[1]}  ${bullet.groupValues[2]}") }
            line.startsWith(">") -> { flush(); blocks += ReadingBlock(ReadingBlockKind.CALLOUT, line.trimStart('>', ' ')) }
            line.startsWith("|") -> {
                flush()
                val cells = line.trim('|').split('|').map(String::trim)
                if (cells.any { cell -> cell.any { it != '-' && it != ':' && it != ' ' } }) {
                    blocks += ReadingBlock(ReadingBlockKind.TABLE_ROW, cells.joinToString("  ·  "))
                }
            }
            else -> paragraph += line
        }
    }
    flush()
    return blocks
}
