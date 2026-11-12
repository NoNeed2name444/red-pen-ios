package com.stethoscore.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// TextSlicing.words, nearest and nearestPages (the lecture excerpt a checker is
// shown): the cases of ios/RedPen/Tests/LLMTests.swift lines 75-103, one test
// each, plus the edges Swift's String gives for free (a surrogate pair is
// never cut in two).
class TextSlicingTest {

    private val lecture = listOf(
        "Asthma is reversible airway obstruction. Salbutamol relieves bronchospasm.",
        "Heart failure: furosemide for congestion, ACE inhibitors reduce mortality.",
        "Diabetes: metformin first line, HbA1c target 48 mmol/mol.",
    ).joinToString("\n\n")

    // iOS LLMTests:79 - "the matching paragraph is chosen"
    @Test fun theMatchingParagraphIsChosen() {
        val near = TextSlicing.nearest(lecture, "Which drug reduces mortality in heart failure? ACE inhibitors", 90)
        assertTrue(near, near.contains("ACE inhibitors") && !near.contains("metformin"))
    }

    // iOS LLMTests:80 - "a short source is used whole"
    @Test fun aShortSourceIsUsedWhole() {
        assertEquals(lecture, TextSlicing.nearest(lecture, "anything", 10_000))
    }

    // iOS LLMTests:81 - "no overlap falls back to the start, within the limit"
    @Test fun noOverlapFallsBackToTheStartWithinTheLimit() {
        val out = TextSlicing.nearest(lecture, "zzzz qqqq", 20)
        assertEquals(20, out.length)
        assertTrue(lecture.startsWith(out))
    }

    private val wordLines: String = ((1..300).map { "Line $it about renal physiology and tubular transport." } +
        "Furosemide blocks the NKCC2 cotransporter in the thick ascending limb." +
        (1..300).map { "Line $it about cardiac output and preload." }).joinToString("\n")

    // iOS LLMTests:93-97 - a Word lecture is one page with a line per paragraph
    @Test fun aOnePageWordLectureOverTheBudgetIsStillUsedAtTheMatchingLine() {
        val fromWord = TextSlicing.nearestPages(listOf("Diuretics, 1:\n" to wordLines), "Which cotransporter does furosemide block?", 8_000)
        assertTrue("the Word page really is bigger than the budget", wordLines.length > 8_000)
        assertNotNull(fromWord)
        assertTrue(fromWord!!.contains("NKCC2"))
        assertTrue("and stays within the budget", fromWord.length <= 8_000)
        assertTrue("with its page named", fromWord.startsWith("Diuretics, 1:"))
    }

    // iOS LLMTests:98 - "nearest picks a line out of one long paragraph"
    @Test fun nearestPicksALineOutOfOneLongParagraph() {
        assertTrue(TextSlicing.nearest(wordLines, "furosemide cotransporter", 500).contains("NKCC2"))
    }

    // iOS LLMTests:99-102 - "the best page comes first"
    @Test fun theBestPageComesFirst() {
        val two = TextSlicing.nearestPages(
            listOf("L, 1:\n" to "Asthma: salbutamol relieves bronchospasm.", "L, 2:\n" to "Heart failure: furosemide for congestion."),
            "furosemide in heart failure", 1_000)
        assertNotNull(two)
        assertTrue(two!!, two.startsWith("L, 2:"))
    }

    // iOS LLMTests:103 - "no shared word, no reference"
    @Test fun noSharedWordNoReference() {
        assertNull(TextSlicing.nearestPages(listOf("L, 1:\n" to "Asthma."), "zzzz qqqq", 1_000))
    }

    @Test fun aPageThatSharesNoWordIsLeftOutBesideOneThatDoes() {
        val out = TextSlicing.nearestPages(listOf("A, 1:\n" to "Asthma.", "A, 2:\n" to "Furosemide dosing in heart failure."), "furosemide dosing", 1_000)
        assertEquals("A, 2:\nFurosemide dosing in heart failure.\n\n", out)
    }

    @Test fun lessRoomThanAPageIsWorthEndsTheSearch() {
        // limit 100: a page needs at least 25 characters of room after its heading; the best page leaves 24
        val best = "furosemide heart " + "x".repeat(43)
        val out = TextSlicing.nearestPages(listOf("L, 1:\n" to "furosemide", "L, 2:\n" to best), "furosemide heart", 100)
        assertEquals("L, 2:\n$best\n\n", out)
    }

    @Test fun wordsAreLongerThanThreeCharactersAndLowerCased() {
        assertEquals(setOf("furosemide", "congestion", "hba1c", "mmol", "drug"), TextSlicing.words("Furosemide for congestion, HbA1c 48 mmol/mol; ACE is a drug."))
    }

    @Test fun aWordKeepsItsAccentsAndItsLengthCountsCharactersNotMarks() {
        // "café" is four characters in either form; "cafe" plus a combining acute is still four
        assertEquals(setOf("café"), TextSlicing.words("café"))
        assertEquals(setOf("café"), TextSlicing.words("café"))
        assertTrue(TextSlicing.words("caé").isEmpty())
    }

    @Test fun anExcerptNeverEndsInHalfASurrogatePair() {
        // an emoji is two UTF-16 units; the limit falls between them
        val source = "ab" + "😀" + "cd"
        val out = TextSlicing.nearest(source, "zzzz", 3)
        assertEquals("ab", out)
        assertFalse(Character.isHighSurrogate(out.last()))
    }
}
