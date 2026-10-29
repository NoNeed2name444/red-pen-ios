package com.stethoscore.app.audio

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import com.stethoscore.app.network.BackendClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.util.Base64

/**
 * Transcribing a lecture with Gemini through the worker (T0146 item 6), the
 * route iOS takes (ios/RedPen/Shared/CloudTranscriber.swift): the recording
 * cut into ten-minute pieces at the same marks (CloudTranscript.chunkStarts),
 * each POSTed to `/transcribe/chunk` as `{"audio": <base64>, "prompt": ...}`
 * with the owner key as the bearer, and the answers turned into timed lines
 * the same way. The Google key never reaches the phone.
 *
 * Only the owner's personal build has a key ([com.stethoscore.app.BuildConfig.OWNER_KEY]);
 * a public build's is empty and keeps today's "not set up" path. Nothing is
 * uploaded unless the student chose to transcribe.
 *
 * Android does not move a cut to the quietest moment before it (iOS reads
 * the levels there with AVAssetReader); it keeps the exact mark, which is
 * iOS's own choice where the audio there cannot be read. The pieces are
 * copied from the recording's AAC without re-encoding.
 */
class CloudTranscriber(
    private val baseUrl: String,
    ownerKey: String,
    private val transport: BackendClient.Transport = BackendClient.HttpTransport,
    private val cutter: ChunkCutter = MediaChunkCutter,
    private val pause: suspend (Long) -> Unit = { delay(it) },
) {
    /** As the worker requires: at least 32 characters (LLMService). */
    private val key: String? = ownerKey.takeIf { it.length >= 32 }

    val isSetUp: Boolean get() = key != null

    /** Cuts a recording into the pieces sent. */
    interface ChunkCutter {
        fun duration(file: File): Double
        fun cut(file: File, start: Double, length: Double, out: File)
    }

    class Failure(message: String) : IOException(message)

    /** The whole recording as timed lines; throws (and the importer falls back to the phone) when it cannot. */
    suspend fun transcribe(file: File, language: LectureLanguage, vocabulary: List<String> = emptyList()): List<LectureTranscriber.Line> {
        val bearer = key ?: throw LectureImporterUnavailable(LectureTranscriber.Failure.cloudNotSetUp)
        val duration = withContext(Dispatchers.IO) { cutter.duration(file) }
        if (!duration.isFinite() || duration <= 0) throw Failure("That file has no audio in it.")
        val starts = CloudTranscript.chunkStarts(duration)
        val prompt = CloudTranscript.prompt(vocabulary, language)
        val folder = File(file.parentFile, ".transcribe-${System.nanoTime()}").also { it.mkdirs() }
        try {
            val lines = ArrayList<LectureTranscriber.Line>()
            for ((i, start) in starts.withIndex()) {
                val end = if (i + 1 < starts.size) starts[i + 1] else duration
                val piece = File(folder, "$i.m4a")
                val audio = withContext(Dispatchers.IO) {
                    cutter.cut(file, start, end - start, piece)
                    piece.readBytes()
                }
                val answer = ask(audio, prompt, bearer)
                lines += CloudTranscript.lines(answer.phrases, start, end - start, answer.model)
            }
            return lines
        } finally {
            folder.deleteRecursively()
        }
    }

    data class Answer(val phrases: List<CloudTranscript.Phrase>, val trimmed: Boolean = false, val model: String? = null)

    /** One chunk: one more try after a server hiccup; anything the server says in words is passed on. */
    suspend fun ask(audio: ByteArray, prompt: String, bearer: String): Answer {
        var last = "The transcriber's answer couldn't be read."
        for (attempt in 0 until 2) {
            val body = JSONObject().put("audio", Base64.getEncoder().encodeToString(audio)).put("prompt", prompt)
            val reply = withContext(Dispatchers.IO) {
                try {
                    transport.send("POST", BackendClient.validateBaseUrl(baseUrl) + "/transcribe/chunk",
                        body.toString().toByteArray(Charsets.UTF_8), bearer, 300_000)
                } catch (e: IOException) { throw Failure("The server could not be reached.") }
            }
            val obj = runCatching { JSONObject(reply.body) }.getOrNull()
            val message = obj?.optString("message")?.takeIf { obj.has("message") && it.isNotBlank() }
            when (val step = CloudTranscript.step(reply.status, message, attempt)) {
                is CloudTranscript.Step.Read -> {
                    val text = obj?.optString("text").orEmpty()
                    val model = obj?.optString("model")?.takeIf { obj.has("model") && it.isNotBlank() }
                    CloudTranscript.phrases(text)?.let {
                        val (kept, removed) = CloudTranscript.cutLoops(it)
                        return Answer(kept, removed >= CloudTranscript.LOOP_WORTH_MENTIONING, model)
                    }
                    CloudTranscript.salvage(text)?.let {
                        val (kept, removed) = CloudTranscript.cutLoops(it)
                        if (kept.isNotEmpty() && (removed > 0 || attempt == 1)) return Answer(kept, true, model)
                    }
                    last = "The transcriber's answer couldn't be read."
                }
                is CloudTranscript.Step.Stop -> throw Failure(step.why)
                is CloudTranscript.Step.Retry -> { last = step.why; if (step.pauseSeconds > 0) pause((step.pauseSeconds * 1000).toLong()) }
            }
        }
        throw Failure(last)
    }

    companion object {
        /** The app's: the worker in BuildConfig and the owner key, empty in every public build. */
        fun forApp(): CloudTranscriber = CloudTranscriber(com.stethoscore.app.BuildConfig.WORKER_URL, com.stethoscore.app.BuildConfig.OWNER_KEY)
    }
}

