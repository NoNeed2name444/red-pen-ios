package com.stethoscore.app.ui.ward

import androidx.activity.ComponentActivity
import androidx.compose.foundation.Indication
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.StethoscoreTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// iOS PressableRowStyle (Shared/Theme.swift): a plain row, held, sinks a
// little and shades, and nothing ripples. The theme gives every plain
// clickable that press as its LocalIndication, and the clickable still clicks.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WardPressIndicationTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun aPlainClickablePressesAsAWardFaceAndStillClicks() {
        var given: Indication? = null
        var clicks = 0
        compose.setContent {
            StethoscoreTheme {
                given = LocalIndication.current
                Box(Modifier.size(48.dp).testTag("row").clickable { clicks++ })
            }
        }
        compose.onNodeWithTag("row").performClick()
        compose.waitForIdle()
        assertTrue("the theme's indication is the Ward press", given === WardPressIndication)
        assertEquals(1, clicks)
    }
}
