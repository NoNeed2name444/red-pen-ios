package com.stethoscore.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Port of ios/RedPen/Tests/ScheduleTests.swift at dcb4745, check for check, on the same
 * clock (1_700_000_000 s). Left out: AnkiScheduleRow and AnkiExportPicture, the .apkg
 * export's rows, which belong to the export port, not the review screens.
 */
class ScheduleTest {
    private class Deck(override val deckName: String, override val deckCards: List<AnkiCard>, override val deckId: String = newId()) : ReviewDeck

    private fun card(front: String) = AnkiCard(type = AnkiCardType.QA, front = front, bullets = listOf("answer"))
    private val now = 1_700_000_000_000L
    private val sec = 1000L
    private val dayMin = 1440.0
    private val lupus = card("malar rash")
    private val renal = card("renal artery")
    private val cards = listOf(lupus, renal)
    private fun newRecord(at: Long = now) = ReviewRecord(due = at, intervalMin = 0.0, ratedAt = at)
    private val rated: Map<String, ReviewRecord> get() = mapOf(lupus.id to ReviewPlan.after(AnkiRating.EASY, ReviewPlan.record(lupus, emptyMap(), now), now))

    @Test fun aDeckNobodyHasTouched() {
        assertTrue("a brand new card is due at once", ReviewPlan.isDue(lupus, emptyMap(), now))
        assertEquals("so a freshly generated deck is reviewable immediately", 2, ReviewPlan.queue(cards, emptyMap(), now).size)
    }

    @Test fun afterARating() {
        val records = rated
        assertTrue("easy puts a card days away", records.getValue(lupus.id).intervalMin >= 4 * dayMin)
        assertFalse("and it is not due an hour later", ReviewPlan.isDue(lupus, records, now + 3600 * sec))
        assertFalse("nor the next day", ReviewPlan.isDue(lupus, records, now + 86_400 * sec))
        assertTrue("and it IS due once the interval is up", ReviewPlan.isDue(lupus, records, now + 5 * 86_400 * sec))
        assertTrue("the card nobody rated is still waiting", ReviewPlan.isDue(renal, records, now))
        val queue = ReviewPlan.queue(cards, records, now)
        assertEquals("a queue holds only what is due", 1, queue.size)
        assertEquals("and it is the right card", renal.id, queue.first().card.id)
    }

    @Test fun againAndTheCounters() {
        val lapsed = ReviewPlan.after(AnkiRating.AGAIN, rated.getValue(lupus.id), now)
        assertEquals("again brings it straight back", 1.0, lapsed.intervalMin, 0.0)
        assertEquals("and is counted as a lapse", 1, lapsed.lapses)
        assertEquals("a rating is counted either way", 2, lapsed.reviews)
        assertEquals("a card you get right is not a lapse", 1, ReviewPlan.after(AnkiRating.GOOD, lapsed, now).lapses)
    }

    @Test fun studyingAhead() {
        val ahead = ReviewPlan.everything(cards, rated, now)
        assertEquals("studying ahead offers the whole deck", 2, ahead.size)
        assertTrue("and a card keeps the interval it earned", ahead.first { it.card.id == lupus.id }.intervalMin >= 4 * dayMin)

        // Easy on Monday, then Easy again each day while studying ahead, used to be 4 days, 16, 64, 256
        val monday = now
        var ahead4 = ReviewPlan.after(AnkiRating.EASY, newRecord(monday), monday)
        for (day in 1..3) ahead4 = ReviewPlan.after(AnkiRating.EASY, ahead4, monday + day * 86_400 * sec)
        val thursday = monday + 3 * 86_400 * sec
        assertTrue("studying ahead every day does not compound the interval", ahead4.intervalMin <= 4 * dayMin + 1)
        assertTrue("so a card seen on Thursday is back within days", ahead4.due - thursday <= (4 * 86_400 + 60) * sec)

        val earnedMonth = ReviewRecord(due = now + 28 * 86_400 * sec, intervalMin = 30 * dayMin, reviews = 4, lapses = 0, ratedAt = now - 2 * 86_400 * sec)
        val earlyGood = ReviewPlan.after(AnkiRating.GOOD, earnedMonth, now)
        assertTrue("an early Good never shortens the interval a card had earned", earlyGood.intervalMin >= earnedMonth.intervalMin)
        assertTrue("and does not multiply it as if the month had passed", earlyGood.intervalMin < 30 * dayMin * 2.5)
        val earlyHard = ReviewPlan.after(AnkiRating.HARD, earnedMonth, now)
        assertTrue("an early Hard brings it closer, by at most 40%", earlyHard.intervalMin >= 0.6 * 30 * dayMin - 1 && earlyHard.intervalMin <= 30 * dayMin)
        val earlyAgain = ReviewPlan.after(AnkiRating.AGAIN, earnedMonth, now)
        assertTrue("an early Again is still a lapse", earlyAgain.intervalMin == 1.0 && earlyAgain.lapses == 1)
        assertEquals("rated when due, the interval grows as before", 75 * dayMin, ReviewPlan.after(AnkiRating.GOOD, earnedMonth, earnedMonth.due).intervalMin, 0.0)

        val stepped = ReviewPlan.after(AnkiRating.GOOD, newRecord(), now)
        val steppedAgain = ReviewPlan.after(AnkiRating.GOOD, stepped, now + 60 * sec)
        assertEquals("a learning step shown early still moves on, out of learning", AnkiScheduler.graduatingMin, steppedAgain.intervalMin, 0.0)
        assertEquals("Good graduates a card on its last learning step", listOf(10.0, 1440.0, 3600.0), listOf(0.0, 10.0, 1440.0).map { AnkiScheduler.nextInterval(AnkiRating.GOOD, it) })
        assertTrue("Hard on a learning step stays a learning step", AnkiScheduler.nextInterval(AnkiRating.HARD, 10.0) < 1440)

        val promisedEarly = ReviewPlan.previewLabels(earnedMonth, now, null)
        assertEquals("an early review's buttons promise what it will store", "in " + AnkiScheduler.formatInterval(earlyGood.intervalMin), promisedEarly[AnkiRating.GOOD])
        val examSoon = now + 10 * 86_400 * sec
        assertTrue("the exam cap still applies to an early review", ReviewPlan.after(AnkiRating.EASY, earnedMonth, now, examSoon).due < examSoon)
    }

