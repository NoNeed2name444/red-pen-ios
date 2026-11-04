package com.stethoscore.app.llm

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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** T0172: the collector and the Delivery, ported from iOS CloudJobCollector.swift and CloudJobs.swift. */
class CloudJobCollectorTest {
    private val id = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private var ioBefore: CoroutineDispatcher = Dispatchers.IO
    private var ranOn: Thread? = null

    @Before fun inPlace() {
        ioBefore = CloudJobs.io
        CloudJobs.io = Dispatchers.Unconfined
    }

    @After fun restore() { CloudJobs.io = ioBefore }

    private fun question(stem: String) = JSONObject().put("stem", stem)
        .put("options", JSONArray(listOf("Atenolol tablets", "Amlodipine tablets", "Ramipril tablets", "Indapamide tablets")))
        .put("correctIndex", 2).put("explanation", "Key point: ACE inhibitors first.")

    private val replies = listOf(JSONObject().put("questions", JSONArray(listOf(question("First line for a 50-year-old?"), question("Which drug for diabetic kidney disease?")))).toString())

    private fun recipe() = CloudRecipe(StudySetKind.MCQ, "", "Cardiology", 2, exam = "usmle1").json()

    /** A record from an earlier run of the app. */
    private fun earlier(started: Long = System.currentTimeMillis()) =
        CloudJobs.Pending(id, "Writing 2 questions", started, launch = "an-earlier-run", total = 2, identity = "owner", recipe = recipe())

    private fun worker(status: String, error: String? = null) = FakeServer { request ->
        when {
            request.method == "GET" && request.path == "/jobs/$id" ->
                FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id).put("status", status).put("done", 2).put("total", 2).put("error", error ?: JSONObject.NULL)))
            request.method == "GET" && request.path == "/jobs/$id?outputs=1" ->
                FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id)).put("outputs", JSONArray(replies)))
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
        assertEquals(listOf("Cardiology – questions is ready|Written in the cloud while the app was closed. The verification layer checks it once the set is saved."), said)
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
        assertTrue(said.single().endsWith("|Written in the cloud; the app was closed before it was saved. The verification layer checks it once the set is saved."))
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
        assertEquals("Writing 2 questions (as written) is ready|Kept as text — it could not be turned into questions.", said.single())
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
}
