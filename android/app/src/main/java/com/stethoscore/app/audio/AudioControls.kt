package com.stethoscore.app.audio

import java.math.BigDecimal
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// The lecture player's controls, as arithmetic (ios/RedPen/Shared/AudioControls.swift, fed0105):
//
//   AudioRate      the speeds on offer (0.75x to 2.5x in quarter steps), and
//                  the one remembered for each lecture and for the next new one
//   SleepCountdown the sleep timer: listening time left, and how loud the last
//                  ten seconds are as it fades out
//   AudioChapters  a lecture cut into sections - from its headings when it has
//                  them, otherwise at the pauses nearest every few minutes -
//                  and which section a moment or a line is in
//
// No Android here, so all of it runs in the JVM tests (AudioControlsTest).

// MARK: speed

/** Where the speeds are remembered (iOS UserDefaults): SharedPreferences on the phone, a map in the tests. */
interface AudioRateMemory {
    fun getDouble(key: String): Double?
    fun putDouble(key: String, value: Double)
}

object AudioRate {
    /** Quarter steps: past 2.5x a lecture stops being words. */
    val steps: List<Double> = listOf(0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5)
    const val normal: Double = 1.0

    /** The nearest speed on offer. Anything that is not a number is Normal. */
    fun snapped(rate: Double): Double {
        if (!rate.isFinite() || rate <= 0) return normal
        var best = normal
        var gap = Double.POSITIVE_INFINITY
        for (step in steps) if (abs(step - rate) < gap) {
            gap = abs(step - rate)
            best = step
        }
        return best
    }

    fun faster(than: Double): Double {
        val now = snapped(than)
        return steps.firstOrNull { it > now } ?: now
    }

    fun slower(than: Double): Double {
        val now = snapped(than)
        return steps.lastOrNull { it < now } ?: now
    }

    /** "1.25×" - the speed as the chip shows it (iOS's %g). */
    fun label(rate: Double): String =
        BigDecimal.valueOf(snapped(rate)).stripTrailingZeros().toPlainString() + "×"

    /** The menu's words: Normal for 1x, the number otherwise. */
    fun name(rate: Double): String = if (snapped(rate) == normal) "Normal" else label(rate)

    // MARK: remembered

    const val defaultKey = "audio.rate.default"
    const val lecturesKey = "audio.rate.lectures"

    private fun lectureKey(lecture: String) = "$lecturesKey.$lecture"

    /**
     * The speed a lecture opens at: the one it was last heard at, or the
     * last speed chosen for any lecture, or Normal.
     */
    fun remembered(lecture: String, memory: AudioRateMemory): Double {
        memory.getDouble(lectureKey(lecture))?.let { return snapped(it) }
        val global = memory.getDouble(defaultKey) ?: 0.0
        return if (global > 0) snapped(global) else normal
    }

    /** A speed chosen for a lecture is kept for it, and becomes the one the next new lecture opens at. */
    fun remember(rate: Double, lecture: String, memory: AudioRateMemory) {
        val kept = snapped(rate)
        memory.putDouble(lectureKey(lecture), kept)
        memory.putDouble(defaultKey, kept)
    }
}

// MARK: the sleep timer

sealed class SleepChoice {
    data class Minutes(val minutes: Int) : SleepChoice()
    /** Stops where the section playing now ends. */
    object EndOfSection : SleepChoice() { override fun toString() = "EndOfSection" }

    val name: String get() = when (this) {
        is Minutes -> "$minutes minutes"
        EndOfSection -> "End of this section"
    }

    companion object {
        val all: List<SleepChoice> = listOf(Minutes(5), Minutes(10), Minutes(15), Minutes(30), Minutes(45), Minutes(60), EndOfSection)
    }
}

/**
 * How long is left before the lecture stops, in listening time: a paused
 * lecture does not use up the timer, so pausing for a sip of water does not
 * cut the last five minutes short.
 */
class SleepCountdown private constructor(val choice: SleepChoice, remaining: Double) {
    var remaining: Double = remaining
        private set

    fun copy(): SleepCountdown = SleepCountdown(choice, remaining)

    /** Time heard since the last check. */
    fun advance(listened: Double) {
        if (!listened.isFinite() || listened <= 0) return
        remaining = max(0.0, remaining - min(listened, maxStep))
    }

    /** "End of this section" follows the player's own clock: a scrub back gives time back, and a faster speed takes it away. */
    fun follow(sectionLeft: Double) {
        if (!sectionLeft.isFinite()) return
        remaining = max(0.0, sectionLeft)
    }

