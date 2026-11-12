package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
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

// The quiz's deck (T0247), chosen as FirstThatFits chooses by width but by height: the first choice that leaves the
// page above it room, and the last, smallest one when none does. Only the choice laid out is there for TalkBack.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class FirstThatLeavesRoomTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val height = mutableStateOf(300.dp)

    private fun show(h: Dp) {
        height.value = h
        compose.setContent {
            Box(Modifier.height(height.value)) {
                FirstThatLeavesRoom(
                    50.dp,
                    { Box(Modifier.size(100.dp, 120.dp).testTag("tall")) },
                    { Box(Modifier.size(100.dp, 60.dp).testTag("short")) },
                    { Box(Modifier.size(100.dp, 10.dp).testTag("least")) },
                )
            }
        }
    }

    private fun shows(tag: String) {
        compose.onNodeWithTag(tag).assertIsDisplayed()
        for (other in listOf("tall", "short", "least") - tag) compose.onNodeWithTag(other).assertDoesNotExist()
    }

    @Test fun theFirstChoiceWhenThePageKeepsItsRoom() { show(300.dp); shows("tall") }
    @Test fun aSmallerChoiceWhenTheFirstTakesTheRoom() { show(150.dp); shows("short") }
    @Test fun theLastChoiceWhenNoneLeavesIt() { show(80.dp); shows("least") }
    @Test fun aHeightThatChangesPicksAgain() {
        show(300.dp); shows("tall")
        height.value = 150.dp; compose.waitForIdle(); shows("short")
        height.value = 300.dp; compose.waitForIdle(); shows("tall")
    }
}
