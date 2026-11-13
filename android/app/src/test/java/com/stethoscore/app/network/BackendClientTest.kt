package com.stethoscore.app.network

import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.accuracy.AccuracyKind
import com.stethoscore.app.accuracy.AccuracyModel
import com.stethoscore.app.accuracy.AccuracyWeights
import com.stethoscore.app.llm.AccuracyCheck
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException

// The accuracy engine's two calls to the Worker: POST /accuracy/model (the
// weights, public) and POST /accuracy/report ("Report an error", signed in or
// the owner key), against a fake transport that puts nothing on the network.
// The request and response shapes are the Worker's: server/worker.js:212-216
// (routes), server/accuracy.js:947-965 (report), :968-970 (modelWeights),
// :86-102 (cleanItem, which reads the item), :282-292 (currentWeights),
// server/accuracy-model.js:313-319 (validWeights). The calls are made only
// where a model call is allowed (LLMService.checker: Pro, a bearer, and the
// owner key's $20 cap), and neither costs anything, so neither counts as spend.
class BackendClientTest {

    private val base = FakeServer.BASE

    /** What the transport saw of one request, including the timeout, which FakeServer does not keep. */
    private class Seen(val method: String, val url: String, val body: String?, val bearer: String?, val timeoutMillis: Int)

    private class Recorder(var answer: (Seen) -> BackendClient.Reply) : BackendClient.Transport {
        val seen = mutableListOf<Seen>()
        override fun send(method: String, url: String, body: ByteArray?, bearer: String?, timeoutMillis: Int): BackendClient.Reply {
            val request = Seen(method, url, body?.toString(Charsets.UTF_8), bearer, timeoutMillis)
            seen += request
            return answer(request)
        }
    }

    private fun reply(status: Int, json: String) = BackendClient.Reply(status, json)

    private val item = AccuracyItem("q1", AccuracyKind.mcq, stem = "Which drug reduces mortality first?",
        options = listOf("Aspirin", "Morphine", "Oxygen", "Nitrates", "Furosemide"), key = 0, explanation = "Aspirin reduces mortality.")

    private fun failure(block: () -> Unit): BackendClient.BackendException {
        try {
            block()
        } catch (e: BackendClient.BackendException) {
            return e
        }
        fail("expected a BackendException")
        throw AssertionError()
    }

    // MARK: POST /accuracy/model (worker.js:216, accuracy.js:968-970)

    @Test fun theModelCallIsAnEmptyPostWithNoBearerEvenWhenSignedIn() {
        val recorder = Recorder { reply(200, """{"weights":${AccuracyModel.bundled.toJson()}}""") }
        BackendClient(base, { "a-session" }, recorder).accuracyModel()
        val request = recorder.seen.single()
        assertEquals("POST", request.method)
        assertEquals("$base/accuracy/model", request.url)
        assertEquals("{}", request.body)
        assertNull("the weights are public: no token is sent", request.bearer)
        assertEquals(20_000, request.timeoutMillis)
    }

    @Test fun theModelCallNeedsNoSessionAtAll() {
        val recorder = Recorder { reply(200, """{"weights":${AccuracyModel.bundled.toJson()}}""") }
        BackendClient(base, { null }, recorder).accuracyModel()
        assertEquals(1, recorder.seen.size)
    }

    @Test fun theWeightsInTheReplyAreTheModelsOwnAndSurviveTheWire() {
        val server = FakeServer { FakeServer.ok(JSONObject().put("weights", AccuracyModel.bundled.toJson())) }
        val weights = AccuracyWeights.fromReply(server.client(null).accuracyModel())
        assertEquals(AccuracyModel.bundled, weights)
    }

