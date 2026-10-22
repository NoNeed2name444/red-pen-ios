package com.stethoscore.app.audio

import kotlin.math.max
import kotlin.math.min

// Where each WORD sits in the recording (ios/RedPen/Shared/WordTiming.swift, fed0105).
//
// Two ways to get word times, and the difference matters enough to keep:
//
//   measured   the recogniser gave real per-word times. Used exactly as given.
//   estimated  only the phrase's end time is known, so the phrase's span is
//              shared out across its words by how long each one takes to say.
//
// An estimate is never presented as a measurement.

enum class TimingSource { measured, estimated }

data class TranscriptWord(val segment: Int, val index: Int, val text: String, val start: Double, val end: Double, val source: TimingSource) {
    val id: String get() = "$segment.$index"
    fun contains(t: Double): Boolean = t >= start && t < end
    val duration: Double get() = max(0.0, end - start)
}

/** A word's measured place in the recording (Swift's (text:, start:, end:) tuple). */
data class MeasuredWord(val text: String, val start: Double, val end: Double)

object WordTiming {
    /** The floor that stops "a" and "في" from flashing past unreadably. */
    const val minimumWordSeconds = 0.12

    private fun isLetter(cp: Int): Boolean = Character.isLetter(cp) || when (Character.getType(cp)) {
        Character.NON_SPACING_MARK.toInt(), Character.COMBINING_SPACING_MARK.toInt(), Character.ENCLOSING_MARK.toInt() -> true
        else -> false
    }

    /**
     * A word's share of a phrase. Arabic script writes short vowels as
     * nothing, so a four-letter Arabic word is spoken about as long as a
     * six-letter English one.
     */
    fun weight(word: String): Double {
        val cps = word.codePoints().toArray()
        val letters = cps.count { isLetter(it) }
        val arabic = cps.any { it in 0x0600..0x06FF }
        return max(1.0, letters * (if (arabic) 1.4 else 1.0))
    }

    /**
     * Split one phrase into words carrying a start and an end. [measured] is
     * the recogniser's own word times when it had them; any word it did not
     * time falls back to its estimated share.
     */
    fun words(text: String, segment: Int, from: Double, to: Double, measured: List<MeasuredWord>? = null): List<TranscriptWord> {
        val tokens = text.split(' ').filter { it.isNotEmpty() }
        if (tokens.isEmpty()) return emptyList()
        if (!measured.isNullOrEmpty()) {
            val out = ArrayList<TranscriptWord>()
            for ((i, token) in tokens.withIndex()) {
                if (i >= measured.size) break
                val m = measured[i]
                out.add(TranscriptWord(segment, i, token, m.start, max(m.start, m.end), TimingSource.measured))
            }
            if (out.size == tokens.size) return out
            // the recogniser timed only part of the phrase: estimate the rest from where its last measurement stopped
            val restStart = out.lastOrNull()?.end ?: from
            val rest = tokens.subList(out.size, tokens.size)
            return out + share(rest, segment, out.size, restStart, max(restStart, to))
        }
        return share(tokens, segment, 0, from, to)
    }

    private fun share(tokens: List<String>, segment: Int, firstIndex: Int, from: Double, to: Double): List<TranscriptWord> {
        if (tokens.isEmpty()) return emptyList()
        val span = max(to - from, tokens.size * minimumWordSeconds)
        val weights = tokens.map(::weight)
        val total = weights.sum()
        val out = ArrayList<TranscriptWord>()
        var at = from
        for ((i, token) in tokens.withIndex()) {
            val slice = max(minimumWordSeconds, span * (weights[i] / total))
            val stop = if (i == tokens.size - 1) max(to, at + minimumWordSeconds) else at + slice
            out.add(TranscriptWord(segment, firstIndex + i, token, at, stop, TimingSource.estimated))
            at = stop
        }
        return out
    }

    /** Lay out a whole transcript. `ends[i]` is the second phrase i finished; a phrase starts where the previous one ended. */
    fun layout(texts: List<String>, ends: List<Double>, measured: List<List<MeasuredWord>>? = null): List<TranscriptWord> {
        val out = ArrayList<TranscriptWord>()
        var previousEnd = 0.0
        for ((i, text) in texts.withIndex()) {
            val end = if (i < ends.size) ends[i] else previousEnd
            val start = min(previousEnd, end)
            out += words(text, i, start, max(start, end), measured?.getOrNull(i))
            previousEnd = max(previousEnd, end)
        }
        return out
    }

    /** The word being spoken at [t]. Binary search, because the player asks this on every frame of the audio clock. */
    fun word(t: Double, words: List<TranscriptWord>): TranscriptWord? {
        if (words.isEmpty()) return null
        var lo = 0
        var hi = words.size - 1
        while (lo <= hi) {
            val mid = (lo + hi) / 2
            if (words[mid].contains(t)) return words[mid]
            if (t < words[mid].start) hi = mid - 1 else lo = mid + 1
        }
        // between two words - stay on the one just spoken rather than blink off
        return if (hi >= 0) words[hi] else null
    }
}
