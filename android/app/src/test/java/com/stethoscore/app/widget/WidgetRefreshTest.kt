package com.stethoscore.app.widget

import android.content.Context
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.work.Configuration
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import com.stethoscore.app.data.DailyGoal
import com.stethoscore.app.data.GlanceDigest
import com.stethoscore.app.data.StudyStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime

/**
 * When the widgets next redraw on their own: the next local midnight, or the
 * next card's due time if it comes first and is still ahead, as iOS's
 * timeline (GlanceTimeline.swift:46-51), across Cairo's clock changes.
 */
class WidgetRefreshTest {
    private val cairo = ZoneId.of("Africa/Cairo")
    private val minute = 60_000L
    private val hour = 60 * minute

    private fun cairo(local: String): Long = LocalDateTime.parse(local).atZone(cairo).toInstant().toEpochMilli()
    private fun delay(now: Long, nextDue: Long?) = WidgetRefresh.delayMs(now, nextDue, cairo)

    @Test fun withNoNextCardTheWidgetsRedrawAtMidnight() {
        assertEquals(14 * hour, delay(cairo("2026-11-05T10:00"), null))
        // at midnight itself, the next one
        assertEquals(24 * hour, delay(cairo("2026-11-05T00:00"), null))
        assertEquals(1L, delay(cairo("2026-11-05T23:59:59.999"), null))
    }

    @Test fun aCardDueBeforeMidnightComesFirstAndOneAfterItWaits() {
        val now = cairo("2026-11-05T10:00")
        assertEquals(30 * minute, delay(now, cairo("2026-11-05T10:30")))
        assertEquals(14 * hour, delay(now, cairo("2026-11-06T08:00")))
        // due at midnight exactly: midnight
        assertEquals(14 * hour, delay(now, cairo("2026-11-06T00:00")))
    }

    @Test fun aNextDueMissingOrPastCountsForNothing() {
        val now = cairo("2026-11-05T10:00")
        val midnight = delay(now, null)
        assertEquals("past", midnight, delay(now, cairo("2026-11-05T09:00")))
        assertEquals("now", midnight, delay(now, now))
        assertEquals("long past", midnight, delay(now, 0L))
        // a millisecond ahead is ahead
        assertEquals(1L, delay(now, now + 1))
    }

    @Test fun cairosSpringForwardSkipsMidnight() {
        // Friday 24 April 2026: Cairo's clocks go from 00:00 straight to 01:00 (+02:00 to +03:00), so the day starts at
        // 01:00, two real hours after 22:00 on the Thursday
        val thursday = cairo("2026-04-23T22:00")
        assertEquals("+02:00", ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(thursday), cairo).offset.id)
        assertEquals(2 * hour, delay(thursday, null))
        assertEquals(ZonedDateTime.of(2026, 4, 24, 1, 0, 0, 0, cairo).toInstant().toEpochMilli(), thursday + delay(thursday, null))
        // that Friday is 23 hours long: from its 01:00 to Saturday's midnight
        val friday = cairo("2026-04-24T01:00")
        assertEquals(23 * hour, delay(friday, null))
        // a card due at 00:30, a time that does not exist, is read at 01:30 (+03:00): midnight's 01:00 comes first
        assertEquals(2 * hour, delay(thursday, cairo("2026-04-24T00:30")))
    }

    @Test fun cairosFallBackRepeatsAnHour() {
        // Thursday 29 October 2026: at midnight Cairo's clocks go back to 23:00 (+03:00 to +02:00), so the day has 25
        // hours, and from 10:00 there are 15 to Friday's midnight, not 14
        val morning = cairo("2026-10-29T10:00")
        assertEquals(15 * hour, delay(morning, null))
        // 23:30 the first time (+03:00) is 90 minutes from midnight; the second time (+02:00), 30
        val first = ZonedDateTime.ofStrict(LocalDateTime.parse("2026-10-29T23:30"), ZoneOffset.ofHours(3), cairo).toInstant().toEpochMilli()
        val second = ZonedDateTime.ofStrict(LocalDateTime.parse("2026-10-29T23:30"), ZoneOffset.ofHours(2), cairo).toInstant().toEpochMilli()
        assertEquals(90 * minute, delay(first, null))
        assertEquals(30 * minute, delay(second, null))
        // a card due in the repeated hour, before midnight, comes first
        assertEquals(60 * minute, delay(first, second))
    }

    @Test fun midnightIsTheZonesNotUTCs() {
        // the same instant: 10:00 in Cairo (+02:00 in November) is 08:00 UTC
        val now = cairo("2026-11-05T10:00")
        assertEquals(14 * hour, WidgetRefresh.delayMs(now, null, cairo))
        assertEquals(16 * hour, WidgetRefresh.delayMs(now, null, ZoneId.of("UTC")))
    }
}

