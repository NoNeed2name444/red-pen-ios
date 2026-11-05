package com.stethoscore.app.widget

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.AppLink
import com.stethoscore.app.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** A widget's tap: the right AppLink, on MainActivity, with SINGLE_TOP | CLEAR_TOP so onNewIntent takes it. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WidgetLinksTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val set = AppLink.OpenSet("7c9e6679-7425-40de-944b-e07fc1f90ae7")

    @Test fun eachTapOpensItsLinkOnMainActivityWithTheFlags() {
        for (link in listOf(AppLink.ReviewDue, AppLink.ExamPlan, set)) {
            val intent = WidgetLinks.intent(context, link)
            assertEquals(Intent.ACTION_VIEW, intent.action)
            assertEquals(link.url, intent.dataString)
            assertEquals(MainActivity::class.java.name, intent.component?.className)
            assertTrue("SINGLE_TOP", intent.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)
            assertTrue("CLEAR_TOP", intent.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0)
            // MainActivity reads it back as the same link, never as a file to import
            assertEquals(link, AppLink.from(intent))
            assertTrue(AppLink.isLink(intent))
            assertEquals(link, MainActivity.coldLink(intent, restored = false))
        }
    }

    @Test fun eachWidgetTapsTheLinkItsIOSTwinDoes() {
        val state = com.stethoscore.app.data.GlanceState.NoFile
        assertEquals(AppLink.ReviewDue, DueFace.of(state).link)
        assertEquals(AppLink.ExamPlan, CountdownFace.of(state, 0).link)
        assertEquals(AppLink.ReviewDue, TodayFace.of(state, 0).link)
    }
}