/** The importer's "not set up" (LectureImporter.TranscriberUnavailable), without the UI package. */
class LectureImporterUnavailable(message: String) : Exception(message)

/** Copies a stretch of an AAC recording into its own .m4a, sample by sample, without re-encoding. */
object MediaChunkCutter : CloudTranscriber.ChunkCutter {
    override fun duration(file: File): Double {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.absolutePath)
            val track = audioTrack(extractor) ?: return 0.0
            val format = extractor.getTrackFormat(track)
            return if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) / 1_000_000.0 else 0.0
        } finally { extractor.release() }
    }

    override fun cut(file: File, start: Double, length: Double, out: File) {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            extractor.setDataSource(file.absolutePath)
            val track = audioTrack(extractor) ?: throw CloudTranscriber.Failure("That file has no audio in it.")
            val format = extractor.getTrackFormat(track)
            if (format.getString(MediaFormat.KEY_MIME) != MediaFormat.MIMETYPE_AUDIO_AAC)
                throw CloudTranscriber.Failure("Only AAC recordings can be sent from this phone.")
            extractor.selectTrack(track)
            val from = (start * 1_000_000).toLong()
            val until = ((start + length) * 1_000_000).toLong()
            extractor.seekTo(from, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            out.delete()
            val made = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = made
            val outTrack = made.addTrack(format)
            made.start()
            val buffer = ByteBuffer.allocate(256 * 1024)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val at = extractor.sampleTime
                if (at >= until) break
                if (at >= from) {
                    info.set(0, size, at - from, if ((extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                    made.writeSampleData(outTrack, buffer, info)
                }
                extractor.advance()
            }
            made.stop()
        } finally {
            runCatching { muxer?.release() }
            extractor.release()
        }
    }

    private fun audioTrack(extractor: MediaExtractor): Int? =
        (0 until extractor.trackCount).firstOrNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
}

/**
 * Everything about Gemini transcription that is a decision rather than a
 * network call (ios/RedPen/Shared/CloudTranscript.swift and NetworkFaults
 * TranscribeStep), ported for the Android cloud path: where the recording
 * is cut, what the model is told, how its answer is read and becomes timed
 * lines.
 */
object CloudTranscript {
    data class Phrase(val start: Double, val end: Double, val text: String)

    const val CHUNK_SECONDS = 600.0
    const val LOOP_REPEATS = 4
    const val LOOP_LONGEST_RUN = 6
    const val LOOP_WORTH_MENTIONING = 20

    /** Every ten minutes; a last sliver under 20 s is folded into the chunk before it. */
    fun chunkStarts(duration: Double): List<Double> {
        if (duration <= 0) return emptyList()
        val starts = ArrayList<Double>()
        var at = 0.0
        while (at < duration) { starts.add(at); at += CHUNK_SECONDS }
        if (starts.size > 1 && duration - starts.last() < 20) starts.removeAt(starts.size - 1)
        return starts
    }

    fun prompt(vocabulary: List<String>, language: LectureLanguage = LectureLanguage.mixed): String {
        val rules = ArrayList<String>()
        if (language == LectureLanguage.mixed) rules += listOf(
            "The lecturer speaks Egyptian Arabic mixed with English medical terms.",
            "- Write the Arabic in Arabic script exactly as spoken, in Egyptian dialect. Do not convert it to Modern Standard Arabic and do not translate it.",
            "- Write every English word in English letters, with correct medical spelling, even inside an Arabic sentence.",
        ) else rules += listOf(
            "The lecturer speaks English.",
            "- Write exactly what was said, in English. Do not translate anything; a few words in another language are written as spoken.",
            "- Write every medical term, drug, investigation and abbreviation with its correct English spelling.",
        )
        rules += listOf(
            "- Do not summarise, correct the lecturer, or add anything that was not said. Leave out only \"um\"/\"eh\" fillers.",
            "- If a stretch is silent or impossible to hear, skip it rather than guessing.",
        )
        if (language == LectureLanguage.mixed)
            rules += "- An English word said with an Egyptian accent is still written in English letters (wrong: كلاود ستوريدج, right: cloud storage)."
        rules += listOf(
            "- Keep repetitions, false starts, students' questions and answers, interruptions and side comments.",
            "- Transcribe from the first second to the last. Keep going to the end of the recording; do not stop early.",
            "- The recording is the only source of the text. Never complete speech from memory or from published material, even when it sounds like something well known.",
            "- This recording is supplied for transcription only and may contain sensitive medical teaching, such as drugs or poisons. Relay what was said; do not give advice.",
        )
        var text = "Transcribe this medical lecture recording word for word.\n\n" + rules.joinToString("\n") + "\n\n" +
            "Split the speech into short phrases at natural pauses, at most 14 words each.\n" +
            "For each phrase give its start and end time in seconds from the beginning of this audio."
        if (vocabulary.isNotEmpty()) text += "\n\nTerms from this lecture's slides, spelled as they should be written: " + vocabulary.joinToString(", ") + "."
        return text
    }

    private fun decode(body: String): List<Phrase>? = try {
        val array = JSONArray(body)
        (0 until array.length()).map {
            val o = array.getJSONObject(it)
            if (!o.has("start") || !o.has("end") || !o.has("text")) return null
            Phrase(o.getDouble("start"), o.getDouble("end"), o.getString("text"))
        }
    } catch (_: Exception) { null }

    /** The phrases in Gemini's reply, or null when it is not the JSON asked for. */
    fun phrases(reply: String): List<Phrase>? {
        var body = reply.trim()
        if (body.startsWith("```")) {
            body = body.split("\n").drop(1).joinToString("\n")
            val fence = body.lastIndexOf("```")
            if (fence >= 0) body = body.substring(0, fence)
        }
        return decode(body)?.filter { it.text.isNotBlank() }
    }

    /** The complete phrases at the start of a reply cut off part way, or null. */
    fun salvage(reply: String): List<Phrase>? {
        var body = reply.trim()
        if (body.startsWith("```")) body = body.split("\n").drop(1).joinToString("\n")
        if (!body.startsWith("[")) return null
        var end = body.length
        repeat(64) {
            val close = body.lastIndexOf('}', end - 1)
            if (close < 0) return null
            decode(body.substring(0, close + 1) + "]")?.let { found ->
                val kept = found.filter { it.text.isNotBlank() }
                return kept.ifEmpty { null }
            }
            end = close
        }
        return null
    }

    private val loop = Regex("(\\b(?:\\S+\\s+){1,$LOOP_LONGEST_RUN}?)(?:\\1){${LOOP_REPEATS - 1},}")

    fun cutRepeats(text: String): String {
        val padded = "$text "
        val cut = loop.replace(padded, "$1")
        return if (cut == padded) text else cut.trim(' ')
    }

    /** The phrases with runaway repetition taken out, and how many words that removed. */
    fun cutLoops(phrases: List<Phrase>): Pair<List<Phrase>, Int> {
        fun words(t: String) = t.split(Regex("\\s+")).count { it.isNotEmpty() }
        val cleaned = phrases.map { it.copy(text = cutRepeats(it.text)) }
        val keys = cleaned.map { p -> p.text.lowercase().split(Regex("[\\s\\p{Punct}]+")).filter { it.isNotEmpty() }.joinToString(" ") }
        val kept = ArrayList<Phrase>()
        var i = 0
        while (i < cleaned.size) {
            var skipTo: Int? = null
            for (period in 1..LOOP_LONGEST_RUN) {
                if (i + period * LOOP_REPEATS > cleaned.size) continue
                val block = keys.subList(i, i + period)
                if (block.none { it.isNotEmpty() }) continue
                var times = 1
                while (i + (times + 1) * period <= keys.size && keys.subList(i + times * period, i + (times + 1) * period) == block) times++
                if (times >= LOOP_REPEATS) { kept += cleaned.subList(i, i + period); skipTo = i + times * period; break }
            }
            if (skipTo != null) i = skipTo else { kept += cleaned[i]; i++ }
        }
        return kept to (phrases.sumOf { words(it.text) } - kept.sumOf { words(it.text) })
    }

    /** Phrases as timed lines on the recording's own clock. */
    fun lines(phrases: List<Phrase>, offset: Double, length: Double, model: String? = null): List<LectureTranscriber.Line> {
        if (phrases.isEmpty() || length <= 0) return emptyList()
        val times = if (trustworthy(phrases, length)) clamped(phrases, length) else spread(phrases, length)
        return phrases.zip(times).map { (phrase, span) ->
            val text = phrase.text.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
            LectureTranscriber.Line(text, offset + span.first, offset + span.second, share(text, offset + span.first, offset + span.second), model)
        }
    }

    fun trustworthy(phrases: List<Phrase>, length: Double): Boolean {
        if (phrases.size <= 1) return phrases.firstOrNull()?.let { it.end > it.start } ?: false
        val inside = phrases.count { it.start >= 0 && it.end <= length + 5 && it.end >= it.start }
        val forward = (1 until phrases.size).count { phrases[it].start >= phrases[it - 1].start }
        val lastEnd = phrases.maxOf { it.end }
        return inside >= phrases.size * 0.9 && forward >= (phrases.size - 1) * 0.9 && lastEnd > 0.5 && phrases.map { it.start }.toSet().size > 1
    }

    private fun clamped(phrases: List<Phrase>, length: Double): List<Pair<Double, Double>> {
        var floor = 0.0
        return phrases.map { p ->
            val start = minOf(maxOf(p.start, floor), length)
            val end = minOf(maxOf(p.end, start + 0.3), length)
            floor = start
            start to maxOf(end, start)
        }
    }

    private fun spread(phrases: List<Phrase>, length: Double): List<Pair<Double, Double>> {
        val weights = phrases.map { maxOf(1, it.text.length).toDouble() }
        val total = weights.sum()
        var at = 0.0
        return weights.map { w -> val span = length * w / total; (at to at + span).also { at += span } }
    }

    private fun share(text: String, start: Double, end: Double): List<LectureTranscriber.SpokenWord> {
        val words = text.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.isEmpty()) return emptyList()
        val weights = words.map { it.length + 1.0 }
        val total = weights.sum()
        val span = maxOf(0.0, end - start)
        var at = start
        return words.zip(weights).map { (w, weight) -> val d = span * weight / total; LectureTranscriber.SpokenWord(w, at, d).also { at += d } }
    }

    /** "ar" when most of the letters in a line are Arabic. */
    fun language(text: String): String {
        var arabic = 0; var latin = 0
        text.codePoints().forEach { c ->
            when (c) {
                in 0x0600..0x06FF, in 0x0750..0x077F, in 0xFB50..0xFDFF, in 0xFE70..0xFEFF -> arabic++
                in 0x41..0x5A, in 0x61..0x7A -> latin++
            }
        }
        return if (arabic >= latin && arabic > 0) "ar" else "en"
    }

    /** What to do with the worker's answer (iOS TranscribeStep). */
    sealed class Step {
        object Read : Step()
        data class Retry(val why: String, val pauseSeconds: Double) : Step()
        data class Stop(val why: String) : Step()
    }

    fun step(code: Int, message: String?, attempt: Int): Step = when (code) {
        200 -> Step.Read
        401 -> Step.Stop("Please sign in again to use cloud transcription.")
        402 -> Step.Stop("Cloud transcription is part of Pro.")
        429 -> Step.Stop(message ?: "Cloud transcription is busy. Try again later, or transcribe on this phone.")
        404, 410, 503 -> Step.Stop("Cloud transcription isn't set up yet.")
        in 500..599 -> Step.Retry(message ?: "The server couldn't transcribe that ($code).", if (attempt == 0) 3.0 else 0.0)
        else -> Step.Stop(message ?: "The server couldn't transcribe that ($code).")
    }
}
