package com.stethoscore.app.llm

import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.accuracy.AccuracyText
import com.stethoscore.app.accuracy.AccuracyWeights
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.network.BackendClient
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
 * Not ported (T0115b): the background loop through the library and the
 * screens that show a grade, so the reply is handed back for the caller to
 * keep (AccuracyLedger.record, over AccuracyCheckReply.parse). The ledger, the
 * weights and the two calls that reach /accuracy/model and /accuracy/report
 * (fetchWeights, report) are here, used only where a model call is allowed
 * (LLMService.checker: Pro, a session or the owner key, and the $20 cap).
 */
object AccuracyCheck {

    private const val SIGN_IN = "Sign in to check accuracy."

    /** What one send gave: how it ended, and the server's reply when there was one. */
    data class Sent(val outcome: AccuracySendOutcome, val reply: JSONObject?)

    /** An item as the worker reads it (iOS AccuracyItem's Codable keys). */
    fun json(item: AccuracyItem): JSONObject = JSONObject().put("id", item.id).put("kind", item.kind.rawValue)
        .put("stem", item.stem).put("options", JSONArray(item.options)).put("key", item.key)
        .put("explanation", item.explanation).put("text", item.text).put("source", item.source)

    /**
     * The item with its lecture excerpt, as iOS builds every item (AccuracyStore.build):
     * the pages of the set's sources nearest to the item's words, up to
     * [AccuracyItem.sourceLimit] characters, which [send] then sends as the
     * item's `source` and the server checks it against. An item that has an
     * excerpt, or a set with no source or none that shares a word, is returned
     * as it is.
     */
    fun withExcerpt(item: AccuracyItem, set: StudySet): AccuracyItem {
        if (item.source.isNotBlank()) return item
        val excerpt = AccuracyText.reference(item.checkedText, set, AccuracyItem.sourceLimit) ?: return item
        return item.copy(source = excerpt.take(AccuracyItem.sourceLimit))
    }

    /** Every checkable item of a set with its lecture excerpt (iOS AccuracyItem.items(in:) as AccuracyStore.build calls it). */
    fun items(set: StudySet): List<AccuracyItem> =
        AccuracyItem.items(set) { words -> AccuracyText.reference(words, set, AccuracyItem.sourceLimit) }

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
            reply = withContext(CloudJobs.io) { client.checkAccuracy(body, priority) }
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
        if (client == null) return (blocker ?: SIGN_IN) to null
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

    /** What asking for the newest trained weights came to. */
    sealed class WeightsFetch {
        /** Weights in the model's shape; the caller keeps them if they differ from the ones it scores with. */
        data class Fresh(val weights: AccuracyWeights) : WeightsFetch()
        /** The cloud may not be used now (not Pro, no session, the owner's cap reached): nothing was sent. */
        data class Blocked(val why: String) : WeightsFetch()
        /** The server answered something that is not usable weights; the old ones stay (iOS refreshWeights). */
        data object Unusable : WeightsFetch()
        data object Offline : WeightsFetch()
    }

    /**
     * The newest trained weights (iOS AccuracyStore.refreshWeights' request),
     * asked for only where a model call is allowed. Asking once a day, and
     * keeping what comes back, is the store's.
     */
    suspend fun fetchWeights(service: LLMService): WeightsFetch {
        val (client, blocker) = service.checker()
        if (client == null) return WeightsFetch.Blocked(blocker ?: SIGN_IN)
        val reply = try {
            withContext(CloudJobs.io) { client.accuracyModel() }
        } catch (e: BackendClient.BackendException) {
            return if (e.status == 0) WeightsFetch.Offline else WeightsFetch.Unusable
        }
        return AccuracyWeights.fromReply(reply)?.let { WeightsFetch.Fresh(it) } ?: WeightsFetch.Unusable
    }

    /** How sending a report came out (iOS AccuracyStore.report keeps the report on the device whatever this is). */
    sealed class ReportOutcome {
        data object Sent : ReportOutcome()
        /** The cloud may not be used now: nothing was sent. */
        data class Blocked(val why: String) : ReportOutcome()
        data object Offline : ReportOutcome()
        /** The server did not take it: its status (429 is today's reports used). */
        data class Refused(val status: Int) : ReportOutcome()
    }

    /**
     * "Report an error": sends the item and the note to the worker for the
     * next training run, only where a model call is allowed. Marking the item
     * reported on this device (AccuracyLedger.markReported) comes first and
     * does not wait for this.
     */
    suspend fun report(item: AccuracyItem, note: String, service: LLMService): ReportOutcome {
        val (client, blocker) = service.checker()
        if (client == null) return ReportOutcome.Blocked(blocker ?: SIGN_IN)
        try {
            withContext(CloudJobs.io) { client.accuracyReport(json(item), note) }
        } catch (e: BackendClient.BackendException) {
            return if (e.status == 0) ReportOutcome.Offline else ReportOutcome.Refused(e.status)
        }
        return ReportOutcome.Sent
    }
}
