package com.stethoscore.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import kotlin.math.abs

// Picture cards, step by step (T0133): every label on a card's picture is
// masked; Reveal takes off only the one asked; a rating moves to the next
// card; the photo path (labels covered, a cover moved and one added, saved)
// ends in cards that review the same way; and all of it reads back after a
// relaunch. The steps' names match ios/RedPen/Tests/OcclusionFlowTests.swift.
// Android has no text reader yet, so its covers are the ones the student
// drags across each label: here, the heart example's eleven labels.
class OcclusionFlowTest {
    @get:Rule val folder = TemporaryFolder()

    private data class Label(val answer: String, val words: List<OcclusionBox>, val cover: OcclusionBox)

    /** The heart example's labels on its 900 x 640 drawing (22 pt, 25 pt pitch), each word's box and the cover dragged over them. */
    private val labels: List<Label> = listOf(
        Triple(listOf("Superior vena", "cava"), 190.0 to 70.0, true), Triple(listOf("Right atrium"), 190.0 to 245.0, true),
        Triple(listOf("Tricuspid valve"), 190.0 to 345.0, true), Triple(listOf("Right ventricle"), 190.0 to 440.0, true),
        Triple(listOf("Inferior vena", "cava"), 190.0 to 548.0, true), Triple(listOf("Aorta"), 700.0 to 58.0, false),
        Triple(listOf("Pulmonary", "trunk"), 700.0 to 150.0, false), Triple(listOf("Left atrium"), 700.0 to 255.0, false),
        Triple(listOf("Mitral valve"), 700.0 to 335.0, false), Triple(listOf("Left ventricle"), 700.0 to 430.0, false),
        Triple(listOf("Interventricular", "septum"), 700.0 to 540.0, false),
    ).map { (lines, at, right) ->
        val words = mutableListOf<OcclusionBox>()
        lines.forEachIndexed { i, line ->
            val parts = line.split(" ")
            val width = parts.sumOf { it.length } * 12.0 + (parts.size - 1) * 6.0
            var left = if (right) at.first - width else at.first
            val baseline = at.second + 21 + 25.0 * i
            for (part in parts) {
                val ascends = part.any { it.isUpperCase() || it in "bdfhklt" }
                val descends = part.any { it in "gjpqy" }
                val top = baseline - (if (ascends) 0.72 else 0.53) * 22
                val bottom = baseline + (if (descends) 0.21 else 0.0) * 22
                words += OcclusionBox(left / 900, top / 640, part.length * 12.0 / 900, (bottom - top) / 640)
                left += part.length * 12.0 + 6
            }
        }
        val x0 = words.minOf { it.x } - 4.0 / 900; val y0 = words.minOf { it.y } - 4.0 / 640
        val x1 = words.maxOf { it.x + it.w } + 4.0 / 900; val y1 = words.maxOf { it.y + it.h } + 4.0 / 640
        Label(lines.joinToString(" "), words, OcclusionBox(x0, y0, x1 - x0, y1 - y0))
    }

    private fun inside(inner: OcclusionBox, outer: OcclusionBox) = inner.x >= outer.x - 1e-9 && inner.y >= outer.y - 1e-9 &&
        inner.x + inner.w <= outer.x + outer.w + 1e-9 && inner.y + inner.h <= outer.y + outer.h + 1e-9

    private val drawn: List<PhotoOcclusion.Cover> = labels.map { PhotoOcclusion.Cover(box = PhotoOcclusion.clamped(it.cover), answer = it.answer) }
    private val deck: List<AnkiCard> = PhotoOcclusion.cards(drawn, 0, source = "Heart")
    private val allWords = labels.flatMap { l -> l.words.map { l.answer to it } }

    /** Every box drawn over a card's picture before Reveal: the grey others and the card's own "?". */
    private fun masked(card: AnkiCard, cards: List<AnkiCard> = deck) = OcclusionCovers.others(card, cards) + listOfNotNull(card.occlusion)

    @Test fun o1EveryHiddenLabelIsMasked() {
        assertEquals("O1 masked: a card for each of the 11 labels", 11, deck.size)
        val showing = deck.flatMap { card -> allWords.filter { (_, w) -> masked(card).none { inside(w, it) } }.map { "${card.bullets[0]}: ${it.first}" } }
        assertTrue("O1 masked: on every card, no word of any label shows | ${showing.take(6)}", showing.isEmpty())
        assertTrue("O1 masked: each card asks one, under its own \"?\"", deck.all { it.occlusion != null && it.bullets.size == 1 })
    }

