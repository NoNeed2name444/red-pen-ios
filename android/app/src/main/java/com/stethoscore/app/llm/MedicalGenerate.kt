package com.stethoscore.app.llm

import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.OsceChecklist
import com.stethoscore.app.data.OsceGenerator
import com.stethoscore.app.data.OsceStations
import com.stethoscore.app.data.TextSlicing
import com.stethoscore.app.exam.TargetExam
import com.stethoscore.app.quiz.ExamTrack
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import org.json.JSONArray
import org.json.JSONObject
import kotlin.coroutines.coroutineContext

/**
 * MCQ generation through the writer route. Port of the MCQ half
 * of iOS Shared/LLM/MedicalGenerate.swift: the same prompt, batching and bar
 * for keeping a question. With Stethoscore Cloud the server writes the whole
 * set as one job (CloudJobs); any other backend is asked call by call.
 *
 * The OSCE half too: osce(), its job, its collector and its parser.
 *
 * Not ported (T0115b): MCQRepair (letter references
 * in an explanation rewritten), ExamExemplars.copies (the bundled exemplar
 * bank is not on Android) and CloudChecks.cite (the evidence the server's
 * check read, cited on each question).
 */
object MedicalGenerate {

    /** The exam a set is written for: the track and the chosen exams (iOS ExamTrack.current, ExamChoice.current). */
    data class Exam(val track: ExamTrack = ExamTrack.general, val target: TargetExam? = null, val secondary: TargetExam? = null)

    suspend fun mcq(
        sourceText: String, count: Int, subject: String, highYield: Boolean,
        using: LLMBackend, exam: Exam = Exam(),
        store: CloudJobs.PendingStore = CloudJobs.store,
        pause: suspend (Long) -> Unit = { kotlinx.coroutines.delay(it) },
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): List<MCQQuestion> {
        val windows = TextSlicing.windows(sourceText, using.promptBudgetChars).take(60)
        val promptSource = windows.firstOrNull() ?: ""
        val cloud = CloudJobs.endpoint(using)
        if (cloud != null) {
            val perCall = minOf(4, MCQPrompt.maxQuestionsPerCall)
            val instructions = MCQPrompt.buildPrompt(
                "{{SOURCE}}", perCall, subject, highYield, requestJSONShape = true,
                alreadyAsked = listOf(MCQCoverage.Asked("{{ALREADY}}", "")),
                exam = exam.track, target = exam.target, secondary = exam.secondary,
                exemplars = 2, exemplarPlaceholder = true, topicText = promptSource.take(4000))
            val spec = CloudJobs.Spec(
                title = "Writing $count questions", mode = "loop", extract = "questions", count = count,
                sources = windows,
                steps = windows.indices.map {
                    CloudJobs.Step(instructions, "Write the $perCall questions now, as JSON only.", it, 950 * perCall, 0.7)
                },
                perReply = perCall,
            )
            // the recipe goes with the job, so a run the app is closed on is
            // collected as these questions (CloudJobCollector), as iOS's screens set it
            val outer = coroutineContext[CloudJobs.Context]
            val recipe = outer?.recipe ?: CloudRecipe(com.stethoscore.app.data.StudySetKind.MCQ, "", subject, count, exam = exam.target?.id).json()
            val replies = kotlinx.coroutines.withContext(CloudJobs.Context(recipe, outer?.delivery)) {
                CloudJobs.run(spec, cloud, store, pause, onProgress)
            }
            return collectQuestions(replies, count)
        }
        val perCall = if (using.isOnDevice) 3 else MCQPrompt.maxQuestionsPerCall
        val collected = mutableListOf<MCQQuestion>()
        val asked = mutableListOf<MCQCoverage.Asked>()
        var consecutiveFailures = 0
        while (collected.size < count && consecutiveFailures < 3) {
            coroutineContext.ensureActive()
            val callCount = minOf(perCall, count - collected.size)
            onProgress(collected.size, count)
            val batch = asked.size / maxOf(1, perCall)
            // exemplars: the bundled bank is not on Android (see above)
            val instructions = MCQPrompt.buildPrompt(
                TextSlicing.window(windows, batch), callCount, subject, highYield, requestJSONShape = true,
                alreadyAsked = asked, exam = exam.track, target = exam.target, secondary = exam.secondary, exemplars = 0)
            try {
                val reply = using.complete(
                    listOf(ChatTurn.system(instructions), ChatTurn.user("Write the $callCount questions now, as JSON only.")),
                    950 * callCount, 0.7)
                var kept = 0
                for (question in parseQuestions(reply)) {
                    val key = question.options[question.correctIndex]
                    if (MCQCoverage.isRepeat(question.stem, key, asked)) continue
                    collected += question
                    asked += MCQCoverage.Asked(question.stem, key)
                    kept += 1
                    if (collected.size >= count) break
                }
                consecutiveFailures = if (kept == 0) consecutiveFailures + 1 else 0
            } catch (e: CancellationException) {
                throw e
            } catch (e: LLMError) {
                // a missing key or a refused request will not fix itself on retry
                if (e is LLMError.EmptyReply) consecutiveFailures += 1 else throw e
            } catch (e: Exception) {
                consecutiveFailures += 1
            }
        }
        if (collected.isEmpty()) throw LLMError.EmptyReply()
        return collected.take(count)
    }

