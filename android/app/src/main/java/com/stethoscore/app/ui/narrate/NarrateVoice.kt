package com.stethoscore.app.ui.narrate

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.stethoscore.app.audio.AudioChapter
import com.stethoscore.app.audio.AudioChapters
import com.stethoscore.app.audio.AudioRate
import com.stethoscore.app.audio.NarratePlan
import java.util.Locale

/** Where the voice is: the line, and the word in it once one is being said. */
data class NarrateSpot(val line: Int, val word: Int?)

/**
 * Reading a typed lecture aloud, word by word
 * (ios/RedPen/Shared/Voice/NarrateVoice.swift, fed0105), with the phone's own
 * voice: one TextToSpeech for the whole lecture, three lines queued ahead so
 * there is no pause between them, and the word lit is the one the engine says
 * it is about to speak (onRangeStart).
 *
 * iOS's natural cloud voice (Pro, online) is not here: there is no paid voice
 * on Android, so the phone reads every line, which is what iOS does whenever
 * the cloud is not set up. TextToSpeech cannot pause, so Pause stops in place
 * and Play starts again from the word it was on.
 */
class NarrateVoice(context: Context) : SleepTarget {
    var spot by mutableStateOf(NarrateSpot(0, null))
        private set
    var playing by mutableStateOf(false)
        private set
    var finished by mutableStateOf(false)
        private set
    /** Playing, but the voice is not ready yet. */
    var waiting by mutableStateOf(false)
        private set
    var speed by mutableStateOf(1.0)
        private set
    var chapters by mutableStateOf<List<AudioChapter>>(emptyList())
        private set
    override var sleepMoved: (() -> Unit)? = null

    private class PhoneLine(val line: Int, val first: Int, val text: String)

