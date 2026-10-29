package com.stethoscore.app.audio

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.json.JSONObject
import java.io.File
import java.time.ZoneOffset

// ios/RedPen/Tests/RecorderTests.swift (T0146), case for case: every move and
// the ones refused, the clock frozen while paused, a call pausing it, the file
// name and default title, the shared file, and the microphone asked only from
// a Record tap.
class RecorderStateTest {
    @get:Rule val tmp = TemporaryFolder()

    private val call = RecorderWords.callPaused
    private val idle = RecorderState.Idle
    private val asking = RecorderState.Asking
    private val saving = RecorderState.Saving
    private fun rec(at: Double, banked: Double = 0.0) = RecorderState.Recording(at, banked)
    private fun paused(banked: Double, reason: String? = null) = RecorderState.Paused(banked, reason)
    private fun failed(why: String = "x") = RecorderState.Failed(why)

    @Test fun everyAllowedMove() {
        assertEquals("idle -> asking on the first Record tap", asking, idle.ask())
        assertEquals("asking -> idle when the microphone is refused", idle, asking.cancel())
        assertEquals("idle -> recording", rec(10.0), idle.start(10.0))
        assertEquals("asking -> recording once allowed", rec(10.0), asking.start(10.0))
        assertEquals("failed -> recording again", rec(10.0), failed().start(10.0))
        assertEquals("recording -> paused, banking 5 s", paused(5.0), rec(10.0).pause(15.0))
        assertEquals("paused -> recording, keeping the banked 5 s", rec(20.0, 5.0), paused(5.0).resume(20.0))
        assertEquals("recording -> saving on Stop", saving, rec(10.0).stop(30.0))
        assertEquals("paused -> saving on Stop", saving, paused(5.0).stop(30.0))
        assertEquals("recording -> paused by a call, saying why", paused(12.0, call), rec(10.0, 2.0).interrupt(20.0, call))
        assertEquals("a call's pause -> recording when asked to resume after it", rec(40.0, 12.0), paused(12.0, call).resumeAfterInterruption(40.0))
        assertEquals("a call's pause -> Resume works too", rec(40.0, 12.0), paused(12.0, call).resume(40.0))
        assertEquals("saving -> idle once handed on", idle, saving.finish())
        assertEquals("failed -> idle once read", idle, failed().finish())
        assertEquals("recording -> failed", failed("disk"), rec(1.0).fail("disk"))
        assertEquals("asking -> failed", failed(), asking.fail("x"))
        assertEquals("saving -> failed", failed(), saving.fail("x"))
        assertEquals("paused -> failed", failed(), paused(1.0).fail("x"))
    }

    @Test fun theMovesRefused() {
        val r = rec(10.0)
        val p = paused(5.0)
        assertNull("idle cannot pause", idle.pause(1.0))
        assertNull("idle cannot resume", idle.resume(1.0))
        assertNull("idle cannot stop", idle.stop(1.0))
        assertNull("idle is not interrupted", idle.interrupt(1.0, call))
        assertNull("idle does not fail", idle.fail("x"))
        assertNull("idle has nothing to finish", idle.finish())
        assertNull("idle has nothing to cancel", idle.cancel())
        assertNull("recording cannot start again", r.start(20.0))
        assertNull("recording does not ask", r.ask())
        assertNull("recording cannot resume", r.resume(20.0))
        assertNull("recording cannot resume after an interruption", r.resumeAfterInterruption(20.0))
        assertNull("recording cannot finish without Stop", r.finish())
        assertNull("paused cannot pause", p.pause(20.0))
        assertNull("paused cannot start", p.start(20.0))
        assertNull("paused is not interrupted again", p.interrupt(20.0, call))
        assertNull("a pause the student chose is not undone by a call ending", p.resumeAfterInterruption(20.0))
        assertNull("saving cannot start", saving.start(1.0))
        assertNull("saving cannot pause", saving.pause(1.0))
        assertNull("saving cannot stop again", saving.stop(1.0))
        assertNull("asking cannot pause", asking.pause(1.0))
        assertNull("asking does not ask twice", asking.ask())
        assertNull("failed does not fail twice", failed().fail("y"))
    }

