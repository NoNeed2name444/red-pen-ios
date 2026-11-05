package com.stethoscore.app.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.stethoscore.app.data.GlanceShelf
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/**
 * The widgets' redraw on time with the app closed, as iOS's timeline has an
 * entry at midnight, when today's count and the countdown turn over, and at
 * the next card's due time, when the due count may have grown
 * (ios/StethoscoreWidgets/GlanceTimeline.swift:46-51). One unique WorkManager
 * job, no network, for whichever comes first: queued after each new digest
 * (WidgetUpdates), replacing the one before, again by the job itself once it
 * has redrawn, and at once when the clock or the zone changes
 * (WidgetClockReceiver). Never from a widget's onUpdate: a one-time job that finishes
 * there sets onUpdate off again, in a loop.
 */
object WidgetRefresh {
    /** The job's unique name: one at a time. */
    const val work = "widget-refresh"

    /**
     * How long from [now] until the widgets next turn over: the start of the
     * next day in [zone] (one hour on from midnight where the clocks skip it,
     * as Cairo's do on the last Friday of April), or [nextDue] if it comes
     * first and is still ahead; a missing one, or one already past, counts
     * for nothing, as iOS adds it only when it is later than now.
     */
    fun delayMs(now: Long, nextDue: Long?, zone: ZoneId): Long {
        val midnight = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        val due = nextDue?.takeIf { it > now }
        return (if (due != null && due < midnight) due else midnight) - now
    }

    /** After a new digest: the job for its [nextDue], in place of any queued or running one. */
    fun queue(context: Context, nextDue: Long?, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()) {
        enqueue(context, ExistingWorkPolicy.REPLACE, delayMs(now, nextDue, zone))
    }

    /**
     * The clock was set or the zone changed (WidgetClockReceiver): the job runs
     * at once, in place of one timed for the old clock, and then queues the
     * next for the new zone's midnight or the next due card (queueNext). At
     * once, not at [queue]'s delay: the faces count today and the days to the
     * exam in the zone they are drawn in, so a change that crosses midnight
     * changes them now.
     */
    fun queueNow(context: Context) {
        enqueue(context, ExistingWorkPolicy.REPLACE, 0L)
    }

    /**
     * From the job, as it ends: the next one, to run after it (REPLACE would
     * cancel the job asking). A new digest's [queue] replaces both.
     */
    internal fun queueNext(context: Context, nextDue: Long?, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()) {
        enqueue(context, ExistingWorkPolicy.APPEND_OR_REPLACE, delayMs(now, nextDue, zone))
    }

    private fun enqueue(context: Context, policy: ExistingWorkPolicy, delayMs: Long) {
        val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>().setInitialDelay(delayMs, TimeUnit.MILLISECONDS).build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(work, policy, request)
    }
}

/**
 * The job WidgetRefresh queues: redraws every placed widget from the digest
 * on disk at the time it runs, then queues the next from that digest's next
 * due card, unless a new digest has replaced it meanwhile.
 */
class WidgetRefreshWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val app = applicationContext
        runCatching { WidgetUpdates.updateNow(app) }
        if (!isStopped) WidgetRefresh.queueNext(app, GlanceShelf(app.filesDir).read()?.nextDue)
        return Result.success()
    }
}

/**
 * The clock was set, or the time zone changed (a flight, or the owner's own
 * setting): the job queued for the old clock's midnight would come at the
 * wrong hour, so the widgets are redrawn now and the next job is timed again
 * (WidgetRefresh.queueNow). Both broadcasts are exempt from Android 8's limit
 * on implicit broadcasts, so the manifest entry still hears them with the app
 * closed; only the system sends them, so the receiver is not exported.
 */
class WidgetClockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in actions) return
        WidgetRefresh.queueNow(context)
    }

    companion object {
        /** The two it is declared for (AndroidManifest.xml). */
        val actions = setOf(Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED)
    }
}
