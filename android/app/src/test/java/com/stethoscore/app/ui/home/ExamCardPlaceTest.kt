package com.stethoscore.app.ui.home

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.learn.LearnRoute
import com.stethoscore.app.ui.learn.LearnRouter
import com.stethoscore.app.ui.learn.LearnRouterClosed
import com.stethoscore.app.ui.ward.WardSpace
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// T0219: home holds no exam card, as iOS's home holds none. The exam is set up
// from the header's button (HomeExamSetUpTest); the card, with its blueprint,
// its predicted score and its Study next, stands only on the exam plan, which
// home's Open plan opens (iOS ExamPlanView). The window is tall so the whole
// of Questions' list is composed, down to its closing line: an absent card is
// then absent from the list, not merely below the fold.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w411dp-h4000dp")
class ExamCardPlaceTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private val mockTile = "Mock paper, Your exam’s real paper"
    private val lastRow = "Study aid. Not for clinical decisions."
    private val openPlan = SemanticsMatcher("Open plan") {
        it.config.getOrElseNullable(SemanticsActions.OnClick) { null }?.label == "Opens the exam plan and forecast"
    }

    private fun prefs() = ApplicationProvider.getApplicationContext<Context>().getSharedPreferences("appearance", Context.MODE_PRIVATE)

    @Before fun noExam() { prefs().edit().clear().commit() }

    private fun chooseExam() { prefs().edit().putString(ExamTrack.storageKey, ExamTrack.plab.rawValue).commit() }

    /** Home on Questions with the examples in the library: the state that showed the card. */
    private fun home() {
        val store = StudyStore(folder.newFolder("home")).also { it.loadExamples(); it.setExamDate(null) }
        compose.setContent { StethoscoreApp(store, forceDark = false) }
        compose.waitForIdle()
    }

    /** Every row the card stood among is composed, and none of it is the card. */
    private fun assertHomeHoldsNoCard() {
        compose.onAllNodes(openPlan).assertCountEquals(1)
        compose.onAllNodesWithContentDescription(mockTile).assertCountEquals(1)
        compose.onAllNodesWithText(lastRow).assertCountEquals(1)
        compose.onAllNodesWithTag("examDashboard").assertCountEquals(0)
        compose.onAllNodesWithTag("examDashboardChoose").assertCountEquals(0)
        compose.onAllNodesWithTag("examDashboardChange").assertCountEquals(0)
        compose.onAllNodesWithText("Which exam are you preparing for?").assertCountEquals(0)
        compose.onAllNodesWithText("Study next").assertCountEquals(0)
        compose.onAllNodesWithContentDescription("Change exam").assertCountEquals(0)
    }

    @Test fun homeHoldsNoExamCardWithAnExamChosen() {
        chooseExam()
        home()
        assertHomeHoldsNoCard()
        // the exam is still set up from home: its header asks for the date
        compose.onAllNodesWithTag("homeExamSetUp").assertCountEquals(1)
        compose.onAllNodesWithText("Add your exam date").assertCountEquals(1)
    }

    @Test fun homeHoldsNoExamCardWithNoExamChosen() {
        home()
        assertHomeHoldsNoCard()
        compose.onAllNodesWithTag("homeExamSetUp").assertCountEquals(1)
        compose.onAllNodesWithText("Choose your exam").assertCountEquals(1)
    }

    @Test fun theMockTileFollowsTheTilesWithNoGapWhereTheCardStood() {
        chooseExam()
        home()
        val brain = compose.onAllNodes(hasContentDescription("Brain map.", substring = true)).onFirst().getUnclippedBoundsInRoot()
        val vitals = compose.onAllNodes(hasContentDescription("Opens Progress", substring = true)).onFirst().getUnclippedBoundsInRoot()
        val mock = compose.onNodeWithContentDescription(mockTile).getUnclippedBoundsInRoot()
        val gap = mock.top.value - maxOf(brain.bottom.value, vitals.bottom.value)
        println("T0219 A1: tiles end ${maxOf(brain.bottom.value, vitals.bottom.value)}, mock tile from ${mock.top.value}, gap $gap dp")
        assertEquals("only the list's own gap (${WardSpace.section} dp) stands between the tiles and the mock tile", WardSpace.section.toFloat(), gap, 1f)
    }

    // the card's place now: the exam plan, opened from home's Open plan

    @Test fun theExamPlanHoldsTheCardWithAnExamChosen() {
        chooseExam()
        home()
        compose.onAllNodesWithTag("examDashboard").assertCountEquals(0)
        compose.onAllNodes(openPlan).onFirst().performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        assertEquals(LearnRoute.ExamPlan, LearnRouter.route)
        // one card in the whole tree: the plan's (home under the sheet holds none)
        compose.onAllNodesWithTag("examDashboard").assertCountEquals(1)
        compose.onAllNodesWithTag("examDashboardChange").assertCountEquals(1)
        compose.onAllNodesWithContentDescription("Change exam").assertCountEquals(1)
    }

    @Test fun theExamPlanHoldsTheCardWithNoExamChosen() {
        home()
        compose.onAllNodes(openPlan).onFirst().performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        assertEquals(LearnRoute.ExamPlan, LearnRouter.route)
        compose.onAllNodesWithTag("examDashboard").assertCountEquals(1)
        compose.onAllNodesWithText("Which exam are you preparing for?").assertCountEquals(1)
        assertTrue("its Choose your exam button", compose.onAllNodes(hasTestTag("examDashboardChoose")).fetchSemanticsNodes().isNotEmpty())
    }
}
