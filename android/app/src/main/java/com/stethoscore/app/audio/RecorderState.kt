package com.stethoscore.app.audio

import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.ZoneId

/**
 * The lecture recorder as a state machine (T0146): what it is doing, and
 * which moves from there are allowed - ios/RedPen/Shared/Recording/RecorderState.swift,
 * case for case. Each move returns the next state, or null where it is not
 * allowed. Times are seconds since 1970, so the shared file reads the same
 * on both platforms.
 */
sealed class RecorderState {
    object Idle : RecorderState()
    /** The permission sheet or the system prompt is up. */
    object Asking : RecorderState()
    /** Recording since [startedAt], with [banked] seconds recorded before it. */
    data class Recording(val startedAt: Double, val banked: Double) : RecorderState()
    /** Paused with [banked] seconds; [reason] when something else paused it (a call). */
    data class Paused(val banked: Double, val reason: String?) : RecorderState()
    /** Stopped: the file is being finished and handed on. */
    object Saving : RecorderState()
    data class Failed(val reason: String) : RecorderState()

    fun ask(): RecorderState? = if (this == Idle || this is Failed) Asking else null

    /** The permission was refused or the sheet closed. */
    fun cancel(): RecorderState? = if (this == Asking) Idle else null

    fun start(now: Double): RecorderState? = if (this == Idle || this == Asking || this is Failed) Recording(now, 0.0) else null

    fun pause(now: Double): RecorderState? = if (this is Recording) Paused(elapsed(now), null) else null

    /** The student's Resume, after their own Pause or after a call. */
    fun resume(now: Double): RecorderState? = if (this is Paused) Recording(now, banked) else null

    fun stop(@Suppress("UNUSED_PARAMETER") now: Double): RecorderState? = if (this is Recording || this is Paused) Saving else null

    /** Something else took the microphone (a call): paused, saying why; it does not resume on its own. */
    fun interrupt(now: Double, reason: String): RecorderState? = if (this is Recording) Paused(elapsed(now), reason) else null

    /** Only from a pause an interruption made: a pause the student chose is never undone by a call ending. */
    fun resumeAfterInterruption(now: Double): RecorderState? =
        if (this is Paused && reason != null) Recording(now, banked) else null

    fun fail(reason: String): RecorderState? = if (this == Idle || this is Failed) null else Failed(reason)

    /** The file was handed on, or a failure was read: back to the start. */
    fun finish(): RecorderState? = if (this == Saving || this is Failed) Idle else null

    /** Seconds recorded: running while recording, frozen while paused. */
    fun elapsed(now: Double): Double = when (this) {
        is Recording -> banked + maxOf(0.0, now - startedAt)
        is Paused -> banked
        else -> 0.0
    }

    val isRecording: Boolean get() = this is Recording
    val isPaused: Boolean get() = this is Paused
    val isActive: Boolean get() = isRecording || isPaused

    val phase: String get() = when (this) {
        Idle -> "idle"
        Asking -> "asking"
        is Recording -> "recording"
        is Paused -> "paused"
        Saving -> "saving"
        is Failed -> "failed"
    }

    override fun toString(): String = phase
}

/** The recording's file name and the set's default title. */
object RecorderNames {
    data class Moment(val year: Int, val month: Int, val day: Int, val hour: Int, val minute: Int) {
        companion object {
            fun of(epochSeconds: Long, zone: ZoneId = ZoneId.systemDefault()): Moment {
                val t = Instant.ofEpochSecond(epochSeconds).atZone(zone)
                return Moment(t.year, t.monthValue, t.dayOfMonth, t.hour, t.minute)
            }
        }
    }

    /** The moment a recording began, read back from its file name (a recovered one has nothing else). */
    fun moment(fileName: String): Moment? {
        val m = Regex("^lecture-(\\d{4})(\\d{2})(\\d{2})-(\\d{2})(\\d{2})\\.").find(fileName) ?: return null
        val (y, mo, d, h, mi) = m.destructured
        return Moment(y.toInt(), mo.toInt(), d.toInt(), h.toInt(), mi.toInt())
    }

    /** `lecture-20261023-1405.m4a`: Western digits always, so it sorts. */
    fun fileName(m: Moment, ext: String = "m4a"): String =
        "lecture-" + pad(m.year, 4) + pad(m.month, 2) + pad(m.day, 2) + "-" + pad(m.hour, 2) + pad(m.minute, 2) + "." + ext

