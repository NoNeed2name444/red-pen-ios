package com.stethoscore.app.export

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.CaseFile
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.NarrateSegment
import com.stethoscore.app.data.OsceChecklist
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.ui.ReadingBlockKind
import com.stethoscore.app.ui.readingBlocks
import com.stethoscore.app.ui.splitReadingPages

// Printing a set as a flashcard deck: port of ios/RedPen/Shared/DeckCard.swift. Every mode
// reduces to question/answer cards here, in code that is tested, before anything is drawn.

/** A line of a printed card. */
sealed class DeckBlock {
    data class Text(val text: String) : DeckBlock()
    /** [lead] is set in the mode's colour before the rest: the highest-yield part of the line. */
    data class Bullet(val lead: String?, val text: String) : DeckBlock()
    /** An MCQ option; [correct] is only ever true on an answer page. */
    data class Option(val letter: String, val text: String, val correct: Boolean) : DeckBlock()
    /** A quieter note: an explanation, a "why", a citation. */
    data class Note(val label: String, val text: String) : DeckBlock()
}

/** One printed card: a question on one page, its answer on the next. */
data class DeckCard(
    val number: Int = 0,
    val topic: String,
    val kindLabel: String,
    val question: List<DeckBlock>,
    val answer: List<DeckBlock>,
    val imageIndex: Int? = null,
    val source: String? = null,
)

object DeckBuilder {
    /** Anki sets do not print: their scheduling and occlusion masks survive only in a deck file. */
    fun printsAsPdf(kind: StudySetKind) = kind != StudySetKind.ANKI

    fun cards(set: StudySet): List<DeckCard> {
        val built = when (set.kind) {
            StudySetKind.MCQ -> mcq(set.questions)
            StudySetKind.OSCE -> osce(set.osceChecklists)
            StudySetKind.BOOK -> book(set.bookMarkdown)
            StudySetKind.NARRATE -> narrate(set.narrateSegments)
            StudySetKind.ANKI -> anki(set.cards)
            StudySetKind.CASES -> cases(set.caseFiles)
        }
        return built.mapIndexed { i, card -> card.copy(number = i + 1) }
    }

    fun mcq(questions: List<MCQQuestion>): List<DeckCard> = questions.map { q ->
        val letters = q.options.indices.map(::letter)
        val answer = q.options.mapIndexed { i, o -> DeckBlock.Option(letters[i], o, i == q.correctIndex) }.toMutableList<DeckBlock>()
        if (q.explanation.isNotBlank()) answer += DeckBlock.Note("Why", q.explanation)
        DeckCard(
            topic = topic(q.stem), kindLabel = "MCQ",
            question = listOf<DeckBlock>(DeckBlock.Text(q.stem)) + q.options.mapIndexed { i, o -> DeckBlock.Option(letters[i], o, false) },
            answer = answer, imageIndex = q.imageIndex, source = q.source,
        )
    }

    /** One card per step, asking what comes next; the last three steps taken are printed as context. */
    fun osce(checklists: List<OsceChecklist>): List<DeckCard> = checklists.flatMap { checklist ->
        checklist.steps.mapIndexed { i, step ->
            val question = mutableListOf<DeckBlock>(DeckBlock.Text(if (i == 0) "You are starting this station. What is the first step?" else "What comes next?"))
            checklist.steps.take(i).takeLast(3).forEach { question += DeckBlock.Bullet(null, it) }
            DeckCard(topic = checklist.title, kindLabel = "STEP", question = question, answer = listOf(DeckBlock.Bullet("Step ${i + 1}", step)))
        }
    }

    /** A patient prints as the one question the case ends on: the diagnosis and the next step. */
    fun cases(files: List<CaseFile>): List<DeckCard> = files.map { file ->
        val who = listOf(file.patient.ageSex, file.setting.label).filter { it.isNotEmpty() }.joinToString(" · ")
        val question = listOf(DeckBlock.Text(who), DeckBlock.Text("“" + file.complaint + "”"), DeckBlock.Text("What is the diagnosis, and the next step?"))
        val answer = mutableListOf<DeckBlock>(DeckBlock.Bullet("Diagnosis", file.diagnosis.name))
        file.nextStep.options.getOrNull(file.nextStep.key)?.let { answer += DeckBlock.Bullet("Next step", it) }
        file.teaching.forEach { answer += DeckBlock.Note("Teaching", it) }
        val cited = listOf(file.source.lecture, file.source.pages.takeIf { it.isNotBlank() }?.let { "p. $it" } ?: "").filter { it.isNotBlank() }.joinToString(", ")
        DeckCard(topic = file.specialty.ifEmpty { file.title }, kindLabel = "CASE", question = question, answer = answer, source = cited.ifEmpty { null })
    }

    /** Each textbook page: its heading is the prompt, the page is the answer. */
    fun book(markdown: String): List<DeckCard> = splitReadingPages(markdown).map { page ->
        DeckCard(topic = page.title, kindLabel = "PAGE", question = listOf(DeckBlock.Text("What do you remember about “${page.title}”?")), answer = blocks(page.markdown))
    }

    fun narrate(segments: List<NarrateSegment>): List<DeckCard> = segments.mapIndexed { i, s ->
        DeckCard(topic = "Line ${i + 1}", kindLabel = "LINE", question = listOf(DeckBlock.Text("Read this aloud, then check yourself.")), answer = listOf(DeckBlock.Text(s.text)))
    }

