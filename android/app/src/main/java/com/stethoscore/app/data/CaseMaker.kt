package com.stethoscore.app.data

import com.stethoscore.app.llm.ChatTurn
import com.stethoscore.app.llm.CloudJobs
import com.stethoscore.app.llm.LLMBackend
import com.stethoscore.app.llm.LLMError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

/**
 * Writing cases with whichever writer this device has. One case per call,
 * each from the next window of the lecture, each through the structure checks
 * and the accuracy rules before it is kept (CaseChecks). Port of the
 * Foundation part of iOS Features/Cases/CaseMaker.swift.
 *
 * Android's one writer is the writer route (Stethoscore
 * Cloud, [BackendWriter]); with Stethoscore Cloud the server writes every case
 * as one job, as iOS's cloudWrite does. Apple's on-device model and the
 * downloaded Gemma are Apple-only or not on Android, so with nothing chosen
 * [writer] finds none and the screens say so ([noWriter]).
 */
object CaseMaker {

    /** One call to a writer: the window of lecture and the brief in, the cases it wrote out. */
    fun interface Writer {
        suspend fun one(window: String, lecture: String, subject: String, brief: CaseWriting.Brief): List<CaseFile>

        /** Characters of lecture one call can read. */
        val sourceChars: Int get() = CaseWriting.onDeviceSourceChars

        /** The model behind this writer, when it is one (iOS Writer.backend). */
        val backend: LLMBackend? get() = null
    }

    /** A chosen backend as a case writer: one patient a call, as iOS's one() asks a backend. */
    class BackendWriter(override val backend: LLMBackend) : Writer {
        override val sourceChars: Int get() =
            if (backend.isOnDevice) CaseWriting.onDeviceSourceChars else minOf(backend.promptBudgetChars, 12_000)

        override suspend fun one(window: String, lecture: String, subject: String, brief: CaseWriting.Brief): List<CaseFile> {
            val rules = CaseWriting.instructions(window, subject, brief, json = true)
            val reply = backend.complete(listOf(ChatTurn.system(rules), ChatTurn.user(CaseWriting.requestJSON)), 3_500, 0.7)
            return CaseWriting.parse(reply, lecture)
        }
    }

    /** A failure the writer will not get past by asking again (a missing key, a refused request). */
    class Refused(message: String) : Exception(message)

    sealed class Trouble(message: String) : Exception(message) {
        class Unavailable(why: String) : Trouble(why)
        class NothingUsable(val dropped: Int) : Trouble(
            if (dropped > 0) "The cases written from this lecture did not pass the structure and accuracy checks. A lecture about a condition - its presentation, tests and treatment - works best."
            else "Nothing in that lecture could be written up as a patient. A lecture about a condition - its presentation, tests and treatment - works best."
        )
    }

    data class Made(
        val cases: List<CaseFile>,
        /** Written but refused by the checks. */
        val dropped: Int,
    )

    /** The writer to use here: the writer route's backend, or null while it is blocked. */
    fun writer(backend: LLMBackend?): Writer? = backend?.let { BackendWriter(it) }

    /**
     * Why there is no writer, in the student's words, as iOS says it: Stethoscore
     * Cloud's blocker (part of Pro, or sign in), else that it cannot be reached.
     * Nothing is written on the phone (the owner, 23 Oct: "Lock it").
     */
    fun noWriter(blocker: String? = null): String =
        blocker ?: "Stethoscore Cloud can't be reached right now."

    /** The lecture as the writers read it, each page marked with its number so the teaching can cite it. */
    fun sourceText(pages: List<Pair<Int, String>>): String =
        pages.filter { it.second.trim().isNotEmpty() }.joinToString("\n\n") { "[Page ${it.first}]\n${it.second}" }

