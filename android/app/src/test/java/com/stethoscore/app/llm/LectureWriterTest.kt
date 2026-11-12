package com.stethoscore.app.llm

import com.stethoscore.app.data.CardStyle
import com.stethoscore.app.data.OsceGenerator
import com.stethoscore.app.data.PlainTextImport
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.TextSlicing
import com.stethoscore.app.data.osceStyle
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.reading.BookFigure
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * The card, textbook and station writers (iOS LectureWriter, BatchWriting and
 * MedicalGenerate.osce) against fixed replies: a stand-in backend or a fake
 * worker, no network and no key.
 */
class LectureWriterTest {
    private val noPause: suspend (Long) -> Unit = {}

    /** Answers each call in turn from [replies] (the last one again once they run out), and keeps what it was sent. */
    private class StandIn(val replies: List<() -> String>) : LLMBackend {
        override val label = "Stand-in"
        override val isOnDevice = false
        override val promptBudgetChars = 40_000
        val asked = mutableListOf<List<ChatTurn>>()
        override suspend fun complete(turns: List<ChatTurn>, maxTokens: Int, temperature: Double): String {
            asked += turns
            return replies[minOf(asked.size - 1, replies.size - 1)]()
        }
    }

    private fun owner(server: FakeServer) =
        LLMService(FakeServer.standInKey(), { null }, FakeServer.BASE, server, OwnerSpend(OwnerSpend.MemoryStore()))

    // card prompts

    @Test fun theCardPromptAsksForTheChosenKind() {
        val qa = LectureWriter.cardPrompt(12, "Rheumatology", emptyList(), "Lupus lecture.", CardStyle.qa)
        assertTrue(qa.startsWith("Write 12 flashcards for a medical student revising Rheumatology. One fact per card."))
        assertTrue(qa.contains("Question cards, one per line, exactly: Front | answer point 1"))
        assertFalse(qa.contains("Cloze cards"))
        assertTrue(qa.endsWith("\n\nSOURCE:\nLupus lecture."))
        val cloze = LectureWriter.cardPrompt(4, "", emptyList(), "x", CardStyle.cloze)
        assertTrue(cloze.contains("revising medicine"))
        assertTrue(cloze.contains("{{c1::that word}}") && !cloze.contains("Question cards"))
        val mixed = LectureWriter.cardPrompt(4, "", emptyList(), "x", CardStyle.mixed)
        assertTrue(mixed.contains("Mix the two kinds, about half each:\n- Question cards") && mixed.contains("\n- Cloze cards"))
        assertFalse(mixed.contains("Already written"))
    }

    @Test fun theCardPromptListsTheLast60AlreadyWritten() {
        val already = (1..70).map { "Front $it" }
        val prompt = LectureWriter.cardPrompt(12, "", already, "x")
        assertTrue(prompt.contains("Already written - do not repeat these:\n- Front 11\n"))
        assertFalse(prompt.contains("- Front 10\n"))
        assertTrue(prompt.contains("- Front 70\n"))
    }

    // reading a reply

    @Test fun aReplyIsReadIntoFreshLines() {
        val reply = """
            Here are your cards:
            1. What spares the nasolabial folds? | the **malar** rash | lupus
            - What spares the nasolabial folds? | the **malar** rash | lupus
            The malar rash spares the {{c1::nasolabial folds}}
            * Which antibody is most specific? | **anti-dsDNA**
            A line with no fields at all
        """.trimIndent()
        val seen = mutableSetOf("which antibody is most specific? | **anti-dsdna**")
        val lines = LectureWriter.freshLines(reply, StudySetKind.ANKI, seen)
        assertEquals(listOf("What spares the nasolabial folds? | the **malar** rash | lupus",
            "The malar rash spares the {{c1::nasolabial folds}}"), lines)
        // a textbook's or another kind's line needs its second field
        assertFalse(LectureWriter.freshLines(reply, StudySetKind.BOOK, mutableSetOf()).any { it.contains("{{c") })
        // what is kept reads as cards through the same parser a student's typing does
        assertEquals(2, PlainTextImport.parseAnyCards(lines.joinToString("\n")).size)
    }

    @Test fun aJobsRepliesAreCollectedOnceAndCut() {
        val replies = listOf("A? | one\nB? | two", "b? | TWO\nC? | three\nD? | four")
        assertEquals(listOf("A? | one", "B? | two", "C? | three"), LectureWriter.collectLines(replies, StudySetKind.ANKI, 3))
    }

    // writing call by call

