package com.stethoscore.app.quiz

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.util.UUID

// A port of ios/RedPen/Tests/ExamToolsTests.swift: a mock paper's
// formats, assembly and marking, the twins, the attending's hint, the
// calculator, the reference ranges and the highlighter pieces, case for case.
class ExamToolsTest {
    private fun id() = UUID.randomUUID().toString()

    @Test fun paperFormats() {
        val plab = MockFormat.papers(ExamTrack.plab)[0]
        assertTrue("PLAB 1 is 180 questions in 3 hours", plab.questionCount == 180 && plab.minutes == 180)
        val mrcp = MockFormat.papers(ExamTrack.mrcp)
        assertTrue("MRCP Part 1 is two papers of 100", mrcp.size == 2 && mrcp.all { it.questionCount == 100 && it.minutes == 180 })
        val usmle = MockFormat.papers(ExamTrack.usmle, usmleBlocks = 3)[0]
        assertTrue("USMLE blocks are 40 in 60 minutes", usmle.sections.size == 3 && usmle.sections.all { it.questions == 40 && it.minutes == 60 })
        assertEquals("no more than seven USMLE blocks", 7, MockFormat.papers(ExamTrack.usmle, usmleBlocks = 12)[0].sections.size)
        assertEquals("MRCS A has its two papers", listOf(180, 120), MockFormat.papers(ExamTrack.mrcs).map { it.minutes })
    }

    @Test fun partLabels() {
        // the owner, 22 Oct: the mock says "Part n", never "section"
        val usmle = MockFormat.papers(ExamTrack.usmle, usmleBlocks = 3)[0]
        assertEquals(listOf("Part 1", "Part 2", "Part 3"), usmle.sections.map { it.title })
        assertEquals("part 2 of 3", MockFormat.partOf(2, 3))
        assertEquals("between parts", MockFormat.betweenParts)
        assertEquals("Part 2 closed", MockFormat.partClosed(2))
        assertEquals("Next part: 40 questions in 1 hr. Its clock starts when you do.", MockFormat.nextPartLine(40, "1 hr"))
        assertEquals("12 minutes left in this part", MockFormat.minutesLeft(12))
        assertEquals("A closed part can\u2019t be reopened.", MockFormat.closedForGood)
        val words = MockFormat.rules + listOf(MockFormat.partOf(1, 2), MockFormat.betweenParts, MockFormat.partClosed(1),
            MockFormat.nextPartLine(1, "1 min"), MockFormat.minutesLeft(1), MockFormat.closedForGood)
        assertTrue(words.toString(), words.none { it.lowercase().contains("section") })
    }

    private fun pool(counts: Map<String, Int>): List<MockCandidate> =
        counts.toSortedMap().flatMap { (subject, n) -> List(n) { MockCandidate(id(), subject) } }

    @Test fun assembly() {
        val plab = MockFormat.papers(ExamTrack.plab)[0]
        val usmle = MockFormat.papers(ExamTrack.usmle, usmleBlocks = 3)[0]
        val rng = MockSeededGenerator(42u)
        val big = pool(mapOf("Cardiology" to 150, "Renal" to 60, "Neuro" to 40))
        val full = MockAssembler.assemble(plab, big, rng)
        assertTrue("a big library fills the paper: ${full?.count}", full?.count == 180 && full.isShort == false && full.shortfallNote == null)
        val ids = full?.questionIds?.flatten() ?: emptyList()
        assertEquals("no question twice", ids.size, ids.toSet().size)
        val bySubject = big.filter { it.id in ids }.groupingBy { it.subject }.eachCount()
        assertTrue("every subject gets its share before one fills the rest: $bySubject",
            (bySubject["Neuro"] ?: 0) == 40 && (bySubject["Renal"] ?: 0) == 60)

        val small = pool(mapOf("Cardiology" to 30, "Renal" to 15))
        val short = MockAssembler.assemble(plab, small, rng)
        assertTrue("a short library sits a shorter paper", short?.count == 45 && short.isShort)
        assertEquals("at the real paper's pace", 45, short?.sections?.first()?.minutes)
        assertTrue("and says so honestly: ${short?.shortfallNote}",
            short?.shortfallNote?.contains("45") == true && short.shortfallNote.contains("180"))

        val blocks = MockAssembler.assemble(usmle, pool(mapOf("A" to 50, "B" to 20)), rng)
        assertEquals("blocks fill in order, the last one short", listOf(40, 30), blocks?.sections?.map { it.questions })
        assertEquals("a short block keeps the pace", 45, blocks?.sections?.last()?.minutes)

        assertNull("too few questions makes no paper", MockAssembler.assemble(plab, pool(mapOf("A" to 9)), rng))
        val one = MockCandidate(id(), "A")
        assertNull("copies of one question are one question", MockAssembler.assemble(plab, List(20) { one }, rng))

        val same1 = MockAssembler.assemble(plab, big, MockSeededGenerator(7u))
        val same2 = MockAssembler.assemble(plab, big, MockSeededGenerator(7u))
        assertEquals("the same seed makes the same paper", same1, same2)
    }