    @Test fun noRunawayIntervals() {
        var runaway = newRecord()
        var clock = now
        repeat(60) { runaway = ReviewPlan.after(AnkiRating.EASY, runaway, clock); clock = runaway.due }
        assertTrue("sixty Easy ratings stop at the ceiling", runaway.intervalMin <= AnkiScheduler.maxIntervalMin)
        assertEquals("and the label for it does not crash", "36500 d", AnkiScheduler.formatInterval(runaway.intervalMin))
        assertEquals("nor for an interval already stored out of range", "36500 d", AnkiScheduler.formatInterval(1e30))
        assertEquals("36500 d", AnkiScheduler.formatInterval(Double.POSITIVE_INFINITY))
        assertEquals("the buttons for a runaway card do not crash", "in 36500 d", AnkiScheduler.previewLabels(1e300, exam = null)[AnkiRating.EASY])
    }

    @Test fun theWholeLibraryAtOnce() {
        val records = rated
        val anatomy = Deck("Anatomy", listOf(card("femoral triangle")))
        val immunology = Deck("Immunology", cards)
        val everything = ReviewPlan.dueAcross(listOf(anatomy, immunology), records, now)
        assertEquals("the day's queue spans every deck", 2, everything.size)
        assertEquals("and each card remembers which deck it came from", setOf("Anatomy", "Immunology"), everything.map { it.setName }.toSet())
        assertTrue("a deck with nothing due contributes nothing", ReviewPlan.dueAcross(listOf(Deck("Done", listOf(lupus))), records, now).isEmpty())
        assertTrue("an empty library is not an error", ReviewPlan.dueAcross(emptyList<Deck>(), records, now).isEmpty())
        val copied = Deck("Immunology (from another device)", cards)
        val twice = ReviewPlan.dueAcross(listOf(immunology, copied), records, now)
        assertTrue("the same card in two decks is two distinct rows", twice.map { it.id }.toSet().size == twice.size && twice.size == 2)
        assertEquals("and removing one leaves the other", 1, twice.filterNot { it.id == twice.first().id }.size)

        assertNotNull("a card still in a deck keeps its place", ReviewPlan.pruned(records, listOf(immunology))[lupus.id])
        assertTrue("a deleted card's schedule is dropped", ReviewPlan.pruned(records, listOf(anatomy)).isEmpty())
    }

    @Test fun whatTheButtonsPromiseIsWhatGetsStored() {
        for (rating in AnkiRating.entries) {
            val start = ReviewRecord(due = now, intervalMin = 30.0, ratedAt = now)
            val after = ReviewPlan.after(rating, start, now)
            val promised = AnkiScheduler.nextInterval(rating, 30.0)
            assertEquals("$rating stores the interval its button promised", promised, after.intervalMin, 0.0)
            assertTrue("$rating sets the due date to match the interval", abs((after.due - now) - promised * 60_000) < 1)
        }
    }

    @Test fun twoDevicesOneSchedule() {
        val morning = mapOf(lupus.id to ReviewRecord(due = now + 3600 * sec, intervalMin = 60.0, reviews = 1, lapses = 0, ratedAt = now))
        val afternoon = mapOf(renal.id to ReviewRecord(due = now + 7200 * sec, intervalMin = 120.0, reviews = 1, lapses = 0, ratedAt = now + 3600 * sec))
        assertEquals("both sittings survive a merge", 2, ReviewPlan.merging(morning, afternoon).size)
        val laterSame = mapOf(lupus.id to ReviewRecord(due = now + 86_400 * sec, intervalMin = 1440.0, reviews = 2, lapses = 0, ratedAt = now + 600 * sec))
        assertEquals("the later rating of the same card wins", 1440.0, ReviewPlan.merging(morning, laterSame).getValue(lupus.id).intervalMin, 0.0)
        assertEquals("and an older one does not overwrite a newer", 1440.0, ReviewPlan.merging(laterSame, morning).getValue(lupus.id).intervalMin, 0.0)
        assertEquals("merging with nothing changes nothing", morning, ReviewPlan.merging(morning, emptyMap()))
    }

    @Test fun nextDueIsTheSoonestStoredCard() {
        assertNull("a deck nobody rated has no next card", ReviewPlan.nextDue(cards, emptyMap()))
        assertEquals(rated.getValue(lupus.id).due, ReviewPlan.nextDue(cards, rated))
    }
}
