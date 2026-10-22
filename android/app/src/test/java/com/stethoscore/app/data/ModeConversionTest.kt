package com.stethoscore.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// iOS Tests/ModeConversionTests.swift, check for check: turning a set of one
// mode into another. The instant conversions promise that nothing is invented
// and nothing of the original is lost or changed, so that is what is asserted:
// every item arrives, with its own words, and the set it came from is left as
// it was.
class ModeConversionTest {
    private val folder = "folder-1"
    private val quiz = StudySet(name = "Nephrology", subject = "Renal", kind = StudySetKind.MCQ, folderId = folder,
        images = listOf("aGVsbG8="),
        sources = listOf(SourceDoc(name = "Glomerular disease", kind = "pdf", pages = listOf(SourcePage(1, "Nephrotic syndrome in adults")))),
        questions = listOf(
            MCQQuestion(stem = "A 34-year-old has frothy urine, periorbital oedema and 6 g/day of proteinuria, with an albumin of 22 g/L and normal renal function on admission to the ward. Which finding is most likely on light microscopy?",
                options = listOf("Normal glomeruli", "Segmental sclerosis", "Crescents", "IgA deposits"), correctIndex = 1,
                explanation = "FSGS is the commonest primary nephrotic syndrome in adults."),
            MCQQuestion(stem = "Anti-PLA2R antibodies are most specific for which condition?",
                options = listOf("Membranous nephropathy", "Lupus nephritis", "IgA nephropathy", "Anti-GBM disease"), correctIndex = 0,
                explanation = "Found in most primary membranous nephropathy.", source = "Glomerular disease, p.1"),
            // a broken question - its answer points past the options - is left out
            MCQQuestion(stem = "Broken?", options = listOf("A"), correctIndex = 3),
        ))

    @Test fun mcqTurnsIntoCardsInstantly() {
        val deck = ModeConversion.convert(quiz, StudySetKind.ANKI)
        assertNotNull("MCQ turns into Cards instantly", deck); deck!!
        assertEquals("the new set is a deck", StudySetKind.ANKI, deck.kind)
        assertEquals("it is named after the original", "Nephrology – Cards", deck.name)
        assertNotEquals("it is a new set, not the old one", quiz.id, deck.id)
        assertTrue("subject, folder, pictures and lectures come with it",
            deck.subject == "Renal" && deck.folderId == folder && deck.images == quiz.images && deck.sources == quiz.sources)
        assertEquals("one card per sound question", 2, deck.cards.size)
        assertEquals("the stem is the front", quiz.questions[0].stem, deck.cards.first().front)
        assertEquals("the right answer is the back", listOf("Segmental sclerosis"), deck.cards.first().bullets)
        assertEquals("the explanation is the why", quiz.questions[0].explanation, deck.cards.first().why)
        assertEquals("the citation is kept", "Glomerular disease, p.1", deck.cards.last().source)
        assertTrue("the original is untouched", quiz.questions.size == 3 && quiz.cards.isEmpty())
    }

    @Test fun anythingElseFromMcqIsWritten() {
        assertNull("MCQ into OSCE needs writing", ModeConversion.convert(quiz, StudySetKind.OSCE))
        assertNull("MCQ into Textbook needs writing", ModeConversion.convert(quiz, StudySetKind.BOOK))
        assertNull("a set is never turned into itself", ModeConversion.convert(quiz, StudySetKind.MCQ))
        assertFalse("nothing turns into Narrate", ModeConversion.canTurn(quiz, StudySetKind.NARRATE))
    }

    private fun qa(front: String, answer: String, why: String) = AnkiCard(type = AnkiCardType.QA, front = front, bullets = listOf(answer), why = why)

    private val cardsSet = StudySet(name = "Lupus", subject = "Rheumatology", kind = StudySetKind.ANKI, cards = listOf(
        qa("Which drug lowers mortality in SLE?", "Hydroxychloroquine", "It lowers flares and damage accrual."),
        qa("Which antibody is the entry criterion for SLE?", "Antinuclear antibody", "Required before points are counted."),
        qa("Which antibody is most specific for SLE?", "Anti-double-stranded DNA", "Specific, and tracks nephritis."),
        qa("Which drug is used for lupus nephritis induction?", "Mycophenolate mofetil", "As effective as cyclophosphamide."),
        qa("Which test monitors disease activity in SLE?", "Complement C3 and C4", "They fall in active disease."),
        qa("Which skin sign spares the nasolabial folds?", "The malar rash", "Sparing separates it from rosacea."),
    ))

