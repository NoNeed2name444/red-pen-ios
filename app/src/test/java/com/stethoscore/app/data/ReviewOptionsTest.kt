package com.stethoscore.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.math.abs
import kotlin.math.exp

/** Ports of ios/RedPen/Tests/ReviewEssentialsTests.swift (FSRS, the study day, limits, holds). */
class ReviewOptionsTest {
    private val utc: ZoneId = ZoneOffset.UTC
    private val now = 1_700_000_000_000L // 2023-11-14 22:13:20 UTC
    private val day = 86_400_000L
    private fun near(a: Double, b: Double, tol: Double = 1e-3) = abs(a - b) <= tol
    private fun card(front: String) = AnkiCard(type = AnkiCardType.QA, front = front, bullets = listOf("answer"))
    private val fresh get() = ReviewRecord(due = now, intervalMin = 0.0, ratedAt = now)

    @Test fun fsrsCurveAndFirstRatings() {
        assertTrue(near(FSRS.retrievability(10.0, 10.0), 0.9))
        assertTrue(near(FSRS.intervalDays(7.5), 7.5, 1e-6))
        assertTrue(near(FSRS.initialStability(3), 3.173))
        assertTrue(FSRS.initialDifficulty(1) > FSRS.initialDifficulty(3) && FSRS.initialDifficulty(3) > FSRS.initialDifficulty(4))
        assertTrue(near(FSRS.initialDifficulty(3), 7.1949 - exp(2 * 0.5345) + 1))
    }

    @Test fun fsrsLaterRatings() {
        val s0 = FSRS.State(10.0, 5.0)
        val good = FSRS.next(s0, 3, 10.0); val easy = FSRS.next(s0, 4, 10.0)
        val hard = FSRS.next(s0, 2, 10.0); val again = FSRS.next(s0, 1, 10.0)
        assertTrue(good.stability > 10)
        assertTrue(hard.stability < good.stability && good.stability < easy.stability)
        assertTrue(again.stability <= 10)
        assertTrue(again.difficulty > 5 && easy.difficulty < 5)
        assertTrue(FSRS.nextDifficulty(9.99, 1) in 1.0..10.0 && FSRS.nextDifficulty(1.0, 4) in 1.0..10.0)
        assertTrue(near(FSRS.next(s0, 3, 0.01).stability, 10 * exp(0.51655 * 0.6621), 1e-6))
        assertTrue(FSRS.next(s0, 3, 40.0).stability > good.stability)
    }

    @Test fun fsrsThroughTheSchedule() {
        val plan = ReviewOptions.fsrsPlan(fresh, now)
        assertEquals(1.0, plan.getValue(AnkiRating.AGAIN).minutes, 0.0)
        assertEquals(10.0, plan.getValue(AnkiRating.GOOD).minutes, 0.0)
        assertEquals(16.0 * 1440, plan.getValue(AnkiRating.EASY).minutes, 0.0)
        val first = ReviewOptions.after(AnkiRating.GOOD, fresh, now, null, ReviewScheduler.FSRS)
        assertNotNull(first.stability); assertNotNull(first.difficulty)
        assertEquals(now, first.introducedAt)
        val second = ReviewOptions.after(AnkiRating.GOOD, first, now + 600_000, null, ReviewScheduler.FSRS)
        assertTrue(second.intervalMin >= 1440)
        val later = now + (second.intervalMin * 60_000).toLong()
        val rp = ReviewOptions.fsrsPlan(second, later)
        val h = rp.getValue(AnkiRating.HARD).minutes; val g = rp.getValue(AnkiRating.GOOD).minutes; val e = rp.getValue(AnkiRating.EASY).minutes
        assertTrue(h < g && g < e)
        assertEquals(0.0, h % 1440, 0.0)
        val labels = ReviewOptions.previewLabels(second, later, null, ReviewScheduler.FSRS)
        val stored = ReviewOptions.after(AnkiRating.GOOD, second, later, null, ReviewScheduler.FSRS)
        assertEquals("in " + AnkiScheduler.formatInterval(stored.intervalMin), labels[AnkiRating.GOOD])
        val lapsed = ReviewOptions.after(AnkiRating.AGAIN, stored, later, null, ReviewScheduler.FSRS)
        assertEquals(stored.lapses + 1, lapsed.lapses); assertEquals(1.0, lapsed.intervalMin, 0.0)
        val exam = now + 5 * day
        assertTrue(ReviewOptions.after(AnkiRating.EASY, fresh, now, exam, ReviewScheduler.FSRS).due < exam)
        val classic = ReviewOptions.after(AnkiRating.GOOD, stored, stored.due, null, ReviewScheduler.CLASSIC)
        assertNull(classic.stability)
        assertEquals(maxOf(10.0, stored.intervalMin * 2.5), classic.intervalMin, 1e-6)
        val legacy = ReviewRecord(due = now, intervalMin = 4.0 * 1440, reviews = 3, lapses = 1, ratedAt = now - 4 * day)
        assertTrue(ReviewOptions.fsrsPlan(legacy, now).getValue(AnkiRating.GOOD).minutes > 4 * 1440)
    }

