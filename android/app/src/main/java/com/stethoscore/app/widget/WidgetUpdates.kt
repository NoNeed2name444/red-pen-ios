package com.stethoscore.app.widget

import android.content.Context
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

    /** Every store's new digest updates the widgets (StudyStore.onAnyGlanceWritten); ProcessStore installs it before it makes the store. */
    fun install(context: Context) {
        val app = context.applicationContext
        StudyStore.onAnyGlanceWritten = { debouncer.submit { updateNow(app) } }
    }

    /**
     * The app came back to the foreground (iOS AppIntentsRouting.swift:241-250):
     * the digest is worked out again off the main thread, through the same
     * debounce; it is written, and the widgets told, only if it changed.
     */
    fun republish(store: StudyStore) {
        debouncer.submit { store.publishGlance() }
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
