package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import com.stethoscore.app.data.StudyStore
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The twin of iOS b3b21c29 ("Let a swipe from the screen's edge go back"):
// on Android the edge swipe (and predictive back, on by default for apps
// targeting 36 and up) is the system's back, sent to the activity's
// OnBackPressedDispatcher. Every pushed screen goes back on it to home.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SwipeBackTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private fun backFrom(screen: String) {
        val store = StudyStore(folder.newFolder(screen))
        compose.setContent { StethoscoreApp(store, initialScreen = screen, forceDark = false) }
        compose.onNodeWithText("YOUR STUDY WARD").assertDoesNotExist()
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.waitForIdle()
        compose.onNodeWithText("YOUR STUDY WARD").assertExists()
    }

    @Test fun backFromVitals() = backFrom("vitals")
    @Test fun backFromSettings() = backFrom("settings")
    @Test fun backFromNewSet() = backFrom("new")
    @Test fun backFromDueToday() = backFrom("due")
}
