package com.stethoscore.app.llm

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

/**
 * Writing a set a batch at a time, apart from any model, so what happens when
 * a batch fails can be run in a test. Port of iOS Shared/LLM/BatchWriting.swift.
 *
 * A failed batch is counted and the run carries on; what was written is kept;
 * what is missing is said, and can be written again on its own (audit #88).
 */
object BatchWriting {

    /** How the batches of one run went. */
    data class Tally(
        var failedBatches: Int = 0,
        /** Batches in a row that failed or brought nothing new. */
        var inARow: Int = 0,
        /** Why the last failed batch failed, in words for the student. */
        var reason: String? = null,
        /** A failure every later batch would meet too: the run stops at once. */
        var final: Boolean = false,
    ) {
        fun batchReturned(fresh: Int) { inARow = if (fresh > 0) 0 else inARow + 1 }

        fun batchFailed(why: String, final: Boolean) {
            failedBatches += 1
            inARow += 1
            reason = why
            if (final) this.final = true
        }

        fun exhausted(patience: Int): Boolean = final || inARow >= maxOf(1, patience)
    }

    /** What a run did not write, for the screen to say and to offer again. */
    data class Shortfall(
        val wanted: Int,
        val written: Int,
        val failedBatches: Int,
        /** A textbook's parts left unwritten, as indexes into its slices; empty for cards. */
        val parts: List<Int> = emptyList(),
        val reason: String? = null,
    ) {
        val missing: Int get() = maxOf(0, wanted - written)

        /** What the student is told. [noun]: "card", "case" or "page". */
        fun message(noun: String): String {
            var said = "Wrote $written of $wanted ${plural(noun, wanted)}."
            val which = if (parts.isEmpty()) "" else " (${partList(parts)})"
            if (failedBatches > 0) {
                val batches = if (failedBatches == 1) "1 batch" else "$failedBatches batches"
                said += " $missing could not be written$which: $batches failed"
                val why = reason?.trim()
                if (!why.isNullOrEmpty()) said += " — " + why.removeSuffix(".")
                said += "."
            } else {
                said += " The model found nothing new to write for the other $missing$which."
            }
            return "$said Everything written is kept."
        }

        /** The button that writes only what is missing. */
        fun retryTitle(noun: String): String =
            "Write the missing " + if (missing == 1) noun else "$missing ${plural(noun, missing)}"
    }

    /** What a run wrote: null when it wrote everything asked for. */
    fun shortfall(wanted: Int, written: Int, tally: Tally, parts: List<Int> = emptyList()): Shortfall? {
        if (written >= wanted && parts.isEmpty()) return null
        return Shortfall(wanted, minOf(written, wanted), tally.failedBatches, parts, tally.reason)
    }

    /** A session refused (401, 403), or a model that needs Pro (402): every later batch would fail the same way. */
    fun isFinal(status: Int?): Boolean = status == 401 || status == 402 || status == 403

    /** Milliseconds to wait after a failed batch: 1, 2, 4, then 8 seconds. */
    fun waitMillis(afterFailuresInARow: Int): Long {
        if (afterFailuresInARow <= 0) return 0
        return minOf(8_000L, 1_000L shl minOf(3, afterFailuresInARow - 1))
    }

    /** A failed batch in words, and whether every later batch would fail the same way (iOS LectureWriter.failure). */
    fun failure(error: Throwable): Pair<String, Boolean> {
        val reason = error.message ?: "The request failed."
        return reason to (error is LLMError.Http && isFinal(error.status))
    }

    // cards

    class Items(val items: List<String>, val tally: Tally, val lastError: Throwable?)

    /**
     * Batches until [wanted] items are written, or [patience] batches in a row
     * bring nothing new. [batch] (round from 1, size, written so far) returns
     * only its new items. A batch that throws is counted and the run carries
     * on; a cancellation ends it at once.
     */
    suspend fun items(
        wanted: Int, perBatch: Int, patience: Int,
        classify: (Throwable) -> Pair<String, Boolean> = ::failure,
        pause: suspend (Int) -> Unit,
        onProgress: (Int, Int) -> Unit,
        batch: suspend (Int, Int, List<String>) -> List<String>,
    ): Items {
        val items = mutableListOf<String>()
        val tally = Tally()
        var lastError: Throwable? = null
        var round = 0
        while (items.size < wanted && !tally.exhausted(patience)) {
            coroutineContext.ensureActive()
            onProgress(items.size, wanted)
            val size = minOf(maxOf(1, perBatch), wanted - items.size)
            round += 1
            try {
                val fresh = batch(round, size, items.toList())
                tally.batchReturned(fresh.size)
                items += fresh.take(wanted - items.size)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val (why, final) = classify(e)
                tally.batchFailed(why, final)
                lastError = e
                if (!tally.exhausted(patience)) pause(tally.inARow)
            }
        }
        return Items(items, tally, lastError)
    }

    // a textbook's pages

    class Pages(val pages: Map<Int, String>, val missing: List<Int>, val tally: Tally, val lastError: Throwable?)

    /** Each part written once, in order; after [patience] failures in a row the rest are listed without being asked for. */
    suspend fun pages(
        parts: List<Int>, patience: Int,
        classify: (Throwable) -> Pair<String, Boolean> = ::failure,
        pause: suspend (Int) -> Unit,
        onProgress: (Int, Int) -> Unit,
        write: suspend (Int) -> String,
    ): Pages {
        val pages = linkedMapOf<Int, String>()
        val missing = mutableListOf<Int>()
        val tally = Tally()
        var lastError: Throwable? = null
        for ((n, part) in parts.withIndex()) {
            coroutineContext.ensureActive()
            if (tally.exhausted(patience)) { missing += part; continue }
            onProgress(n, parts.size)
            try {
                pages[part] = write(part)
                tally.batchReturned(1)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val (why, final) = classify(e)
                tally.batchFailed(why, final)
                lastError = e
                missing += part
                if (!tally.exhausted(patience)) pause(tally.inARow)
            }
        }
        return Pages(pages, missing, tally, lastError)
    }

    /** What stands in a textbook draft for a part not written, until it is. */
    fun gap(part: Int): String =
        "## Part ${part + 1}: not written yet\n\n> **Not written:** this part of the lecture could not be written. Use “Write the missing pages” to try again."

    /** The draft with a part's page in its gap's place, or added at the end when the gap has been edited away. */
    fun fill(draft: String, part: Int, page: String): String {
        val hole = gap(part)
        val at = draft.indexOf(hole)
        if (at >= 0) return draft.replaceRange(at, at + hole.length, page)
        if (page == hole) return draft
        val kept = draft.trim()
        return if (kept.isEmpty()) page else kept + "\n\n" + page
    }

    fun plural(noun: String, n: Int): String = if (n == 1) noun else noun + "s"

    /** "Part 4", "Parts 4 and 9", "Parts 1, 2 and 3", from zero-based parts. */
    fun partList(parts: List<Int>): String {
        val named = parts.map { (it + 1).toString() }
        val last = named.lastOrNull() ?: return ""
        if (named.size == 1) return "Part $last"
        return "Parts " + named.dropLast(1).joinToString(", ") + " and " + last
    }
}
