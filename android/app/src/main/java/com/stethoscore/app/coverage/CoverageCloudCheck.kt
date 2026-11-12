package com.stethoscore.app.coverage

import com.stethoscore.app.data.StudySet
import com.stethoscore.app.llm.CloudJobs
import com.stethoscore.app.llm.LLMText
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.reading.BookPages
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.text.BreakIterator
import java.util.Locale

// A port of ios/RedPen/Shared/Coverage/CoverageCloudCheck.swift: the AI check.
// Each area's subtopics, with a compact digest of the library, go to
// Stethoscore Cloud with a request for strict JSON back; the reply is read
// into one verdict per subtopic. Pure Kotlin over org.json, so the prompt, the
// reading of a reply and the kept checks are tested on the JVM; the bearer, the
// client and the spend meter are handed in by whoever runs it
// (ui/coverage/CoverageChecker.kt).
//
// It calls the worker's chat route directly rather than through LLMBackend
// because the reply says which model actually answered (the worker falls back
// when the preferred one is not available), and the screen shows that.

/** What the AI check said about one subtopic (iOS CoverageVerdict). */
data class CoverageVerdict(val status: Status, val evidence: String = "", val suggestion: String = "") {
    @Suppress("EnumEntryName")
    enum class Status(val rawValue: String) {
        covered("covered"), thin("thin"), missing("missing");

        /** The same scale as the keyword engine's, so the two can be compared. */
        val coverage: CoverageStatus get() = when (this) {
            covered -> CoverageStatus.covered
            thin -> CoverageStatus.thin
            missing -> CoverageStatus.notCovered
        }

        companion object {
            /**
             * A status as a model writes it: any case, spaced or not, and the
             * engine's own "not covered". Null for anything else, rather than a
             * guess that could call a gap covered (iOS Status.read, :11-22).
             */
            fun read(text: String): Status? {
                val t = CoverageCloudCheck.trimEdges(text.lowercase(Locale.ROOT).replace("_", " ").replace("-", " ")) {
                    CoverageCloudCheck.isSpaceOrPunctuation(it)
                }
                return when (t) {
                    "covered", "well covered", "fully covered" -> covered
                    "thin", "partial", "partly covered", "partially covered" -> thin
                    "missing", "not covered", "notcovered", "uncovered", "absent", "none" -> missing
                    else -> null
                }
            }

            fun from(raw: String?): Status? = entries.firstOrNull { it.rawValue == raw }
        }
    }
}

/**
 * One AI check of one exam's blueprint against the library, kept so it is not
 * paid for again every time the screen opens (iOS CoverageCheck).
 */
data class CoverageCheck(
    /** The exam it was run for (ExamTrack's raw value). */
    val track: String,
    /** When it was made, in milliseconds since the epoch. */
    val date: Long,
    /** The models that answered, most areas first. Usually one. */
    val sources: List<String>,
    /** By SubtopicCoverage.id ("area/subtopic"). */
    val verdicts: Map<String, CoverageVerdict>,
    /** Areas whose request failed, so the screen can say the check is partial. */
    val failedAreas: List<String> = emptyList(),
    /** A ready-made check shipped with the personal build, not a real one. */
    val isExample: Boolean = false,
) {
    val source: String get() = sources.firstOrNull() ?: ""

    /** Whether the model asked for is the one that answered. */
    val byPreferredModel: Boolean get() = sources.isNotEmpty() && sources.all { it == CoverageCloudCheck.preferredModel }
}

object CoverageCloudCheck {
    const val preferredModel = "gemini-3.1-pro-preview"

    /** Most characters one request may carry. */
    const val requestLimit = 30_000

    /** The reply's room and the model's temperature (iOS send, :164-165). */
    const val maxTokens = 4_000
    const val temperature = 0.2

    /** The friendly name of a model id, for the screen. */
    fun displayName(model: String): String = when (model) {
        preferredModel -> "Gemini 3.1 Pro"
        "" -> "the cloud model"
        else -> model
    }

    // The prompt

