package com.stethoscore.app.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

/**
 * Writing cases with whichever writer this device has. One case per call,
 * each from the next window of the lecture, each through the structure checks
 * and the accuracy rules before it is kept (CaseChecks). Port of the
 * Foundation part of iOS Features/Cases/CaseMaker.swift.
 *
 * iOS's writers (a chosen backend, Apple's on-device model, the downloaded
 * Gemma, Vignette Cloud) are not on Android yet, so [writer] finds none and
 * the screens say so ([noWriter]); the loop itself is here, run by any
 * [Writer], and tested.
 */
object CaseMaker {

    /** One call to a writer: the window of lecture and the brief in, the cases it wrote out. */
    fun interface Writer {
        suspend fun one(window: String, lecture: String, subject: String, brief: CaseWriting.Brief): List<CaseFile>

        /** Characters of lecture one call can read. */
        val sourceChars: Int get() = CaseWriting.onDeviceSourceChars
    }

    /** A failure the writer will not get past by asking again (a missing key, a refused request). */
    class Refused(message: String) : Exception(message)

    sealed class Trouble(message: String) : Exception(message) {
        class Unavailable(why: String) : Trouble(why)
        class NothingUsable(val dropped: Int) : Trouble(
            if (dropped > 0) "The cases written from this lecture did not pass the structure and accuracy checks. A lecture about a condition - its presentation, tests and treatment - works best."
            else "Nothing in that lecture could be written up as a patient. A lecture about a condition - its presentation, tests and treatment - works best."
        )
    }

    data class Made(
        val cases: List<CaseFile>,
        /** Written but refused by the checks. */
        val dropped: Int,
    )

    /** The writer to use here, or null when there is none. Android has no case writer yet. */
    fun writer(): Writer? = null

    /** Why there is no writer, in the student's words. */
    fun noWriter(): String = "On-device writing isn't available here. Writing new patients comes to Android with its AI models."

    /** The lecture as the writers read it, each page marked with its number so the teaching can cite it. */
    fun sourceText(pages: List<Pair<Int, String>>): String =
        pages.filter { it.second.trim().isNotEmpty() }.joinToString("\n\n") { "[Page ${it.first}]\n${it.second}" }

    suspend fun write(
        count: Int, source: String, lecture: String, subject: String,
        brief: CaseWriting.Brief = CaseWriting.Brief(), using: Writer,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): Made {
        val wanted = count.coerceIn(1, CaseWriting.maxCases)
        val windows = TextSlicing.windows(source, using.sourceChars)
        val kept = mutableListOf<CaseFile>()
        var dropped = 0
        var failures = 0
        var round = 0
        while (kept.size < wanted && failures < 3 && round < wanted * 3) {
            coroutineContext.ensureActive()
            onProgress(kept.size, wanted)
            var asked = brief
            if (asked.setting == null && asked.diagnosis == null) asked = asked.copy(setting = CaseWriting.setting(round))
            if (asked.diagnosis == null) asked = asked.copy(avoid = brief.avoid + kept.map { it.diagnosis.name })
            val window = if (windows.isEmpty()) "" else TextSlicing.window(windows, round)
            round += 1
            try {
                val written = using.one(window, lecture, subject, asked)
                val screened = CaseChecks.screen(written)
                dropped += screened.dropped.size
                var added = 0
                for (file in screened.kept) {
                    if (kept.size >= wanted) break
                    // one patient per diagnosis in a run, unless asked for one
                    if (brief.diagnosis == null && kept.any { CaseNames.same(it.diagnosis.name, file.diagnosis.name) }) continue
                    kept += file
                    added += 1
                }
                failures = if (added == 0) failures + 1 else 0
            } catch (e: CancellationException) {
                throw e
            } catch (e: Refused) {
                throw e
            } catch (e: Trouble.Unavailable) {
                throw e
            } catch (e: Exception) {
                failures += 1
            }
        }
        onProgress(kept.size, wanted)
        if (kept.isEmpty()) throw Trouble.NothingUsable(dropped)
        return Made(kept, dropped)
    }
}

/** Cutting a lecture into windows a prompt can hold (the part of iOS's TextSlicing the case writer uses). */
object TextSlicing {

    /**
     * A source longer than one prompt can hold, as windows that each fit, cut
     * at a paragraph, line or sentence end where one is near, so every part of
     * a lecture is read by some call.
     */
    fun windows(text: String, maxChars: Int): List<String> {
        val limit = maxOf(500, maxChars)
        if (text.length <= limit) return listOf(text)
        val out = mutableListOf<String>()
        var rest = text
        while (rest.isNotEmpty()) {
            if (rest.length <= limit) { out += rest; break }
            val head = rest.substring(0, limit)
            // a paragraph end in the last third of the window, else a line or
            // sentence end in its last fifth, else a hard cut
            var cut = limit
            for ((mark, share) in listOf("\n\n" to 2, "\n" to 4, ". " to 4)) {
                val floor = limit * share / (share + 1)
                val at = head.lastIndexOf(mark)
                if (at >= 0 && at >= floor) { cut = at + mark.length; break }
            }
            out += rest.substring(0, cut).trim()
            rest = rest.substring(cut)
        }
        return out.filter { it.isNotEmpty() }
    }

    /** The window a call reads: each call the next one, round and round. */
    fun window(windows: List<String>, round: Int): String {
        if (windows.isEmpty()) return ""
        return windows[((round % windows.size) + windows.size) % windows.size]
    }
}