    @Test fun marking() {
        val marks = listOf(
            MockMark(id(), "Cardio", picked = 1, correct = true, seconds = 50.0),
            MockMark(id(), "Cardio", picked = 2, correct = false, seconds = 70.0),
            MockMark(id(), "Renal", picked = null, correct = false, seconds = 0.0),
            MockMark(id(), "Renal", picked = 0, correct = true, seconds = 60.0),
        )
        val result = MockResult(marks, passMark = 0.6)
        assertTrue("score counts right answers", result.correct == 2 && result.total == 4)
        assertEquals("unanswered are counted", 1, result.unanswered)
        assertTrue("50% does not pass a 60% mark", !result.passed)
        assertEquals("subjects are listed", listOf("Cardio", "Renal"), result.bySubject.map { it.subject }.sorted())
        assertEquals("renal answered once of twice", 1, result.bySubject.first { it.subject == "Renal" }.answered)
        // negative marking: one right, one wrong, one blank, one right
        assertEquals("NEET-PG's -1 of +4 is a quarter", 0.25, MockMarking.penalty("-1 of +4 for a wrong answer"), 1e-9)
        assertEquals("INI-CET's -1/3 is a third", 1.0 / 3, MockMarking.penalty("-1/3 for a wrong answer"), 1e-9)
        assertEquals("no negative marking costs nothing", 0.0, MockMarking.penalty(null), 0.0)
        val neetResult = MockResult(marks, passMark = 0.6, penalty = 0.25)
        assertTrue("a wrong answer costs a quarter of a mark", neetResult.wrong == 1 && kotlin.math.abs(neetResult.fraction - 1.75 / 4) < 1e-9)
        assertEquals("a blank costs nothing", 0.0, MockResult(listOf(marks[2]), passMark = 0.5, penalty = 0.25).fraction, 1e-9)
        assertEquals("the marked score never goes below nothing", 0.0, MockResult(listOf(marks[1]), passMark = 0.5, penalty = 1.0).fraction, 0.0)
        val neetAdvice = MockMarking.guessAdvice("NEET-PG", "-1 of +4 for a wrong answer", 4)
        assertTrue("NEET-PG: a blind guess still pays, so answer everything",
            neetAdvice.contains("answer every question") && !neetAdvice.contains("blank when"))
        val iniAdvice = MockMarking.guessAdvice("INI-CET", "-1/3 for a wrong answer", 4)
        assertTrue("INI-CET: a blind guess breaks even", iniAdvice.contains("breaks even"))
        assertTrue("a full mark off: guess only down to two", MockMarking.guessAdvice("X", "-1 for a wrong answer", 4).contains("down to 2 options"))
        assertTrue("no penalty: never leave a blank", MockMarking.guessAdvice("PLAB", null, 5).startsWith("Never leave one blank"))
        assertEquals("pacing: halfway through PLAB is Q90", 90, MockPacing.target(5_400.0, 180, 180))
    }

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
