package com.stethoscore.app.data

import org.junit.Assert.*
import org.junit.Test

class AnkiSchedulerTest {
    @Test fun goodGraduatesAtTenMinutes() {
        assertEquals(10.0, AnkiScheduler.nextInterval(AnkiRating.GOOD, 0.0), 0.0)
        assertEquals(1440.0, AnkiScheduler.nextInterval(AnkiRating.GOOD, 10.0), 0.0)
        assertEquals(3600.0, AnkiScheduler.nextInterval(AnkiRating.GOOD, 1440.0), 0.0)
        assertEquals(1.0, AnkiScheduler.nextInterval(AnkiRating.AGAIN, 3600.0), 0.0)
    }
    @Test fun hardAndEasyMatchUpstreamIntervals() {
        assertEquals(5.0, AnkiScheduler.nextInterval(AnkiRating.HARD, 0.0), 0.0)
        assertEquals(12.0, AnkiScheduler.nextInterval(AnkiRating.HARD, 10.0), 0.0)
        assertEquals(5760.0, AnkiScheduler.nextInterval(AnkiRating.EASY, 0.0), 0.0)
    }
    @Test fun runawayIntervalsAreFiniteAndPrintable() {
        assertEquals(AnkiScheduler.maxIntervalMin, AnkiScheduler.nextInterval(AnkiRating.EASY, Double.POSITIVE_INFINITY), 0.0)
        assertEquals("36500 d", AnkiScheduler.formatInterval(Double.NaN))
        assertEquals(1.0, AnkiScheduler.nextInterval(AnkiRating.AGAIN, Double.NaN), 0.0)
    }
    @Test fun earlyReviewsDoNotMultiplyFullEarnedInterval() {
        val now = 1_000_000L
        val fourDays = 5760.0
        val kept = ReviewRecord(now + (3 * 1440 * 60000L), fourDays, reviews = 1, ratedAt = now - 86400000)
        assertEquals(fourDays, ReviewPlan.earned(AnkiRating.EASY, kept, now), 0.0)
        assertEquals(fourDays, ReviewPlan.earned(AnkiRating.GOOD, kept, now), 0.0)
        assertEquals(fourDays * 0.6, ReviewPlan.earned(AnkiRating.HARD, kept, now), 0.0)
    }
    @Test fun examCapAndPreviewsMatchPersistedSchedule() {
        val now = 1_000_000L
        val exam = now + 3 * 86400000L
        val record = ReviewRecord(now, 14400.0)
        val next = ReviewPlan.after(AnkiRating.EASY, record, now, exam)
        assertEquals(1.5 * 1440, next.intervalMin, 0.0)
        assertEquals("in " + AnkiScheduler.formatInterval(next.intervalMin), ReviewPlan.previewLabels(record, now, exam)[AnkiRating.EASY])
        assertEquals(10.0, ExamCap.capped(10.0, now, now + 60000), 0.0)
        assertEquals(5760.0, ExamCap.capped(5760.0, now, now - 1), 0.0)
    }
    @Test fun lapseCountsAndIntroductionSurviveRatings() {
        val one = ReviewPlan.after(AnkiRating.EASY, ReviewRecord(100, 0.0), now = 100)
        val two = ReviewPlan.after(AnkiRating.AGAIN, one, now = 200)
        assertEquals(2, two.reviews); assertEquals(1, two.lapses)
        assertEquals(100L, two.introducedAt); assertEquals(60200L, two.due)
    }

    // the time under each rating's word, for the same card states as iOS's ScheduleTests
    // ("the rating faces"): the same inputs give the same strings on both platforms
    @Test fun ratingFacesMatchIos() {
        val expected = linkedMapOf(
            0.0 to listOf("1 min", "5 min", "10 min", "4 d"),
            10.0 to listOf("1 min", "12 min", "1 d", "4 d"),
            60.0 to listOf("1 min", "1 hr", "1 d", "4 d"),
            1440.0 to listOf("1 min", "1 d", "3 d", "4 d"),
            5760.0 to listOf("1 min", "5 d", "10 d", "16 d"),
        )
        for ((current, faces) in expected) {
            val labels = AnkiScheduler.previewLabels(current, 1_700_000_000_000L, exam = null)
            assertEquals("labels at $current", faces.map { "in $it" }, AnkiRating.entries.map { labels[it] })
            assertEquals("faces at $current", faces, AnkiRating.entries.map { CardReview.bareInterval(labels[it] ?: "") })
        }
    }
}
