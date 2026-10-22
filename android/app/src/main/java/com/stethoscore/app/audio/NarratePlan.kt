package com.stethoscore.app.audio

import kotlin.math.max
import kotlin.math.min

// How a lecture is cut up to be read aloud, and where each word falls
// (ios/RedPen/Shared/NarratePlan.swift, fed0105). Pure arithmetic, kept apart
// from the audio so it can be tested on the JVM:
//
//   chunks     lines grouped into clips the server will take: a short first
//              clip so speech starts quickly, then longer ones
//   wordTimes  a clip's words spread over the clip's REAL duration by how
//              long each takes to say, with room for the pauses at commas,
//              full stops and line ends
//   spot       which word is being said at a moment, by binary search
//   prefetch   which clips to fetch next, so the next few are always ready
//   phoneRate  a playback speed as iOS's AVSpeechUtterance rate
//   wordIndex  the word a speech-synthesis range starts in
//
// Android reads every lecture with the phone's voice (TextToSpeech), so the
// clip half is kept for parity and its tests; the screen uses tokens,
// wordIndex and dropsEmptyLecture.

/** Consecutive lines read as one clip ([lines]: first until end). */
data class NarrateChunk(val lines: IntRange, val text: String) {
    /** The line after its last (Swift's upperBound). */
    val end: Int get() = lines.last + 1
}

/** One word inside a clip, and when it is said, in seconds from the clip start. */
data class ClipWord(val line: Int, val word: Int, val start: Double, val end: Double)

/** A cached clip file and when it was last written or heard (milliseconds). */
data class CachedClip(val name: String, val used: Long)

object NarratePlan {
    /**
     * A lecture made by the Audio page's "Add an audio file" goes again when
     * its screen closes with nothing in it - no transcript, no recording, none
     * on its way - so a cancelled pick leaves no empty "New lecture" behind
     * (audit #33).
     */
    fun dropsEmptyLecture(madeHere: Boolean, segments: Int, hasRecording: Boolean, importing: Boolean): Boolean =
        madeHere && segments == 0 && !hasRecording && !importing

    /** The server takes up to 1,500 characters; a little under leaves room. */
    const val hardCap = 1400
    /** The first clip is short so the voice starts within a second or two. */
    const val firstLimit = 240
    /** Later clips are longer: fewer requests, and each is fetched well before it is needed. */
    const val limit = 900

    // MARK: cutting the lecture into clips

    /**
     * Lines grouped into clips. A line is never split, and a clip always has
     * at least one line, so a single very long line becomes its own clip.
     */
    fun chunks(lines: List<String>, first: Int = firstLimit, rest: Int = limit): List<NarrateChunk> {
        val out = ArrayList<NarrateChunk>()
        var start = 0
        var length = 0
        for (i in lines.indices) {
            val n = lines[i].length + 1
            val cap = if (out.isEmpty()) first else rest
            if (i > start && length + n > cap) {
                out.add(chunk(lines, start until i))
                start = i
                length = 0
            }
            length += n
        }
        if (start < lines.size) out.add(chunk(lines, start until lines.size))
        return out
    }

    private fun chunk(lines: List<String>, range: IntRange): NarrateChunk {
        val text = range.map { lines[it].trim(' ', '\t') }.filter { it.isNotEmpty() }.joinToString(" ")
        return NarrateChunk(range, text)
    }

    /** The clip a line is read in. */
    fun chunkIndex(containing: Int, chunks: List<NarrateChunk>): Int? {
        var lo = 0
        var hi = chunks.size - 1
        while (lo <= hi) {
            val mid = (lo + hi) / 2
            val range = chunks[mid].lines
            if (containing in range) return mid
            if (containing < range.first) hi = mid - 1 else lo = mid + 1
        }
        return null
    }

    // MARK: where each word falls inside a clip

    /** The words as the screen shows them: split on spaces, empties dropped. */
    fun tokens(line: String): List<String> = line.split(' ').filter { it.isNotEmpty() }

    private fun isAlphanumeric(cp: Int): Boolean = Character.isLetterOrDigit(cp) || when (Character.getType(cp)) {
        Character.NON_SPACING_MARK.toInt(), Character.COMBINING_SPACING_MARK.toInt(), Character.ENCLOSING_MARK.toInt(),
        Character.LETTER_NUMBER.toInt(), Character.OTHER_NUMBER.toInt() -> true
        else -> false
    }

    /**
     * How long a word takes to say, in "characters". Letters and digits
     * count; a floor keeps "a" and "of" from flashing past; Arabic writes no
     * short vowels, so its letters are worth more.
     */
    fun weight(word: String): Double {
        var letters = 0
        var arabic = false
        word.codePoints().forEach { cp ->
            if (isAlphanumeric(cp)) letters += 1
            if (cp in 0x0600..0x06FF) arabic = true
        }
        val base = max(2, letters) * (if (arabic) 1.4 else 1.0)
        // the move from one word to the next takes a moment too
        return base + 1.0
    }