    @Test fun weightsTheModelCannotUseAreNotKept() {
        fun fromWire(mutate: (JSONObject) -> Unit): AccuracyWeights? {
            val w = JSONObject(AccuracyModel.bundled.toJson().toString()).also(mutate)
            return AccuracyWeights.fromReply(JSONObject().put("weights", w))
        }
        assertNotNull("the unchanged weights are fine", fromWire { })
        assertNull("a feature this app does not know", fromWire { it.getJSONArray("features").put(0, "invented_feature") })
        assertNull("a weight missing", fromWire { it.getJSONArray("weights").remove(0) })
        assertNull("cut-offs crossed", fromWire { it.put("thresholds", JSONObject().put("verified", 0.3).put("flagged", 0.5)) })
        assertNull("a cut-off above one", fromWire { it.put("thresholds", JSONObject().put("verified", 1.5).put("flagged", 0.4)) })
        assertNull("no thresholds", fromWire { it.remove("thresholds") })
        assertNull("no version", fromWire { it.remove("version") })
        assertNull("no weights object", AccuracyWeights.fromReply(JSONObject()))
        assertNull("nothing", AccuracyWeights.fromReply(null))
    }

    @Test fun anErrorStatusFromTheModelCallIsAnExceptionWithTheServersWords() {
        val server = FakeServer { reply(500, """{"error":{"message":"Down for a bit."},"message":"Down for a bit."}""") }
        val e = failure { server.client(null).accuracyModel() }
        assertEquals(500, e.status)
        assertEquals(BackendClient.Failure.SERVER, e.failure)
        assertEquals("Down for a bit.", e.message)
    }

    @Test fun anOlderWorkerWithoutTheRouteIsNotConfigured() {
        val server = FakeServer { reply(404, """{"error":"No such endpoint.","message":"No such endpoint."}""") }
        val e = failure { server.client(null).accuracyModel() }
        assertEquals(404, e.status)
        assertEquals(BackendClient.Failure.NOT_CONFIGURED, e.failure)
    }

    @Test fun aModelCallThatTimesOutIsOfflineWithTheCauseKept() {
        val recorder = Recorder { throw SocketTimeoutException("Read timed out") }
        val e = failure { BackendClient(base, { null }, recorder).accuracyModel() }
        assertEquals(0, e.status)
        assertEquals(BackendClient.Failure.OFFLINE, e.failure)
        assertTrue(e.cause is SocketTimeoutException)
        assertEquals(20_000, recorder.seen.single().timeoutMillis)
    }

    @Test fun aModelReplyThatIsNotJsonIsAnUnreadableResponse() {
        val server = FakeServer { reply(200, "<html>captive portal</html>") }
        val e = failure { server.client(null).accuracyModel() }
        assertEquals(BackendClient.Failure.SERVER, e.failure)
        assertEquals("The server sent an unreadable response.", e.message)
    }

    // MARK: POST /accuracy/report (worker.js:212-214, accuracy.js:947-965)

    @Test fun theReportIsThePostedItemAndNoteWithTheBearerAndAMinute() {
        val recorder = Recorder { reply(200, """{"ok":true,"hash":"abc","reports":1}""") }
        val answer = BackendClient(base, { "a-session" }, recorder).accuracyReport(AccuracyCheck.json(item), "The key is wrong.")
        val request = recorder.seen.single()
        assertEquals("POST", request.method)
        assertEquals("$base/accuracy/report", request.url)
        assertEquals("a-session", request.bearer)
        assertEquals(60_000, request.timeoutMillis)
        val body = JSONObject(request.body!!)
        assertEquals(setOf("item", "note"), body.keys().asSequence().toSet())
        assertEquals("The key is wrong.", body.getString("note"))
        assertEquals(AccuracyCheck.json(item).toString(), body.getJSONObject("item").toString())
        assertTrue(answer.getBoolean("ok"))
        assertEquals("abc", answer.getString("hash"))
        assertEquals(1, answer.getInt("reports"))
    }

    // cleanItem (accuracy.js:86-102): the Worker reads a known kind, and for a question 2 to 10 options and a stem
    @Test fun theItemCarriesWhatTheWorkersCleanItemReads() {
        val sent = AccuracyCheck.json(item)
        val kinds = Regex("""export const KINDS = \[([^\]]*)\]""").find(serverFile("server/accuracy-model.js"))!!.groupValues[1]
            .split(",").map { it.trim().trim('\'') }
        assertTrue(sent.getString("kind") in kinds)
        assertEquals(kinds, AccuracyKind.values().map { it.rawValue })
        assertTrue(sent.getJSONArray("options").length() in 2..10)
        assertTrue(sent.getString("stem").isNotBlank())
        assertEquals(0, sent.getInt("key"))
        val text = AccuracyCheck.json(AccuracyItem("c1", AccuracyKind.card, text = "Aspirin inhibits COX-1."))
        assertEquals("Aspirin inhibits COX-1.", text.getString("text"))
    }

