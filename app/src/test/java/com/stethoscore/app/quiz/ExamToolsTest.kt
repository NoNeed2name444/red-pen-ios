package com.stethoscore.app.quiz

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.util.UUID

// A port of upstream/ios/RedPen/Tests/ExamToolsTests.swift: the twins, the
// attending's hint, the calculator, the reference ranges and the highlighter
// pieces, case for case. Its first three parts (paper formats, assembly and
// marking of a mock paper) test MockFormat and MockAssembler, which come with
// the mock paper (parity batch 11) and are ported there.
class ExamToolsTest {
    private fun id() = UUID.randomUUID().toString()

    @Test fun twins() {
        var queue = TwinQueue()
        val utc = ZoneId.of("UTC")
        val midnight = (1_000_000L - 1_000_000L % 86_400L) * 1000
        val now = midnight + 21 * 3_600_000L // nine in the evening
        val parent = id()
        val twin = id()
        queue = queue.add(twin, parent, now, confident = true, zone = utc)
        assertEquals("a confident mistake's twin is due the next day, from its start", midnight + 86_400_000L, queue.entries.first().dueAt)
        assertEquals("so an evening miss is ready the next morning", listOf(twin), queue.due(midnight + (86_400 + 7 * 3_600) * 1000L).map { it.id })
        assertTrue("not due at once", queue.due(now).isEmpty())
        assertEquals("due the next day", listOf(twin), queue.due(now + 90_000_000L).map { it.id })
        assertTrue("the question has a twin on the way", queue.hasTwin(parent))
        val twin2 = id()
        queue = queue.add(twin2, parent, now, guessed = true, zone = utc)
        assertEquals("one waiting twin per missed question", listOf(twin2), queue.waiting.map { it.id })
        assertEquals("a guess waits three days", midnight + 3 * 86_400_000L, queue.entries.first().dueAt)
        val later = now + 4 * 86_400_000L
        queue = queue.answered(twin2, correct = false, now = later, zone = utc)
        assertEquals("a missed twin comes back a day later", listOf(twin2), queue.due(later + 86_400_000L).map { it.id })
        queue = queue.answered(twin2, correct = true, now = later + 86_400_000L)
        assertTrue("a twin got right leaves the queue", queue.waiting.isEmpty() && queue.isTwin(twin2))
        queue = queue.prune(emptySet())
        assertTrue("twins gone from the library are forgotten", queue.entries.isEmpty())
        assertEquals("the re-test comes a few questions on", 6, TwinRetest.slot(2, 20))
        assertEquals("or at the end", 20, TwinRetest.slot(18, 20))
        val qa = id(); val qb = id(); val qc = id()
        assertEquals("a re-test is not a first showing", listOf(0, 1, 3), TwinRetest.firstShowings(listOf(qa, qb, qa, qc)))
        val folded = TwinRetest.collapse(listOf(qa, qb, qa, qc), listOf("miss", "right", "retest", ""),
            listOf(listOf(0, 1), listOf(1, 0), listOf(1, 0), listOf(0, 1)), current = 3)
        assertEquals("a re-test is left out of the answers kept", listOf("miss", "right", ""), folded.answers)
        assertEquals("its option order goes with it", listOf(listOf(0, 1), listOf(1, 0), listOf(0, 1)), folded.orders)
        assertEquals("the place is the set's own: question 3", 2, folded.current)
        assertEquals("standing on the re-test resumes at the next of the set's own", 2,
            TwinRetest.collapse(listOf(qa, qb, qa, qc), listOf("a", "b", "c", "d"), listOf(emptyList(), emptyList(), emptyList(), emptyList()), current = 2).current)

        val input = TwinPrompt.input("A 24-year-old woman has palpitations.", listOf("Graves disease", "Toxic adenoma"),
            correctIndex = 0, explanation = "Diffuse uptake.", picked = 1, reason = "Mixed up lookalikes")
        assertTrue("the twin prompt carries the answer, the choice and the reason",
            input.contains("Correct answer: Graves disease") && input.contains("chose: Toxic adenoma") && input.contains("lookalikes"))
        assertTrue("the same stem again is too close",
            TwinPrompt.isTooClose("A 24-year-old woman has palpitations and weight loss.", "A 24-year-old woman has palpitations and weight loss today."))
        assertTrue("a new patient is not",
            !TwinPrompt.isTooClose("A 61-year-old man with tremor and a goitre sees his GP.", "A 24-year-old woman has palpitations and weight loss."))
    }

