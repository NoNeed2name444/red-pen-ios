package com.stethoscore.app

import android.graphics.Color
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.core.view.WindowInsetsControllerCompat
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.exam.ExamSheet
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

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

    // Android 8 and 9 draw the navigation bar's scrim from the app's style
    // (EdgeToEdgeApi26/28), so it has to take the app's mode as the icons do:
    // taking the phone's put light icons on a light scrim for a dark app.
    @Test @Config(sdk = [28], qualifiers = "notnight") fun onAndroid9ADarkAppOnALightPhoneHasADarkScrim() {
        shown(dark = true)
        @Suppress("DEPRECATION") assertEquals(Color.argb(0x80, 0x1b, 0x1b, 0x1b), activity.window.navigationBarColor)
        assertFalse("light navigation icons", bars().isAppearanceLightNavigationBars)
    }

    @Test @Config(sdk = [28], qualifiers = "night") fun onAndroid9ALightAppOnADarkPhoneHasALightScrim() {
        shown(dark = false)
        @Suppress("DEPRECATION") assertEquals(Color.argb(0xe6, 0xFF, 0xFF, 0xFF), activity.window.navigationBarColor)
        assertTrue("dark navigation icons", bars().isAppearanceLightNavigationBars)
    }

    // An exam sheet is its own window: it meets a cutout as the app's does
    // (enableEdgeToEdge's mode), so no dimmed strip shows beside it.
    private fun sheetMeetsTheCutoutAsTheApp(mode: Int) {
        shown(dark = false)
        compose.setContent { StethoscoreTheme(dark = false) { ExamSheet({}) { } } }
        compose.waitForIdle()
        val sheet = checkNotNull(ShadowDialog.getLatestDialog()?.window) { "no sheet" }
        assertEquals("the app's window", mode, activity.window.attributes.layoutInDisplayCutoutMode)
        assertEquals("the sheet's window", mode, sheet.attributes.layoutInDisplayCutoutMode)
    }

    @Test fun anExamSheetMeetsTheCutoutAsTheAppDoes() =
        sheetMeetsTheCutoutAsTheApp(WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS)

    @Test @Config(sdk = [28]) fun onAndroid9AnExamSheetMeetsTheCutoutAsTheAppDoes() =
        sheetMeetsTheCutoutAsTheApp(WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES)

    @Test fun theThemeLeavesTheIconsToTheActivity() {
        shown(dark = false)
        // a theme in the other mode sets nothing over what the activity chose
        compose.setContent { StethoscoreTheme(dark = true) { } }
        compose.waitForIdle()
        assertTrue(bars().isAppearanceLightStatusBars)
        assertTrue(bars().isAppearanceLightNavigationBars)
    }
}