    @Test fun aReportWithoutASessionSendsNothingAndSaysSignedOut() {
        val recorder = Recorder { reply(200, "{}") }
        val e = failure { BackendClient(base, { null }, recorder).accuracyReport(AccuracyCheck.json(item), "x") }
        assertEquals(0, e.status)
        assertEquals(BackendClient.Failure.SIGNED_OUT, e.failure)
        assertTrue(recorder.seen.isEmpty())
        val blank = failure { BackendClient(base, { "  " }, recorder).accuracyReport(AccuracyCheck.json(item), "x") }
        assertEquals(BackendClient.Failure.SIGNED_OUT, blank.failure)
        assertTrue(recorder.seen.isEmpty())
    }

    @Test fun aReportOfAnItemWithNoKindIsRefusedBeforeItIsSent() {
        val recorder = Recorder { reply(200, "{}") }
        try {
            BackendClient(base, { "a-session" }, recorder).accuracyReport(JSONObject().put("stem", "x"), "x")
            fail("sent an item with no kind")
        } catch (e: IllegalArgumentException) {
            assertEquals("Report an item with its kind.", e.message)
        }
        assertTrue(recorder.seen.isEmpty())
    }

    @Test fun todaysReportsUsedIsRateLimitedWithTheDayLimitKept() {
        val server = FakeServer {
            reply(429, """{"error":{"message":"That's today's reports sent. Thank you - try again tomorrow."},"message":"That's today's reports sent. Thank you - try again tomorrow.","limit":"day"}""")
        }
        val e = failure { server.client("a-session").accuracyReport(AccuracyCheck.json(item), "x") }
        assertEquals(429, e.status)
        assertEquals(BackendClient.Failure.RATE_LIMITED, e.failure)
        assertEquals("That's today's reports sent. Thank you - try again tomorrow.", e.message)
        assertEquals("day", e.response?.optString("limit"))
    }

    @Test fun anItemTheWorkerCouldNotReadIsAPlainErrorWithItsWords() {
        val server = FakeServer { reply(400, """{"error":{"message":"That item could not be read."},"message":"That item could not be read."}""") }
        val e = failure { server.client("a-session").accuracyReport(AccuracyCheck.json(item), "x") }
        assertEquals(400, e.status)
        assertEquals("That item could not be read.", e.message)
    }

    @Test fun aReportRefusedForASessionThatHasEndedIsSignedOut() {
        val server = FakeServer { reply(401, """{"error":"Please sign in again.","message":"Please sign in again."}""") }
        val e = failure { server.client("an-old-session").accuracyReport(AccuracyCheck.json(item), "x") }
        assertEquals(401, e.status)
        assertEquals(BackendClient.Failure.SIGNED_OUT, e.failure)
    }

    @Test fun aServerErrorOnReportIsAServerFailure() {
        val server = FakeServer { reply(503, "") }
        val e = failure { server.client("a-session").accuracyReport(AccuracyCheck.json(item), "x") }
        assertEquals(503, e.status)
        assertEquals(BackendClient.Failure.SERVER, e.failure)
        assertEquals("Something went wrong talking to the server.", e.message)
    }

    @Test fun aReportThatTimesOutIsOfflineAfterAMinuteWithTheCauseKept() {
        val recorder = Recorder { throw SocketTimeoutException("timeout") }
        val e = failure { BackendClient(base, { "a-session" }, recorder).accuracyReport(AccuracyCheck.json(item), "x") }
        assertEquals(0, e.status)
        assertEquals(BackendClient.Failure.OFFLINE, e.failure)
        assertTrue(e.cause is SocketTimeoutException)
        assertEquals(60_000, recorder.seen.single().timeoutMillis)
    }