    @Test fun theClock() {
        val running = rec(100.0)
        assertEquals("60 s in while recording", 60.0, running.elapsed(160.0), 0.0)
        val held = running.pause(160.0)!!
        assertTrue("frozen at 60 s while paused", held.elapsed(160.0) == 60.0 && held.elapsed(1000.0) == 60.0)
        val again = held.resume(200.0)!!
        assertEquals("resumed with the banked 60 s", 60.0, again.elapsed(200.0), 0.0)
        assertEquals("and counting on from it: 90 s", 90.0, again.elapsed(230.0), 0.0)
        assertEquals("a clock that went back never takes time off", 60.0, again.elapsed(150.0), 0.0)
        assertTrue("nothing elapsed when not recording", idle.elapsed(5.0) == 0.0 && saving.elapsed(5.0) == 0.0)
        val byCall = again.interrupt(245.0, call)!!
        assertTrue("a call pauses it at 105 s with the reason", byCall == paused(105.0, call) && byCall.elapsed(999.0) == 105.0)
        assertTrue("the clock reads 12:03, 1:02:03 and 0:00",
            RecorderNames.clock(723.0) == "12:03" && RecorderNames.clock(3723.0) == "1:02:03" && RecorderNames.clock(-4.0) == "0:00")
    }

    @Test fun names() {
        val moment = RecorderNames.Moment(2026, 10, 23, 14, 5)
        assertEquals("a fixed date read in its time zone", moment, RecorderNames.Moment.of(1792764300L, ZoneOffset.UTC))
        assertEquals("file name lecture-20261023-1405.m4a", "lecture-20261023-1405.m4a", RecorderNames.fileName(moment))
        assertEquals("English title: Lecture, 23 Oct 14:05", "Lecture, 23 Oct 14:05", RecorderNames.defaultTitle(moment, "en"))
        assertEquals("Arabic title in Arabic digits", "محاضرة، ٢٣ أكتوبر ١٤:٠٥", RecorderNames.defaultTitle(moment, "ar"))
        assertEquals("ar-EG reads Arabic too", "محاضرة، ٢٣ أكتوبر ١٤:٠٥", RecorderNames.defaultTitle(moment, "ar-EG"))
        val early = RecorderNames.Moment(2027, 1, 3, 9, 7)
        assertEquals("single digits padded in the file name", "lecture-20270103-0907.m4a", RecorderNames.fileName(early))
        assertEquals("and the title: Lecture, 3 Jan 09:07", "Lecture, 3 Jan 09:07", RecorderNames.defaultTitle(early, "en"))
    }

    @Test fun theMeterAndTheDisk() {
        assertTrue("meter: -60 dB silent, -25 dB half, 0 dB full",
            RecorderMeter.level(-60.0) == 0.0 && RecorderMeter.level(-25.0) == 0.5 && RecorderMeter.level(0.0) == 1.0)
        assertEquals("meter: no signal reads silent", 0.0, RecorderMeter.level(Double.NEGATIVE_INFINITY), 0.0)
        assertEquals("meter: a full-scale amplitude is full", 1.0, RecorderMeter.level(32767), 1e-9)
        assertTrue("under 200 MB free stops the recording",
            RecorderMeter.diskTooLow(199L * 1024 * 1024) && !RecorderMeter.diskTooLow(200L * 1024 * 1024))
    }