    suspend fun write(
        count: Int, source: String, lecture: String, subject: String,
        brief: CaseWriting.Brief = CaseWriting.Brief(), using: Writer,
        onProgress: (Int, Int) -> Unit = { _, _ -> },
        store: CloudJobs.PendingStore = CloudJobs.MemoryStore(),
        pause: suspend (Long) -> Unit = { delay(it) },
    ): Made {
        val wanted = count.coerceIn(1, CaseWriting.maxCases)
        val cloud = using.backend?.let { CloudJobs.endpoint(it) }
        if (cloud != null) return cloudWrite(wanted, source, lecture, subject, brief, using.backend!!, cloud, store, pause, onProgress)
        val windows = TextSlicing.windows(source, using.sourceChars)
        val kept = mutableListOf<CaseFile>()
        var dropped = 0
        var failures = 0
        var round = 0
        while (kept.size < wanted && failures < 3 && round < wanted * 3) {
            coroutineContext.ensureActive()
            onProgress(kept.size, wanted)
            var asked = brief
            if (asked.setting == null && asked.diagnosis == null) asked = asked.copy(setting = CaseWriting.setting(round))
            if (asked.diagnosis == null) asked = asked.copy(avoid = brief.avoid + kept.map { it.diagnosis.name })
            val window = if (windows.isEmpty()) "" else TextSlicing.window(windows, round)
            round += 1
            try {
                val written = using.one(window, lecture, subject, asked)
                val screened = CaseChecks.screen(written)
                dropped += screened.dropped.size
                var added = 0
                for (file in screened.kept) {
                    if (kept.size >= wanted) break
                    // one patient per diagnosis in a run, unless asked for one
                    if (brief.diagnosis == null && kept.any { CaseNames.same(it.diagnosis.name, file.diagnosis.name) }) continue
                    kept += file
                    added += 1
                }
                failures = if (added == 0) failures + 1 else 0
            } catch (e: CancellationException) {
                throw e
            } catch (e: Refused) {
                throw e
            } catch (e: Trouble.Unavailable) {
                throw e
            } catch (e: LLMError) {
                // a missing key or a refused request will not fix itself on retry
                if (e is LLMError.EmptyReply) failures += 1 else throw e
            } catch (e: Exception) {
                failures += 1
            }
        }
        onProgress(kept.size, wanted)
        if (kept.isEmpty()) throw Trouble.NothingUsable(dropped)
        return Made(kept, dropped)
    }

    /** Stethoscore Cloud writes every case in one job, a prompt per case (iOS cloudWrite). */
    private suspend fun cloudWrite(
        wanted: Int, source: String, lecture: String, subject: String, brief: CaseWriting.Brief,
        backend: LLMBackend, at: com.stethoscore.app.llm.CloudEndpoint,
        store: CloudJobs.PendingStore, pause: suspend (Long) -> Unit, onProgress: (Int, Int) -> Unit,
    ): Made {
        val windows = TextSlicing.windows(source, minOf(backend.promptBudgetChars, 12_000)).take(60)
        val sources = windows.ifEmpty { listOf("") }
        val steps = (0 until wanted).map { i ->
            var asked = brief
            if (asked.setting == null && asked.diagnosis == null) asked = asked.copy(setting = CaseWriting.setting(i))
            CloudJobs.Step(CaseWriting.instructions("{{SOURCE}}", subject, asked, json = true),
                CaseWriting.requestJSON, i % sources.size, 3_500, 0.7)
        }
        val spec = CloudJobs.Spec("Writing $wanted case" + if (wanted == 1) "" else "s", "each", "pages", wanted, sources, steps)
        val replies = CloudJobs.run(spec, at, store, pause, onProgress)
        val screened = CaseChecks.screen(replies.flatMap { CaseWriting.parse(it, lecture) })
        if (screened.kept.isEmpty()) throw Trouble.NothingUsable(screened.dropped.size)
        return Made(screened.kept.take(wanted), screened.dropped.size)
    }
}

/** Cutting a lecture into windows a prompt can hold (the part of iOS's TextSlicing the case writer uses). */
object TextSlicing {

    /**
     * A source longer than one prompt can hold, as windows that each fit, cut
     * at a paragraph, line or sentence end where one is near, so every part of
     * a lecture is read by some call.
     */
    fun windows(text: String, maxChars: Int): List<String> {
        val limit = maxOf(500, maxChars)
        if (text.length <= limit) return listOf(text)
        val out = mutableListOf<String>()
        var rest = text
        while (rest.isNotEmpty()) {
            if (rest.length <= limit) { out += rest; break }
            val head = rest.substring(0, limit)
            // a paragraph end in the last third of the window, else a line or
            // sentence end in its last fifth, else a hard cut
            var cut = limit
            for ((mark, share) in listOf("\n\n" to 2, "\n" to 4, ". " to 4)) {
                val floor = limit * share / (share + 1)
                val at = head.lastIndexOf(mark)
                if (at >= 0 && at >= floor) { cut = at + mark.length; break }
            }
            out += rest.substring(0, cut).trim()
            rest = rest.substring(cut)
        }
        return out.filter { it.isNotEmpty() }
    }

    /** The window a call reads: each call the next one, round and round. */
    fun window(windows: List<String>, round: Int): String {
        if (windows.isEmpty()) return ""
        return windows[((round % windows.size) + windows.size) % windows.size]
    }

