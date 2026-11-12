package com.stethoscore.app.llm

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.OcclusionBox
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.network.BackendClient
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import kotlinx.coroutines.async
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * T0172: the collector and the Delivery, ported from iOS CloudJobCollector.swift and CloudJobs.swift.
 * T0237: every kind screened as iOS screens it, "is ready" announced, and CloudJobRetryTests.
 */
class CloudJobCollectorTest {
    private val id = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private var ioBefore: CoroutineDispatcher = Dispatchers.IO
    private var ranOn: Thread? = null

    @Before fun inPlace() {
        ioBefore = CloudJobs.io
        CloudJobs.io = Dispatchers.Unconfined
    }

    @After fun restore() {
        CloudJobs.io = ioBefore
        CloudJobCollector.announcer = null
    }

    private fun question(stem: String) = JSONObject().put("stem", stem)
        .put("options", JSONArray(listOf("Atenolol tablets", "Amlodipine tablets", "Ramipril tablets", "Indapamide tablets")))
        .put("correctIndex", 2).put("explanation", "Key point: ACE inhibitors first.")

    private val replies = listOf(JSONObject().put("questions", JSONArray(listOf(question("First line for a 50-year-old?"), question("Which drug for diabetic kidney disease?")))).toString())

    private fun recipe() = CloudRecipe(StudySetKind.MCQ, "", "Cardiology", 2, exam = "usmle1").json()

    /** A record from an earlier run of the app. */
    private fun earlier(started: Long = System.currentTimeMillis()) =
        CloudJobs.Pending(id, "Writing 2 questions", started, launch = "an-earlier-run", total = 2, identity = "owner", recipe = recipe())

