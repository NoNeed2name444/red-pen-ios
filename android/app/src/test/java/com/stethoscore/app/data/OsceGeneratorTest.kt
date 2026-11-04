package com.stethoscore.app.data

import com.stethoscore.app.llm.ChatTurn
import com.stethoscore.app.llm.LLMBackend
import com.stethoscore.app.llm.LLMError
import com.stethoscore.app.quiz.ExamTrack
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The station writer (OsceGenerator.writer, the OSCE half of iOS
 * Shared/LLM/MedicalGenerate.swift) against a stand-in backend: no network,
 * no model. A reply read into stations, an unusable one giving none, a set
 * asked for two at a time and capped, the count said before each call, the
 * exam's kind of station in the prompt, and the lecture read a window at a
 * time. Each part collects its failures and reports them all, as OsceTest
 * does.
 */
class OsceGeneratorTest {
    private class Checks {
        val failures = mutableListOf<String>()
        fun ok(condition: Boolean, what: String) { if (!condition) failures += what }
        fun done() = assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    private fun checks(body: suspend Checks.() -> Unit) {
        runBlocking {
            val c = Checks()
            c.body()
            c.done()
        }
    }

    /** The stand-in writer: answers each call with how many stations it asked for, and keeps what it was sent. */
    private class StandIn(override val isOnDevice: Boolean = false, val answer: (Int) -> String) : LLMBackend {
        override val label = "Stand-in"
        override val promptBudgetChars = 40_000
        val asked = mutableListOf<List<ChatTurn>>()
        /** How many stations each call asked for. */
        val wanted = mutableListOf<Int>()
        val tokens = mutableListOf<Int>()

        override suspend fun complete(turns: List<ChatTurn>, maxTokens: Int, temperature: Double): String {
            asked += turns
            tokens += maxTokens
            val count = Regex("""Write the (\d+) station""").find(turns.last().text)?.groupValues?.get(1)?.toIntOrNull() ?: 0
            wanted += count
            return answer(count)
        }

        /** The instructions each call was sent. */
        val prompts: List<String> get() = asked.map { it.first().text }

        /** The part of the lecture each call was given. */
        val sources: List<String> get() = prompts.map { it.substringAfter("\nSOURCE:\n").substringBefore("\n\nAnswer with JSON only") }
    }

    private val steps = listOf("Introduce yourself and confirm the patient's name", "Explain the examination and gain consent",
        "Wash your hands", "Expose the knee with the patient lying flat", "Inspect from the end of the bed",
        "Thank the patient and say what you would do to finish")

    private fun station(title: String, steps: List<String> = this.steps): JSONObject =
        JSONObject().put("title", title).put("steps", JSONArray(steps))

    private fun reply(stations: List<JSONObject>): String = JSONObject().put("stations", JSONArray(stations)).toString()

    /** A stand-in that writes what each call asks for, and [extra] more, every title new. */
    private fun obliging(onDevice: Boolean = false, extra: Int = 0): StandIn {
        var written = 0
        return StandIn(onDevice) { count -> reply(List(count + extra) { station("Station ${++written}") }) }
    }

    private val styles: List<String> = ExamTrack.entries.mapNotNull { it.osceStyle }

    @Test fun aWriterOnlyWithABackend() = checks {
        ok(OsceGenerator.writer(null) == null, "with no backend there is no writer, and the form says why")
        ok(OsceGenerator.writer(obliging()) != null, "with one, there is")
    }

    @Test fun aReplyIsReadIntoStations() = checks {
        val raw = "Here are your stations:\n```json\n" + reply(listOf(
            station("1. Knee examination", listOf("1. Introduce yourself", "Gain consent", "Wash your hands", "Wash your hands", "Inspect the knee")),
            JSONObject().put("steps", JSONArray(steps)),                                    // no title
            JSONObject().put("title", "Hip examination").put("steps",                        // a step that is not words
                JSONArray().put("Introduce yourself").put(7).put("Wash your hands").put("Inspect the hip").put("Assess the gait")),
            station("Inhaler counselling", listOf("Introduce yourself", "Check what they know")),   // two steps is not a station
            station("KNEE EXAMINATION"),                                                    // the same station again
            station("Inhaler technique counselling"),
        )) + "\n```"
        val backend = StandIn { raw }
        val written = OsceGenerator.writer(backend)!!.stations("A skills lecture on the knee.", 2, "Orthopaedics")
        ok(backend.asked.size == 1, "two stations asked for, one call")
        ok(backend.prompts.single().contains("Orthopaedics") && backend.prompts.single().contains("A skills lecture on the knee."),
            "the call names the subject and carries the source")
        ok(backend.prompts.single().endsWith("{\"stations\":[{\"title\":\"...\",\"steps\":[\"...\"]}]}"), "and asks for the JSON it is read from")
        ok(written.map { it.title } == listOf("Knee examination", "Inhaler technique counselling"),
            "the usable stations, in the order written: numbering off, no title, a step that is not words, too few steps and a repeat dropped")
        ok(written.firstOrNull()?.steps == listOf("Introduce yourself", "Gain consent", "Wash your hands", "Inspect the knee"),
            "each station's steps tidied")
        ok(written.getOrNull(1)?.steps == steps, "a clean station kept as written")
    }