    @Test fun attendingHint() {
        val stem = "A 30-year-old woman has heat intolerance, a diffuse goitre and exophthalmos."
        val options = listOf("Graves disease", "Toxic multinodular goitre", "Subacute thyroiditis", "Hashimoto thyroiditis")
        val others = options.drop(1)
        assertTrue("naming the answer leaks", AttendingHint.leaks("Think of Graves disease.", options[0], stem, others))
        assertTrue("its distinctive word leaks", AttendingHint.leaks("Could this be Graves?", options[0], stem, others))
        assertTrue("a nudge about the eyes does not",
            !AttendingHint.leaks("Which finding here is not explained by a nodule - look at the eyes.", options[0], stem, others))
        assertTrue("a word shared with other options is not a leak",
            !AttendingHint.leaks("Which kind of thyroiditis would be painful?", "Subacute thyroiditis", stem, listOf("Graves disease", "Hashimoto thyroiditis")))
        assertTrue("a long stem of the answer word leaks",
            AttendingHint.leaks("It is hyperthyroid in origin.", "Hyperthyroidism", "Tired woman.", listOf("Anaemia")))
        assertNull("a leaking reply is refused", AttendingHint.accept("Hint: it's Graves disease.", options[0], stem, others))
        assertEquals("a good reply is kept, tidied", "What does eye involvement tell you about the cause?",
            AttendingHint.accept("Hint: What does eye involvement tell you about the cause?", options[0], stem, others))
        val tiers = DifferentialTiers(mostLikely = listOf(DifferentialEntry("Graves disease", supporting = listOf("Exophthalmos"))),
            expanded = listOf(DifferentialEntry("Toxic multinodular goitre", against = listOf("A diffuse, not nodular, goitre"))))
        val fb = AttendingHint.fallback(options[0], stem, options, tiers)
        assertTrue("the fallback rules a rival out: $fb", fb.contains("Toxic multinodular goitre") && fb.contains("diffuse"))
        assertTrue("and never names the answer: $fb", !AttendingHint.leaks(fb, options[0], stem, others))
        val bare = AttendingHint.fallback(options[0], stem, options, null)
        assertTrue("with no differential, a fixed nudge", bare.contains("most specific finding"))
        val cache = HintCache()
        val hid = id()
        cache.store("one", hid)
        assertEquals("a hint is kept", "one", cache.hint(hid))
        repeat(HintCache.cap + 5) { cache.store("x", id()) }
        assertTrue("the oldest go past the cap", cache.hint(hid) == null && cache.hints.size == HintCache.cap)
        val fixed = HintCache()
        val before = HintCache.version("Which drug?", listOf("A", "B"), "A")
        val after = HintCache.version("Which drug?", listOf("A", "B"), "B")
        fixed.store("points to A", hid, before)
        assertEquals("a hint is kept for the wording it was written for", "points to A", fixed.hint(hid, before))
        assertTrue("a corrected key does not get the old hint", before != after && fixed.hint(hid, after) == null)
        assertEquals("the fingerprint is the same every launch", before, HintCache.version("Which drug?", listOf("A", "B"), "A"))
    }

    @Test fun calculator() {
        val calc = ExamCalculator()
        calc.digit(1); calc.digit(2); calc.op(ExamCalculator.Op.add); calc.digit(3); calc.equals()
        assertEquals("12 + 3 = 15", "15", calc.display)
        calc.clear(); calc.digit(7); calc.op(ExamCalculator.Op.divide); calc.digit(2); calc.equals()
        assertEquals("7 / 2 = 3.5", "3.5", calc.display)
        calc.clear(); calc.digit(2); calc.op(ExamCalculator.Op.add); calc.digit(3); calc.op(ExamCalculator.Op.multiply); calc.digit(4); calc.equals()
        assertEquals("chained left to right, as a basic calculator does", "20", calc.display)
        calc.clear(); calc.digit(5); calc.op(ExamCalculator.Op.divide); calc.digit(0); calc.equals()
        assertEquals("dividing by zero says Error", "Error", calc.display)
        calc.digit(8)
        assertEquals("a digit after Error starts again", "8", calc.display)
        calc.clear(); calc.dot(); calc.digit(5); calc.negate()
        assertEquals("-0.5", "-0.5", calc.display)
        calc.clear(); calc.digit(1); calc.op(ExamCalculator.Op.divide); calc.digit(3); calc.equals()
        assertEquals("a third to ten figures", "0.3333333333", calc.display)
    }

    @Test fun referenceRanges() {
        assertEquals("every group is listed", LabRanges.groups.toSet(), LabRanges.all.map { it.group }.toSet())
        assertEquals("no range twice", LabRanges.all.size, LabRanges.all.map { it.id }.toSet().size)
        val sodium = LabRanges.search("sodium").firstOrNull()
        assertTrue("sodium in SI and US units", sodium?.si?.contains("mmol/L") == true && sodium.us.contains("mEq/L"))
        assertTrue("USMLE reads conventional units", LabUnits.conventional(ExamTrack.usmle) && !LabUnits.conventional(ExamTrack.plab))
        assertEquals("search finds a group", LabRanges.gases.size, LabRanges.search("blood gases").size)
    }

    @Test fun highlighterPieces() {
        val longStem = "A 67-year-old man presents with sudden breathlessness. He had a hip replacement 10 days ago, and his left calf is swollen and tender to touch. What is the most likely diagnosis?"
        val pieces = StemPieces.split(longStem)
        assertEquals("the pieces give back the stem", longStem, pieces.joinToString(""))
        assertTrue("sentences are pieces: $pieces", pieces.size >= 3)
        assertEquals("a decimal is not a break", 2, StemPieces.split("Potassium 5.9 mmol/L. Next?").size)
    }
}