    val isDone: Boolean get() = remaining <= 0

    val volume: Float get() = volume(remaining)

    /**
     * Seconds until the next check: once a second, ten times a second while
     * fading so the volume slides rather than steps - and never sleeping
     * past the moment the fade begins.
     */
    val nextCheck: Double get() {
        val untilFade = remaining - fade
        if (untilFade <= 0) return 0.1
        return max(0.1, min(1.0, untilFade))
    }

    /** Minutes and seconds left, for the chip. */
    val label: String get() {
        val total = ceil(remaining).toInt()
        return String.format(java.util.Locale.ROOT, "%d:%02d", total / 60, total % 60)
    }

    override fun equals(other: Any?): Boolean = other is SleepCountdown && other.choice == choice && other.remaining == remaining
    override fun hashCode(): Int = choice.hashCode() * 31 + remaining.hashCode()

    companion object {
        /** The last ten seconds fade out rather than stopping dead. */
        const val fade: Double = 10.0
        /** The most one check may take off. Checks come every second; a longer gap means the app was not running, and so nothing was heard either. */
        const val maxStep: Double = 5.0

        /** Null for "end of this section" when the player cannot say where the section ends. */
        fun of(choice: SleepChoice, sectionLeft: Double? = null): SleepCountdown? = when (choice) {
            is SleepChoice.Minutes -> SleepCountdown(choice, max(1, choice.minutes) * 60.0)
            SleepChoice.EndOfSection ->
                if (sectionLeft == null || !sectionLeft.isFinite()) null else SleepCountdown(choice, max(0.0, sectionLeft))
        }

        /**
         * Full volume until the last ten seconds, then down along a square
         * curve: it sounds even to the ear, where a straight line seems to
         * hang on loud and then drop away at the end.
         */
        fun volume(remaining: Double, over: Double = fade): Float {
            if (!remaining.isFinite() || over <= 0) return 1f
            val x = min(1.0, max(0.0, remaining / over))
            return (x * x).toFloat()
        }
    }
}

// MARK: chapters

/** One section of a lecture: its lines ([lines], first until end), and where it starts in the recording when there is one. */
data class AudioChapter(val title: String, val lines: IntRange, val start: Double?) {
    /** The line after its last (Swift's upperBound). */
    val end: Int get() = lines.last + 1
}

object AudioChapters {
    /** Without headings, a lecture shorter than this is one section. */
    const val shortest: Double = 6 * 60.0
    /** Roughly how long a section runs when there are no headings to go by. */
    const val target: Double = 5 * 60.0
    /** "Previous" within this long of a section's start goes to the one before, as a music player's Back does; later, to this one's start. */
    const val backGrace: Double = 3.0
    /** Speaking pace used when a line has no timing: 150 words a minute. */
    const val wordsPerSecond: Double = 2.5

    /**
     * A lecture's sections. [starts] and [ends] are each line's times in the
     * recording (null when a line is not timed). Empty when the lecture is
     * one section - there is nothing to jump between.
     */
    fun derive(lines: List<String>, starts: List<Double?> = emptyList(), ends: List<Double?> = emptyList()): List<AudioChapter> {
        if (lines.size < 2) return emptyList()
        val timed = starts.size == lines.size && starts.none { it == null }
        val at: List<Double> = if (timed) starts.map { it ?: 0.0 } else estimatedStarts(lines)
        val fromHeadings = byHeadings(lines, if (timed) at else null, timed)
        if (fromHeadings.size >= 2) return fromHeadings
        return byLength(lines, at, if (timed) ends else emptyList(), timed)
    }

    /** Where each line would start, read at 150 words a minute. */
    fun estimatedStarts(lines: List<String>): List<Double> {
        val out = ArrayList<Double>(lines.size)
        var t = 0.0
        for (line in lines) {
            out.add(t)
            t += secondsToSay(line)
        }
        return out
    }

    fun secondsToSay(line: String): Double {
        val words = line.split(' ', '\n').count { it.isNotEmpty() }
        return max(1, words) / wordsPerSecond
    }

    // MARK: headings

