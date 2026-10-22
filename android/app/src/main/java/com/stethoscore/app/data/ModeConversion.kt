package com.stethoscore.app.data

import com.stethoscore.app.exam.NewSetPreset
import com.stethoscore.app.reading.isBlank

// iOS Shared/ModeConversion.swift: turning a set of one mode into a set of
// another - an MCQ quiz into cards, a deck into a quiz, an OSCE station into
// cards that drill its order.
//
// Two kinds of turning. Instant: the content already says everything the
// other mode needs, so it is only rearranged (a question's stem is a card's
// front, its right answer the back); nothing is written by a model and nothing
// leaves the phone. Written: it does not, so the set goes back to New set with
// the target mode chosen and the material filled in (sourceText, lecture).
// Either way the original is left as it was; the new set sits beside it, in
// the same folder, with the same subject, pictures and lectures. Plain Kotlin,
// so ModeConversionTest runs every conversion.

object ModeConversion {
    /** The modes a set can be turned into. Narrate is a recording read along with, and there is nothing to turn into one. */
    val targets: List<StudySetKind> = listOf(StudySetKind.MCQ, StudySetKind.ANKI, StudySetKind.OSCE, StudySetKind.BOOK)

    /** Whether [set] can be turned into [kind] at all - instantly or written. */
    fun canTurn(set: StudySet, kind: StudySetKind): Boolean = kind != set.kind && kind in targets

    /** What the new set is called: "Lupus – Cards". */
    fun name(set: StudySet, kind: StudySetKind): String = "${set.name} – ${kind.label}"

    /**
     * The set rearranged into [kind], or null when that needs writing. Null
     * also when the rearranging leaves nothing worth having - a deck of three
     * cards makes no quiz, because each question needs the other cards'
     * answers as its wrong options.
     */
    fun convert(set: StudySet, kind: StudySetKind): StudySet? {
        if (!canTurn(set, kind)) return null
        val base = StudySet(name = name(set, kind), subject = set.subject, kind = kind, folderId = set.folderId,
            images = set.images, sources = set.sources)
        val out = when {
            set.kind == StudySetKind.MCQ && kind == StudySetKind.ANKI -> base.copy(cards = set.questions.mapNotNull(::card))
            set.kind == StudySetKind.ANKI && kind == StudySetKind.MCQ -> {
                // the deck's own answers are the wrong options: nothing invented.
                // Three is where the card review's own "Quiz me" draws the line.
                val built = QuizFromCards.build(set.cards)
                if (built.questions.size < 3) return null
                base.copy(questions = built.questions)
            }
            set.kind == StudySetKind.OSCE && kind == StudySetKind.ANKI -> base.copy(cards = set.osceChecklists.flatMap(::cards))
            else -> return null
        }
        return if (out.itemCount > 0) out else null
    }

    // instant, one item at a time

    /** A question as a card: the stem on the front, the right answer on the back, the explanation as the card's "why". */
    fun card(question: MCQQuestion): AnkiCard? {
        val answer = rightAnswer(question) ?: return null
        return AnkiCard(type = AnkiCardType.QA, front = question.stem.trim(), bullets = listOf(answer),
            why = question.explanation.trim(), source = question.source)
    }

    /**
     * A station as cards that drill its order: one card per step, asking what
     * comes after the one before it. The order is what an examiner marks, and
     * it is the part that slips.
     */
    fun cards(station: OsceChecklist): List<AnkiCard> {
        val steps = station.steps.map { it.trim() }.filter { it.isNotEmpty() }
        val title = station.title.trim { it == ' ' || it == '\t' }
        return steps.indices.map { i ->
            val front = if (i == 0) "$title: what is the first step?" else "$title: what comes after “${steps[i - 1]}”?"
            AnkiCard(type = AnkiCardType.QA, front = front, bullets = listOf(steps[i]), why = "Step ${i + 1} of ${steps.size}.")
        }
    }

    private fun rightAnswer(question: MCQQuestion): String? {
        val answer = question.options.getOrNull(question.correctIndex)?.trim() ?: return null
        return answer.ifEmpty { null }
    }

    // material for the writer

    /**
     * The lecture the set was made from, if it kept one with any words in it.
     * Writing from the lecture beats writing from the set: the set is already
     * a selection of it.
     */
    fun lecture(set: StudySet): SourceDoc? = set.sources.firstOrNull { doc -> doc.pages.any { !it.isBlank } }

    /**
     * The set's own content as plain text, for the writer to work from when
     * there is no lecture - every stem with its answer and explanation, every
     * card, every page.
     */
    fun sourceText(set: StudySet): String {
        val parts: List<String> = when (set.kind) {
            StudySetKind.MCQ -> set.questions.map { q ->
                val lines = mutableListOf(q.stem)
                rightAnswer(q)?.let { lines += "Answer: $it" }
                if (q.explanation.isNotEmpty()) lines += q.explanation
                lines.joinToString("\n")
            }
            StudySetKind.ANKI -> set.cards.mapNotNull { c ->
                when (c.type) {
                    AnkiCardType.QA -> (listOf(c.front) + c.bullets.map { "- $it" } + listOf(c.why)).filter { it.isNotEmpty() }.joinToString("\n")
                    AnkiCardType.CLOZE -> listOf(CardQuality.clozeBare(c.clozeText), c.why).filter { it.isNotEmpty() }.joinToString("\n")
                    AnkiCardType.OCCLUSION -> null
                }
            }
            StudySetKind.BOOK -> listOf(set.bookMarkdown)
            StudySetKind.OSCE -> set.osceChecklists.map { station -> (listOf("## " + station.title) + station.steps.map { "- $it" }).joinToString("\n") }
            StudySetKind.NARRATE -> listOf(set.narrateSegments.joinToString(" ") { it.text })
            StudySetKind.CASES -> set.caseFiles.map { it.assertedText }
        }
        return parts.map { it.trim() }.filter { it.isNotEmpty() }.joinToString("\n\n")
    }

    /**
     * What New set opens with when a set is turned into another mode by the
     * writer (iOS NewSetPreset(turning:into:)): the mode, "Name – Mode", the
     * subject, and the kept lecture when there is one, else the set as text.
     */
    fun preset(set: StudySet, kind: StudySetKind): NewSetPreset {
        val lecture = lecture(set)?.let { ReadSource(name = it.name, pages = it.pages, kind = it.kind, fileBlob = it.fileBlob) }
        return NewSetPreset(kind, name(set, kind), set.subject, if (lecture == null) sourceText(set) else "", lecture = lecture)
    }
}
