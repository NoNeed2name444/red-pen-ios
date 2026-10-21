package com.stethoscore.app.data

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

// Ported from ios/RedPen/Shared/Learn/StudyRhythm.swift (StudyRhythm,
// ReminderSettings), with LearnDefaults standing in for UserDefaults.
// Tested by LearnTest.
//
// The reminders themselves (LearnNotifications) are not delivered on
// Android yet; the choices and the wording are here so the screens and the
// tests read the same as iOS.

/** Small values kept on this device (UserDefaults on iOS). */
interface LearnDefaults {
    fun string(key: String): String?
    fun set(key: String, value: String?)

    fun bool(key: String): Boolean = string(key) == "true"
    fun setBool(key: String, value: Boolean) = set(key, if (value) "true" else "false")
    fun int(key: String): Int? = string(key)?.toIntOrNull()
    fun setInt(key: String, value: Int) = set(key, value.toString())
    fun strings(key: String): List<String> = string(key)?.split('\n')?.filter { it.isNotEmpty() } ?: emptyList()
    fun setStrings(key: String, value: List<String>) = set(key, value.joinToString("\n"))

    class Memory : LearnDefaults {
        private val values = HashMap<String, String>()
        override fun string(key: String): String? = values[key]
        override fun set(key: String, value: String?) {
            if (value == null) values.remove(key) else values[key] = value
        }
    }

    companion object {
        /** What the app reads and writes; the activity swaps in its SharedPreferences. */
        var shared: LearnDefaults = Memory()
    }
}

/**
 * The small daily rhythm around the main sessions: a question of the day, a
 * calm evening re-read of the day's misses, and a two-minute morning check
 * of the same items.
 */
