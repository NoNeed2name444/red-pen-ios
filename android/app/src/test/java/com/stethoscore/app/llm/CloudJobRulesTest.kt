package com.stethoscore.app.llm

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A1: the job rules, the pending records and the reply parsing ported from iOS. */
class CloudJobRulesTest {

    @Test fun onlyA404IsGone() {
        assertEquals(CloudJobRules.Answer.Gone, CloudJobRules.answerForFailedStatus(404))
        assertEquals(CloudJobRules.Answer.Unreachable, CloudJobRules.answerForFailedStatus(500))
        assertEquals(CloudJobRules.Answer.Unreachable, CloudJobRules.answerForFailedStatus(null))
    }

    @Test fun aRecordIsLetGoOnlyWhenLongGone() {
        val day = 86_400_000L
        assertFalse(CloudJobRules.letGo(0, CloudJobRules.Answer.Gone, true, 7 * day))
        assertTrue(CloudJobRules.letGo(0, CloudJobRules.Answer.Gone, true, 9 * day))
        assertFalse(CloudJobRules.letGo(0, CloudJobRules.Answer.Unreachable, true, 90 * day))
        assertFalse(CloudJobRules.letGo(0, CloudJobRules.Answer.Unreachable, false, 29 * day))
        assertTrue(CloudJobRules.letGo(0, CloudJobRules.Answer.Unreachable, false, 31 * day))
    }

    @Test fun aFailedFetchWaitsThenHandsOver() {
        assertEquals(CloudJobRules.Retry.After(2.0), CloudJobRules.afterFailedFetch(1, 500))
        assertEquals(CloudJobRules.Retry.After(30.0), CloudJobRules.afterFailedFetch(7, null))
        assertEquals(CloudJobRules.Retry.HandOver, CloudJobRules.afterFailedFetch(8, null))
        assertEquals(CloudJobRules.Retry.HandOver, CloudJobRules.afterFailedFetch(1, 401))
        assertEquals(CloudJobRules.StopFate.handOver, CloudJobRules.afterStop(CloudJobRules.stopAtExpiry(true)))
        assertEquals(CloudJobRules.StopFate.delete, CloudJobRules.afterStop(CloudJobRules.stopAtExpiry(false)))
        assertTrue(CloudJobRules.handedOverMessage("Your 40 questions").startsWith("Your 40 questions finished in the cloud"))
    }

    @Test fun aPendingJobIsKeptUntilCollected() = runBlocking {
        val jobs = FakeJobs(listOf("{\"questions\":[]}"))
        val server = FakeServer { jobs.answer(it) }
        val store = CloudJobs.MemoryStore()
        val at = CloudEndpoint(server.client("bearer"), null, null)
        val spec = CloudJobs.Spec("Writing 40 questions", "loop", "questions", 40, listOf("src"), listOf(CloudJobs.Step("s {{SOURCE}}", "u", 0, 100, 0.5)))
        val outputs = CloudJobs.run(spec, at, store, pause = {})
        assertEquals(listOf("{\"questions\":[]}"), outputs)
        assertTrue(store.all().isEmpty())
        assertEquals("Your 40 questions", CloudJobs.Pending("id", "Writing 40 questions", 0, null).what)
        val pending = CloudJobs.Pending("id", "Writing 4 cases", 5, "launch", 1, 4, "owner")
        assertEquals(pending, CloudJobs.Pending.of(JSONObject(pending.json().toString())))
        // a step's prompt counts its source in place of {{SOURCE}}
        assertEquals("s {{SOURCE}}".length + "u".length + "src".length, spec.promptChars(0))
    }

    @Test fun textHelpersReadWhatModelsWrite() {
        assertEquals("answer", LLMText.stripThinking("<think>working</think> answer "))
        assertEquals("", LLMText.stripThinking("<think>cut off"))
        assertEquals(2, LLMText.keyIndex("C", listOf("a", "b", "c")))
        assertEquals(1, LLMText.keyIndex("1", listOf("a", "b")))
        assertEquals(0, LLMText.keyIndex("A drug", listOf("a drug", "b")))
        assertNull(LLMText.keyIndex(5, listOf("a", "b")))
        assertEquals(2, LLMText.completeItems("{\"questions\":[{\"a\":1},{\"b\":\"}\"},{\"c\":", "questions").size)
        assertEquals("Too many requests today.", LLMError.Http(429, "Too many requests today.").message)
        assertTrue(LLMError.Http(500, "{}").message!!.startsWith("The hosted model refused the request (HTTP 500)."))
    }
}
