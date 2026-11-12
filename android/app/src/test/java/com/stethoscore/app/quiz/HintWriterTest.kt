package com.stethoscore.app.quiz

import com.stethoscore.app.llm.ChatTurn
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMBackend
import com.stethoscore.app.llm.LLMError
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import kotlinx.coroutines.CancellationException
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
import java.io.File
import java.io.IOException

// "Hint Me" in the quiz, step by step: the writer is asked first; a hint kept
// from before costs nothing; no writer, a writer that fails and a reply the
// acceptance rule refuses all end in the attending's own hint; and a hint that
// names the answer is never shown. The model is a stand-in: nothing goes on
// the network. iOS keeps this logic in ExamStore's HintWriter, which its tests
// do not reach (the writer is a singleton there), so the cases are made here
// from its rules.
class HintWriterTest {
    @get:Rule val folder = TemporaryFolder()

    private val stem = "A 30-year-old woman has heat intolerance, a diffuse goitre and exophthalmos."
    private val options = listOf("Graves disease", "Toxic multinodular goitre", "Subacute thyroiditis", "Hashimoto thyroiditis")
    private val answer = options[0]
    private val others = options.drop(1)
    private val nudge = "What does eye involvement tell you about the cause?"
    private val tiers = DifferentialTiers(
        mostLikely = listOf(DifferentialEntry("Graves disease", supporting = listOf("Exophthalmos"))),
        expanded = listOf(DifferentialEntry("Toxic multinodular goitre", against = listOf("A diffuse, not nodular, goitre"))),
    )

    /** The file of the store last made by [freshStore]. */
    private lateinit var file: File

    /** A store on a file of its own, in a folder of its own: nothing is shared between scenes. */
    private fun freshStore(): HintStore {
        file = File(folder.newFolder(), HintStore.FILE_NAME)
        return HintStore(file)
    }

    /** The stand-in writer: counts its calls and keeps what it was asked. */
    private class Writer(val reply: () -> String) : LLMBackend {
        override val label = "Stand-in"
        override val isOnDevice = false
        override val promptBudgetChars = 40_000
        var calls = 0
        var turns: List<ChatTurn> = emptyList()
        var maxTokens = -1
        var temperature = -1.0
        override suspend fun complete(turns: List<ChatTurn>, maxTokens: Int, temperature: Double): String {
            calls += 1
            this.turns = turns
            this.maxTokens = maxTokens
            this.temperature = temperature
            return reply()
        }
    }

    private fun ask(store: HintStore, backend: LLMBackend?, id: String = "q1", shownAnswer: String = answer,
                    differential: DifferentialTiers? = tiers): String = runBlocking {
        HintWriter.hint(id, stem, options, shownAnswer, differential, backend, store)
    }

    private fun fallback(differential: DifferentialTiers? = tiers) = AttendingHint.fallback(answer, stem, options, differential)

    // MARK: the writer first

    @Test fun theWriterIsAskedFirstAndItsTidiedReplyIsShown() {
        val store = freshStore()
        val writer = Writer { "Hint: $nudge" }
        assertEquals(nudge, ask(store, writer))
        assertEquals(1, writer.calls)
        assertEquals("the brief, then the item", listOf(ChatTurn.Role.system, ChatTurn.Role.user), writer.turns.map { it.role })
        assertEquals(AttendingHint.instructions, writer.turns[0].text)
        assertEquals(AttendingHint.input(stem, options, answer, tiers), writer.turns[1].text)
        assertTrue("the expert's differential goes with it", writer.turns[1].text.contains("The expert's differential:"))
        assertEquals(160, writer.maxTokens)
        assertEquals(0.4, writer.temperature, 0.0)
    }

    // MARK: kept hints

    @Test fun aHintKeptBeforeDoesNotCallTheWriter() {
        val store = freshStore()
        val writer = Writer { nudge }
        assertEquals(nudge, ask(store, writer))
        assertEquals(nudge, ask(store, writer))
        assertEquals("the second ask is served from what was kept", 1, writer.calls)
        // after a relaunch: a new store on the same file, a new writer
        val later = Writer { "This one must never be asked for." }
        assertEquals(nudge, ask(HintStore(file), later))
        assertEquals(0, later.calls)
    }

