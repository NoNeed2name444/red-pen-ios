package com.stethoscore.app.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

// ios/RedPen/Tests/LearningTests.swift (fed0105), case for case: the sound
// key, the pronunciation store, fixing a word, and the word clock.
//
// The sound keys must equal the values sound() in consensus.py produces for
// the same tokens: a table learned on the phone is read by the committee and
// one learned by the committee is read by the phone.
class LearningTest {

    // MARK: the sound key

    @Test fun theSoundKey() {
        val arabicReversible = "ريفرسبل"
        assertEquals("an Arabic and an English spelling of one sound match", SoundKey.of("reversible"), SoundKey.of(arabicReversible))
        assertEquals("the definite article does not change the sound",
            SoundKey.of("مالار"), SoundKey.of("الـمالار"))
        assertEquals("a ta-marbuta and a ha are the same word",
            SoundKey.of("مميزة"), SoundKey.of("مميزه"))
        assertNotEquals("different words stay different", SoundKey.of("علم"), SoundKey.of("فهم"))

        // A known, deliberate collision, asserted so nobody "fixes" it by accident:
        // qaf and kaf are both k in this scheme, so heart and dog are one sound.
        assertTrue("qaf and kaf collide, exactly as they do in Python: ${SoundKey.of("قلب")} / ${SoundKey.of("كلب")}",
            SoundKey.of("قلب") == "klb" && SoundKey.of("كلب") == "klb")
        assertEquals("a split word and a joined one meet once the seam is closed",
            SoundKey.collapsed(SoundKey.of("mucocutaneous")),
            SoundKey.collapsed(SoundKey.of(listOf("ميكو", "كوتينيوس"))))
    }

    // MARK: the store

    private val acuteHeard = "اكيوت"
    private val acuteLine = "ده اكيوت جدا"

    @Test fun theStore() {
        val store = PronunciationStore()
        assertTrue("a correction is trusted at once", store.add(SoundKey.of(acuteHeard), "acute", acuteHeard, Evidence.correction))
        assertTrue("and is then applied: ${store.apply(acuteLine).text}", store.apply(acuteLine).text.contains("acute"))

        // one sighting of repetition is not enough to rewrite anything
        val weak = PronunciationStore()
        weak.add("tst", "test", "تست", Evidence.repetition)
        assertTrue("one repetition is not yet trusted: ${weak.entries["tst"]?.counts}", weak.entries["tst"]?.isTrusted == false)
        repeat(2) { weak.add("tst", "test", "تست", Evidence.repetition) }
        assertTrue("three repetitions are", weak.entries["tst"]?.isTrusted == true)

        // a guess must never displace a person's own spelling
        val fought = PronunciationStore()
        fought.add("rsk", "risk", "رسك", Evidence.correction)
        fought.add("rsk", "rosacea", "رسك", Evidence.repetition)
        assertEquals("a weaker guess cannot overwrite a correction", "risk", fought.spelling(listOf("رسك")))

        // the table is the same one the pipeline reads and writes
        val round = PronunciationStore.fromTSV(store.tsv())
        assertEquals("the table survives a round trip through TSV: ${round.tsv()}", "acute", round.spelling(listOf(acuteHeard)))
    }

    // MARK: fixing a word

    @Test fun fixingAWord() {
        val segments = mutableListOf(acuteLine, "والـاكيوت تاني")
        val snapshot = segments.toList()
        val learning = PronunciationStore()
        val outcome = TranscriptCorrections.fix(0, 1..1, "acute", segments, learning)
        assertTrue("the word the student tapped is fixed: ${segments[0]}", segments[0].contains("acute"))
        assertTrue("the same mistake elsewhere is fixed too: ${segments[1]}", segments[1].contains("acute"))
        assertTrue("the lecturer's article is kept: ${segments[1]}", segments[1].contains("الـ acute"))
        assertTrue("the spread is reported rather than silent: ${outcome.summary()}",
            outcome.elsewhere.size == 1 && outcome.summary().contains("1 more like it"))
        assertTrue("and it was remembered", outcome.learned)

        TranscriptCorrections.undo(snapshot, segments, outcome)
        assertEquals("one undo puts all of it back", snapshot, segments)

        // the same mistake twice in ONE line must not shift the splice off the word that was actually tapped
        val twice = mutableListOf("$acuteHeard ده $acuteHeard")
        val store2 = PronunciationStore()
        val twiceOut = TranscriptCorrections.fix(0, 2..2, "acute", twice, store2)
        assertEquals("both occurrences end up fixed, none skipped: ${twice[0]}", 2, twice[0].split(" ").count { it == "acute" })
        assertTrue("the tapped word is the one reported as here", twiceOut.here != null)
    }

    // MARK: the word clock

    @Test fun theWordClock() {
        val words = WordTiming.layout(listOf("one two three", "four five"), listOf(3.0, 5.0))
        assertEquals("every word gets a slot", 5, words.size)
        assertTrue("the words run in order", words.zipWithNext().all { (a, b) -> a.end <= b.start + 0.0001 })
        assertTrue("an estimate says it is an estimate", words.all { it.source == TimingSource.estimated })
        assertTrue("the phrase ends where it was told to: ${words.lastOrNull()?.end}", abs((words.lastOrNull()?.end ?: 0.0) - 5.0) < 0.0001)
        assertEquals("the word at a moment is found", "one", WordTiming.word(0.1, words)?.text)

        val measured = WordTiming.words("one two", 0, 0.0, 2.0, listOf(MeasuredWord("one", 0.0, 0.8), MeasuredWord("two", 0.8, 1.9)))
        assertTrue("a measured time is used as given", measured.all { it.source == TimingSource.measured } && measured[1].end == 1.9)

        val partial = WordTiming.words("one two three", 0, 0.0, 3.0, listOf(MeasuredWord("one", 0.0, 0.8)))
        assertTrue("a partly timed phrase keeps what was measured and estimates the rest: ${partial.map { it.source }}",
            partial.size == 3 && partial[0].source == TimingSource.measured && partial[1].source == TimingSource.estimated)

        assertTrue("an Arabic word is not rushed: ${WordTiming.weight("مكتب")} vs ${WordTiming.weight("desk")}",
            WordTiming.weight("مكتب") > WordTiming.weight("desk"))
    }
}