    /**
     * The heading a line is, if it reads as one: a Markdown "#", a "Slide 4"
     * / "Part two" / "Section B", a short line ending in a colon, or - in a
     * typed lecture only - a short capitalised line with no full stop. A
     * recogniser's transcript often has no punctuation at all, so that last
     * rule would make every other line a heading there.
     */
    fun heading(raw: String, timed: Boolean = false): String? {
        val line = raw.trim()
        if (line.isEmpty() || line.length > 80) return null
        if (line.startsWith("#")) {
            val bare = line.dropWhile { it == '#' }.trim(' ', '\t')
            return bare.ifEmpty { null }
        }
        val words = line.split(' ').filter { it.isNotEmpty() }
        if (words.size <= 10 && startsWithMarker(words)) return tidy(line)
        if (words.size <= 8 && line.endsWith(":")) return tidy(line)
        if (timed || words.size > 6 || !line.first().isUpperCase()) return null
        val stops = setOf('.', '?', '!', ',', ';', '…', '،', '؟')
        if (line.last() in stops || line.none { it.isLetter() }) return null
        return tidy(line)
    }

    private val markers = setOf("slide", "section", "part", "chapter", "topic", "lecture", "unit")

    private val numberWords = setOf("one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
        "twelve", "first", "second", "third", "fourth", "fifth", "last", "final")

    /**
     * "Slide 7", "Part two", "Section B", "Chapter IV" - a marker and then its
     * number. "Part of the reason is..." and "Lecture notes are online" start
     * with the same words and are sentences, not headings.
     */
    private fun startsWithMarker(words: List<String>): Boolean {
        if (words.size < 2) return false
        val said = words[0].lowercase()
        val first = if (said.endsWith(":")) said.dropLast(1) else said
        if (first !in markers) return false
        // "Topic: the kidneys" - the colon says it is a label
        if (said.endsWith(":")) return true
        val bare = words[1].lowercase().trim(':', '.', ',', ')', '-')
        return isNumbering(bare)
    }

    private fun isNumbering(word: String): Boolean {
        if (word.isEmpty()) return false
        if (word.all { it.isDigit() }) return true
        if (word in numberWords) return true
        // a single letter (Section B), or a Roman numeral (Part IV)
        if (word.length == 1 && word[0].isLetter()) return true
        val roman = setOf('i', 'v', 'x', 'l')
        return word.length <= 5 && word.all { it in roman }
    }

    private fun tidy(line: String): String = line.trimEnd(':', '.', ' ')

    /**
     * A section at every heading. Headings in a row (a title and its
     * subtitle) start one section, under the first; the lines before the
     * first heading are an opening section of their own.
     */
    private fun byHeadings(lines: List<String>, at: List<Double>?, timed: Boolean): List<AudioChapter> {
        val starts = ArrayList<Int>()
        val titles = ArrayList<String>()
        var previousWasHeading = false
        var headingLines = 0
        for ((i, line) in lines.withIndex()) {
            val title = heading(line, timed)
            if (title == null) {
                previousWasHeading = false
                continue
            }
            headingLines += 1
            if (!previousWasHeading) {
                starts.add(i)
                titles.add(title)
            }
            previousWasHeading = true
        }
        // headings on most lines are a list, not a lecture's sections
        if (starts.isEmpty() || headingLines * 2 > lines.size || starts.size * 3 > lines.size) return emptyList()
        if (starts[0] > 0) {
            starts.add(0, 0)
            titles.add(0, shortTitle(lines[0]))
        }
        return assemble(starts, titles, lines.size, at)
    }

    // MARK: by length

    private val turns = listOf("so ", "now ", "next ", "okay", "ok ", "moving on", "let's ", "lets ", "another ", "finally", "right,", "alright")

    /**
     * No headings: a section about every five minutes, cut where the lecturer
     * paused longest near each mark, or at a line that turns to something new
     * ("So", "Now", "Moving on").
     */
    private fun byLength(lines: List<String>, at: List<Double>, ends: List<Double?>, timed: Boolean): List<AudioChapter> {
        val lastStart = at.lastOrNull() ?: 0.0
        val total = lastStart + secondsToSay(lines[lines.size - 1])
        if (total < shortest) return emptyList()
        val count = min(12, max(2, roundHalfAway(total / target).toInt()))
        val span = total / count
        val starts = arrayListOf(0)
        for (k in 1 until count) {
            val mark = span * k
            val previous = starts[starts.size - 1]
            val cut = bestCut(mark, span * 0.35, previous, lines, at, ends) ?: continue
            starts.add(cut)
        }
        if (starts.size < 2) return emptyList()
        val titles = starts.map { shortTitle(lines[it]) }
        return assemble(starts, titles, lines.size, if (timed) at else null)
    }

    private fun roundHalfAway(x: Double): Double = if (x >= 0) floor(x + 0.5) else -floor(-x + 0.5)