    /** The owner's rule on [cards]: each label under exactly one cover, all its words inside with a margin, no other label's word under it. */
    private fun oneEach(name: String, cards: List<AnkiCard>) {
        val boxes = cards.flatMap { listOfNotNull(it.occlusion) + it.siblings }
            .distinctBy { listOf(it.x, it.y, it.w, it.h) }
        for (label in labels) {
            val touching = boxes.filter { box -> label.words.any { w -> OcclusionCovers.overlapShare(w, box) > 0 } }
            assertEquals("$name: \"${label.answer}\" has exactly one cover", 1, touching.size)
            val cover = touching.single()
            assertTrue("$name: every word of \"${label.answer}\" is wholly under it", label.words.all { inside(it, cover) })
            val x0 = label.words.minOf { it.x }; val y0 = label.words.minOf { it.y }
            val x1 = label.words.maxOf { it.x + it.w }; val y1 = label.words.maxOf { it.y + it.h }
            assertTrue("$name: \"${label.answer}\" has a margin all round",
                listOf(x0 - cover.x, y0 - cover.y, cover.x + cover.w - x1, cover.y + cover.h - y1).all { it > 0 })
            val swallowed = labels.filter { it.answer != label.answer }.flatMap { it.words }.filter { OcclusionCovers.overlapShare(it, cover) > 0.05 }
            assertTrue("$name: \"${label.answer}\"'s cover reaches no other label", swallowed.isEmpty())
        }
    }

    @Test fun o1OneRectanglePerLabel() {
        oneEach("O1 heart", deck)
        // the photo path: a two-line label dragged line by line is still one cover over both lines
        val byLine = labels.flatMap { label ->
            val lines = label.words.groupBy { it.y }.values.toList()
            if (lines.size < 2) listOf(PhotoOcclusion.Cover(box = label.cover, answer = label.answer))
            else lines.map { line ->
                val x0 = line.minOf { it.x } - 4.0 / 900; val y0 = line.minOf { it.y } - 4.0 / 640
                PhotoOcclusion.Cover(box = OcclusionBox(x0, y0, line.maxOf { it.x + it.w } + 4.0 / 900 - x0, line.maxOf { it.y + it.h } + 4.0 / 640 - y0),
                    answer = if (line === lines[0]) label.answer else "  ${label.answer.lowercase()} ")
            }
        }
        assertTrue("O1 photo: the two-line labels were dragged twice", byLine.size > labels.size)
        val saved = PhotoOcclusion.cards(byLine, 0)
        assertEquals("O1 photo: one card per label", 11, saved.size)
        oneEach("O1 photo", saved)
        // the same term in two far places keeps a cover at each; it is two labels, not one
        val twice = PhotoOcclusion.oneEach(listOf(PhotoOcclusion.Cover(box = OcclusionBox(0.7, 0.1, 0.1, 0.04), answer = "Aorta"),
            PhotoOcclusion.Cover(box = OcclusionBox(0.7, 0.8, 0.1, 0.04), answer = "Aorta")))
        assertEquals("O1 photo: a term in two far places keeps both covers", 2, twice.size)
    }

    @Test fun o2RevealTakesOffTheOneAskedAndOnlyIt() {
        for (card in deck) {
            val label = labels.first { it.answer == card.bullets[0] }
            val after = OcclusionCovers.others(card, deck)
            assertTrue("O2 reveal: ${label.answer}'s words come into view", label.words.all { w -> after.none { inside(w, it) } })
            val stillHidden = allWords.filter { (answer, _) -> answer != label.answer }
            assertTrue("O2 reveal: every other label stays covered on ${label.answer}",
                stillHidden.all { (_, w) -> after.any { inside(w, it) } })
        }
        assertEquals("O2 reveal: across the deck, each label is revealed by its own card", 11, deck.map { it.bullets[0] }.toSet().size)
    }

