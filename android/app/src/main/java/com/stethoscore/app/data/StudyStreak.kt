package com.stethoscore.app.data

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// A port of ios/RedPen/Shared/StudyStreak.swift (StudyStreak,
// GoalProgress) and Shared/DailyGoal.swift: the streak home's Vitals tile
// shows, and the daily goal. Pure Kotlin (StudyStreakTest, the goal and
// streak checks of WardRoundTests). A calendar is a time zone here.

/**
 * The streak's rules, apart from where the days are kept, so the JVM tests
 * can run them.
 *
 * A day counts when anything was studied on it. A missed day does not end
 * the streak if it is the week's one free rest day: a single missed day
 * between two days of study (or before today, while today is still young)
 * is covered as long as no other rest day was used in the 7 days before it.
 * Two missed days in a row always end it, and use no rest day. Rest days are
 * not stored: they fall out of the days themselves.
 */
object StudyStreak {
    data class Summary(
        /** Days studied in the current run: rest days keep it going but do not add to it. */
        val streak: Int,
        /** The missed days covered as rest days, keyed `yyyy-MM-dd`. */
        val restDays: Set<String>,
        /** Whether a missed day now would be covered. */
        val restReady: Boolean,
    ) {
        companion object { val empty = Summary(0, emptySet(), true) }
    }

    /** The rule's answer on day numbers. */
    data class Run(val streak: Int, val rests: List<Int>, val restReady: Boolean)

    /** How far apart two rest days must be, in days. */
    const val restEvery: Int = 7

    /** The streak as of [today], from the keys of the days anything was done. */
    fun summary(active: Set<String>, today: Instant, zone: ZoneId): Summary {
        val todayKey = key(today, zone)
        val todayNumber = dayNumber(todayKey, zone) ?: return Summary.empty
        val studied = HashSet<Int>()
        for (day in active) {
            val number = dayNumber(day, zone)
            if (number != null && number <= todayNumber) studied.add(number)
        }
        val result = run(studied, todayNumber)
        val keys = HashSet<String>()
        for (number in result.rests) keys.add(key(date(number, zone), zone))
        return Summary(result.streak, keys, result.restReady)
    }

    /** The rule itself, on plain day numbers: [studied] are the days with something done, [today] is today's number. */
    fun run(studied: Set<Int>, today: Int): Run {
        val first = studied.minOrNull() ?: return Run(0, emptyList(), true)
        var streak = 0
        var lastRest: Int? = null
        val rests = mutableListOf<Int>()
        var day = first
        while (day < today) {
            if (day in studied) {
                streak += 1
            } else if (streak > 0) {
                // only a gap of one day that the student came back after (or
                // that today can still close) is worth a rest day
                val next = day + 1
                val bridged = next in studied || next == today
                val allowed = lastRest?.let { day - it >= restEvery } ?: true
                if (bridged && allowed) {
                    lastRest = day
                    rests.add(day)
                } else {
                    streak = 0
                }
            }
            day += 1
        }
        if (today in studied) streak += 1
        val ready = lastRest?.let { today - it >= restEvery } ?: true
        return Run(streak, rests, ready)
    }

    // MARK: days

    /** `yyyy-MM-dd` in the phone's own time zone: a day is the student's day, not UTC's. */
    fun key(date: Instant, zone: ZoneId): String {
        val d = date.atZone(zone).toLocalDate()
        return String.format(Locale.ROOT, "%04d-%02d-%02d", d.year, d.monthValue, d.dayOfMonth)
    }

    /**
     * A day key as a count of days, so days can be stepped through with
     * plain arithmetic. Noon of the day, in its own offset, so a change to or
     * from summer time never makes two days one.
     */
    fun dayNumber(key: String, zone: ZoneId): Int? {
        val parts = key.split("-").mapNotNull { it.toIntOrNull() }
        if (parts.size != 3) return null
        val noon = runCatching { ZonedDateTime.of(LocalDate.of(parts[0], parts[1], parts[2]), LocalTime.NOON, zone) }.getOrNull() ?: return null
        val offset = noon.offset.totalSeconds
        val local = noon.toEpochSecond().toDouble() + offset
        return floor(local / 86_400).toInt()
    }

    /** The noon of a day number, for turning it back into a key. */
    fun date(number: Int, zone: ZoneId): Instant {
        val guess = Instant.ofEpochSecond(number.toLong() * 86_400 + 43_200)
        val offset = zone.rules.getOffset(guess).totalSeconds
        return guess.minusSeconds(offset.toLong())
    }
}

/** Today against the daily goal: "32 / 50 today". */
data class GoalProgress(val done: Int, val goal: Int) {
    /** How far round the ring is, 0 to 1. */
    val fraction: Double get() = if (goal <= 0) 0.0 else min(1.0, max(0, done).toDouble() / goal)

    val met: Boolean get() = goal > 0 && done >= goal

    val label: String get() = "$done / $goal today"

    companion object {
        /** The goal from what Settings stored under DailyGoal.key, read the way DailyGoal.current reads it. */
        fun goal(stored: Int): Int {
            if (stored <= 0) return 50
            return min(max(stored, DailyGoal.range.first), DailyGoal.range.last)
        }
    }
}

/**
 * How much the student means to do each day (cards, questions and steps),
 * for the goal ring beside the streak. Kept in [store]: the app's
 * preferences, an in-memory map until the app hands it one.
 */
object DailyGoal {
    const val key = "stethoscore.dailyGoal"
    val range: IntRange = 10..300

    /** Where the goal is kept (UserDefaults on iOS). */
    interface Store {
        fun int(key: String): Int
        fun set(key: String, value: Int)
        fun remove(key: String)
    }

    class MemoryStore : Store {
        private val values = HashMap<String, Int>()
        override fun int(key: String): Int = values[key] ?: 0
        override fun set(key: String, value: Int) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
    }

    var store: Store = MemoryStore()

    /** The goal, 50 until one is chosen, always within [range]. */
    var current: Int
        get() {
            val stored = store.int(key)
            if (stored <= 0) return 50
            return min(max(stored, range.first), range.last)
        }
        set(value) {
            store.set(key, min(max(value, range.first), range.last))
        }
}
