package com.stethoscore.app.ui.narrate

import android.content.Context
import android.content.SharedPreferences
import com.stethoscore.app.audio.AudioRateMemory
import com.stethoscore.app.audio.CorrectionOutcome
import com.stethoscore.app.audio.PronunciationStore
import com.stethoscore.app.audio.TranscriptCorrections
import java.io.File

/**
 * The pronunciations this phone has learned (iOS PronunciationLibrary), kept
 * as the same TSV the transcription pipeline reads and writes, in the app's
 * files. One per process, so every lecture screen shares what was learned.
 */
class PronunciationLibrary private constructor(private val file: File) {
    private val store: PronunciationStore = runCatching {
        if (file.exists()) PronunciationStore.fromTSV(file.readText()) else PronunciationStore()
    }.getOrElse { PronunciationStore() }

    /** Everything already learned, applied to a transcript that has just arrived or just opened. */
    @Synchronized fun applyLearned(texts: MutableList<String>): Int = TranscriptCorrections.applyLearned(store, texts)

    /** The student fixed a word: here, everywhere that sounds the same, and remembered. */
    @Synchronized fun fix(segment: Int, word: Int, to: String, texts: MutableList<String>): CorrectionOutcome {
        val outcome = TranscriptCorrections.fix(segment, word..word, to, texts, store)
        if (outcome.learned) save()
        return outcome
    }

    /** One undo puts back everything one correction changed in the transcript; what was learned stays learned, as on iOS. */
    fun undo(snapshot: List<String>, texts: MutableList<String>, touching: CorrectionOutcome) =
        TranscriptCorrections.undo(snapshot, texts, touching)

    private fun save() {
        runCatching {
            val temp = File(file.parentFile, file.name + ".tmp")
            temp.writeText(store.tsv())
            if (!temp.renameTo(file)) { file.writeText(store.tsv()); temp.delete() }
        }
    }

    companion object {
        @Volatile private var shared: PronunciationLibrary? = null

        fun shared(context: Context): PronunciationLibrary = shared ?: synchronized(this) {
            shared ?: PronunciationLibrary(File(context.applicationContext.filesDir, "redpen-pronunciations.tsv")).also { shared = it }
        }
    }
}

/** The speed memory in the app's preferences (iOS keeps it in UserDefaults.standard). */
class PreferencesRateMemory(context: Context) : AudioRateMemory {
    private val prefs: SharedPreferences = context.applicationContext.getSharedPreferences("audio", Context.MODE_PRIVATE)
    override fun getDouble(key: String): Double? = prefs.getString(key, null)?.toDoubleOrNull()
    override fun putDouble(key: String, value: Double) { prefs.edit().putString(key, value.toString()).apply() }
}