    /**
     * Up to [count] stations, never more than OsceGenerator.maxStationsTotal
     * (iOS MedicalGenerate.osce). With Stethoscore Cloud, one job; otherwise
     * two a call, each call reading the next window of the lecture and told
     * the titles already written, until three calls in a row keep none, telling
     * [onProgress] how many are kept so far, of how many, before each call.
     * Throws OsceGenerator.NothingUsable when no station is kept.
     */
    suspend fun osce(
        sourceText: String, count: Int, subject: String, using: LLMBackend,
        exam: ExamTrack = ExamTrack.general,
        pause: suspend (Long) -> Unit = { kotlinx.coroutines.delay(it) },
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): List<OsceChecklist> {
        val wanted = minOf(count, OsceGenerator.maxStationsTotal)
        // a station prompt is long: 12,000 characters of source a call on a
        // hosted model, and the whole lecture in turn
        val budget = if (using.isOnDevice) OsceGenerator.maxPromptChars else minOf(using.promptBudgetChars, 12_000)
        val windows = TextSlicing.windows(sourceText, budget).take(60)
        val cloud = CloudJobs.endpoint(using)
        if (cloud != null) {
            val perCall = OsceGenerator.maxStationsPerCall
            val instructions = OsceGenerator.prompt("{{SOURCE}}", perCall, subject, listOf("{{ALREADY}}"), exam)
            val spec = CloudJobs.Spec(
                title = "Writing $wanted stations", mode = "loop", extract = "stations", count = wanted,
                sources = windows,
                steps = windows.indices.map {
                    CloudJobs.Step(instructions, stationsRequest(perCall), it, 900 * perCall, 0.6)
                },
                perReply = perCall,
            )
            return collectStations(CloudJobs.run(spec, cloud, pause = pause, onProgress = onProgress), wanted)
        }
        val collected = mutableListOf<OsceChecklist>()
        val titles = mutableListOf<String>()
        var consecutiveFailures = 0
        while (collected.size < wanted && consecutiveFailures < 3) {
            coroutineContext.ensureActive()
            val callCount = minOf(OsceGenerator.maxStationsPerCall, wanted - collected.size)
            onProgress(collected.size, wanted)
            val instructions = OsceGenerator.prompt(
                TextSlicing.window(windows, titles.size / OsceGenerator.maxStationsPerCall), callCount, subject, titles, exam)
            try {
                val reply = using.complete(listOf(ChatTurn.system(instructions), ChatTurn.user(stationsRequest(callCount))),
                    900 * callCount, 0.6)
                var kept = 0
                for (station in OsceStations.tidy(parseStations(reply))) {
                    if (titles.any { it.equals(station.title, ignoreCase = true) }) continue
                    collected += station
                    titles += station.title
                    kept += 1
                    if (collected.size >= wanted) break
                }
                consecutiveFailures = if (kept == 0) consecutiveFailures + 1 else 0
            } catch (e: CancellationException) {
                throw e
            } catch (e: LLMError) {
                // a missing key or a refused request will not fix itself on retry
                if (e is LLMError.EmptyReply) consecutiveFailures += 1 else throw e
            } catch (e: Exception) {
                consecutiveFailures += 1
            }
        }
        if (collected.isEmpty()) throw OsceGenerator.NothingUsable()
        return collected.take(wanted)
    }

