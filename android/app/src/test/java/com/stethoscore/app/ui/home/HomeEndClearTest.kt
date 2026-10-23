package com.stethoscore.app.ui.home

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.learn.LearnRouterClosed
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// Home and the library (T0131 item 3, r014-home-*): New set and the dock float
// over the page, and the rows pass behind them at rest (the owner, 22 Oct: no
// cut above the bar), but the list's end row lets its last card scroll wholly
// clear of them, so nothing at the bottom stays covered.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HomeEndClearTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private val newSet = "New set. Make questions or cards from a lecture"
    private val last = "Study aid · Not for clinical decisions"

    @Test fun theLastRowScrollsClearOfNewSetAndTheDock() {
        val store = StudyStore(folder.newFolder("home")).also { it.loadExamples() }
        compose.setContent { StethoscoreApp(store, forceDark = false) }
        val list = compose.onAllNodes(hasScrollToNodeAction()).onFirst()
        list.performScrollToNode(hasText(last))
        // on to the list's end: a few long swipes, past the end row
        repeat(4) { list.performTouchInput { swipeUp() } }
        compose.waitForIdle()
        val row = compose.onNodeWithText(last).getUnclippedBoundsInRoot()
        val bar = compose.onNodeWithContentDescription(newSet).getUnclippedBoundsInRoot()
        assertTrue("the last row (bottom ${row.bottom}) ends above New set (top ${bar.top})", row.bottom <= bar.top)
    }
}
