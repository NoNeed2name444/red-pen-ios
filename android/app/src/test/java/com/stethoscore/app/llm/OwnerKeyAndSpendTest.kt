package com.stethoscore.app.llm

import com.stethoscore.app.BuildConfig
import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.accuracy.AccuracyKind
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class OwnerKeyAndSpendTest {

    private fun service(ownerKey: String, server: FakeServer, session: String? = null, spend: OwnerSpend = OwnerSpend(OwnerSpend.MemoryStore())) =
        LLMService(LLMService.MemoryPrefs().also { it.set(LLMService.CHOICE_KEY, "cloud") }, ownerKey, { session }, FakeServer.BASE, server, spend)

    private val item = AccuracyItem("q1", AccuracyKind.mcq, stem = "Which drug?", options = listOf("A drug", "B drug", "C drug", "D drug"), key = 0, explanation = "Because.")

    // A3: the default build

    @Test fun aDefaultBuildHasNoOwnerKey() {
        assertEquals("", BuildConfig.OWNER_KEY)
        val server = FakeServer()
        val llm = service(BuildConfig.OWNER_KEY, server)
        assertFalse(llm.isPersonal)
        assertFalse(llm.isPro)
        assertNull(llm.cloudToken)
        assertFalse(llm.usesOwnerKey)
    }

    @Test fun aDefaultBuildSendsNoOwnerBearer() = runBlocking {
        val server = FakeServer { FakeServer.chat("{}") }
        val llm = service(BuildConfig.OWNER_KEY, server)
        // exactly the iOS public build without Pro: the cloud is Pro's, nothing is sent
        assertEquals("Stethoscore Cloud is part of Pro.", llm.cloudBlocker)
        assertNull(llm.backend())
        assertNull(llm.summary())
        val (said, reply) = AccuracyCheck.checkNow(item, llm)
        assertEquals("Stethoscore Cloud is part of Pro.", said)
        assertNull(reply)
        assertTrue(server.requests.isEmpty())
    }

    @Test fun aDefaultBuildWithASessionStillDoesNotUseTheCloud() {
        val server = FakeServer()
        val llm = service(BuildConfig.OWNER_KEY, server, session = "a-session")
        // the session is a bearer, but Android has no Pro: the cloud stays shut
        assertEquals("Stethoscore Cloud is part of Pro.", llm.cloudBlocker)
        assertNull(llm.backend())
        assertTrue(server.requests.none { it.bearer != null && it.bearer == BuildConfig.OWNER_KEY })
    }

    @Test fun aShortKeyIsNoOwnerKey() {
        val llm = service("k".repeat(31), FakeServer())
        assertFalse(llm.isPersonal)
        assertNull(llm.backend())
    }

    @Test fun thePersonalBuildSendsTheOwnerKeyOnlyToTheWorker() = runBlocking {
        val key = FakeServer.standInKey()
        val server = FakeServer { FakeServer.chat("hello") }
        val llm = service(key, server)
        assertTrue(llm.isPersonal)
        assertNull(llm.cloudBlocker)
        assertEquals("Stethoscore Cloud, hosted", llm.summary())
        val backend = llm.backend() as HostedLLMClient
        assertEquals("owner", backend.jobs?.identity)
        assertEquals("hello", backend.complete(listOf(ChatTurn.user("hi")), 100, 0.2))
        val sent = server.requests.single()
        assertEquals("${FakeServer.BASE}/v1/chat/completions", sent.url)
        assertEquals(key, sent.bearer)
        assertEquals("cramdown-writer", sent.body?.getString("model"))
        assertEquals(100, sent.body?.getInt("max_tokens"))
        // the key is never in what the student can read
        assertFalse(llm.cloudBlocker.orEmpty().contains(key))
        assertFalse(llm.spend.said.contains(key))
    }

    @Test fun aSessionIsSentBeforeTheOwnerKeyAndIsNotCounted() = runBlocking {
        val server = FakeServer { FakeServer.chat("hello") }
        val llm = service(FakeServer.standInKey(), server, session = "a-session")
        assertFalse(llm.usesOwnerKey)
        llm.backend()!!.complete(listOf(ChatTurn.user("hi")), 100, 0.2)
        assertEquals("a-session", server.requests.single().bearer)
        assertEquals(0L, llm.spend.spentMicros)
    }

    // A3: counting and the $20.00 cap

    @Test fun usageIsPricedLikeTheAnthropicRoute() {
        // $4 a million in, $20 a million out: micro-dollars are tokens times the price
        assertEquals(1_000L * 4 + 500L * 20, OwnerSpend.costMicros(JSONObject().put("input_tokens", 1000).put("output_tokens", 500)))
        assertEquals(1_000L * 4 + 500L * 20, OwnerSpend.costMicros(JSONObject().put("prompt_tokens", 1000).put("completion_tokens", 500)))
        // cache reads at a tenth, cache writes at 1.25
        assertEquals(1_000L * 4 + 100L * 4 + 125L * 4, OwnerSpend.costMicros(JSONObject().put("input_tokens", 1000)
            .put("cache_read_input_tokens", 1000).put("cache_creation_input_tokens", 100)))
        assertNull(OwnerSpend.costMicros(JSONObject().put("total", 3)))
        assertEquals("$0.01", OwnerSpend.dollars(14_000))
    }

    @Test fun aReplyWithUsageIsCountedFromIt() = runBlocking {
        val server = FakeServer { FakeServer.chat("ok", JSONObject().put("input_tokens", 2000).put("output_tokens", 300)) }
        val llm = service(FakeServer.standInKey(), server)
        llm.backend()!!.complete(listOf(ChatTurn.system("rules"), ChatTurn.user("go")), 4000, 0.7)
        assertEquals(2_000L * 4 + 300L * 20, llm.spend.spentMicros)
    }

    @Test fun aReplyWithNoUsageIsCountedAtItsMaxTokens() = runBlocking {
        val server = FakeServer { FakeServer.chat("ok") }
        val llm = service(FakeServer.standInKey(), server)
        val system = "x".repeat(2_999)
        llm.backend()!!.complete(listOf(ChatTurn.system(system), ChatTurn.user("go")), 3_800, 0.7)
        // 3,001 characters at three a token: 1,001 tokens in; 3,800 out, the most it could have been
        assertEquals(1_001L * 4 + 3_800L * 20, llm.spend.spentMicros)
        assertEquals(OwnerSpend.estimateMicros(3_001, 3_800), llm.spend.spentMicros)
    }

    @Test fun theOwnerKeyStopsAtTwentyDollars() = runBlocking {
        val server = FakeServer { FakeServer.chat("ok") }
        val store = OwnerSpend.MemoryStore(19_990_000)
        val llm = service(FakeServer.standInKey(), server, spend = OwnerSpend(store))
        assertEquals("$19.99 of $20.00", llm.spend.said)
        val backend = llm.backend()!!
        // under the cap: sent, and counted past it (1,000 out is $0.02)
        backend.complete(listOf(ChatTurn.user("go")), 1_000, 0.7)
        assertEquals(1, server.requests.size)
        assertTrue(llm.spend.capReached)
        // at the cap: the backend already handed out stops without sending
        try {
            backend.complete(listOf(ChatTurn.user("again")), 1_000, 0.7)
            fail("sent past the cap")
        } catch (e: LLMError.NotReady) {
            assertEquals(OwnerSpend.CAP_REACHED, e.message)
        }
        assertEquals(1, server.requests.size)
        // and the service says so plainly, and gives out no backend
        assertEquals(OwnerSpend.CAP_REACHED, llm.cloudBlocker)
        assertNull(llm.backend())
        assertEquals(OwnerSpend.CAP_REACHED, AccuracyCheck.checkNow(item, llm).first)
        assertEquals(1, server.requests.size)
    }

    @Test fun exactlyTwentyDollarsIsTheCap() {
        val spend = OwnerSpend(OwnerSpend.MemoryStore(20_000_000))
        assertTrue(spend.capReached)
        assertEquals("$20.00 of $20.00", spend.said)
        assertFalse(OwnerSpend(OwnerSpend.MemoryStore(19_999_999)).capReached)
    }

    @Test fun aSessionIsNotStoppedByTheOwnerCap() {
        val llm = service(FakeServer.standInKey(), FakeServer(), session = "a-session", spend = OwnerSpend(OwnerSpend.MemoryStore(25_000_000)))
        assertNull(llm.cloudBlocker)
    }
}
