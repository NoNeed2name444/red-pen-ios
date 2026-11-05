package com.stethoscore.app.widget

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import androidx.glance.appwidget.updateAll
import com.stethoscore.app.data.StudyStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Runs the last of a burst of calls once, [delayMs] after the calls stop (a
 * review session writes the digest after each card). Plain Kotlin over a
 * [Timer], so it is tested on the JVM with a hand-driven one (WidgetUpdatesTest).
 */
class Debouncer(private val delayMs: Long, private val timer: Timer) {
    /** Schedules [action] after a delay; the returned function cancels it if it has not run. */
    fun interface Timer {
        fun schedule(delayMs: Long, action: () -> Unit): () -> Unit
    }

    private var cancel: (() -> Unit)? = null

    @Synchronized fun submit(action: () -> Unit) {
        cancel?.invoke()
        cancel = timer.schedule(delayMs) { action() }
    }
}

/**
 * Asks the three widgets to draw the new digest, off the save thread and a
 * few seconds after the digest stops changing (iOS GlancePublisher reloads
 * the same way). StudyStore only calls this when what the widgets show changed.
 */
object WidgetUpdates {
    /** iOS's "a few seconds" after the library stops changing. */
    const val delayMs = 2_000L

    private val executor = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "widget-updates").apply { isDaemon = true } }
    private val timer = Debouncer.Timer { delay, action ->
        val future: ScheduledFuture<*> = executor.schedule({ runCatching(action) }, delay, TimeUnit.MILLISECONDS)
        ({ future.cancel(false) })
    }
    private val debouncer = Debouncer(delayMs, timer)

    /** Counts the digests the widgets were told of; a drawn widget reads the file again when it moves. */
    val version = MutableStateFlow(0L)

    /** Every store's new digest updates the widgets (StudyStore.onAnyGlanceWritten). */
    fun install(context: Context) {
        val app = context.applicationContext
        StudyStore.onAnyGlanceWritten = { debouncer.submit { updateNow(app) } }
    }

    /** Redraws every placed widget from the file on disk; no widget placed is a no-op. */
    fun updateNow(context: Context) {
        version.value += 1
        runBlocking {
            for (widget in listOf(DueCardsWidget(), ExamCountdownWidget(), DoneTodayWidget())) {
                runCatching { widget.updateAll(context) }
            }
        }
    }
}

/**
 * Installs [WidgetUpdates] when the app's process starts, before any activity
 * makes the store, as androidx.startup's provider does; it serves no data.
 */
class WidgetUpdatesStarter : ContentProvider() {
    override fun onCreate(): Boolean {
        context?.let(WidgetUpdates::install)
        return true
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
