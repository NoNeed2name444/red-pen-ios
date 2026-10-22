package com.stethoscore.app.ui.cases

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// The owner, 15 Oct: "the wrong should be faded and what is right gets the
// color of the mode used". iOS draws the Cases answers with WardOptionRow
// (Features/Cases/CaseDecisionView.swift, CaseDebriefView.swift); so does
// Android, and the row colours right in the section's ink and wrong in the
// faded ink, never in green or red.
class CaseAnswerRowsTest {
    private val ui = File("src/main/java/com/stethoscore/app/ui")

    @Test fun casesAnswersAreWardOptionRows() {
        for (name in listOf("CaseDecisionScreen.kt", "CaseDebriefScreen.kt")) {
            val text = File(ui, "cases/$name").readText()
            assertTrue("$name draws WardOptionRow", text.contains("WardOptionRow("))
            assertTrue("$name still draws CaseOptionRow", !text.contains("CaseOptionRow("))
        }
        assertTrue("CaseOptionRow is gone from the kit", !File(ui, "cases/CaseKit.kt").readText().contains("fun CaseOptionRow"))
    }

    @Test fun rightTakesTheSectionInkAndWrongFades() {
        val text = File(ui, "ChartQuizViews.kt").readText()
        val start = text.indexOf("@Composable fun WardOptionRow(")
        assertTrue("found WardOptionRow", start >= 0)
        val row = text.substring(start, text.indexOf("\n/**", start))
        assertTrue("right and chosen take the section's ink",
            row.contains("ChartQuiz.Mark.chosen, ChartQuiz.Mark.right -> accent") && row.contains("val accent = wardColor(WardToken.primaryInk)"))
        assertTrue("wrong takes the faded ink", row.contains("ChartQuiz.Mark.wrong -> faded") && row.contains("val faded = wardColor(WardToken.fadedInk)"))
        for (colour in listOf("WardToken.success", "WardToken.danger", "CaseInk.discharge", "CaseInk.resus", "alpha ="))
            assertTrue("WardOptionRow uses $colour", !row.contains(colour))
    }
}
