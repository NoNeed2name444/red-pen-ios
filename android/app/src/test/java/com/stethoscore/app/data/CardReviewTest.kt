package com.stethoscore.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

/** The card review screens' words and sitting rules, as iOS's views state them (dcb4745). */
class CardReviewTest {
    private val now = 1_700_000_000_000L
    private fun card(front: String, type: AnkiCardType = AnkiCardType.QA) = AnkiCard(type = type, front = front, bullets = listOf("answer"))

    @Test fun clozeSentencesSplitAtTheirGaps() {
        val pieces = CardReview.clozePieces("The {{c1::aorta}} leaves the {{c2::left ventricle::chamber}}.")
        assertEquals(listOf(
            ClozePiece("The ", false), ClozePiece("aorta", true), ClozePiece(" leaves the ", false),
            ClozePiece("left ventricle", true, "chamber"), ClozePiece(".", false),
        ), pieces)
        assertEquals("[...]", CardReview.clozeGap(pieces[1]))
        assertEquals("[chamber]", CardReview.clozeGap(pieces[3]))
        assertEquals("The blank leaves the blank, hint: chamber.", CardReview.clozeSpoken("The {{c1::aorta}} leaves the {{c2::left ventricle::chamber}}.", false))
        assertEquals("The aorta leaves the left ventricle.", CardReview.clozeSpoken("The {{c1::aorta}} leaves the {{c2::left ventricle::chamber}}.", true))
        assertEquals(listOf(ClozePiece("no gaps", false)), CardReview.clozePieces("no gaps"))
    }

    @Test fun theFaceSaysWhatKindOfCardItIs() {
        assertEquals("Question", CardReview.badge(AnkiCardType.QA))
        assertEquals("Fill in the gap", CardReview.badge(AnkiCardType.CLOZE))
        assertEquals("What is hidden?", CardReview.badge(AnkiCardType.OCCLUSION))
        assertEquals("Answer: x is y. z", CardReview.spokenBack(AnkiCard(front = "q", bullets = listOf("**x** is y", "z"))))
        assertEquals("Answer: The aorta", CardReview.spokenBack(AnkiCard(type = AnkiCardType.CLOZE, clozeText = "The {{c1::aorta::vessel}}")))
        assertEquals("Answer shown.", CardReview.spokenBack(AnkiCard(front = "q")))
        assertEquals(listOf("A " to false, "bold" to true, " word" to false), CardReview.boldRuns("A **bold** word"))
    }

    @Test fun theRatingsSpeakPlainly() {
        assertEquals(listOf("I forgot it", "I just about got it", "I got it", "Too easy"), AnkiRating.entries.map(CardReview::meaning))
        assertEquals(listOf("Again", "Hard", "Good", "Easy"), AnkiRating.entries.map(CardReview::title))
        assertEquals("4 days", CardReview.spokenInterval("in 4 d"))
        assertEquals("1 minute", CardReview.spokenInterval("1 min"))
        assertEquals("Good, back in 2 hours", CardReview.spokenRating(AnkiRating.GOOD, "in 2 hr"))
        assertEquals("Again", CardReview.spokenRating(AnkiRating.AGAIN, ""))
    }

    @Test fun headersAndFinishesUseTheSameWords() {
        assertEquals(CardReview.Header("3 cards left", "2 done", 0.4), CardReview.deckHeader(3, 2, false))
        assertEquals(CardReview.Header("1 card left", "0 done · studying ahead", 0.0), CardReview.deckHeader(1, 0, true))
        // nothing was due: "No cards due" and no "0 done" beside it; after a sitting, "All done" with its count
        assertEquals(CardReview.Header("No cards due", "", 0.0), CardReview.deckHeader(0, 0, false))
        assertEquals(CardReview.Header("No cards due", "", 0.0), CardReview.dueHeader(0, 0))
        assertEquals(CardReview.Header("All done", "3 done", 1.0), CardReview.deckHeader(0, 3, false))
        assertEquals(CardReview.Header("All done", "2 done", 1.0), CardReview.dueHeader(0, 2))
        assertEquals(CardReview.Header("1 card due", "1 done", 0.5), CardReview.dueHeader(1, 1))
        assertEquals("No cards due", CardReview.dueHeader(0, 0).status)
        assertEquals("Next card back in 10 min.", CardReview.nextLine(now + 10 * 60_000, now))
        assertEquals("Everything here has been seen.", CardReview.nextLine(null, now))
        assertEquals("Everything here has been seen.", CardReview.nextLine(now - 1, now))
        assertEquals("You went through 1 card. Everything here has been seen.", CardReview.doneLine(1, "Everything here has been seen."))
        assertEquals("You went through 12 cards. Next card back in 10 min.", CardReview.doneLine(12, "Next card back in 10 min."))
        assertEquals("Open a deck to study ahead.", CardReview.dueEmptyLine(0))
        assertEquals("2 cards reviewed across your decks.", CardReview.dueEmptyLine(2))
    }