    @Test fun aReportThatCannotConnectIsOffline() {
        val recorder = Recorder { throw IOException("Unable to resolve host") }
        val e = failure { BackendClient(base, { "a-session" }, recorder).accuracyReport(AccuracyCheck.json(item), "x") }
        assertEquals(BackendClient.Failure.OFFLINE, e.failure)
    }

    // MARK: only where a model call is allowed (LLMService.checker)

    private fun service(ownerKey: String, server: BackendClient.Transport, session: String? = null, spend: OwnerSpend = OwnerSpend(OwnerSpend.MemoryStore())) =
        LLMService(ownerKey, { session }, base, server, spend)

    private val weightsReply = """{"weights":${AccuracyModel.bundled.toJson()}}"""

    @Test fun withoutProNeitherCallIsMadeAndTheReasonIsGiven() = runBlocking {
        val server = FakeServer { FakeServer.ok(JSONObject(weightsReply)) }
        val llm = service("", server)
        assertFalse(llm.isPro)
        val fetched = AccuracyCheck.fetchWeights(llm)
        assertEquals(AccuracyCheck.WeightsFetch.Blocked("Stethoscore Cloud is part of Pro."), fetched)
        val reported = AccuracyCheck.report(item, "x", llm)
        assertEquals(AccuracyCheck.ReportOutcome.Blocked("Stethoscore Cloud is part of Pro."), reported)
        assertTrue(server.requests.isEmpty())
    }

    @Test fun aSessionAloneDoesNotOpenTheCloudInADefaultBuild() = runBlocking {
        val server = FakeServer { FakeServer.ok(JSONObject(weightsReply)) }
        val llm = service("", server, session = "a-session")
        assertTrue(AccuracyCheck.fetchWeights(llm) is AccuracyCheck.WeightsFetch.Blocked)
        assertTrue(AccuracyCheck.report(item, "x", llm) is AccuracyCheck.ReportOutcome.Blocked)
        assertTrue(server.requests.isEmpty())
    }

    @Test fun withProTheWeightsAreFetchedWithNoBearerAndKeptAsTheModelsOwn() = runBlocking {
        val server = FakeServer { FakeServer.ok(JSONObject(weightsReply)) }
        val llm = service(FakeServer.standInKey(), server)
        val fetched = AccuracyCheck.fetchWeights(llm)
        assertEquals(AccuracyCheck.WeightsFetch.Fresh(AccuracyModel.bundled), fetched)
        val request = server.requests.single()
        assertEquals("/accuracy/model", request.path)
        assertEquals("POST", request.method)
        assertNull("the owner key never goes with a public call", request.bearer)
        assertEquals("{}", request.body.toString())
    }

    @Test fun withProAReportGoesWithTheOwnerKeyAndIsNotSpend() = runBlocking {
        val key = FakeServer.standInKey()
        val server = FakeServer { reply(200, """{"ok":true,"hash":"h","reports":1}""") }
        val spend = OwnerSpend(OwnerSpend.MemoryStore(1_000))
        val llm = service(key, server, spend = spend)
        assertEquals(AccuracyCheck.ReportOutcome.Sent, AccuracyCheck.report(item, "The key is wrong.", llm))
        val request = server.requests.single()
        assertEquals("/accuracy/report", request.path)
        assertEquals(key, request.bearer)
        assertEquals("The key is wrong.", request.body?.getString("note"))
        assertEquals("q1", request.body?.getJSONObject("item")?.getString("id"))
        assertEquals("a report costs nothing", 1_000L, spend.spentMicros)
    }

    @Test fun aSessionIsTheBearerBeforeTheOwnerKey() = runBlocking {
        val server = FakeServer { reply(200, """{"ok":true,"hash":"h","reports":1}""") }
        val llm = service(FakeServer.standInKey(), server, session = "a-session")
        AccuracyCheck.report(item, "x", llm)
        assertEquals("a-session", server.requests.single().bearer)
    }