    private fun bestCut(mark: Double, window: Double, previous: Int, lines: List<String>, at: List<Double>, ends: List<Double?>): Int? {
        var best: Int? = null
        var bestScore = Double.NEGATIVE_INFINITY
        for (i in (previous + 1) until lines.size) {
            val t = at[i]
            if (t < mark - window) continue
            if (t > mark + window) break
            val score = cutScore(i, mark, window, lines, at, ends)
            if (score > bestScore) {
                bestScore = score
                best = i
            }
        }
        return best
    }

    /** A long pause before the line counts most, a turning word next, and being close to the mark breaks ties. */
    private fun cutScore(i: Int, mark: Double, window: Double, lines: List<String>, at: List<Double>, ends: List<Double?>): Double {
        var gap = 0.0
        if (i < ends.size) ends[i - 1]?.let { gap = max(0.0, at[i] - it) }
        val lower = lines[i].lowercase()
        val turn = if (turns.any { lower.startsWith(it) }) 1.5 else 0.0
        val near = 1 - abs(at[i] - mark) / max(window, 1.0)
        return min(gap, 6.0) + turn + near
    }

    private fun assemble(starts: List<Int>, titles: List<String>, count: Int, at: List<Double>?): List<AudioChapter> =
        starts.mapIndexed { n, first ->
            val end = if (n + 1 < starts.size) starts[n + 1] else count
            AudioChapter(titles[n], first until end, at?.get(first))
        }

    /** A section named by its first words: "Buffers act in seconds, the…". */
    fun shortTitle(line: String, limit: Int = 6): String {
        val words = line.split(' ').filter { it.isNotEmpty() }
        if (words.isEmpty()) return "Section"
        val title = words.take(limit).joinToString(" ").trimEnd(',', ';', ':', '.')
        return if (words.size > limit) "$title…" else title
    }

    // MARK: where am I

    /** The section a line is in. */
    fun indexContainingLine(line: Int, chapters: List<AudioChapter>): Int? {
        if (chapters.isEmpty()) return null
        if (line < chapters[0].lines.first) return 0
        return chapters.indexOfLast { it.lines.first <= line }.takeIf { it >= 0 }
    }

    /** The section playing at [t] seconds into the recording: the last one that has started, by binary search. */
    fun indexAtTime(t: Double, chapters: List<AudioChapter>): Int? {
        if (chapters.isEmpty()) return null
        var low = 0
        var high = chapters.size - 1
        while (low < high) {
            val mid = (low + high + 1) / 2
            if ((chapters[mid].start ?: 0.0) <= t) low = mid else high = mid - 1
        }
        return low
    }

    /** Where the section playing at [t] ends: the next one's start, or the end of the recording. */
    fun end(after: Double, chapters: List<AudioChapter>, duration: Double): Double {
        val i = indexAtTime(after, chapters) ?: return duration
        if (i + 1 >= chapters.size) return duration
        return chapters[i + 1].start ?: duration
    }

    /** The section Back goes to from [t]: this one's start when well into it, the one before when just started. */
    fun previousFromTime(t: Double, chapters: List<AudioChapter>): Int? {
        val i = indexAtTime(t, chapters) ?: return null
        val start = chapters[i].start ?: 0.0
        if (t - start > backGrace || i == 0) return i
        return i - 1
    }

    /** The same for a lecture read aloud, by line. */
    fun previousFromLine(line: Int, chapters: List<AudioChapter>): Int? {
        val i = indexContainingLine(line, chapters) ?: return null
        if (line > chapters[i].lines.first || i == 0) return i
        return i - 1
    }

    /** The section after the one holding [i], or null at the last. */
    fun next(after: Int?, chapters: List<AudioChapter>): Int? {
        if (after == null) return if (chapters.isEmpty()) null else 0
        return if (after + 1 < chapters.size) after + 1 else null
    }

    /**
     * Roughly how long, at [speed], until the voice reaching line [until]
     * when it is on word [word] of line [line]. Never quite zero before it
     * gets there, so a sleep timer waits for the line rather than an
     * estimate that ran out early.
     */
    fun secondsToRead(lines: List<String>, line: Int, word: Int, until: Int, speed: Double): Double {
        if (line >= until || line >= lines.size) return 0.0
        fun count(s: String) = s.split(' ').count { it.isNotEmpty() }
        var words = max(0, count(lines[line]) - word)
        val upper = min(until, lines.size)
        for (i in (line + 1) until upper) words += count(lines[i])
        val pace = wordsPerSecond * max(0.25, speed)
        return max(1.0, words / pace)
    }

    /** "Section 2 of 7", for the lock screen and the chip. */
    fun position(i: Int, chapters: List<AudioChapter>): String = "Section ${i + 1} of ${chapters.size}"
}