    @Test fun theSharedFile() {
        val file = RecorderShelf.file(tmp.newFolder("files"))
        for (state in listOf(idle, asking, rec(1792764300.5, 12.25), paused(61.0), paused(61.0, call), saving, failed("disk"))) {
            assertTrue("round trip: ${state.phase}", RecorderShelf.write(state, file) && RecorderShelf.read(file) == state)
        }
        val shape = JSONObject(RecorderShelf.encode(rec(5.0, 2.0)))
        assertTrue("the file says v, phase, startedAt and banked",
            shape.getString("phase") == "recording" && shape.getInt("v") == 1 && shape.getDouble("startedAt") == 5.0)
        assertEquals("a missing file reads as idle", idle, RecorderShelf.read(File(file.parentFile, "missing.json")))
        file.writeText("{not json")
        assertEquals("a garbled file reads as idle", idle, RecorderShelf.read(file))
        file.writeText("{\"v\":9,\"phase\":\"recording\",\"startedAt\":1,\"banked\":0}")
        assertEquals("a newer app's file reads as idle", idle, RecorderShelf.read(file))
        file.writeText("{\"v\":1,\"phase\":\"recording\"}")
        assertEquals("a recording with no clock reads as idle", idle, RecorderShelf.read(file))
        file.writeText("[1,2]")
        assertEquals("the wrong shape reads as idle", idle, RecorderShelf.read(file))
    }

    @Test fun theMomentFromAFileName() {
        assertEquals("read back from the file name", RecorderNames.Moment(2026, 10, 23, 14, 5), RecorderNames.moment("lecture-20261023-1405.aac"))
        assertEquals("any extension", RecorderNames.Moment(2027, 1, 3, 9, 7), RecorderNames.moment("lecture-20270103-0907.caf"))
        assertNull("not ours: nothing", RecorderNames.moment("notes.m4a"))
        assertNull("a name cut short: nothing", RecorderNames.moment("lecture-2026102-1405.m4a"))
    }

    @Test fun theMicrophoneAskedAgainWheneverAndroidAllows() {
        assertEquals("granted", MicPermission.granted, MicAsk.status(granted = true, rationale = false, refusedForGood = true))
        assertEquals("never asked: the sheet", MicPermission.undetermined, MicAsk.status(granted = false, rationale = false, refusedForGood = false))
        assertEquals("denied once, a rationale offered: asked again", MicPermission.undetermined, MicAsk.status(granted = false, rationale = true, refusedForGood = false))
        assertEquals("a rationale beats an old refusal", MicPermission.undetermined, MicAsk.status(granted = false, rationale = true, refusedForGood = true))
        assertEquals("refused for good: Settings", MicPermission.denied, MicAsk.status(granted = false, rationale = false, refusedForGood = true))
        assertTrue("no, and no rationale after it: for good", MicAsk.refusedForGood(granted = false, rationaleAfter = false))
        assertTrue("no, with a rationale after it: askable", !MicAsk.refusedForGood(granted = false, rationaleAfter = true))
        // a one-time grant that ran out: the last answer was a grant, so it is askable, not denied
        val lastAnswer = MicAsk.refusedForGood(granted = true, rationaleAfter = false)
        assertEquals("a one-time grant that has run out is askable again", MicPermission.undetermined,
            MicAsk.status(granted = false, rationale = false, refusedForGood = lastAnswer))
    }

    /** The screen's flow: the kept flag is read through stillRefused on every check, and written back. */
    @Test fun refusedForGoodThenGrantedThenRevokedIsAskedAgain() {
        var kept = false
        fun check(granted: Boolean, rationale: Boolean): MicPermission {
            kept = MicAsk.stillRefused(granted, rationale, kept)
            return MicAsk.status(granted, rationale, kept)
        }
        // refused for good: no grant, and no rationale after the prompt
        kept = MicAsk.refusedForGood(granted = false, rationaleAfter = false)
        assertEquals("refused for good: Settings", MicPermission.denied, check(granted = false, rationale = false))
        // then granted in Settings
        assertEquals("granted in Settings", MicPermission.granted, check(granted = true, rationale = false))
        assertTrue("the grant clears the refusal", !kept)
        // then revoked in Settings: no rationale shows after a revoke
        assertEquals("revoked: asked again, never sent to Settings", MicPermission.undetermined, check(granted = false, rationale = false))
        // a rationale clears it too
        kept = true
        assertEquals("a rationale offered: asked", MicPermission.undetermined, check(granted = false, rationale = true))
        assertTrue("and the refusal is cleared", !kept)
    }

