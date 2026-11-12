package com.stethoscore.app.quiz

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// What the writer is told and what is taken back: the brief, the item as the
// writer sees it, the differential as text, and the acceptance rule's edges.
// A port of the writer half of ios/RedPen/Shared/Exam/AttendingHint.swift
// (instructions, input) and Models/Differential.swift (checkText); the leak
// rule, the fallback and the cache keep their cases in ExamToolsTest.
class AttendingHintTest {
    private val stem = "A 30-year-old woman has heat intolerance, a diffuse goitre and exophthalmos."
    private val options = listOf("Graves disease", "Toxic multinodular goitre", "Subacute thyroiditis", "Hashimoto thyroiditis")
    private val answer = options[0]
    private val others = options.drop(1)

    private val tiers = DifferentialTiers(
        mostLikely = listOf(DifferentialEntry("Graves disease", supporting = listOf("Exophthalmos", "Heat intolerance"), test = "TSH receptor antibodies")),
        expanded = listOf(DifferentialEntry("Toxic multinodular goitre", against = listOf("A diffuse, not nodular, goitre"))),
        cantMiss = listOf(DifferentialEntry("Thyroid storm")),
    )

    @Test fun theBriefIsTheOneIosGives() {
        val expected = "You are an experienced attending physician teaching a medical student at the bedside.\n" +
            "The student is stuck on the question below. Give ONE short Socratic nudge - the next reasoning step: which finding matters most and what it points towards in general terms, or which category of option it rules out.\n" +
            "NEVER name, paraphrase, abbreviate or hint at the wording of the correct answer, and never say which option letter is right. Do not list the options back.\n" +
            "At most two sentences, plain text, no preamble."
        assertEquals(expected, AttendingHint.instructions)
    }

    @Test fun theItemIsShownWithItsAnswerMarkedNeverToReveal() {
        val expected = "Question:\n$stem\n\nOptions:\n- Graves disease\n- Toxic multinodular goitre\n- Subacute thyroiditis\n- Hashimoto thyroiditis\n\n" +
            "Correct answer (NEVER reveal it): Graves disease"
        assertEquals(expected, AttendingHint.input(stem, options, answer, null))
        assertEquals("an empty differential adds nothing", expected, AttendingHint.input(stem, options, answer, DifferentialTiers()))
    }

    @Test fun theDifferentialFollowsWhenThereIsOne() {
        val input = AttendingHint.input(stem, options, answer, tiers)
        val expectedTail = "\n\nThe expert's differential:\n" +
            "- Most likely: Graves disease (for: Exophthalmos, Heat intolerance; test: TSH receptor antibodies)\n" +
            "- Expanded: Toxic multinodular goitre (against: A diffuse, not nodular, goitre)\n" +
            "- Can’t miss: Thyroid storm"
        assertTrue(input, input.endsWith("Correct answer (NEVER reveal it): Graves disease$expectedTail"))
    }

    @Test fun anEmptyTierIsLeftOutOfTheText() {
        assertEquals("- Can’t miss: Aortic dissection (for: Tearing pain; against: Symmetrical pulses; test: CT angiogram)",
            DifferentialTiers(cantMiss = listOf(DifferentialEntry("Aortic dissection", listOf("Tearing pain"), listOf("Symmetrical pulses"), "CT angiogram"))).checkText)
        assertEquals("", DifferentialTiers().checkText)
    }

    @Test fun aReplyIsTidiedToTheNudgeItself() {
        val nudge = "What does eye involvement tell you about the cause?"
        assertEquals(nudge, AttendingHint.accept("  Hint: $nudge \n", answer, stem, others))
        assertEquals(nudge, AttendingHint.accept("hint: $nudge", answer, stem, others))
        assertEquals(nudge, AttendingHint.accept("Nudge: $nudge", answer, stem, others))
        assertEquals(nudge, AttendingHint.accept("Attending: $nudge", answer, stem, others))
        assertEquals(nudge, AttendingHint.accept("“$nudge”", answer, stem, others))
        assertEquals(nudge, AttendingHint.accept("\"$nudge\"", answer, stem, others))
    }

    @Test fun aReplyTooShortToBeANudgeIsRefused() {
        assertNull(AttendingHint.accept("", answer, stem, others))
        assertNull(AttendingHint.accept("Hint:   ", answer, stem, others))
        assertNull("11 characters", AttendingHint.accept("Look closer", answer, stem, others))
        assertEquals("12 characters", "Look closely", AttendingHint.accept("Look closely", answer, stem, others))
    }

    @Test fun aLongReplyIsCutAt400WithAnEllipsis() {
        val sentence = "Which finding here points away from a nodule? "
        val long = sentence.repeat(20)
        val cut = AttendingHint.accept(long, answer, stem, others)
        assertNotNull(cut)
        assertEquals(401, cut!!.length)
        assertTrue(cut.endsWith("…"))
        assertEquals(long.trim().take(400), cut.dropLast(1))
        // counted in characters a person sees, not UTF-16 units: a pair is never split
        val emoji = AttendingHint.accept("a".repeat(399) + "🙂🙂", answer, stem, others)
        assertEquals("a".repeat(399) + "🙂…", emoji)
    }

    @Test fun aReplyThatNamesTheAnswerIsRefusedWhateverItsWrapping() {
        assertNull(AttendingHint.accept("Hint: it's Graves disease.", answer, stem, others))
        assertNull(AttendingHint.accept("“Think about Graves.”", answer, stem, others))
        assertNull(AttendingHint.accept("Nudge: this is hyperthyroid in origin.", "Hyperthyroidism", "Tired woman.", listOf("Anaemia")))
    }

    @Test fun theFallbackPassesOverAFindingThatNamesTheAnswer() {
        val named = DifferentialTiers(
            mostLikely = listOf(DifferentialEntry("Graves disease", supporting = listOf("Exophthalmos"))),
            expanded = listOf(DifferentialEntry("Toxic multinodular goitre", against = listOf("Positive Graves antibodies"))),
        )
        val line = AttendingHint.fallback(answer, stem, options, named)
        assertTrue(line, line.startsWith("The finding that carries this question is exophthalmos."))
        assertFalse(AttendingHint.leaks(line, answer, stem, others))
    }

    @Test fun theFallbackNeverNamesAnyOptionAsTheAnswer() {
        for (withTiers in listOf(tiers, null)) {
            for (i in options.indices) {
                val shown = options[i]
                val rest = options.filter { it != shown }
                val line = AttendingHint.fallback(shown, stem, options, withTiers)
                assertFalse("$shown: $line", AttendingHint.leaks(line, shown, stem, rest))
            }
        }
    }
}