/**
 * The on-time redraw as WorkManager runs it: one job at a time, replaced by
 * each new digest, redrawing the widgets and queuing the next after itself.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WidgetRefreshWorkTest {
    @get:Rule val folder = TemporaryFolder()
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val work: WorkManager get() = WorkManager.getInstance(context)
    private val cairo = ZoneId.of("Africa/Cairo")
    private val now = LocalDateTime.parse("2026-11-05T10:00").atZone(cairo).toInstant().toEpochMilli()

    private var timerBefore: Debouncer.Timer = WidgetUpdates.timer
    private var hookBefore: ((GlanceDigest) -> Unit)? = null
    private var goalsBefore: DailyGoal.Store? = null

    @Before fun setUp() {
        val config = Configuration.Builder().setExecutor(SynchronousExecutor()).setMinimumLoggingLevel(Log.DEBUG).build()
        WorkManagerTestInitHelper.initializeTestWorkManager(context, config)
        timerBefore = WidgetUpdates.timer
        hookBefore = StudyStore.onAnyGlanceWritten
        goalsBefore = DailyGoal.store
    }

    @After fun tearDown() {
        WidgetUpdates.timer = timerBefore
        StudyStore.onAnyGlanceWritten = hookBefore
        goalsBefore?.let { DailyGoal.store = it }
    }

    private fun infos(): List<WorkInfo> = work.getWorkInfosForUniqueWork(WidgetRefresh.work).get()
    private fun waiting(): List<WorkInfo> = infos().filter { !it.state.isFinished }

    @Test fun aNewDigestReplacesTheJobQueuedBefore() {
        WidgetRefresh.queue(context, now + 30 * 60_000L, now, cairo)
        val before = waiting().single()
        assertEquals(30 * 60_000L, before.initialDelayMillis)
        WidgetRefresh.queue(context, null, now, cairo)
        // REPLACE cancels the job queued before and deletes it: one job is left, the new one
        val job = infos().single()
        assertNotEquals(before.id, job.id)
        assertEquals(WorkInfo.State.ENQUEUED, job.state)
        assertEquals("the next midnight", 14 * 3_600_000L, job.initialDelayMillis)
    }

    @Test fun theJobRedrawsThenQueuesTheNextAfterItself() {
        WidgetRefresh.queue(context, null)
        val first = waiting().single()
        val drawn = WidgetUpdates.version.value
        WorkManagerTestInitHelper.getTestDriver(context)!!.setInitialDelayMet(first.id)
        assertTrue("the job redrew the widgets", WidgetUpdates.version.value > drawn)
        assertEquals(WorkInfo.State.SUCCEEDED, infos().single { it.id == first.id }.state)
        // no digest on disk, so no next card: the next one waits for midnight
        val next = waiting().single()
        assertEquals(WorkInfo.State.ENQUEUED, next.state)
        val midnight = WidgetRefresh.delayMs(System.currentTimeMillis(), null, ZoneId.systemDefault())
        assertEquals(midnight.toDouble(), next.initialDelayMillis.toDouble(), 10_000.0)
    }

    @Test fun eachNewDigestFromTheStoreQueuesTheJob() {
        val timer = HandTimer()
        WidgetUpdates.timer = timer
        DailyGoal.store = DailyGoal.MemoryStore()
        WidgetUpdates.install(context)
        assertEquals(emptyList<WorkInfo>(), infos())
        // the store's first digest, at its load: redrawn and queued once the digests stop coming
        StudyStore(folder.root)
        assertEquals(emptyList<WorkInfo>(), infos())
        timer.fire()
        assertEquals(WorkInfo.State.ENQUEUED, waiting().single().state)
    }
}

/** A timer the test runs by hand. */
internal class HandTimer : Debouncer.Timer {
    val waiting = mutableListOf<Pair<Long, () -> Unit>>()
    var cancelled = 0
    override fun schedule(delayMs: Long, action: () -> Unit): () -> Unit {
        val item = delayMs to action
        waiting += item
        return { if (waiting.remove(item)) cancelled++ }
    }
    fun fire() { val due = waiting.toList(); waiting.clear(); due.forEach { it.second() } }
}
