package com.stethoscore.app.exam

import android.content.Context
import android.content.SharedPreferences
import com.stethoscore.app.quiz.ExamTrack

// A port of ios/RedPen/Shared/Exam/ExamChoice.swift: which exam the
// student is preparing for, one primary and optionally a second. Everything
// that puts an exam first reads ExamChoice.current.
//
// The older setting, ExamTrack, still decides units, guidelines and OSCE
// style; choosing an exam here moves it to the exam's family, and a track of a
// different family lets go of the exam here, falling back to the track's own
// exam where it has one.
//
// iOS keeps these in UserDefaults; Android keeps them beside the track in the
// "appearance" SharedPreferences. [ExamDefaults] stands between, so the logic
// is tested on the JVM with a scratch map (ExamCatalogTest).

/** The few reads and writes the choice needs, as UserDefaults offers them. */
interface ExamDefaults {
    fun string(key: String): String?
    fun bool(key: String): Boolean
    fun double(key: String): Double
    fun has(key: String): Boolean
    fun set(key: String, value: String)
    fun set(key: String, value: Boolean)
    fun set(key: String, value: Double)
    fun remove(key: String)
}

/** The choice kept in memory, for tests and previews. */
class MemoryExamDefaults : ExamDefaults {
    private val values = HashMap<String, Any>()
    override fun string(key: String): String? = values[key] as? String
    override fun bool(key: String): Boolean = values[key] as? Boolean ?: false
    override fun double(key: String): Double = values[key] as? Double ?: 0.0
    override fun has(key: String): Boolean = key in values
    override fun set(key: String, value: String) { values[key] = value }
    override fun set(key: String, value: Boolean) { values[key] = value }
    override fun set(key: String, value: Double) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}

/** The choice kept in SharedPreferences. A double is kept as its bits, as a Long. */
class PrefsExamDefaults(private val prefs: SharedPreferences) : ExamDefaults {
    override fun string(key: String): String? = runCatching { prefs.getString(key, null) }.getOrNull()
    override fun bool(key: String): Boolean = runCatching { prefs.getBoolean(key, false) }.getOrDefault(false)
    override fun double(key: String): Double =
        runCatching { Double.fromBits(prefs.getLong(key, 0.0.toRawBits())) }.getOrDefault(0.0)
    override fun has(key: String): Boolean = prefs.contains(key)
    override fun set(key: String, value: String) { prefs.edit().putString(key, value).apply() }
    override fun set(key: String, value: Boolean) { prefs.edit().putBoolean(key, value).apply() }
    override fun set(key: String, value: Double) { prefs.edit().putLong(key, value.toRawBits()).apply() }
    override fun remove(key: String) { prefs.edit().remove(key).apply() }
}

object ExamChoice {
    const val primaryKey = "exam.primary"
    const val secondaryKey = "exam.secondary"
    /** Set once the onboarding question has been answered or skipped. */
    const val askedKey = "exam.asked"
    /** What the accuracy engine reads, kept as plain values. */
    const val strictnessKey = "exam.accuracyStrictness"
    const val strictnessFamilyKey = "exam.accuracyFamily"

    /** The preferences the track lives in (QuizPrefs on Android). */
    fun defaults(context: Context): ExamDefaults =
        PrefsExamDefaults(context.getSharedPreferences("appearance", Context.MODE_PRIVATE))

    /** The exam picked, whatever the track says now. */
    fun picked(defaults: ExamDefaults): TargetExam? = ExamCatalog.exam(defaults.string(primaryKey))

    fun pickedSecondary(defaults: ExamDefaults): TargetExam? = ExamCatalog.exam(defaults.string(secondaryKey))

    /**
     * The exam the app puts first under this track: the one picked, when it
     * belongs to the track; otherwise the track's own exam, where it has
     * exactly one; otherwise none.
     */
    fun effective(track: ExamTrack, defaults: ExamDefaults): TargetExam? {
        val exam = picked(defaults)
        if (exam != null && exam.family == track) return exam
        return fallback(track)
    }

    fun fallback(track: ExamTrack): TargetExam? = when (track) {
        ExamTrack.plab -> ExamCatalog.plab1
        ExamTrack.mrcp -> ExamCatalog.mrcp1
        ExamTrack.mrcs -> ExamCatalog.mrcsA
        ExamTrack.usmle, ExamTrack.general -> null
    }

    /** The second exam, only alongside a primary and never the same one. */
    fun secondary(track: ExamTrack, defaults: ExamDefaults): TargetExam? {
        val primary = effective(track, defaults) ?: return null
        val second = pickedSecondary(defaults) ?: return null
        return if (second.id != primary.id) second else null
    }

    fun current(defaults: ExamDefaults): TargetExam? = effective(currentTrack(defaults), defaults)

    fun currentSecondary(defaults: ExamDefaults): TargetExam? = secondary(currentTrack(defaults), defaults)

    fun current(context: Context): TargetExam? = current(defaults(context))

    fun currentSecondary(context: Context): TargetExam? = currentSecondary(defaults(context))

    /** The track, read from the given defaults. */
    fun currentTrack(defaults: ExamDefaults): ExamTrack = ExamTrack.from(defaults.string(ExamTrack.storageKey))

    /** Whether the onboarding question has been dealt with. */
    fun hasAsked(defaults: ExamDefaults): Boolean = defaults.bool(askedKey)

    fun markAsked(defaults: ExamDefaults) = defaults.set(askedKey, true)

    /**
     * Chooses the exams: the track follows the primary, and the accuracy
     * engine is told how strict to be. Null clears the choice.
     */
    fun choose(primary: TargetExam?, secondary: TargetExam?, defaults: ExamDefaults) {
        markAsked(defaults)
        if (primary == null) {
            defaults.remove(primaryKey)
            defaults.remove(secondaryKey)
            defaults.remove(strictnessKey)
            defaults.remove(strictnessFamilyKey)
            return
        }
        defaults.set(primaryKey, primary.id)
        if (secondary != null && secondary.id != primary.id) defaults.set(secondaryKey, secondary.id)
        else defaults.remove(secondaryKey)
        defaults.set(ExamTrack.storageKey, primary.family.rawValue)
        defaults.set(strictnessKey, primary.accuracyStrictness)
        defaults.set(strictnessFamilyKey, primary.family.rawValue)
    }
}
