package com.stethoscore.app.ui.coverage

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.stethoscore.app.coverage.AreaCoverage
import com.stethoscore.app.coverage.CoverageCheck
import com.stethoscore.app.coverage.CoverageCloudCheck
import com.stethoscore.app.coverage.CoverageVerdict
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.llm.CloudJobs
import com.stethoscore.app.llm.HostedProvider
import com.stethoscore.app.llm.LLMError
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.quiz.ExamTrack
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.io.File

// A port of ios/RedPen/Features/Coverage/CoverageChecker.swift: runs the AI
// check for the Syllabus screen and keeps its result - one request per area,
// a few at a time, the finished check saved per exam. The engine behind it is
// coverage/CoverageCloudCheck.kt.
//
// Where it may ask a model is whatever LLMService already allows: Pro (on
// Android, the owner's personal build), a bearer, and the $20 cap on the owner
// key (OwnerSpend), which each request counts against. No key is held here and
// nothing is sent without that. Any other build shows the same unavailable
// words iOS shows before sign-in and without Pro.
//
// Not ported: the personal build's example check (CoverageExamples.swift), so a
// check on show is always a real one kept or just run.

/** Runs the AI check and keeps its result (iOS CoverageChecker). */
class CoverageChecker(
    private val llm: LLMService,
    /** Where kept checks live, one file per exam. */
    private val folder: File,
    /** The screen's scope: leaving the screen cancels a run in it. */
    private val scope: CoroutineScope,
) {
    /** The check on show: the kept one for this exam, or the one just run. */
    var check: CoverageCheck? by mutableStateOf(null)
        private set
    var running: Boolean by mutableStateOf(false)
        private set
    var done: Int by mutableStateOf(0)
        private set
    var total: Int by mutableStateOf(0)
        private set

    /** Why the last run failed, in the student's terms. */
    var failure: String? by mutableStateOf(null)
        private set

    /** Why the cloud cannot be asked right now, or null when it can; read again after a run, which may have reached the cap. */
    var blocker: String? by mutableStateOf(blockerFor(llm))
        private set

    private var job: Job? = null

    /** Shows what is kept for an exam. */
    fun load(track: ExamTrack, exam: String? = null) {
        if (running) return
        failure = null
        check = CoverageCloudCheck.load(folder, track, exam)
        blocker = blockerFor(llm)
    }

    fun cancel() {
        job?.cancel()
        job = null
        running = false
        blocker = blockerFor(llm)
    }

    /** Checks every area and keeps the result. */
    fun run(track: ExamTrack, areas: List<AreaCoverage>, library: List<StudySet>, exam: String? = null) {
        if (running || blockerFor(llm) != null) return
        val token = llm.cloudToken ?: return
        val client = llm.client(token)
        val meter = if (llm.usesOwnerKey) llm.spend else null
        val prompts = areas.map { CoverageCloudCheck.prompt(it, track, library) }
        running = true
        failure = null
        done = 0
        total = areas.size
        job = scope.launch {
            val verdicts = LinkedHashMap<String, CoverageVerdict>()
            val sources = LinkedHashMap<String, Int>()
            val failed = ArrayList<String>()
            var firstError: Throwable? = null

            coroutineScope {
                // a few at a time, the next starting as one finishes
                val gate = Semaphore(PARALLEL)
                val finished = Channel<Pair<Int, Result<CoverageCloudCheck.Sent>>>(Channel.UNLIMITED)
                for (i in prompts.indices) launch { gate.withPermit { finished.send(i to ask(client, prompts[i], meter)) } }
                repeat(prompts.size) {
                    val (i, result) = finished.receive()
                    result.onSuccess { reply ->
                        val found = CoverageCloudCheck.parse(reply.content, areas[i])
                        if (found.isEmpty()) failed.add(areas[i].area.name)
                        verdicts.putAll(found)
                        sources[reply.source] = (sources[reply.source] ?: 0) + 1
                    }.onFailure { error ->
                        failed.add(areas[i].area.name)
                        if (firstError == null) firstError = error
                    }
                    done += 1
                }
            }

            running = false
            if (verdicts.isEmpty()) {
                failure = said(firstError) ?: "The cloud check did not come back. The keyword check below still stands."
                blocker = blockerFor(llm)
                return@launch
            }
            val ranked = sources.entries.sortedByDescending { it.value }.map { it.key }
            val made = CoverageCheck(track.rawValue, System.currentTimeMillis(), ranked, verdicts, failed)
            withContext(CloudJobs.io) { CoverageCloudCheck.save(folder, made, track, exam) }
            check = made
            blocker = blockerFor(llm)
        }
    }

    /** One request, with its failure kept rather than thrown, so one area going wrong does not lose the others. */
    private suspend fun ask(client: BackendClient, prompt: String, meter: OwnerSpend?): Result<CoverageCloudCheck.Sent> = try {
        Result.success(CoverageCloudCheck.send(client, prompt, meter))
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        Result.failure(e)
    }

    /** The failures that are written for the student (iOS LocalizedError); anything else has no words of its own. */
    private fun said(error: Throwable?): String? = when (error) {
        is CoverageCloudCheck.Failure -> error.message
        is LLMError -> error.message
        else -> null
    }

    companion object {
        /** The product's name, as iOS's Brand.name. */
        const val brand = HostedProvider.BRAND

        /** Requests in flight at once: quick enough, and gentle on the server. */
        const val PARALLEL = 3

        /** What iOS says with no sign-in (CoverageChecker.swift:25) and without Pro (:28). */
        fun signInWords(): String = "Sign in to have $brand Cloud check this too. Until then the keyword check below is all there is."
        fun proWords(): String = "The AI check uses $brand Cloud, which is part of Pro. The keyword check below still works."

        /**
         * Why the cloud cannot be asked right now, or null when it can. Whether it
         * may is LLMService's say (Pro, a bearer, the owner key's cap); this picks
         * iOS's words for the reason - no bearer, no Pro - and the cap's own words
         * for the one iOS does not have.
         */
        fun blockerFor(llm: LLMService): String? {
            if (llm.cloudBlocker == null) return null
            return when {
                llm.cloudToken == null -> signInWords()
                !llm.isPro -> proWords()
                else -> OwnerSpend.CAP_REACHED
            }
        }
    }
}
