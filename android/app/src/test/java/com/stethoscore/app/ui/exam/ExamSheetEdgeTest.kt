package com.stethoscore.app.ui.exam

import android.view.View
import android.view.ViewGroup
import android.view.Window
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.stethoscore.app.ui.StethoscoreTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

// ExamSheet is a full-screen dialog (no platform width, fillMaxSize), so it
// goes edge to edge: its base reaches under the bars, while the page inside
// keeps clear of them (safeDrawingPadding), and its bars' icons follow the
// app's mode.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ExamSheetEdgeTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun open(dark: Boolean) {
        compose.setContent { StethoscoreTheme(dark = dark) { ExamSheet({}) { Box(Modifier.fillMaxSize().testTag("sheetPage")) } } }
        compose.waitForIdle()
    }

    private fun sheetWindow(): Window = checkNotNull(checkNotNull(ShadowDialog.getLatestDialog()) { "no sheet" }.window)

    private fun composeView(view: View): View? {
        if (view.javaClass.name == "androidx.compose.ui.platform.AndroidComposeView") return view
        if (view is ViewGroup) for (i in 0 until view.childCount) composeView(view.getChildAt(i))?.let { return it }
        return null
    }

    @Test fun theBaseReachesUnderTheBarsAndThePageStaysClear() {
        open(dark = false)
        val window = sheetWindow()
        val density = compose.activity.resources.displayMetrics.density
        compose.runOnIdle {
            ViewCompat.dispatchApplyWindowInsets(window.decorView, WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, (24 * density).toInt(), 0, 0))
                .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(0, 0, 0, (48 * density).toInt()))
                .build())
        }
        compose.waitForIdle()
        val view = checkNotNull(composeView(window.decorView)) { "no Compose view in the sheet" }
        val at = IntArray(2).also { view.getLocationInWindow(it) }
        assertEquals("the sheet's base starts at the window's top, under the status bar", 0, at[1])
        assertEquals("and runs to its foot, under the navigation bar", window.decorView.height, view.height)
        val page = compose.onNodeWithTag("sheetPage").getBoundsInRoot()
        assertEquals("the page starts below the status bar", 24f, page.top.value, 0.5f)
        val foot = view.height / density - 48f
        assertEquals("the page ends above the navigation bar", foot, page.bottom.value, 0.5f)
    }

    @Test fun itsBarsFollowTheAppsMode() {
        var dark by mutableStateOf(false)
        compose.setContent { StethoscoreTheme(dark = dark) { ExamSheet({}) { Box(Modifier.fillMaxSize()) } } }
        compose.waitForIdle()
        val window = sheetWindow()
        val bars = WindowInsetsControllerCompat(window, window.decorView)
        assertTrue("dark status icons in light", bars.isAppearanceLightStatusBars)
        assertTrue("dark navigation icons in light", bars.isAppearanceLightNavigationBars)
        dark = true
        compose.waitForIdle()
        assertFalse("light status icons in dark", bars.isAppearanceLightStatusBars)
        assertFalse("light navigation icons in dark", bars.isAppearanceLightNavigationBars)
    }
}
