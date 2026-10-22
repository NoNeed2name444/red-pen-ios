package com.stethoscore.app.quiz

import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.llm.ChatTurn
import com.stethoscore.app.llm.LLMBackend
import com.stethoscore.app.ui.library.CategoryFeature
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.LocalDateTime
import java.time.ZoneId

// Write a twin, step by step (T0133): a question is missed, Write a twin is
// tapped, a stand-in writer (no network) writes the twin, it waits a day or
// two on a fake clock, then it is due in the Twins review; the empty Twins
// tile; the twin answered; and everything read back after a relaunch. The
// steps' names match ios/RedPen/Tests/TwinFlowTests.swift.
class TwinFlowTest {
    @get:Rule val folder = TemporaryFolder()

    private val zone = ZoneId.of("Europe/London")

    /** The fake clock: a day and hour in October 2026, London time. */
    private fun at(day: Int, hour: Int, minute: Int = 0): Long =
        LocalDateTime.of(2026, 10, day, hour, minute).atZone(zone).toInstant().toEpochMilli()

    private val missed = MCQQuestion(id = "missed-1",
        stem = "A 34-year-old man has frothy urine, periorbital oedema and 6 g/day proteinuria. Which finding on light microscopy is most likely?",
        options = listOf("Normal glomeruli", "Segmental sclerosis in some glomeruli", "Diffuse basement membrane thickening",
            "Mesangial IgA deposits", "Crescents"),
        correctIndex = 1, explanation = "FSGS is the commonest primary cause of nephrotic syndrome in Black adults.", source = "Renal set")

    private val twinStem = "A 52-year-old woman with long-standing obesity has leg swelling and 5 g/day of protein in her urine. What does a kidney biopsy most likely show?"

    /** The stand-in writer: answers as the worker would, from the prompt it is given; no network. */
    private class StandIn(val reply: (List<ChatTurn>) -> String) : LLMBackend {
        override val label = "Stand-in"
        override val isOnDevice = true
        override val promptBudgetChars = 100_000
        val asked = mutableListOf<List<ChatTurn>>()
        override suspend fun complete(turns: List<ChatTurn>, maxTokens: Int, temperature: Double): String {
            asked += turns
            return reply(turns)
        }
    }

    private fun questionJson(stem: String, options: List<String>, correct: Int) = JSONObject()
        .put("questions", JSONArray().put(JSONObject().put("stem", stem).put("options", JSONArray(options))
            .put("correctIndex", correct).put("explanation", "Obesity-related FSGS."))).toString()

    private fun twinWriter() = StandIn { turns ->
        val text = turns.joinToString("\n") { it.toString() }
        if (text.contains(missed.stem)) questionJson(twinStem, listOf("Segmental sclerosis", "Normal glomeruli",
            "Crescents in most glomeruli", "Mesangial IgA deposits", "Thickened basement membrane"), 0) else "{}"
    }

    private fun storeWithMiss(): StudyStore = StudyStore(folder.root).also {
        it.addSet(StudySet(name = "Renal", subject = "Renal", kind = StudySetKind.MCQ, questions = listOf(missed)))
    }

    private val request = PendingTwin(missed.id, picked = 0, reason = "Misread the question")

    @Test fun s1MissTellsTheWriterWhatWasChosen() {
        val input = TwinPrompt.input(missed.stem, missed.options, missed.correctIndex, missed.explanation, 0, "Misread the question")
        assertTrue("S1 miss: the writer is told the missed stem", input.contains(missed.stem))
        assertTrue("S1 miss: and the answer the student chose", input.contains("The student chose: Normal glomeruli"))
        assertTrue("S1 miss: and the right one", input.contains("Correct answer: Segmental sclerosis in some glomeruli"))
        assertTrue("S1 miss: and why it was missed", input.contains("Why they missed it: Misread the question"))
    }

    @Test fun s2WriteTheStandInWritesItAndItJoinsTheQueue() = runBlocking {
        val store = storeWithMiss()
        val writer = twinWriter()
        val outcome = TwinWriter.write(request, store, writer, "UK finals style.", { at(22, 21) }, zone)
        assertEquals("S2 write: the twin is written, back in two days", TwinOutcome.Made(2), outcome)
        assertEquals("S2 write: the quiz says when it comes back",
            "Twin written. It comes back in 2 days, under Questions → Twins.", outcome.note)
        assertTrue("S2 write: the writer was asked once, with the twin prompt",
            writer.asked.size == 1 && writer.asked[0].toString().contains("\"twin\""))
        val set = store.library.single { it.name == "Twins · Renal" }
        val twin = set.questions.single()
        assertEquals("S2 write: the twin is in the subject's Twins set", twinStem, twin.stem)
        assertTrue("S2 write: the twin has its own id", twin.id != missed.id)
        assertEquals("S2 write: it says where it came from", "Twin of a question from Renal set", twin.source)
        assertTrue("S2 write: the twin is on the way", store.twinShelf.isOnTheWay(missed.id))
        assertEquals("S2 write: queued under its own id", listOf(twin.id), store.twinShelf.book.queue.waiting.map { it.id })
    }

