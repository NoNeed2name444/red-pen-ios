package com.stethoscore.app.llm

import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.accuracy.AccuracyRules
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.quiz.DifferentialTiers
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * T0234: a reply is parsed, then repaired (iOS MedicalGenerate.parseQuestions
 * -> MCQRepair.repaired), and a cloud job's recipe carries the set's name and
 * the lecture it was read from (iOS MCQGenerateForm startGenerating).
 */
class MedicalGenerateTest {
    private val id = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private var ioBefore: CoroutineDispatcher = Dispatchers.IO

    @Before fun inPlace() {
        ioBefore = CloudJobs.io
        CloudJobs.io = Dispatchers.Unconfined
    }

    @After fun restore() { CloudJobs.io = ioBefore }

    private val drugs = listOf("Atenolol tablets", "Amlodipine tablets", "Ramipril tablets", "Indapamide tablets", "Doxazosin tablets")

    private fun question(stem: String, explanation: String?, key: Int = 2, options: List<String> = drugs): JSONObject {
        val o = JSONObject().put("stem", stem).put("options", JSONArray(options)).put("correctIndex", key)
        if (explanation != null) o.put("explanation", explanation)
        return o
    }

    private fun reply(vararg questions: JSONObject) = JSONObject().put("questions", JSONArray(questions.toList())).toString()

    private val stem = "A 54-year-old diabetic with hypertension needs a first drug; which is best?"

    // A2: parseQuestions repairs before it returns

    @Test fun aPositionInTheExplanationIsNamedByTheOptionsWords() {
        val questions = MedicalGenerate.parseQuestions(reply(question(stem,
            "Option C is the correct answer: ramipril is first line. Option A and the last option are not.")))
        assertEquals(1, questions.size)
        assertEquals("\"Ramipril tablets\" is the correct answer: ramipril is first line. \"Atenolol tablets\" and \"Doxazosin tablets\" are not.",
            questions[0].explanation)
        // the key, the options and the stem are as written
        assertEquals(2, questions[0].correctIndex)
        assertEquals(drugs, questions[0].options)
        assertEquals(stem, questions[0].stem)
    }

    @Test fun aMissingExplanationStaysEmptyAndTheQuestionIsKept() {
        val questions = MedicalGenerate.parseQuestions(reply(
            question(stem, null),
            question("Which electrolyte rises with ramipril in renal impairment?", null, key = 0,
                options = listOf("Potassium level", "Sodium level", "Calcium level", "Chloride level", "Magnesium level"))
                .put("explanation", JSONObject.NULL)))
        assertEquals(2, questions.size)
        assertEquals(listOf("", ""), questions.map { it.explanation })
    }

    @Test fun anExplanationNamingAnotherAnswerIsKeptAsWrittenAndStillFlagged() {
        val written = "Option C is correct because ramipril is first line."
        // keyed on B, but the explanation says C
        val questions = MedicalGenerate.parseQuestions(reply(question(stem, written, key = 1)))
        assertEquals(1, questions.size)
        assertEquals(written, questions[0].explanation)
        assertEquals(1, questions[0].correctIndex)
        val hits = AccuracyRules.hits(AccuracyItem.mcq(questions[0]))
        assertTrue(hits.map { it.rule }.toString(), hits.any { it.rule == "key-explanation-conflict" })
    }

    @Test fun anExplanationWithNoPositionIsUntouched() {
        val written = "Key point: ACE inhibitors first. It was the drug of choice a decade ago."
        assertEquals(written, MedicalGenerate.parseQuestions(reply(question(stem, written))).single().explanation)
    }

    @Test fun theDifferentialIsKeptWithTheRepairedQuestion() {
        val item = question(stem, "Option C is right.").put("differential", JSONObject()
            .put("mostLikely", JSONArray().put(JSONObject().put("name", "Essential hypertension").put("for", JSONArray().put("raised BP")).put("test", "ABPM"))))
        val q = MedicalGenerate.parseQuestions(reply(item)).single()
        assertEquals("\"Ramipril tablets\" is right.", q.explanation)
        val tiers = DifferentialTiers.fromQuestionJson(q.rawJson)!!
        assertEquals("Essential hypertension", tiers.mostLikely.single().name)
    }

    @Test fun aQuestionThatFailsTheBarIsStillDroppedNotRepaired() {
        // the longest answer gives it away: dropped before any repair, as on iOS
        val questions = MedicalGenerate.parseQuestions(reply(
            question("Longest answer gives it away?", "Option A is right.", key = 0,
                options = listOf("A very long and detailed answer option that stands out", "Short", "Brief", "Tiny", "Small")),
            question(stem, "Option C is right.")))
        assertEquals(listOf("\"Ramipril tablets\" is right."), questions.map { it.explanation })
    }

