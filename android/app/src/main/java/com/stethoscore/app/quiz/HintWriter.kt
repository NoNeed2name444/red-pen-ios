package com.stethoscore.app.quiz

import com.stethoscore.app.llm.ChatTurn
import com.stethoscore.app.llm.LLMBackend
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The hint for an item in the quiz: a port of iOS HintWriter
 * (Shared/Exam/ExamStore.swift). Kept from before, written now, or made from
 * its differential when there is no writer or the written one gave the answer
 * away. Never throws but to pass on a cancellation: a hint is always there.
 *
 * [backend] is the writer, and null is "no writer": the caller hands over
 * `LLMService.backend()`, which is null unless the app may call a model right
 * now (Pro, signed in, and the owner build's $20 cap not reached), so this
 * adds no gate of its own and sends nothing where nothing may be sent.
 */
object HintWriter {
    /** The reply's room and looseness, as iOS asks for them. */
    const val maxTokens = 160
    const val temperature = 0.4

    /** What the held Hint button says aloud while the writer works. */
    const val writing = "Writing a hint"

    suspend fun hint(
        id: String, stem: String, options: List<String>, answer: String, differential: DifferentialTiers?,
        backend: LLMBackend?, store: HintStore,
    ): String {
        val version = HintCache.version(stem, options, answer)
        val others = options.filter { it != answer }
        // a kept hint costs nothing; it is looked at once more, so a changed file can never show the answer
        val kept = withContext(Dispatchers.IO) { store.hint(id, version) }
        if (kept != null && !AttendingHint.leaks(kept, answer, stem, others)) return kept
        val fallback = AttendingHint.fallback(answer, stem, options, differential)
        backend ?: return fallback
        val input = AttendingHint.input(stem, options, answer, differential)
        val reply = try {
            backend.complete(listOf(ChatTurn.system(AttendingHint.instructions), ChatTurn.user(input)), maxTokens, temperature)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return fallback
        }
        val good = AttendingHint.accept(reply, answer, stem, others) ?: return fallback
        withContext(Dispatchers.IO) { store.keep(good, id, version) }
        return good
    }
}