    @Test fun s2WriteRefusedOfflineOrNoWriter() = runBlocking {
        val store = storeWithMiss()
        val echo = StandIn { questionJson(missed.stem, missed.options, 1) }
        val refused = TwinWriter.write(request, store, echo, "", { at(22, 21) }, zone)
        assertEquals("S2 write: the missed question again is refused, and waits", TwinOutcome.Later(TwinWriter.later), refused)
        val offline = StandIn { throw java.io.IOException("offline") }
        TwinWriter.write(request, store, offline, "", { at(22, 21) }, zone)
        assertEquals("S2 write: refused or offline, it waits to be written, once", listOf(request), store.twinShelf.book.pending)
        assertTrue("S2 write: and is on the way", store.twinShelf.isOnTheWay(missed.id))
        assertTrue("S2 write: no twin set is made", store.library.none { it.name.startsWith("Twins") })
        assertEquals("S2 write: with no writer set up, it says so plainly",
            TwinOutcome.Unavailable(TwinWriter.noWriter), TwinWriter.write(request, store, null, "", { at(22, 21) }, zone))
        assertNull("S2 write: a writer that gives nothing gives no twin", TwinDraft.pick(emptyList(), missed))
        // back online: the waiting twin is written the next time a quiz opens
        TwinWriter.retryPending(store, twinWriter(), "")
        assertTrue("S2 write: once back online the waiting twin is written", store.twinShelf.book.pending.isEmpty()
            && store.twinShelf.book.queue.hasTwin(missed.id))
        var many = TwinBook().later(request)
        repeat(40) { many = many.later(PendingTwin("other-$it")) }
        assertTrue("S2 write: at most 30 wait, the oldest let go first",
            many.pending.size == TwinBook.pendingLimit && request !in many.pending)
    }

    @Test fun s3WaitADayOrTwoOnTheFakeClock() {
        val book = TwinBook().added("twin", missed.id, confident = false, guessed = false, now = at(22, 21), zone = zone)
        assertTrue("S3 wait: not due the evening it was written", book.queue.due(at(22, 23, 59)).isEmpty())
        assertTrue("S3 wait: not due the next day", book.queue.due(at(23, 18)).isEmpty())
        assertEquals("S3 wait: due from the start of the second day", listOf("twin"), book.queue.due(at(24, 0)).map { it.id })
        val sure = TwinBook().added("sure", "p", confident = true, guessed = false, now = at(22, 21), zone = zone)
        assertTrue("S3 wait: a sure-but-wrong miss comes back tomorrow morning",
            sure.queue.due(at(23, 0)).size == 1 && sure.queue.due(at(22, 23, 59)).isEmpty())
        val guess = TwinBook().added("guess", "p", confident = false, guessed = true, now = at(22, 21), zone = zone)
        assertTrue("S3 wait: a guess waits three days", guess.queue.due(at(24, 12)).isEmpty() && guess.queue.due(at(25, 0)).size == 1)
    }

    @Test fun s4ReviewTheLongestWaitingFirst() = runBlocking {
        val store = storeWithMiss()
        TwinWriter.write(request, store, twinWriter(), "", { at(22, 21) }, zone)
        assertTrue("S4 review: the Twins quiz is empty before it is due", TwinSets.quiz(store, at(23, 12)).questions.isEmpty())
        val quiz = TwinSets.quiz(store, at(24, 9))
        assertEquals("S4 review: on the second day it is in the Twins quiz", listOf(twinStem), quiz.questions.map { it.stem })
        assertEquals("S4 review: the quiz is called Twin questions", "Twin questions", quiz.name)
        // a second, sure-but-wrong miss that morning is due first
        val other = MCQQuestion(id = "other", stem = "Which nerve supplies the deltoid muscle in a 25-year-old rugby player with a shoulder dislocation?",
            options = listOf("Axillary", "Radial", "Median", "Ulnar", "Musculocutaneous"), correctIndex = 0)
        val early = other.copy(id = "early-twin", stem = "A 70-year-old woman falls on her outstretched hand and has numbness over the regimental badge area. Which nerve is hurt?")
        TwinSets.add(store, early, "Anatomy", at(22, 9))
        store.twinShelf.addTwin(early.id, other.id, confident = true, guessed = false, now = at(22, 9), zone = zone)
        assertEquals("S4 review: by the 24th both, the longest-waiting first",
            listOf(early.stem, twinStem), TwinSets.quiz(store, at(24, 9)).questions.map { it.stem })
        val again = store.twinShelf.book.added("again", missed.id, confident = false, guessed = false, now = at(23, 10), zone = zone)
        assertTrue("S4 review: a newer twin for the same question replaces the waiting one",
            again.queue.waiting.filter { it.parentId == missed.id }.map { it.id } == listOf("again"))
    }