    fun anki(cards: List<AnkiCard>): List<DeckCard> = cards.map { card ->
        DeckCard(
            topic = topic(card.front), kindLabel = if (card.type == AnkiCardType.OCCLUSION) "IMAGE" else "RECALL",
            question = listOf(DeckBlock.Text(card.front)),
            answer = card.bullets.map { DeckBlock.Bullet(null, it) } + (if (card.why.isBlank()) emptyList() else listOf(DeckBlock.Note("Why", card.why))),
            imageIndex = card.imageIndex, source = card.source,
        )
    }

    /**
     * A short label for the contents index, taken from the ask (the last question in the
     * stem), not the opening words: clinical vignettes all open the same way.
     */
    fun topic(text: String): String {
        val cleaned = plain(text).replace("\n", " ").trim()
        if (cleaned.isEmpty()) return "Untitled"
        var candidate = cleaned
        val questions = cleaned.split("?").filter { it.isNotEmpty() }.let { if (cleaned.endsWith("?")) it else it.dropLast(1) }
        val question = questions.lastOrNull()
        if (question != null && question.split(" ").filter { it.isNotEmpty() }.size >= 3) {
            candidate = question.split(".").filter { it.isNotEmpty() }.lastOrNull() ?: question
        }
        candidate = candidate.trim(' ', ',', '.', ';', ':', '?', '“', '’', '\'', '"')
        for (opener in listOf("which of the following", "which", "what", "who", "how", "why", "when", "where")) {
            if (candidate.lowercase().startsWith("$opener ")) { candidate = candidate.drop(opener.length + 1); break }
        }
        var label = candidate.split(" ").filter { it.isNotEmpty() }.take(8).joinToString(" ")
        if (label.isEmpty()) return "Untitled"
        label = label.take(1).uppercase() + label.drop(1)
        if (label.length > 64) label = label.take(62) + "…"
        return label
    }

    fun letter(index: Int): String = if (index in 0 until 26) ('A' + index).toString() else "${index + 1}"

    /** Markdown as printable blocks, through the textbook's own reader. */
    fun blocks(markdown: String): List<DeckBlock> = readingBlocks(markdown).mapNotNull { b ->
        when (b.kind) {
            ReadingBlockKind.HEADING -> DeckBlock.Bullet(plain(b.text), "")
            ReadingBlockKind.BULLET -> {
                val marker = b.text.substringBefore("  ")
                DeckBlock.Bullet(marker.takeIf { it.firstOrNull()?.isDigit() == true }, plain(b.text.substringAfter("  ")))
            }
            ReadingBlockKind.PARAGRAPH, ReadingBlockKind.CODE -> DeckBlock.Text(plain(b.text))
            ReadingBlockKind.CALLOUT -> DeckBlock.Bullet(null, plain(b.text))
            ReadingBlockKind.TABLE_ROW -> {
                val cells = b.text.split("  \u00B7  ").map { plain(it).trim() }.filter { it.isNotEmpty() }
                if (cells.isEmpty()) null else DeckBlock.Bullet(cells.first(), cells.drop(1).joinToString(" \u2014 "))
            }
        }
    }

    /** Text without the study markup (bold, highlight, cloze braces). */
    fun plain(text: String): String = text
        .replace(Regex("\\{\\{c\\d+::(.*?)(::.*?)?\\}\\}"), "$1")
        .replace("**", "").replace("==", "").replace("__", "")
}

/** The contents index: one row per run of cards on the same topic. */
data class DeckIndexRow(val topic: String, val first: Int, val last: Int) {
    val range: String get() = if (first == last) "$first" else "$first–$last"
}

object DeckIndex {
    fun rows(cards: List<DeckCard>): List<DeckIndexRow> {
        val out = mutableListOf<DeckIndexRow>()
        for (card in cards) {
            val last = out.lastOrNull()
            if (last != null && last.topic == card.topic && last.last == card.number - 1) out[out.size - 1] = last.copy(last = card.number)
            else out += DeckIndexRow(card.topic, card.number, card.number)
        }
        return out
    }
}

/** The mode tints (iOS DeckPalette), as 0..1 RGB. */
data class DeckPalette(val red: Double, val green: Double, val blue: Double) {
    fun shade(amount: Double = 0.22) = (1 - amount).coerceIn(0.0, 1.0).let { DeckPalette(red * it, green * it, blue * it) }
    fun tint(amount: Double = 0.86) = amount.coerceIn(0.0, 1.0).let { a -> DeckPalette(red + (1 - red) * a, green + (1 - green) * a, blue + (1 - blue) * a) }
    fun argb(): Int = (0xFF shl 24) or (channel(red) shl 16) or (channel(green) shl 8) or channel(blue)
    private fun channel(v: Double) = Math.round(v.coerceIn(0.0, 1.0) * 255).toInt()

    companion object {
        fun of(kind: StudySetKind) = when (kind) {
            StudySetKind.MCQ -> DeckPalette(0.78, 0.16, 0.16)
            StudySetKind.ANKI -> DeckPalette(0.31, 0.36, 0.86)
            StudySetKind.BOOK -> DeckPalette(0.10, 0.55, 0.50)
            StudySetKind.OSCE -> DeckPalette(0.20, 0.62, 0.35)
            StudySetKind.NARRATE -> DeckPalette(0.55, 0.32, 0.80)
            StudySetKind.CASES -> DeckPalette(0.11, 0.37, 0.69)
        }
    }
}

/** One text size for every page of a side: the largest ladder step at which all of them fit. */
object DeckFit {
    val ladder = listOf(1.0f, 0.94f, 0.88f, 0.82f, 0.76f, 0.7f, 0.64f)

    fun scale(available: List<Float>, heightAt: (cardIndex: Int, scale: Float) -> Float): Float =
        ladder.firstOrNull { s -> available.indices.all { heightAt(it, s) <= available[it] } } ?: ladder.last()
}
