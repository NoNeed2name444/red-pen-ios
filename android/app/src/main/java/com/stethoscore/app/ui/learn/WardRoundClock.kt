package com.stethoscore.app.ui.learn

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.stethoscore.app.data.LearnDefaults
import com.stethoscore.app.data.StudyMinutes
import com.stethoscore.app.data.WardRound
import com.stethoscore.app.data.WardRoundPlan
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// A port of ios/RedPen/Shared/Learn/WardRoundClock.swift: runs the one ward
// round (data/WardRound.kt), keeps it across a relaunch, and acts on what its
// clock says.
//
// There is no ticking timer here. The clock is dates; this sleeps until the
// running phase is due to end, wakes once, and moves the round on - and does
// the same whenever the app comes back to the front. The screens showing a
// round redraw themselves once a second while they are on screen.
//
// What the round does to the rest of the app:
// - each round's focus minutes go into StudyMinutes, so they count for the
//   streak;
// - everything studied while a round's clock runs is counted on it, from
//   StudyStore.onStudied;
// - in front, the chip says what just ended (`notice`).
// Not on Android yet: the notifications for an end while the app is away,
// Health's mindful minutes and the Live Activity.

internal object WardRoundClock {
    /** The running round, JSON. */
    const val stateKey = "wardRound.state"
    /** The last choices on the tile. */
    const val focusKey = "wardRound.focusMinutes"
    const val breakKey = "wardRound.breakMinutes"

    /** The round under way, or null. */
    var round by mutableStateOf<WardRound?>(null)
        private set
    /** A short line when a phase ends in front of the student; the chip shows it for a few seconds. */
    var notice by mutableStateOf<String?>(null)
        private set
    /** Whether the round's panel is open over the app (WardRoundOverlayModel.expanded). */
    var expanded by mutableStateOf(false)

    /** Whether the app is in front; a phase that ends while it is away ends quietly. */
    var inFront: Boolean = true

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var wake: Job? = null
    private var noticeClear: Job? = null
    private var restored = false

    private val defaults: LearnDefaults get() = LearnDefaults.shared
    private fun now(): Long = System.currentTimeMillis()

    /** Once, when the library is on screen: picks up a round left running. */
    fun restore() {
        if (restored) return
        restored = true
        val saved = defaults.string(stateKey)?.let(WardRound::fromJson)
        if (saved == null || saved.phase == WardRound.Phase.Done) {
            defaults.set(stateKey, null)
            return
        }
        round = saved
        tick()
        changed()
    }

    // MARK: the student's moves

    fun start(plan: WardRoundPlan) {
        defaults.setInt(focusKey, plan.focusMinutes)
        defaults.setInt(breakKey, plan.breakMinutes)
        round = WardRound.begin(plan, now())
        notice = null
        changed()
    }

    fun pause() = edit { it.pause(now()) }

    fun resume() = edit { it.resume(now()) }

    fun startNext() = edit { it.startNext(now()) }

    /** Ends the running round early (its time still counts) or skips a break. */
    fun skip() {
        val current = round ?: return
        val step = current.skip(now())
        round = step.round
        handle(step.events, quietly = true)
        changed()
    }

    /** Stops the whole ward round; a round under way counts for its time. */
    fun stop() {
        val current = round ?: return
        val step = current.stop(now())
        handle(step.events, quietly = true)
        close()
    }

    /** Puts a finished (or stopped) ward round away. */
    fun close() {
        round = null
        notice = null
        expanded = false
        changed()
    }

    private fun edit(change: (WardRound) -> WardRound) {
        val current = round ?: return
        round = change(current)
        changed()
    }

    // MARK: the clock

    /** Moves the round on to now, for whatever has ended since it last looked. */
    fun tick() {
        val current = round ?: return
        val step = current.advance(now())
        if (step.events.isEmpty()) {
            arm()
            return
        }
        round = step.round
        handle(step.events, quietly = !inFront)
        changed()
    }

    /** Back in front: whatever ended while away. */
    fun returned() {
        inFront = true
        if (round != null) tick()
    }

    /** Something was studied: counted on the round while its focus clock runs. */
    fun studied(count: Int) {
        val current = round ?: return
        if (current.phase != WardRound.Phase.Focus || current.isPaused) return
        round = current.noteStudied(count)
        save()
    }

    /** What ended: minutes to the log, and a line in front. */
    private fun handle(events: List<WardRound.Event>, quietly: Boolean) {
        for (event in events) {
            if (event is WardRound.Event.FocusEnded) StudyMinutes.record((event.seconds / 60).toInt(), event.end)
        }
        val current = round
        if (quietly || current == null || events.isEmpty()) return
        say(line(current))
    }

    /** "Round 2 of 4 done — take 5 minutes". */
    fun line(round: WardRound): String = when (round.phase) {
        WardRound.Phase.Rest -> round.roundWords + " done — take ${round.plan.breakMinutes} minutes"
        WardRound.Phase.Ready -> "Break over — round ${round.round + 1} when you’re ready"
        WardRound.Phase.Done -> "Ward round done — ${round.focusMinutes} minutes"
        WardRound.Phase.Focus -> round.roundWords
    }

    private fun say(line: String) {
        notice = line
        noticeClear?.cancel()
        noticeClear = scope.launch {
            delay(8_000)
            notice = null
        }
    }

    /** After every change: saved, and the next wake. */
    private fun changed() {
        save()
        arm()
        if (round == null) expanded = false
    }

    private fun save() {
        defaults.set(stateKey, round?.toJson())
    }

    /** One sleep, until the running phase is due to end. */
    private fun arm() {
        wake?.cancel()
        val current = round ?: return
        if (!current.ticks) return
        val wait = maxOf(50L, current.phaseEnds - now())
        wake = scope.launch {
            delay(wait)
            tick()
        }
    }
}
