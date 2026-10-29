package com.stethoscore.app.audio

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File

/**
 * Records a lecture (T0146 item 3; iOS Shared/Recording/LectureRecorder.swift).
 *
 * MediaRecorder writes AAC in ADTS at 64 kbps, mono, 44.1 kHz straight to
 * `lecture-<yyyyMMdd-HHmm>.aac`, with pause and resume (API 24+). ADTS frames
 * stand alone, so a recording cut off by the app being killed still plays up
 * to its last whole frame (RecorderRecovery), where an .m4a would be
 * unreadable without Stop writing its index. It runs
 * inside [RecordingService], a foreground service of type microphone, so it
 * keeps going in the background and with the screen off; the service is only
 * started while the app is in front (Android 14's while-in-use rule).
 *
 * One recorder for the process ([shared]): the screen, the service and the
 * notification's actions all move the same one. Every move goes to the
 * shared file (RecorderShelf). The machine that touches the microphone is
 * passed in, so the service's tests run without one.
 */
class LectureRecorder(
    /** Where recordings are written: noBackupFilesDir/recordings. */
    private val folder: File,
    /** RecorderShelf's file, in filesDir. */
    private val shelf: File,
    private val machine: () -> AudioMachine,
    private val clock: () -> Double = { System.currentTimeMillis() / 1000.0 },
    private val zone: java.time.ZoneId = java.time.ZoneId.systemDefault(),
) {
    /** What touches the microphone. */
    interface AudioMachine {
        fun begin(out: File)
        fun pause()
        fun resume()
        /** Stops and finishes the file. */
        fun end()
        /** 0...32767 since the last call. */
        fun amplitude(): Int
        fun release()
        /**
         * Tells the recorder when the microphone fails ([onError]: the
         * recording ends) or is taken for another app ([onTaken]: it pauses,
         * so it never records silence). Called once, after [begin].
         */
        fun watch(onError: (String) -> Unit, onTaken: () -> Unit) {}
    }

    var state: RecorderState = RecorderState.Idle
        private set
    /** The file being recorded, then the finished one until it is handed on. */
    var file: File? = null
        private set
    /** When this recording began, for its file name and default title. */
    var startedEpoch: Long = 0
        private set
    /** Set when the recorder stopped by itself (low disk). */
    var note: String? = null
    /** A recording the app was killed during, made ready by [recoverLeftover]: keep or discard it. */
    var recovered: File? = null
    /** The file found when this recorder was made at launch, not yet trimmed. */
    @Volatile internal var leftover: File? = null

    /**
     * Trims the recording found at launch to its whole frames, off the main
     * thread, and puts it in [recovered]; once per process.
     */
    suspend fun recoverLeftover(io: kotlin.coroutines.CoroutineContext = kotlinx.coroutines.Dispatchers.IO): File? {
        val found = leftover ?: return recovered
        leftover = null
        recovered = kotlinx.coroutines.withContext(io) { RecorderRecovery.ready(found) }
        return recovered
    }

    private var running: AudioMachine? = null
    private val listeners = mutableListOf<(RecorderState) -> Unit>()

    fun listen(listener: (RecorderState) -> Unit): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }

    private fun move(next: RecorderState?) {
        if (next == null) return
        state = next
        RecorderShelf.write(next, shelf)
        listeners.toList().forEach { it(next) }
    }

    fun elapsed(): Double = state.elapsed(clock())

    val moment: RecorderNames.Moment get() = RecorderNames.Moment.of(startedEpoch, zone)

    fun start(): Boolean {
        // the microphone is opened only for a move that is allowed from here
        val next = state.start(clock()) ?: return false
        return try {
            folder.mkdirs()
            startedEpoch = clock().toLong()
            val out = File(folder, RecorderNames.fileName(moment, EXTENSION))
            val made = machine()
            made.begin(out)
            running = made
            file = out
            note = null
            made.watch(onError = { lost(it) }, onTaken = { interrupt(RecorderWords.micTaken) })
            move(next)
            true
        } catch (e: Exception) {
            running?.release(); running = null
            move(state.fail(e.message ?: "The microphone could not be opened.") ?: RecorderState.Failed(e.message ?: ""))
            false
        }
    }

    fun pause() {
        if (!state.isRecording) return
        runCatching { running?.pause() }
        move(state.pause(clock()))
    }

    fun resume() {
        if (!state.isPaused) return
        try { running?.resume() } catch (e: Exception) { move(state.fail(e.message ?: "The microphone could not be opened again.")); return }
        move(state.resume(clock()))
    }

    /** A call or another app took the microphone: paused, and it stays paused. */
    fun interrupt(reason: String = RecorderWords.callPaused) {
        if (!state.isRecording) return
        runCatching { running?.pause() }
        move(state.interrupt(clock(), reason))
    }

    /**
     * The microphone failed: the recorder is let go and the recording ends
     * as Failed. What was written up to then is whole frames, so it is
     * trimmed and handed on to be saved; nothing whole is dropped.
     */
    fun lost(reason: String) {
        if (!state.isActive) return
        val made = running
        running = null
        runCatching { made?.release() }
        val kept = file?.let { Adts.trim(it) }
        file = kept
        move(state.fail(reason))
        if (kept != null) finished(kept)
    }

    /**
     * Stops and finishes the file; returns it, or null when nothing was
     * recording. A stop that fails leaves the file's whole frames; with none,
     * the broken file is dropped and the recording fails.
     */
    fun stop(): File? {
        if (!state.isActive) return null
        move(state.stop(clock()))
        val made = running
        running = null
        val ended = runCatching { made?.end() }.isSuccess
        runCatching { made?.release() }
        if (!ended) {
            file = file?.let { Adts.trim(it) }
            if (file == null) move(state.fail(RecorderWords.nothingRecorded))
        }
        return file
    }

    /** The finished file went to the lecture flow. */
    fun handedOn() {
        file = null
        move(state.finish())
    }

    fun clearFailure() { if (state is RecorderState.Failed) move(state.finish()) }

    fun level(): Double = if (state.isRecording) RecorderMeter.level(runCatching { running?.amplitude() ?: 0 }.getOrDefault(0)) else 0.0

    /** True when the disk is too low to go on (checked by the service). */
    fun diskTooLow(): Boolean = RecorderMeter.diskTooLow(folder.usableSpace.takeIf { it > 0 } ?: Long.MAX_VALUE)

    /** MediaRecorder, AAC in ADTS, 64 kbps mono 44.1 kHz. */
    class MediaMachine(private val context: Context) : AudioMachine {
        private var recorder: MediaRecorder? = null
        private var silenced: Any? = null

        override fun begin(out: File) {
            val made = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
            made.setAudioSource(MediaRecorder.AudioSource.MIC)
            made.setOutputFormat(MediaRecorder.OutputFormat.AAC_ADTS)
            made.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            made.setAudioEncodingBitRate(64_000)
            made.setAudioSamplingRate(44_100)
            made.setAudioChannels(1)
            made.setOutputFile(out.absolutePath)
            made.prepare()
            made.start()
            recorder = made
        }

        override fun pause() { recorder?.pause() }
        override fun resume() { recorder?.resume() }
        override fun end() { recorder?.stop() }
        override fun amplitude(): Int = recorder?.maxAmplitude ?: 0
        override fun release() {
            val made = recorder ?: return
            if (Build.VERSION.SDK_INT >= 29) (silenced as? android.media.AudioManager.AudioRecordingCallback)?.let { made.unregisterAudioRecordingCallback(it) }
            silenced = null
            made.release()
            recorder = null
        }

        override fun watch(onError: (String) -> Unit, onTaken: () -> Unit) {
            val made = recorder ?: return
            val main = android.os.Handler(android.os.Looper.getMainLooper())
            made.setOnErrorListener { _, _, _ -> main.post { onError(RecorderWords.micLost) } }
            // Android 10+ silences a recording when another app takes the microphone: pause rather than record silence
            if (Build.VERSION.SDK_INT >= 29) {
                val callback = object : android.media.AudioManager.AudioRecordingCallback() {
                    override fun onRecordingConfigChanged(configs: MutableList<android.media.AudioRecordingConfiguration>?) {
                        if (recorder?.activeRecordingConfiguration?.isClientSilenced == true) main.post { onTaken() }
                    }
                }
                made.registerAudioRecordingCallback(context.mainExecutor, callback)
                silenced = callback
            }
        }
    }

    companion object {
        /** The live file's extension: AAC in ADTS. */
        const val EXTENSION = "aac"

        @Volatile private var instance: LectureRecorder? = null

        /** Tests replace the microphone. */
        @Volatile var machineFactory: ((Context) -> AudioMachine)? = null

        /**
         * Where a stopped recording goes: the screen showing "Save the
         * recording to" sets it; with no screen (Stop from the notification)
         * the file waits in [pending] for the screen to open.
         */
        @Volatile var handOff: ((File) -> Unit)? = null
        @Volatile var pending: File? = null

        fun shared(context: Context): LectureRecorder = instance ?: synchronized(this) {
            instance ?: run {
                val app = context.applicationContext
                val folder = File(app.noBackupFilesDir, "recordings")
                val shelf = RecorderShelf.file(app.filesDir)
                LectureRecorder(folder, shelf, { (machineFactory ?: { MediaMachine(it) })(app) }).also {
                    // made once per process, at its first use after launch: nothing is recording yet.
                    // The shared file is read and reset here; the trim waits for recoverLeftover, off the main thread.
                    it.leftover = RecorderRecovery.found(shelf, folder)
                    instance = it
                }
            }
        }

        /** A stopped recording, to whoever takes it. */
        fun finished(file: File) {
            val taker = handOff
            if (taker != null) taker(file) else pending = file
        }

        /** Tests only: a fresh recorder. */
        internal fun reset() { instance = null; pending = null; handOff = null }
    }
}
