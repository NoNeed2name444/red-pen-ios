package com.stethoscore.app.llm

import org.json.JSONObject
import java.util.Locale
import kotlin.math.ceil

/**
 * What the owner's personal build has spent on Stethoscore Cloud with the
 * owner key, and the cap it stops at: $20.00. Android's own guard, kept on
 * this device; the worker keeps its own monthly cap for the owner key as well
 * (server/ai.js wallet, OWNER_MONTHLY_USD), and a public build, which has no
 * owner key, never counts anything here.
 *
 * Every reply is priced like the worker's Anthropic route (server/ai.js
 * routeFor: Claude Opus, `claude-opus-5-5`, $4 a million tokens in and $20 out,
 * priceOf and GEMINI_PRICES in wrangler.toml), from the token counts the reply
 * reports, in the shapes costOf reads. The worker's replies do not report
 * usage today, so most are counted the way a reply with no usage is: the
 * prompt at a token for every three characters (as askClaudeVoter estimates
 * it) and the request's max_tokens as output - the most it could have cost.
 */
class OwnerSpend(private val store: Store, val capMicros: Long = CAP_MICROS) {

    /** Where the running total is kept, in millionths of a dollar. */
    interface Store {
        fun read(): Long
        fun write(micros: Long)
    }

    class MemoryStore(private var micros: Long = 0) : Store {
        override fun read(): Long = micros
        override fun write(micros: Long) { this.micros = micros }
    }

    val spentMicros: Long @Synchronized get() = store.read()

    val capReached: Boolean get() = spentMicros >= capMicros

    /** "$3.40 of $20.00", for the model settings screen. */
    val said: String get() = "${dollars(spentMicros)} of ${dollars(capMicros)}"

    /** Throws the cap's words once it is reached: nothing more is sent with the owner key. */
    fun ensureRoom() {
        if (capReached) throw LLMError.NotReady(CAP_REACHED)
    }

    /** Adds one reply: its reported usage, or its worst case when it reports none. Returns what was added. */
    @Synchronized
    fun record(usage: JSONObject?, promptChars: Int, maxTokens: Int): Long {
        val cost = usage?.let { costMicros(it) } ?: estimateMicros(promptChars, maxTokens)
        store.write(store.read() + cost)
        return cost
    }

    companion object {
        const val CAP_MICROS: Long = 20_000_000
        /** The Anthropic route's model and price (server/ai.js DEFAULT_ANTHROPIC_MODEL, priceOf). */
        const val MODEL = "claude-opus-5-5"
        const val INPUT_PER_MILLION = 4.0
        const val OUTPUT_PER_MILLION = 20.0

        const val CAP_REACHED = "This build has used its \$20.00 of Stethoscore Cloud, so the AI modes are stopped. Nothing more is sent."

        /** server/ai.js costOf for a Claude model: input, cache reads at a tenth, cache writes at 1.25, output. Null when the object names no tokens at all. */
        fun costMicros(usage: JSONObject): Long? {
            val inKeys = listOf("input_tokens", "prompt_tokens", "promptTokenCount")
            val outKeys = listOf("output_tokens", "completion_tokens", "candidatesTokenCount")
            if ((inKeys + outKeys).none { usage.has(it) }) return null
            fun first(keys: List<String>): Double = keys.firstOrNull { usage.has(it) }?.let { usage.optDouble(it, 0.0) } ?: 0.0
            val input = first(inKeys)
            val cached = usage.optDouble("cache_read_input_tokens", 0.0) * 0.1 + usage.optDouble("cache_creation_input_tokens", 0.0) * 1.25
            val output = first(outKeys) + usage.optDouble("thoughtsTokenCount", 0.0)
            return ceil((input + cached) * INPUT_PER_MILLION + output * OUTPUT_PER_MILLION).toLong()
        }

        /** A reply with no usage: the prompt at three characters a token, and the request's max_tokens out. */
        fun estimateMicros(promptChars: Int, maxTokens: Int): Long {
            val input = ceil(maxOf(0, promptChars) / 3.0)
            return ceil(input * INPUT_PER_MILLION + maxOf(0, maxTokens) * OUTPUT_PER_MILLION).toLong()
        }

        fun dollars(micros: Long): String = String.format(Locale.US, "$%.2f", micros / 1_000_000.0)
    }
}
