package com.stethoscore.app.audio

import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.ui.narrate.LectureImporter
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.Base64

// The Android cloud transcriber against a fake worker (T0146 A6): the same
// cut points, prompt and request as iOS's CloudTranscriber.swift and
// CloudTranscript.swift, the owner key as the bearer, and an empty key taking
// the "not set up" path without a request.
class CloudTranscriberTest {
    @get:Rule val tmp = TemporaryFolder()

    private val key = "o".repeat(40)
    private val worker = "https://worker.example"

    private class Sent(val method: String, val url: String, val body: JSONObject, val bearer: String?)

    private class FakeWorker(private val replies: MutableList<BackendClient.Reply>) : BackendClient.Transport {
        val sent = ArrayList<Sent>()
        override fun send(method: String, url: String, body: ByteArray?, bearer: String?, timeoutMillis: Int): BackendClient.Reply {
            sent += Sent(method, url, JSONObject(String(body!!, Charsets.UTF_8)), bearer)
            return replies.removeAt(0)
        }
    }

    /** A recording of a given length; each piece is its start and length as bytes. */
    private class FakeCutter(val seconds: Double) : CloudTranscriber.ChunkCutter {
        val cuts = ArrayList<Pair<Double, Double>>()
        override fun duration(file: File) = seconds
        override fun cut(file: File, start: Double, length: Double, out: File) {
            cuts += start to length
            out.writeText("piece $start $length")
        }
    }

    private fun ok(phrases: String, model: String = "gemini") =
        BackendClient.Reply(200, JSONObject().put("text", phrases).put("model", model).toString())

    private fun recording(): File = File(tmp.newFolder(), "lecture-20261023-1405.m4a").also { it.writeText("aac") }

    @Test fun theChunksAndRequestMatchIOS() = runBlocking {
        assertEquals("one chunk for a short lecture", listOf(0.0), CloudTranscript.chunkStarts(300.0))
        assertEquals("every ten minutes", listOf(0.0, 600.0, 1200.0), CloudTranscript.chunkStarts(1500.0))
        assertEquals("a last sliver under 20 s folds into the chunk before", listOf(0.0, 600.0), CloudTranscript.chunkStarts(1210.0))
        assertEquals("nothing for no audio", emptyList<Double>(), CloudTranscript.chunkStarts(0.0))

        val phrases = JSONArray().put(JSONObject().put("start", 1.0).put("end", 3.0).put("text", "the nephron filters"))
            .put(JSONObject().put("start", 3.5).put("end", 6.0).put("text", "الكلية بتصفي الدم")).toString()
        val fake = FakeWorker(mutableListOf(ok(phrases), ok(phrases), ok(phrases)))
        val cutter = FakeCutter(1500.0)
        val lines = CloudTranscriber(worker, key, fake, cutter, pause = {}).transcribe(recording(), LectureLanguage.mixed, listOf("glomerulus"))

        assertEquals("three pieces at iOS's marks", listOf(0.0 to 600.0, 600.0 to 600.0, 1200.0 to 300.0), cutter.cuts)
        assertEquals("one request per piece", 3, fake.sent.size)
        val prompt = CloudTranscript.prompt(listOf("glomerulus"), LectureLanguage.mixed)
        fake.sent.forEachIndexed { i, s ->
            assertEquals("POST", s.method)
            assertEquals("to the worker's transcribe route", "$worker/transcribe/chunk", s.url)
            assertEquals("the owner key as the bearer", key, s.bearer)
            assertEquals("the piece's audio, base64", Base64.getEncoder().encodeToString(("piece " + cutter.cuts[i].first + " " + cutter.cuts[i].second).toByteArray()), s.body.getString("audio"))
            assertEquals("the prompt iOS sends", prompt, s.body.getString("prompt"))
            assertEquals("and nothing else in the body", setOf("audio", "prompt"), s.body.keys().asSequence().toSet())
        }
        assertEquals("two lines a piece", 6, lines.size)
        assertEquals("on the recording's own clock", 601.0, lines[2].start, 1e-9)
        assertEquals("the model that answered", "gemini", lines[0].model)
        assertEquals("Arabic lines read as Arabic", "ar", CloudTranscript.language(lines[1].text))
    }

