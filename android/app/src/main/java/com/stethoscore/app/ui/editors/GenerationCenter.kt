package com.stethoscore.app.ui.editors

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlin.coroutines.CoroutineContext
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.llm.GenerationRules
import com.stethoscore.app.ui.vitals.EcgStrip
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.wardColor
import java.util.UUID
import kotlin.math.roundToLong

// A port of ios/RedPen/Shared/GenerationCenter.swift: the one piece of
// generation running right now, shown as a floating card with a strip for how
// much is done and a Cancel that really stops it. Every generator reports here
// instead of drawing its own spinner. Android has no continued-processing task
// or finished notification yet, so BackgroundWork, AppNotifications and
// stopAtExpiry are not ported.
//
// It lives for the process, as iOS's shared one does: a rotation recreates
// MainActivity, and the work, its card, its status line and the set it makes
// carry on into the new one (the work runs in [GenerationCenter.scope], not a
// screen's; its screen is known by an owner id kept across the recreation).
// So does Android destroying the activity in the background: only the student
// leaving (the activity finishing, or the screen closing in a live activity)
// stops a run.

/** The one generation running, and its card's state (iOS GenerationCenter). */
object GenerationCenter {

    data class Job(
        val id: UUID,
        val title: String,
        val done: Int,
        val total: Int,
        val phase: String? = null,
        /** When it began, in epoch milliseconds, for the time-left estimate. */
        val started: Long = System.currentTimeMillis(),
    ) {
        val fraction: Double get() = if (total > 0) minOf(1.0, done.toDouble() / total) else 0.0

        /** Seconds left at the pace so far; null until there is a pace to go on. */
        fun secondsLeft(now: Long = System.currentTimeMillis()): Int? {
            if (done <= 0 || total <= done) return null
            val elapsed = (now - started) / 1000.0
            if (elapsed < 5) return null
            val perItem = elapsed / done
            return (perItem * (total - done)).roundToLong().toInt()
        }
    }

    var job: Job? by mutableStateOf(null)
        private set

    /** Where generations run: the process's, so a recreated activity does not stop them (as CloudJobCollector's). */
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /**
     * Starts a run's work in [scope], so no screen's end stops it, but on the
     * dispatcher of [ui], the screen's composition: the main thread's, which
     * outlives any one activity, or under a test the clock the test drives.
     * Plain Dispatchers.Main posts to a looper the test clock never moves, so
     * the work's waits there never ended.
     */
    fun launch(ui: CoroutineContext, block: suspend CoroutineScope.() -> Unit): kotlinx.coroutines.Job =
        scope.launch(ui.minusKey(kotlinx.coroutines.Job), block = block)

    /** Each owner's line under Make once nothing is running: "Done …", "Cancelled.", a refusal or an error. */
    private val notes = mutableStateMapOf<UUID, String>()
    /** What a finished generation made, waiting for its owner's screen to take it. */
    private val results = mutableStateMapOf<UUID, Any>()
    /** What an owner's screen has open from a finished run, until it is saved or discarded. */
    private val held = mutableStateMapOf<UUID, Any>()

    /** Whether the job running was started by [owner]. */
    fun runs(owner: UUID): Boolean = job != null && this.owner == owner

    fun note(owner: UUID): String? = notes[owner]

    fun note(owner: UUID, text: String?) { if (text == null) notes.remove(owner) else notes[owner] = text }

    fun result(owner: UUID): Any? = results[owner]

    fun deliver(owner: UUID, value: Any) { results[owner] = value }

    /** The result is in its screen's hands. */
    fun take(owner: UUID) { results.remove(owner) }

    /** What [owner]'s screen holds open (New set's questions in the quiz), kept across a recreated activity. */
    fun held(owner: UUID): Any? = held[owner]

    fun hold(owner: UUID, value: Any) { held[owner] = value }

    /** The held set was saved and closed, or discarded. */
    fun release(owner: UUID) { held.remove(owner) }

    /** Its screen is gone for good: its note, any result and what it held go with it. */
    fun forget(owner: UUID) { notes.remove(owner); results.remove(owner); held.remove(owner) }
    private var stop: (() -> Unit)? = null
    /** The screen that started the running job (New set), if any. */
    private var owner: UUID? = null

    /** Why a new generation cannot start now, in words for the student; null when nothing is running. */
    val busy: String? get() = (GenerationRules.admit(job?.title) as? GenerationRules.Admission.Refuse)?.why

    /**
     * Starts showing a job, or refuses with null while another one runs. The
     * one running is never stopped to make room. [onCancel] must cancel the
     * work and put the screen that started it back to idle; [owner] is the
     * screen it is started under ([LocalGenerationOwner]), which stops it when it closes.
     */
    @Synchronized fun begin(title: String, total: Int, owner: UUID? = null, onCancel: () -> Unit): UUID? {
        if (GenerationRules.admit(job?.title) != GenerationRules.Admission.Start) return null
        val id = UUID.randomUUID()
        job = Job(id, title, 0, total)
        stop = onCancel
        this.owner = owner
        return id
    }

    /** Progress from a generator's callback. Ignored once the job has finished or been cancelled, so a late report cannot bring the card back. */
    @Synchronized fun update(id: UUID, done: Int, total: Int, phase: String? = null) {
        val current = job ?: return
        if (current.id != id) return
        job = current.copy(done = done, total = total, phase = phase)
    }

