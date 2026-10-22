package com.stethoscore.app.llm

import org.json.JSONArray
import org.json.JSONObject

// The model layer's shared parts: a turn of conversation, the interface every
// writer sits behind, its errors in the student's words, and the pure text
// helpers (stripping a reasoning model's working, pulling JSON items out of a
// chatty reply, reading a keyed option). Port of iOS Shared/LLM/LLMCore.swift
// (ChatTurn, LLMBackend, LLMError) and Shared/LLM/LLMParsing.swift (LLMText).

/** One turn of a conversation with a model. */
data class ChatTurn(val role: Role, val text: String) {
    @Suppress("EnumEntryName")
    enum class Role(val rawValue: String) { system("system"), user("user"), assistant("assistant") }

    companion object {
        fun system(text: String) = ChatTurn(Role.system, text)
        fun user(text: String) = ChatTurn(Role.user, text)
        fun assistant(text: String) = ChatTurn(Role.assistant, text)
    }
}

/** Anything that can finish a conversation; a mode never knows which one it got. */
interface LLMBackend {
    val label: String
    /** True when this backend runs on the device and sends nothing anywhere. */
    val isOnDevice: Boolean
    /** Characters of source one prompt can carry. */
    val promptBudgetChars: Int
    suspend fun complete(turns: List<ChatTurn>, maxTokens: Int, temperature: Double): String
}

/** iOS LLMError, with its errorDescription as the message. */
sealed class LLMError(message: String) : Exception(message) {
    class NotReady(why: String) : LLMError(why)
    class EmptyReply : LLMError("The model returned nothing usable — try again.")
    class Http(val status: Int, val body: String) : LLMError(describe(status, body))
    class BadResponse : LLMError("The hosted model answered in a shape the app doesn't understand.")

    companion object {
        /** The server's own refusals (Pro, quota, an app too old) are sentences meant for the student. */
        val plainRefusals: Set<Int> = setOf(401, 402, 403, 409, 410, 429)

        /** A message a person can read, not a JSON or HTML error page. */
        fun readable(body: String): Boolean {
            val text = body.trim()
            return text.isNotEmpty() && !text.startsWith("{") && !text.startsWith("<")
        }

        fun describe(status: Int, body: String): String =
            if (status in plainRefusals && readable(body)) body.take(200)
            else "The hosted model refused the request (HTTP $status). ${body.take(160)}"
    }
}

object LLMText {
    /** A reasoning model's answer follows a `<think>...</think>` block that is working, not output. */
    fun stripThinking(raw: String): String {
        val end = raw.lastIndexOf("</think>")
        val text = when {
            end >= 0 -> raw.substring(end + "</think>".length)
            // cut off mid-thought: nothing after it is an answer
            raw.contains("<think>") -> ""
            else -> raw
        }
        return text.trim()
    }

    /** The outermost `{...}` in a reply, for models that wrap JSON in prose or a code fence. */
    fun jsonObject(raw: String): String? {
        val start = raw.indexOf('{')
        val end = raw.lastIndexOf('}')
        if (start < 0 || end <= start) return null
        return raw.substring(start, end + 1)
    }

    /**
     * Each object in the `key` array of a JSON reply, read one at a time, so
     * one malformed item costs only itself. A reply cut off mid-array still
     * gives back every item that was complete.
     */
    fun jsonItems(raw: String, key: String): List<JSONObject> {
        val whole = jsonObject(raw)?.let { runCatching { JSONObject(it) }.getOrNull() }
        val list = whole?.optJSONArray(key)
        if (list != null) return (0 until list.length()).mapNotNull { list.optJSONObject(it) }
        return completeItems(raw, key)
    }

    /** The complete `{...}` objects inside a `"key": [` array that may never close. Braces inside strings are not counted. */
    fun completeItems(raw: String, key: String): List<JSONObject> {
        val named = raw.indexOf("\"$key\"")
        if (named < 0) return emptyList()
        val open = raw.indexOf('[', named + key.length + 2)
        if (open < 0) return emptyList()
        val out = mutableListOf<JSONObject>()
        var depth = 0
        var inString = false
        var escaped = false
        var start = -1
        var i = open + 1
        while (i < raw.length) {
            val c = raw[i]
            if (inString) {
                if (escaped) escaped = false else if (c == '\\') escaped = true else if (c == '"') inString = false
            } else if (c == '"') {
                inString = true
            } else if (c == '{') {
                if (depth == 0) start = i
                depth += 1
            } else if (c == '}') {
                depth -= 1
                if (depth < 0) break
                if (depth == 0 && start >= 0) {
                    runCatching { JSONObject(raw.substring(start, i + 1)) }.getOrNull()?.let { out += it }
                    start = -1
                }
            } else if (c == ']' && depth == 0) {
                break
            }
            i += 1
        }
        return out
    }

    /** The keyed option however a model wrote it - 2, "2", "C", or the option's own text. Null when it names no option. */
    fun keyIndex(value: Any?, options: List<String>): Int? {
        val index: Int? = when (value) {
            is Int -> value
            is Long -> value.toInt()
            is Double -> if (value % 1.0 == 0.0) value.toInt() else null
            is String -> {
                val t = value.trim()
                t.toIntOrNull() ?: if (t.length == 1 && t.uppercase()[0] in 'A'..'Z') t.uppercase()[0] - 'A'
                else options.indexOfFirst { it.equals(t, ignoreCase = true) }.takeIf { it >= 0 }
            }
            else -> null
        }
        return index?.takeIf { it in options.indices }
    }

    /** The strings of a JSON array, skipping anything that is not one. */
    fun strings(array: JSONArray?): List<String> =
        if (array == null) emptyList() else (0 until array.length()).mapNotNull { array.opt(it) as? String }
}