    @Test fun thePromptIsIOSsWordForWord() {
        val swift = File("../../ios/RedPen/Shared/CloudTranscript.swift").let { if (it.exists()) it else File("../ios/RedPen/Shared/CloudTranscript.swift") }
        assertTrue("the iOS source is there to compare with", swift.exists())
        val source = swift.readText().replace("\\\"", "\"")
        for (language in LectureLanguage.values()) {
            val lines = CloudTranscript.prompt(emptyList(), language).split("\n").filter { it.isNotBlank() }
            for (line in lines) assertTrue("iOS says: $line", source.contains(line))
        }
        assertTrue("the slide terms are added as iOS adds them",
            CloudTranscript.prompt(listOf("Bowman", "podocyte")).endsWith("\n\nTerms from this lecture's slides, spelled as they should be written: Bowman, podocyte."))
    }

    @Test fun anEmptyKeyIsNotSetUp() = runBlocking {
        for (empty in listOf("", "short-key")) {
            val fake = FakeWorker(mutableListOf())
            val cloud = CloudTranscriber(worker, empty, fake, FakeCutter(60.0), pause = {})
            assertTrue("no key: not set up", !cloud.isSetUp)
            try {
                cloud.transcribe(recording(), LectureLanguage.mixed)
                fail("an empty key must not transcribe")
            } catch (e: LectureImporterUnavailable) {
                assertEquals("today's not-set-up words", LectureTranscriber.Failure.cloudNotSetUp, e.message)
            }
            assertEquals("and nothing is sent", 0, fake.sent.size)
            // the importer a public build gets keeps today's message
            val importer = LectureImporter.forApp(cloud)
            importer.transcribe(recording(), LectureImporter.Engine.cloud, LectureLanguage.mixed) {}
            assertTrue("the importer says so", importer.trouble!!.contains(LectureTranscriber.Failure.cloudNotSetUp))
        }
    }

    @Test fun theWorkersAnswers() = runBlocking {
        val busy = FakeWorker(mutableListOf(BackendClient.Reply(429, JSONObject().put("message", "That's today's cloud transcription used.").toString())))
        try {
            CloudTranscriber(worker, key, busy, FakeCutter(60.0), pause = {}).transcribe(recording(), LectureLanguage.english)
            fail("a 429 stops")
        } catch (e: CloudTranscriber.Failure) {
            assertEquals("the server's own words are passed on", "That's today's cloud transcription used.", e.message)
        }
        assertEquals("with no second try", 1, busy.sent.size)

        val paused = ArrayList<Long>()
        val phrases = JSONArray().put(JSONObject().put("start", 0.0).put("end", 2.0).put("text", "hello")).toString()
        val hiccup = FakeWorker(mutableListOf(BackendClient.Reply(502, "{}"), ok(phrases)))
        val lines = CloudTranscriber(worker, key, hiccup, FakeCutter(60.0), pause = { paused += it }).transcribe(recording(), LectureLanguage.english)
        assertTrue("a 5xx is tried once more, after 3 s", hiccup.sent.size == 2 && paused == listOf(3000L) && lines.single().text == "hello")

        val fenced = FakeWorker(mutableListOf(ok("```json\n$phrases\n```")))
        assertEquals("a fenced answer still counts", "hello", CloudTranscriber(worker, key, fenced, FakeCutter(60.0), pause = {}).transcribe(recording(), LectureLanguage.english).single().text)

        val cutOff = "[{\"start\":0,\"end\":1,\"text\":\"kept\"},{\"start\":1,\"end\":2,\"text\":\"lo"
        val twice = FakeWorker(mutableListOf(ok(cutOff), ok(cutOff)))
        assertEquals("a reply cut off twice keeps what came whole", "kept",
            CloudTranscriber(worker, key, twice, FakeCutter(60.0), pause = {}).transcribe(recording(), LectureLanguage.english).single().text)

        val loop = JSONArray().apply { repeat(8) { put(JSONObject().put("start", it.toDouble()).put("end", it + 1.0).put("text", "again and again")) } }.toString()
        val (kept, removed) = CloudTranscript.cutLoops(CloudTranscript.phrases(loop)!!)
        assertTrue("a phrase said eight times in a row is cut back to one", kept.size == 1 && removed == 21)
        assertEquals("a run inside a phrase is cut back to one, as iOS", "no", CloudTranscript.cutRepeats("no no no no no no no no"))
        assertEquals("three times in a row is still speech, as iOS", "no no no", CloudTranscript.cutRepeats("no no no"))
        assertEquals("two repeats are the lecturer's own", "malar rash malar rash", CloudTranscript.cutRepeats("malar rash malar rash"))
    }
}