    @Test fun aDeckTurnsIntoAQuizFromItsOwnAnswers() {
        val answers = cardsSet.cards.mapNotNull { it.bullets.firstOrNull() }
        val fromCards = ModeConversion.convert(cardsSet, StudySetKind.MCQ)
        assertEquals("a deck turns into a quiz instantly", 5, fromCards?.questions?.size)
        fromCards!!
        assertTrue("every option is one of the deck's own answers", fromCards.questions.all { q -> q.options.all { it in answers } })
        assertTrue("every key is right", fromCards.questions.all { q -> cardsSet.cards.any { it.bullets.firstOrNull() == q.options[q.correctIndex] } })
        assertNull("too thin a deck is written instead", ModeConversion.convert(cardsSet.copy(cards = cardsSet.cards.take(2)), StudySetKind.MCQ))
    }

    private val osce = StudySet(name = "Skills", kind = StudySetKind.OSCE, osceChecklists = listOf(
        OsceChecklist(title = "Venepuncture", steps = listOf("Wash hands", "Confirm identity", "Apply tourniquet"))))

    @Test fun aStationTurnsIntoCardsThatDrillItsOrder() {
        val drill = ModeConversion.convert(osce, StudySetKind.ANKI)
        assertEquals("a station turns into one card per step", 3, drill?.cards?.size)
        assertEquals("the first card asks for the first step", "Venepuncture: what is the first step?", drill!!.cards.first().front)
        assertEquals("later cards ask what comes next", "Venepuncture: what comes after “Confirm identity”?", drill.cards.last().front)
        assertEquals(listOf("Apply tourniquet"), drill.cards.last().bullets)
    }

    private val book = StudySet(name = "Thyroid", kind = StudySetKind.BOOK, bookMarkdown = "# Thyroid\nHashimoto's is the commonest cause of hypothyroidism.")

    @Test fun aTextbookIsAlwaysWritten() {
        for (kind in listOf(StudySetKind.MCQ, StudySetKind.ANKI, StudySetKind.OSCE))
            assertNull("a textbook into ${kind.label} is written", ModeConversion.convert(book, kind))
    }

    @Test fun theWritersMaterial() {
        assertEquals("the kept lecture is the material", "Glomerular disease", ModeConversion.lecture(quiz)?.name)
        assertNull("no lecture, no material from one", ModeConversion.lecture(cardsSet))
        val quizText = ModeConversion.sourceText(quiz)
        assertTrue("a quiz's text has its stems, answers and explanations",
            quizText.contains("Anti-PLA2R") && quizText.contains("Answer: Membranous nephropathy") && quizText.contains("FSGS"))
        assertEquals("a station's text keeps its steps in order",
            "## Venepuncture\n- Wash hands\n- Confirm identity\n- Apply tourniquet", ModeConversion.sourceText(osce))
        assertEquals("a textbook's text is the book", book.bookMarkdown, ModeConversion.sourceText(book))
        val cloze = StudySet(name = "HF", kind = StudySetKind.ANKI, cards = listOf(
            AnkiCard(type = AnkiCardType.CLOZE, clozeText = "An ejection fraction of {{c1::40% or less}} defines HFrEF."),
            AnkiCard(type = AnkiCardType.OCCLUSION, imageIndex = 0)))
        assertEquals("a cloze card's text has its words, not its braces",
            "An ejection fraction of 40% or less defines HFrEF.", ModeConversion.sourceText(cloze))
    }

    @Test fun aWrittenTurnOpensNewSetWithTheMaterial() {
        // iOS NewSetPreset(turning:into:): the lecture when there is one, else the set as text
        val fromLecture = ModeConversion.preset(quiz, StudySetKind.OSCE)
        assertEquals(StudySetKind.OSCE, fromLecture.kind)
        assertEquals("Nephrology – OSCE", fromLecture.name)
        assertEquals("Renal", fromLecture.subject)
        assertEquals("Glomerular disease", fromLecture.lecture?.name)
        assertEquals("", fromLecture.notes)
        assertEquals("Nephrotic syndrome in adults", fromLecture.text)
        val fromSet = ModeConversion.preset(book, StudySetKind.MCQ)
        assertNull(fromSet.lecture)
        assertEquals(book.bookMarkdown, fromSet.text)
    }
}
