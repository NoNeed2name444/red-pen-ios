package com.stethoscore.app.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// ios/RedPen/Tests/NarrateTests.swift (fed0105), case for case: reading a
// lecture aloud - how it is cut into clips, where each word falls inside one,
// what is fetched ahead, the phone's voice, the clip cache, the audio tile's
// empty lecture, and the word flow's lines (FlowLines).
class NarrateTest {
    private val line = "word ".repeat(20)   // 100 characters
    private val lecture = List(40) { line }
    private val chunks = NarratePlan.chunks(lecture)
    private val long = "x".repeat(2000)
    private val odd = NarratePlan.chunks(listOf("short", long, "after"))

    // MARK: clips

    @Test fun clips() {
        assertEquals("every line is in exactly one clip, in order", (0 until 40).toList(), chunks.flatMap { it.lines.toList() })
        assertTrue("the first clip is short, so speech starts quickly: ${chunks[0].text.length}", chunks[0].text.length <= NarratePlan.firstLimit)
        assertTrue("later clips are longer, so a lecture is few requests: ${chunks.size}",
            chunks.size < 12 && chunks[1].lines.count() > chunks[0].lines.count())
        assertTrue("no clip is more than the server takes", chunks.all { it.text.length <= NarratePlan.hardCap })

        assertEquals("a line too long for a clip is still its own clip, never lost", listOf(0 until 1, 1 until 2, 2 until 3), odd.map { it.lines })
        assertEquals("a blank line leaves no double space", "one two", NarratePlan.chunks(listOf("one", "  ", "two"))[0].text)
        assertTrue("an empty lecture has no clips", NarratePlan.chunks(emptyList()).isEmpty())

        assertEquals("the clip holding a line is found", true, NarratePlan.chunkIndex(17, chunks)?.let { 17 in chunks[it].lines })
        assertNull("a line past the end is in no clip", NarratePlan.chunkIndex(99, chunks))
    }

    // MARK: word times

    @Test fun wordTimes() {
        val words = NarratePlan.wordTimes(listOf("Buffers act in seconds, the lungs in minutes.", "The kidneys take days."), 0 until 2, 6.0)
        assertEquals("every word is timed", 12, words.size)
        assertTrue("the words fill the clip exactly", words.first().start == 0.0 && words.last().end == 6.0)
        assertTrue("times only move forward", words.zipWithNext().all { (a, b) -> a.end <= b.start && a.start < a.end })
        val seconds = words[3]                      // "seconds," before a comma
        val the = words[4]
        assertTrue("a comma leaves a pause before the next word: ${the.start - seconds.end}", the.start - seconds.end > 0.05)
        val minutes = words[7]                      // "minutes." ends the line
        val next = words[8]
        assertTrue("a full stop leaves a longer pause than a comma", next.start - minutes.end > the.start - seconds.end)
        assertTrue("a long word is given longer than a short one", words[0].end - words[0].start > words[2].end - words[2].start)
        assertTrue("the second line's words say which line they are in", words[8].line == 1 && words[8].word == 0)
        assertTrue("nothing to time gives nothing", NarratePlan.wordTimes(listOf("a"), 0 until 1, 0.0).isEmpty())

        assertEquals("the word at a moment is found", 3, NarratePlan.spot(seconds.start + 0.01, words))
        assertEquals("in a pause the word just said stays lit", 3, NarratePlan.spot(seconds.end + 0.01, words))
        assertEquals("before the first word, the first word", 0, NarratePlan.spot(-1.0, words))
        assertEquals("after the end, the last word", words.size - 1, NarratePlan.spot(99.0, words))
        assertNull("no words, no spot", NarratePlan.spot(1.0, emptyList()))
        assertEquals("a line starts where its first word does", words[8].start, NarratePlan.start(1, words), 0.0)
    }

    // MARK: fetching ahead

    @Test fun fetchingAhead() {
        assertEquals("the playing clip and the next three are fetched", listOf(2, 3, 4, 5), NarratePlan.prefetch(2, 10, 3, emptySet()))
        assertEquals("clips already here are not fetched again", listOf(4, 5), NarratePlan.prefetch(2, 10, 3, setOf(2, 3)))
        assertEquals("nothing past the end is fetched", listOf(8, 9), NarratePlan.prefetch(8, 10, 3, emptySet()))
        assertTrue("past the end, nothing", NarratePlan.prefetch(10, 10, 3, emptySet()).isEmpty())
    }

    // MARK: the phone's voice

    @Test fun thePhonesVoice() {
        assertEquals("normal speed is the phone's normal pace", 0.5f, NarratePlan.phoneRate(1.0))
        assertTrue("faster is faster, slower is slower", NarratePlan.phoneRate(1.5) > 0.5f && NarratePlan.phoneRate(0.75) < 0.5f)
        assertTrue("double speed stays intelligible", NarratePlan.phoneRate(2.0) <= 0.7f)
        // the same speed menu drives the recording and the phone's voice, so every step on it has to be a little faster than the one before
        val menu = listOf(0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5)
        val phoneRates = menu.map { NarratePlan.phoneRate(it) }
        assertTrue("every step on the speed menu is faster than the last: $phoneRates", phoneRates.zipWithNext().all { (a, b) -> a < b })
        assertTrue("the fastest step is still words: ${NarratePlan.phoneRate(2.5)}", NarratePlan.phoneRate(2.5) <= 0.75f)

        val spoken = "The  bicarbonate buffer"
        assertEquals("a range at the start is the first word", 0, NarratePlan.wordIndex(0, spoken))
        assertEquals("a double space does not count as a word", 1, NarratePlan.wordIndex(5, spoken))
        assertEquals("the third word", 2, NarratePlan.wordIndex(17, spoken))
        assertEquals("the words match the screen's split", listOf("The", "bicarbonate", "buffer"), NarratePlan.tokens(spoken))
        val arabic = "الحمض pH"
        assertEquals("Arabic counts words the same way", 1, NarratePlan.wordIndex(6, arabic))
    }

