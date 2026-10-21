package com.stethoscore.app.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.UUID

// ios/RedPen/Tests/LectureAudioTests.swift (fed0105), case for case: replacing
// a lecture recording - the old one goes only once the new one is in.
//
// The backup case: iOS sets isExcludedFromBackup on the folder; Android keeps
// it under noBackupFilesDir, which is never backed up, so only the "still
// found" half of that case has anything to check here.
class LectureAudioTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun replacingARecording() {
        val dir = LectureAudio.folder(tmp.newFolder("nobackup"))
        fun text(f: File): String? = if (f.exists()) f.readText() else null
        fun put(text: String, name: String): File = File(dir, name).also { it.writeText(text) }
        fun leftovers(): List<String> = (dir.list()?.toList() ?: emptyList()).filter { it.startsWith(".incoming-") }

        val set = UUID.randomUUID().toString().uppercase()
        val old = put("the old lecture", "$set.m4a")

        // MARK: a copy that fails keeps the old recording
        val gone = File(dir, "picked-then-deleted.m4a")
        var threw = false
        try { LectureAudio.store(gone, set, dir) } catch (e: Exception) { threw = true }
        assertTrue("a recording that cannot be copied in says so", threw)
        assertEquals("and the old recording is still there, whole", "the old lecture", text(old))
        assertTrue("with nothing half-copied left beside it", leftovers().isEmpty())

        // MARK: a copy that lands replaces it
        val picked = put("the new lecture", "picked.m4a")
        val placed = LectureAudio.store(picked, set, dir)
        assertEquals("a new recording takes the old one's place", "the new lecture", text(placed))
        assertEquals("and is the only one for the set", 1, LectureAudio.recordings(set, dir).size)
        assertTrue("with nothing left beside it", leftovers().isEmpty())

        // MARK: another container replaces the old one too
        val wav = put("the same lecture as wav", "picked.WAV")
        val placedWav = LectureAudio.store(wav, set, dir)
        val now = LectureAudio.recordings(set, dir)
        assertTrue("a recording in another container replaces the earlier one, under its own lower-case extension",
            now == listOf(placedWav) && placedWav.extension == "wav")
        assertEquals("with what was picked", "the same lecture as wav", text(placedWav))

        // MARK: another set's recording is never touched
        val other = UUID.randomUUID().toString().uppercase()
        val theirs = put("someone else's lecture", "$other.m4a")
        LectureAudio.store(picked, set, dir)
        assertEquals("another set's recording is left alone", "someone else's lecture", text(theirs))

        // MARK: recordings are not in the phone's backup (audit #81)
        assertTrue("the recordings folder is under the no-backup files", dir.parentFile?.name == "nobackup" && dir.name == "lectures")
        assertEquals("and its recordings are still found", 1, LectureAudio.recordings(set, dir).size)
    }
}
