package com.stethoscore.app.ui.learn

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.ward.WardSection
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.wardColor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// Bedtime (r060, the owner, 22 Oct): it no longer stays dark in light mode. The
// re-read follows the app's mode, on that mode's page colour, as every other
// learning sheet does (LearnSheet's theme is the app's, Bedtime or not).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BedtimeModeTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learn = LearnRouterClosed()

    private val dark = mutableStateOf(false)

    @Test fun bedtimeFollowsTheAppsMode() {
        val store = StudyStore(folder.newFolder("bedtime"))
        val page = mutableMapOf<Boolean, Color>()
        LearnRouter.open(LearnRoute.Bedtime)
        compose.setContent {
            StethoscoreTheme(false) { page[false] = wardColor(WardToken.background) }
            StethoscoreTheme(true) { page[true] = wardColor(WardToken.background) }
            LearnSheet(store, dark.value, WardSection.outside) {}
        }
        compose.onNodeWithText("Today’s misses").assertExists()
        assertNotEquals("light and dark have different page colours", hex(page.getValue(false)), hex(page.getValue(true)))
        for (mode in listOf(false, true)) {
            dark.value = mode
            compose.waitForIdle()
            val name = if (mode) "dark" else "light"
            assertEquals("$name: bedtime is on the $name page colour", hex(page.getValue(mode)), hex(groundPixel()))
        }
    }

    /** The window drawn in software, read low in the middle, under the sheet's few lines. */
    private fun groundPixel(): Color {
        val root = compose.activity.window.decorView.rootView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        compose.runOnIdle { root.draw(Canvas(bitmap)) }
        return Color(bitmap.getPixel(root.width / 2, root.height * 9 / 10))
    }

    private fun hex(c: Color): String = "%06X".format(
        ((c.red * 255 + 0.5f).toInt() shl 16) or ((c.green * 255 + 0.5f).toInt() shl 8) or (c.blue * 255 + 0.5f).toInt())
}
