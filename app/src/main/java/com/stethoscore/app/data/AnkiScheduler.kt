package com.stethoscore.app.data

import kotlin.math.roundToLong

enum class AnkiRating(val label: String) { AGAIN("Again"), HARD("Hard"), GOOD("Good"), EASY("Easy") }

data class ReviewRecord(
    val due: Long, val intervalMin: Double, val reviews: Int = 0, val lapses: Int = 0,
    val ratedAt: Long = System.currentTimeMillis(), val suspended: Boolean = false,
    val buriedUntil: Long? = null, val stability: Double? = null, val difficulty: Double? = null,
    val introducedAt: Long? = null, val changedAt: Long? = null, val rawJson: String = "{}"
) { val mergeStamp: Long get() = maxOf(ratedAt, changedAt ?: ratedAt) }

/** Port of ios/RedPen/Features/Anki/AnkiScheduler.swift at be11a56. */
object AnkiScheduler {
    const val maxIntervalMin: Double = 36_500.0 * 1440
    const val graduatingMin: Double = 1440.0
    val baseMinutes = mapOf(AnkiRating.AGAIN to 1.0, AnkiRating.HARD to 5.0, AnkiRating.GOOD to 10.0, AnkiRating.EASY to 5760.0)
    fun nextInterval(rating: AnkiRating, currentIntervalMin: Double): Double {
        val cur = if (currentIntervalMin.isFinite()) currentIntervalMin else maxIntervalMin
        val next = when (rating) {
            AnkiRating.AGAIN -> 1.0
            AnkiRating.HARD -> maxOf(5.0, cur * 1.2)
            AnkiRating.GOOD -> if (cur >= 10 && cur < graduatingMin) graduatingMin else maxOf(10.0, cur * 2.5)
            AnkiRating.EASY -> maxOf(5760.0, cur * 4)
        }
        return minOf(maxIntervalMin, next)
    }
    fun formatInterval(minutes: Double): String {
        val m = if (minutes.isFinite()) minutes.coerceIn(1.0, maxIntervalMin) else maxIntervalMin
        return when { m < 60 -> "${m.roundToLong()} min"; m < 1440 -> "${(m / 60).roundToLong()} hr"; else -> "${(m / 1440).roundToLong()} d" }
    }
    fun previewLabels(currentIntervalMin: Double, now: Long = System.currentTimeMillis(), exam: Long? = null): Map<AnkiRating, String> = AnkiRating.entries.associateWith { "in " + formatInterval(ExamCap.capped(nextInterval(it, currentIntervalMin), now, exam)) }
}

object ExamCap {
    const val day = 1440.0
    fun capped(minutes: Double, now: Long, exam: Long?): Double {
        if (exam == null) return minutes
        val untilExam = (exam - now) / 60000.0
        if (untilExam <= 0 || minutes < day || minutes <= untilExam - day) return minutes
        val lead = minOf(2 * day, untilExam / 2)
        return maxOf(10.0, minOf(minutes, untilExam - lead))
    }
}

/** Includes the current iOS early-review protection and exam cap. */
object ReviewPlan {
    fun earned(rating: AnkiRating, record: ReviewRecord, now: Long): Double {
        val plain = AnkiScheduler.nextInterval(rating, record.intervalMin)
        val remaining = (record.due - now) / 60000.0
        if (rating == AnkiRating.AGAIN || remaining <= 0 || record.intervalMin < ExamCap.day) return plain
        val elapsed = maxOf(0.0, record.intervalMin - remaining)
        val grown = AnkiScheduler.nextInterval(rating, elapsed)
        val floor = if (rating == AnkiRating.HARD) record.intervalMin * 0.6 else record.intervalMin
        return minOf(AnkiScheduler.maxIntervalMin, maxOf(grown, floor))
    }
    fun after(rating: AnkiRating, record: ReviewRecord, now: Long = System.currentTimeMillis(), exam: Long? = null): ReviewRecord {
        val next = ExamCap.capped(earned(rating, record, now), now, exam)
        return ReviewRecord(due = now + (next * 60000).toLong(), intervalMin = next, reviews = record.reviews + 1, lapses = record.lapses + if (rating == AnkiRating.AGAIN) 1 else 0, ratedAt = now, suspended = record.suspended, introducedAt = if (record.reviews == 0) now else record.introducedAt, rawJson = record.rawJson)
    }
    fun previewLabels(record: ReviewRecord, now: Long = System.currentTimeMillis(), exam: Long? = null): Map<AnkiRating, String> = AnkiRating.entries.associateWith { "in " + AnkiScheduler.formatInterval(ExamCap.capped(earned(it, record, now), now, exam)) }
    fun isAvailable(record: ReviewRecord?, now: Long): Boolean = record == null || (!record.suspended && (record.buriedUntil ?: 0) <= now && record.due <= now)
}