    /**
     * The request for one area: its subtopics, what the keyword engine found,
     * the library's shape, and the matching items themselves.
     */
    fun prompt(area: AreaCoverage, exam: ExamTrack, library: List<StudySet>): String {
        val lines = ArrayList<String>()
        lines.add("You are checking how well a medical student's revision library covers the ${exam.title} syllabus, area \"${area.area.name}\".")
        lines.add("For each subtopic below, judge from the digest whether the library covers it: \"covered\" (enough material, including questions or cards, to revise it for the exam), \"thin\" (mentioned, but too little or reading only), or \"missing\" (nothing on it).")
        lines.add("Judge meaning, not keywords: a question on warfarin reversal covers anticoagulation even if the word is not used, and a passing mention is not coverage.")
        lines.add("Reply with ONLY this JSON and nothing else:")
        lines.add("{\"subtopics\":[{\"id\":\"s1\",\"status\":\"covered\"|\"thin\"|\"missing\",\"evidence\":\"<under 15 words: what in the library shows it>\",\"suggestion\":\"<under 20 words: what to add>\"}]}")
        lines.add("")
        lines.add("SUBTOPICS (id: name - what a keyword search found)")
        for ((i, sub) in area.subtopics.withIndex()) {
            var found = "nothing"
            if (sub.evidence > 0) {
                found = "${sub.evidence} items, ${sub.practice} of them questions/cards"
            }
            sub.accuracy?.let { accuracy ->
                val percent = Math.round(accuracy * 100)
                found += ", $percent% of ${sub.answered} answers right"
            }
            lines.add("s${i + 1}: ${sub.subtopic.name} - $found")
        }

        val digest = ArrayList<String>()
        digest.add("")
        digest.add("ITEMS THAT MATCHED (tagged with the subtopic that found them)")
        var shown = 0
        val seen = HashSet<String>()
        for ((i, sub) in area.subtopics.withIndex()) {
            for (sample in sub.samples.take(4)) {
                if (shown < 40 && seen.add(sample)) {
                    digest.add("[s${i + 1}] $sample")
                    shown += 1
                }
            }
        }
        if (shown == 0) digest.add("(none)")

        digest.add("")
        digest.add("THE LIBRARY'S SETS (name - subject - kind, size)")
        for (set in library.take(80)) {
            digest.add("${set.name} - ${set.subject} - ${set.kind.label}, ${set.itemCount} ${set.itemNoun}s")
        }

        digest.add("")
        digest.add("LECTURE AND TEXTBOOK PAGES (first line of each)")
        val headings = ArrayList<String>()
        val sourcesSeen = HashSet<String>()
        for (set in library) {
            for (source in set.sources) {
                if (!sourcesSeen.add(source.id)) continue
                val heads = source.pages.map { heading(it.text) }.filter { it.isNotEmpty() }
                if (heads.isNotEmpty()) headings.add(source.name + ": " + heads.joinToString(" | "))
            }
            if (set.bookMarkdown.isNotEmpty()) {
                headings.add(set.name + ": " + BookPages.split(set.bookMarkdown).joinToString(" | ") { it.title })
            }
        }
        digest.addAll(if (headings.isEmpty()) listOf("(none)") else headings)

        val head = lines.joinToString("\n")
        val body = digest.joinToString("\n")
        return head + characterPrefix(body, maxOf(0, requestLimit - characterCount(head)))
    }

    /** A source page's first line with anything on it, for the digest (iOS SourceDoc.Page.heading). */
    internal fun heading(text: String): String {
        for (line in text.split(newlines)) {
            val trimmed = trimEdges(line) { it == 9 || Character.getType(it).toByte() == Character.SPACE_SEPARATOR }
            if (trimmed.isNotEmpty()) return characterPrefix(trimmed, 80)
        }
        return ""
    }

    private val newlines = Regex("[\\n\\r\\u000B\\u000C\\u0085\\u2028\\u2029]")

    // The request

    /** One reply: the text, and the model that wrote it. */
    data class Sent(val content: String, val source: String)

    /** A failure in the student's words (iOS AuthAPI.Failure's errorDescription). */
    class Failure(message: String) : Exception(message)

