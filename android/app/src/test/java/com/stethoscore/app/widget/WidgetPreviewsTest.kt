package com.stethoscore.app.widget

import android.appwidget.AppWidgetProviderInfo
import android.content.Context
import androidx.glance.appwidget.composeForPreview
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.GlanceState
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * The picker's previews: each widget's own composable, at every size it
 * lists, from iOS's gallery numbers (GlanceDigest.sample), in the words the
 * widgets already say.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WidgetPreviewsTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val cairo = ZoneId.of("Africa/Cairo")

    @Test fun theSampleIsIOSsGalleryNumbers() {
        // just after midnight on the day Cairo's clocks go back an hour: 38 steps of 24 hours would end at 23:30 on
        // the 37th day, so the 38 days are counted by date
        val now = LocalDateTime.parse("2026-10-29T00:30").atZone(cairo).toInstant().toEpochMilli()
        val sample = WidgetPreviews.sample(now, cairo)
        val due = DueFace.of(sample)
        assertEquals("24", due.number)
        assertEquals("due now", due.caption)
        assertEquals(listOf("Cardiology" to 14, "Renal" to 10), due.decks.map { it.name to it.count })
        assertEquals(true, due.showsReview)
        val countdown = CountdownFace.of(sample, now, cairo)
        assertEquals(38, countdown.days)
        assertEquals("days to PLAB 1", countdown.caption)
        val today = TodayFace.of(sample, now, cairo)
        assertEquals("32", today.number)
        assertEquals("of 50 done today", today.caption)
        assertEquals(GlanceState.CardsDue::class, sample::class)
    }

    @Test fun eachWidgetsPreviewIsComposedAtEverySizeItLists() {
        for (widget in listOf(DueCardsWidget(), ExamCountdownWidget(), DoneTodayWidget())) {
            assertEquals("${widget::class.simpleName}: the picker gets the sizes the home screen does", widget.sizeMode, widget.previewSizeMode)
            val views = runBlocking { widget.composeForPreview(context, AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN) }
            assertNotNull(views)
        }
        assertEquals(listOf(DueCardsReceiver::class, ExamCountdownReceiver::class, DoneTodayReceiver::class), WidgetPreviews.receivers)
    }

    @Test fun thePreviewsArePublishedAgainForANewFontScale() {
        val before = WidgetPreviews.drawnFor(context)
        assertEquals(before, WidgetPreviews.drawnFor(context))
        RuntimeEnvironment.setFontScale(1.3f)
        assertNotEquals(before, WidgetPreviews.drawnFor(context))
    }
}