    @Test fun aHintIsKeptOnlyForTheWordingItWasWrittenFor() {
        val store = freshStore()
        val writer = Writer { nudge }
        ask(store, writer)
        assertEquals("a corrected key is a new question", nudge, ask(store, writer, shownAnswer = options[1]))
        assertEquals(2, writer.calls)
        assertEquals("another item is its own", nudge, ask(store, writer, id = "q2"))
        assertEquals(3, writer.calls)
        assertEquals(3, store.count)
    }

    @Test fun aKeptHintThatNamesTheAnswerIsNotShown() {
        val store = freshStore()
        store.keep("It is Graves disease, look at the eyes.", "q1", HintCache.version(stem, options, answer))
        val writer = Writer { nudge }
        assertEquals(nudge, ask(store, writer))
        assertEquals("it was asked for again", 1, writer.calls)
        assertEquals("and the good one took its place", nudge, store.hint("q1", HintCache.version(stem, options, answer)))
        // with no writer, the leaking hint gives way to the fallback
        val other = freshStore()
        other.keep("It is Graves disease, look at the eyes.", "q1", HintCache.version(stem, options, answer))
        assertEquals(fallback(), ask(other, null))
        assertFalse(AttendingHint.leaks(fallback(), answer, stem, others))
    }

    // MARK: without the writer

    @Test fun withNoWriterTheHintIsTheAttendingsOwnAndNothingIsKept() {
        val store = freshStore()
        assertEquals(fallback(), ask(store, null))
        assertEquals(fallback(null), ask(store, null, differential = null))
        assertTrue("the fixed nudge when there is no differential", fallback(null).contains("most specific finding"))
        assertEquals(0, store.count)
        assertFalse("nothing was written", file.exists())
    }

    @Test fun aWriterThatFailsGivesTheFallbackAndKeepsNothing() {
        val store = freshStore()
        for (failure in listOf<() -> Nothing>(
            { throw LLMError.NotReady("The server could not be reached.") },
            { throw LLMError.Http(500, "boom") },
            { throw LLMError.EmptyReply() },
            { throw IOException("offline") },
            { throw IllegalStateException("odd") },
        )) {
            val writer = Writer { failure() }
            assertEquals(fallback(), ask(store, writer))
            assertEquals(1, writer.calls)
        }
        assertEquals("a failure is not kept, so the next ask tries again", 0, store.count)
        val again = Writer { nudge }
        assertEquals(nudge, ask(store, again))
        assertEquals(1, again.calls)
    }

    @Test fun aReplyTheAcceptanceRuleRefusesGivesTheFallbackAndKeepsNothing() {
        val store = freshStore()
        for (reply in listOf("Think of Graves disease.", "Hint: it's Graves disease", "Hmm", "", "   ", "“Look closer”")) {
            val writer = Writer { reply }
            val shown = ask(store, writer)
            assertEquals("'$reply'", fallback(), shown)
            assertFalse("'$reply' shown: $shown", AttendingHint.leaks(shown, answer, stem, others))
        }
        assertEquals(0, store.count)
    }

    @Test fun aCancelledAskIsPassedOnNotAnswered() {
        val store = freshStore()
        val writer = Writer { throw CancellationException("the screen was left") }
        val cancelled = runBlocking {
            try { HintWriter.hint("q1", stem, options, answer, tiers, writer, store); false } catch (e: CancellationException) { true }
        }
        assertTrue(cancelled)
        assertEquals("and nothing is kept for it", 0, store.count)
    }

    // MARK: where the app may call a model

