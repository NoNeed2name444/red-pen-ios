package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.saveable.SaverScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelected
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import com.stethoscore.app.data.MCQAnswer
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.ui.library.LibraryState
import com.stethoscore.app.ui.library.Naming
import com.stethoscore.app.ui.mock.MockPaperScreen
import com.stethoscore.app.ui.ward.WardSection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// What a rotation, a fold or a window resize must keep (T0139): each of them
// recreates the activity, and the screen comes back from its saved state.
// StateRestorationTester saves and restores as the activity does; the
// emulators' RotationStateTest turns the real device.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RotationRestoreTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private fun store() = StudyStore(folder.newFolder()).also { it.loadExamples() }

    /**
     * Tapped by its click action, brought into view first where it scrolls: Robolectric's
     * screen is short, and the study bar's buttons can lie below it, where a touch lands on nothing.
     */
    private fun tap(matcher: SemanticsMatcher) {
        val node = compose.onAllNodes(matcher).onFirst()
        try { node.performScrollTo() } catch (_: AssertionError) {}
        node.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick)
        compose.waitForIdle()
    }

    private fun page(section: WardSection, content: @androidx.compose.runtime.Composable () -> Unit): @androidx.compose.runtime.Composable () -> Unit = {
        StethoscoreTheme(false, section) {
            Box(Modifier.fillMaxSize()) { Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { content() } }
        }
    }

    private fun exists(matcher: SemanticsMatcher) = compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()

    /** MCQQuizScreen.kt's place and answers were plain remember: a rotation sent the quiz back to question 1. */
    @Test fun quizKeepsItsQuestionAndChoice() {
        val s = store()
        val set = s.library.first { it.kind == StudySetKind.MCQ }
        assertTrue("three questions to walk", set.questions.size >= 3)
        val restoration = StateRestorationTester(compose)
        restoration.setContent(page(WardSection.fromKindRaw(StudySetKind.MCQ.rawValue)) { QuizScreen(set, s, {}) })
        compose.waitForIdle()
        for (q in set.questions.take(2)) {
            tap(hasClickAction() and hasContentDescription(": " + q.options[q.correctIndex], substring = true))
            tap(hasText(ChartQuiz.primaryTitle(false, true, false, false, false)) and hasClickAction())
            tap(hasText(ChartQuiz.primaryTitle(true, true, false, false, false)) and hasClickAction())
        }
        val third = set.questions[2]
        val pick = third.options[(third.correctIndex + 1) % third.options.size]
        tap(hasClickAction() and hasContentDescription(": $pick", substring = true))
        val chosen = compose.onAllNodes(hasContentDescription(": $pick", substring = true) and isSelected()).fetchSemanticsNodes()
        assertEquals("the pick is chosen before the rotation", 1, chosen.size)
        val letter = chosen.first().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].first().substringBefore(":")

        restoration.emulateSavedInstanceStateRestore()
        compose.waitForIdle()

        assertTrue("still on question 3", exists(hasText(third.stem.take(40), substring = true)))
        assertFalse("not back on question 1", exists(hasText(set.questions[0].stem.take(40), substring = true)))
        val after = compose.onAllNodes(hasContentDescription(": $pick", substring = true) and isSelected()).fetchSemanticsNodes()
        assertEquals("its choice still chosen", 1, after.size)
        assertEquals("in the same place among the options",
            letter, after.first().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].first().substringBefore(":"))
        assertTrue("and ready to check", exists(hasText(ChartQuiz.primaryTitle(false, true, false, false, false))))
    }

    /** MockSittingScreen.kt's part and question were plain remember, and the paper's own screen dropped the sitting. */
    @Test fun mockKeepsItsSittingQuestionAndChoice() {
        val s = store()
        // a mock needs ten questions at least: the examples' and twelve more
        s.addSet(com.stethoscore.app.data.StudySet(name = "Renal drill", subject = "Nephrology", kind = StudySetKind.MCQ,
            questions = List(12) { i -> com.stethoscore.app.data.MCQQuestion(stem = "Drill question ${i + 1}?", options = listOf("One", "Two", "Three", "Four"), correctIndex = i % 4) }))
        val restoration = StateRestorationTester(compose)
        restoration.setContent(page(WardSection.fromKindRaw(StudySetKind.MCQ.rawValue)) { MockPaperScreen(s) {} })
        compose.waitForIdle()
        tap(hasText("Start mock") and hasClickAction())
        assertTrue("the sitting is open", exists(hasText("Question 1 of", substring = true)))
        tap(hasClickAction() and hasContentDescription("Answer A:", substring = true))
        tap(hasText("Next") and hasClickAction())
        tap(hasClickAction() and hasContentDescription("Answer B:", substring = true))
        assertTrue(exists(hasContentDescription("Answer B:", substring = true) and isSelected()))

        restoration.emulateSavedInstanceStateRestore()
        compose.waitForIdle()

        assertTrue("still in the sitting, on question 2", exists(hasText("Question 2 of", substring = true)))
        assertTrue("its choice still chosen", exists(hasContentDescription("Answer B:", substring = true) and isSelected()))
        assertFalse("not back at the paper's start", exists(hasText("Start mock")))
        // the first question's answer is kept too
        tap(hasText("Back") and hasClickAction())
        assertTrue("question 1's choice kept", exists(hasContentDescription("Answer A:", substring = true) and isSelected()))
    }

    /** MockSittingScreen.kt: the results were plain remember, and the sitting's save was gone once marked. */
    @Test fun mockResultsSurviveATurn() {
        val s = store()
        s.addSet(com.stethoscore.app.data.StudySet(name = "Renal drill", subject = "Nephrology", kind = StudySetKind.MCQ,
            questions = List(12) { i -> com.stethoscore.app.data.MCQQuestion(stem = "Drill question ${i + 1}?", options = listOf("One", "Two", "Three", "Four"), correctIndex = i % 4) }))
        val dir = compose.activity.filesDir
        val restoration = StateRestorationTester(compose)
        restoration.setContent(page(WardSection.fromKindRaw(StudySetKind.MCQ.rawValue)) { MockPaperScreen(s) {} })
        compose.waitForIdle()
        tap(hasText("Start mock") and hasClickAction())
        tap(hasClickAction() and hasContentDescription("Answer A:", substring = true))
        tap(hasText("End") and hasClickAction())
        tap(hasText("End and see results") and hasClickAction())
        val score = hasText(" right", substring = true)
        assertTrue("the results are up", exists(score))
        val shown = compose.onAllNodes(score).fetchSemanticsNodes().first().config[androidx.compose.ui.semantics.SemanticsProperties.Text].joinToString()
        assertEquals("one record kept", 1, com.stethoscore.app.quiz.MockRecords.load(com.stethoscore.app.ui.mock.MockLibrary.recordsFile(dir)).size)

        restoration.emulateSavedInstanceStateRestore()
        compose.waitForIdle()

        assertTrue("the results still up after the turn", exists(hasText(shown)))
        assertFalse("not back at the paper's start", exists(hasText("Start mock")))
        assertFalse("not back in the sitting", exists(hasText("Question 1 of", substring = true)))
        assertEquals("marked and recorded once, not again", 1, com.stethoscore.app.quiz.MockRecords.load(com.stethoscore.app.ui.mock.MockLibrary.recordsFile(dir)).size)
    }

    /** AnkiReviewScreen.kt: after a turn, a revealed answer stays only over the card it was revealed on. */
    @Test fun revealedAnswerIsDroppedWhenTheFirstCardChanged() {
        val s = store()
        val set = s.library.first { it.kind == StudySetKind.ANKI }
        val due = s.queue(set)
        assertTrue("two cards due", due.size >= 2)
        val restoration = StateRestorationTester(compose)
        restoration.setContent(page(WardSection.cards) { AnkiReviewScreen(set, s, {}) })
        compose.waitForIdle()
        tap(hasText("Reveal") and hasClickAction())
        assertTrue(exists(hasContentDescription("Good")))
        // the card on screen is rated elsewhere while the app is away: the queue made again starts on another
        s.rateCard(due.first().card, com.stethoscore.app.data.AnkiRating.EASY)
        assertTrue("another card leads the queue", s.queue(set).firstOrNull()?.id != due.first().id)

        restoration.emulateSavedInstanceStateRestore()
        compose.waitForIdle()

        assertTrue("the new card's answer is hidden: Reveal is back", exists(hasText("Reveal") and hasClickAction()))
        assertFalse("no ratings over a card not revealed", exists(hasContentDescription("Good")))
    }

    /** AnkiReviewScreen.kt: studying ahead was plain remember, so a turn put the deck back on "Nothing to review". */
    @Test fun studyingAheadSurvivesATurnWithItsRevealedCard() {
        val s = store()
        val set = s.library.first { it.kind == StudySetKind.ANKI }
        // nothing left due: every card rated well ahead
        for (item in s.everything(set)) s.rateCard(item.card, com.stethoscore.app.data.AnkiRating.EASY)
        assertTrue("nothing due", s.queue(set).isEmpty())
        val restoration = StateRestorationTester(compose)
        restoration.setContent(page(WardSection.cards) { AnkiReviewScreen(set, s, {}) })
        compose.waitForIdle()
        tap(hasText("Study it anyway") and hasClickAction())
        tap(hasText("Reveal") and hasClickAction())
        assertTrue(exists(hasContentDescription("Good")))

        restoration.emulateSavedInstanceStateRestore()
        compose.waitForIdle()

        assertFalse("still studying ahead", exists(hasText("Nothing to review")))
        assertTrue("the same card, still revealed", exists(hasContentDescription("Good")))
    }

    @Test fun revealedCardStaysRevealed() {
        val s = store()
        val set = s.library.first { it.kind == StudySetKind.ANKI }
        val restoration = StateRestorationTester(compose)
        restoration.setContent(page(WardSection.cards) { AnkiReviewScreen(set, s, {}) })
        compose.waitForIdle()
        tap(hasText("Reveal") and hasClickAction())
        assertTrue(exists(hasContentDescription("Good")))
        restoration.emulateSavedInstanceStateRestore()
        compose.waitForIdle()
        assertTrue("the ratings still up", exists(hasContentDescription("Good")))
        assertFalse("Reveal not back", exists(hasText("Reveal") and hasClickAction()))
    }

    @Test fun nameSheetKeepsItsDraft() {
        val restoration = StateRestorationTester(compose)
        restoration.setContent(page(WardSection.outside) { com.stethoscore.app.ui.library.NameSheet("New folder", "Folder name", "", "Create folder", {}) {} })
        compose.waitForIdle()
        compose.onAllNodes(hasSetTextAction()).onFirst().performTextReplacement("Renal week")
        compose.waitForIdle()
        restoration.emulateSavedInstanceStateRestore()
        compose.waitForIdle()
        assertTrue("the typed name kept", exists(hasText("Renal week")))
    }

    @Test fun libraryStateRoundTrips() {
        val saver = SaverScope { true }
        val before = LibraryState().apply {
            selecting = true; selected = setOf("a", "b"); naming = Naming.RenameSet("s1", "Renal, draft"); session = "acid base"
            scope = com.stethoscore.app.data.LibrarySearch.Scope.entries.last()
        }
        val saved = with(LibraryState.Saver) { saver.save(before) }!!
        val after = LibraryState.Saver.restore(saved)!!
        assertEquals(before.selecting, after.selecting)
        assertEquals(before.selected, after.selected)
        assertEquals(before.naming, after.naming)
        assertEquals(before.session, after.session)
        assertEquals(before.scope, after.scope)
        for (n in listOf(Naming.NewFolder, Naming.Combine, Naming.RenameFolder("f", "Folder"), null)) {
            val st = LibraryState().apply { naming = n }
            assertEquals(n, LibraryState.Saver.restore(with(LibraryState.Saver) { saver.save(st) }!!)!!.naming)
        }
    }

    @Test fun saversRoundTrip() {
        val saver = SaverScope { true }
        val answers = listOf(MCQAnswer(), MCQAnswer(2, false), MCQAnswer(0, true))
        assertEquals(answers, StudySavers.answers.restore(with(StudySavers.answers) { saver.save(answers) }!!))
        val orders = listOf(listOf(2, 0, 1), emptyList(), listOf(0, 1, 2, 3))
        assertEquals(orders, StudySavers.orders.restore(with(StudySavers.orders) { saver.save(orders) }!!))
        val marks = mapOf(0 to setOf(1, 3), 4 to emptySet(), 2 to setOf(0))
        assertEquals(marks, StudySavers.marks.restore(with(StudySavers.marks) { saver.save(marks) }!!))
        val idMarks = mapOf("q1" to setOf(1, 3), "q2" to emptySet())
        assertEquals(idMarks, StudySavers.idMarks.restore(with(StudySavers.idMarks) { saver.save(idMarks) }!!))
        val ints = mapOf("q1" to 2, "q9" to 0)
        assertEquals(ints, StudySavers.idInts.restore(with(StudySavers.idInts) { saver.save(ints) }!!))
    }
}
