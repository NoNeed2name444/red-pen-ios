package com.stethoscore.app.ui.sources

import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.ui.StethoscoreTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The lecture reader's sheet fills the window, and Material's sheet keeps only
// the bottom bar clear by default, so the tour (r074) showed Done and the
// lecture's name under the status bar. The reader keeps clear of every bar.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SourcePreviewSheetTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val lecture = SourceDoc(name = "Renal lecture", kind = "pdf", pages = listOf(SourcePage(1, "Nephritic syndrome")))

    @Test fun theReaderSitsBelowTheStatusBar() {
        compose.setContent { StethoscoreTheme { SourcePreviewSheet(lecture, null, 1) {} } }
        compose.waitForIdle()
        // a status bar 40 dp tall over every window, the sheet's own among them
        val bar = (40 * compose.activity.resources.displayMetrics.density).toInt()
        compose.runOnIdle {
            val views = windowRoots().flatMap { composeViews(it) }
            assertTrue("the sheet has a window of its own", views.size >= 2)
            for (view in views) ViewCompat.dispatchApplyWindowInsets(view, WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, bar, 0, 0)).build())
        }
        compose.waitForIdle()
        val top = compose.onNodeWithText("Done").getBoundsInRoot().top
        assertTrue("Done starts below the 40 dp status bar, at $top", top >= 40.dp)
    }

    /** Every window's root view: the activity's and the sheet's. */
    @Suppress("UNCHECKED_CAST")
    private fun windowRoots(): List<View> {
        val global = Class.forName("android.view.WindowManagerGlobal")
        val instance = global.getMethod("getInstance").invoke(null)
        val views = global.getDeclaredField("mViews").apply { isAccessible = true }.get(instance) as List<View>
        return views.toList()
    }

    /** The views Compose reads a window's insets from. */
    private fun composeViews(view: View): List<View> {
        if (view.javaClass.name == "androidx.compose.ui.platform.AndroidComposeView") return listOf(view)
        if (view is ViewGroup) return (0 until view.childCount).flatMap { composeViews(view.getChildAt(it)) }
        return emptyList()
    }
}
