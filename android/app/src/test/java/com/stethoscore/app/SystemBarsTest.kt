package com.stethoscore.app

import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
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

// The bars follow the app's own light or dark setting, not the phone's:
// MainActivity.showGround (the start, and Settings' switch) sets them through
// enableEdgeToEdge, and the theme no longer sets the icons over it.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SystemBarsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val activity get() = compose.activity
    private fun bars() = WindowInsetsControllerCompat(activity.window, activity.window.decorView)

    private fun shown(dark: Boolean) {
        compose.runOnUiThread { MainActivity.showGround(activity, dark) }
        compose.waitForIdle()
    }

    @Test @Config(qualifiers = "night") fun aLightAppOnADarkPhoneHasDarkIcons() {
        shown(dark = false)
        assertTrue("dark status icons", bars().isAppearanceLightStatusBars)
        assertTrue("dark navigation icons", bars().isAppearanceLightNavigationBars)
    }

    @Test @Config(qualifiers = "notnight") fun aDarkAppOnALightPhoneHasLightIcons() {
        shown(dark = true)
        assertFalse("light status icons", bars().isAppearanceLightStatusBars)
        assertFalse("light navigation icons", bars().isAppearanceLightNavigationBars)
    }

    @Test fun settingsSwitchTurnsThemBothWays() {
        shown(dark = true)
        assertFalse(bars().isAppearanceLightStatusBars)
        shown(dark = false)
        assertTrue(bars().isAppearanceLightStatusBars)
        assertTrue(bars().isAppearanceLightNavigationBars)
    }

    @Test fun theBarsAreClearAndTheSystemKeepsTheNavigationBarReadable() {
        for (dark in listOf(false, true)) {
            shown(dark)
            @Suppress("DEPRECATION") assertEquals("status bar ($dark)", Color.TRANSPARENT, activity.window.statusBarColor)
            @Suppress("DEPRECATION") assertEquals("navigation bar ($dark)", Color.TRANSPARENT, activity.window.navigationBarColor)
            assertTrue("three-button navigation keeps the system's scrim ($dark)", activity.window.isNavigationBarContrastEnforced)
            assertFalse("no scrim under the status bar ($dark)", activity.window.isStatusBarContrastEnforced)
        }
    }

    @Test fun theThemeLeavesTheIconsToTheActivity() {
        shown(dark = false)
        // a theme in the other mode sets nothing over what the activity chose
        compose.setContent { StethoscoreTheme(dark = true) { } }
        compose.waitForIdle()
        assertTrue(bars().isAppearanceLightStatusBars)
        assertTrue(bars().isAppearanceLightNavigationBars)
    }
}
