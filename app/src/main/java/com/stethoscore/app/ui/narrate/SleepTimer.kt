package com.stethoscore.app.ui.narrate

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.stethoscore.app.audio.SleepChoice
import com.stethoscore.app.audio.SleepCountdown

/** What the sleep timer stops: the recording, or the voice reading the lecture (iOS SleepTarget). */
interface SleepTarget {
    val sleepPlaying: Boolean
    /** Where the section playing now ends, in the player's own terms; null when it cannot say. */
    fun sleepSectionEnd(): Double?
    /** Listening seconds until [end]; zero or less once there. */
    fun sleepSecondsLeft(until: Double): Double
    fun sleepFade(level: Float)
    /** Pause, and put the volume back for when the student wakes. */
    fun sleepFinish()
    /** Set by the timer: called when the student moves the place by hand. */
    var sleepMoved: (() -> Unit)?
}

/**
 * The sleep timer (ios/RedPen/Shared/Voice/SleepTimer.swift, fed0105):
 * counts down the listening time left, fades the last ten seconds out and
 * pauses. It checks once a second (ten times a second through the fade) on
 * the main looper, never a frame loop; a check measures the time since the
 * last one, so a late one does not stretch the timer. The countdown itself is
 * SleepCountdown, which the JUnit tests cover.
 */
class SleepTimer {
    /** What the chip shows: changed only when the label or the choice changes. */
    var countdown by mutableStateOf<SleepCountdown?>(null)
        private set
    private var live: SleepCountdown? = null
    private var target: SleepTarget? = null
    private var mark: Double? = null
    private var lastCheck = 0L
    private val handler = Handler(Looper.getMainLooper())
    private val tick = Runnable { check() }

    val running: Boolean get() = live != null

    /** The player the timer stops. A new one cancels the timer. */
    fun attach(newTarget: SleepTarget?) {
        if (newTarget === target) return
        cancel()
        target?.sleepMoved = null
        target = newTarget
        newTarget?.sleepMoved = { rearm() }
    }

    fun start(choice: SleepChoice) {
        val target = target ?: return
        cancel()
        var left: Double? = null
        if (choice == SleepChoice.EndOfSection) {
            val end = target.sleepSectionEnd() ?: return
            mark = end
            left = target.sleepSecondsLeft(end)
        }
        val made = SleepCountdown.of(choice, left) ?: return
        live = made
        countdown = made.copy()
        lastCheck = SystemClock.elapsedRealtime()
        schedule()
    }

    /** Off: the volume comes straight back. */
    fun cancel() {
        handler.removeCallbacks(tick)
        mark = null
        if (live != null) target?.sleepFade(1f)
        live = null
        if (countdown != null) countdown = null
    }

    private fun schedule() {
        val wait = live?.nextCheck ?: return
        handler.postDelayed(tick, (wait * 1000).toLong().coerceAtLeast(1))
    }

    private fun check() {
        val now = live
        val target = target
        if (now == null || target == null) { cancel(); return }
        val at = SystemClock.elapsedRealtime()
        val heard = (at - lastCheck) / 1000.0
        lastCheck = at
        val mark = mark
        if (mark != null) now.follow(target.sleepSecondsLeft(mark))
        else if (target.sleepPlaying) now.advance(heard)
        if (now.isDone) { finish(); return }
        show(now)
        if (target.sleepPlaying) target.sleepFade(now.volume)
        schedule()
    }

    private fun finish() {
        handler.removeCallbacks(tick)
        mark = null
        live = null
        countdown = null
        target?.sleepFinish()
    }

    private fun show(now: SleepCountdown) {
        val shown = countdown
        if (shown != null && now.label == shown.label && now.choice == shown.choice) return
        countdown = now.copy()
    }

    /** The student moved: "the end of this section" is now the end of the one they moved to. */
    private fun rearm() {
        val now = live ?: return
        val target = target ?: return
        if (now.choice != SleepChoice.EndOfSection) return
        val end = target.sleepSectionEnd() ?: return
        mark = end
        now.follow(target.sleepSecondsLeft(end))
        show(now)
        target.sleepFade(now.volume)
    }
}
