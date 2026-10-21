package com.stethoscore.app.quiz

import com.stethoscore.app.data.MCQAnswer
import com.stethoscore.app.data.MCQQuestion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The question screen's parts of upstream/ios/RedPen/Tests/AnswerCheckingTests.swift
// ("shuffled options: slot on screen vs index in the question") and of
// AccessibilityTextTests.swift (what is said about an option and an answer),
// case for case. The rest of those files - decks turned into quizzes, duels,
// spoken answers, markers' numbers, audio events - test other modes and are
// ported with them.
//
// The one failure that matters here is a right answer marked wrong, or a
// wrong one marked right. So each check picks an answer by what it SAYS - the
// text on the button - and asserts the verdict, rather than trusting an index.
class AnswerCheckingTest {
    /** Every ordering of 0 until n. */
    private fun permutations(n: Int): List<List<Int>> {
        if (n == 0) return listOf(emptyList())
        val out = mutableListOf<List<Int>>()
        for (smaller in permutations(n - 1)) {
            for (i in 0..smaller.size) out += smaller.toMutableList().also { it.add(i, n - 1) }
        }
        return out
    }

    private val question = MCQQuestion(stem = "Which drug is first line for trigeminal neuralgia?",
        options = listOf("Amitriptyline", "Carbamazepine", "Gabapentin", "Sumatriptan", "Pregabalin"),
        correctIndex = 1, explanation = "Carbamazepine.")

    @Test fun shuffledOptions() {
        var everyOrderRight = true
        var everyWrongWrong = true
        var summaryAgrees = true
        var pickedIsOriginal = true
        val all = permutations(5)
        assertEquals(120, all.size)
        for (order in all) {
            // what the student sees in each slot, and taps by its text
            val shown = order.map { question.options[it] }
            val rightSlot = shown.indexOf("Carbamazepine")
            if (rightSlot < 0) { everyOrderRight = false; continue }
            if (!OptionOrder.isCorrect(rightSlot, question.correctIndex, order)) everyOrderRight = false
            if (OptionOrder.slot(question.correctIndex, order) != rightSlot) everyOrderRight = false
            for (slot in shown.indices) {
                if (slot != rightSlot && OptionOrder.isCorrect(slot, question.correctIndex, order)) everyWrongWrong = false
            }
            // the answer handed to the summary and the store is in the question's own numbering, and marks the same way
            for (slot in shown.indices) {
                val original = OptionOrder.original(slot, order)
                if (original?.let { question.options[it] } != shown[slot]) pickedIsOriginal = false
                val handedOver = MCQAnswer(selected = original, checked = true)
                val quizSaid = OptionOrder.isCorrect(slot, question.correctIndex, order)
                if (handedOver.isCorrect(question) != quizSaid) summaryAgrees = false
            }
        }
        assertTrue("the right option is marked right in all 120 orders", everyOrderRight)
        assertTrue("every other option is marked wrong in all 120 orders", everyWrongWrong)
        assertTrue("the summary marks exactly as the quiz did", summaryAgrees)
        assertTrue("the option recorded as picked is the one tapped, in the question's own numbering", pickedIsOriginal)

        assertTrue("no answer is not right", !OptionOrder.isCorrect(null, 1, listOf(0, 1, 2)))
        assertTrue("a slot past the end is not right", !OptionOrder.isCorrect(7, 1, listOf(0, 1, 2)))
        assertTrue("a checked but unanswered question is wrong in the summary", !MCQAnswer(selected = null, checked = true).isCorrect(question))
        assertTrue("a right answer that was never checked does not score", !MCQAnswer(selected = 1, checked = false).isCorrect(question))
    }

    @Test fun savedOrders() {
        // a saved order that no longer fits the question (it was edited) is not used
        assertEquals("a valid saved order is kept", listOf(2, 0, 1), OptionOrder.valid(listOf(2, 0, 1), 3))
        assertEquals("an order for fewer options falls back to the written order", listOf(0, 1, 2), OptionOrder.valid(listOf(1, 0), 3))
        assertEquals("an order for more options falls back", listOf(0, 1, 2), OptionOrder.valid(listOf(3, 1, 0, 2), 3))
        assertEquals("an order with a repeat falls back", listOf(0, 1, 2), OptionOrder.valid(listOf(0, 0, 1), 3))
        assertEquals("no saved order is the written order", listOf(0, 1, 2, 3), OptionOrder.valid(null, 4))
        val fresh = OptionOrder.make(5, shuffle = true)
        assertEquals("a fresh shuffle is an ordering of every option: $fresh", listOf(0, 1, 2, 3, 4), fresh.sorted())
        assertEquals("unshuffled is as written", listOf(0, 1, 2, 3), OptionOrder.make(4, shuffle = false))
        assertNull("a key missing from the options is in no slot", OptionOrder.slot(5, listOf(0, 1, 2)))
    }

    @Test fun spokenOptionsAndResults() {
        assertEquals("before checking, chosen", "Chosen", SpokenText.optionState(checked = false, isCorrect = true, isChosen = true))
        assertEquals("before checking, nothing gives the answer away", "", SpokenText.optionState(checked = false, isCorrect = true, isChosen = false))
        assertEquals("right and picked", "Correct, your answer", SpokenText.optionState(checked = true, isCorrect = true, isChosen = true))
        assertEquals("right, not picked", "Correct answer", SpokenText.optionState(checked = true, isCorrect = true, isChosen = false))
        assertEquals("picked, wrong", "Your answer, incorrect", SpokenText.optionState(checked = true, isCorrect = false, isChosen = true))
        assertEquals("neither", "", SpokenText.optionState(checked = true, isCorrect = false, isChosen = false))
        assertEquals("announce right", "Correct.", SpokenText.answerResult(true, "B", "x"))
        assertEquals("announce wrong with the answer", "Incorrect. The answer is C: Aortic stenosis.", SpokenText.answerResult(false, "C", " Aortic stenosis \n"))
        assertEquals("announce wrong, empty option", "Incorrect. The answer is A.", SpokenText.answerResult(false, "A", ""))
        assertEquals("announce wrong, no key", "Incorrect.", SpokenText.answerResult(false, "", "x"))
    }
}
