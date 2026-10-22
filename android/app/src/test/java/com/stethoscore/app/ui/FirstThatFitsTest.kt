package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The quiz's "How sure?" row (iOS ViewThatFits): the widest choice when it fits,
// a narrower one when it does not, and the last, wrapping, choice in any width
// at all. Only the choice laid out is there for TalkBack.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class FirstThatFitsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val width = mutableStateOf(300.dp)

    private fun show(w: Dp) {
        width.value = w
        compose.setContent {
            Box(Modifier.width(width.value)) {
                FirstThatFits(
                    { Box(Modifier.size(200.dp, 20.dp).testTag("wide")) },
                    { Box(Modifier.size(100.dp, 20.dp).testTag("narrow")) },
                    { Box(Modifier.size(1.dp, 20.dp).testTag("wrapping")) },
                )
            }
        }
    }

    private fun shows(tag: String) {
        compose.onNodeWithTag(tag).assertIsDisplayed()
        for (other in listOf("wide", "narrow", "wrapping") - tag) compose.onNodeWithTag(other).assertDoesNotExist()
    }

    @Test fun theWideChoiceFits() { show(300.dp); shows("wide") }
    @Test fun aNarrowWidthFallsBack() { show(150.dp); shows("narrow") }
    @Test fun noWidthGivesTheLastChoice() { show(0.dp); compose.onNodeWithTag("wrapping").assertExists(); for (t in listOf("wide", "narrow")) compose.onNodeWithTag(t).assertDoesNotExist() }
    @Test fun aWidthThatChangesPicksAgain() {
        show(300.dp); shows("wide")
        width.value = 150.dp; compose.waitForIdle(); shows("narrow")
        width.value = 300.dp; compose.waitForIdle(); shows("wide")
    }
}
