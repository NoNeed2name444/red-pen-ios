package com.stethoscore.app.ui.home

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.learn.LearnRoute
import com.stethoscore.app.ui.learn.LearnRouter
import com.stethoscore.app.ui.learn.LearnRouterClosed
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// T0220: the exam is changed in the exam plan's card now (T0219 took the card off
// home), and home's header kept what it showed before the plan opened: the setup
// button ("Choose your exam" / "Add your exam date") after an exam and a date
// were set, or the old countdown. The header's two reads keyed on the library's
// revision alone, and closing the plan bumps LearnRouter.version, not revision.
// Each test changes the exam or the date only inside the plan, closes the plan
// with its Done, and reads home's header with nothing else done.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HomeHeaderAfterPlanTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private val openPlan = SemanticsMatcher("Open plan") {
        it.config.getOrElseNullable(SemanticsActions.OnClick) { null }?.label == "Opens the exam plan and forecast"
    }
    private val setUpButton = "homeExamSetUp"

    private fun prefs() = ApplicationProvider.getApplicationContext<Context>().getSharedPreferences("appearance", Context.MODE_PRIVATE)

    @Before fun noExam() { prefs().edit().clear().commit() }

    private fun home(date: Long? = null) {
        val store = StudyStore(folder.newFolder("home")).also { it.loadExamples(); it.setExamDate(date) }
        compose.setContent { StethoscoreApp(store, forceDark = false) }
        compose.waitForIdle()
    }

    private fun openThePlan() {
        compose.onAllNodes(openPlan).onFirst().performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        assertEquals(LearnRoute.ExamPlan, LearnRouter.route)
    }

    /** The plan's own Done: the one button of that name outside a dialog. */
    private fun closeThePlan() {
        compose.onNode(hasText("Done") and !hasAnyAncestor(isDialog())).performClick()
        compose.waitForIdle()
        assertEquals(null, LearnRouter.route)
    }

    /** Change exam in the plan's card (or Choose your exam on it): the picker opens over the plan. */
    private fun openThePicker(tag: String) {
        compose.onNodeWithTag(tag).performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("examPickerSave").assertExists()
    }

    /** The list is longer than the sheet, so the row is brought into view and tapped by its action, as StudyReachTest taps its rows. */
    private fun pickExam(id: String) {
        compose.onNodeWithTag("examPick-$id").performScrollTo().performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        compose.onNodeWithTag("examPick-$id").assertIsSelected()
    }

    /** The picker's Exam date row, left on the date it opens on (ninety days on), saved with its Done. */
    private fun setTheDate() {
        compose.onNodeWithText("Exam date").performScrollTo().performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        compose.onNode(hasText("Done") and hasAnyAncestor(isDialog())).performClick()
        compose.waitForIdle()
        compose.onAllNodesWithText("Clear the date").assertCountEquals(1)
    }

    private fun savePicker() { compose.onNodeWithTag("examPickerSave").performClick(); compose.waitForIdle() }

    @Test fun anExamAndADateSetInThePlanAreHomesHeaderOnceThePlanCloses() {
        home()
        compose.onAllNodesWithTag(setUpButton).assertCountEquals(1)
        compose.onAllNodesWithText("Choose your exam").assertCountEquals(1)
        openThePlan()
        openThePicker("examDashboardChoose")
        pickExam("plab1")
        setTheDate()
        savePicker()
        closeThePlan()
        compose.onAllNodesWithTag(setUpButton).assertCountEquals(0)
        compose.onAllNodesWithText("Choose your exam").assertCountEquals(0)
        compose.onAllNodesWithText("PLAB 1 in ", substring = true).assertCountEquals(1)
    }

    @Test fun anExamChosenInThePlanMakesHomesButtonAskForTheDate() {
        home()
        compose.onAllNodesWithText("Choose your exam").assertCountEquals(1)
        openThePlan()
        openThePicker("examDashboardChoose")
        pickExam("plab1")
        savePicker()
        closeThePlan()
        compose.onAllNodesWithTag(setUpButton).assertCountEquals(1)
        compose.onAllNodesWithText("Choose your exam").assertCountEquals(0)
        compose.onAllNodesWithText("Add your exam date").assertCountEquals(1)
    }

    @Test fun aDateSetInThePlanReplacesHomesButtonWithTheCountdown() {
        prefs().edit().putString(ExamTrack.storageKey, ExamTrack.plab.rawValue).commit()
        home()
        compose.onAllNodesWithText("Add your exam date").assertCountEquals(1)
        openThePlan()
        openThePicker("examDashboardChange")
        setTheDate()
        savePicker()
        closeThePlan()
        compose.onAllNodesWithTag(setUpButton).assertCountEquals(0)
        compose.onAllNodesWithText("Add your exam date").assertCountEquals(0)
        compose.onAllNodesWithText("PLAB 1 in ", substring = true).assertCountEquals(1)
    }
}