    @Test fun cardsAreWrittenABatchAtATimeAndAShortfallSaid() = runBlocking {
        val backend = StandIn(listOf(
            { (1..12).joinToString("\n") { "Card $it? | answer $it" } },
            { throw LLMError.Http(500, "busy") },
        ))
        val draft = LectureWriter.draft(StudySetKind.ANKI, "Lupus lecture.", 20, "", backend, pause = noPause)
        assertEquals(12, draft.text.lines().size)
        val short = draft.shortfall!!
        assertEquals(20, short.wanted)
        assertEquals(12, short.written)
        assertEquals(3, short.failedBatches)
        assertEquals(4, backend.asked.size)
        assertTrue(short.message("card").startsWith("Wrote 12 of 20 cards. 8 could not be written: 3 batches failed — The hosted model refused the request (HTTP 500)."))
        assertTrue(short.message("card").endsWith("Everything written is kept."))
        assertEquals("Write the missing 8 cards", short.retryTitle("card"))
        // the second batch is told what the first wrote, and asks only for what is left
        val second = backend.asked[1].first().text
        assertTrue(second.contains("Write 8 flashcards") && second.contains("- Card 12?"))
    }

    @Test fun aRefusalStopsAtOnceAndIsSaid() = runBlocking {
        val backend = StandIn(listOf({ throw LLMError.Http(402, "Stethoscore Cloud is part of Pro.") }))
        try {
            LectureWriter.draft(StudySetKind.ANKI, "Lupus lecture.", 12, "", backend, pause = noPause)
            fail("nothing written, yet no error")
        } catch (e: LLMError.Http) {
            assertEquals("Stethoscore Cloud is part of Pro.", e.message)
        }
        assertEquals(1, backend.asked.size)
    }

    @Test fun aTextbookLeavesAGapForAPageThatFailed() = runBlocking {
        val lecture = (1..3).joinToString("\n\n") { "Topic $it. " + "Sentence about topic $it. ".repeat(60) }
        var call = 0
        val backend = StandIn(listOf({
            call += 1
            if (call == 2) throw LLMError.Http(500, "busy") else "## Topic $call\n\n### Definition\n\nText $call."
        }))
        val draft = LectureWriter.draft(StudySetKind.BOOK, lecture, 3, "Medicine", backend, exam = ExamTrack.plab, pause = noPause)
        assertEquals(setOf(0, 2), draft.pages.keys)
        assertTrue(draft.text.contains(BatchWriting.gap(1)))
        assertEquals(listOf(1), draft.shortfall!!.parts)
        assertTrue(draft.shortfall!!.message("page").contains("1 could not be written (Part 2): 1 batch failed"))
        val prompt = backend.asked.first().single().text
        assertTrue(prompt.startsWith("You are writing one page of a medical revision textbook for medical students studying Medicine, preparing for PLAB 1 & 2."))
        assertTrue(prompt.endsWith("SOURCE:\n" + TextSlicing.slice(lecture, 3, 40_000)[0]))
        // the second try writes the missing page into its gap
        val filled = BatchWriting.fill(draft.text, 1, "## Topic 2\n\nWritten again.")
        assertFalse(filled.contains("not written yet"))
        assertTrue(filled.indexOf("Topic 1") < filled.indexOf("Written again.") && filled.indexOf("Written again.") < filled.indexOf("Topic 3"))
    }

    @Test fun theBookPromptPlacesTheLecturesDiagrams() {
        val figure = BookFigure("", 4, listOf("aorta", "left ventricle"))
        val prompt = LectureWriter.bookPrompt("Heart.", "", ExamTrack.general, listOf(2 to figure))
        assertTrue(prompt.startsWith("You are writing one page of a medical revision textbook for medical students.\n"))
        assertTrue(prompt.contains("  - image:2 (page 4) labelled: aorta, left ventricle\n"))
        assertFalse(LectureWriter.bookPrompt("Heart.", "", ExamTrack.general, emptyList()).contains("image:"))
    }

    @Test fun slicesKeepTheWholeLecture() {
        val lecture = (1..10).joinToString("\n\n") { "Paragraph $it " + "x".repeat(900) }
        val slices = TextSlicing.slice(lecture, 3, 40_000)
        assertEquals(3, slices.size)
        assertTrue(slices.first().startsWith("Paragraph 1 ") && slices.last().contains("Paragraph 10 "))
        assertTrue(TextSlicing.slice("  \n\n ", 3, 100).isEmpty())
    }

    // Stethoscore Cloud: one job

    @Test fun cardsAreWrittenAsOneCloudJob() = runBlocking {
        val jobs = FakeJobs(listOf("A? | one\nB? | two", "B? | two\nThe {{c1::malar}} rash"))
        val llm = owner(FakeServer { jobs.answer(it) })
        val draft = LectureWriter.draft(StudySetKind.ANKI, "Lupus lecture.", 10, "Rheumatology", llm.backend()!!, style = CardStyle.cloze, pause = noPause)
        assertEquals("A? | one\nB? | two\nThe {{c1::malar}} rash", draft.text)
        assertNull(draft.shortfall)
        val spec = jobs.spec!!
        assertEquals("Writing 10 cards", spec.getString("title"))
        assertEquals("loop", spec.getString("mode"))
        assertEquals("lines", spec.getString("extract"))
        assertTrue(spec.getBoolean("cloze"))
        val step = spec.getJSONArray("steps").getJSONObject(0)
        assertEquals("Write the 12 lines now.", step.getString("user"))
        assertEquals(1920, step.getInt("maxTokens"))
        assertTrue(step.getString("system").contains("{{SOURCE}}") && step.getString("system").contains("- {{ALREADY}}"))
        assertEquals(1, jobs.deleted)
    }