object StudyRhythm {
    private fun day(at: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(at).atZone(zone).toLocalDate()

    // MARK: the day's misses

    /** Questions whose latest answer on [dayAt] was wrong, in the order they were last missed. */
    fun missed(dayAt: Long, events: List<AnswerEvent>, zone: ZoneId = ZoneId.systemDefault()): List<String> {
        val start = day(dayAt, zone)
        val latest = LinkedHashMap<String, AnswerEvent>()
        for (e in events) {
            if (day(e.at, zone) != start) continue
            val kept = latest[e.questionId]
            if (kept != null && kept.at > e.at) continue
            latest[e.questionId] = e
        }
        return latest.values.filter { !it.correct }.sortedBy { it.at }.map { it.questionId }
    }

    /** The morning check: yesterday's misses not already answered today. */
    fun morningItems(now: Long, events: List<AnswerEvent>, zone: ZoneId = ZoneId.systemDefault()): List<String> {
        val yesterday = Instant.ofEpochMilli(now).atZone(zone).minusDays(1).toInstant().toEpochMilli()
        val today = day(now, zone)
        val answeredToday = events.filter { day(it.at, zone) == today }.map { it.questionId }.toSet()
        return missed(yesterday, events, zone).filter { it !in answeredToday }
    }

    // MARK: question of the day

    /** One question the notification can ask. */
    data class Candidate(val id: String, val subject: String, val optionCount: Int)

    /**
     * The day's question: from the weakest subject that has one, preferring a
     * question one or two days from secured, then one slipped, then one never
     * tried, then any. The same all day (seeded by the date).
     */
    fun questionOfTheDay(candidates: List<Candidate>, weakestFirst: List<String>,
                         standings: Map<String, SecuredRule.Standing>, dayAt: Long,
                         zone: ZoneId = ZoneId.systemDefault()): String? {
        val usable = candidates.filter { it.optionCount in 2..5 }
        if (usable.isEmpty()) return null
        val order = weakestFirst + (usable.map { it.subject }.toSet() - weakestFirst.toSet()).sorted()
        val seed = daySeed(dayAt, zone)
        for (subject in order) {
            val pool = usable.filter { it.subject == subject }
            if (pool.isEmpty()) continue
            val close = pool.filter { (standings[it.id] as? SecuredRule.Standing.Building)?.let { b -> b.n > 0 } == true }
            val fresh = pool.filter { (standings[it.id] ?: SecuredRule.Standing.New) == SecuredRule.Standing.New }
            val slipped = pool.filter { standings[it.id] == SecuredRule.Standing.Building(0) }
            for (tier in listOf(close, slipped, fresh, pool)) {
                if (tier.isEmpty()) continue
                val sorted = tier.sortedBy { it.id.uppercase() }
                return sorted[(seed % sorted.size.toULong()).toInt()].id
            }
        }
        return null
    }

    /** A number that is the same all day. */
    fun daySeed(dayAt: Long, zone: ZoneId = ZoneId.systemDefault()): ULong {
        val d = day(dayAt, zone)
        val n = d.year * 10_000 + d.monthValue * 100 + d.dayOfMonth
        return maxOf(0, n).toULong() * 2_654_435_761uL
    }

    /** "A", "B", ... */
    fun letter(i: Int): String {
        val letters = listOf("A", "B", "C", "D", "E", "F", "G", "H")
        return if (i in letters.indices) letters[i] else "${i + 1}"
    }

    /** An option cut to fit a notification button. */
    fun abbreviated(option: String, limit: Int = 34): String {
        val s = option.trim()
        if (s.length <= limit) return s
        return s.take(limit - 1).trim() + "…"
    }

    /** The notification's body: the stem, cut to fit, then the options. */
    fun questionBody(stem: String, options: List<String>, stemLimit: Int = 320): String {
        var s = stem.trim()
        if (s.length > stemLimit) s = s.take(stemLimit - 1) + "…"
        val lines = options.mapIndexed { i, o -> "${letter(i)}  ${abbreviated(o, 60)}" }
        return (listOf(s, "") + lines + listOf("", "Hold to answer.")).joinToString("\n")
    }

    /** The reply after an answer from the notification. */
    fun verdict(correct: Boolean, rightLetter: String, rightText: String): Pair<String, String> =
        if (correct) "Correct — $rightLetter" to "${abbreviated(rightText, 80)}. Tap for why."
        else "It was $rightLetter" to "${abbreviated(rightText, 80)}. Tap for why."

    // MARK: evening and morning

    fun bedtimeBody(misses: Int, examDays: Int?): String {
        val plural = if (misses == 1) "" else "es"
        var s = "$misses of today’s miss$plural, with the answer and one line each. A calm read, not a test."
        if (examDays != null && examDays in 0..7) s += " Then sleep — it does more than cramming this week."
        return s
    }

    fun morningBody(items: Int): String {
        val plural = if (items == 1) "" else "s"
        return "Two minutes: $items question$plural you missed yesterday, before anything new."
    }
}

/** The reminder choices, kept on this device. */
object ReminderSettings {
    const val questionKey = "reminder.qotd"
    const val questionTimeKey = "reminder.qotd.minutes"
    const val bedtimeKey = "reminder.bedtime"
    const val bedtimeTimeKey = "reminder.bedtime.minutes"
    const val morningKey = "reminder.morning"
    const val morningTimeKey = "reminder.morning.minutes"

    /** Minutes after midnight. */
    const val defaultQuestionTime = 12 * 60 + 30
    const val defaultBedtime = 22 * 60
    const val defaultMorning = 7 * 60 + 30

    fun minutes(key: String, default: Int, defaults: LearnDefaults = LearnDefaults.shared): Int {
        val stored = defaults.int(key) ?: return default
        return if (stored in 0 until 1440) stored else default
    }

    val questionOn: Boolean get() = LearnDefaults.shared.bool(questionKey)
    val bedtimeOn: Boolean get() = LearnDefaults.shared.bool(bedtimeKey)
    val morningOn: Boolean get() = LearnDefaults.shared.bool(morningKey)

    /** Notification permission was refused: every reminder goes off (audit #37). */
    fun refused(defaults: LearnDefaults = LearnDefaults.shared) {
        for (key in listOf(questionKey, bedtimeKey, morningKey)) defaults.setBool(key, false)
    }

    /** The next time at [minutes] past midnight after [now] (today's if still ahead by a few minutes, else tomorrow's). */
    fun next(minutes: Int, now: Long, zone: ZoneId = ZoneId.systemDefault()): Long {
        val start = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().atStartOfDay(zone)
        val today = start.plusMinutes(minutes.toLong())
        if (today.toInstant().toEpochMilli() > now + 120_000) return today.toInstant().toEpochMilli()
        return today.plusDays(1).toInstant().toEpochMilli()
    }
}
