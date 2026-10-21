package com.stethoscore.app.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

// ios/RedPen/Tests/AudioControlsTests.swift (fed0105), case for case: the
// lecture player's controls - the speeds on offer and the one remembered,
// the sleep timer's countdown and fade, and a lecture's sections.
class AudioControlsTest {
    private class MapMemory : AudioRateMemory {
        val values = HashMap<String, Double>()
        override fun getDouble(key: String): Double? = values[key]
        override fun putDouble(key: String, value: Double) { values[key] = value }
    }

    // MARK: speed

    @Test fun speed() {
        assertEquals("quarter steps from 0.75x to 2.5x", listOf(0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5), AudioRate.steps)
        assertEquals("a speed off the menu snaps to the nearest step", 1.25, AudioRate.snapped(1.3), 0.0)
        assertEquals("too fast is the fastest", 2.5, AudioRate.snapped(9.0), 0.0)
        assertEquals("too slow is the slowest", 0.75, AudioRate.snapped(0.1), 0.0)
        assertTrue("not a number is Normal", AudioRate.snapped(Double.NaN) == 1.0 && AudioRate.snapped(-2.0) == 1.0)
        assertEquals("faster goes up a step", 1.75, AudioRate.faster(1.5), 0.0)
        assertEquals("faster at the top stays there", 2.5, AudioRate.faster(2.5), 0.0)
        assertEquals("slower goes down a step", 0.75, AudioRate.slower(1.0), 0.0)
        assertEquals("slower at the bottom stays there", 0.75, AudioRate.slower(0.75), 0.0)
        assertEquals("the chip reads 1.25×", "1.25×", AudioRate.label(1.25))
        assertEquals("1x is called Normal", "Normal", AudioRate.name(1.0))
        assertEquals("2x is called 2×", "2×", AudioRate.name(2.0))
    }

    @Test fun rememberedSpeed() {
        val defaults = MapMemory()
        val first = UUID.randomUUID().toString()
        val second = UUID.randomUUID().toString()
        val third = UUID.randomUUID().toString()
        assertEquals("a lecture never played opens at Normal", 1.0, AudioRate.remembered(first, defaults), 0.0)
        AudioRate.remember(1.75, first, defaults)
        assertEquals("a lecture opens at the speed it was last heard at", 1.75, AudioRate.remembered(first, defaults), 0.0)
        assertEquals("a new lecture opens at the last speed chosen anywhere", 1.75, AudioRate.remembered(second, defaults), 0.0)
        AudioRate.remember(1.25, third, defaults)
        assertTrue("each lecture keeps its own",
            AudioRate.remembered(first, defaults) == 1.75 && AudioRate.remembered(third, defaults) == 1.25)
        assertEquals("and the default follows the latest choice", 1.25, AudioRate.remembered(second, defaults), 0.0)
        AudioRate.remember(7.0, first, defaults)
        assertEquals("a speed off the menu is kept as a step on it", 2.5, AudioRate.remembered(first, defaults), 0.0)
    }

    // MARK: the sleep timer

    @Test fun sleepTimer() {
        assertTrue("the menu has the six times and the end of the section",
            SleepChoice.all.size == 7 && SleepChoice.all.last() == SleepChoice.EndOfSection)

        val timer = SleepCountdown.of(SleepChoice.Minutes(15))!!
        assertEquals("fifteen minutes is 900 seconds", 900.0, timer.remaining, 0.0)
        assertEquals("full volume to begin with", 1f, timer.volume)
        assertEquals("the chip counts down in minutes and seconds", "15:00", timer.label)
        timer.advance(1.0)
        assertTrue("a second heard is a second off: ${timer.label}", timer.remaining == 899.0 && timer.label == "14:59")
        timer.advance(600.0)
        assertEquals("a long gap - the app was not running - takes off no more than a few seconds",
            899 - SleepCountdown.maxStep, timer.remaining, 0.0)
        timer.advance(-3.0)
        timer.advance(Double.NaN)
        assertEquals("time never runs backwards", 899 - SleepCountdown.maxStep, timer.remaining, 0.0)
        assertEquals("checks once a second while far from the end", 1.0, timer.nextCheck, 0.0)

        val ending = SleepCountdown.of(SleepChoice.Minutes(1))!!
        repeat(50) { ending.advance(1.0) }
        assertTrue("the last ten seconds are when it checks often: ${ending.nextCheck}", ending.nextCheck == 0.1 && !ending.isDone)
        assertTrue("it never sleeps past the start of the fade", SleepCountdown.of(SleepChoice.Minutes(1))!!.nextCheck <= 1)
        assertEquals("still loud until the fade", 1f, ending.volume)
        ending.advance(5.0)
        assertEquals("half way through the fade is a quarter of the volume", 0.25f, ending.volume)
        repeat(10) { ending.advance(1.0) }
        assertTrue("then it is done, and silent", ending.isDone && ending.volume == 0f)

        val curve = generateSequence(10.0) { it - 0.5 }.takeWhile { it >= 0.0 }.map { SleepCountdown.volume(it) }.toList()
        assertTrue("the fade only ever gets quieter: $curve", curve.zipWithNext().all { (a, b) -> a >= b })
        assertTrue("the fade starts at full volume and ends at none", curve.first() == 1f && curve.last() == 0f)

        assertNull("the end of a section with no end known cannot be set", SleepCountdown.of(SleepChoice.EndOfSection))
        val section = SleepCountdown.of(SleepChoice.EndOfSection, 120.0)!!
        assertEquals("the end of this section starts from the player's own count", 120.0, section.remaining, 0.0)
        section.advance(1.0)
        section.follow(200.0)
        assertEquals("a scrub back gives the time back", 200.0, section.remaining, 0.0)
        section.follow(-4.0)
        assertTrue("past the end is done", section.isDone)
    }

