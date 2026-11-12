package com.stethoscore.app.quiz

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * The attending's hints once written, kept on disk so a question asks the
 * model only once, across launches (iOS ExamStore's hints, the "exam.hints"
 * blob; here its own file in filesDir). The file has the shape iOS keeps:
 * `{"hints": {key: text}, "order": [key]}`, and the rules are [HintCache]'s: a
 * key is the item's id and a fingerprint of its wording, the oldest go first
 * past the cap.
 *
 * Only hints the writer wrote and [AttendingHint.accept] passed are kept
 * (HintWriter), and only that. A cache can be rebuilt, so a file that cannot be
 * read is read as empty and replaced by the next write, and a write that fails
 * loses nothing on screen: the hint stays kept for this launch. Nothing here
 * throws.
 */
class HintStore(private val file: File) {
    private val lock = Any()
    private var cache: HintCache? = null

    /** The hint kept for this item and wording, or null. */
    fun hint(id: String, version: String = ""): String? = synchronized(lock) { loaded().hint(id, version) }

    /** Keeps [text] for this item and wording, and writes the file. */
    fun keep(text: String, id: String, version: String = "") {
        synchronized(lock) {
            val kept = loaded()
            kept.store(text, id, version)
            runCatching { write(kept) }
        }
    }

    /** How many hints are kept. */
    val count: Int get() = synchronized(lock) { loaded().hints.size }

    private fun loaded(): HintCache = cache ?: read().also { cache = it }

    private fun read(): HintCache {
        val kept = HintCache()
        if (!file.exists()) return kept
        return try {
            val root = JSONObject(file.readText(Charsets.UTF_8))
            val hints = root.optJSONObject("hints") ?: return kept
            val order = root.optJSONArray("order")
            val seen = HashSet<String>()
            // the saved order first, then any hint it forgot; the cap trims the oldest
            for (i in 0 until (order?.length() ?: 0)) {
                val key = order?.optString(i).orEmpty()
                val text = hints.optString(key, "")
                if (text.isNotEmpty() && seen.add(key)) { kept.hints[key] = text; kept.order += key }
            }
            for (key in hints.keys()) {
                val text = hints.optString(key, "")
                if (text.isNotEmpty() && seen.add(key)) { kept.hints[key] = text; kept.order += key }
            }
            while (kept.order.size > HintCache.cap) kept.hints.remove(kept.order.removeAt(0))
            kept
        } catch (e: Exception) {
            HintCache()
        }
    }

    /** A temporary file, fsync, then an atomic rename, as the library is written: an interruption never leaves half a file. */
    private fun write(kept: HintCache) {
        val directory = file.parentFile ?: return
        val temporary = File(directory, file.name + ".tmp")
        try {
            if (!directory.exists()) directory.mkdirs()
            val json = JSONObject().put("hints", JSONObject(kept.hints)).put("order", JSONArray(kept.order)).toString()
            FileOutputStream(temporary).use { stream -> stream.write(json.toByteArray(Charsets.UTF_8)); stream.fd.sync() }
            try {
                Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (_: AtomicMoveNotSupportedException) {
                check(temporary.renameTo(file)) { "Could not replace the hints file." }
            }
        } catch (e: Exception) {
            temporary.delete()
            throw e
        }
    }

    companion object {
        const val FILE_NAME = "exam-hints.json"

        @Volatile private var shared: HintStore? = null

        /** The app's one store, so every quiz screen shares what was kept. */
        fun from(context: Context): HintStore = shared ?: synchronized(this) {
            shared ?: HintStore(File(context.applicationContext.filesDir, FILE_NAME)).also { shared = it }
        }
    }
}