    val monthsEnglish = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    val monthsArabic = listOf("يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر")

    /** "Lecture, 23 Oct 14:05" / "محاضرة، ٢٣ أكتوبر ١٤:٠٥": written out, so every platform says exactly the same. */
    fun defaultTitle(m: Moment, language: String): String {
        val month = m.month.coerceIn(1, 12) - 1
        val clock = pad(m.hour, 2) + ":" + pad(m.minute, 2)
        return if (language.lowercase().startsWith("ar")) "محاضرة، " + arabicDigits(m.day.toString()) + " " + monthsArabic[month] + " " + arabicDigits(clock)
        else "Lecture, ${m.day} ${monthsEnglish[month]} $clock"
    }

    fun arabicDigits(text: String): String = text.map { c -> if (c in '0'..'9') "٠١٢٣٤٥٦٧٨٩"[c - '0'] else c }.joinToString("")

    /** The elapsed clock: "12:03", "1:02:03". */
    fun clock(seconds: Double): String {
        val total = if (seconds.isFinite() && seconds > 0) seconds.toInt() else 0
        val h = total / 3600; val m = (total % 3600) / 60; val s = total % 60
        return if (h > 0) "$h:" + pad(m, 2) + ":" + pad(s, 2) else "$m:" + pad(s, 2)
    }

    private fun pad(value: Int, width: Int): String = value.toString().padStart(width, '0')
}

object RecorderMeter {
    /** MediaRecorder's max amplitude (0...32767) as 0...1 for the bar, on the same -50 dB scale as iOS. */
    fun level(amplitude: Int): Double {
        if (amplitude <= 0) return 0.0
        return level(20 * Math.log10(amplitude / 32767.0))
    }

    /** A power in dBFS as 0...1: -50 dB and below is silence, 0 dB is full. */
    fun level(decibels: Double): Double = if (!decibels.isFinite()) 0.0 else ((decibels + 50) / 50).coerceIn(0.0, 1.0)

    const val LOW_DISK_BYTES: Long = 200L * 1024 * 1024
    fun diskTooLow(freeBytes: Long): Boolean = freeBytes < LOW_DISK_BYTES
}

/**
 * The recorder's state in filesDir/recorder-state.json (iOS: the App Group's
 * recorder-state.json), for tiles, widgets and the watch. The phase and its
 * clock only, never a lecture or set name. A missing, garbled or newer file
 * reads as idle.
 */
object RecorderShelf {
    const val FILE_NAME = "recorder-state.json"
    const val CURRENT_VERSION = 1

    fun file(filesDir: File): File = File(filesDir, FILE_NAME)

    fun encode(state: RecorderState): String {
        val o = JSONObject().put("v", CURRENT_VERSION).put("phase", state.phase)
        when (state) {
            is RecorderState.Recording -> o.put("startedAt", state.startedAt).put("banked", state.banked)
            is RecorderState.Paused -> { o.put("banked", state.banked); state.reason?.let { o.put("reason", it) } }
            is RecorderState.Failed -> o.put("reason", state.reason)
            else -> Unit
        }
        return o.toString()
    }

    fun decode(text: String): RecorderState {
        val o = try { JSONObject(text) } catch (_: Exception) { return RecorderState.Idle }
        val version = o.optInt("v", Int.MAX_VALUE)
        if (!o.has("v") || version > CURRENT_VERSION) return RecorderState.Idle
        val banked = if (o.has("banked")) o.optDouble("banked") else null
        val reason = if (o.has("reason") && !o.isNull("reason")) o.optString("reason") else null
        return when (o.optString("phase")) {
            "asking" -> RecorderState.Asking
            "recording" -> if (o.has("startedAt") && banked != null) RecorderState.Recording(o.optDouble("startedAt"), banked) else RecorderState.Idle
            "paused" -> if (banked != null) RecorderState.Paused(banked, reason) else RecorderState.Idle
            "saving" -> RecorderState.Saving
            "failed" -> RecorderState.Failed(reason ?: "")
            else -> RecorderState.Idle
        }
    }

    fun read(file: File): RecorderState = try { if (file.exists()) decode(file.readText()) else RecorderState.Idle } catch (_: Exception) { RecorderState.Idle }

