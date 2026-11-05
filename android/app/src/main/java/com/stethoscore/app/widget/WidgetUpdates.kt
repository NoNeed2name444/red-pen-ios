package com.stethoscore.app.widget

import android.app.Activity
import android.app.Application
import android.content.ComponentCallbacks
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import androidx.glance.appwidget.updateAll
import com.stethoscore.app.data.GlanceDigest
import com.stethoscore.app.data.StudyStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Runs the last of a burst of calls once, [delayMs] after the calls stop (a
 * review session writes the digest after each card). Plain Kotlin over a
 * [Debouncer.Timer], so it is tested on the JVM with a hand-driven one (WidgetUpdatesTest).
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
 * The font scale and display density the widgets are drawn at. Each face is
 * fitted in the dp its sp come to at the font scale (WidgetFit's TextScale),
 * so a face drawn at one scale can be cut or squeezed at another.
 */
data class DrawnScale(val fontScale: Float, val densityDpi: Int) {
    companion object {
        fun of(config: Configuration): DrawnScale = DrawnScale(config.fontScale, config.densityDpi)
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
    private val executorTimer = Debouncer.Timer { delay, action ->
        val future: ScheduledFuture<*> = executor.schedule({ runCatching(action) }, delay, TimeUnit.MILLISECONDS)
        ({ future.cancel(false) })
    }
    /** Where the debounces schedule their work: the background thread; a test hands in its own. */
    @Volatile internal var timer: Debouncer.Timer = executorTimer
    private val viaTimer = Debouncer.Timer { delay, action -> timer.schedule(delay, action) }
    /** The widgets' redraw after a new digest, and the on-time redraw queued for it (WidgetRefresh). */
    private val updates = Debouncer(delayMs, viaTimer)
    /**
     * The foreground's fresh digest, apart from [updates]: sharing one would let
     * a republish soon after a save cancel that save's redraw, and the
     * republish then finds the digest unchanged and tells no one.
     */
    private val republishes = Debouncer(delayMs, viaTimer)
    /** The redraw after the font size or the display size changes, apart from the others for the same reason. */
    private val rescales = Debouncer(delayMs, viaTimer)
    /** What an app start catches up on (catchUp). */
    private val starts = Debouncer(delayMs, viaTimer)

    /** Counts the digests the widgets were told of; a drawn widget reads the file again when it moves. */
    val version = MutableStateFlow(0L)

    /**
     * Every store's new digest updates the widgets and queues their next
     * redraw on time (StudyStore.onAnyGlanceWritten); ProcessStore installs it
     * before it makes the store. The first call in the process also listens
     * for a new font or display size and for the app's starts (listen).
     */
    fun install(context: Context) {
        val app = context.applicationContext
        StudyStore.onAnyGlanceWritten = hook { digest ->
            updateNow(app)
            WidgetRefresh.queue(app, digest.nextDue)
        }
        listen(app)
    }

    /** The store's hook: each new digest runs [update] with the last of them once the digests stop coming. */
    internal fun hook(update: (GlanceDigest) -> Unit): (GlanceDigest) -> Unit = { digest -> updates.submit { update(digest) } }

    /**
     * The app came back to the foreground (iOS AppIntentsRouting.swift:241-250):
     * the digest is worked out again off the main thread, debounced on its own
     * (a rotation or a fold starts the activity again); it is written, and the
     * widgets told, only if it changed.
     */
    fun republish(store: StudyStore) {
        republishes.submit { store.publishGlance() }
    }

    /**
     * Redraws every placed widget from the file on disk; no widget placed is a
     * no-op. Only this redraw of all three records the scale they are drawn at
     * (drawnScale), once each was asked to: one widget's own update (its
     * period, or being placed) redraws that one alone, so it records nothing
     * and catchUp still redraws the others.
     */
    fun updateNow(context: Context) {
        val scale = DrawnScale.of(context.applicationContext.resources.configuration)
        version.value += 1
        val all = runBlocking {
            listOf(DueCardsWidget(), ExamCountdownWidget(), DoneTodayWidget())
                .map { widget -> runCatching { widget.updateAll(context) }.isSuccess }
                .all { it }
        }
        if (all) record(context, scale)
    }

    // MARK: - The font and display size

    @Volatile private var listening: Context? = null

    /**
     * Once for the application: a change of font scale or density redraws the
     * widgets while the process runs, and each start of an app screen (its
     * onStart) catches up on one made while it did not. A process that is not
     * running hears of neither; its widgets wait for the next periodic update
     * (widget_*.xml) or the next start.
     */
    @Synchronized private fun listen(app: Context) {
        if (listening === app) return
        listening = app
        app.registerComponentCallbacks(ScaleWatch(app))
        (app as? Application)?.registerActivityLifecycleCallbacks(StartWatch(app))
    }

    /** Redraws on a new font scale or density only; a rotation, the night mode or the language leave the fit as it is. */
    private class ScaleWatch(private val app: Context) : ComponentCallbacks {
        private var seen = DrawnScale.of(app.resources.configuration)

        override fun onConfigurationChanged(newConfig: Configuration) {
            val now = DrawnScale.of(newConfig)
            if (now == seen) return
            seen = now
            rescales.submit { updateNow(app) }
        }

        @Suppress("OVERRIDE_DEPRECATION")
        override fun onLowMemory() = Unit
    }

    /** An app screen's onStart: catchUp, off the main thread. */
    private class StartWatch(private val app: Context) : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(activity: Activity) = starts.submit { catchUp(app) }
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
        override fun onActivityResumed(activity: Activity) = Unit
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivityStopped(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) = Unit
    }

    /**
     * The app's screen started: the widgets are all redrawn unless all three
     * were last redrawn together at this font scale and density (a widget's
     * own update since does not count, updateNow), and from Android 15 the picker's
     * previews are published again where they are out of date (WidgetPreviews).
     */
    internal fun catchUp(context: Context) {
        if (needsRedraw(drawnScale(context), DrawnScale.of(context.resources.configuration))) updateNow(context)
        // a refused or failed publish leaves the last previews, and the redraw above stands
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) runCatching { WidgetPreviews.publishIfStale(context) }
    }

    /** A redraw is due where the widgets were drawn at another scale, or the app has no record of one. */
    fun needsRedraw(drawn: DrawnScale?, now: DrawnScale): Boolean = drawn != now

    private const val fontScaleKey = "drawnFontScale"
    private const val densityKey = "drawnDensityDpi"

    internal fun prefs(context: Context) = context.applicationContext.getSharedPreferences("widgets", Context.MODE_PRIVATE)

    /** The scale all three widgets were last redrawn at together ([updateNow]), or null before the first. */
    fun drawnScale(context: Context): DrawnScale? {
        val prefs = prefs(context)
        if (!prefs.contains(fontScaleKey)) return null
        return DrawnScale(prefs.getFloat(fontScaleKey, 1f), prefs.getInt(densityKey, 0))
    }

    /** [updateNow]'s record; nothing else writes it. */
    private fun record(context: Context, scale: DrawnScale) {
        if (drawnScale(context) == scale) return
        prefs(context).edit().putFloat(fontScaleKey, scale.fontScale).putInt(densityKey, scale.densityDpi).apply()
    }
}
