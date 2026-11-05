package com.stethoscore.app.widget

import android.app.Activity
import android.app.Application
import android.content.res.Configuration
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.GlanceDigest
import com.stethoscore.app.data.StudyStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The widgets are fitted at the font scale and density they are drawn at, so
 * a new one redraws them: heard while the process runs, and caught up on at
 * the app's next start when it was missed.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WidgetScaleTest {
    private val app: Application get() = ApplicationProvider.getApplicationContext()
    private val timer = HandTimer()
    private var timerBefore: Debouncer.Timer = WidgetUpdates.timer
    private var hookBefore: ((GlanceDigest) -> Unit)? = null

    @Before fun setUp() {
        timerBefore = WidgetUpdates.timer
        hookBefore = StudyStore.onAnyGlanceWritten
        WidgetUpdates.timer = timer
    }

    @After fun tearDown() {
        WidgetUpdates.timer = timerBefore
        StudyStore.onAnyGlanceWritten = hookBefore
    }

    @Test fun aNewFontScaleOrDensityRedrawsTheWidgetsAndARotationDoesNot() {
        WidgetUpdates.install(app)
        val config = Configuration(app.resources.configuration)
        val turned = Configuration(config).apply {
            orientation = if (config.orientation == Configuration.ORIENTATION_PORTRAIT) Configuration.ORIENTATION_LANDSCAPE else Configuration.ORIENTATION_PORTRAIT
        }
        app.onConfigurationChanged(turned)
        assertEquals("a rotation keeps the fit", 0, timer.waiting.size)
        app.onConfigurationChanged(Configuration(config).apply { fontScale = 1.3f })
        assertEquals("a larger font redraws", 1, timer.waiting.size)
        app.onConfigurationChanged(Configuration(config).apply { fontScale = 1.3f; densityDpi = config.densityDpi + 80 })
        assertEquals("a new display size redraws, once for the burst", 1, timer.waiting.size)
        assertEquals(1, timer.cancelled)
        // a second install in the same process listens once
        WidgetUpdates.install(app)
        app.onConfigurationChanged(Configuration(config).apply { fontScale = 2.0f })
        assertEquals(1, timer.waiting.size)
        assertEquals(2, timer.cancelled)
    }

    @Test fun eachStartOfAnAppScreenCatchesUp() {
        WidgetUpdates.install(app)
        assertEquals(0, timer.waiting.size)
        Robolectric.buildActivity(Activity::class.java).create().start()
        assertEquals("the screen's onStart", 1, timer.waiting.size)
    }

    @Test fun theScaleTheWidgetsWereDrawnAtIsKept() {
        WidgetUpdates.prefs(app).edit().clear().commit()
        assertNull(WidgetUpdates.drawnScale(app))
        WidgetUpdates.drawn(app)
        val now = DrawnScale.of(app.resources.configuration)
        assertEquals(now, WidgetUpdates.drawnScale(app))
        assertFalse("drawn at this scale", WidgetUpdates.needsRedraw(WidgetUpdates.drawnScale(app), now))
        assertTrue("no record", WidgetUpdates.needsRedraw(null, now))
        assertTrue("another font scale", WidgetUpdates.needsRedraw(now.copy(fontScale = 1.3f), now))
        assertTrue("another density", WidgetUpdates.needsRedraw(now.copy(densityDpi = now.densityDpi + 80), now))
    }

    @Test fun anAppStartAfterAMissedFontChangeRedrawsAndRecordsTheNewScale() {
        WidgetUpdates.drawn(app)
        val before = WidgetUpdates.drawnScale(app)
        // the font grew while no process heard it
        RuntimeEnvironment.setFontScale(1.3f)
        val drawn = WidgetUpdates.version.value
        WidgetUpdates.catchUp(app)
        assertTrue("redrawn", WidgetUpdates.version.value > drawn)
        assertNotEquals(before, WidgetUpdates.drawnScale(app))
        assertEquals(1.3f, WidgetUpdates.drawnScale(app)!!.fontScale, 0f)
        // and the next start finds nothing to do
        val again = WidgetUpdates.version.value
        WidgetUpdates.catchUp(app)
        assertEquals(again, WidgetUpdates.version.value)
    }
}
