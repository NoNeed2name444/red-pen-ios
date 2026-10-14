package com.stethoscore.app.network

import android.os.Looper
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.time.Instant

/**
 * The existing Stethoscore worker contract, ported from AuthAPI/SyncAPI/CloudJobs.
 * Calls are synchronous: invoke on an executor or Dispatchers.IO. Creating this
 * client never connects. There is no default server and no automatic retry.
 */
class BackendClient(baseUrl: String, private val tokenProvider: () -> String? = { null }) {
    val baseUrl: String = validateBaseUrl(baseUrl)

    fun createDeviceAccount(): JSONObject = request("POST", "/auth/device", JSONObject(), authenticated = false)

    fun pair(code: String): JSONObject {
        require(code.isNotBlank()) { "Enter a pairing code." }
        return request("POST", "/auth/pair", JSONObject().put("code", code.trim()), authenticated = false)
    }

    fun refreshSession(refreshToken: String): JSONObject {
        require(refreshToken.isNotBlank()) { "A refresh token is required." }
        return request("POST", "/auth/refresh", JSONObject().put("refreshToken", refreshToken), authenticated = false)
    }

    /** Newer workers implement this route; older ones return NOT_CONFIGURED. */
    fun accountMe(): JSONObject = request("POST", "/account/me", JSONObject())

    fun pairingCode(): JSONObject = request("POST", "/pair/start", JSONObject())

    /** Exactly /sync/changes; there is no /sync/pull in the source worker. */
    fun pullSync(since: Long, limit: Int = 200): JSONObject {
        require(since >= 0) { "The sync cursor cannot be negative." }
        require(limit in 1..500) { "A sync page contains 1 to 500 documents." }
        return request("POST", "/sync/changes", JSONObject().put("since", since).put("limit", limit), timeoutMillis = 60_000)
    }

    /** Returns accepted, conflicts and optional resting; never discards conflicts. */
    fun pushSync(docs: JSONArray): JSONObject {
        require(docs.length() <= 500) { "Push no more than 500 documents at once." }
        for (i in 0 until docs.length()) validateSyncDocument(docs.getJSONObject(i))
        return request("POST", "/sync/push", JSONObject().put("docs", docs), timeoutMillis = 60_000)
    }

    /** Explicit cloud operation; the caller chooses when to send study content. */
    fun checkAccuracy(items: JSONArray, priority: String = "foreground", exam: String? = null): JSONObject {
        require(items.length() in 1..4) { "Check between 1 and 4 items at once." }
        require(priority == "foreground" || priority == "background") { "Unknown accuracy priority." }
        val body = JSONObject().put("items", items).put("priority", priority)
        if (!exam.isNullOrBlank()) body.put("exam", exam)
        return request("POST", "/accuracy/check", body, timeoutMillis = 120_000)
    }

    fun accuracyModel(): JSONObject = request("POST", "/accuracy/model", JSONObject(), authenticated = false)

    /** A job starts generation. Call only from an explicit user action. */
    fun createJob(spec: JSONObject): JSONObject {
        require(spec.optString("mode") in setOf("loop", "each")) { "The job mode must be loop or each." }
        require(spec.optString("extract") in setOf("lines", "questions", "stations", "pages")) { "Unknown job output format." }
        require((spec.optJSONArray("steps")?.length() ?: 0) in 1..200) { "A job needs 1 to 200 prompts." }
        return request("POST", "/jobs", spec, timeoutMillis = 60_000)
    }

    fun listJobs(): JSONObject = request("GET", "/jobs")
    fun jobStatus(id: String): JSONObject = request("GET", "/jobs/${jobId(id)}")
    fun jobResult(id: String): JSONObject = request("GET", "/jobs/${jobId(id)}?outputs=1", timeoutMillis = 60_000)
    fun cancelJob(id: String): JSONObject = request("DELETE", "/jobs/${jobId(id)}")

    private fun jobId(id: String): String {
        require(Regex("^[a-f0-9-]{36}$").matches(id)) { "Invalid job id." }
        return id
    }

    private fun request(
        method: String,
        path: String,
        body: JSONObject? = null,
        authenticated: Boolean = true,
        timeoutMillis: Int = 20_000
    ): JSONObject {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Run backend requests off the main thread." }
        val token = if (authenticated) tokenProvider()?.trim()?.takeIf { it.isNotEmpty() }
            ?: throw BackendException(0, Failure.SIGNED_OUT, "Add a session token in Settings before connecting.") else null
        require(token == null || (token.length <= 16_384 && token.none { it.code < 32 || it.code == 127 })) { "Invalid session token." }
        val encoded = body?.toString()?.toByteArray(Charsets.UTF_8)
        require(encoded == null || encoded.size <= MAX_BODY_BYTES) { "That request is too large." }
        val connection = URL(baseUrl + path).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = minOf(timeoutMillis, 30_000)
            connection.readTimeout = timeoutMillis
            // Never forward a bearer token to another host through a redirect.
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.setRequestProperty("Accept", "application/json")
            if (token != null) connection.setRequestProperty("Authorization", "Bearer $token")
            if (encoded != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.setFixedLengthStreamingMode(encoded.size)
                connection.outputStream.use { it.write(encoded) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val raw = stream?.use { input ->
                val result = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (result.size() + count > MAX_RESPONSE_BYTES) throw IOException("The server response is too large.")
                    result.write(buffer, 0, count)
                }
                result.toString(Charsets.UTF_8.name())
            }.orEmpty()
            val reply = if (raw.isBlank()) JSONObject() else try { JSONObject(raw) } catch (_: Exception) { null }
            if (status !in 200..299) {
                val code = (reply?.opt("code") as? String)?.trim().orEmpty()
                val said = (reply?.opt("message") as? String) ?: (reply?.opt("error") as? String)
                val failure = classify(status, code, said)
                val message = said?.takeIf { it.isNotBlank() } ?: defaultMessage(failure)
                throw BackendException(status, failure, message, code, reply, connection.getHeaderField("Retry-After"))
            }
            return reply ?: throw BackendException(status, Failure.SERVER, "The server sent an unreadable response.")
        } catch (e: BackendException) {
            throw e
        } catch (e: IOException) {
            throw BackendException(0, Failure.OFFLINE, "The server could not be reached. Your local library is still available.", cause = e)
        } finally {
            connection.disconnect()
        }
    }

