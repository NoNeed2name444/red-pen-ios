package com.stethoscore.app

import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.net.URI
import java.net.URLDecoder

// Where a link from outside the app asks it to go (iOS Shared/Platform/AppLink.swift).
// The widgets' taps are the first links Android answers: the due queue, the exam
// plan and one set. The parsing is plain JVM, so it is tested without a device
// (AppLinkTest); AppLinks hands a parsed link to the app on screen.

sealed interface AppLink {
    /** Every card due today, across the library. */
    data object ReviewDue : AppLink

    /** One set, opened from the library; [id] in lower case. */
    data class OpenSet(val id: String) : AppLink

    /** The exam plan (the countdown widget's tap). */
    data object ExamPlan : AppLink

    /** The link that leads here, in iOS's form (AppLink.url). */
    val url: String
        get() = when (this) {
            ReviewDue -> "redpen://due"
            is OpenSet -> "redpen://set/$id"
            ExamPlan -> "redpen://exam"
        }

    companion object {
        /** The schemes the app answers to, as on iOS: `redpen` from the first build, `stethoscore` the name people see. */
        val schemes: Set<String> = setOf("redpen", "stethoscore")

        /** Hosts that belong to something else and are never routed (iOS's sign-in return). */
        val reserved: Set<String> = setOf("auth")

        private val uuid = Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

        /**
         * The link's destination, or null when it is not one the app routes
         * (AppLink.parse, AppLink.swift:39-70). The hosts and paths are iOS's
         * for these three; iOS's quiz, search, new and note links are not
         * routed on Android yet and give null.
         */
        fun parse(text: String): AppLink? {
            val uri = runCatching { URI(text.trim()) }.getOrNull() ?: return null
            val scheme = uri.scheme?.lowercase() ?: return null
            if (scheme !in schemes || uri.isOpaque) return null
            val host = (uri.host ?: uri.rawAuthority?.substringAfterLast('@')?.substringBefore(':') ?: "").lowercase()
            if (host in reserved) return null
            val parts = (uri.path ?: "").split('/').filter { it.isNotEmpty() }
            val items = query(uri.rawQuery)
            fun value(name: String): String? = items.firstOrNull { it.first == name }?.second?.trim()
            return when (host) {
                "due", "review" -> ReviewDue
                "set", "open" -> {
                    val raw = parts.firstOrNull() ?: value("id") ?: ""
                    if (uuid.matches(raw)) OpenSet(raw.lowercase()) else null
                }
                "exam", "countdown" -> ExamPlan
                else -> null
            }
        }

        /** The link a VIEW intent carries, or null for any other intent. */
        fun from(intent: Intent?): AppLink? {
            if (intent?.action != Intent.ACTION_VIEW) return null
            return intent.dataString?.let(::parse)
        }

        /** Whether [intent] opens one of the app's own schemes: a link, never a file to import. */
        fun isLink(intent: Intent?): Boolean =
            intent?.action == Intent.ACTION_VIEW && intent.data?.scheme?.lowercase() in schemes

        /** The screen a cold start opens on for [link] (StethoscoreApp's initialScreen); the rest go through [AppLinks]. */
        fun initialScreen(link: AppLink?): String = if (link == ReviewDue) "due" else "home"

        /** Query items as URLComponents reads them: percent escapes decoded, a "+" kept as itself. */
        private fun query(raw: String?): List<Pair<String, String?>> {
            if (raw.isNullOrEmpty()) return emptyList()
            fun decode(s: String) = runCatching { URLDecoder.decode(s.replace("+", "%2B"), "UTF-8") }.getOrDefault(s)
            return raw.split('&').filter { it.isNotEmpty() }.map { item ->
                val at = item.indexOf('=')
                if (at < 0) decode(item) to null else decode(item.substring(0, at)) to decode(item.substring(at + 1))
            }
        }
    }
}

/**
 * The link waiting for the app on screen (iOS AppRouter.pending): MainActivity
 * puts one here from a new intent, and StethoscoreApp takes it and goes there.
 */
object AppLinks {
    var pending: AppLink? by mutableStateOf(null)
}