    @Test fun aSaveThatIsCopyingCannotStartAnother() {
        val file = tmp.newFile("lecture-20261023-1500.aac")
        val offered = RecordingSave().offer(file)
        val copying = offered.begin()!!
        assertTrue("copying: the choice is closed and Save the recording waits", copying.copying && !copying.choosing && !copying.canSave)
        assertNull("a second tap starts no second copy", copying.begin())
        assertEquals("nor reopens the choice", copying, copying.reopen())
        val failed = copying.save("SET") { _, _ -> null }
        assertTrue("a failed copy can be saved again", failed.canSave && !failed.copying && failed.file == file)
        val saved = failed.begin()!!.save("SET") { _, _ -> File(file.parentFile, "SET.aac") }
        assertTrue("saved", saved.kept != null && !saved.copying && !saved.canSave)
    }

    @Test fun aCancelledSaveCanBeSavedAgain() {
        val file = tmp.newFile("lecture-20261023-1405.aac")
        val offered = RecordingSave().offer(file)
        assertTrue("Stop offers the choice", offered.choosing && offered.file == file)
        val cancelled = offered.cancel()
        assertTrue("Cancel keeps the recording, waiting", cancelled.waiting && cancelled.file == file)
        val again = cancelled.reopen()
        assertTrue("Save the recording opens the choice again", again.choosing && !again.waiting)
        val kept = File(file.parentFile, "SET.aac")
        var copies = 0
        val saved = again.save("SET") { _, _ -> copies += 1; kept }
        assertTrue("saved: kept under the set, nothing waiting", saved.kept == kept && saved.setId == "SET" && saved.file == null && !saved.waiting)
        assertEquals("one copy", 1, copies)
        assertEquals("nothing to reopen once saved", saved, saved.reopen())
        assertEquals("nothing to save twice", saved, saved.save("OTHER") { _, _ -> error("no second copy") })
    }

    @Test fun wholeAdtsFrames() {
        val frames = RecordingServiceTest.frame(20) + RecordingServiceTest.frame(30)
        assertEquals("two whole frames", 50, Adts.wholeLength(frames))
        assertEquals("a cut-off third is left out", 50, Adts.wholeLength(frames + RecordingServiceTest.frame(40).copyOf(39)))
        assertEquals("a header cut short is left out", 50, Adts.wholeLength(frames + byteArrayOf(0xFF.toByte(), 0xF1.toByte())))
        assertEquals("not ADTS: nothing", 0, Adts.wholeLength("{not audio}".toByteArray()))
        val file = tmp.newFile("x.aac").apply { writeBytes(frames + RecordingServiceTest.frame(40).copyOf(10)) }
        assertEquals("trimmed in place", 50L, Adts.trim(file)!!.length())
        val empty = tmp.newFile("y.aac").apply { writeBytes(byteArrayOf(1, 2, 3)) }
        assertNull("nothing whole: dropped", Adts.trim(empty))
        assertTrue("and deleted", !empty.exists())
    }

