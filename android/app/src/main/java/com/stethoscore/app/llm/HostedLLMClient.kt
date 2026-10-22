package com.stethoscore.app.llm

import com.stethoscore.app.network.BackendClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

// Port of iOS Shared/LLM/HostedLLMClient.swift, for the one hosted model
// Android has: Stethoscore Cloud, the worker's own /v1 with the student's
// session (or the owner key) as the bearer and "cramdown-writer" as the model
// it maps to whatever it runs. The providers a student adds with their own key
// (OpenAI-compatible, Anthropic, Gemini, called from the phone) are not ported:
// on Android nothing calls a provider directly, everything goes through the worker.

/** The job a model does in the app: `writer` writes questions, stations, cards, cases and pages. */
@Suppress("EnumEntryName")
enum class LLMRole(val rawValue: String, val title: String) { writer("writer", "Writer") }

/** A hosted model: which name to ask the worker for. */
data class HostedProvider(val id: String, val name: String, val model: String) {
    companion object {
        const val CLOUD_ID = "00000000-0000-0000-0000-00000000C10D"
        const val BRAND = "Stethoscore"

        /** Stethoscore Cloud: our own worker, a model name per job that it maps itself. */
        fun cloud(@Suppress("UNUSED_PARAMETER") role: LLMRole): HostedProvider =
            HostedProvider(CLOUD_ID, "$BRAND Cloud", "cramdown-writer")
    }
}

/** Where a whole generation can be handed to the server to finish (iOS CloudJobBackend's `jobs`). */
class CloudEndpoint(
    /** A client that sends this endpoint's bearer. */
    val client: BackendClient,
    /** Whose jobs these are: "owner" for the owner key, else the account's (null when unknown). */
    val identity: String?,
    /** Counts what the owner key spends; null for any other bearer. */
    val meter: OwnerSpend?,
)

/**
 * Talks to Stethoscore Cloud. Same [LLMBackend] interface as any other writer,
 * so nothing else in the app changes with it.
 */
class HostedLLMClient(
    val provider: HostedProvider,
    private val client: BackendClient,
    /** The session or owner key the client sends; empty means none. */
    private val bearer: String,
    private val identity: String? = null,
    /** The owner build's spend cap, when the bearer is the owner key. */
    private val meter: OwnerSpend? = null,
) : LLMBackend {
    override val label: String get() = provider.name
    override val isOnDevice: Boolean get() = false
    override val promptBudgetChars: Int get() = 40_000

    /** The jobs endpoint: the cloud writer with a bearer, or null to generate call by call. */
    val jobs: CloudEndpoint? get() =
        if (provider.model == "cramdown-writer" && bearer.isNotEmpty()) CloudEndpoint(client, identity, meter) else null

    /** The request body, exactly as iOS's openAIRequest writes it. */
    fun body(turns: List<ChatTurn>, maxTokens: Int, temperature: Double): JSONObject {
        val messages = JSONArray()
        for (turn in turns) messages.put(JSONObject().put("role", turn.role.rawValue).put("content", turn.text))
        return JSONObject().put("model", provider.model).put("max_tokens", maxTokens)
            .put("temperature", temperature).put("messages", messages)
    }

    override suspend fun complete(turns: List<ChatTurn>, maxTokens: Int, temperature: Double): String {
        meter?.ensureRoom()
        val sent = body(turns, maxTokens, temperature)
        val reply = try {
            withContext(Dispatchers.IO) { client.chat(sent) }
        } catch (e: BackendClient.BackendException) {
            throw if (e.status == 0) LLMError.NotReady(e.message ?: "The server could not be reached.") else LLMError.Http(e.status, e.message ?: "")
        }
        meter?.record(reply.optJSONObject("usage"), turns.sumOf { it.text.length }, maxTokens)
        val text = LLMText.stripThinking(parse(reply))
        if (text.isEmpty()) throw LLMError.EmptyReply()
        return text
    }

    private fun parse(json: JSONObject): String {
        val message = json.optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message") ?: throw LLMError.BadResponse()
        return message.opt("content") as? String ?: throw LLMError.BadResponse()
    }
}
