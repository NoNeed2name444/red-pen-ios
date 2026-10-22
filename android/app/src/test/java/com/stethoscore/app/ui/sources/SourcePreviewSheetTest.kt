package com.stethoscore.app.ui.sources

import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.ui.Modifier
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
        compose.setContent {
            StethoscoreTheme {
                // the sheet's content, kept clear of the bars as SourcePreviewSheet keeps it
                Box(Modifier.fillMaxSize().windowInsetsPadding(sourcePreviewInsets)) {
                    SourcePreview(lecture, null, 1, {}, Modifier.fillMaxSize())
                }
            }
        }
        // a status bar 40 dp tall over the window
        val bar = (40 * compose.activity.resources.displayMetrics.density).toInt()
        compose.runOnIdle {
            val view = checkNotNull(composeView(compose.activity.window.decorView)) { "no Compose view" }
            ViewCompat.dispatchApplyWindowInsets(view, WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, bar, 0, 0)).build())
        }
        compose.waitForIdle()
        val top = compose.onNodeWithText("Done").getBoundsInRoot().top
        assertTrue("Done starts below the 40 dp status bar, at $top", top >= 40.dp)
    }

    /** The view Compose reads the window's insets from. */
    private fun composeView(view: View): View? {
        if (view.javaClass.name == "androidx.compose.ui.platform.AndroidComposeView") return view
        if (view is ViewGroup) for (i in 0 until view.childCount) composeView(view.getChildAt(i))?.let { return it }
        return null
    }
}
