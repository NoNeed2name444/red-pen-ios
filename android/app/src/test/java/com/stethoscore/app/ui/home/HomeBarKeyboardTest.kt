package com.stethoscore.app.ui.home

import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.learn.LearnRouterClosed
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// While the keyboard is up, home's floating bar (New set and the dock) stays
// behind it, as iOS's does, so it never rides up over the search's results;
// it is back once the keyboard closes.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HomeBarKeyboardTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private val newSet = "New set. Make questions or cards from a lecture"

    private fun keyboard(up: Boolean) {
        val height = (300 * compose.activity.resources.displayMetrics.density).toInt()
        compose.runOnIdle {
            val view = checkNotNull(composeView(compose.activity.window.decorView)) { "no Compose view" }
            ViewCompat.dispatchApplyWindowInsets(view, WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, if (up) height else 0))
                .setVisible(WindowInsetsCompat.Type.ime(), up).build())
        }
        compose.waitForIdle()
    }

    @Test fun theBarHidesWhileTheKeyboardIsUp() {
        val store = StudyStore(folder.newFolder("home")).also { it.loadExamples() }
        compose.setContent { StethoscoreApp(store, forceDark = false) }
        compose.onNodeWithContentDescription(newSet).assertExists()
        keyboard(up = true)
        compose.onNodeWithContentDescription(newSet).assertDoesNotExist()
        keyboard(up = false)
        compose.onNodeWithContentDescription(newSet).assertExists()
    }

    /** The view Compose reads the window's insets from. */
    private fun composeView(view: View): View? {
        if (view.javaClass.name == "androidx.compose.ui.platform.AndroidComposeView") return view
        if (view is ViewGroup) for (i in 0 until view.childCount) composeView(view.getChildAt(i))?.let { return it }
        return null
    }
}