    // MARK: chapters - from headings

    @Test fun chaptersFromHeadings() {
        val typed = listOf(
            "Today: acid-base in three systems.",
            "# Buffers",
            "Buffers act in seconds.",
            "The bicarbonate buffer is the one you'll use most.",
            "# The lungs",
            "The lungs act in minutes.",
            "A rise in CO2 lowers pH.",
            "Slide 7: The kidneys",
            "The kidneys act over days.",
            "They reabsorb bicarbonate.",
        )
        val fromHeadings = AudioChapters.derive(typed)
        assertEquals("a section at every heading, and one for the opening",
            listOf(0 until 1, 1 until 4, 4 until 7, 7 until 10), fromHeadings.map { it.lines })
        assertEquals("headings are the sections' names",
            listOf("Today: acid-base in three systems", "Buffers", "The lungs", "Slide 7: The kidneys"), fromHeadings.map { it.title })
        assertTrue("a typed lecture has no times", fromHeadings.all { it.start == null })

        assertEquals("a Markdown heading is a heading", "Renal tubular acidosis", AudioChapters.heading("## Renal tubular acidosis"))
        assertEquals("a short line ending in a colon is a heading", "Management", AudioChapters.heading("Management:"))
        assertEquals("Part two is a heading", "Part two", AudioChapters.heading("Part two"))
        assertTrue("Section B and Chapter IV are headings",
            AudioChapters.heading("Section B") == "Section B" && AudioChapters.heading("Chapter IV") == "Chapter IV")
        assertEquals("Slide 12 is a heading in a recording too", "slide 12 the nephron", AudioChapters.heading("slide 12 the nephron", timed = true))
        assertNull("a sentence that starts with Part is not a heading", AudioChapters.heading("part of the reason is the kidneys", timed = true))
        assertEquals("Topic: with its colon is a heading", "topic: the kidneys", AudioChapters.heading("topic: the kidneys", timed = true))
        assertNull("nor one that starts with Lecture", AudioChapters.heading("lecture notes are online after this", timed = true))
        assertEquals("a short capitalised line with no full stop is a heading in typed notes",
            "Clinical features", AudioChapters.heading("Clinical features"))
        assertNull("but not in a recording's transcript, which may have no punctuation at all",
            AudioChapters.heading("Clinical features", timed = true))
        assertNull("a sentence is not a heading", AudioChapters.heading("Buffers act in seconds."))
        assertNull("a long line is not a heading",
            AudioChapters.heading("The kidneys compensate slowly by reabsorbing more bicarbonate over days"))
        assertNull("Arabic has no capitals, so only a marker makes it a heading", AudioChapters.heading("العلاج"))

        val doubled = listOf("# Renal", "## Acid-base", "Line one.", "Line two.", "Line three.", "# Next", "More.", "And more.")
        val merged = AudioChapters.derive(doubled)
        assertTrue("a heading and its subheading start one section, under the first: ${merged.map { it.lines }}",
            merged.map { it.lines } == listOf(0 until 5, 5 until 8) && merged.firstOrNull()?.title == "Renal")

        val listy = listOf("Causes:", "Drugs:", "Sepsis.", "Trauma:", "Burns:", "Other.")
        assertTrue("headings on most lines are a list, not sections", AudioChapters.derive(listy).isEmpty())
    }

    // MARK: chapters - a recording with no headings

