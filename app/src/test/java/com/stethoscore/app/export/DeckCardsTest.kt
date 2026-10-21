package com.stethoscore.app.export

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.DemoData
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.OsceChecklist
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The printed deck's content rules, as on iOS (DeckCard.swift). */
class DeckCardsTest {
    @Test fun mcqHidesTheAnswerOnTheQuestionPage() {
        val q = MCQQuestion(stem = "A 24-year-old man presents with chest pain. Which drug is first line?", options = listOf("Aspirin", "Morphine"), correctIndex = 0, explanation = "Antiplatelet.")
        val card = DeckBuilder.cards(StudySet(name = "MCQ", kind = StudySetKind.MCQ, questions = listOf(q))).single()
        assertEquals(1, card.number)
        assertTrue(card.question.filterIsInstance<DeckBlock.Option>().none { it.correct })
        assertEquals(listOf(true, false), card.answer.filterIsInstance<DeckBlock.Option>().map { it.correct })
        assertEquals(DeckBlock.Note("Why", "Antiplatelet."), card.answer.last())
        assertEquals("Drug is first line", card.topic) // the ask, not the opening words
    }

    @Test fun osceAsksForEachNextStepWithTheLastThreeAsContext() {
        val station = OsceChecklist(title = "Cannula", steps = (1..6).map { "Step $it" })
        val cards = DeckBuilder.osce(station.let(::listOf))
        assertEquals(6, cards.size)
        assertEquals(DeckBlock.Text("You are starting this station. What is the first step?"), cards[0].question.first())
        assertEquals(listOf("Step 3", "Step 4", "Step 5"), cards[5].question.filterIsInstance<DeckBlock.Bullet>().map { it.text })
        assertEquals(DeckBlock.Bullet("Step 6", "Step 6"), cards[5].answer.single())
    }

    @Test fun ankiSetsDoNotPrint() {
        assertFalse(DeckBuilder.printsAsPdf(StudySetKind.ANKI))
        assertTrue(StudySetKind.entries.filter { it != StudySetKind.ANKI }.all(DeckBuilder::printsAsPdf))
        val c = DeckBuilder.anki(listOf(AnkiCard(type = AnkiCardType.OCCLUSION, front = "Label the valve", bullets = listOf("Mitral"))))
        assertEquals("IMAGE", c.single().kindLabel)
    }

    @Test fun everyExampleSetBuildsNumberedCards() {
        for (set in DemoData.sets) {
            val cards = DeckBuilder.cards(set)
            assertTrue(set.name, cards.isNotEmpty())
            assertEquals((1..cards.size).toList(), cards.map { it.number })
            assertTrue(cards.all { it.topic.isNotBlank() && it.topic.length <= 64 })
        }
        val book = DemoData.sets.first { it.kind == StudySetKind.BOOK }
        assertTrue(DeckBuilder.cards(book).all { it.kindLabel == "PAGE" && it.answer.isNotEmpty() })
        val cases = DemoData.sets.first { it.kind == StudySetKind.CASES }
        assertTrue(DeckBuilder.cards(cases).all { c -> c.answer.first() is DeckBlock.Bullet && (c.answer.first() as DeckBlock.Bullet).lead == "Diagnosis" })
    }

    @Test fun topicsAndLetters() {
        assertEquals("Untitled", DeckBuilder.topic("  "))
        assertEquals("Heart failure drugs", DeckBuilder.topic("**Heart failure drugs**"))
        assertEquals("Heart failure drugs.pdf", DeckPdf.fileName(StudySet(name = "Heart failure: drugs?", kind = StudySetKind.MCQ)))
        assertEquals("A", DeckBuilder.letter(0)); assertEquals("Z", DeckBuilder.letter(25)); assertEquals("27", DeckBuilder.letter(26))
        assertEquals("answer here", DeckBuilder.plain("{{c1::answer}} here"))
    }

    @Test fun theIndexCollapsesRunsOnOneTopic() {
        val cards = listOf("A", "A", "B", "A").mapIndexed { i, t -> DeckCard(number = i + 1, topic = t, kindLabel = "MCQ", question = emptyList(), answer = emptyList()) }
        val rows = DeckIndex.rows(cards)
        assertEquals(listOf("1–2", "3", "4"), rows.map { it.range })
    }

    @Test fun oneSizeFitsEveryPageOfASide() {
        // card 1 fits at full size, card 2 only from 0.82 down: both print at 0.82
        val scale = DeckFit.scale(listOf(100f, 100f)) { i, s -> if (i == 0) 50f * s else 121f * s }
        assertEquals(0.82f, scale, 1e-6f)
        assertEquals(DeckFit.ladder.last(), DeckFit.scale(listOf(1f)) { _, _ -> 1000f })
    }

    @Test fun paletteTintsTowardWhiteAndShadesTowardBlack() {
        val p = DeckPalette.of(StudySetKind.MCQ)
        assertTrue(p.tint().green > p.green && p.shade().red < p.red)
        assertEquals(0xFFFF6B6B.toInt(), p.argb())
    }

    @Test fun everyModeBarCarriesWhiteAndItsWordsReadOnPaper() {
        for (kind in StudySetKind.values()) {
            val p = DeckPalette.of(kind)
            assertTrue("$kind: white is under 4.5:1 on the bright tint as drawn", !p.carriesWhiteText)
            assertTrue("$kind: its bar carries white", p.barFill().carriesWhiteText)
            assertTrue("$kind: its words read 5:1 on white", 1.05 / (p.ink().wcagLuminance + 0.05) >= 5)
        }
    }
}