    /** The silence a speaker leaves after a word, in the same units. */
    fun pause(after: String, endsLine: Boolean): Double {
        val last = after.lastOrNull() ?: return 0.0
        if (last in ".!?") return 6.0
        if (last in ",;:") return 3.0
        if (last == '—' || last == '-') return 2.0
        return if (endsLine) 2.0 else 0.0
    }

    private class Spot(val line: Int, val word: Int, val weight: Double, val pause: Double)

    /** The clip's words laid over its real duration. */
    fun wordTimes(lines: List<String>, range: IntRange, duration: Double): List<ClipWord> {
        val spots = ArrayList<Spot>()
        for (li in range) {
            if (li < 0 || li >= lines.size) continue
            val words = tokens(lines[li])
            for ((wi, word) in words.withIndex()) {
                val endsLine = wi == words.size - 1
                spots.add(Spot(li, wi, weight(word), pause(word, endsLine)))
            }
        }
        if (spots.isEmpty() || duration <= 0) return emptyList()
        var total = 0.0
        for ((i, spot) in spots.withIndex()) {
            // the last word's pause is the clip's own end, not a gap
            total += spot.weight + (if (i == spots.size - 1) 0.0 else spot.pause)
        }
        val scale = duration / max(total, 0.001)
        val out = ArrayList<ClipWord>(spots.size)
        var at = 0.0
        for ((i, spot) in spots.withIndex()) {
            val last = i == spots.size - 1
            val end = if (last) duration else at + spot.weight * scale
            out.add(ClipWord(spot.line, spot.word, at, end))
            at = end + spot.pause * scale
        }
        return out
    }

    /** The word being said at [t]: the last one that has started, so the highlight holds through a pause instead of blinking off. */
    fun spot(t: Double, words: List<ClipWord>): Int? {
        if (words.isEmpty()) return null
        if (t < words[0].start) return 0
        var lo = 0
        var hi = words.size - 1
        while (lo < hi) {
            val mid = (lo + hi + 1) / 2
            if (words[mid].start <= t) lo = mid else hi = mid - 1
        }
        return lo
    }

    /** Where in its clip a line begins, for jumping to it. */
    fun start(ofLine: Int, words: List<ClipWord>): Double = words.firstOrNull { it.line >= ofLine }?.start ?: 0.0

    // MARK: the phone standing in

    /**
     * Where the phone hands a line back to the cloud: the end of the clip the
     * line is in. Null when no clip holds it.
     */
    fun standInEnd(forLine: Int, chunks: List<NarrateChunk>): Int? = chunkIndex(forLine, chunks)?.let { chunks[it].end }

    // MARK: the clip cache

    /**
     * Which cached clips to delete: the least recently written or heard
     * beyond [keep], and never one in [protected] - a clip the lecture on
     * screen holds or has queued, which deleted would play as silence.
     */
    fun pruneList(files: List<CachedClip>, keep: Int, protected: Set<String>): List<String> {
        if (files.size <= keep) return emptyList()
        val excess = files.size - keep
        return files.filter { it.name !in protected }.sortedBy { it.used }.take(excess).map { it.name }
    }

    // MARK: fetching ahead

    /** The clips to fetch now: the one playing and the next [ahead], less any already fetched or on their way. */
    fun prefetch(current: Int, count: Int, ahead: Int, have: Set<Int>): List<Int> {
        if (count <= 0 || current >= count) return emptyList()
        val from = max(0, current)
        val to = min(count - 1, from + ahead)
        return (from..to).filter { it !in have }
    }

    // MARK: the phone's own voice

    /**
     * A playback speed (0.75x, 1x, 1.5x... 2.5x) as iOS's AVSpeechUtterance
     * rate, where 0.5 is the phone's normal pace and the scale is far from
     * linear. Android's TextToSpeech takes the speed itself (1 is normal, 2
     * twice as fast), so the phone's voice there uses [ttsRate].
     */
    fun phoneRate(speed: Double): Float {
        val upTo2 = min(speed, 2.0)
        val past2 = max(0.0, speed - 2)
        val rate = 0.5 + (upTo2 - 1) * 0.18 + past2 * 0.12
        return min(0.74, max(0.32, rate)).toFloat()
    }

    /** The speed as Android's TextToSpeech.setSpeechRate takes it: the speed on the menu, snapped to it. */
    fun ttsRate(speed: Double): Float = AudioRate.snapped(speed).toFloat()

    /** The word a synthesiser range starts in. [offset] counts UTF-16 units; words are split exactly as [tokens] splits them. */
    fun wordIndex(offset: Int, text: String): Int {
        var index = -1
        var position = 0
        var previousWasSpace = true
        for (unit in text) {
            if (position > offset) break
            val space = unit == ' '
            if (!space && previousWasSpace) index += 1
            previousWasSpace = space
            position += 1
        }
        return max(0, index)
    }
}
