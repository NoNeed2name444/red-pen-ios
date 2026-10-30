package com.stethoscore.app.audio

import android.Manifest
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Looper
import android.telephony.TelephonyManager
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.ui.narrate.LectureImporter
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.File

// The recording service (T0146 A5): in the foreground with type microphone; a
// notification with a chronometer counting up, Pause/Resume and Stop, private,
// with a public version that names nothing; Stop hands the file on to the
// lecture flow (a LectureImporter with a fake transcriber). Repair 1: saving
// makes no upload call (R1); a cancelled save can be saved again (R2); a
// recording cut off by a kill is found at the next launch, trimmed to whole
// ADTS frames and offered (R3); calls on API 26-30 and 31+, focus loss, a
// silenced or failed microphone pause or fail it (R5); start opens no
// microphone for a refused move and a broken stop is dropped (R6).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RecordingServiceTest {
    @get:Rule val tmp = TemporaryFolder()

    private val app: Application get() = ApplicationProvider.getApplicationContext()

    /** Writes ADTS frames where MediaRecorder would, and nothing else. */
    private class FakeMachine : LectureRecorder.AudioMachine {
        var out: File? = null
        val moves = ArrayList<String>()
        var endFails = false
        var onError: ((String) -> Unit)? = null
        var onTaken: (() -> Unit)? = null
        override fun begin(out: File) { this.out = out; out.writeBytes(frame(20) + frame(30)); moves += "begin" }
        override fun pause() { moves += "pause" }
        override fun resume() { moves += "resume" }
        override fun end() { if (endFails) throw RuntimeException("stop failed"); out?.appendBytes(frame(25)); moves += "end" }
        override fun amplitude() = 0
        override fun release() { moves += "release" }
        override fun watch(onError: (String) -> Unit, onTaken: () -> Unit) { this.onError = onError; this.onTaken = onTaken }
    }

    private val machine = FakeMachine()

    @Before fun setUp() {
        LectureRecorder.reset()
        LectureRecorder.machineFactory = { machine }
        shadowOf(app).grantPermissions(Manifest.permission.RECORD_AUDIO, Manifest.permission.POST_NOTIFICATIONS)
    }

    @After fun tearDown() {
        LectureRecorder.reset()
        LectureRecorder.machineFactory = null
        RecordingService.sdk = { android.os.Build.VERSION.SDK_INT }
    }

    private fun started(): org.robolectric.android.controller.ServiceController<RecordingService> {
        val controller = Robolectric.buildService(RecordingService::class.java, RecordingService.intent(app, RecordingService.ACTION_START)).create()
        controller.startCommand(0, 1)
        return controller
    }

    private fun idleMain() = shadowOf(Looper.getMainLooper()).idle()

    private fun send(controller: org.robolectric.android.controller.ServiceController<RecordingService>, action: String) {
        controller.withIntent(RecordingService.intent(app, action)).startCommand(0, 1)
    }

    private fun titles(n: Notification) = n.actions.orEmpty().map { it.title.toString() }

    @Test fun recordsInTheForegroundAndHandsTheFileOn() = runBlocking {
        val handed = ArrayList<File>()
        LectureRecorder.handOff = { handed += it }
        val controller = Robolectric.buildService(RecordingService::class.java, RecordingService.intent(app, RecordingService.ACTION_START)).create()
        controller.startCommand(0, 1)
        val service = controller.get()
        val shadow = shadowOf(service)
        val recorder = LectureRecorder.shared(app)

        // MARK: in the foreground, of type microphone
        assertTrue("recording", recorder.state.isRecording)
        assertEquals("the microphone was opened once", listOf("begin"), machine.moves)
        assertEquals("in the foreground", RecordingService.NOTIFICATION_ID, shadow.lastForegroundNotificationId)
        assertEquals("of type microphone", ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE, service.foregroundServiceType)
        assertTrue("the file is named for when it began, AAC in ADTS", machine.out!!.name.matches(Regex("lecture-\\d{8}-\\d{4}\\.aac")))

        // MARK: the notification
        val n = shadow.lastForegroundNotification
        assertNotNull(n)
        assertEquals("on the recorder's channel", RecordingService.CHANNEL_ID, n.channelId)
        assertEquals("titled Recording", "Recording", n.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertTrue("with a chronometer", n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertFalse("counting up", n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN))
        assertTrue("from when it began", kotlin.math.abs(System.currentTimeMillis() - n.`when`) < 5_000)
        assertEquals("Pause and Stop", listOf("Pause", "Stop"), titles(n))
        assertTrue("ongoing", n.flags and Notification.FLAG_ONGOING_EVENT != 0)

        // MARK: nothing private on the lock screen
        assertEquals("private", Notification.VISIBILITY_PRIVATE, n.visibility)
        val public = n.publicVersion
        assertNotNull("with a public version", public)
        assertEquals("that says only Recording", "Recording", public!!.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertNull("and names nothing", public.extras.getCharSequence(Notification.EXTRA_TEXT))
        assertTrue("and has no buttons", public.actions.isNullOrEmpty())
        val named = n.extras.getCharSequence(Notification.EXTRA_TEXT).toString()
        assertTrue("the private one has the lecture's title", named.startsWith("Lecture, "))

        // MARK: Pause, then Resume
        send(controller, RecordingService.ACTION_PAUSE)
        assertTrue("paused", recorder.state.isPaused)
        val manager = shadowOf(app.getSystemService(NotificationManager::class.java))
        val paused = manager.getNotification(RecordingService.NOTIFICATION_ID)
        assertEquals("Resume and Stop", listOf("Resume", "Stop"), titles(paused))
        assertFalse("the clock is held", paused.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertTrue("and shows the time", paused.extras.getCharSequence(Notification.EXTRA_TITLE).toString().startsWith("Paused · "))
        assertEquals("still private", Notification.VISIBILITY_PRIVATE, paused.visibility)
        assertEquals("public still says only Recording", "Recording", paused.publicVersion!!.extras.getCharSequence(Notification.EXTRA_TITLE).toString())

        send(controller, RecordingService.ACTION_RESUME)
        assertTrue("recording again", recorder.state.isRecording)
        assertEquals("Pause and Stop again", listOf("Pause", "Stop"), titles(manager.getNotification(RecordingService.NOTIFICATION_ID)))
        assertEquals(listOf("begin", "pause", "resume"), machine.moves)

        // MARK: Stop hands the file on
        send(controller, RecordingService.ACTION_STOP)
        assertEquals("the file is finished and let go", listOf("begin", "pause", "resume", "end", "release"), machine.moves)
        assertTrue("out of the foreground", shadow.isForegroundStopped)
        assertTrue("and the service stops", shadow.isStoppedBySelf)
        assertEquals("handed on once", 1, handed.size)
        val file = handed.single()
        assertEquals("the recorded file", machine.out, file)
        assertTrue("three whole frames", (frame(20) + frame(30) + frame(25)).contentEquals(file.readBytes()))
        assertTrue("saving until the flow takes it", recorder.state is RecorderState.Saving)

        // MARK: saving only saves (R1): the copy is made, nothing is sent
        var uploads = 0
        val importer = LectureImporter(cloud = { f, _ ->
            uploads += 1
            assertEquals("the transcriber gets the kept copy", 75L, f.length())
            listOf(LectureTranscriber.Line("the nephron filters the blood", 0.0, 3.0, emptyList(), "fake"))
        })
        val set = "SET-1"
        val dir = LectureAudio.folder(tmp.newFolder("nobackup"))
        // R2: the choice is cancelled, the recording waits, then it is saved
        var save = RecordingSave().offer(file).cancel()
        assertTrue("cancelled: the recording waits to be saved", save.waiting && save.file == file && file.exists())
        save = save.reopen()
        assertTrue("Save the recording opens the choice again", save.choosing)
        save = save.save(set) { f, id -> importer.storeRecorded(f, id, dir) }
        recorder.handedOn()
        val kept = save.kept
        assertNotNull("kept under the set", kept)
        assertTrue("named for the set", kept!!.name.startsWith(set))
        assertFalse("the recorder's copy is removed", file.exists())
        assertNull("no trouble", importer.trouble)
        assertEquals("saving made no upload call", 0, uploads)
        assertNull("and no transcript", importer.produced)
        assertEquals("and the recorder is idle again", RecorderState.Idle, recorder.state)

        // MARK: Transcribe, its own action, sends it
        importer.transcribe(kept, LectureImporter.Engine.cloud, LectureLanguage.english) {}
        assertEquals("Transcribe sends it once", 1, uploads)
        assertEquals("the transcript is made", "the nephron filters the blood", importer.produced!!.single().text)
    }

    @Test fun aSaveThatFailsCanBeSavedAgain() = runBlocking {
        val file = tmp.newFile("lecture-20261023-1405.aac").apply { writeBytes(frame(20)) }
        val importer = LectureImporter(cloud = { _, _ -> error("no upload while saving") })
        var save = RecordingSave().offer(file)
        save = save.save("SET-2") { _, _ -> null }
        assertTrue("a failed copy keeps the file, waiting", save.waiting && save.file == file && save.kept == null)
        save = save.reopen().save("SET-2") { f, id -> importer.storeRecorded(f, id, LectureAudio.folder(tmp.newFolder("lectures"))) }
        assertNotNull("then it saves", save.kept)
        assertNull("nothing was sent", importer.trouble)
    }

    @Test fun aRefusedStartOpensNoMicrophone() {
        started()
        val recorder = LectureRecorder.shared(app)
        recorder.stop()
        assertTrue("saving", recorder.state is RecorderState.Saving)
        assertFalse("start is refused while saving", recorder.start())
        assertEquals("and the microphone was not opened again", 1, machine.moves.count { it == "begin" })
    }

    @Test fun aFailedStopKeepsWholeFramesAndDropsABrokenFile() {
        started()
        val recorder = LectureRecorder.shared(app)
        machine.endFails = true
        machine.out!!.appendBytes(frame(40).copyOf(12))
        val kept = recorder.stop()
        assertEquals("the half frame is cut off", 50L, kept!!.length())

        LectureRecorder.reset()
        LectureRecorder.machineFactory = { machine }
        started()
        machine.out!!.writeBytes(byteArrayOf(1, 2, 3))
        val out = machine.out!!
        val broken = LectureRecorder.shared(app).stop()
        assertNull("nothing whole: dropped", broken)
        assertFalse("the broken file is deleted", out.exists())
        assertEquals("and the recording failed, saying so", RecorderState.Failed(RecorderWords.nothingRecorded), LectureRecorder.shared(app).state)
    }

    @Test fun focusLossPausesAndACallSaysSo() {
        started()
        val recorder = LectureRecorder.shared(app)
        val focus = shadowOf(app.getSystemService(AudioManager::class.java)).lastAudioFocusRequest
        assertNotNull("audio focus is held while recording", focus)
        focus!!.listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        idleMain()
        assertEquals("another app took focus: paused for another app, not the microphone line", RecorderWords.focusLost, (recorder.state as RecorderState.Paused).reason)
        assertEquals("said in words of its own", com.stethoscore.app.R.string.recorder_focus_lost, RecordingService.pausedWord(RecorderWords.focusLost))
        assertTrue("the machine paused: no silence recorded", machine.moves.last() == "pause")

        recorder.resume()
        app.getSystemService(AudioManager::class.java).mode = AudioManager.MODE_IN_CALL
        idleMain()
        assertEquals("a call on Android 12+: paused for a call", RecorderWords.callPaused, (recorder.state as RecorderState.Paused).reason)
    }

    @Test fun aRefusedFocusRequestPausesAtOnce() {
        shadowOf(app.getSystemService(AudioManager::class.java)).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
        started()
        val recorder = LectureRecorder.shared(app)
        assertEquals("no focus: paused at once, saying why", RecorderWords.focusLost, (recorder.state as RecorderState.Paused).reason)
        assertEquals("and the machine paused: no silence recorded", "pause", machine.moves.last())
    }

    @Test fun aCallBeforeAndroid12PausesIt() {
        RecordingService.sdk = { 30 }
        started()
        val recorder = LectureRecorder.shared(app)
        @Suppress("DEPRECATION")
        shadowOf(app.getSystemService(TelephonyManager::class.java)).setCallState(TelephonyManager.CALL_STATE_RINGING)
        idleMain()
        assertEquals("ringing on API 26-30: paused for a call", RecorderWords.callPaused, (recorder.state as RecorderState.Paused).reason)
        assertEquals("and the machine paused", "pause", machine.moves.last())
    }

    @Test fun aSilencedOrFailedMicrophoneNeverRecordsSilence() {
        val handed = ArrayList<File>()
        LectureRecorder.handOff = { handed += it }
        val controller = started()
        val recorder = LectureRecorder.shared(app)
        machine.onTaken!!()
        assertEquals("silenced for another app: paused", RecorderWords.micTaken, (recorder.state as RecorderState.Paused).reason)
        recorder.resume()
        machine.out!!.appendBytes(frame(30).copyOf(9))
        machine.onError!!(RecorderWords.micLost)
        assertEquals("an error: failed, saying why", RecorderState.Failed(RecorderWords.micLost), recorder.state)
        assertEquals("the recorder is let go, never ended into silence", "release", machine.moves.last())
        assertEquals("what was written is handed on to save, whole frames only", 50L, handed.single().length())
        assertTrue("and the service stops", shadowOf(controller.get()).isStoppedBySelf)
    }

    @Test fun aRecordingCutOffByAKillIsOfferedAtTheNextLaunch() {
        val folder = File(app.noBackupFilesDir, "recordings").apply { mkdirs() }
        val shelf = RecorderShelf.file(app.filesDir)
        RecorderShelf.write(RecorderState.Recording(1792764300.0, 12.0), shelf)
        val partial = File(folder, "lecture-20261023-1405.aac").apply { writeBytes(frame(20) + frame(30) + frame(40).copyOf(17)) }
        File(folder, "lecture-20261022-0900.m4a").writeBytes(frame(20))
        LectureRecorder.reset()
        val recorder = LectureRecorder.shared(app)
        assertEquals("making the recorder reads no audio: the trim waits", 50L + 17L, partial.length())
        assertEquals("the shared file is reset at once", RecorderState.Idle, RecorderShelf.read(shelf))
        val trimmedOn = arrayOfNulls<Thread>(1)
        val io = java.util.concurrent.Executors.newSingleThreadExecutor { Thread(it, "recover-io").also { t -> trimmedOn[0] = t } }
        val found = kotlinx.coroutines.runBlocking { recorder.recoverLeftover(io.asCoroutineDispatcher()) }
        io.shutdown()
        // Coroutine debug mode adds " @coroutine#N" to a thread's name while a coroutine runs on it,
        // so check the thread itself and its name without that suffix.
        assertNotNull("trimmed on the IO dispatcher given", trimmedOn[0])
        assertNotSame("not on the caller's thread", Thread.currentThread(), trimmedOn[0])
        assertEquals("trimmed on the IO dispatcher given, not the caller's thread", "recover-io", trimmedOn[0]!!.name.substringBefore(" @"))
        assertEquals("the newest recording is found", partial, found)
        assertEquals("and offered", partial, recorder.recovered)
        assertEquals("trimmed to its whole frames, so it plays", 50L, partial.length())
        assertEquals("the shared file says idle again", RecorderState.Idle, RecorderShelf.read(shelf))
        assertEquals("the recorder is idle", RecorderState.Idle, recorder.state)
        assertEquals("its set is named for when it began", RecorderNames.Moment(2026, 10, 23, 14, 5), RecorderNames.moment(partial.name))
        LectureRecorder.reset()
        assertNull("found once: the next launch has nothing to offer", kotlinx.coroutines.runBlocking { LectureRecorder.shared(app).recoverLeftover() })
    }

    companion object {
        /** One ADTS frame of [length] bytes (a 7-byte header, no CRC). */
        fun frame(length: Int): ByteArray {
            val b = ByteArray(length)
            b[0] = 0xFF.toByte(); b[1] = 0xF1.toByte(); b[2] = 0x50
            b[3] = (0x80 or ((length shr 11) and 0x03)).toByte()
            b[4] = ((length shr 3) and 0xFF).toByte()
            b[5] = (((length and 0x07) shl 5) or 0x1F).toByte()
            b[6] = 0xFC.toByte()
            return b
        }
    }

    @Test fun stopWithNoScreenWaitsForIt() {
        val controller = Robolectric.buildService(RecordingService::class.java, RecordingService.intent(app, RecordingService.ACTION_START)).create()
        controller.startCommand(0, 1)
        send(controller, RecordingService.ACTION_STOP)
        assertEquals("the file waits for the screen", machine.out, LectureRecorder.pending)
    }

    @Test fun aRecorderThatCannotStartLeavesTheForeground() {
        LectureRecorder.machineFactory = { object : LectureRecorder.AudioMachine {
            override fun begin(out: File) = throw IllegalStateException("busy")
            override fun pause() {}
            override fun resume() {}
            override fun end() {}
            override fun amplitude() = 0
            override fun release() {}
        } }
        val controller = Robolectric.buildService(RecordingService::class.java, Intent(app, RecordingService::class.java).setAction(RecordingService.ACTION_START)).create()
        controller.startCommand(0, 1)
        val shadow = shadowOf(controller.get())
        assertTrue("failed", LectureRecorder.shared(app).state is RecorderState.Failed)
        assertTrue("and the notification is gone", shadow.isForegroundStopped)
        assertTrue("with the service", shadow.isStoppedBySelf)
    }
}