    @Test fun recoveryFromTheSharedFile() {
        val files = tmp.newFolder("files2")
        val folder = tmp.newFolder("recordings")
        val shelf = RecorderShelf.file(files)
        assertEquals("the newest stem", "lecture-20261023-1405.aac", RecorderRecovery.leftover(listOf("lecture-20261022-0900.aac", "lecture-20261023-1405.aac", "SET.m4a")))
        assertEquals("its live recording before a half-made export", "lecture-20261023-1405.caf",
            RecorderRecovery.leftover(listOf("lecture-20261023-1405.m4a", "lecture-20261023-1405.caf")))
        assertEquals("a finished export alone", "lecture-20261023-1405.m4a", RecorderRecovery.leftover(listOf("lecture-20261023-1405.m4a")))
        assertNull("none of ours", RecorderRecovery.leftover(listOf("notes.txt")))

        RecorderShelf.write(rec(1792764300.0, 3.0), shelf)
        val partial = File(folder, "lecture-20261023-1405.aac").apply { writeBytes(RecordingServiceTest.frame(20) + RecordingServiceTest.frame(30).copyOf(4)) }
        assertEquals("a recording cut off by a kill is found", partial, RecorderRecovery.recover(shelf, folder))
        assertEquals("trimmed to whole frames", 20L, partial.length())
        assertEquals("the shared file is reset", idle, RecorderShelf.read(shelf))
        assertNull("and found once", RecorderRecovery.recover(shelf, folder))

        RecorderShelf.write(paused(9.0, call), shelf)
        assertEquals("paused when killed: found too", partial, RecorderRecovery.recover(shelf, folder))
        RecorderShelf.write(saving, shelf)
        assertEquals("stopped but not saved: found too", partial, RecorderRecovery.recover(shelf, folder))
        RecorderShelf.write(failed("x"), shelf)
        assertNull("a failure: nothing offered", RecorderRecovery.recover(shelf, folder))
        assertEquals("but reset", idle, RecorderShelf.read(shelf))
        RecorderShelf.write(rec(1.0), shelf)
        partial.writeBytes(byteArrayOf(9, 9))
        assertNull("nothing whole: nothing offered", RecorderRecovery.recover(shelf, folder))
        assertTrue("the broken file is deleted", !partial.exists())
        assertEquals("and the shared file reset", idle, RecorderShelf.read(shelf))
    }

    private class FakeGate(override var status: MicPermission, val answer: Boolean) : PermissionGate {
        var requests = 0
        override suspend fun request(): Boolean {
            requests += 1
            status = if (answer) MicPermission.granted else MicPermission.denied
            return answer
        }
    }

    @Test fun theMicrophoneAskedOnlyFromARecordTap() = runBlocking {
        val fresh = FakeGate(MicPermission.undetermined, answer = true)
        val flow = RecordFlow(fresh)
        assertEquals("making the flow (the launch path) asks nothing", 0, fresh.requests)
        assertTrue("the first Record tap shows the sheet, not the system prompt", flow.tapRecord() == RecordFlow.Step.sheet && fresh.requests == 0)
        assertTrue("Continue asks the system once, and records when allowed", flow.continueFromSheet() == RecordFlow.Step.record && fresh.requests == 1)
        assertTrue("the next tap records without asking again", flow.tapRecord() == RecordFlow.Step.record && fresh.requests == 1)
        assertTrue("Continue after it was allowed does not ask again", flow.continueFromSheet() == RecordFlow.Step.record && fresh.requests == 1)

        val refusing = FakeGate(MicPermission.undetermined, answer = false)
        val refused = RecordFlow(refusing)
        refused.tapRecord()
        assertTrue("refused: the Open Settings row", refused.continueFromSheet() == RecordFlow.Step.settingsRow && refusing.requests == 1)
        assertTrue("and a later tap shows the row again, never the prompt", refused.tapRecord() == RecordFlow.Step.settingsRow && refusing.requests == 1)

        val off = FakeGate(MicPermission.denied, answer = true)
        assertTrue("already off in Settings: the row, no prompt", RecordFlow(off).tapRecord() == RecordFlow.Step.settingsRow && off.requests == 0)

        assertTrue("the sheet and row say what the owner wrote", RecorderWords.sheetTitle == "Record your lecture" &&
            RecorderWords.sheetBody == "Stethoscore uses the microphone to record the lecture. The recording stays on this phone until you choose to transcribe it." &&
            RecorderWords.micOff == "Microphone is off for Stethoscore")
        assertTrue("the pause and low-disk lines are whole sentences, no bare hyphen",
            RecorderWords.callPaused == "Paused for a call" && RecorderWords.lowDisk == "Stopped because this phone is almost full.")
        assertTrue("a plain loss of focus says another app, not the microphone",
            RecorderWords.focusLost == "Paused for another app" && RecorderWords.focusLost != RecorderWords.micTaken)
    }
}
