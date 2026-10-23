package com.stethoscore.app.llm

import com.stethoscore.app.data.MCQQuestion
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
 * Not ported (T0115b): osce() and its stations, MCQRepair (letter references
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
        store: CloudJobs.PendingStore = CloudJobs.MemoryStore(),
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
            return collectQuestions(CloudJobs.run(spec, cloud, store, pause, onProgress), count)
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
