package com.stethoscore.app.audio

import com.stethoscore.app.data.NarrateScheduler
import com.stethoscore.app.data.StudyJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject
import kotlin.math.abs

// ios/RedPen/Tests/TranscriberTests.swift (fed0105), case for case: where a
// recording becomes readable lines, and whether the highlight lands on the
// word actually being spoken. The recogniser itself is not tested - it needs
// a device; what is tested is everything the app decides.
//
// Also the parts of CloudTranscriptTests.swift that are not Gemini's (the
// recogniser's terms, the language's recogniser, a saved line's model): the
// rest of that suite is the cloud transcriber's, which Android does not have.
class TranscriberTest {
    private fun say(text: String, start: Double, dur: Double = 0.3) = LectureTranscriber.SpokenWord(text, start, dur)

    // A lecturer speaking, pausing, then speaking again.
    private val spoken = listOf(
        say("the", 0.0), say("malar", 0.35), say("rash", 0.7),
        say("spares", 1.05), say("the", 1.4), say("nasolabial", 1.75), say("folds", 2.2),
        // a breath
        say("that", 3.2), say("is", 3.55), say("how", 3.9),
        say("you", 4.25), say("tell", 4.6), say("it", 4.95), say("from", 5.3),
        say("rosacea", 5.65),
    )
    private val lines = LectureTranscriber.lines(spoken)

    @Test fun lines() {
        assertEquals("a pause ends a line", 2, lines.size)
        assertEquals("the first line is what was said before the pause", "the malar rash spares the nasolabial folds", lines.first().text)
        assertTrue("a line starts when its first word does", lines.first().start == 0.0 && lines.last().start == 3.2)
        assertTrue("a line ends when its last word does: ${lines.first().end}", abs(lines.first().end - 2.5) < 0.0001)
        assertEquals("no word is lost at a break", spoken.size, lines.sumOf { it.words.size })

        // An unbroken stretch still has to end somewhere, or it becomes a paragraph.
        val gabble = (0 until 40).map { say("word", it * 0.3) }
        val chopped = LectureTranscriber.lines(gabble)
        assertTrue("speech with no pause is still broken into lines: ${chopped.size}", chopped.size >= 3)
        assertTrue("and no line runs past the limit: ${chopped.map { it.words.size }}",
            chopped.all { it.words.size <= LectureTranscriber.maxWordsPerLine })

        assertTrue("silence transcribes to nothing rather than an empty line", LectureTranscriber.lines(emptyList()).isEmpty())
    }

    // MARK: the word clock the player runs on

    @Test fun theWordClock() {
        val timings = LectureTranscriber.timings(lines)
        val words = WordTiming.layout(lines.map { it.text }, lines.map { it.end }, timings)
        assertEquals("every spoken word reaches the player", spoken.size, words.size)
        assertTrue("the recogniser's own times are used, not estimates", words.all { it.source == TimingSource.measured })

        // the point of the whole exercise: the right word at the right moment
        assertEquals("the highlight is on the word being said", "nasolabial", WordTiming.word(1.9, words)?.text)
        assertEquals("and on the last word of the lecture at the end", "rosacea", WordTiming.word(5.8, words)?.text)
        // during the breath there is no word being spoken; the player should hold the last one rather than blink the highlight off
        assertEquals("a pause holds the last word rather than going blank", "folds", WordTiming.word(2.9, words)?.text)
        assertNull("before the lecture starts nothing is highlighted", WordTiming.word(-1.0, words))

        // A partly-timed phrase must not throw the rest of the line away.
        val partly = WordTiming.words("one two three", 0, 0.0, 3.0, listOf(MeasuredWord("one", 0.0, 0.8)))
        assertTrue("an untimed remainder is estimated, not dropped: ${partly.map { it.source }}",
            partly.size == 3 && partly[0].source == TimingSource.measured && partly[2].source == TimingSource.estimated)
    }

    // MARK: what a lecture transcript then goes through

    @Test fun learnedCorrectionsApplyToAFreshTranscript() {
        // The learned table is applied to a fresh transcript, which is what makes a correction made last week show up already fixed this week.
        val heard = "ميكوكوتينيوس"
        val table = PronunciationStore()
        table.add(SoundKey.of(heard), "mucocutaneous", heard, Evidence.correction)
        val fresh = mutableListOf("ده $heard تاني")
        val fixed = TranscriptCorrections.applyLearned(table, fresh)
        assertTrue("last week's correction is already applied to this week's lecture: ${fresh[0]}",
            fixed == 1 && fresh[0].contains("mucocutaneous"))
    }

    // MARK: from CloudTranscriptTests: what is not Gemini's

    @Test fun recogniserTermsAndLanguage() {
        val distinct = (0 until 150).map { "term$it" }
        assertTrue("recogniser terms keep order, omit empties and case repeats, and stop at 100",
            LectureTranscriber.recogniserTerms(listOf("", "Fibrillation", "fibrillation", "", "Anticoagulation", "FIBRILLATION")) ==
                listOf("Fibrillation", "Anticoagulation") && LectureTranscriber.recogniserTerms(distinct) == distinct.take(100))
        assertTrue("no slides, no recogniser terms", LectureTranscriber.recogniserTerms(emptyList()).isEmpty())
        assertTrue("an English lecture is heard by the English recogniser",
            LectureLanguage.english.locale == "en-US" && LectureLanguage.mixed.locale == "ar-EG")

        val heard = listOf(LectureTranscriber.Line("hi there", 0.0, 1.0, listOf(say("hi", 0.0), say("there", 0.5)), model = "gemini-3.5-flash-lite"))
        val kept = NarrateScheduler.segments(heard, "ar")
        assertTrue("and so does the saved transcript", kept.all { it.model == "gemini-3.5-flash-lite" })
        val saved = StudyJson.decodeSet(JSONObject("""{"id":"s","name":"n","kind":"narrate","narrateSegments":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"hi","lang":"en"}]}"""))
        assertTrue("a line saved before models were kept still opens",
            saved?.narrateSegments?.firstOrNull()?.let { it.text == "hi" && it.model == null } == true)
        assertEquals("the measured words are the saved ones", listOf(listOf(MeasuredWord("hi", 0.0, 0.3), MeasuredWord("there", 0.5, 0.8))),
            NarrateScheduler.measured(kept))
        assertNull("a transcript with no word times has none", NarrateScheduler.measured(saved?.narrateSegments ?: emptyList()))
    }
}