    @Test fun aCloudJobsRepliesAreRepairedToo() {
        val replies = listOf(reply(question(stem, "Option C is right and option B is not.")))
        val questions = MedicalGenerate.collectQuestions(replies, 5)
        assertEquals("\"Ramipril tablets\" is right and \"Amlodipine tablets\" is not.", questions.single().explanation)
    }

    @Test fun aDirectBackendsQuestionsAreRepairedBeforeTheyAreKept() = runBlocking {
        val backend = object : LLMBackend {
            override val label = "Fake"
            override val isOnDevice = false
            override val promptBudgetChars = 40_000
            override suspend fun complete(turns: List<ChatTurn>, maxTokens: Int, temperature: Double): String =
                reply(question(stem, "The second option is wrong; the answer is option C."))
        }
        val questions = MedicalGenerate.mcq("Source text", 1, "Cardiology", false, backend)
        assertEquals(1, questions.size)
        assertEquals("\"Amlodipine tablets\" is wrong; the answer is \"Ramipril tablets\".", questions[0].explanation)
    }

    // A3: the recipe a cloud job carries

    private val lecture = SourceDoc(id = "doc-1", name = "Hypertension lecture", kind = "pdf",
        pages = listOf(SourcePage(1, "Hypertension lecture."), SourcePage(2, "ACE inhibitors first.")))

    private val replies = listOf(reply(
        question("First line for a 50-year-old?", "Key point: ACE inhibitors first."),
        question("Which drug for diabetic kidney disease?", "Key point: ACE inhibitors first.")))

    private fun worker(running: () -> Boolean) = FakeServer { request ->
        when {
            request.method == "POST" && request.path == "/jobs" ->
                FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id).put("status", "queued")))
            // the connection is lost while it writes: the run hands the job over
            running() -> BackendClient.Reply(500, "{}")
            request.method == "GET" && request.path == "/jobs/$id" ->
                FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id).put("status", "done").put("done", 2).put("total", 2).put("error", JSONObject.NULL)))
            request.method == "GET" && request.path == "/jobs/$id?outputs=1" ->
                FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id)).put("outputs", JSONArray(replies)))
            request.method == "DELETE" -> FakeServer.ok(JSONObject().put("ok", true))
            else -> BackendClient.Reply(404, "{}")
        }
    }

    private class Shelf : CloudJobCollector.Library {
        val sets = mutableListOf<StudySet>()
        override fun add(set: StudySet): Boolean { sets += set; return true }
    }

    @Test fun aRunTheAppWasClosedOnKeepsTheSetsNameAndLecture() = runBlocking {
        var running = true
        val server = worker { running }
        val llm = LLMService(FakeServer.standInKey(), { null }, FakeServer.BASE, server)
        val store = CloudJobs.MemoryStore()
        val lost = runCatching {
            MedicalGenerate.mcq("Hypertension lecture.", 2, "Cardiology", false, llm.backend()!!, store = store, pause = {},
                name = "Blood pressure", source = lecture)
        }
        assertTrue(lost.exceptionOrNull() is LLMError.NotReady)
        val recipe = CloudRecipe.of(store.all().single().recipe)
        assertNotNull(recipe)
        recipe!!
        assertEquals(StudySetKind.MCQ, recipe.kind)
        assertEquals("Blood pressure", recipe.name)
        assertEquals("Cardiology", recipe.subject)
        assertEquals(2, recipe.count)
        assertEquals("doc-1", recipe.source?.id)
        assertEquals("Hypertension lecture", recipe.source?.name)
        assertEquals(listOf("Hypertension lecture.", "ACE inhibitors first."), recipe.source?.pages?.map { it.text })
        // collected the next time the app opens: the set has the name and the lecture
        running = false
        val shelf = Shelf()
        CloudJobCollector.collect(store, shelf, llm::cloudBearer, server::client)
        val set = shelf.sets.single()
        assertEquals("Blood pressure", set.name)
        assertEquals(2, set.questions.size)
        assertEquals(listOf("Hypertension lecture"), set.sources.map { it.name })
    }

    @Test fun withNoNameOrSourceTheRecipeIsAsItWas() = runBlocking {
        val server = worker { true }
        val llm = LLMService(FakeServer.standInKey(), { null }, FakeServer.BASE, server)
        val store = CloudJobs.MemoryStore()
        runCatching { MedicalGenerate.mcq("Hypertension lecture.", 2, "Cardiology", false, llm.backend()!!, store = store, pause = {}) }
        val recipe = CloudRecipe.of(store.all().single().recipe)!!
        assertEquals("", recipe.name)
        assertNull(recipe.source)
        assertEquals("Cardiology", recipe.subject)
    }
}
