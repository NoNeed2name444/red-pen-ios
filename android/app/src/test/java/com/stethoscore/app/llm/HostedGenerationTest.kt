package com.stethoscore.app.llm

import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.accuracy.AccuracyKind
import com.stethoscore.app.data.CaseJson
import com.stethoscore.app.data.CaseMaker
import com.stethoscore.app.data.CaseSamples
import com.stethoscore.app.data.CaseWriting
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.quiz.DifferentialTiers
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** A2: making questions, the Cases maker and debrief, and the accuracy checker call the client, against a fake worker. */
class HostedGenerationTest {

    private val noPause: suspend (Long) -> Unit = {}

    private fun question(stem: String, key: Int = 2, options: List<String> = listOf("Atenolol tablets", "Amlodipine tablets", "Ramipril tablets", "Indapamide tablets", "Doxazosin tablets")) =
        JSONObject().put("stem", stem).put("options", JSONArray(options)).put("correctIndex", key).put("explanation", "Key point: ACE inhibitors first.")

    private fun reply(vararg questions: JSONObject) = JSONObject().put("questions", JSONArray(questions.toList())).toString()

    private fun owner(server: FakeServer, spend: OwnerSpend = OwnerSpend(OwnerSpend.MemoryStore())) =
        LLMService(FakeServer.standInKey(), { null }, FakeServer.BASE, server, spend)

    // making questions

    @Test fun questionsAreWrittenAsOneCloudJob() = runBlocking {
        val jobs = FakeJobs(listOf(
            reply(question("A 54-year-old diabetic with hypertension needs a first drug; which is best?"),
                question("Which electrolyte rises with ramipril in renal impairment?", 0, listOf("Potassium level", "Sodium level", "Calcium level", "Chloride level", "Magnesium level"))),
            reply(question("A 54-year-old diabetic with hypertension needs a first drug; which is best?")),
        ))
        val server = FakeServer { jobs.answer(it) }
        val llm = owner(server)
        val progress = mutableListOf<Pair<Int, Int>>()
        val questions = MedicalGenerate.mcq("Hypertension lecture. ".repeat(50), 5, "", false, llm.backend()!!, pause = noPause) { d, t -> progress += d to t }
        // the repeat in the second reply is dropped, as iOS's collector does
        assertEquals(2, questions.size)
        assertEquals(2, questions[0].correctIndex)
        val spec = jobs.spec!!
        assertEquals("Writing 5 questions", spec.getString("title"))
        assertEquals("loop", spec.getString("mode"))
        assertEquals("questions", spec.getString("extract"))
        assertEquals(5, spec.getInt("count"))
        val step = spec.getJSONArray("steps").getJSONObject(0)
        assertEquals("Write the 4 questions now, as JSON only.", step.getString("user"))
        assertEquals(3800, step.getInt("maxTokens"))
        assertEquals(0.7, step.getDouble("temperature"), 0.0)
        assertTrue(step.getString("system").contains("{{SOURCE}}"))
        assertTrue(step.getString("system").contains("{{ALREADY}}"))
        assertFalse(spec.has("perReply"))
        // every request went to the worker with the owner key, and the job was cleared off it
        assertTrue(server.requests.all { it.url.startsWith(FakeServer.BASE) && it.bearer == FakeServer.standInKey() })
        assertEquals(1, jobs.deleted)
        assertEquals(0 to 5, progress.first())
        // two replies with no usage, each counted at its step's worst case
        val chars = step.getString("system").length + step.getString("user").length + spec.getJSONArray("sources").getString(0).length
        assertEquals(2 * OwnerSpend.estimateMicros(chars, 3800), llm.spend.spentMicros)
    }

    @Test fun aJobPastTheCapIsNeverSent() = runBlocking {
        val server = FakeServer()
        val llm = owner(server, OwnerSpend(OwnerSpend.MemoryStore(19_999_000)))
        val backend = llm.backend()!!
        llm.spend.record(null, 0, 1_000)
        try {
            MedicalGenerate.mcq("Lecture", 5, "", false, backend, pause = noPause)
            fail("written past the cap")
        } catch (e: LLMError.NotReady) {
            assertEquals(OwnerSpend.CAP_REACHED, e.message)
        }
        assertTrue(server.requests.isEmpty())
    }