    @Test fun theStudyDayTurnsOverAtFour() {
        val start = ReviewDay.start(now, utc)
        assertEquals(4, Instant.ofEpochMilli(start).atZone(utc).hour)
        assertEquals(start, ReviewDay.start(1_700_020_000_000L, utc)) // 03:46 the next day
        assertEquals(start + day, ReviewDay.next(now, utc))
    }

    @Test fun dailyLimits() {
        val cards = (0 until 10).map { card("c$it") }
        val records = HashMap<String, ReviewRecord>()
        assertEquals(10, ReviewOptions.dailyQueue(cards, records, now, ReviewLimits.unlimited, zone = utc).size)
        val limits = ReviewLimits(newPerDay = 3, reviewsPerDay = 2)
        assertEquals(3, ReviewOptions.dailyQueue(cards, records, now, limits, zone = utc).size)
        for (c in cards.take(2)) records[c.id] = ReviewPlan.after(AnkiRating.EASY, fresh, now - 60_000, null)
        assertEquals(ReviewOptions.DayCounts(2, 0), ReviewOptions.counts(records, now, utc))
        assertEquals(1, ReviewOptions.dailyQueue(cards, records, now, limits, zone = utc).size)
        for (c in cards.subList(2, 6)) records[c.id] = ReviewRecord(due = now - day, intervalMin = 3.0 * 1440, reviews = 2, ratedAt = now - 4 * day)
        records[cards[6].id] = ReviewRecord(due = now - 60_000, intervalMin = 10.0, reviews = 1, ratedAt = now - 11 * 60_000)
        val q = ReviewOptions.dailyQueue(cards, records, now, limits, zone = utc)
        val reviewIds = cards.subList(2, 6).map { it.id }.toSet()
        assertEquals(2, q.count { it.id in reviewIds })
        assertTrue(q.any { it.id == cards[6].id })
        val deck = object : ReviewDeck { override val deckId = "cardio"; override val deckName = "Cardio"; override val deckCards = cards }
        assertEquals("Due today counts the same limits", q.size, ReviewOptions.dueToday(listOf(deck), records, now, limits, zone = utc).size)
        assertEquals(q.size, ReviewOptions.dueCount(cards, records, now, limits, zone = utc))
        assertEquals(ReviewOptions.dailyQueue(cards, records, now, ReviewLimits.unlimited).size, ReviewOptions.dueCount(cards, records, now, ReviewLimits.unlimited))
        assertEquals(1, ReviewOptions.dueCount(cards, records, now, limits, today = ReviewOptions.DayCounts(3, 2), zone = utc))
        assertEquals(q.size, ReviewOptions.dueCount(cards + listOf(card("x1"), card("x2")), records, now, limits, zone = utc))
    }

    @Test fun suspendAndBury() {
        val cards = (0 until 10).map { card("c$it") }
        val held = HashMap<String, ReviewRecord>()
        held[cards[2].id] = ReviewOptions.suspending(cards[2], true, held, now)
        held[cards[9].id] = ReviewOptions.burying(cards[9], held, now, utc)
        val q = ReviewOptions.dailyQueue(cards, held, now, ReviewLimits.unlimited)
        assertFalse("a suspended card leaves the queue", q.any { it.id == cards[2].id })
        assertFalse("a buried new card leaves the queue", q.any { it.id == cards[9].id })
        val tomorrow = ReviewDay.start(now, utc) + day + 60_000
        val next = ReviewOptions.dailyQueue(cards, held, tomorrow, ReviewLimits.unlimited)
        assertTrue("a buried card is back the next day", next.any { it.id == cards[9].id })
        assertFalse("a suspended card is still out the next day", next.any { it.id == cards[2].id })
        assertEquals("study ahead skips suspended cards only", 9, ReviewOptions.studyAhead(cards, held, now).size)
        val back = ReviewOptions.suspending(cards[2], false, held, now)
        assertTrue("unsuspending clears the flag", !back.suspended && !ReviewOptions.isHeld(back, now))
        assertTrue("rating a suspended card (study ahead) keeps it suspended", ReviewPlan.after(AnkiRating.GOOD, held.getValue(cards[2].id), now, null).suspended)
        assertTrue(ReviewOptions.after(AnkiRating.GOOD, held.getValue(cards[2].id), now, null, ReviewScheduler.FSRS).suspended)
    }