    /** The user turn that asks for [count] stations. */
    fun stationsRequest(count: Int): String = "Write the $count station${if (count == 1) "" else "s"} now, as JSON only."

    /** The stations in a job's replies, tidied, repeats dropped (iOS collectStations). */
    fun collectStations(replies: List<String>, count: Int): List<OsceChecklist> {
        val collected = mutableListOf<OsceChecklist>()
        for (station in OsceStations.tidy(replies.flatMap { parseStations(it) })) {
            if (collected.size >= count) break
            if (collected.any { it.title.equals(station.title, ignoreCase = true) }) continue
            collected += station
        }
        if (collected.isEmpty()) throw OsceGenerator.NothingUsable()
        return collected
    }

    /**
     * Every station in a reply, each read on its own (LLMText.jsonItems): a
     * malformed one costs only itself. Whether it is worth drilling is for
     * OsceStations.tidy to say.
     */
    fun parseStations(raw: String): List<OsceChecklist> = LLMText.jsonItems(raw, "stations").mapNotNull { item ->
        val title = item.opt("title") as? String ?: return@mapNotNull null
        val array = item.optJSONArray("steps") ?: return@mapNotNull null
        val steps = LLMText.strings(array)
        // a step that is not words costs the station, as iOS's [String] reads it
        if (steps.size != array.length()) return@mapNotNull null
        OsceChecklist(title = title, steps = steps)
    }

    /** The questions in a job's replies, repeats dropped as the loop above does. */
    fun collectQuestions(replies: List<String>, count: Int): List<MCQQuestion> {
        val collected = mutableListOf<MCQQuestion>()
        val asked = mutableListOf<MCQCoverage.Asked>()
        for (question in replies.flatMap { parseQuestions(it) }) {
            if (collected.size >= count) break
            val key = question.options[question.correctIndex]
            if (MCQCoverage.isRepeat(question.stem, key, asked)) continue
            collected += question
            asked += MCQCoverage.Asked(question.stem, key)
        }
        if (collected.isEmpty()) throw LLMError.EmptyReply()
        return collected
    }

    /** Every usable question in a reply, each read on its own: a malformed one costs only itself. */
    fun parseQuestions(raw: String): List<MCQQuestion> {
        val out = mutableListOf<MCQQuestion>()
        for (item in LLMText.jsonItems(raw, "questions")) {
            val stem = item.opt("stem") as? String ?: continue
            val array = item.optJSONArray("options") ?: continue
            val options = LLMText.strings(array)
            if (options.size != array.length()) continue
            val key = LLMText.keyIndex(item.opt("correctIndex"), options) ?: continue
            if (!MCQPrompt.isValidQuestion(stem, options, key)) continue
            val explanation = item.opt("explanation") as? String ?: ""
            val raw = JSONObject()
            differential(item.opt("differential"))?.let { raw.put("differential", it) }
            out += MCQQuestion(stem = stem, options = options, correctIndex = key, explanation = explanation, rawJson = raw.toString())
        }
        return out
    }

    /**
     * A question's differential in the shape the app keeps it (iOS
     * DifferentialTiers: "supporting" for what the model calls "for"), read
     * tolerantly so a malformed one costs only itself. Null when it has none.
     */
    fun differential(value: Any?): JSONObject? {
        val o = value as? JSONObject ?: return null
        val out = JSONObject()
        var any = false
        for (tier in listOf("mostLikely", "expanded", "cantMiss")) {
            val list = o.optJSONArray(tier) ?: continue
            val kept = JSONArray()
            for (i in 0 until list.length()) {
                val e = list.optJSONObject(i) ?: continue
                val name = (e.opt("name") as? String)?.trim().orEmpty()
                if (name.isEmpty()) continue
                kept.put(JSONObject().put("name", name)
                    .put("supporting", JSONArray(LLMText.strings(e.optJSONArray("for") ?: e.optJSONArray("supporting"))))
                    .put("against", JSONArray(LLMText.strings(e.optJSONArray("against"))))
                    .put("test", e.opt("test") as? String ?: ""))
            }
            if (kept.length() > 0) { out.put(tier, kept); any = true }
        }
        return if (any) out else null
    }
}