    @Test fun aSittingKeepsWhatIsDueAgainSoon() {
        val a = card("a"); val b = card("b")
        val queue = listOf(AnkiQueueItem(a, now - 2, 0.0), AnkiQueueItem(b, now - 1, 0.0))
        val again = ReviewPlan.after(AnkiRating.AGAIN, ReviewPlan.record(a, emptyMap(), now), now)
        val kept = CardReview.afterRating(queue, queue[0], again)
        assertEquals("Again comes back in this sitting, behind what is already waiting", listOf(b.id, a.id), kept.map { it.id })
        val easy = ReviewPlan.after(AnkiRating.EASY, ReviewPlan.record(a, emptyMap(), now), now)
        assertEquals("Easy leaves the sitting", listOf(b.id), CardReview.afterRating(queue, queue[0], easy).map { it.id })
        val good = ReviewPlan.after(AnkiRating.GOOD, ReviewPlan.record(a, emptyMap(), now), now)
        assertEquals("ten minutes is inside the sitting", 2, CardReview.afterRating(queue, queue[0], good).size)
        val undone = CardReview.afterUndo(listOf(AnkiQueueItem(b, now, 0.0)), a, 0.0)
        assertEquals("an undone card goes back in front", listOf(a.id, b.id), undone.map { it.id })
        val due = listOf(ReviewPlan.Due("s", "Set", a, now - 2), ReviewPlan.Due("s", "Set", b, now - 1))
        assertEquals(listOf(b.id, a.id), CardReview.afterRating(due, due[0], again).map { it.card.id })
        assertEquals(listOf(b.id), CardReview.afterRating(due, due[0], easy).map { it.card.id })
    }

    @Test fun occlusionCoversHideEveryOtherLabelButTheAnswer() {
        val target = OcclusionBox(0.1, 0.1, 0.2, 0.1)
        val same = OcclusionBox(0.11, 0.1, 0.2, 0.1)
        val other = OcclusionBox(0.6, 0.6, 0.2, 0.1)
        val asked = AnkiCard(type = AnkiCardType.OCCLUSION, imageIndex = 0, occlusion = target)
        val deck = listOf(asked, AnkiCard(type = AnkiCardType.OCCLUSION, imageIndex = 0, occlusion = other), AnkiCard(type = AnkiCardType.OCCLUSION, imageIndex = 0, occlusion = same), AnkiCard(type = AnkiCardType.OCCLUSION, imageIndex = 1, occlusion = OcclusionBox(0.0, 0.0, 0.1, 0.1)))
        assertEquals("an older card takes its neighbours' masks, never one over its own label", listOf(other), OcclusionCovers.others(asked, deck))
        assertEquals("a card that carries its siblings uses them", listOf(other), OcclusionCovers.others(asked.copy(siblings = listOf(other, other)), emptyList()))
        val r = OcclusionCovers.rect(OcclusionBox(0.5, 0.5, 0.001, 0.001), 200.0, 100.0)!!
        assertTrue("a box OCR made too small is drawn at least six across", r.w >= 6 && r.h >= 6)
        val edge = OcclusionCovers.rect(OcclusionBox(0.95, 0.0, 0.2, 0.1), 200.0, 100.0)!!
        assertEquals("a cover stays on the picture", 200.0, edge.x + edge.w, 1e-9)
        assertNull(OcclusionCovers.rect(target, 0.0, 100.0))
    }

    @Test fun theStoreUndoesBuriesAndSuspendsAsIOSDoes() {
        val dir = Files.createTempDirectory("cards").toFile()
        try {
            val store = StudyStore(dir)
            val a = card("a"); val b = card("b")
            val set = StudySet(name = "Deck", kind = StudySetKind.ANKI, cards = listOf(a, b))
            store.addSet(set)
            store.rateCard(a, AnkiRating.EASY, now)
            assertEquals(1, store.queue(set, now).size)
            val undone = store.undoLast(now + 5_000)
            assertEquals("undo names the card it took back", a.id, undone?.cardId)
            assertEquals("and leaves a never-rated card, stamped so a merge keeps the undo", now + 5_000, store.reviews.getValue(a.id).changedAt)
            assertEquals(2, store.queue(set, now + 5_000).size)
            assertNull("one step, as in Anki", store.undoLast())
            store.rateCard(b, AnkiRating.GOOD, now)
            store.buryCard(b, now)
            assertNull("burying the card just rated drops its undo", store.lastRating)
            store.suspendCard(a, now = now)
            assertEquals(1, store.suspendedCount)
            assertTrue(store.queue(set, now + 60_000).isEmpty())
            assertEquals("study ahead skips the suspended card", listOf(b.id), store.everything(set, now).map { it.id })
            store.unsuspendAll(now + 1)
            assertEquals(0, store.suspendedCount)
            assertEquals(listOf(a.id), store.dueAcross(now + 10_000).map { it.card.id })
        } finally { dir.deleteRecursively() }
    }
}