    @Test fun aFailedJobSaysWhy() = runBlocking {
        val id = "0f8fad5b-d9cb-469f-a165-70867728950e"
        val server = FakeServer { r ->
            when {
                r.method == "POST" -> FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id)))
                r.method == "GET" -> FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id).put("status", "failed").put("done", 4).put("total", 8).put("error", "The writer is busy.")))
                else -> FakeServer.ok(JSONObject())
            }
        }
        val llm = owner(server)
        try {
            MedicalGenerate.mcq("Lecture", 8, "", false, llm.backend()!!, pause = noPause)
            fail("no error")
        } catch (e: LLMError.NotReady) {
            assertEquals("The writer is busy.", e.message)
        }
        assertTrue(server.requests.any { it.method == "DELETE" })
        // four questions written: one reply of four, counted
        assertTrue(llm.spend.spentMicros > 0)
    }

    @Test fun aDirectBackendIsAskedCallByCall() = runBlocking {
        val asked = mutableListOf<List<ChatTurn>>()
        val backend = object : LLMBackend {
            override val label = "Fake"
            override val isOnDevice = false
            override val promptBudgetChars = 40_000
            override suspend fun complete(turns: List<ChatTurn>, maxTokens: Int, temperature: Double): String {
                asked += turns
                val topic = listOf("gout", "asthma", "anaemia", "sepsis")[asked.size - 1]
                return reply(question("Which finding best defines $topic in adults?", key = 1,
                    options = listOf("$topic first finding", "$topic second finding", "$topic third finding", "$topic fourth finding")))
            }
        }
        val questions = MedicalGenerate.mcq("Source text", 3, "Cardiology", true, backend)
        assertEquals(3, questions.size)
        assertEquals(3, asked.size)
        assertEquals("Write the 3 questions now, as JSON only.", asked[0][1].text)
        assertTrue(asked[0][0].text.contains("Topic to focus on: \"Cardiology\""))
        assertTrue(asked[1][0].text.contains("ALREADY ASKED in this set - 1 question(s) so far."))
    }

    @Test fun repliesAreReadOneQuestionAtATime() {
        val raw = "Here you are: {\"questions\":[" +
            question("Good one?", 2).put("correctIndex", "C").put("differential", JSONObject()
                .put("mostLikely", JSONArray().put(JSONObject().put("name", "Essential hypertension").put("for", JSONArray().put("raised BP")).put("test", "ABPM")))).toString() +
            ",{\"stem\":\"No options\"}," +
            question("Longest answer gives it away?", 0, listOf("A very long and detailed answer option that stands out", "Short", "Brief", "Tiny", "Small")).toString() +
            ",{\"stem\":\"Cut off"
        val questions = MedicalGenerate.parseQuestions(raw)
        assertEquals(1, questions.size)
        assertEquals(2, questions[0].correctIndex)
        val tiers = DifferentialTiers.fromQuestionJson(questions[0].rawJson)!!
        assertEquals("Essential hypertension", tiers.mostLikely.single().name)
        assertEquals(listOf("raised BP"), tiers.mostLikely.single().supporting)
    }

    @Test fun thePromptIsTheIOSOne() {
        val prompt = MCQPrompt.buildPrompt("notes", 4, "", false, requestJSONShape = true)
        assertTrue(prompt.startsWith(com.stethoscore.app.quiz.ExamTrack.general.mcqStyle))
        assertTrue(prompt.contains("Write exactly 4 multiple-choice questions. Follow these rules strictly:"))
        assertTrue(prompt.contains("At least one in five questions in the set should be this recall-only style."))
        assertTrue(prompt.contains("\"options\" must have exactly 5 strings."))
        assertTrue(MCQCoverage.isRepeat("What is the first-line treatment for gout?", "Allopurinol", listOf(MCQCoverage.Asked("What is the first-line drug treatment for gout?", "allopurinol"))))
        assertFalse(MCQCoverage.isRepeat("What is the first-line treatment for gout?", "Allopurinol", listOf(MCQCoverage.Asked("What is the first-line treatment for hypertension?", "Ramipril"))))
    }

    // Cases

    private fun caseReply(): String = JSONObject().put("cases", JSONArray().put(CaseJson.write(CaseSamples.breathless))).toString()

    @Test fun casesAreWrittenAsOneCloudJob() = runBlocking {
        val jobs = FakeJobs(listOf(caseReply(), caseReply()))
        val server = FakeServer { jobs.answer(it) }
        val llm = owner(server)
        val writer = CaseMaker.writer(llm.backend())!!
        val made = CaseMaker.write(2, "Lecture text", "Lecture", "Respiratory", using = writer, pause = noPause)
        assertTrue(made.cases.isNotEmpty())
        val spec = jobs.spec!!
        assertEquals("Writing 2 cases", spec.getString("title"))
        assertEquals("each", spec.getString("mode"))
        assertEquals("pages", spec.getString("extract"))
        val steps = spec.getJSONArray("steps")
        assertEquals(2, steps.length())
        assertEquals(CaseWriting.requestJSON, steps.getJSONObject(0).getString("user"))
        assertEquals(3500, steps.getJSONObject(0).getInt("maxTokens"))
        assertEquals(1, jobs.deleted)
    }

    @Test fun theDebriefWritesAnotherPatientIntoTheSet() = runBlocking {
        val jobs = FakeJobs(listOf(caseReply()))
        val server = FakeServer { jobs.answer(it) }
        val llm = owner(server)
        val file = CaseSamples.breathless
        val set = com.stethoscore.app.data.StudySet(name = "Cases", subject = "Respiratory", kind = com.stethoscore.app.data.StudySetKind.CASES, caseFiles = listOf(file))
        val brief = com.stethoscore.app.ui.cases.CaseAnother.brief(file, sameDiagnosis = true)
        assertEquals(file.diagnosis.name, brief.diagnosis)
        val written = com.stethoscore.app.ui.cases.CaseAnother.write(file, set, true, CaseMaker.writer(llm.backend())!!)
        assertEquals(1, written.size)
        assertEquals("Writing 1 case", jobs.spec!!.getString("title"))
        assertTrue(jobs.spec!!.getJSONArray("steps").getJSONObject(0).getString("system").contains(file.diagnosis.name))
    }

    @Test fun withNoWriterTheDebriefSaysSo() {
        assertNull(CaseMaker.writer(null))
        assertEquals("Stethoscore Cloud is part of Pro.", CaseMaker.noWriter("Stethoscore Cloud is part of Pro."))
        assertEquals("Sign in to use Stethoscore Cloud.", CaseMaker.noWriter("Sign in to use Stethoscore Cloud."))
        // there is no writer to choose and nothing on the phone: iOS's words, the cloud cannot be reached
        assertEquals("Stethoscore Cloud can't be reached right now.", CaseMaker.noWriter())
        assertFalse(CaseMaker.noWriter().contains("AI models"))
        assertFalse(CaseMaker.noWriter().contains("On-device"))
    }

    // the accuracy checker

    private val item = AccuracyItem("q1", AccuracyKind.mcq, stem = "Which drug?", options = listOf("A drug", "B drug", "C drug", "D drug"), key = 0, explanation = "Because.")

    @Test fun theCheckerSendsTheItemAndReadsTheVotes() = runBlocking {
        val server = FakeServer { FakeServer.ok(JSONObject().put("items", JSONArray().put(JSONObject().put("id", "q1").put("votes", JSONArray().put(JSONObject().put("verdict", "correct")))))) }
        val llm = owner(server)
        val (said, reply) = AccuracyCheck.checkNow(item, llm)
        assertNull(said)
        assertTrue(AccuracyCheck.isChecked(reply, "q1"))
        val sent = server.requests.single()
        assertEquals("${FakeServer.BASE}/accuracy/check", sent.url)
        assertEquals("foreground", sent.body!!.getString("priority"))
        assertEquals("mcq", sent.body!!.getJSONArray("items").getJSONObject(0).getString("kind"))
        // counted at the voter's max_tokens: 500 an item + 600
        assertEquals(OwnerSpend.estimateMicros(item.checkedText.length, 1_100), llm.spend.spentMicros)
    }

    @Test fun theCheckerSaysWhatCameOfIt() = runBlocking {
        fun said(reply: BackendClient.Reply): String? = runBlocking { AccuracyCheck.checkNow(item, owner(FakeServer { reply })).first }
        assertEquals("Today's free checks are used. Try again after midnight UTC.", said(BackendClient.Reply(429, "{\"error\":\"limit\"}")))
        assertEquals("Sign in again to check accuracy.", said(BackendClient.Reply(401, "{}")))
        assertEquals("The checkers are busy. Try again in a few minutes.", said(FakeServer.ok(JSONObject().put("busy", true))))
        assertEquals("The checkers are busy. Try again in a minute.", said(FakeServer.ok(JSONObject().put("items", JSONArray()))))
        assertEquals("Couldn't reach the server. Check your connection.", said(BackendClient.Reply(500, "{}")))
        val offline = owner(FakeServer { throw java.io.IOException("down") })
        assertEquals("Couldn't reach the server. Check your connection.", AccuracyCheck.checkNow(item, offline).first)
        assertEquals(AccuracySendOutcome.NotPro("The accuracy check is part of Pro."), AccuracySendOutcome.of(402, null, null))
        assertFalse(AccuracySendOutcome.NotPro("x").records)
    }
}
