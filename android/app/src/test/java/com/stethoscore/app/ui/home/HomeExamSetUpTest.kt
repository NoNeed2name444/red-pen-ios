package com.stethoscore.app.ui.home

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.learn.LearnRouterClosed
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// T0211 A6: on a first run, with no exam date, the header's countdown slot was
// empty. It holds one compact button now that opens the exam setup, Your exam:
// "Choose your exam" while none is chosen, "Add your exam date" once one is.
// With a date it is the countdown again, and no button.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HomeExamSetUpTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private fun prefs() = ApplicationProvider.getApplicationContext<Context>().getSharedPreferences("appearance", Context.MODE_PRIVATE)

    @Before fun noExam() { prefs().edit().clear().commit() }

    private fun home(date: Long? = null): StudyStore {
        val store = StudyStore(folder.newFolder("home")).also { it.loadExamples(); it.setExamDate(date) }
        compose.setContent { StethoscoreApp(store, forceDark = false) }
        compose.waitForIdle()
        return store
    }

    @Test fun theWords() {
        assertEquals("Choose your exam", ExamCountdown.setUp(examChosen = false))
        assertEquals("Add your exam date", ExamCountdown.setUp(examChosen = true))
    }

    @Test fun aFirstRunsSlotOpensTheExamSetUp() {
        home()
        val button = compose.onNodeWithTag("homeExamSetUp", useUnmergedTree = false)
        button.assertIsDisplayed()
        val node = button.fetchSemanticsNode()
        assertTrue("it says what it is: Choose your exam", compose.onAllNodes(hasText("Choose your exam")).fetchSemanticsNodes().isNotEmpty())
        assertEquals("TalkBack hears where it goes", ExamCountdown.setUpHint, node.config[SemanticsActions.OnClick].label)
        button.performClick()
        compose.waitForIdle()
        assertTrue("it opens Your exam", compose.onAllNodes(hasText("Your exam")).fetchSemanticsNodes().isNotEmpty())
    }

    @Test fun anExamWithNoDateAsksForTheDate() {
        prefs().edit().putString(ExamTrack.storageKey, ExamTrack.plab.rawValue).commit()
        home()
        compose.onNodeWithTag("homeExamSetUp").assertIsDisplayed()
        assertTrue(compose.onAllNodes(hasText("Add your exam date")).fetchSemanticsNodes().isNotEmpty())
    }

    @Test fun aDateShowsTheCountdownAndNoButton() {
        home(System.currentTimeMillis() + 30L * 24 * 3600 * 1000)
        assertTrue("no button with a date", compose.onAllNodes(androidx.compose.ui.test.hasTestTag("homeExamSetUp")).fetchSemanticsNodes().isEmpty())
        assertTrue("the countdown", compose.onAllNodes(hasText(" in ", substring = true)).fetchSemanticsNodes().isNotEmpty())
    }
}