    /** Written beside and moved over, so a reader never sees half a file. */
    fun write(state: RecorderState, file: File): Boolean = try {
        val next = File(file.parentFile, ".${file.name}.new")
        next.writeText(encode(state))
        next.renameTo(file) || run { file.writeText(encode(state)); next.delete(); true }
    } catch (_: Exception) { false }
}

enum class MicPermission { undetermined, granted, denied }

/** The system's microphone permission; the app's is in RecordLectureScreen, the tests pass a fake. */
interface PermissionGate {
    val status: MicPermission
    /** Shows the system prompt. Called only by [RecordFlow.continueFromSheet]. */
    suspend fun request(): Boolean
}

/**
 * What a Record tap leads to. The permission is never asked at launch or in
 * onboarding: only a Record tap reaches the sheet, and only Continue on the
 * sheet reaches the system prompt.
 */
class RecordFlow(private val gate: PermissionGate) {
    enum class Step { sheet, record, settingsRow }

    fun tapRecord(): Step = when (gate.status) {
        MicPermission.undetermined -> Step.sheet
        MicPermission.granted -> Step.record
        MicPermission.denied -> Step.settingsRow
    }

    /** Continue on the sheet: the one place the system prompt is asked for. */
    suspend fun continueFromSheet(): Step {
        if (gate.status != MicPermission.undetermined) return tapRecord()
        return if (gate.request()) Step.record else Step.settingsRow
    }
}

/** The recorder's words (iOS RecorderWords); the screen reads them through res/values strings. */
object RecorderWords {
    const val sheetTitle = "Record your lecture"
    const val sheetBody = "Stethoscore uses the microphone to record the lecture. The recording stays on this phone until you choose to transcribe it."
    const val sheetContinue = "Continue"
    const val micOff = "Microphone is off for Stethoscore"
    const val openSettings = "Open Settings"
    const val callPaused = "Paused for a call"
    /** The system silenced this recording for another app. */
    const val micTaken = "Paused while another app uses the microphone"
    /** Audio focus lost to another app, with no call. */
    const val focusLost = "Paused for another app"
    const val lowDisk = "Stopped because this phone is almost full."
    /** MediaRecorder reported an error: the recording ends, what was written is kept. */
    const val micLost = "The microphone stopped working."
    /** Stop found nothing whole to keep. */
    const val nothingRecorded = "Nothing was recorded."
    const val saveBody = "It stays on this phone until you choose to transcribe it."
    const val saveAgain = "Save the recording"
    const val transcribe = "Transcribe"
    const val recoverTitle = "Keep the unfinished recording?"
    const val recoverBody = "Stethoscore closed while recording. You can keep what it recorded up to then."
    const val keep = "Keep"
    const val discard = "Delete"
}

/**
 * The microphone permission as Android tells it (T0146 repair): granted, or
 * whether asking again shows the system prompt. A refusal is for good only
 * when the system said no and no longer offers a rationale right after it
 * ([refusedForGood], kept by the screen); one denial on Android 11+, a
 * one-time grant that has run out, or a permission revoked in Settings are
 * all askable again.
 */
object MicAsk {
    fun status(granted: Boolean, rationale: Boolean, refusedForGood: Boolean): MicPermission = when {
        granted -> MicPermission.granted
        rationale -> MicPermission.undetermined
        refusedForGood -> MicPermission.denied
        else -> MicPermission.undetermined
    }

    /** After the system prompt: no grant and no rationale left means it will not be shown again. */
    fun refusedForGood(granted: Boolean, rationaleAfter: Boolean): Boolean = !granted && !rationaleAfter

    /**
     * The kept "refused for good" as it should stand now: a grant or a
     * rationale clears it, so a permission granted later and then revoked
     * in Settings is asked for again, never sent to Settings.
     */
    fun stillRefused(granted: Boolean, rationale: Boolean, refusedForGood: Boolean): Boolean = refusedForGood && !granted && !rationale
}

/**
 * A stopped recording on its way to a set (T0146 repair; iOS RecordingSave).
 * Saving only saves: [save] copies the file in under the set on this phone
 * and sends nothing. Transcribing is its own action, on the saved file. A
 * cancelled choice keeps the file, so it can be saved again.
 */
