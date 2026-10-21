package com.stethoscore.app.data

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.ceil
import kotlin.math.pow
import kotlin.math.roundToInt

// Ported from ios/RedPen/Shared/Learn/RetentionForecast.swift. Dates are
// epoch milliseconds; a calendar is a time zone. Tested by LearnTest.

/**
 * How much of the deck the student would remember on exam day, and how many
 * reviews it takes to get that to 90%.
 *
 * A card's interval stands in for its stability: the number of days after
 * which it is still recalled nine times in ten. Recall then fades on the
 * power curve FSRS uses, R = (1 + t / 9S)^-1, so R is exactly 0.9 when t
 * equals S. A card forgotten again and again is less stable than its
 * interval says, so each lapse takes a little off.
 *
 * It is an estimate from one scheduler's intervals, not a measurement, and
 * the screens say so.
 */
object RetentionForecast {
    /** The recall aimed for on exam day. */
    const val target: Double = 0.9
    /** Each lapse leaves a card this much of its stability. */
    const val lapseFactor: Double = 0.85
    /** Never less stable than this, in days (about 15 minutes). */
    const val floorDays: Double = 0.01
    /** A review simulation never plans more than this many for one card. */
    const val maxPlanned = 24

    private const val dayMs = 86_400_000L

    /** One card's stability in days. */
    fun stabilityDays(record: ReviewRecord): Double {
        val days = record.intervalMin / ExamCap.day
        val kept = lapseFactor.pow(maxOf(0, record.lapses).toDouble())
        return maxOf(floorDays, days * kept)
    }

    /** Recall after [elapsedDays] for a card of stability [stability]. */
    fun recall(elapsedDays: Double, stability: Double): Double {
        val t = maxOf(0.0, elapsedDays)
        val s = maxOf(floorDays, stability)
        return 1 / (1 + t / (9 * s))
    }

    /** One card's recall at [date]. Null for a card never rated. */
    fun recall(record: ReviewRecord?, date: Long): Double? {
        if (record == null || record.reviews <= 0) return null
        val elapsed = (date - record.ratedAt) / 86_400_000.0
        return recall(elapsed, stabilityDays(record))
    }

    /** The whole forecast. */
    data class Forecast(
        /** Cards rated at least once, which the percentages are about. */
        val studied: Int,
        /** Cards never rated. */
        val unseen: Int,
        /** Average recall of the studied cards now, 0...1. */
        val today: Double,
        /** Average recall on exam day if nothing more were done. */
        val onExamDay: Double,
        /** Reviews that would bring every studied card to the target on the day. */
        val reviewsNeeded: Int,
        /** Whole days left to do them in, at least 1. */
        val days: Int,
    ) {
        val perDay: Int get() = if (reviewsNeeded == 0) 0 else ceil(reviewsNeeded.toDouble() / maxOf(1, days)).toInt()
        /** Whether the exam-day recall is already at the target. */
        val onCourse: Boolean get() = studied > 0 && onExamDay >= target
    }

    /** The forecast for [cardIDs] against [exam] (null forecasts for today only, with no review plan). */
    fun forecast(cardIDs: List<String>, records: Map<String, ReviewRecord>, now: Long, exam: Long?): Forecast {
        val whenAt = exam?.let { if (it > now) it else now } ?: now
        var studied = 0
        var unseen = 0
        var needed = 0
        var sumToday = 0.0
        var sumExam = 0.0
        for (id in cardIDs) {
            val record = records[id]
            if (record == null || record.reviews <= 0) {
                unseen += 1
                continue
            }
            studied += 1
            sumToday += recall(record, now) ?: 0.0
            sumExam += recall(record, whenAt) ?: 0.0
            if (exam != null) needed += reviewsToTarget(record, now, whenAt)
        }
        val n = maxOf(1, studied).toDouble()
        val seconds = (whenAt - now) / 1000.0
        val days = maxOf(1, ceil(seconds / 86_400).toInt())
        return Forecast(studied, unseen,
            if (studied == 0) 0.0 else sumToday / n,
            if (studied == 0) 0.0 else sumExam / n,
            needed, days)
    }

    /**
     * How many reviews one card needs before [exam] for its recall on the
     * day to reach the target, reviewing it when it falls due (never after
     * the exam's cap) and assuming each is answered "Good".
     */
    fun reviewsToTarget(record: ReviewRecord, now: Long, exam: Long): Int {
        var interval = record.intervalMin
        var stability = stabilityDays(record)
        var last = record.ratedAt
        var due = maxOf(record.due, now)
        var count = 0
        while (count < maxPlanned) {
            val gap = (exam - last) / 86_400_000.0
            if (gap <= stability) return count
            // the review, when it falls due - but never later than the day before the exam
            val latest = maxOf(now, exam - dayMs)
            val at = minOf(due, latest)
            val next = AnkiScheduler.nextInterval(AnkiRating.GOOD, interval)
            // what the review earned is the whole interval; the cap only
            // brings the next sitting forward, it does not weaken the memory
            stability = maxOf(floorDays, next / ExamCap.day)
            interval = ExamCap.capped(next, at, exam)
            last = at
            due = at + (interval * 60_000).toLong()
            count += 1
        }
        return count
    }

    /** Cards falling due on each of the next [days] days (index 0 is today, counting everything overdue). */
    fun dueByDay(cardIDs: List<String>, records: Map<String, ReviewRecord>, now: Long, days: Int,
                 zone: ZoneId = ZoneId.systemDefault()): List<Int> {
        if (days <= 0) return emptyList()
        val out = IntArray(days)
        val start = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        for (id in cardIDs) {
            val record = records[id]
            if (record == null) {
                out[0] += 1
                continue
            }
            val offset = ChronoUnit.DAYS.between(start, Instant.ofEpochMilli(record.due).atZone(zone).toLocalDate()).toInt()
            val slot = maxOf(0, offset)
            if (slot < days) out[slot] += 1
        }
        return out.toList()
    }

    /** "71%". */
    fun percent(x: Double): String = "${(minOf(1.0, maxOf(0.0, x)) * 100).roundToInt()}%"
}