    enum class Failure { OFFLINE, SIGNED_OUT, NEEDS_PRO, NEEDS_CONSENT, RATE_LIMITED, REFUSED, NOT_CONFIGURED, NOT_FOUND, GONE, SERVER }

    class BackendException(
        val status: Int,
        val failure: Failure,
        message: String,
        val code: String = "",
        /** Preserve partial accuracy results, quota information and server reasons. */
        val response: JSONObject? = null,
        val retryAfter: String? = null,
        cause: Throwable? = null
    ) : IOException(message, cause)

    companion object {
        private const val MAX_BODY_BYTES = 24 * 1024 * 1024
        private const val MAX_RESPONSE_BYTES = 32 * 1024 * 1024

        fun validateBaseUrl(value: String): String {
            val parsed = try { URI(value.trim()) } catch (_: Exception) { throw IllegalArgumentException("Enter a valid HTTPS server URL.") }
            require(parsed.scheme.equals("https", ignoreCase = true) && !parsed.host.isNullOrBlank()) { "The server URL must use HTTPS." }
            require(parsed.rawUserInfo == null && parsed.rawQuery == null && parsed.rawFragment == null) { "Use a server URL without credentials, a query or a fragment." }
            require(parsed.path.isNullOrEmpty() || parsed.path == "/") { "Use the server origin without an endpoint path." }
            require(parsed.port == -1 || parsed.port in 1..65535) { "Invalid server port." }
            return parsed.toASCIIString().trimEnd('/')
        }

        /** Wire payload is UTF-8 JSON encoded as base64, matching Swift Data. */
        fun syncDocument(id: String, kind: String, rev: Long, updatedAt: String, payload: JSONObject?, deleted: Boolean = false): JSONObject {
            val encoded = if (deleted || payload == null) JSONObject.NULL else Base64.encodeToString(payload.toString().toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
            return JSONObject().put("id", id).put("kind", kind).put("rev", rev)
                .put("updatedAt", updatedAt).put("deleted", deleted).put("payload", encoded)
                .also { validateSyncDocument(it) }
        }

        private fun validateSyncDocument(doc: JSONObject) {
            require(doc.optString("id").length in 1..200) { "Invalid sync document id." }
            require(doc.optString("kind") in setOf("set", "folder", "review", "saying")) { "Unknown sync document kind." }
            require(doc.has("rev") && doc.getLong("rev") >= 0) { "A document needs its last server revision." }
            try { Instant.parse(doc.getString("updatedAt")) } catch (_: Exception) { throw IllegalArgumentException("Use an ISO 8601 UTC timestamp for updatedAt.") }
            require(doc.opt("deleted") is Boolean) { "A document needs a deleted flag." }
            val payload = doc.opt("payload")
            require(payload == null || payload === JSONObject.NULL || (payload is String && payload.length <= 1_900_000)) { "A payload must be base64 text or null." }
            require(!doc.optBoolean("deleted") || payload == null || payload === JSONObject.NULL) { "A deleted document cannot carry a payload." }
        }

        private fun classify(status: Int, code: String, message: String?): Failure = when {
            status == 401 -> Failure.SIGNED_OUT
            status == 402 -> Failure.NEEDS_PRO
            status == 428 -> Failure.NEEDS_CONSENT
            status == 429 -> Failure.RATE_LIMITED
            code.isNotEmpty() -> Failure.REFUSED
            status == 403 -> Failure.SIGNED_OUT
            status == 404 && (message.isNullOrBlank() || message == "No such endpoint.") -> Failure.NOT_CONFIGURED
            status == 404 -> Failure.NOT_FOUND
            status == 410 -> Failure.GONE
            else -> Failure.SERVER
        }

        private fun defaultMessage(failure: Failure): String = when (failure) {
            Failure.SIGNED_OUT -> "Please sign in again."
            Failure.NEEDS_PRO -> "That feature requires Pro on this server."
            Failure.NEEDS_CONSENT -> "The server requires your consent before this operation."
            Failure.RATE_LIMITED -> "Too many requests. Try again later."
            Failure.NOT_CONFIGURED -> "This server does not provide that endpoint."
            Failure.NOT_FOUND -> "The requested item could not be found."
            Failure.GONE -> "That item is no longer available."
            else -> "Something went wrong talking to the server."
        }
    }
}