    @Test fun aTextbookIsWrittenAsOneCloudJob() = runBlocking {
        val jobs = FakeJobs(listOf("## Lupus\n\n### Definition\n\nAn autoimmune disease."))
        val llm = owner(FakeServer { jobs.answer(it) })
        val draft = LectureWriter.draft(StudySetKind.BOOK, "Lupus lecture.", 1, "", llm.backend()!!, pause = noPause)
        assertTrue(draft.text.startsWith("## Lupus"))
        val spec = jobs.spec!!
        assertEquals("each", spec.getString("mode"))
        assertEquals("pages", spec.getString("extract"))
        val step = spec.getJSONArray("steps").getJSONObject(0)
        assertEquals("", step.getString("system"))
        assertTrue(step.getString("user").endsWith("SOURCE:\n{{SOURCE}}"))
        assertEquals(3000, step.getInt("maxTokens"))
    }

    // a cloud job keeps what the app needs to finish the set if it is closed first (T0237)

    /** The jobs on [store] as they stand each time the run reports progress: the first report comes once the record is saved. */
    private class Seen(private val store: CloudJobs.MemoryStore) {
        val jobs = mutableListOf<CloudJobs.Pending>()
        val onProgress: (Int, Int) -> Unit = { _, _ -> if (jobs.isEmpty()) store.all().firstOrNull()?.let { jobs += it } }
    }

    @Test fun cardsKeepTheirJobAndAFallbackRecipeOnTheStoreTheyAreGiven() = runBlocking {
        val jobs = FakeJobs(listOf("A? | one\nB? | two"))
        val llm = owner(FakeServer { jobs.answer(it) })
        val store = CloudJobs.MemoryStore()
        val seen = Seen(store)
        LectureWriter.draft(StudySetKind.ANKI, "Lupus lecture.", 10, "Rheumatology", llm.backend()!!, store = store, pause = noPause, onProgress = seen.onProgress)
        val kept = seen.jobs.singleOrNull()
        assertNotNull("the job is kept on the store the writer was given, while it runs", kept)
        assertEquals("Writing 10 cards", kept!!.title)
        assertEquals("with the recipe made from what the writer was given",
            CloudRecipe(StudySetKind.ANKI, "", "Rheumatology", 10), CloudRecipe.of(kept.recipe))
        assertNull("cards have no figure placement", kept.extra)
        // no screen gave it a delivery: its replies are read and it is let go at once
        assertTrue(store.all().isEmpty())
        assertEquals(1, jobs.deleted)
    }

    @Test fun aTextbookKeepsItsFiguresAndTheirPlacementOnTheStoreItIsGiven() = runBlocking {
        val jobs = FakeJobs(listOf("## Aorta\n\n### Definition\n\nThe main artery."))
        val llm = owner(FakeServer { jobs.answer(it) })
        val store = CloudJobs.MemoryStore()
        val seen = Seen(store)
        val figures = listOf(BookFigure("figure-zero", 1, listOf("aorta", "left ventricle")), BookFigure("figure-one", 2, listOf("tibia", "fibula")))
        LectureWriter.draft(StudySetKind.BOOK, "The aorta leaves the left ventricle and carries blood to the body.", 1, "Cardiology", llm.backend()!!,
            figures = figures, store = store, pause = noPause, onProgress = seen.onProgress)
        val kept = seen.jobs.singleOrNull()
        assertNotNull("the job is kept on the store the writer was given, while it runs", kept)
        assertEquals("Writing 1 textbook pages", kept!!.title)
        // every figure rides with the job, in the order the placement counts them
        assertEquals(CloudRecipe(StudySetKind.BOOK, "", "Cardiology", 1, figures = listOf("figure-zero", "figure-one")), CloudRecipe.of(kept.recipe))
        assertEquals("the first figure goes to the page, the second shares nothing with it", "[[0]]", kept.extra)
        assertTrue(store.all().isEmpty())
        assertEquals(1, jobs.deleted)
    }