    private val main = Handler(Looper.getMainLooper())
    private var lines: List<String> = emptyList()
    private var langs: List<String> = emptyList()
    private var paused = false
    private var session = 0
    private var fade = 1f
    private var ready = false
    private var broken = false
    private var startWhenReady = false
    private val utterances = LinkedHashMap<String, PhoneLine>()
    private var nextPhoneLine = 0
    private var serial = 0
    private var shutDown = false

    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        main.post { engineReady(status == TextToSpeech.SUCCESS) }
    }

    init {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) { main.post { phoneStarted(utteranceId) } }
            override fun onDone(utteranceId: String?) { main.post { phoneFinished(utteranceId) } }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) { main.post { phoneFinished(utteranceId) } }
            override fun onStop(utteranceId: String?, interrupted: Boolean) { main.post { utterances.remove(utteranceId) } }
            override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                main.post { phoneWillSpeak(utteranceId, start) }
            }
        })
    }

    private fun engineReady(ok: Boolean) {
        if (shutDown) return
        ready = ok
        broken = !ok
        waiting = false
        if (!ok) { playing = false; paused = false; return }
        if (startWhenReady && playing) { startWhenReady = false; startPhone(spot.line, spot.word ?: 0) }
    }

    // MARK: what is read

    /** The lecture to read. Called again after a word is fixed: if it is playing it carries on from the same line with the new words. */
    fun load(newLines: List<String>, newLangs: List<String>) {
        val wasPlaying = playing
        val at = spot.line
        if (wasPlaying || paused) stopOutput()
        paused = false
        lines = newLines
        langs = newLangs
        if (spot.line >= newLines.size) spot = NarrateSpot(0, null)
        if (wasPlaying) play(minOf(at, maxOf(0, newLines.size - 1)))
    }

    // MARK: the controls

    fun play(from: Int) {
        if (lines.isEmpty() || broken) return
        val start = from.coerceIn(0, lines.size - 1)
        stopOutput()
        session += 1
        finished = false
        paused = false
        playing = true
        spot = NarrateSpot(start, null)
        sleepMoved?.invoke()
        if (!ready) { waiting = true; startWhenReady = true; return }
        startPhone(start, 0)
    }

    /** Play: carries on from where Pause stopped, or starts from the line that is lit. */
    fun resume() {
        if (!paused) { play(if (finished) 0 else spot.line); return }
        paused = false
        playing = true
        if (!ready) { waiting = true; startWhenReady = true; return }
        startPhone(spot.line, spot.word ?: 0)
    }

    fun pause() {
        if (!playing) return
        playing = false
        paused = true
        waiting = false
        startWhenReady = false
        stopOutput()
    }

    fun toggle() { if (playing) pause() else resume() }

    /** A tapped line: read from there if reading, otherwise light it and wait. */
    fun jump(to: Int) {
        if (lines.isEmpty()) return
        val target = to.coerceIn(0, lines.size - 1)
        if (playing) { play(target); return }
        stopOutput()
        paused = false
        finished = false
        spot = NarrateSpot(target, null)
        sleepMoved?.invoke()
    }

    // MARK: sections

    fun useChapters(made: List<AudioChapter>) { chapters = made }

    val hasSections: Boolean get() = chapters.size >= 2

    fun nextSection() {
        val here = AudioChapters.indexContainingLine(spot.line, chapters)
        val next = AudioChapters.next(here, chapters) ?: return
        jump(chapters[next].lines.first)
    }

    /** Back to this section's first line, or to the one before from there. */
    fun previousSection() {
        val back = AudioChapters.previousFromLine(spot.line, chapters) ?: return
        jump(chapters[back].lines.first)
    }

    fun jumpToSection(i: Int) {
        if (i !in chapters.indices) return
        jump(chapters[i].lines.first)
    }

    /** A new speed takes effect at once: the voice starts again from the word it was on (a line already begun keeps its rate). */
    fun chooseSpeed(chosen: Double) {
        val newSpeed = AudioRate.snapped(chosen)
        if (newSpeed == speed) return
        speed = newSpeed
        if (playing && ready) startPhone(spot.line, spot.word ?: 0)
    }

    /** Everything off, the place kept: a new transcript is coming. */
    fun stop() {
        session += 1
        startWhenReady = false
        stopOutput()
        playing = false
        paused = false
    }

    /** The screen is going away: the engine goes with it. */
    fun release() {
        stop()
        if (!shutDown) { shutDown = true; runCatching { tts.shutdown() } }
    }

    private fun finish() {
        stopOutput()
        playing = false
        paused = false
        finished = true
        spot = NarrateSpot(maxOf(0, lines.size - 1), null)
    }

    /** Silences the voice without changing what the screen shows. */
    private fun stopOutput() {
        waiting = false
        if (utterances.isNotEmpty()) { utterances.clear(); runCatching { tts.stop() } }
    }

    // MARK: the phone's voice

    private fun startPhone(line: Int, word: Int) {
        stopOutput()
        if (line >= lines.size) { finish(); return }
        speakLine(line, word)
        queuePhoneLines()
        if (utterances.isEmpty()) phoneRanOut()
    }

    /** Three lines queued ahead, so one runs into the next without a pause while a new one is set up. */
    private fun queuePhoneLines() {
        while (utterances.size < 3 && nextPhoneLine < lines.size) speakLine(nextPhoneLine, 0)
    }

    private fun phoneRanOut() {
        if (nextPhoneLine >= lines.size) finish()
    }

    private fun speakLine(line: Int, from: Int) {
        nextPhoneLine = line + 1
        val words = NarratePlan.tokens(lines[line])
        if (from >= words.size) return
        val text = words.drop(from).joinToString(" ")
        val arabic = line < langs.size && langs[line] == "ar"
        runCatching { tts.setLanguage(if (arabic) Locale.forLanguageTag("ar-SA") else Locale.forLanguageTag("en-US")) }
        tts.setSpeechRate(NarratePlan.ttsRate(speed))
        // a line begun while the sleep timer fades starts that much quieter
        val params = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, fade) }
        // never reused, so a late callback from a line already stopped finds nothing
        serial += 1
        val id = "narrate-$serial"
        utterances[id] = PhoneLine(line, from, text)
        if (tts.speak(text, TextToSpeech.QUEUE_ADD, params, id) == TextToSpeech.ERROR) utterances.remove(id)
    }

    private fun phoneStarted(id: String?) {
        val place = utterances[id] ?: return
        if (!playing) return
        val now = NarrateSpot(place.line, place.first)
        if (now != spot) spot = now
    }

    private fun phoneWillSpeak(id: String?, offset: Int) {
        val place = utterances[id] ?: return
        if (!playing) return
        val now = NarrateSpot(place.line, place.first + NarratePlan.wordIndex(offset, place.text))
        if (now != spot) spot = now
    }

    private fun phoneFinished(id: String?) {
        if (utterances.remove(id) == null) return
        queuePhoneLines()
        if (utterances.isEmpty()) phoneRanOut()
    }

    // MARK: the sleep timer: lines, not a clock

    override val sleepPlaying: Boolean get() = playing

    override fun sleepSectionEnd(): Double? {
        if (lines.isEmpty()) return null
        val i = AudioChapters.indexContainingLine(spot.line, chapters)
        if (i == null || !hasSections) return lines.size.toDouble()
        return chapters[i].end.toDouble()
    }

    override fun sleepSecondsLeft(until: Double): Double {
        if (finished) return 0.0
        return AudioChapters.secondsToRead(lines, spot.line, spot.word ?: 0, until.toInt(), speed)
    }

    override fun sleepFade(level: Float) { fade = level }

    override fun sleepFinish() {
        pause()
        fade = 1f
    }
}