    @Test fun s5NothingYetTheEmptyTwinsTile() {
        val store = storeWithMiss()
        assertTrue("S5 nothing yet: an empty book has nothing due", TwinSets.quiz(store, at(30, 12)).questions.isEmpty())
        assertTrue("S5 nothing yet: so the tile opens Nothing here yet, not a quiz",
            CategoryFeature.TWINS.quiz(store)?.set?.questions.isNullOrEmpty())
        assertEquals("S5 nothing yet: with the twins' own words", TwinBook.nothingYet, CategoryFeature.TWINS.emptyText)
        assertTrue("S5 nothing yet: the words say what to do",
            TwinBook.nothingYet.contains("Write a twin") && TwinBook.nothingYet.contains("a day or two"))
        assertTrue("S5 nothing yet: Twins is a Questions tile that opens a quiz", CategoryFeature.TWINS.isQuiz)
    }

    @Test fun s6AnsweredRightLeavesWrongComesBackOnce() {
        val book = TwinBook().added("twin", missed.id, confident = false, guessed = false, now = at(22, 21), zone = zone)
        var q = book.queue.answered("twin", false, at(24, 10), zone)
        assertTrue("S6 answer: a missed twin comes back the next day",
            q.due(at(24, 23)).isEmpty() && q.due(at(25, 0)).map { it.id } == listOf("twin"))
        q = q.answered("twin", false, at(25, 10), zone)
        assertTrue("S6 answer: missed twice, it leaves the twins for the mistakes", q.waiting.isEmpty())
        val right = book.queue.answered("twin", true, at(24, 10), zone)
        assertTrue("S6 answer: got right, it leaves the queue", right.waiting.isEmpty() && right.due(at(30, 0)).isEmpty())
        assertEquals("S6 answer: and is kept for the record", true, right.entries.first().answeredCorrectly)
    }

    @Test fun s6AnswerInTheQuizMovesTheTwinOnly() = runBlocking {
        val store = storeWithMiss()
        TwinWriter.write(request, store, twinWriter(), "", { at(22, 21) }, zone)
        val twinId = store.twinShelf.book.queue.entries.single().id
        store.recordAnswer(missed.id, false)
        assertEquals("S6 answer: answering another question leaves the twin as it was", null,
            store.twinShelf.book.queue.entries.single().answeredCorrectly)
        store.recordAnswer(twinId, true)
        assertTrue("S6 answer: the twin answered right in the quiz leaves the queue", store.twinShelf.book.queue.waiting.isEmpty())
    }

    @Test fun s7RelaunchEverythingReadsBack() = runBlocking {
        val store = storeWithMiss()
        TwinWriter.write(request, store, twinWriter(), "", { at(22, 21) }, zone)
        store.twinShelf.later(PendingTwin("waiting", picked = 2, reason = "Guessed", confident = false, guessed = true))
        val before = store.twinShelf.book
        val reopened = StudyStore(folder.root)
        assertEquals("S7 relaunch: the queue and pending twins read back the same", before, reopened.twinShelf.book)
        assertEquals("S7 relaunch: the same twins are due", listOf(twinStem), TwinSets.quiz(reopened, at(24, 9)).questions.map { it.stem })
        assertTrue("S7 relaunch: still nothing due early", TwinSets.quiz(reopened, at(22, 22)).questions.isEmpty())
        assertNotNull("S7 relaunch: the twin question itself reads back",
            reopened.library.firstOrNull { it.name == "Twins · Renal" }?.questions?.singleOrNull { it.stem == twinStem })
        assertEquals("S7 relaunch: a JSON round trip is exact", before, TwinBook.fromJson(before.toJson()))
        assertEquals("S7 relaunch: an unreadable file is an empty book", TwinBook(), TwinBook.fromJson("not twins"))
        reopened.deleteSet(reopened.library.first { it.name == "Twins · Renal" }.id)
        TwinSets.quiz(reopened, at(24, 9))
        assertFalse("S7 relaunch: a twin whose question left the library is let go", reopened.twinShelf.book.queue.entries.any())
    }
}