    @Test fun anUnusableReplyGivesNone() = checks {
        val prose = StandIn { "There is no clinical procedure in this source, so no stations can be written." }
        ok(OsceGenerator.writer(prose)!!.stations("Facts about the knee.", 10, "").isEmpty(), "a reply with no stations in it gives none")
        ok(prose.asked.size == 3, "and the writer stops after three tries in a row that keep nothing")
        val stubs = StandIn { reply(listOf(station("", steps), station("Knee examination", listOf("Look", "Feel")))) }
        ok(OsceGenerator.writer(stubs)!!.stations("Facts about the knee.", 2, "").isEmpty(),
            "nor does one whose stations have no title or too few steps")
        val silent = StandIn { throw LLMError.EmptyReply() }
        ok(OsceGenerator.writer(silent)!!.stations("Facts about the knee.", 2, "").isEmpty() && silent.asked.size == 3,
            "an empty reply is tried again, three times in all")
    }

    @Test fun aRefusalIsPassedOnNotRetried() = checks {
        val refusing = StandIn { throw LLMError.Http(402, "Stethoscore Cloud is part of Pro.") }
        try {
            OsceGenerator.writer(refusing)!!.stations("A skills lecture.", 4, "")
            ok(false, "a refused request is said, not swallowed")
        } catch (e: LLMError.Http) {
            ok(e.message == "Stethoscore Cloud is part of Pro.", "in the server's own words")
        }
        ok(refusing.asked.size == 1, "and not asked again: it will not fix itself on retry")
    }

    @Test fun aSetIsAskedForAFewAtATime() = checks {
        val per = OsceGenerator.maxStationsPerCall
        val backend = obliging()
        val written = OsceGenerator.writer(backend)!!.stations("A skills lecture.", 5, "")
        ok(written.size == 5, "five stations asked for, five written")
        ok(backend.asked.size == (5 + per - 1) / per, "in ceil(5 / $per) calls")
        ok(backend.wanted == List((5 + per - 1) / per) { minOf(per, 5 - it * per) }, "each asking for $per at most, the last for what is left")
        ok(backend.tokens == backend.wanted.map { 900 * it }, "with room to write them")
        ok(backend.prompts[1].contains("write different ones:\n- Station 1\n"), "each call told the titles already written, so it writes new ones")
        ok(written.map { it.title } == (1..5).map { "Station $it" }, "kept in the order written")
        val eager = obliging(extra = 1)
        ok(OsceGenerator.writer(eager)!!.stations("A skills lecture.", 3, "").size == 3, "a writer that writes more than it is asked for is cut to the count")
    }

    @Test fun neverMoreThanASetHolds() = checks {
        val per = OsceGenerator.maxStationsPerCall
        val most = OsceGenerator.maxStationsTotal
        val backend = obliging()
        val written = OsceGenerator.writer(backend)!!.stations("A skills lecture.", most + 25, "")
        ok(written.size == most, "asked for more than a set holds, a full set is written and no more")
        ok(backend.asked.size == (most + per - 1) / per, "in ceil($most / $per) calls")
        ok(backend.wanted.all { it in 1..per }, "never more than $per a call")
    }

    @Test fun theCountIsSaidBeforeEachCall() = checks {
        // the second call writes the first two stations again, so it keeps none
        var written = 0
        var calls = 0
        val backend = StandIn { count ->
            calls += 1
            if (calls == 2) reply(listOf(station("Station 1"), station("Station 2")))
            else reply(List(count) { station("Station ${++written}") })
        }
        val said = mutableListOf<Pair<Int, Int>>()
        val callsBefore = mutableListOf<Int>()
        val stations = OsceGenerator.writer(backend)!!.stations("A skills lecture.", 5, "") { done, total ->
            said += done to total
            callsBefore += backend.asked.size
        }
        ok(stations.size == 5 && backend.asked.size == 4, "five stations written in four calls, one of which kept none")
        ok(said == listOf(0 to 5, 2 to 5, 2 to 5, 4 to 5),
            "each call starts by saying how many are written so far, of how many, a call that kept none saying it again: $said")
        ok(callsBefore == listOf(0, 1, 2, 3), "said before each call, not after it: $callsBefore")
    }

    @Test fun theExamShapesTheStations() = checks {
        for (track in ExamTrack.entries) {
            val backend = obliging()
            OsceGenerator.writer(backend, track)!!.stations("A skills lecture.", 1, "")
            val prompt = backend.prompts.single()
            val style = track.osceStyle
            if (style == null) ok(styles.none { prompt.contains(it) }, "general revision is asked for no exam's format")
            else ok(prompt.contains(style), "a ${track.title} student is asked for ${track.title} stations")
        }
        val plain = obliging()
        OsceGenerator.writer(plain)!!.stations("A skills lecture.", 1, "")
        ok(styles.none { plain.prompts.single().contains(it) }, "with no exam given, general revision")
    }

    @Test fun theLectureIsReadAWindowAtATime() = checks {
        val lecture = (1..600).joinToString(" ") { "Sentence $it of a skills lecture on examining the knee." }
        for (onDevice in listOf(true, false)) {
            val budget = if (onDevice) OsceGenerator.maxPromptChars else 12_000
            val where = if (onDevice) "on a phone" else "hosted"
            val backend = obliging(onDevice)
            OsceGenerator.writer(backend)!!.stations(lecture, 4, "")
            val sources = backend.sources
            ok(sources.size == 2 && sources.all { it.isNotEmpty() && it.length <= budget },
                "$where, each call is given no more of the lecture than $budget characters")
            ok(sources.size == 2 && sources[0] != sources[1] && sources.all { lecture.contains(it) },
                "$where, the next call reads the next part of it")
        }
    }
}
