package com.stethoscore.app.ui

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// Wave 2 of the Android consistency report: the stand-ins written while the
// Ward kit was being ported are retired for the kit itself (ui/ward), one to
// one with iOS, and the iOS pieces that were missing are ported once.
class WardKitPortTest {
    private val ui = File("src/main/java/com/stethoscore/app/ui")

    private fun sources(): List<File> = ui.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()

    @Test fun theQuizStandInsAreGone() {
        val gone = listOf("fun Modifier.quizFace(", "class QuizFace", "fun QuizTag(", "class QuizTone", "fun QuizChip(",
            "fun QuizCard(", "fun QuizSmallCaps(")
        val calls = Regex("(?<![A-Za-z])(quizFace|QuizChip|QuizTag|QuizCard|QuizSmallCaps)\\(")
        for (file in sources()) {
            val text = file.readText()
            for (piece in gone) assertTrue("${file.name} still defines $piece", !text.contains(piece))
            assertTrue("${file.name} still calls a quiz stand-in", !calls.containsMatchIn(text))
        }
    }

    @Test fun theOptionRowStandsOnTheWardPressFace() {
        val text = File(ui, "ChartQuizViews.kt").readText()
        val start = text.indexOf("@Composable fun WardOptionRow(")
        assertTrue("found WardOptionRow", start >= 0)
        val row = text.substring(start, text.indexOf("\n/**", start))
        // iOS ChartQuizViews.swift: WardPressFace, pressed when chosen or right, a wrong pick flat on the faded face
        assertTrue("the row's face is WardPressFace", row.contains("wardPressFace("))
        assertTrue("a wrong pick lies flat", row.contains("flat = wrong"))
        assertTrue("chosen and right are pressed in", row.contains("wardDepth(mark == ChartQuiz.Mark.chosen || mark == ChartQuiz.Mark.right)"))
    }

    @Test fun theCasesKitDrawsTheWardKit() {
        // iOS Features/Cases/CaseKit.swift: caseCard over wardCard, the avatar and
        // the clock pressed in, WardChip, WardSegmented and the Ward buttons
        val text = File(ui, "cases/CaseKit.kt").readText()
        for (piece in listOf("WardCardFace(", "WardChip(", "WardSegmented(", "WardButtonBox(", "wardInset(CircleShape)"))
            assertTrue("CaseKit draws $piece", text.contains(piece))
        for (piece in listOf(".border(", "OutlinedButton(", "alpha = 0.12f", ".clickable("))
            assertTrue("CaseKit no longer draws $piece", !text.contains(piece))
    }
}
