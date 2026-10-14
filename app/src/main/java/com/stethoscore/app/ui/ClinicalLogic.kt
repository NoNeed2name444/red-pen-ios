package com.stethoscore.app.ui

import com.stethoscore.app.data.CaseFile
import kotlin.math.roundToInt

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

internal data class ClinicalScore(
    val diagnosis: Int,
    val nextStep: Int,
    val keyFindings: Int,
    val redFlags: Int,
    val time: Int,
    val capped: Boolean,
) {
    val total: Int get() = (diagnosis + nextStep + keyFindings + redFlags + time).let { if (capped) it.coerceAtMost(60) else it }
}

internal fun diagnosisMatches(answer: String, file: CaseFile): Boolean {
    fun normalise(value: String) = value.lowercase().trim().replace(Regex("[^\\p{L}\\p{N} ]"), "").replace(Regex("\\s+"), " ")
    val given = normalise(answer)
    return given.isNotEmpty() && (listOf(file.diagnosis.name) + file.diagnosis.accepted).any { normalise(it) == given }
}

/** Scoring transcribed from docs/design/cases-rebuild.md; the component scores stay visible. */
internal fun scoreClinicalCase(file: CaseFile, taken: Set<String>, diagnosis: String, nextStep: Int): ClinicalScore {
    val found = file.steps.filter { it.id in taken }
    val key = file.steps.filter { it.value.equals("key", ignoreCase = true) }
    val flags = file.steps.filter { it.redFlag }
    val low = found.count { it.value.equals("low", ignoreCase = true) }
    val elapsed = found.sumOf { it.minutes }
    fun proportion(points: Int, all: Int, seen: Int) = if (all == 0) points else (points.toDouble() * seen / all).roundToInt()
    return ClinicalScore(
        diagnosis = if (diagnosisMatches(diagnosis, file)) 30 else 0,
        nextStep = if (nextStep == file.nextStep.key) 20 else 0,
        keyFindings = proportion(25, key.size, key.count { it.id in taken }),
        redFlags = proportion(15, flags.size, flags.count { it.id in taken }),
        time = (10 - (low - 1).coerceAtLeast(0) * 2 - if (elapsed > file.budgetMinutes) 5 else 0).coerceAtLeast(0),
        capped = file.steps.any { it.mustNotMiss && it.redFlag && it.id !in taken },
    )
}