    @Test fun theModelIsUsedOnlyWhereTheAppAllowsAModelCall() {
        val server = FakeServer { FakeServer.chat(nudge) }
        // a public build: no owner key, no session, so no writer and nothing is sent
        val publicBuild = LLMService("", { null }, FakeServer.BASE, server)
        assertNull(publicBuild.backend())
        assertEquals(fallback(), ask(freshStore(), publicBuild.backend()))
        assertTrue(server.requests.isEmpty())

        // the owner's build: one call to the worker's chat route, counted against the cap
        val spend = OwnerSpend(OwnerSpend.MemoryStore())
        val ownerBuild = LLMService(FakeServer.standInKey(), { null }, FakeServer.BASE, server, spend)
        val owner = freshStore()
        assertEquals(nudge, ask(owner, ownerBuild.backend()))
        val sent = server.requests.single()
        assertEquals("/v1/chat/completions", sent.path)
        assertEquals(FakeServer.standInKey(), sent.bearer)
        val messages: JSONArray = sent.body!!.getJSONArray("messages")
        assertEquals("system", messages.getJSONObject(0).getString("role"))
        assertEquals(AttendingHint.instructions, messages.getJSONObject(0).getString("content"))
        assertEquals(160, sent.body!!.getInt("max_tokens"))
        assertTrue("the call was counted", spend.spentMicros > 0)
        // asked again, it costs nothing
        assertEquals(nudge, ask(owner, ownerBuild.backend()))
        assertEquals(1, server.requests.size)

        // the cap reached: no writer, nothing more is sent
        val full = LLMService(FakeServer.standInKey(), { null }, FakeServer.BASE, server, OwnerSpend(OwnerSpend.MemoryStore(OwnerSpend.CAP_MICROS)))
        assertNull(full.backend())
        assertEquals(fallback(), ask(freshStore(), full.backend()))
        assertEquals(1, server.requests.size)
    }

    @Test fun aWorkerThatRefusesGivesTheFallbackAndKeepsNothing() {
        val server = FakeServer { com.stethoscore.app.network.BackendClient.Reply(429, "Too many requests just now.") }
        val ownerBuild = LLMService(FakeServer.standInKey(), { null }, FakeServer.BASE, server, OwnerSpend(OwnerSpend.MemoryStore()))
        val store = freshStore()
        assertEquals(fallback(), ask(store, ownerBuild.backend()))
        assertEquals(1, server.requests.size)
        assertEquals(0, store.count)
    }

    // MARK: the file

    @Test fun theStoreKeepsTheShapeIosKeepsAndReadsItBack() {
        val store = freshStore()
        store.keep("one", "id-1", "v1")
        store.keep("two", "id-2")
        val saved = JSONObject(file.readText())
        assertEquals("one", saved.getJSONObject("hints").getString("id-1#v1"))
        assertEquals("two", saved.getJSONObject("hints").getString("id-2"))
        assertEquals(listOf("id-1#v1", "id-2"), (0 until saved.getJSONArray("order").length()).map { saved.getJSONArray("order").getString(it) })
        assertFalse("no half-written file is left", File(file.parentFile, HintStore.FILE_NAME + ".tmp").exists())
        val again = HintStore(file)
        assertEquals("one", again.hint("id-1", "v1"))
        assertEquals("two", again.hint("id-2"))
        assertNull(again.hint("id-1"))
    }

    @Test fun theOldestGoPastTheCapEvenOnTheWayIn() {
        file = File(folder.newFolder(), HintStore.FILE_NAME)
        val total = HintCache.cap + 5
        val hints = JSONObject()
        val order = JSONArray()
        for (i in 0 until total) { hints.put("k$i", "hint $i"); order.put("k$i") }
        file.writeText(JSONObject().put("hints", hints).put("order", order).toString())
        val store = HintStore(file)
        assertEquals(HintCache.cap, store.count)
        assertNull("the oldest are gone", store.hint("k0"))
        assertNotNull(store.hint("k5"))
        store.keep("newest", "k-new")
        assertEquals(HintCache.cap, store.count)
        assertNull(store.hint("k5"))
        assertEquals("newest", HintStore(file).hint("k-new"))
    }

    @Test fun aFileThatCannotBeReadIsReadAsEmptyAndReplacedByTheNextWrite() {
        file = File(folder.newFolder(), HintStore.FILE_NAME)
        file.writeText("{this is not json")
        val store = HintStore(file)
        assertNull(store.hint("id"))
        assertEquals(nudge, ask(store, Writer { nudge }))
        assertEquals(nudge, HintStore(file).hint("q1", HintCache.version(stem, options, answer)))
    }

    @Test fun aWriteThatFailsLosesNothingForThisLaunch() {
        // the file's folder is a plain file, so nothing can be written there
        val blocker = folder.newFile("blocker")
        val store = HintStore(File(blocker, HintStore.FILE_NAME))
        val writer = Writer { nudge }
        assertEquals(nudge, ask(store, writer))
        assertEquals(nudge, ask(store, writer))
        assertEquals("still kept in memory", 1, writer.calls)
    }
}
