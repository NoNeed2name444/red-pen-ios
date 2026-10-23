package com.stethoscore.app.data

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

// A port of ios/RedPen/Shared/Learn/RhythmReading.swift: how
// regularly the studying has gone lately, read the way a monitor reads a
// rhythm strip: the last fourteen days, each a beat (something studied that
// day) or a flat line (a day off), and a word for the pattern. Pure Kotlin.
//
// - Regular: something on at least 70% of the days the strip covers, and no
//   more than two days off in a row.
// - Resting: nothing in the last seven days of the strip.
// - Irregular: anything else with a beat in the last week.
//
// A day with nothing yet today does not count against the strip until it is
// over. Days are `yyyy-MM-dd` in the phone's own time zone.
object RhythmReading {
    const val window = 14
    const val regularShare = 0.7
    const val regularGap = 2
    const val restingDays = 7

    enum class Rhythm { regular, irregular, resting, noTrace }

    data class Reading(
        val rhythm: Rhythm,
        /** The strip, oldest day first, `window` long: true where something was studied. */
        val beats: List<Boolean>,
        val activeDays: Int,
        val span: Int,
    ) {
        /** "Sinus · regular". */
        val words: String get() = when (rhythm) {
            Rhythm.regular -> "Sinus · regular"
            Rhythm.irregular -> "Sinus · irregular"
            Rhythm.resting -> "Sinus · resting"
            Rhythm.noTrace -> "No trace yet"
        }

        /** One plain line about the strip. */
        val line: String get() = when (rhythm) {
            Rhythm.regular, Rhythm.irregular -> {
                val days = if (span == 1) "day" else "$span days"
                "Studied $activeDays of the last $days."
            }
            Rhythm.resting -> "Nothing in the last $restingDays days. Pick it up whenever you’re ready."
            Rhythm.noTrace -> "Your study days show here once you start."
        }

        /** What TalkBack reads for the strip. */
        val spoken: String get() {
            val word = when (rhythm) {
                Rhythm.regular -> "regular"
                Rhythm.irregular -> "irregular"
                Rhythm.resting -> "resting"
                Rhythm.noTrace -> "no trace yet"
            }
            return "Study rhythm, $word. $line"
        }
    }

    fun key(date: LocalDate): String = String.format(Locale.ROOT, "%04d-%02d-%02d", date.year, date.monthValue, date.dayOfMonth)

    fun key(date: Instant, zone: ZoneId): String = key(date.atZone(zone).toLocalDate())

    /** The days studied, from a study log and the dated answers together: the larger count each day. */
    fun merged(log: Map<String, Int>, answers: List<Instant>, zone: ZoneId): Map<String, Int> {
        val perDay = HashMap<String, Int>()
        for (date in answers) perDay.merge(key(date, zone), 1, Int::plus)
        val days = HashMap(log)
        for ((day, count) in perDay) if (count > (days[day] ?: 0)) days[day] = count
        return days
    }

    fun read(days: Map<String, Int>, now: Instant, zone: ZoneId): Reading {
        val active = days.filter { it.value > 0 }.keys
        val today = now.atZone(zone).toLocalDate()
        // a day with nothing in it yet is not over: the strip ends yesterday
        val end = if (key(today) !in active) today.minusDays(1) else today
        val keys = (window - 1 downTo 0).map { key(end.minusDays(it.toLong())) }
        val beats = keys.map { it in active }
        // the keys sort as dates do, so the first day ever studied is the least
        val first = active.minOrNull() ?: return Reading(Rhythm.noTrace, beats, 0, 0)
        val counted = keys.indices.filter { keys[it] >= first }.map { beats[it] }
        val activeDays = counted.count { it }
        val span = counted.size
        val trailing = offAtEnd(beats)
        val rhythm = when {
            activeDays == 0 || trailing >= restingDays -> Rhythm.resting
            activeDays >= regularShare * span && longestOff(counted) <= regularGap -> Rhythm.regular
            else -> Rhythm.irregular
        }
        return Reading(rhythm, beats, activeDays, span)
    }

    /** Days off at the end of the strip. */
    fun offAtEnd(beats: List<Boolean>): Int {
        var run = 0
        for (beat in beats.asReversed()) { if (beat) break; run += 1 }
        return run
    }

    /** The longest run of days off anywhere on the strip. */
    fun longestOff(beats: List<Boolean>): Int {
        var longest = 0
        var run = 0
        for (beat in beats) { run = if (beat) 0 else run + 1; longest = maxOf(longest, run) }
        return longest
    }
}