    @Test fun buryKeepsTheClockTimeAcrossAClockChange() {
        // London springs forward at 01:00 UTC on 31 March 2024: the study day after the 30th
        // starts at 04:00 on the clock, as iOS's calendar day added to today's start gives
        val london = ZoneId.of("Europe/London")
        val evening = Instant.parse("2024-03-30T20:00:00Z").toEpochMilli()
        val next = Instant.ofEpochMilli(ReviewDay.next(evening, london)).atZone(london)
        assertEquals(4, next.hour); assertEquals(31, next.dayOfMonth)
    }

    @Test fun oldSchedulesAndTheMerge() {
        val oldJson = """{"due":"2023-11-14T00:00:00Z","intervalMin":1440,"reviews":2,"lapses":0,"ratedAt":"2023-11-13T00:00:00Z"}"""
        val old = StudyJson.review(org.json.JSONObject(oldJson))
        assertTrue("a record written before these fields still decodes", !old.suspended && old.stability == null)
        val text = StudyJson.encodeReview(old).toString()
        assertTrue("an untouched record encodes without the new keys (no spurious sync): $text", !text.contains("suspended") && !text.contains("changedAt"))
        val cards = (0 until 4).map { card("c$it") }
        val c = cards[3]
        val before = ReviewRecord(due = now - day, intervalMin = 3.0 * 1440, reviews = 2, ratedAt = now - 4 * day)
        val rated = ReviewPlan.after(AnkiRating.GOOD, before, now, null)
        val undone = ReviewOptions.restoring(before, now + 5_000)
        assertTrue("an undo beats the rating it cancelled, whichever side has it",
            ReviewPlan.merging(mapOf(c.id to undone), mapOf(c.id to rated))[c.id] == undone && ReviewPlan.merging(mapOf(c.id to rated), mapOf(c.id to undone))[c.id] == undone)
        val suspendedThere = ReviewOptions.suspending(c, true, mapOf(c.id to rated), now + 30_000)
        assertTrue("a suspend on another device wins over an older rating", ReviewPlan.merging(mapOf(c.id to rated), mapOf(c.id to suspendedThere)).getValue(c.id).suspended)
        val ratedLater = ReviewPlan.after(AnkiRating.GOOD, rated, now + 60_000, null)
        assertEquals("a later rating still wins over an older suspend", ratedLater.ratedAt, ReviewPlan.merging(mapOf(c.id to suspendedThere), mapOf(c.id to ratedLater)).getValue(c.id).ratedAt)
        val firstUndo = ReviewOptions.restoring(null, now)
        assertTrue("undoing a first rating leaves a never-rated card, due now", firstUndo.reviews == 0 && firstUndo.due == now && ReviewOptions.stage(firstUndo) == ReviewOptions.Stage.NEW)
    }

    @Test fun flaggedCardsAreHeldOutOfReviewUntilCleared() {
        val held = AnkiCard(type = AnkiCardType.QA, front = "Antidote to heparin?", bullets = listOf("Vitamin K"))
        val fine = AnkiCard(type = AnkiCardType.QA, front = "Antidote to warfarin?", bullets = listOf("Vitamin K and PCC"))
        val at = System.currentTimeMillis()
        AccuracyHolds.reset()
        try {
            AccuracyHolds.update(held.id, flagged = true)
            assertEquals("a Flagged card is held out of today's queue", listOf(fine.id), ReviewOptions.dailyQueue(listOf(held, fine), emptyMap(), at, ReviewLimits.unlimited).map { it.card.id })
            assertEquals("and out of the due count", 1, ReviewOptions.dueCount(listOf(held, fine), emptyMap(), at, ReviewLimits.unlimited))
            AccuracyHolds.update(held.id, flagged = false)
            assertEquals("a fix or a re-check clears it, and it comes back", 2, ReviewOptions.dailyQueue(listOf(held, fine), emptyMap(), at, ReviewLimits.unlimited).size)
        } finally { AccuracyHolds.reset() }
    }

    @Test fun storeAppliesTheSettingsAndKeepsThem() {
        val dir = Files.createTempDirectory("review").toFile()
        val store = StudyStore(dir)
        assertEquals(ReviewSettings(), store.reviewSettings)
        store.setReviewSettings(ReviewSettings(ReviewScheduler.FSRS, ReviewLimits(newPerDay = 5, reviewsPerDay = -3)))
        assertEquals(ReviewLimits(5, 0), store.reviewSettings.limits)
        val reopened = StudyStore(dir)
        assertEquals(ReviewScheduler.FSRS, reopened.reviewSettings.scheduler)
        assertEquals(5, reopened.reviewSettings.limits.newPerDay)
        assertTrue(File(dir, "review-settings.json").exists())
        dir.deleteRecursively()
    }
}
