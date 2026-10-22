package com.stethoscore.app.data

import org.junit.Assert.assertTrue
import org.junit.Test

// A port of the "editing without moving the answer" part of
// ios/RedPen/Tests/SlideTests.swift (fed0105), case for case. The rest
// of SlideTests (slide reading, Provenance) is the lecture importers' and
// comes with them.
class MCQEditTest {
    private fun check(label: String, ok: Boolean, detail: Any? = null) = assertTrue(if (detail == null) label else "$label  | $detail", ok)

    @Test fun editingWithoutMovingTheAnswer() {
        val four = MCQQuestion(stem = "Which?", options = listOf("A", "B", "C", "D"), correctIndex = 2, explanation = "")
        val shorter = MCQEdit.removing(setOf(0), four)
        // the silent one: correctIndex is a position, and deleting an earlier option moves it
        check("deleting an earlier option moves the key with it",
            shorter.options[shorter.correctIndex] == "C", "${shorter.options} key=${shorter.correctIndex}")
        val later = MCQEdit.removing(setOf(3), four)
        check("deleting a later option leaves the key alone", later.options[later.correctIndex] == "C")
        val gone = MCQEdit.removing(setOf(2), four)
        // never quietly option A
        check("deleting the key itself leaves nothing marked correct",
            !MCQEdit.hasKey(gone) && gone.options == listOf("A", "B", "D"), "${gone.options} key=${gone.correctIndex}")
        check("and a question with nothing marked cannot be saved", MCQEdit.tidied(gone) == null)
        val picked = gone.copy(correctIndex = 2)
        check("until the right answer is picked again", MCQEdit.tidied(picked)?.options?.get(2) == "D")

        val blanks = MCQQuestion(stem = "Which?", options = listOf("A", "  ", "C"), correctIndex = 2, explanation = "")
        val tidied = MCQEdit.tidied(blanks)
        check("dropping a blank option moves the key too",
            tidied?.options == listOf("A", "C") && tidied.let { it.options[it.correctIndex] } == "C",
            "${tidied?.options ?: emptyList<String>()} key=${tidied?.correctIndex ?: -1}")
        check("whitespace around an option is trimmed",
            MCQEdit.tidied(MCQQuestion(stem = "", options = listOf(" A ", "B"), correctIndex = 0, explanation = ""))?.options == listOf("A", "B"))
        check("a question with no options does not crash, and is not saved",
            MCQEdit.tidied(MCQQuestion(stem = "", options = emptyList(), correctIndex = 0, explanation = "")) == null)
        // emptying the keyed option to retype it, then saving: no silent key of A
        val emptied = MCQQuestion(stem = "Which?", options = listOf("A", "B", "   ", "D"), correctIndex = 2, explanation = "")
        check("clearing the keyed option's text does not make A the key", MCQEdit.tidied(emptied) == null && !MCQEdit.hasKey(emptied))
        val twins = MCQQuestion(stem = "Which?", options = listOf("Same", " ", "Same"), correctIndex = 2, explanation = "")
        check("the key follows its position, not the first option with the same words", MCQEdit.tidied(twins)?.correctIndex == 1)
    }
}