    /** The body of one request, as iOS's send writes it (:161-167). */
    fun body(prompt: String): JSONObject = JSONObject()
        .put("model", "cramdown-writer").put("prefer", preferredModel)
        .put("max_tokens", maxTokens).put("temperature", temperature)
        .put("messages", JSONArray().put(JSONObject().put("role", "user").put("content", prompt)))

    /**
     * Sends one prompt and returns the reply's text and the model that wrote it.
     * With the owner key, [meter] stops it at the cap and counts what it spends.
     */
    suspend fun send(client: BackendClient, prompt: String, meter: OwnerSpend? = null): Sent {
        meter?.ensureRoom()
        val reply = try {
            withContext(CloudJobs.io) { client.chat(body(prompt)) }
        } catch (e: BackendClient.BackendException) {
            throw failure(e)
        }
        meter?.record(reply.optJSONObject("usage"), prompt.length, maxTokens)
        val content = reply.optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message")?.opt("content") as? String
        if (content.isNullOrEmpty()) throw Failure("The cloud check sent back nothing.")
        val source = (reply.opt("source") as? String) ?: (reply.opt("model") as? String) ?: ""
        return Sent(content, source)
    }

    /**
     * A refusal read as every other call to the worker reads it (iOS
     * AuthAPI.failure, with the cloud check's two fallbacks, :179-181).
     */
    fun failure(e: BackendClient.BackendException): Failure {
        val said = (e.response?.opt("message") as? String) ?: (e.response?.opt("error") as? String)
        val words = when {
            // a 200 whose reply holds nothing readable: the reply has no content (iOS :186-188)
            e.status in 200..299 -> "The cloud check sent back nothing."
            e.status == 0 || e.failure == BackendClient.Failure.OFFLINE -> "No connection. Signing in needs one — studying does not."
            else -> when (e.failure) {
                BackendClient.Failure.SIGNED_OUT -> "Please sign in again."
                BackendClient.Failure.NEEDS_PRO -> (e.response?.opt("message") as? String) ?: "The cloud check is part of Pro."
                BackendClient.Failure.NEEDS_CONSENT -> "Cloud AI needs your permission first."
                BackendClient.Failure.RATE_LIMITED -> "Too many requests just now. Try again in a moment."
                BackendClient.Failure.NOT_CONFIGURED -> "Sign-in isn't set up in this build yet."
                BackendClient.Failure.GONE -> "That has ended or is no longer available."
                // a refusal with words of its own, a server error or a missing route that says something
                else -> said ?: "The cloud check did not answer."
            }
        }
        return Failure(words)
    }

    // The reply

    /**
     * The verdicts in a reply, keyed the way the screen looks them up.
     * Tolerates a reply wrapped in a code fence or with words around it;
     * subtopics it does not recognise, or leaves out, are skipped. As on iOS, a
     * list with anything in it that is not an object is no list at all.
     */
    fun parse(content: String, area: AreaCoverage): Map<String, CoverageVerdict> {
        val json = LLMText.jsonObject(content) ?: return emptyMap()
        val reply = try { JSONObject(json) } catch (_: JSONException) { return emptyMap() }
        val list = reply.opt("subtopics") as? JSONArray ?: return emptyMap()
        val entries = ArrayList<JSONObject>()
        for (i in 0 until list.length()) entries.add(list.opt(i) as? JSONObject ?: return emptyMap())
        val out = LinkedHashMap<String, CoverageVerdict>()
        for (entry in entries) {
            val id = entry.opt("id") as? String ?: continue
            val number = integer(id.lowercase(Locale.ROOT).replace("s", "")) ?: continue
            val sub = area.subtopics.getOrNull(number - 1) ?: continue
            val raw = entry.opt("status") as? String ?: continue
            val status = CoverageVerdict.Status.read(raw) ?: continue
            out[sub.id] = CoverageVerdict(status, entry.opt("evidence") as? String ?: "", entry.opt("suggestion") as? String ?: "")
        }
        return out
    }

    /** Swift's Int(String): optional sign, ASCII digits, nothing else. */
    private fun integer(text: String): Int? =
        if (Regex("[+-]?[0-9]+").matches(text)) text.toIntOrNull() else null