    private fun worker(status: String, error: String? = null, outputs: List<String> = replies) = FakeServer { request ->
        when {
            request.method == "GET" && request.path == "/jobs/$id" ->
                FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id).put("status", status).put("done", 2).put("total", 2).put("error", error ?: JSONObject.NULL)))
            request.method == "GET" && request.path == "/jobs/$id?outputs=1" ->
                FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id)).put("outputs", JSONArray(outputs)))
            request.method == "DELETE" -> FakeServer.ok(JSONObject().put("ok", true))
            else -> BackendClient.Reply(404, "{}")
        }
    }

    private class Shelf(var onDisk: Boolean = true) : CloudJobCollector.Library {
        val sets = mutableListOf<StudySet>()
        override fun add(set: StudySet): Boolean { if (onDisk) sets += set; return onDisk }
    }

    private suspend fun collect(store: CloudJobs.PendingStore, server: FakeServer, shelf: Shelf, said: MutableList<String> = mutableListOf()) =
        CloudJobCollector.collect(store, shelf, { if (it == "owner") "bearer" else null }, server::client,
            announce = { title, body, _ -> said += "$title|$body"; ranOn = Thread.currentThread() })

    @Test fun aFinishedJobBecomesItsSetOnceAndOnlyOnce() = runBlocking {
        val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
        val server = worker("done")
        val shelf = Shelf()
        val said = mutableListOf<String>()
        val made = collect(store, server, shelf, said)
        assertEquals(1, made.size)
        val set = shelf.sets.single()
        assertEquals("Cardiology – questions", set.name)
        assertEquals(StudySetKind.MCQ, set.kind)
        assertEquals(2, set.questions.size)
        assertEquals("usmle1", set.exam)
        assertEquals(listOf("Cardiology – questions is ready|Written in the cloud while the app was closed. $PASSED"), said)
        // marked delivered: the record is gone here and the server's copy forgotten
        assertTrue(store.all().isEmpty())
        assertEquals(1, server.requests.count { it.method == "DELETE" && it.path == "/jobs/$id" })
        // the second start makes nothing
        assertTrue(collect(store, server, shelf).isEmpty())
        assertEquals(1, shelf.sets.size)
        // the work ran in place, on the test's own thread (CloudJobs.io)
        assertEquals(Thread.currentThread(), ranOn)
    }

    @Test fun aSetThatIsNotOnDiskLeavesTheJobToCollectAgain() = runBlocking {
        val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
        val server = worker("done")
        val shelf = Shelf(onDisk = false)
        assertTrue(collect(store, server, shelf).isEmpty())
        assertEquals(listOf(id), store.all().map { it.id })
        assertEquals(0, server.requests.count { it.method == "DELETE" })
        shelf.onDisk = true
        assertEquals(1, collect(store, server, shelf).size)
        assertTrue(store.all().isEmpty())
    }

    @Test fun aJobStillRunningIsLeftAlone() = runBlocking {
        val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
        val server = worker("running")
        val shelf = Shelf()
        assertTrue(collect(store, server, shelf).isEmpty())
        assertEquals(listOf(id), store.all().map { it.id })
        assertTrue(shelf.sets.isEmpty())
        assertEquals(0, server.requests.count { it.method == "DELETE" })
        assertEquals(0, server.requests.count { it.path.endsWith("?outputs=1") })
    }

    @Test fun thisRunsJobsAreLeftToTheirScreens() = runBlocking {
        val store = CloudJobs.MemoryStore().also { it.save(earlier().copy(launch = CloudJobs.launch)) }
        val server = worker("done")
        assertTrue(collect(store, server, Shelf()).isEmpty())
        assertTrue(server.requests.isEmpty())
        assertEquals(1, store.all().size)
    }

    @Test fun aFailedJobIsLetGoWithNoSet() = runBlocking {
        val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
        val server = worker("failed", "The cloud model could not write this.")
        val shelf = Shelf()
        val said = mutableListOf<String>()
        assertTrue(collect(store, server, shelf, said).isEmpty())
        assertTrue(store.all().isEmpty())
        assertTrue(shelf.sets.isEmpty())
        assertTrue(said.isEmpty())
        assertEquals(1, server.requests.count { it.method == "DELETE" && it.path == "/jobs/$id" })
    }

    @Test fun aJobGoneFromTheServerIsLetGoOnlyWhenOld() = runBlocking {
        val day = 86_400_000L
        val gone = FakeServer { BackendClient.Reply(404, "{}") }
        val fresh = CloudJobs.MemoryStore().also { it.save(earlier()) }
        collect(fresh, gone, Shelf())
        assertEquals(1, fresh.all().size)
        val old = CloudJobs.MemoryStore().also { it.save(earlier(System.currentTimeMillis() - 9 * day)) }
        collect(old, gone, Shelf())
        assertTrue(old.all().isEmpty())
        // a server error is not the job being gone, however old
        val broken = CloudJobs.MemoryStore().also { it.save(earlier(System.currentTimeMillis() - 9 * day)) }
        collect(broken, FakeServer { BackendClient.Reply(500, "{}") }, Shelf())
        assertEquals(1, broken.all().size)
    }

    @Test fun aJobOfAnotherIdentityIsKeptForAMonth() = runBlocking {
        val day = 86_400_000L
        val store = CloudJobs.MemoryStore()
        store.save(earlier().copy(identity = "account-1"))
        store.save(earlier(System.currentTimeMillis() - 31 * day).copy(id = "11111111-2222-3333-4444-555555555555", identity = "account-1"))
        val server = worker("done")
        collect(store, server, Shelf())
        assertEquals(listOf(id), store.all().map { it.id })
        assertTrue(server.requests.isEmpty())
    }

    @Test fun aDeliveredJobIsMadeFromItsKeptReplies() = runBlocking {
        val store = CloudJobs.MemoryStore()
        store.save(earlier().copy(identity = "account-1", delivered = true, notified = true, outputs = replies))
        val server = worker("done")
        val shelf = Shelf()
        val said = mutableListOf<String>()
        assertEquals(1, collect(store, server, shelf, said).size)
        assertTrue(said.single().endsWith("|Written in the cloud; the app was closed before it was saved. $PASSED"))
        assertTrue(store.all().isEmpty())
        // no bearer for that identity: the server's copy expires there on its own
        assertTrue(server.requests.isEmpty())
    }

    @Test fun repliesThatMakeNoSetAreKeptAsText() = runBlocking {
        val store = CloudJobs.MemoryStore()
        store.save(earlier().copy(delivered = true, outputs = listOf("  Not JSON at all.  ", "")))
        val shelf = Shelf()
        val said = mutableListOf<String>()
        collect(store, worker("done"), shelf, said)
        val set = shelf.sets.single()
        assertEquals("Writing 2 questions (as written)", set.name)
        assertEquals(StudySetKind.BOOK, set.kind)
        assertEquals("Not JSON at all.", set.bookMarkdown)
        assertEquals("Writing 2 questions (as written) is ready|Saved as text. It couldn't be made into questions.", said.single())
    }

    @Test fun theKeptTextNoteReadsAsASentenceForEveryKind() {
        val said = StudySetKind.values().associateWith { "It couldn't be made into ${it.cloudPhrase}." }
        assertEquals("It couldn't be made into a textbook.", said[StudySetKind.BOOK])
        assertEquals("It couldn't be made into a lecture.", said[StudySetKind.NARRATE])
        assertEquals("It couldn't be made into questions.", said[StudySetKind.MCQ])
        assertEquals("It couldn't be made into OSCE stations.", said[StudySetKind.OSCE])
        assertEquals("It couldn't be made into cards.", said[StudySetKind.ANKI])
        assertEquals("It couldn't be made into cases.", said[StudySetKind.CASES])
    }

    @Test fun theDeliveryKeepsAFinishedJobUntilTheScreenIsDone() = runBlocking {
        val jobs = FakeJobs(replies, id)
        val server = FakeServer(jobs::answer)
        val store = CloudJobs.MemoryStore()
        val at = CloudEndpoint(server.client("bearer"), "owner", null)
        val delivery = CloudJobs.Delivery()
        val spec = CloudJobs.Spec("Writing 2 questions", "loop", "questions", 2, listOf("source"), listOf(CloudJobs.Step("s", "u", 0, 100, 0.7)))
        val outputs = withContext(CloudJobs.Context(recipe(), delivery)) { CloudJobs.run(spec, at, store, pause = {}) }
        assertEquals(replies, outputs)
        val kept = store.all().single()
        assertEquals(true, kept.delivered)
        assertEquals(replies, kept.outputs)
        assertEquals(recipe(), kept.recipe)
        assertEquals(0, jobs.deleted)
        // the screen saved it: let go here and on the server
        CloudJobs.finish(delivery)
        assertTrue(store.all().isEmpty())
        assertEquals(1, jobs.deleted)
    }

    @Test fun aSystemStopHandsTheJobToTheCollector() = runBlocking {
        val jobs = FakeJobs(replies, id)
        val server = FakeServer(jobs::answer)
        val store = CloudJobs.MemoryStore()
        val at = CloudEndpoint(server.client("bearer"), "owner", null)
        val delivery = CloudJobs.Delivery()
        val spec = CloudJobs.Spec("Writing 2 questions", "loop", "questions", 2, listOf("source"), listOf(CloudJobs.Step("s", "u", 0, 100, 0.7)))
        withContext(CloudJobs.Context(recipe(), delivery)) { CloudJobs.run(spec, at, store, pause = {}) }
        delivery.stopped(CloudJobRules.Stop.system)
        CloudJobs.finish(delivery)
        val handed = store.all().single()
        assertNull(handed.launch)
        assertEquals(0, jobs.deleted)
        // the next start makes it into its set
        val shelf = Shelf()
        assertEquals(1, collect(store, server, shelf).size)
        assertEquals(2, shelf.sets.single().questions.size)
    }

    @Test fun aRecordKeepsItsRecipeAndRepliesOnDisk() {
        val folder = kotlin.io.path.createTempDirectory("cloud-jobs").toFile()
        try {
            val store = CloudJobs.FileStore(folder)
            store.save(earlier().copy(delivered = true, notified = true, outputs = replies, extra = "[[1]]"))
            val read = store.all().single()
            assertEquals(recipe(), read.recipe)
            assertEquals(replies, read.outputs)
            assertEquals(true, read.delivered)
            assertEquals("[[1]]", read.extra)
            assertTrue(CloudJobs.markNotified(id, store).not())
            assertEquals(CloudRecipe.of(read.recipe), CloudRecipe(StudySetKind.MCQ, "", "Cardiology", 2, exam = "usmle1"))
        } finally {
            folder.deleteRecursively()
        }
    }
    @Test fun aDeliveredSetSignalsTheLibraryToRedraw() = runBlocking {
        val before = CloudJobCollector.delivered.value
        val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
        collect(store, worker("running"), Shelf())
        assertEquals(before, CloudJobCollector.delivered.value)
        collect(store, worker("done"), Shelf())
        assertEquals(before + 1, CloudJobCollector.delivered.value)
    }

    @Test fun aQuestionRunTheAppWasClosedOnIsCollectedAsQuestions() = runBlocking {
        var running = true
        val server = FakeServer { request ->
            when {
                request.method == "POST" && request.path == "/jobs" ->
                    FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id).put("status", "queued")))
                // the connection is lost while it writes: the run hands the job over
                running -> BackendClient.Reply(500, "{}")
                else -> worker("done").send(request.method, request.url, null, request.bearer, 0)
            }
        }
        val llm = LLMService(FakeServer.standInKey(), { null }, FakeServer.BASE, server)
        val store = CloudJobs.MemoryStore()
        val lost = runCatching { MedicalGenerate.mcq("Hypertension lecture.", 2, "Cardiology", false, llm.backend()!!, store = store, pause = {}) }
        assertTrue(lost.exceptionOrNull() is LLMError.NotReady)
        val record = store.all().single()
        assertNull(record.launch)
        val recipe = CloudRecipe.of(record.recipe)
        assertNotNull(recipe)
        recipe!!
        assertEquals(StudySetKind.MCQ, recipe.kind)
        assertEquals("Cardiology", recipe.subject)
        assertEquals(2, recipe.count)
        running = false
        val shelf = Shelf()
        CloudJobCollector.collect(store, shelf, llm::cloudBearer, server::client)
        val set = shelf.sets.single()
        assertEquals(StudySetKind.MCQ, set.kind)
        assertEquals("Cardiology \u2013 questions", set.name)
        assertEquals(2, set.questions.size)
    }

    @Test fun twoCollectionsAtOnceMakeOneSet() = runBlocking {
        CloudJobs.io = Dispatchers.IO
        val asked = java.util.concurrent.CountDownLatch(1)
        val release = java.util.concurrent.CountDownLatch(1)
        val done = worker("done")
        val server = FakeServer { request ->
            if (request.path == "/jobs/$id") { asked.countDown(); release.await(10, java.util.concurrent.TimeUnit.SECONDS) }
            done.send(request.method, request.url, null, request.bearer, 0)
        }
        val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
        val shelf = Shelf()
        val first = async(Dispatchers.IO) { collect(store, server, shelf) }
        assertTrue(asked.await(10, java.util.concurrent.TimeUnit.SECONDS))
        // the first is still asking the server: the second finds it collecting
        assertTrue(collect(store, server, shelf).isEmpty())
        release.countDown()
        assertEquals(1, first.await().size)
        assertEquals(1, shelf.sets.size)
        assertTrue(store.all().isEmpty())
    }
    @Test fun aSetGoesToTheLibraryOfTheActivityMadeAgain() = runBlocking {
        CloudJobs.io = Dispatchers.IO
        val asked = java.util.concurrent.CountDownLatch(1)
        val release = java.util.concurrent.CountDownLatch(1)
        val done = worker("done")
        val server = FakeServer { request ->
            if (request.path == "/jobs/$id") { asked.countDown(); release.await(10, java.util.concurrent.TimeUnit.SECONDS) }
            done.send(request.method, request.url, null, request.bearer, 0)
        }
        val first = kotlin.io.path.createTempDirectory("library-first").toFile()
        val second = kotlin.io.path.createTempDirectory("library-second").toFile()
        try {
            val old = com.stethoscore.app.data.StudyStore(first)
            val fresh = com.stethoscore.app.data.StudyStore(second)
            val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
            val bearer: (String?) -> String? = { if (it == "owner") "bearer" else null }
            val app = kotlinx.coroutines.CoroutineScope(Dispatchers.IO)
            val running = CloudJobCollector.start(old, app, store, bearer, server::client)
            assertTrue(asked.await(10, java.util.concurrent.TimeUnit.SECONDS))
            // the activity is made again while the first collection asks the server
            CloudJobCollector.start(fresh, app, store, bearer, server::client).join()
            release.countDown()
            running.join()
            assertTrue(old.library.none { it.name == "Cardiology \u2013 questions" })
            assertEquals(1, fresh.library.count { it.name == "Cardiology \u2013 questions" })
            // and on disk, in the new library's file
            assertEquals(1, com.stethoscore.app.data.StudyStore(second).library.count { it.name == "Cardiology \u2013 questions" })
            assertTrue(store.all().isEmpty())
        } finally {
            first.deleteRecursively()
            second.deleteRecursively()
        }
    }

    // MARK: every kind, screened as iOS screens it (T0237)

    private val PASSED = "On-device checks passed. The independent checkers are verifying the rest now."

    private fun station(title: String) = JSONObject().put("title", title).put("steps", JSONArray(listOf(
        "Introduce yourself and confirm the patient's name", "Explain the examination and gain consent", "Wash your hands",
        "Inspect from the end of the bed", "Thank the patient")))

    private fun stationsReply(vararg titles: String) = JSONObject().put("stations", JSONArray(titles.map { station(it) })).toString()

    /** A job of an earlier run made into its set: the set, and what was announced with it. */
    private suspend fun collected(job: CloudJobs.Pending, outputs: List<String>): Pair<StudySet, String> {
        val store = CloudJobs.MemoryStore().also { it.save(job) }
        val shelf = Shelf()
        val said = mutableListOf<String>()
        collect(store, worker("done", outputs = outputs), shelf, said)
        assertTrue(store.all().isEmpty())
        return shelf.sets.single() to said.single()
    }

    @Test fun aStationRunTheAppWasClosedOnIsCollectedAsStations() = runBlocking {
        val job = earlier().copy(title = "Writing 2 stations", recipe = CloudRecipe(StudySetKind.OSCE, "", "Orthopaedics", 2).json())
        val (set, said) = collected(job, listOf(stationsReply("Knee examination", "Hip examination")))
        assertEquals(StudySetKind.OSCE, set.kind)
        assertEquals("Orthopaedics – OSCE stations", set.name)
        assertEquals(listOf("Knee examination", "Hip examination"), set.osceChecklists.map { it.title })
        assertEquals("Orthopaedics – OSCE stations is ready|Written in the cloud while the app was closed. $PASSED", said)
    }

    @Test fun aCardRunIsCollectedAsCardsWithItsDiagramCards() = runBlocking {
        val diagram = AnkiCard(id = "diagram-1", type = AnkiCardType.OCCLUSION, front = "Label the aorta", imageIndex = 0, occlusion = OcclusionBox(0.1, 0.1, 0.2, 0.2))
        val recipe = CloudRecipe(StudySetKind.ANKI, "Lupus cards", "Rheumatology", 10, diagramCards = listOf(diagram), diagramImages = listOf("picture-one"))
        val written = listOf("What spares the nasolabial folds? | the **malar** rash | lupus", "Which antibody is most specific? | **anti-dsDNA**")
        val (set, said) = collected(earlier().copy(title = "Writing 10 cards", recipe = recipe.json()), written)
        assertEquals(StudySetKind.ANKI, set.kind)
        assertEquals(listOf("What spares the nasolabial folds?", "Which antibody is most specific?", "Label the aorta"), set.cards.map { it.front })
        assertEquals(listOf("picture-one"), set.images)
        assertEquals("Lupus cards is ready|Written in the cloud while the app was closed. $PASSED", said)
    }

    @Test fun aTextbookRunIsCollectedWithItsFiguresAndLeftToTheLayerOnceSaved() = runBlocking {
        val recipe = CloudRecipe(StudySetKind.BOOK, "Lupus textbook", "Rheumatology", 1, figures = listOf("figure-zero", "figure-one"))
        val page = "## Lupus\n\n### Definition\n\nAn autoimmune disease.\n\n![The malar rash](image:1)"
        val (set, said) = collected(earlier().copy(title = "Writing 1 textbook pages", recipe = recipe.json(), extra = "[[1]]"), listOf(page))
        assertEquals(StudySetKind.BOOK, set.kind)
        assertTrue(set.bookMarkdown.contains("![The malar rash](image:0)"))
        assertEquals(listOf("figure-one"), set.images)
        assertEquals("Lupus textbook is ready|Written in the cloud while the app was closed. The verification layer checks it once the set is saved.", said)
    }

    @Test fun aCaseThatFailsTheStructureChecksIsLeftOutAndSaid() = runBlocking {
        val recipe = CloudRecipe(StudySetKind.CASES, "Knee cases", "Orthopaedics", 1)
        val thin = """{"complaint":"Pain in the knee","steps":[{"label":"Look at the knee","finding":"Red and swollen","group":"examine"}]}"""
        val (set, said) = collected(earlier().copy(title = "Writing 1 cases", recipe = recipe.json()), listOf(thin))
        assertEquals(StudySetKind.CASES, set.kind)
        assertTrue(set.caseFiles.isEmpty())
        assertEquals("Knee cases is ready|Written in the cloud while the app was closed. 1 case failed the structure or accuracy checks and was left out.", said)
    }

    @Test fun aBrokenQuestionIsRemovedWithItsReasonAndSaid() = runBlocking {
        val contradicted = question("Which drug for diabetic kidney disease?").put("explanation", "Ramipril tablets is not the correct answer.")
        val written = JSONObject().put("questions", JSONArray(listOf(question("First line for a 50-year-old?"), contradicted))).toString()
        val (set, said) = collected(earlier(), listOf(written))
        assertEquals(listOf("First line for a 50-year-old?"), set.questions.map { it.stem })
        assertEquals("Cardiology – questions is ready|Written in the cloud while the app was closed. " +
            "On-device checks: 1 removed (1 key contradicted by its explanation). The independent checkers are verifying the rest now.", said)
    }

    // the screen's own rules are pinned in accuracy.VerificationScreenTest; this is that the collector applies it and says so

    @Test fun aStationWithARedFlagIsKeptAndSaidToBeHeld() = runBlocking {
        val dose = JSONObject().put("title", "Pain relief").put("steps", JSONArray(listOf(
            "Introduce yourself and confirm the patient's name", "Check for allergies", "Give paracetamol 20 g every four hours",
            "Record the dose", "Thank the patient")))
        val job = earlier().copy(title = "Writing 2 stations", recipe = CloudRecipe(StudySetKind.OSCE, "", "Orthopaedics", 2).json())
        val written = JSONObject().put("stations", JSONArray(listOf(station("Knee examination"), dose))).toString()
        val (set, said) = collected(job, listOf(written))
        assertEquals(listOf("Knee examination", "Pain relief"), set.osceChecklists.map { it.title })
        assertEquals("Orthopaedics – OSCE stations is ready|Written in the cloud while the app was closed. " +
            "On-device checks: 1 held for a red flag. The independent checkers are verifying the rest now.", said)
    }

    // MARK: announcing (T0237)

    @Test fun theAppsAnnouncerHearsOfTheSetAStartMakes() = runBlocking {
        val said = mutableListOf<Triple<String, String, String>>()
        CloudJobCollector.announcer = CloudJobCollector.Announce { title, body, setId -> said += Triple(title, body, setId) }
        val folder = kotlin.io.path.createTempDirectory("library-announce").toFile()
        try {
            val library = com.stethoscore.app.data.StudyStore(folder)
            val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
            val bearer: (String?) -> String? = { if (it == "owner") "bearer" else null }
            CloudJobCollector.start(library, kotlinx.coroutines.CoroutineScope(Dispatchers.Unconfined), store, bearer, worker("done")::client).join()
            val set = library.library.single { it.name == "Cardiology – questions" }
            assertEquals(listOf(Triple("Cardiology – questions is ready", "Written in the cloud while the app was closed. $PASSED", set.id)), said)
        } finally {
            folder.deleteRecursively()
        }
    }

    @Test fun anAnnouncerGivenToACollectionIsTheOneHeard() = runBlocking {
        val app = mutableListOf<String>()
        CloudJobCollector.announcer = CloudJobCollector.Announce { title, _, _ -> app += title }
        val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
        val said = mutableListOf<String>()
        collect(store, worker("done"), Shelf(), said)
        assertEquals(1, said.size)
        assertTrue(app.isEmpty())
    }

    @Test fun aSetThatCannotBeMadeIsNeverAnnounced() = runBlocking {
        val said = mutableListOf<String>()
        // not on disk, still running, failed: nothing to say in any of them
        collect(CloudJobs.MemoryStore().also { it.save(earlier()) }, worker("done"), Shelf(onDisk = false), said)
        collect(CloudJobs.MemoryStore().also { it.save(earlier()) }, worker("running"), Shelf(), said)
        collect(CloudJobs.MemoryStore().also { it.save(earlier()) }, worker("failed", "no"), Shelf(), said)
        assertTrue(said.isEmpty())
    }

    @Test fun aNotificationThatFailsDoesNotMakeTheSetTwice() = runBlocking {
        val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
        val shelf = Shelf()
        val made = CloudJobCollector.collect(store, shelf, { if (it == "owner") "bearer" else null }, worker("done")::client,
            announce = { _, _, _ -> throw IllegalStateException("no channel") })
        assertEquals(1, made.size)
        assertTrue(store.all().isEmpty())
        assertEquals(1, shelf.sets.size)
    }

    // MARK: iOS CloudJobRetryTests, check for check (T0237)
    // A finished job's result that fails to download is asked for again, with
    // waits between, while its screen waits; given up, the job is handed to the
    // collector and the student told it is not lost (audit #93). A job whose
    // generation the system stopped is handed over too, never deleted (#94) -
    // unless the stop may have been the student's own.

    private val handOver = CloudJobRules.Retry.HandOver

    @Test fun noSignalOrAServerErrorIsAskedAgainWaitingLongerEachTime() {
        assertEquals("no signal: asked again in two seconds", CloudJobRules.Retry.After(2.0), CloudJobRules.afterFailedFetch(1, null))
        val waits = mutableListOf<Double>()
        var failed = 0
        while (true) {
            val next = CloudJobRules.afterFailedFetch(failed + 1, 503) as? CloudJobRules.Retry.After ?: break
            failed += 1
            waits += next.seconds
            if (failed > 100) break
        }
        assertEquals("a server error is asked again ${CloudJobRules.fetchWaits.size} times, then handed over", CloudJobRules.fetchWaits.size, failed)
        assertEquals("with the waits in order: $waits", CloudJobRules.fetchWaits, waits)
        assertTrue("each wait no shorter than the one before", waits.zipWithNext().all { (a, b) -> a <= b })
        val total = waits.sum()
        assertTrue("about two minutes in all while the screen waits ($total s)", total in 60.0..180.0)
        assertEquals("past the last wait, handed over to the collector", handOver, CloudJobRules.afterFailedFetch(CloudJobRules.fetchWaits.size + 1, null))
        for (code in listOf(429, 500, 502, 503, 504)) {
            assertNotEquals("HTTP $code is worth asking again", handOver, CloudJobRules.afterFailedFetch(1, code))
        }
    }

    @Test fun answersAskingAgainCannotChangeAreHandedOverAtOnce() {
        for (code in listOf(401, 403, 404)) {
            assertEquals("HTTP $code is handed over at once, not retried", handOver, CloudJobRules.afterFailedFetch(1, code))
        }
        assertEquals("a count of nothing failed is not a reason to wait", handOver, CloudJobRules.afterFailedFetch(0, null))
    }

    /** What the screen ends with, for a server that fails [times] times in a row with [status] and then answers: whether it got the result, and how long it waited. */
    private fun screenFailing(times: Int, status: Int?): Pair<Boolean, Double> {
        var tries = 0
        var waited = 0.0
        while (true) {
            tries += 1
            if (tries > times) return true to waited
            when (val next = CloudJobRules.afterFailedFetch(tries, status)) {
                is CloudJobRules.Retry.After -> waited += next.seconds
                CloudJobRules.Retry.HandOver -> return false to waited
            }
        }
    }

    @Test fun aFetchThatFailsSomeTimesThenWorks() {
        assertTrue("a fetch that works is not delayed", screenFailing(0, null).first)
        assertEquals("not by a second", 0.0, screenFailing(0, null).second, 0.0)
        assertTrue("one dropped request no longer loses the wait", screenFailing(1, null).first)
        assertTrue("a server that blinks for a few seconds is waited out", screenFailing(3, 502).first)
        assertTrue("so is a lift with no signal, up to the last wait", screenFailing(CloudJobRules.fetchWaits.size, null).first)
        assertFalse("longer than that, the collector takes over", screenFailing(CloudJobRules.fetchWaits.size + 1, null).first)
        assertFalse("and a job the server does not know is handed over at once", screenFailing(1, 404).first)
    }

    @Test fun aGenerationStoppedPartWayIsDeletedOnlyWhenTheStudentStoppedIt() {
        assertEquals("the student's Cancel stops the cloud job and forgets it, as asked", CloudJobRules.StopFate.delete, CloudJobRules.afterStop(CloudJobRules.Stop.student))
        assertEquals("the system stopping the work leaves the job to finish, for the collector", CloudJobRules.StopFate.handOver, CloudJobRules.afterStop(CloudJobRules.Stop.system))
        // the expiration handler cannot tell the system from the student's Stop on
        // the progress indicator, which is shown only while the app is away
        assertEquals("an expiry on screen is the system's: the job is kept", CloudJobRules.Stop.system, CloudJobRules.stopAtExpiry(true))
        assertEquals("an expiry while away may be the student's Stop on the progress indicator, and is honoured as one", CloudJobRules.Stop.student, CloudJobRules.stopAtExpiry(false))
        assertEquals("so a set stopped from the indicator is not written on and put in the library",
            CloudJobRules.StopFate.delete, CloudJobRules.afterStop(CloudJobRules.stopAtExpiry(false)))
    }

    @Test fun whatTheStudentIsToldWhenAResultCannotBeDownloaded() {
        val told = CloudJobRules.handedOverMessage("Your 40 questions")
        assertTrue("the message names what was written: $told", told.startsWith("Your 40 questions"))
        assertTrue("says nothing is lost", told.contains("Nothing is lost"))
        assertTrue("and where it will be", told.contains("library"))
        assertFalse("without calling it an error", told.lowercase().contains("error"))
    }

    // the same rules, as the code that asks the server follows them

    private fun fetching(failures: Int, status: Int): FakeServer {
        var left = failures
        return FakeServer { request ->
            when {
                request.path.endsWith("?outputs=1") && left-- > 0 -> BackendClient.Reply(status, "{}")
                request.path.endsWith("?outputs=1") ->
                    FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id)).put("outputs", JSONArray(replies)))
                else -> BackendClient.Reply(404, "{}")
            }
        }
    }

    @Test fun theScreenWaitsOutAFailingFetchAndGetsTheReplies() = runBlocking {
        val waited = mutableListOf<Long>()
        val got = CloudJobs.resultRetrying(id, CloudEndpoint(fetching(3, 502).client("bearer"), "owner", null), pause = { waited += it })
        assertEquals(replies, got)
        assertEquals(listOf(2_000L, 4_000L, 8_000L), waited)
    }

    @Test fun aJobTheServerDoesNotKnowIsGivenUpOnAtOnce() = runBlocking {
        val waited = mutableListOf<Long>()
        val server = fetching(1, 404)
        val failure = runCatching { CloudJobs.resultRetrying(id, CloudEndpoint(server.client("bearer"), "owner", null), pause = { waited += it }) }.exceptionOrNull()
        assertEquals(404, (failure as LLMError.Http).status)
        assertTrue(waited.isEmpty())
        assertEquals(1, server.requests.size)
    }

    @Test fun aServerThatStaysDownIsGivenUpOnAfterTheLastWait() = runBlocking {
        val waited = mutableListOf<Long>()
        val server = fetching(1_000, 503)
        val failure = runCatching { CloudJobs.resultRetrying(id, CloudEndpoint(server.client("bearer"), "owner", null), pause = { waited += it }) }.exceptionOrNull()
        assertEquals(503, (failure as LLMError.Http).status)
        assertEquals(CloudJobRules.fetchWaits.map { (it * 1000).toLong() }, waited)
        assertEquals(CloudJobRules.fetchWaits.size + 1, server.requests.size)
    }

    @Test fun aResultThatCannotBeDownloadedIsLeftForTheNextCollection() = runBlocking {
        var down = true
        val done = worker("done")
        val server = FakeServer { request ->
            if (down && request.path.endsWith("?outputs=1")) BackendClient.Reply(502, "{}")
            else done.send(request.method, request.url, null, request.bearer, 0)
        }
        val store = CloudJobs.MemoryStore().also { it.save(earlier()) }
        val shelf = Shelf()
        assertTrue(collect(store, server, shelf).isEmpty())
        // finished on the server, kept on both sides until it can be read
        assertEquals(listOf(id), store.all().map { it.id })
        assertEquals(0, server.requests.count { it.method == "DELETE" })
        down = false
        assertEquals(1, collect(store, server, shelf).size)
        assertTrue(store.all().isEmpty())
        assertEquals(1, server.requests.count { it.method == "DELETE" && it.path == "/jobs/$id" })
    }

    @Test fun aSessionThatRanOutOrAServerThatIsBusyDoesNotLoseAnOldJob() = runBlocking {
        val old = System.currentTimeMillis() - 9 * 86_400_000L
        for (code in listOf(401, 403, 429, 503)) {
            val store = CloudJobs.MemoryStore().also { it.save(earlier(old)) }
            collect(store, FakeServer { BackendClient.Reply(code, "{}") }, Shelf())
            assertEquals("HTTP $code is not the job being gone", 1, store.all().size)
        }
    }
}
