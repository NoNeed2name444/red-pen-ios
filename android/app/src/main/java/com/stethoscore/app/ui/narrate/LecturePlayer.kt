package com.stethoscore.app.ui.narrate

import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.stethoscore.app.audio.AudioChapter
import com.stethoscore.app.audio.AudioChapters
import com.stethoscore.app.audio.AudioRate
import com.stethoscore.app.audio.TranscriptWord
import com.stethoscore.app.audio.WordTiming
import java.io.File

/** The position, fifteen times a second; read only by the scrub bar (iOS LectureClock). */
class LectureClock { var time by mutableDoubleStateOf(0.0) }

/**
 * Playing a lecture's recording (ios/RedPen/Shared/LecturePlayer.swift,
 * fed0105), with MediaPlayer: the audio is the clock, so the word lit is the
 * one the recogniser's timestamps put at the audio's position, published only
 * when it changes. Seeks are exact (SEEK_CLOSEST), so a tapped line starts on
 * its first word. The speed is applied only while playing: MediaPlayer starts
 * playing when a speed is set on a paused player.
 */
class LecturePlayer : SleepTarget {
    val clock = LectureClock()
    val time: Double get() = clock.time
    var duration by mutableDoubleStateOf(0.0)
        private set
    var playing by mutableStateOf(false)
        private set
    var failure by mutableStateOf<String?>(null)
        private set
    var spot by mutableStateOf<NarrateSpot?>(null)
        private set
    var rate by mutableDoubleStateOf(1.0)
        private set
    var section by mutableStateOf<Int?>(null)
        private set
    var chapters by mutableStateOf<List<AudioChapter>>(emptyList())
        private set
    var hasAudio by mutableStateOf(false)
        private set
    override var sleepMoved: (() -> Unit)? = null

    private var player: MediaPlayer? = null
    private var prepared = false
    private var playWhenPrepared = false
    private var timeline: List<TranscriptWord> = emptyList()
    private val main = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            syncTime()
            if (playing) main.postDelayed(this, 1000L / 15)
        }
    }

    fun setTimeline(words: List<TranscriptWord>) {
        timeline = words
        publishSpot(time)
    }

    fun useChapters(made: List<AudioChapter>) {
        chapters = made
        section = null
        publishSection(time)
    }

    fun load(file: File) {
        stop()
        failure = null
        val made = MediaPlayer()
        try {
            made.setDataSource(file.path)
            made.setOnPreparedListener { p ->
                if (player !== p) return@setOnPreparedListener
                prepared = true
                duration = maxOf(0.0, p.duration / 1000.0)
                if (playWhenPrepared) { playWhenPrepared = false; play() }
            }
            made.setOnCompletionListener { p -> if (player === p) ended() }
            made.setOnErrorListener { p, _, _ -> if (player === p) broke(); true }
            made.prepareAsync()
        } catch (e: Exception) {
            made.release()
            failure = "This recording can't be played."
            return
        }
        player = made
        hasAudio = true
    }

    private fun broke() {
        stop()
        failure = "This recording can't be played."
    }

    /** Play at the speed chosen. At the end, Play starts over. */
    fun play() {
        val player = player ?: return
        if (!prepared) { playWhenPrepared = true; return }
        if (duration > 0 && time >= duration - 0.05) moveTo(0.0)
        runCatching {
            player.start()
            player.playbackParams = player.playbackParams.setSpeed(rate.toFloat())
        }
        playing = true
        main.removeCallbacks(tick)
        main.post(tick)
    }

    fun pause() {
        playWhenPrepared = false
        runCatching { if (prepared) player?.pause() }
        playing = false
        main.removeCallbacks(tick)
        syncTime()
    }

    fun toggle() { if (playing) pause() else play() }

    /** A new speed takes effect at once, and is what Play uses next. */
    fun chooseRate(newRate: Double) {
        rate = AudioRate.snapped(newRate)
        val player = player ?: return
        if (playing) runCatching { player.playbackParams = player.playbackParams.setSpeed(rate.toFloat()) }
    }

    /** Jump to a moment: a tapped line, a scrub, a skip, a section. */
    fun seek(to: Double) {
        if (player == null) return
        val end = if (duration > 0) duration else maxOf(0.0, to)
        moveTo(to.coerceIn(0.0, end))
        sleepMoved?.invoke()
    }

    /** Back fifteen, forward thirty, or any other step. */
    fun skip(by: Double) = seek(time + by)

    // MARK: sections

    val hasSections: Boolean get() = chapters.size >= 2

    fun nextSection() {
        val next = AudioChapters.next(section, chapters) ?: return
        val start = chapters[next].start ?: return
        seek(start)
    }

    /** Back to this section's start, or to the one before when it has only just begun, as Back does on any player. */
    fun previousSection() {
        val back = AudioChapters.previousFromTime(time, chapters) ?: return
        val start = chapters[back].start ?: return
        seek(start)
    }

    fun jumpToSection(i: Int) {
        if (i !in chapters.indices) return
        val start = chapters[i].start ?: return
        seek(start)
    }

    fun stop() {
        main.removeCallbacks(tick)
        player?.let { p -> runCatching { p.reset() }; p.release() }
        player = null
        hasAudio = false
        prepared = false
        playWhenPrepared = false
        playing = false
        clock.time = 0.0
        duration = 0.0
        spot = null
        section = null
    }

    private fun moveTo(target: Double) {
        val player = player ?: return
        if (prepared) runCatching { player.seekTo((target * 1000).toLong(), MediaPlayer.SEEK_CLOSEST) }
        // the clock shows the new place at once, not when the seek lands
        clock.time = target
        publishSpot(target)
        publishSection(target)
    }

    private fun syncTime() {
        val player = player ?: return
        if (!prepared) return
        val now = runCatching { player.currentPosition / 1000.0 }.getOrNull() ?: return
        clock.time = now
        publishSpot(now)
        publishSection(now)
    }

    private fun publishSpot(t: Double) {
        val word = WordTiming.word(t, timeline)
        val next = word?.let { NarrateSpot(it.segment, it.index) }
        if (next != spot) spot = next
    }

    private fun publishSection(t: Double) {
        val now = if (hasSections) AudioChapters.indexAtTime(t, chapters) else null
        if (now != section) section = now
    }

    private fun ended() {
        playing = false
        main.removeCallbacks(tick)
        // park on the end rather than snapping to zero, so the last line stays lit when the lecture finishes
        clock.time = duration
        publishSpot(duration)
    }

    // MARK: the sleep timer counts in the recording's own clock

    override val sleepPlaying: Boolean get() = playing

    override fun sleepSectionEnd(): Double? {
        if (!hasAudio || duration <= 0) return null
        return AudioChapters.end(time, chapters, duration)
    }

    override fun sleepSecondsLeft(until: Double): Double = (until - time) / maxOf(0.25, rate)

    /** The player's own volume, not the phone's: the student's volume is where they left it when they wake. */
    override fun sleepFade(level: Float) { runCatching { player?.setVolume(level, level) } }

    override fun sleepFinish() {
        pause()
        runCatching { player?.setVolume(1f, 1f) }
    }
}