    // Kept checks

    private fun file(folder: File, track: ExamTrack, exam: String?): File =
        File(folder, "check-${CoverageScope.key(track, exam)}.json")

    /** The last check run for an exam, if any. */
    fun load(folder: File, track: ExamTrack, exam: String? = null): CoverageCheck? = try {
        val f = file(folder, track, exam)
        if (f.isFile) fromJson(JSONObject(f.readText(Charsets.UTF_8))) else null
    } catch (_: Exception) { null }

    /** Keeps a real check; an example is never kept (iOS save, :240). */
    fun save(folder: File, check: CoverageCheck, track: ExamTrack, exam: String? = null) {
        if (check.isExample) return
        try {
            folder.mkdirs()
            val target = file(folder, track, exam)
            val temp = File(folder, target.name + ".tmp")
            temp.writeText(toJson(check).toString(), Charsets.UTF_8)
            if (!temp.renameTo(target)) { target.delete(); temp.renameTo(target) }
        } catch (_: Exception) { /* a check that cannot be kept is still shown this time */ }
    }

    fun toJson(check: CoverageCheck): JSONObject {
        val verdicts = JSONObject()
        for ((id, v) in check.verdicts) {
            verdicts.put(id, JSONObject().put("status", v.status.rawValue).put("evidence", v.evidence).put("suggestion", v.suggestion))
        }
        return JSONObject().put("track", check.track).put("date", check.date).put("sources", JSONArray(check.sources))
            .put("verdicts", verdicts).put("failedAreas", JSONArray(check.failedAreas)).put("isExample", check.isExample)
    }

    fun fromJson(json: JSONObject): CoverageCheck {
        val verdicts = LinkedHashMap<String, CoverageVerdict>()
        val kept = json.getJSONObject("verdicts")
        for (id in kept.keys()) {
            val v = kept.getJSONObject(id)
            val status = CoverageVerdict.Status.from(v.optString("status")) ?: continue
            verdicts[id] = CoverageVerdict(status, v.optString("evidence"), v.optString("suggestion"))
        }
        return CoverageCheck(json.getString("track"), json.getLong("date"), LLMText.strings(json.optJSONArray("sources")), verdicts,
            LLMText.strings(json.optJSONArray("failedAreas")), json.optBoolean("isExample"))
    }

    // Swift's String, character by character

    /** Foundation's whitespacesAndNewlines plus punctuationCharacters (iOS Status.read, :15). */
    internal fun isSpaceOrPunctuation(cp: Int): Boolean = cp in 9..13 || cp == 0x85 || Character.isSpaceChar(cp) ||
        when (Character.getType(cp).toByte()) {
            Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION, Character.END_PUNCTUATION,
            Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION, Character.OTHER_PUNCTUATION -> true
            else -> false
        }

    /** trimmingCharacters(in:): the scalars at both ends that [trim] says to drop. */
    internal fun trimEdges(text: String, trim: (Int) -> Boolean): String {
        val scalars = text.codePoints().toArray()
        var start = 0
        var end = scalars.size
        while (start < end && trim(scalars[start])) start++
        while (end > start && trim(scalars[end - 1])) end--
        return String(scalars, start, end - start)
    }

    /** Swift's String.count: user-perceived characters, not UTF-16 units. */
    internal fun characterCount(text: String): Int {
        val breaks = BreakIterator.getCharacterInstance(Locale.ROOT)
        breaks.setText(text)
        var count = 0
        while (breaks.next() != BreakIterator.DONE) count++
        return count
    }

    /** Swift's String.prefix(n) in characters. */
    internal fun characterPrefix(text: String, n: Int): String {
        if (n <= 0) return ""
        // a character is at least one UTF-16 unit, so a text this short fits whole
        if (text.length <= n) return text
        val breaks = BreakIterator.getCharacterInstance(Locale.ROOT)
        breaks.setText(text)
        var end = 0
        var taken = 0
        while (taken < n) {
            val next = breaks.next()
            if (next == BreakIterator.DONE) return text
            end = next
            taken++
        }
        return text.substring(0, end)
    }
}