data class RecordingSave(
    /** Stopped and not yet saved. */
    val file: File? = null,
    /** "Save the recording to" is showing. */
    val choosing: Boolean = false,
    /** The copy under the set, once saved. */
    val kept: File? = null,
    val setId: String? = null,
    /** The copy is being made: nothing else may start one. */
    val copying: Boolean = false,
) {
    fun offer(stopped: File) = RecordingSave(file = stopped, choosing = true)
    fun cancel() = copy(choosing = false)
    fun reopen() = if (file != null && !copying) copy(choosing = true) else this
    /** Cancelled: the Save the recording button. */
    val waiting: Boolean get() = file != null && !choosing
    /** The Save the recording button can be tapped: not while a copy is running. */
    val canSave: Boolean get() = waiting && !copying
    /** A set was chosen: the copy starts, or null while one is already running. */
    fun begin(): RecordingSave? = if (file == null || copying) null else copy(choosing = false, copying = true)

    /** [keep] copies the file in under [setId], or returns null (then it can be saved again). */
    inline fun save(setId: String, keep: (File, String) -> File?): RecordingSave {
        val stopped = file ?: return this
        val made = keep(stopped, setId) ?: return copy(choosing = false, copying = false)
        return RecordingSave(kept = made, setId = setId)
    }
}

/**
 * A recording cut off by the app being killed (T0146 repair; iOS
 * RecorderRecovery). At launch, with nothing recording in this process, a
 * shared file still saying recording, paused or saving means a recording was
 * left behind: the newest `lecture-*` file in the folder is offered to keep
 * or discard, and the shared file goes back to idle. The live file is AAC in
 * ADTS, frames that each stand alone, so a cut-off one is trimmed to its
 * last whole frame and plays.
 */
object RecorderRecovery {
    private val open = setOf("recording", "paused", "saving")
    private val live = setOf("aac", "caf")

    fun recover(shelf: File, folder: File): File? = found(shelf, folder)?.let(::ready)

    /** Reads the shared file and resets it to idle; the file left behind, untouched, or null. Small and quick. */
    fun found(shelf: File, folder: File): File? {
        val left = RecorderShelf.read(shelf)
        if (left == RecorderState.Idle) return null
        RecorderShelf.write(RecorderState.Idle, shelf)
        if (left.phase !in open) return null
        val name = leftover(folder.list()?.toList().orEmpty()) ?: return null
        return File(folder, name)
    }

    /** Makes a found file playable: ADTS trimmed to its whole frames; reads the whole file, so never on the main thread. */
    fun ready(file: File): File? = if (file.extension == "aac") Adts.trim(file) else file.takeIf { it.length() > 0 }

    /** The newest `lecture-…` stem, its live recording before a finished export of it. */
    fun leftover(names: List<String>): String? {
        val ours = names.filter { it.startsWith("lecture-") && it.contains('.') }
        val stem = ours.map { it.substringBeforeLast('.') }.maxOrNull() ?: return null
        val same = ours.filter { it.substringBeforeLast('.') == stem }
        return same.firstOrNull { it.substringAfterLast('.') in live } ?: same.first()
    }
}

/** AAC in ADTS frames: how much of a file is whole frames. */
object Adts {
    /** The length of the run of whole frames at the start of [bytes]. */
    fun wholeLength(bytes: ByteArray): Int {
        var at = 0
        while (at + 7 <= bytes.size) {
            val b0 = bytes[at].toInt() and 0xFF
            val b1 = bytes[at + 1].toInt() and 0xFF
            if (b0 != 0xFF || (b1 and 0xF6) != 0xF0) break
            val length = ((bytes[at + 3].toInt() and 0x03) shl 11) or ((bytes[at + 4].toInt() and 0xFF) shl 3) or
                ((bytes[at + 5].toInt() and 0xE0) ushr 5)
            if (length < 7 || at + length > bytes.size) break
            at += length
        }
        return at
    }

    /** Cuts [file] back to its whole frames; deletes it and returns null when there are none. */
    fun trim(file: File): File? = try {
        val whole = wholeLength(file.readBytes())
        if (whole == 0) { file.delete(); null }
        else {
            if (whole.toLong() != file.length()) java.io.RandomAccessFile(file, "rw").use { it.setLength(whole.toLong()) }
            file
        }
    } catch (_: Exception) { null }
}
