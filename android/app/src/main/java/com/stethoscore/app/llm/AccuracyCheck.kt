package com.stethoscore.app.llm

import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.network.BackendClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * How one send to /accuracy/check ended. Port of iOS Shared/NetworkFaults.swift
 * AccuracySendOutcome, rule for rule.
 */
sealed class AccuracySendOutcome {
    data object Done : AccuracySendOutcome()
    data object DayUsed : AccuracySendOutcome()
    data class NotPro(val why: String) : AccuracySendOutcome()
    data object Offline : AccuracySendOutcome()
    /** The server answered, but no checker did. */
    data object Busy : AccuracySendOutcome()

    /** Whether the reply says anything about the items (a refusal does not). */
    val records: Boolean get() = this !is NotPro

    companion object {
        fun of(status: Int?, limit: String?, message: String?, busy: Boolean = false): AccuracySendOutcome {
            if (status == null) return Offline
            if (status == 402) return NotPro(message ?: "The accuracy check is part of Pro.")
            if (status == 401) return NotPro("Sign in again to check accuracy.")
            if (status == 429 || limit == "day") return DayUsed
            if (status == 200 && busy) return Busy
            return if (status == 200) Done else Offline
        }
    }
}

/**
 * The accuracy checker's cloud half: sending items to the worker's
 * /accuracy/check and saying what came of it. Port of iOS
 * Shared/Accuracy/AccuracyStore.swift send() and checkNow(), same words.
 *
 * Not ported (T0115b): the ledger kept on disk, the trained weights
 * (/accuracy/model), the background loop through the library, reports
 * (/accuracy/report) and the screens that show a grade - Android has none of
 * them yet, so the reply is handed back for the caller to keep.
 */
object AccuracyCheck {

    /** What one send gave: how it ended, and the server's reply when there was one. */
    data class Sent(val outcome: AccuracySendOutcome, val reply: JSONObject?)

    /** An item as the worker reads it (iOS AccuracyItem's Codable keys). */
    fun json(item: AccuracyItem): JSONObject = JSONObject().put("id", item.id).put("kind", item.kind.rawValue)
        .put("stem", item.stem).put("options", JSONArray(item.options)).put("key", item.key)
        .put("explanation", item.explanation).put("text", item.text).put("source", item.source)

    /**
     * The owner key's spend on a check: the worker asks Claude to vote on the
     * owner's items (server/accuracy.js askClaudeVoter, max_tokens 500 a
     * item + 600), and its reply carries no usage, so it is counted at that.
     */
    fun maxTokens(items: Int): Int = 500 * items + 600

    suspend fun send(client: BackendClient, items: List<AccuracyItem>, priority: String = "foreground",
                     meter: OwnerSpend? = null): Sent {
        meter?.ensureRoom()
        val body = JSONArray(items.map { json(it) })
        val reply: JSONObject
        try {
            reply = withContext(Dispatchers.IO) { client.checkAccuracy(body, priority) }
        } catch (e: BackendClient.BackendException) {
            if (e.status == 0) return Sent(AccuracySendOutcome.Offline, null)
            val said = e.response
            return Sent(AccuracySendOutcome.of(e.status, said?.opt("limit") as? String, e.message), said)
        }
        meter?.record(reply.optJSONObject("usage"), items.sumOf { it.checkedText.length + it.source.length }, maxTokens(items.size))
        val outcome = AccuracySendOutcome.of(200, reply.opt("limit") as? String, reply.opt("message") as? String, reply.optBoolean("busy"))
        return Sent(outcome, reply)
    }

    /** Whether the reply holds a vote on this item (iOS ledger.isChecked). */
    fun isChecked(reply: JSONObject?, id: String): Boolean {
        val items = reply?.optJSONArray("items") ?: return false
        return (0 until items.length()).mapNotNull { items.optJSONObject(it) }
            .any { it.optString("id") == id && (it.optJSONArray("votes")?.length() ?: 0) > 0 }
    }

    /** One item now, for the student who asked: null when it was checked, else why not. */
    suspend fun checkNow(item: AccuracyItem, service: LLMService): Pair<String?, JSONObject?> {
        val (client, blocker) = service.checker()
        if (client == null) return (blocker ?: "Sign in to check accuracy.") to null
        val sent = try {
            send(client, listOf(item), "foreground", if (service.usesOwnerKey) service.spend else null)
        } catch (e: LLMError.NotReady) {
            return (e.message ?: OwnerSpend.CAP_REACHED) to null
        }
        val said = when (val outcome = sent.outcome) {
            AccuracySendOutcome.Done -> if (isChecked(sent.reply, item.id)) null else "The checkers are busy. Try again in a minute."
            AccuracySendOutcome.DayUsed -> "Today's free checks are used. Try again after midnight UTC."
            is AccuracySendOutcome.NotPro -> outcome.why
            AccuracySendOutcome.Offline -> "Couldn't reach the server. Check your connection."
            AccuracySendOutcome.Busy -> "The checkers are busy. Try again in a few minutes."
        }
        return said to sent.reply
    }
}
