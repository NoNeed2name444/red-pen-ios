package com.stethoscore.app.ui.ward

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.WardCard
import com.stethoscore.app.ui.wardColor
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// What the dark tour showed wrong on the Ward faces every screen shares (T0130):
// a ring's middle filled white or grey, so the timer's "24:57" and the scores in
// it could not be read (the groove's outline lost WardAnnulus's even-odd rule,
// so its hole was filled with the face and its lights), and card titles that
// name no colour drawn in Material's default black (a card gave its words no
// content colour). Each is checked in light and dark.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WardDarkFacesTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val dark = mutableStateOf(false)

    @Test fun aRingsMiddleIsThePageColour() {
        var page = Color.Unspecified
        compose.setContent {
            StethoscoreTheme(dark.value) {
                page = wardColor(WardToken.background)
                // the focus timer's ring, its words left out so the middle is the ground alone
                Box(Modifier.testTag("ground").background(page).padding(8.dp)) {
                    WardRing(0.75, Modifier.size(180.dp), tone = WardTone.Red, centre = "")
                }
            }
        }
        for (mode in listOf(false, true)) {
            dark.value = mode
            compose.waitForIdle()
            val middle = pixelAtMiddleOf("ground")
            val name = if (mode) "dark" else "light"
            assertEquals("$name: the ring's middle is the page colour, not filled", hex(page), hex(middle))
        }
    }

    @Test fun aCardsTitleIsInTheInk() {
        var ink = Color.Unspecified
        var seen = Color.Unspecified
        compose.setContent {
            StethoscoreTheme(dark.value) {
                ink = wardColor(WardToken.ink)
                // "Make your first set": a title with a style and no colour of its own
                WardCard {
                    seen = LocalContentColor.current
                    Text("Make your first set", style = WardType.title.textStyle())
                }
            }
        }
        for (mode in listOf(false, true)) {
            dark.value = mode
            compose.waitForIdle()
            val name = if (mode) "dark" else "light"
            assertEquals("$name: a card's words take the ink", hex(ink), hex(seen))
        }
    }

    /** The window drawn in software, as it would be on screen, read at the middle of the node tagged [tag]. */
    private fun pixelAtMiddleOf(tag: String): Color {
        val bounds = compose.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot
        val root = compose.activity.window.decorView.rootView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        compose.runOnIdle { root.draw(Canvas(bitmap)) }
        return Color(bitmap.getPixel(bounds.center.x.toInt(), bounds.center.y.toInt()))
    }

    private fun hex(c: Color): String = "%06X".format(
        ((c.red * 255 + 0.5f).toInt() shl 16) or ((c.green * 255 + 0.5f).toInt() shl 8) or (c.blue * 255 + 0.5f).toInt())
}
