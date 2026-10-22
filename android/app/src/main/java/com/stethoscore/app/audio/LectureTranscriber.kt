package com.stethoscore.app.audio

import com.stethoscore.app.data.NarrateScheduler
import com.stethoscore.app.data.NarrateSegment
import com.stethoscore.app.data.SpokenTiming

// Turning a recording into readable lines (ios/RedPen/Shared/LectureTranscriber.swift
// and Models/NarrateSegment.swift, fed0105): where a line ends, what happens to
// the word times on the way through, and what the player asks for.
//
// The recogniser itself is not on Android. iOS listens with Apple's on-device
// Speech framework, or Gemini; Android's SpeechRecognizer hears only the
// microphone, and no transcriber is set up on this phone, so the importer
// says so (Failure.cloudNotSetUp, Failure.deviceNotSetUp) - the same path the other batches take where
// iOS has a writer Android lacks.

/** What a recorded lecture is spoken in. Mixed is the default: these are Egyptian lectures that carry English terms. */
enum class LectureLanguage(val rawValue: String) {
    /** Egyptian Arabic with English medical terms inside the same sentence. */
    mixed("mixed"),
    /** English throughout. */
    english("english");

    /** The on-device recogniser for it. */
    val locale: String get() = if (this == english) "en-US" else "ar-EG"

    companion object {
        fun of(raw: String?): LectureLanguage? = values().firstOrNull { it.rawValue == raw }
    }
}

object LectureTranscriber {
    /** One word as a recogniser reports it. */
    data class SpokenWord(val text: String, val start: Double, val duration: Double) {
        val end: Double get() = start + duration
    }

    data class Line(val text: String, val start: Double, val end: Double, val words: List<SpokenWord>, val model: String? = null)

    /** Why a recording could not be made into a transcript. */
    object Failure {
        /** iOS's Gemini (Pro): not on Android. */
        const val cloudNotSetUp = "Gemini transcription is not set up on this phone."
        /** iOS's on-device recogniser: Android has none for a recording. */
        const val deviceNotSetUp = "No speech recogniser that can transcribe a recording is set up on this phone."
    }

    /** A pause long enough to be the end of a sentence: lecturers speak in breaths, not sentences. */
    const val pauseSeconds = 0.55
    /** A line nobody paused inside still has to end somewhere. */
    const val maxWordsPerLine = 14

    /** Break a stream of timed words into readable lines. */
    fun lines(from: List<SpokenWord>): List<Line> {
        val lines = ArrayList<Line>()
        var current = ArrayList<SpokenWord>()
        fun flush() {
            val first = current.firstOrNull() ?: return
            val last = current.last()
            lines.add(Line(current.joinToString(" ") { it.text }, first.start, last.end, current))
            current = ArrayList()
        }
        for (word in from) {
            val previous = current.lastOrNull()
            if (previous != null) {
                val gap = word.start - previous.end
                if (gap >= pauseSeconds || current.size >= maxWordsPerLine) flush()
            }
            current.add(word)
        }
        flush()
        return lines
    }

    /** The lines as the Narrate player wants them: the measured word timings. */
    fun timings(lines: List<Line>): List<List<MeasuredWord>> = lines.map { line -> line.words.map { MeasuredWord(it.text, it.start, it.end) } }

    /** Keep up to 100 nonempty lecture terms in order, ignoring case for repeats. */
    fun recogniserTerms(terms: List<String>): List<String> {
        val seen = HashSet<String>()
        val result = ArrayList<String>()
        for (term in terms) {
            if (term.isEmpty()) continue
            if (!seen.add(term.lowercase())) continue
            result.add(term)
            if (result.size == 100) break
        }
        return result
    }
}

/** The transcript a recording produced, as segments the player can hold (iOS NarrateScheduler.segments). */
fun NarrateScheduler.segments(lines: List<LectureTranscriber.Line>, lang: String): List<NarrateSegment> = lines.map { line ->
    NarrateSegment(text = line.text, lang = lang, start = line.start, end = line.end,
        words = line.words.map { SpokenTiming(it.text, it.start, it.end) }, model = line.model)
}

/** The word timings in the shape WordTiming.layout wants (iOS NarrateScheduler.measured); null when no line has any. */
fun NarrateScheduler.measured(segments: List<NarrateSegment>): List<List<MeasuredWord>>? {
    if (segments.none { it.words.isNotEmpty() }) return null
    return segments.map { s -> s.words.map { MeasuredWord(it.text, it.start, it.end) } }
}
