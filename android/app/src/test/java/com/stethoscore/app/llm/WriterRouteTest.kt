package com.stethoscore.app.llm

import com.stethoscore.app.BuildConfig
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// There is no writer to choose (the owner, 22 Oct): every text job goes to the
// worker's writer route, "cramdown-writer", which the worker sends to its Claude
// route for the owner key (server/tests/owner-claude.test.mjs). The gates stay:
// the owner key only in the personal build, Pro's cloud otherwise shut, and this
// phone's $20.00 cap.
class WriterRouteTest {
    private fun service(key: String, server: FakeServer, spent: Long = 0) =
        LLMService(key, { null }, FakeServer.BASE, server, OwnerSpend(OwnerSpend.MemoryStore(spent)))

    @Test fun theWriterIsAlwaysTheWorkersWriterRoute() = runBlocking {
        val server = FakeServer { FakeServer.chat("written") }
        val llm = service(FakeServer.standInKey(), server)
        // nothing set, nothing to set: the writer is there from the first launch
        val writer = llm.backend() as HostedLLMClient
        assertEquals("Stethoscore Cloud", writer.label)
        for (role in LLMRole.entries) assertEquals("cramdown-writer", (llm.backend(role) as HostedLLMClient).provider.model)
        assertEquals("written", writer.complete(listOf(ChatTurn.user("Write one question.")), 50, 0.2))
        val sent = server.requests.single()
        assertEquals("${FakeServer.BASE}/v1/chat/completions", sent.url)
        assertEquals("cramdown-writer", sent.body?.getString("model"))
    }

    @Test fun theGatesStillHold() {
        // the public build: no owner key, the cloud is Pro's, nothing is sent
        val shut = FakeServer()
        val public = service(BuildConfig.OWNER_KEY, shut)
        assertNull(public.backend())
        assertEquals("Stethoscore Cloud is part of Pro.", public.cloudBlocker)
        assertTrue(shut.requests.isEmpty())
        // the personal build at its cap: stopped, nothing more is sent
        val capped = FakeServer()
        val owner = service(FakeServer.standInKey(), capped, spent = OwnerSpend.CAP_MICROS)
        assertNull(owner.backend())
        assertEquals(OwnerSpend.CAP_REACHED, owner.cloudBlocker)
        assertTrue(capped.requests.isEmpty())
    }
}