    /**
     * The words of [text] longer than three letters, lower-cased (iOS
     * TextSlicing.words: runs of letters, marks and numbers, as Foundation's
     * alphanumerics; a word's length counts its characters, not its marks).
     */
    fun words(text: String): Set<String> {
        val out = HashSet<String>()
        val word = StringBuilder()
        var length = 0
        fun end() {
            if (length > 3) out += word.toString()
            word.setLength(0)
            length = 0
        }
        val lower = text.lowercase()
        var i = 0
        while (i < lower.length) {
            val cp = lower.codePointAt(i)
            i += Character.charCount(cp)
            when (Character.getType(cp).toByte()) {
                Character.UPPERCASE_LETTER, Character.LOWERCASE_LETTER, Character.TITLECASE_LETTER, Character.MODIFIER_LETTER,
                Character.OTHER_LETTER, Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> {
                    word.appendCodePoint(cp); length += 1
                }
                Character.NON_SPACING_MARK, Character.ENCLOSING_MARK, Character.COMBINING_SPACING_MARK -> word.appendCodePoint(cp)
                else -> end()
            }
        }
        end()
        return out
    }

    /** The first [limit] characters of [text], never cutting a surrogate pair in two. */
    private fun head(text: String, limit: Int): String {
        if (text.length <= limit) return text
        val cut = if (limit > 0 && Character.isHighSurrogate(text[limit - 1])) limit - 1 else limit
        return text.substring(0, cut)
    }

    /**
     * The paragraphs of a long [source] that share the most words with [text]
     * (iOS TextSlicing.nearest), back in reading order, up to [limit]
     * characters; the source whole when it fits, its start when nothing shares
     * a word.
     */
    fun nearest(source: String, text: String, limit: Int): String {
        if (source.length <= limit) return source
        val wanted = words(text)
        // A paragraph too long to fit is taken line by line instead: a Word
        // file's text is one page with a line per paragraph and no blank
        // lines, so as one paragraph it could never be chosen at all.
        val paragraphs = mutableListOf<String>()
        for (paragraph in source.split("\n\n")) {
            if (paragraph.length > limit) paragraphs += paragraph.split("\n") else paragraphs += paragraph
        }
        val ranked = paragraphs.mapIndexed { i, p -> i to words(p).count { it in wanted } }.sortedByDescending { it.second }
        val chosen = mutableListOf<Int>()
        var size = 0
        for ((index, score) in ranked) {
            if (score <= 0) continue
            // the blank line each one is joined with counts too
            val length = paragraphs[index].length + (if (chosen.isEmpty()) 0 else 2)
            if (size + length > limit) continue
            chosen += index
            size += length
        }
        if (chosen.isEmpty()) return head(source, limit)
        return chosen.sorted().joinToString("\n\n") { paragraphs[it] }
    }

    /**
     * The pages (heading, text) that share the most words with [text], best
     * first, up to [limit] characters; null when no page shares a word with it
     * (iOS TextSlicing.nearestPages).
     *
     * A page bigger than the room left is cut down to its own nearest
     * paragraphs rather than ending the search: a Word file is kept as ONE
     * page, so stopping at the first page that does not fit meant a Word
     * lecture was never used at all, and the check fell back to "no source".
     */
    fun nearestPages(pages: List<Pair<String, String>>, text: String, limit: Int): String? {
        val wanted = words(text)
        val ranked = pages.map { (heading, body) -> Triple(heading, body, words(body).count { it in wanted }) }.sortedByDescending { it.third }
        // less than this left is not worth a page
        val smallest = minOf(200, maxOf(1, limit / 4))
        val out = StringBuilder()
        for ((heading, body, score) in ranked) {
            if (score <= 0) continue
            val room = limit - out.length - heading.length - 2
            if (room < smallest) break
            val chosen = if (body.length <= room) body else nearest(body, text, room)
            out.append(heading).append(chosen).append("\n\n")
        }
        return if (out.isEmpty()) null else out.toString()
    }

    /**
     * Paragraph-aligned slices of roughly equal length (iOS TextSlicing.slice),
     * for a textbook's pages and a long lecture's card windows. More pieces
     * than [count] are merged with their neighbours rather than the tail
     * dropped, so the last chapter is never silently lost.
     */
    fun slice(text: String, count: Int, maxChars: Int): List<String> {
        val paragraphs = text.split("\n\n").filter { it.isNotBlank() }
        if (paragraphs.isEmpty()) return emptyList()
        val target = minOf(maxChars, maxOf(800, text.length / maxOf(1, count)))
        val slices = mutableListOf<String>()
        var current = ""
        for (p in paragraphs) {
            if (current.isNotEmpty() && current.length + p.length > target) {
                slices += current
                current = ""
            }
            current += (if (current.isEmpty()) "" else "\n\n") + p.take(maxChars)
        }
        if (current.isNotEmpty()) slices += current
        val wanted = maxOf(1, count)
        if (slices.size <= wanted) return slices
        return (0 until wanted).map { bucket ->
            val from = bucket * slices.size / wanted
            val to = (bucket + 1) * slices.size / wanted
            slices.subList(from, to).joinToString("\n\n").take(maxChars)
        }
    }
}