    @Test fun atTheOwnerKeysCapNeitherCallIsMade() = runBlocking {
        val server = FakeServer { FakeServer.ok(JSONObject(weightsReply)) }
        val llm = service(FakeServer.standInKey(), server, spend = OwnerSpend(OwnerSpend.MemoryStore(20_000_000)))
        assertEquals(AccuracyCheck.WeightsFetch.Blocked(OwnerSpend.CAP_REACHED), AccuracyCheck.fetchWeights(llm))
        assertEquals(AccuracyCheck.ReportOutcome.Blocked(OwnerSpend.CAP_REACHED), AccuracyCheck.report(item, "x", llm))
        assertTrue(server.requests.isEmpty())
    }

    @Test fun weightsTheModelCannotUseLeaveTheOldOnesInPlace() = runBlocking {
        val bad = JSONObject(AccuracyModel.bundled.toJson().toString()).put("thresholds", JSONObject().put("verified", 0.3).put("flagged", 0.5))
        val server = FakeServer { FakeServer.ok(JSONObject().put("weights", bad)) }
        assertEquals(AccuracyCheck.WeightsFetch.Unusable, AccuracyCheck.fetchWeights(service(FakeServer.standInKey(), server)))
        val empty = FakeServer { FakeServer.ok(JSONObject()) }
        assertEquals(AccuracyCheck.WeightsFetch.Unusable, AccuracyCheck.fetchWeights(service(FakeServer.standInKey(), empty)))
    }

    @Test fun aServerErrorOrAnOlderWorkerLeavesTheOldWeights() = runBlocking {
        val down = FakeServer { reply(500, "{}") }
        assertEquals(AccuracyCheck.WeightsFetch.Unusable, AccuracyCheck.fetchWeights(service(FakeServer.standInKey(), down)))
        val older = FakeServer { reply(404, """{"error":"No such endpoint."}""") }
        assertEquals(AccuracyCheck.WeightsFetch.Unusable, AccuracyCheck.fetchWeights(service(FakeServer.standInKey(), older)))
    }

    @Test fun noConnectionIsOfflineForBothCalls() = runBlocking {
        val recorder = Recorder { throw SocketTimeoutException("timeout") }
        val llm = service(FakeServer.standInKey(), recorder)
        assertEquals(AccuracyCheck.WeightsFetch.Offline, AccuracyCheck.fetchWeights(llm))
        assertEquals(AccuracyCheck.ReportOutcome.Offline, AccuracyCheck.report(item, "x", llm))
        assertEquals(2, recorder.seen.size)
    }

    @Test fun aReportTheServerRefusedSaysWhichStatus() = runBlocking {
        val limit = FakeServer { reply(429, """{"message":"Reports are paused for the rest of today.","limit":"day"}""") }
        assertEquals(AccuracyCheck.ReportOutcome.Refused(429), AccuracyCheck.report(item, "x", service(FakeServer.standInKey(), limit)))
        val unread = FakeServer { reply(400, """{"message":"That item could not be read."}""") }
        assertEquals(AccuracyCheck.ReportOutcome.Refused(400), AccuracyCheck.report(item, "x", service(FakeServer.standInKey(), unread)))
        val down = FakeServer { reply(500, "") }
        assertEquals(AccuracyCheck.ReportOutcome.Refused(500), AccuracyCheck.report(item, "x", service(FakeServer.standInKey(), down)))
    }

    private fun serverFile(relative: String): String {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, relative).exists()) dir = dir.parentFile
        assertNotNull("$relative is found from the test's working directory", dir)
        return File(dir, relative).readText(Charsets.UTF_8)
    }

    // the edges of the cut-offs' range, as they arrive on the wire: one and nought are kept, equal cut-offs are not
    @Test fun cutOffsAtTheEdgesOfTheirRangeAreKeptOffTheWireAndEqualOnesAreNot() {
        fun fromWire(verified: Double, flagged: Double): AccuracyWeights? {
            val w = JSONObject(AccuracyModel.bundled.toJson().toString()).put("thresholds", JSONObject().put("verified", verified).put("flagged", flagged))
            return AccuracyWeights.fromReply(JSONObject().put("weights", w))
        }
        assertNotNull("a Verified cut-off of one", fromWire(1.0, 0.4))
        assertNotNull("a Flagged cut-off of nought", fromWire(0.5, 0.0))
        assertNull("equal cut-offs", fromWire(0.5, 0.5))
    }
}