    @Test fun o3RatingMovesToTheNextCard() {
        val now = 1_792_000_000_000L
        val records = mutableMapOf<String, ReviewRecord>()
        var queue = ReviewPlan.queue(deck, records, now)
        assertEquals("O3 rate: the whole deck is due the first time", 11, queue.size)
        val first = queue[0].card
        records[first.id] = ReviewPlan.after(AnkiRating.GOOD, ReviewPlan.record(first, records, now), now)
        queue = ReviewPlan.queue(deck, records, now)
        assertTrue("O3 rate: Good moves on to the next card", queue.size == 10 && queue[0].card.id != first.id)
        val second = queue[0].card
        records[second.id] = ReviewPlan.after(AnkiRating.AGAIN, ReviewPlan.record(second, records, now), now)
        assertTrue("O3 rate: Again brings it back within the sitting, not now",
            (records[second.id]?.due ?: now) > now && (records[second.id]?.intervalMin ?: 99.0) <= 10)
        assertTrue("O3 rate: and it is back once its minutes are up",
            ReviewPlan.queue(deck, records, now + 11 * 60_000).any { it.card.id == second.id })
    }

    @Test fun o4PhotoCoverMoveAddSave() {
        val editing = drawn.toMutableList()
        assertEquals("O4 photo: each label gets a cover", 11, editing.size)
        val aorta = editing.indexOfFirst { it.answer == "Aorta" }
        val before = editing[aorta].box
        editing[aorta] = editing[aorta].copy(box = PhotoOcclusion.moved(before, 0.01, 0.005))
        assertTrue("O4 photo: a cover moves", abs(editing[aorta].box.x - before.x - 0.01) < 1e-9 && abs(editing[aorta].box.y - before.y - 0.005) < 1e-9)
        editing += PhotoOcclusion.Cover(box = PhotoOcclusion.added(0.5, 0.95, 900.0 / 640.0), answer = "Apex")
        editing += PhotoOcclusion.Cover(box = PhotoOcclusion.added(0.1, 0.95, 900.0 / 640.0), answer = "  ")
        val saved = PhotoOcclusion.cards(editing, 0, source = "My photo")
        assertEquals("O4 photo: saving makes a card for each answered cover", 12, saved.size)
        assertTrue("O4 photo: the added label is asked", saved.any { it.bullets == listOf("Apex") })
        assertEquals("O4 photo: the moved cover is where it was put", editing[aorta].box, saved.first { it.bullets == listOf("Aorta") }.occlusion)
        assertTrue("O4 photo: an unanswered cover still masks on every card", saved.all { it.siblings.size == 12 })
        assertTrue("O4 photo: the cards are reviewable picture cards", saved.all { it.type == AnkiCardType.OCCLUSION && it.imageIndex == 0 } &&
            ReviewPlan.queue(saved, emptyMap(), 1_792_000_000_000L).size == 12)
    }

    @Test fun o5AfterARelaunch() {
        val store = StudyStore(folder.root)
        val set = StudySet(name = "Heart", kind = StudySetKind.ANKI, images = listOf("aGVhcnQ="), cards = deck)
        store.addSet(set)
        val now = 1_792_000_000_000L
        val first = store.dueCards(store.library.single(), now).first()
        store.rateCard(first, AnkiRating.GOOD, now)
        val reopened = StudyStore(folder.root)
        val back = reopened.library.single()
        // (a box read back also keeps the JSON it was read from, so boxes are compared by place and size)
        fun place(b: OcclusionBox?) = b?.let { listOf(it.x, it.y, it.w, it.h) }
        assertEquals("O5 relaunch: the cards read back the same", deck.map { Triple(it.bullets, place(it.occlusion), it.siblings.map(::place)) },
            back.cards.map { Triple(it.bullets, place(it.occlusion), it.siblings.map(::place)) })
        assertTrue("O5 relaunch: still every cover masked on every card",
            back.cards.all { card -> drawn.all { c -> masked(card, back.cards).any { abs(it.x - c.box.x) < 1e-9 && abs(it.y - c.box.y) < 1e-9 } } })
        assertEquals("O5 relaunch: the ratings read back, so the next card is the same",
            store.dueCards(store.library.single(), now).map { it.bullets }, reopened.dueCards(back, now).map { it.bullets })
        assertEquals("O5 relaunch: the rated card is not due again yet", 10, reopened.dueCards(back, now).size)
    }
}
