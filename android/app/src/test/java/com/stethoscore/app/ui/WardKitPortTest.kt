package com.stethoscore.app.ui

import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.wardScoreTone
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

    @Test fun whatFloatsOverAPageIsUnlit() {
        // iOS WardSurfaces.swift WardUnlitKey, read by the faces: no lights round
        // a face, but a control keeps its rim and a well its hollow
        val faces = File(ui, "ward/WardFaces.kt").readText()
        assertTrue("an unlit local, off by default", faces.contains("val LocalWardUnlit = staticCompositionLocalOf { false }"))
        assertTrue("a press face keeps a control's rim", faces.contains("if ((control || !unlit) && !flat)"))
        assertTrue("a still face drops lights off its rim only", faces.contains("if (!spec.inner && !(unlit && !rim))"))
        assertTrue("the composable forms read it", faces.split("LocalWardUnlit.current").size - 1 == 2)
        val surfaces = File(ui, "ward/WardSurfaces.kt").readText()
        assertTrue("a raised card or slab drops its lights", surfaces.contains("LocalWardUnlit.current && !control"))
        assertTrue("a pressable tile drops its lights unless a control", surfaces.contains("val lit = control || !LocalWardUnlit.current"))
        // the owner, 9 Oct: "remove the glow around the deck and floating buttons"
        assertTrue("home's New set and dock", File(ui, "StethoscoreApp.kt").readText().contains("ward.WardUnlit {"))
        assertTrue("the Ideas bar", File(ui, "ideas/IdeasView.kt").readText().contains("WardUnlit { Box("))
        val decks = sources().map { it.readText() }.filter { it.contains("fun StudyActionBar(folds") }
        assertTrue("the folded study deck", decks.isNotEmpty() && decks.all { it.contains("WardUnlit {") })
    }

    @Test fun theStatesAreTheWardKitsAlone() {
        // iOS Shared/Ward/WardStates.swift: one empty state, banner, groove,
        // score bar and filter chip for every screen
        for (piece in listOf("fun WardEmptyState(", "fun WardBanner(", "fun WardGroove(", "fun WardProgressBar(", "fun WardFilterChip(")) {
            val homes = sources().filter { it.readText().contains(piece) }.map { "${it.parentFile.name}/${it.name}" }
            assertTrue("$piece is defined once, in ward/WardStates.kt: $homes", homes == listOf("ward/WardStates.kt"))
        }
        val copies = Regex("fun (LibraryEmptyState|LibraryBanner|LibraryGroove|EditorBanner|ReaderEmptyState)\\(|private fun EmptyState\\(")
        for (file in sources()) assertTrue("${file.name} keeps its own empty state or banner", !copies.containsMatchIn(file.readText()))
        // a groove and a banner are wells: their fill is the shared well token,
        // so the owner's 22 Oct page-coloured wells reach them too
        val states = File(ui, "ward/WardStates.kt").readText()
        assertTrue("the groove and the banner fill with the well token", states.split("fill = WardToken.well").size - 1 == 2)
    }

    @Test fun aScoreBarTakesTheScoresTone() {
        // WardProgressBar.tone: Resus Red under half, Caution Amber under three quarters, Discharge Green above
        assertTrue(wardScoreTone(0.0) == WardTone.Danger && wardScoreTone(0.49) == WardTone.Danger)
        assertTrue(wardScoreTone(0.5) == WardTone.Warning && wardScoreTone(0.74) == WardTone.Warning)
        assertTrue(wardScoreTone(0.75) == WardTone.Green && wardScoreTone(1.0) == WardTone.Green)
    }
}