    @Test fun aScreensOwnRecipeAndDeliveryWinOverTheFallbackAndTheDeliveryIsHeld() = runBlocking {
        val jobs = FakeJobs(listOf("A? | one\nB? | two"))
        val llm = owner(FakeServer { jobs.answer(it) })
        val store = CloudJobs.MemoryStore()
        val screens = CloudRecipe(StudySetKind.ANKI, "Lupus cards", "Rheumatology", 10, exam = "usmle1")
        val delivery = CloudJobs.Delivery()
        val draft = withContext(CloudJobs.Context(screens.json(), delivery)) {
            LectureWriter.draft(StudySetKind.ANKI, "Lupus lecture.", 10, "Rheumatology", llm.backend()!!, store = store, pause = noPause)
        }
        assertEquals("A? | one\nB? | two", draft.text)
        // the job is kept, whole, for the screen to finish with: on the device and on the server
        val kept = store.all().singleOrNull()
        assertNotNull("a job under a delivery is kept once its replies are read", kept)
        assertEquals("the screen's recipe, not the one the writer would have made", screens.json(), kept!!.recipe)
        assertEquals(true, kept.delivered)
        assertEquals(listOf("A? | one\nB? | two"), kept.outputs)
        assertEquals(0, jobs.deleted)
        // and the screen's delivery is the one that holds it: finishing it lets the job go
        CloudJobs.finish(delivery)
        assertTrue(store.all().isEmpty())
        assertEquals(1, jobs.deleted)
    }

    // stations: MedicalGenerate.osce

    private fun station(title: String) = JSONObject().put("title", title).put("steps", JSONArray(listOf(
        "Introduce yourself and confirm the patient's name", "Explain the examination and gain consent", "Wash your hands",
        "Inspect from the end of the bed", "Thank the patient")))

    private fun stations(vararg titles: String) = JSONObject().put("stations", JSONArray(titles.map { station(it) })).toString()

    @Test fun stationsAreWrittenAsOneCloudJob() = runBlocking {
        val jobs = FakeJobs(listOf(stations("Knee examination", "Hip examination"), stations("KNEE EXAMINATION", "Gait")))
        val llm = owner(FakeServer { jobs.answer(it) })
        val written = MedicalGenerate.osce("A skills lecture on the knee.", 3, "Orthopaedics", llm.backend()!!, ExamTrack.plab, pause = noPause)
        assertEquals(listOf("Knee examination", "Hip examination", "Gait"), written.map { it.title })
        val spec = jobs.spec!!
        assertEquals("Writing 3 stations", spec.getString("title"))
        assertEquals("stations", spec.getString("extract"))
        val step = spec.getJSONArray("steps").getJSONObject(0)
        assertEquals("Write the 2 stations now, as JSON only.", step.getString("user"))
        assertEquals(1800, step.getInt("maxTokens"))
        assertEquals(0.6, step.getDouble("temperature"), 0.0)
        val system = step.getString("system")
        assertTrue(system.contains("{{SOURCE}}") && system.contains("{{ALREADY}}") && system.contains(ExamTrack.plab.osceStyle!!))
        assertTrue(system.endsWith("{\"stations\":[{\"title\":\"...\",\"steps\":[\"...\"]}]}"))
    }

    @Test fun aJobWithNoStationSaysSo() {
        try {
            MedicalGenerate.collectStations(listOf("No procedure here."), 4)
            fail("no station, yet no error")
        } catch (e: OsceGenerator.NothingUsable) {
            assertEquals(OsceGenerator.nothingUsable, e.message)
        }
        assertEquals(listOf("Knee examination"), MedicalGenerate.parseStations("```json\n" + stations("Knee examination") + "\n```").map { it.title })
    }

    @Test fun callByCallNothingKeptThrowsAsIOSDoes() = runBlocking {
        val backend = StandIn(listOf({ "No stations." }))
        try {
            MedicalGenerate.osce("Facts.", 2, "", backend, pause = noPause)
            fail("no station, yet no error")
        } catch (e: OsceGenerator.NothingUsable) {
            assertEquals(3, backend.asked.size)
        }
    }

    // words

    @Test fun partsAreNamedAsIOSNamesThem() {
        assertEquals("Part 4", BatchWriting.partList(listOf(3)))
        assertEquals("Parts 4 and 9", BatchWriting.partList(listOf(3, 8)))
        assertEquals("Parts 1, 2 and 3", BatchWriting.partList(listOf(0, 1, 2)))
        assertEquals("Write the missing page", BatchWriting.Shortfall(3, 2, 1, listOf(1)).retryTitle("page"))
        assertNull(BatchWriting.shortfall(5, 5, BatchWriting.Tally()))
        assertEquals("Wrote 3 of 5 cards. The model found nothing new to write for the other 2. Everything written is kept.",
            BatchWriting.shortfall(5, 3, BatchWriting.Tally())!!.message("card"))
        assertEquals(listOf(0L, 1_000L, 2_000L, 4_000L, 8_000L, 8_000L), (0..5).map { BatchWriting.waitMillis(it) })
    }
}