    @Test fun chaptersFromARecording() {
        // forty minutes, a line every 20 s, a long pause before line 45 and a "So now" at line 61
        val said = ArrayList<String>()
        val starts = ArrayList<Double?>()
        val ends = ArrayList<Double?>()
        for (i in 0 until 120) {
            val turn = i == 61
            said.add(if (turn) "So now the kidneys, which take days" else "and this is line $i of what was said")
            val t = i * 20.0 + (if (i >= 45) 8 else 0)
            starts.add(t)
            ends.add(t + 17)
        }
        val recorded = AudioChapters.derive(said, starts, ends)
        assertEquals("a forty-minute recording is cut into sections of about five minutes", 8, recorded.size)
        assertEquals("every line is in exactly one section, in order", (0 until 120).toList(), recorded.flatMap { it.lines.toList() })
        assertTrue("each section starts when its first line does", recorded.all { it.start == starts[it.lines.first] })
        assertTrue("a cut falls at the long pause: ${recorded.map { it.lines.first }}", recorded.any { it.lines.first == 45 })
        assertTrue("a cut falls at the line that turns to something new: ${recorded.map { it.lines.first }}", recorded.any { it.lines.first == 61 })
        assertTrue("no section is tiny: ${recorded.map { it.lines.count() }}", recorded.all { it.lines.count() >= 5 })
        assertEquals("a section is named by its first words", "and this is line 0 of…", recorded[0].title)

        val untimedStarts: List<Double?> = List(said.size) { null }
        val untimed = AudioChapters.derive(said, untimedStarts, untimedStarts)
        assertTrue("a transcript with no times is cut by its length read aloud: ${untimed.size}",
            untimed.size >= 2 && untimed.all { it.start == null })

        val brief = listOf("One short line.", "Another short line.", "And a third.")
        assertTrue("a short lecture with no headings is one section", AudioChapters.derive(brief).isEmpty())
        assertTrue("a single line is one section", AudioChapters.derive(listOf("Just this.")).isEmpty())
    }

    // MARK: where am I

    @Test fun whereAmI() {
        val marks = listOf(
            AudioChapter("A", 0 until 4, 0.0),
            AudioChapter("B", 4 until 9, 100.0),
            AudioChapter("C", 9 until 12, 250.0),
        )
        assertEquals("the section at a moment", 1, AudioChapters.indexAtTime(120.0, marks))
        assertEquals("at the very start of a section, that section", 1, AudioChapters.indexAtTime(100.0, marks))
        assertEquals("before the first, the first", 0, AudioChapters.indexAtTime(-1.0, marks))
        assertEquals("past the last start, the last", 2, AudioChapters.indexAtTime(9_999.0, marks))
        assertNull("no sections, no section", AudioChapters.indexAtTime(5.0, emptyList()))
        assertEquals("the section a line is in", 1, AudioChapters.indexContainingLine(8, marks))
        assertEquals("its last line too", 2, AudioChapters.indexContainingLine(11, marks))
        assertEquals("a section ends where the next starts", 250.0, AudioChapters.end(120.0, marks, 400.0), 0.0)
        assertEquals("the last ends with the recording", 400.0, AudioChapters.end(300.0, marks, 400.0), 0.0)
        assertEquals("Back well into a section goes to its start", 1, AudioChapters.previousFromTime(150.0, marks))
        assertEquals("Back just after a section starts goes to the one before", 0, AudioChapters.previousFromTime(101.0, marks))
        assertEquals("Back in the first section goes to its start", 0, AudioChapters.previousFromTime(1.0, marks))
        assertEquals("Back by line: mid-section to its start", 1, AudioChapters.previousFromLine(6, marks))
        assertEquals("Back by line: on the first line, the one before", 0, AudioChapters.previousFromLine(4, marks))
        assertEquals("Next goes to the section after", 2, AudioChapters.next(1, marks))
        assertNull("there is no next after the last", AudioChapters.next(2, marks))
        assertEquals("the lock screen's words", "Section 2 of 3", AudioChapters.position(1, marks))

        val reading = listOf("one two three four five", "six seven eight nine ten", "eleven twelve")
        assertEquals("ten words at 150 a minute is four seconds", 4.0, AudioChapters.secondsToRead(reading, 0, 0, 2, 1.0), 0.0)
        assertEquals("twice as fast, half the time", 2.0, AudioChapters.secondsToRead(reading, 0, 0, 2, 2.0), 0.0)
        assertEquals("the words already said do not count, but it is never quite zero", 1.0,
            AudioChapters.secondsToRead(reading, 1, 3, 2, 1.0), 0.0)
        assertEquals("once there, zero", 0.0, AudioChapters.secondsToRead(reading, 2, 0, 2, 1.0), 0.0)
        assertNotNull(marks)
        assertFalse(marks.isEmpty())
    }
}