    // MARK: the phone standing in for one clip

    @Test fun thePhoneStandingIn() {
        // a line too long for the server is read by the phone - that clip, and no more: the cloud takes the next one back
        assertEquals("the phone hands the too-long line back at its own clip's end", 2, NarratePlan.standInEnd(1, odd))
        assertNotEquals("not at the end of the lecture", odd.last().end, NarratePlan.standInEnd(1, odd))
        assertEquals("a line in a longer clip hands back where that clip ends",
            NarratePlan.chunkIndex(17, chunks)?.let { chunks[it].end }, NarratePlan.standInEnd(17, chunks))
        assertNull("a line in no clip has nowhere to hand back", NarratePlan.standInEnd(99, chunks))
    }

    // MARK: the clip cache

    @Test fun theClipCache() {
        val day = 86_400_000L
        val cached = (0 until 6).map { CachedClip("clip$it.mp3", it * day) }
        assertTrue("nothing is pruned under the limit", NarratePlan.pruneList(cached, 10, emptySet()).isEmpty())
        assertEquals("the least recently used go first", listOf("clip0.mp3", "clip1.mp3"), NarratePlan.pruneList(cached, 4, emptySet()))
        // replaying an old lecture: its clips are the oldest files, and deleting one that is about to play leaves the lecture silent
        assertEquals("a clip the lecture holds is never pruned, however old",
            listOf("clip1.mp3", "clip2.mp3"), NarratePlan.pruneList(cached, 4, setOf("clip0.mp3")))
        assertTrue("with everything protected, nothing is deleted",
            NarratePlan.pruneList(cached, 2, cached.map { it.name }.toSet()).isEmpty())

        // the audio tile's empty lecture (audit #33)
        assertTrue("a cancelled pick leaves no empty lecture", NarratePlan.dropsEmptyLecture(true, 0, false, false))
        assertFalse("a recording on its way keeps it", NarratePlan.dropsEmptyLecture(true, 0, false, true))
        assertFalse("a recording kept keeps it", NarratePlan.dropsEmptyLecture(true, 0, true, false))
        assertFalse("a lecture opened from the library is never dropped", NarratePlan.dropsEmptyLecture(false, 0, false, false))
    }

    // MARK: the word flow's lines (FlowLines)

    @Test fun theWordFlowsLines() {
        assertEquals("words that fit share a line", listOf(0, 0, 0), FlowLines.lines(listOf(30.0, 40.0, 50.0), 4.0, 200.0))
        assertEquals("a word that does not fit starts the next line", listOf(0, 0, 1), FlowLines.lines(listOf(100.0, 100.0, 100.0), 4.0, 210.0))
        assertEquals("a word wider than a line has a line of its own", listOf(0, 1, 2), FlowLines.lines(listOf(50.0, 500.0, 50.0), 4.0, 200.0))
        assertEquals("with no width offered, every word is on one line", listOf(0, 0, 0, 0),
            FlowLines.lines(listOf(80.0, 90.0, 100.0, 110.0), 4.0, Double.POSITIVE_INFINITY))
        assertEquals("each line is as wide as its words and the gaps between them", listOf(204.0, 100.0),
            FlowLines.lineWidths(listOf(100.0, 100.0, 100.0), 4.0, listOf(0, 0, 1)))
        assertTrue("no words, no lines",
            FlowLines.lines(emptyList(), 4.0, 200.0).isEmpty() && FlowLines.lineWidths(emptyList(), 4.0, emptyList()).isEmpty())

        // The audio tile at XXL (15 Oct): measured on one line 188.6 wide, the line was placed in 188.33, and its last word dropped onto the next paragraph.
        val rounded = listOf(60.2, 70.1, 50.3)
        assertEquals("a line placed in its own width, rounded down, keeps its last word", listOf(0, 0, 0),
            FlowLines.lines(rounded, 4.0, 188.6 - 0.27))

        // Whatever the words and the width offered: offered back the width they asked for (their widest line), less up to a point's rounding, they break into the same lines.
        var seed = 0x5EEDL
        fun nextUnit(): Double {
            seed = seed * 6364136223846793005L + 1442695040888963407L
            return (seed ushr 11).toDouble() / (1L shl 53).toDouble()
        }
        var agree = true
        var disagreement = ""
        for (round in 0 until 500) {
            val count = 1 + (nextUnit() * 30).toInt()
            val widths = (0 until count).map { 8 + nextUnit() * 140 }
            val offered = 60 + nextUnit() * 400
            val measured = FlowLines.lines(widths, 4.0, offered)
            val widest = FlowLines.lineWidths(widths, 4.0, measured).maxOrNull() ?: 0.0
            if (widest > offered) continue
            val given = widest - nextUnit() * 0.99
            val placed = FlowLines.lines(widths, 4.0, given)
            if (placed != measured) {
                agree = false
                disagreement = "offered $offered, given $given: $measured then $placed"
                break
            }
        }
        assertTrue("offered back its own width, rounded down, a flow keeps its lines: $disagreement", agree)
    }
}
