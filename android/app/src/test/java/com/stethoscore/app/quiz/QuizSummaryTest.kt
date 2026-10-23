package com.stethoscore.app.quiz

import com.stethoscore.app.data.MCQAnswer
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The results screen's sums (MCQSummaryView's score, verdict and next button;
// SetPictures' Mistakes top-up). iOS keeps these in the view, untested; here
// they are plain Kotlin, so they are pinned to iOS's numbers and words.
class QuizSummaryTest {
    private fun q(id: String, stem: String, image: Int? = null) =
        MCQQuestion(id = id, stem = stem, options = listOf("A", "B", "C"), correctIndex = 1, imageIndex = image)

    @Test fun scoreAndVerdict() {
        val questions = listOf(q("1", "One"), q("2", "Two"), q("3", "Three"), q("4", "Four"))
        val answers = listOf(MCQAnswer(1, true), MCQAnswer(0, true), MCQAnswer(1, false), MCQAnswer(null, true))
        assertEquals("only a checked right pick scores", 1, QuizSummary.correctCount(questions, answers))
        assertEquals("missing answers are wrong", 1, QuizSummary.correctCount(questions + q("5", "Five"), answers))
        assertEquals(0.0, QuizSummary.fraction(0, 0), 0.0)
        assertEquals("Ready for the exam on this set.", QuizSummary.verdict(0.9))
        assertEquals("Review what you missed.", QuizSummary.verdict(0.7))
        assertEquals("Review what you missed.", QuizSummary.verdict(0.5))
        assertEquals("Review what you missed, then try again.", QuizSummary.verdict(0.49))
        assertEquals("a question re-tested is listed once", listOf("2", "3", "4"),
            QuizSummary.mistakes(questions + q("2", "Two"), answers).map { it.id })
    }

    @Test fun nextButton() {
        assertEquals(QuizSummary.Next.save, QuizSummary.next(isUnsaved = true, saved = false, hasMistakes = true, mistakesSaved = false))
        assertEquals(QuizSummary.Next.done, QuizSummary.next(isUnsaved = true, saved = true, hasMistakes = true, mistakesSaved = false))
        assertEquals(QuizSummary.Next.practise, QuizSummary.next(isUnsaved = false, saved = false, hasMistakes = true, mistakesSaved = false))
        assertEquals(QuizSummary.Next.done, QuizSummary.next(isUnsaved = false, saved = false, hasMistakes = true, mistakesSaved = true))
        assertEquals(QuizSummary.Next.done, QuizSummary.next(isUnsaved = false, saved = false, hasMistakes = false, mistakesSaved = false))
    }

    @Test fun mistakesSet() {
        assertEquals("Mistakes – Cardiology", QuizSummary.mistakesName("Cardiology"))
        assertEquals("one Mistakes set, never Mistakes of Mistakes", "Mistakes – Cardiology", QuizSummary.mistakesName("Mistakes – Cardiology"))
        val source = StudySet(name = "Cardiology", kind = StudySetKind.MCQ, images = listOf("pic0", "pic1"), questions = listOf(q("a", "A?", 1), q("b", "B?")))
        val empty = StudySet(name = "Mistakes – Cardiology", kind = StudySetKind.MCQ)
        val once = QuizSummary.addMistakes(empty, source.questions, source)
        assertEquals("each question brings its picture", listOf("pic1"), once.images)
        assertEquals(0, once.questions.first().imageIndex)
        val twice = QuizSummary.addMistakes(once, source.questions, source)
        assertTrue("topped up, not doubled", twice.questions.size == 2 && twice.images == listOf("pic1"))
    }
}