    /** The job is over. False when it was no longer the current one (cancelled, or another began), so its ending leaves the screen alone (GenerationRules.endingClears). */
    @Synchronized fun end(id: UUID): Boolean {
        if (!GenerationRules.endingClears(id, job?.id)) return false
        clear()
        return true
    }

    /** The card's Cancel: the work stops and its screen goes back to idle. */
    fun cancel() {
        val stopping = synchronized(this) { stop.also { clear() } }
        stopping?.invoke()
    }

    /** A screen is closing (New set): what it started stops, as with Cancel, and nothing else does (GenerationRules.closingStops). */
    fun cancel(startedBy: UUID) {
        if (job == null || !GenerationRules.closingStops(owner, startedBy)) return
        cancel()
    }

    private fun clear() {
        job = null
        stop = null
        owner = null
    }
}

/** The screen that generations started under here belong to: New set gives everything in it one, so closing it stops only what it started (iOS generationOwner). */
val LocalGenerationOwner = staticCompositionLocalOf<UUID?> { null }

/**
 * A screen's owner id, kept across a recreated activity (a rotation). When the
 * screen goes for good, what it started stops (iOS NewSetView's onDisappear)
 * and its note goes; when the activity is only being recreated or destroyed in
 * the background ([changing]), the work carries on into the new one.
 */
@Composable fun rememberGenerationOwner(changing: () -> Boolean = activityChanging()): UUID {
    val owner = UUID.fromString(rememberSaveable { UUID.randomUUID().toString() })
    val isChanging by rememberUpdatedState(changing)
    DisposableEffect(owner) {
        onDispose {
            if (!isChanging()) {
                GenerationCenter.cancel(startedBy = owner)
                GenerationCenter.forget(owner)
            }
        }
    }
    return owner
}

/** Whether this screen's activity will come back (recreated, or destroyed in the background) rather than closed. */
@Composable private fun activityChanging(): () -> Boolean {
    val activity = LocalContext.current.findActivity()
    return {
        activity != null && GenerationLife.goesOn(
            finishing = activity.isFinishing,
            changingConfigurations = activity.isChangingConfigurations,
            destroyed = activity.isDestroyed ||
                (activity as? LifecycleOwner)?.lifecycle?.currentState == Lifecycle.State.DESTROYED,
        )
    }
}

/** When a run outlives the screen that started it. */
internal object GenerationLife {
    /**
     * A screen disposed as its activity goes: the run goes on unless the
     * activity is finishing (the student left). A screen disposed while its
     * activity stays alive was closed, so its run stops.
     */
    fun goesOn(finishing: Boolean, changingConfigurations: Boolean, destroyed: Boolean): Boolean =
        !finishing && (changingConfigurations || destroyed)
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** The card's words (iOS GenerationLines and GenerationProgress). */
internal object GenerationWords {
    /** "8 of 20 · 12 left", or "Starting…" before there is a total. */
    fun counts(job: GenerationCenter.Job): String {
        if (job.total <= 0) return "Starting…"
        val left = maxOf(0, job.total - job.done)
        return "${job.done} of ${job.total} · $left left"
    }

    /** "~2 min left", "<1 min left"; null until there is a pace to go on. */
    fun timeLeft(job: GenerationCenter.Job, now: Long = System.currentTimeMillis()): String? {
        val seconds = job.secondsLeft(now) ?: return null
        if (seconds < 60) return "<1 min left"
        val minutes = (seconds + 30) / 60
        return "~$minutes min left"
    }

    fun percent(fraction: Double): Int = Math.round(fraction * 100).toInt()

    fun shown(fraction: Double): String = "${percent(fraction)}%"

    fun spoken(fraction: Double): String = "${percent(fraction)} percent done"
}

/**
 * The floating card at the bottom, where the thumb is: drawn only while a job
 * runs. New set shows it in place of its dock's slab (iOS NewSetDock, GenerationHUD).
 */
@Composable fun GenerationHUD(modifier: Modifier = Modifier) {
    val job = GenerationCenter.job ?: return
    Box(modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 8.dp), contentAlignment = Alignment.Center) {
        GenerationCard(job, { GenerationCenter.cancel() }, Modifier.widthIn(max = 560.dp).fillMaxWidth())
    }
}

/** The ECG loader, what is being written, how many of how many and about how long is left, the strip, and Cancel. */
@Composable internal fun GenerationCard(job: GenerationCenter.Job, cancel: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.wardRaised(WardRadius.card, WardLift.high).padding(WardSpace.gutter.wardDp),
        verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp), verticalAlignment = Alignment.CenterVertically) {
            EcgLoader()
            GenerationLines(job, Modifier.weight(1f).padding(end = 8.dp))
            WardTextButton("Cancel", cancel, Modifier.testTag("cancelGeneration"), kind = WardButtonKind.compact, fills = false)
        }
        val spoken = GenerationWords.spoken(job.fraction)
        Row(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = spoken },
            horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { EcgStrip(job.fraction) }
            Text(GenerationWords.shown(job.fraction), style = WardTextStyle.caption.textStyle(WardWeight.semibold, mono = true),
                color = wardColor(WardToken.ink))
        }
    }
}

@Composable private fun GenerationLines(job: GenerationCenter.Job, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(job.title, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink),
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        val small = WardTextStyle.caption.textStyle(mono = true)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(GenerationWords.counts(job), style = small, color = wardColor(WardToken.inkSecondary))
            GenerationWords.timeLeft(job)?.let { Text("· $it", style = small, color = wardColor(WardToken.inkSecondary)) }
        }
        job.phase?.let {
            Text(it, style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
