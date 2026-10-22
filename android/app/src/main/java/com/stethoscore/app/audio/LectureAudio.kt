package com.stethoscore.app.audio

import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Locale
import java.util.UUID

/**
 * Where a set's recording lives (ios/RedPen/Shared/LectureAudio.swift, fed0105).
 *
 * A convention rather than a field on StudySet: the location is derived from
 * the set's id (`<id>.<ext>` in the lectures folder), so it is right by
 * construction and a set exported as JSON stays a text file. On Android the
 * folder is under the app's no-backup files (Context.noBackupFilesDir), which
 * is where iOS's isExcludedFromBackup puts it: a term of lectures is
 * gigabytes, and each one can be imported again (audit #81).
 */
object LectureAudio {
    private val known = listOf("m4a", "mp3", "wav", "aac", "caf", "mp4")

    /** The lectures folder under [noBackupRoot] (Context.noBackupFilesDir), made if missing. */
    fun folder(noBackupRoot: File): File = File(noBackupRoot, "lectures").also { it.mkdirs() }

    /** The recording for this set, whatever container it arrived in. */
    fun existing(setId: String, dir: File): File? = recordings(setId, dir).firstOrNull()

    /**
     * Every file stored for this set, most likely container first. Found by
     * listing the folder for `<id>.*` rather than by trying a list of
     * extensions: the picker takes any audio.
     */
    fun recordings(setId: String, dir: File): List<File> {
        val names = dir.list()?.toList() ?: emptyList()
        return names.filter { it.substringBeforeLast('.', it) == setId && it.contains('.') }
            .sortedWith { first, second ->
                val a = known.indexOf(first.substringAfterLast('.').lowercase()).let { if (it < 0) known.size else it }
                val b = known.indexOf(second.substringAfterLast('.').lowercase()).let { if (it < 0) known.size else it }
                if (a == b) first.compareTo(second) else a.compareTo(b)
            }
            .map { File(dir, it) }
    }

    /** A picked file copied in under the set's id (iOS's store(imported:for:in:)), from a file. */
    fun store(imported: File, setId: String, dir: File): File =
        store({ FileInputStream(imported) }, imported.extension, setId, dir)

    /**
     * Copy an imported recording in, keeping its extension (lower-cased) so
     * the player can work out the format. The new file is copied in beside
     * the old recording first, and only once it is all there does it take
     * the old one's place: removing the old one first lost the student's only
     * copy whenever the copy failed. Earlier recordings under other
     * extensions go after.
     */
    fun store(open: () -> InputStream, extension: String, setId: String, dir: File): File {
        val ext = extension.ifEmpty { "m4a" }.lowercase(Locale.ROOT)
        val destination = File(dir, "$setId.$ext")
        // hidden, and named so it is never taken for one of the set's recordings
        val incoming = File(dir, ".incoming-${UUID.randomUUID()}.$ext")
        try {
            open().use { input -> incoming.outputStream().use { input.copyTo(it) } }
        } catch (e: Exception) {
            incoming.delete()
            throw e
        }
        val older = recordings(setId, dir)
        val same = older.firstOrNull { it.name.equals(destination.name, ignoreCase = true) }
        val placed = same ?: destination
        try {
            Files.move(incoming.toPath(), placed.toPath(), StandardCopyOption.REPLACE_EXISTING)
        } catch (e: Exception) {
            incoming.delete()
            throw e
        }
        for (there in older) if (there != same) there.delete()
        return placed
    }

    /** The set's recording, gone from the phone: called when the set is deleted. */
    fun remove(setId: String, dir: File) {
        for (there in recordings(setId, dir)) there.delete()
    }

    /**
     * Minutes and seconds, for a transport bar, or hours too past the hour:
     * "2:05", "1:02:05" (iOS L10nFormat.clock). Negative or not-a-number
     * reads as zero.
     */
    fun clock(seconds: Double): String {
        val total = if (seconds.isFinite() && seconds > 0) Math.round(seconds).toInt() else 0
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val secs = total % 60
        return if (hours > 0) String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, secs)
        else String.format(Locale.ROOT, "%d:%02d", minutes, secs)
    }
}
