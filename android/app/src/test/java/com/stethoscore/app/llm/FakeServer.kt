package com.stethoscore.app.llm

import com.stethoscore.app.network.BackendClient
import org.json.JSONObject

/**
 * A stand-in for the worker: every request is recorded, and answered by
 * [answer]. Nothing goes on the network.
 */
class FakeServer(var answer: (Request) -> BackendClient.Reply = { BackendClient.Reply(404, "{}") }) : BackendClient.Transport {
    data class Request(val method: String, val url: String, val body: JSONObject?, val bearer: String?) {
        val path: String get() = url.substringAfter(BASE)
    }

    val requests = mutableListOf<Request>()

    override fun send(method: String, url: String, body: ByteArray?, bearer: String?, timeoutMillis: Int): BackendClient.Reply {
        val request = Request(method, url, body?.let { JSONObject(String(it, Charsets.UTF_8)) }, bearer)
        requests += request
        return answer(request)
    }

    fun client(bearer: String?): BackendClient = BackendClient(BASE, { bearer }, this)

    companion object {
        const val BASE = "https://worker.example"

        fun ok(json: JSONObject): BackendClient.Reply = BackendClient.Reply(200, json.toString())

        /** A chat reply in the worker's OpenAI shape, with or without usage. */
        fun chat(content: String, usage: JSONObject? = null): BackendClient.Reply {
            val reply = JSONObject().put("choices", org.json.JSONArray().put(JSONObject().put("message", JSONObject().put("role", "assistant").put("content", content))))
                .put("source", "test")
            usage?.let { reply.put("usage", it) }
            return ok(reply)
        }

        /** A key of the owner key's shape, made here: never a real one. */
        fun standInKey(): String = "k".repeat(40)
    }
}

/** A worker that runs one job: created, reported done, its replies handed back, then forgotten. */
class FakeJobs(private val outputs: List<String>, private val id: String = "0f8fad5b-d9cb-469f-a165-70867728950e") {
    var spec: JSONObject? = null
    var deleted = 0

    fun answer(request: FakeServer.Request): com.stethoscore.app.network.BackendClient.Reply = when {
        request.method == "POST" && request.path == "/jobs" -> {
            spec = request.body
            FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id).put("status", "queued")))
        }
        request.method == "GET" && request.path == "/jobs/$id" ->
            FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id).put("title", spec?.optString("title")).put("status", "done")
                .put("done", spec?.optInt("count") ?: 0).put("total", spec?.optInt("count") ?: 0)))
        request.method == "GET" && request.path == "/jobs/$id?outputs=1" ->
            FakeServer.ok(JSONObject().put("job", JSONObject().put("id", id)).put("outputs", org.json.JSONArray(outputs)))
        request.method == "DELETE" && request.path == "/jobs/$id" -> { deleted += 1; FakeServer.ok(JSONObject().put("ok", true)) }
        else -> com.stethoscore.app.network.BackendClient.Reply(404, "{}")
    }
}
