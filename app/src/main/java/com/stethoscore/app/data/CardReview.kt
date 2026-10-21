package com.stethoscore.app.data

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// The words and decisions of the card review screens, kept free of Compose so the JVM tests
// read them exactly as the screens do. Ports of what iOS keeps inside its views:
// ios/RedPen/Features/Anki/AnkiReviewView.swift, DueTodayView.swift, AnkiCardFace.swift,
// ReviewCardActions.swift, plus AnkiCard.clozePieces (Models/AnkiCard.swift), OcclusionCovers
// (Shared/OcclusionFilter.swift) and SpokenText (Shared/AccessibilityText.swift), at dcb4745.

/** One run of a cloze sentence: plain text, or a gap with its answer and Anki's hint. */
data class ClozePiece(val text: String, val isGap: Boolean, val hint: String? = null)

object CardReview {
    /** Cards whose next appearance is this close still come back in the same sitting. */
    const val sittingMinutes: Double = 20.0
    /** How long Undo stays in reach after a rating. */
    const val undoSeconds: Long = 5
    /** How many ratings show the buttons' meanings before they step aside. */
    const val hintCards: Int = 5
    /** A sideways swipe at least this long (dp), and clearly more sideways than down, asks. */
    const val swipe: Float = 90f

    // ---- the card face ----

    fun badge(type: AnkiCardType): String = when (type) {
        AnkiCardType.QA -> "Question"
        AnkiCardType.CLOZE -> "Fill in the gap"
        AnkiCardType.OCCLUSION -> "What is hidden?"
    }

    private val clozePattern = Regex("""\{\{c\d+::([\s\S]+?)(?:::([\s\S]*?))?\}\}""")

    /** The sentence split at its gaps, so a gap is hidden and then filled in where it stood. */
    fun clozePieces(text: String): List<ClozePiece> {
        val out = ArrayList<ClozePiece>()
        var at = 0
        for (m in clozePattern.findAll(text)) {
            if (m.range.first > at) out.add(ClozePiece(text.substring(at, m.range.first), false))
            val hint = m.groups[2]?.value?.trim()
            out.add(ClozePiece(m.groupValues[1], true, hint?.ifEmpty { null }))
            at = m.range.last + 1
        }
        if (at < text.length) out.add(ClozePiece(text.substring(at), false))
        return out
    }

    /** How a gap reads before it is revealed: Anki's "[...]", or its hint. */
    fun clozeGap(piece: ClozePiece): String = "[" + (piece.hint ?: "...") + "]"

    /** The sentence as a screen reader says it: "blank" (or the hint) for a gap. */
    fun clozeSpoken(text: String, revealed: Boolean): String = clozePieces(text).joinToString("") { piece ->
        if (!piece.isGap || revealed) piece.text else piece.hint?.let { "blank, hint: $it" } ?: "blank"
    }

    /** The back of the card as one sentence, read out when it is turned over. */
    fun spokenBack(card: AnkiCard): String {
        val plain = when (card.type) {
            AnkiCardType.QA -> card.bullets.joinToString(". ")
            AnkiCardType.CLOZE -> card.clozeText.replace(Regex("""\{\{c\d+::([^}:]+)(::[^}]*)?\}\}"""), "$1")
            AnkiCardType.OCCLUSION -> card.bullets.firstOrNull() ?: ""
        }
        val text = plain.replace("**", "")
        return if (text.isEmpty()) "Answer shown." else "Answer: $text"
    }

    /** `**term**` markers as runs of (text, bold), as iOS's Markdown reading shows them. */
    fun boldRuns(s: String): List<Pair<String, Boolean>> {
        val out = ArrayList<Pair<String, Boolean>>()
        var at = 0
        for (m in Regex("""\*\*(.+?)\*\*""").findAll(s)) {
            if (m.range.first > at) out.add(s.substring(at, m.range.first) to false)
            out.add(m.groupValues[1] to true)
            at = m.range.last + 1
        }
        if (at < s.length) out.add(s.substring(at) to false)
        return out
    }

    // ---- the ratings ----

    fun title(rating: AnkiRating): String = rating.label

    /** What each button means, in the student's words rather than Anki's. */
    fun meaning(rating: AnkiRating): String = when (rating) {
        AnkiRating.AGAIN -> "I forgot it"
        AnkiRating.HARD -> "I just about got it"
        AnkiRating.GOOD -> "I got it"
        AnkiRating.EASY -> "Too easy"
    }

    /** "in 4 d" -> "4 d", for putting after "back in". */
    fun bareInterval(label: String): String {
        val trimmed = label.trim()
        return if (trimmed.lowercase().startsWith("in ")) trimmed.drop(3).trim() else trimmed
    }

    /** The interval in words: "in 4 d" -> "4 days", "1 min" -> "1 minute". */
    fun spokenInterval(label: String): String {
        val bare = bareInterval(label)
        val parts = bare.split(" ")
        val n = parts.getOrNull(0)?.toIntOrNull()
        if (parts.size != 2 || n == null) return bare
        val unit = when (parts[1].lowercase()) { "min", "m" -> "minute"; "hr", "h" -> "hour"; "d" -> "day"; else -> return bare }
        return "$n " + if (n == 1) unit else unit + "s"
    }

    /** "Good, back in 4 days". */
    fun spokenRating(rating: AnkiRating, label: String): String {
        val words = spokenInterval(label)
        return if (words.isEmpty()) title(rating) else title(rating) + ", back in " + words
    }

    // ---- the headers and finishes ----

    private fun plural(n: Int) = if (n == 1) "" else "s"

    data class Header(val status: String, val detail: String, val fraction: Double)

    /** One deck's header: "3 cards left", "2 done · studying ahead". */
    fun deckHeader(left: Int, done: Int, studyingAhead: Boolean): Header = Header(
        if (left == 0) "All done" else "$left card${plural(left)} left",
        "$done done" + if (studyingAhead) " · studying ahead" else "",
        done.toDouble() / max(1, done + left),
    )

    /** Due today's header: "3 cards due". */
    fun dueHeader(left: Int, done: Int): Header = Header(
        if (left == 0) "All done" else "$left card${plural(left)} due",
        "$done done",
        done.toDouble() / max(1, done + left),
    )

    /** "Next card back in 10 min." or, with nothing to come, that everything has been seen. */
    fun nextLine(nextDue: Long?, now: Long): String {
        if (nextDue == null || nextDue <= now) return "Everything here has been seen."
        return "Next card back in " + AnkiScheduler.formatInterval((nextDue - now) / 60_000.0) + "."
    }

    /** "You went through 12 cards. Next card back in 10 min." */
    fun doneLine(reviewed: Int, nextLine: String): String = "You went through $reviewed card${plural(reviewed)}. $nextLine"

    /** Due today's empty line. */
    fun dueEmptyLine(reviewed: Int): String =
        if (reviewed == 0) "Come back when a card is ready, or open a deck and study ahead."
        else "$reviewed card${plural(reviewed)} reviewed across your decks."

    // ---- the sitting ----

    /** A rating's effect on one deck's sitting: the card leaves, and comes back if it is due again soon. */
    fun afterRating(queue: List<AnkiQueueItem>, item: AnkiQueueItem, kept: ReviewRecord): List<AnkiQueueItem> {
        val rest = queue.filterNot { it.id == item.id }
        val back = if (kept.intervalMin <= sittingMinutes) rest + AnkiQueueItem(item.card, kept.due, kept.intervalMin) else rest
        return back.sortedBy { it.due }
    }

    /** The same across the library: back before the phone goes down, behind whatever else is waiting. */
    fun afterRating(queue: List<ReviewPlan.Due>, due: ReviewPlan.Due, kept: ReviewRecord): List<ReviewPlan.Due> {
        val rest = queue.filterNot { it.id == due.id }
        val back = if (kept.intervalMin <= sittingMinutes) rest + due.copy(due = kept.due) else rest
        return back.sortedBy { it.due }
    }

    /** An undone card goes back in front, question side up. */
    fun afterUndo(queue: List<AnkiQueueItem>, card: AnkiCard, intervalMin: Double): List<AnkiQueueItem> =
        listOf(AnkiQueueItem(card, Long.MIN_VALUE, intervalMin)) + queue.filterNot { it.id == card.id }
}

/** Every tested label on an occlusion card's picture, covered. Port of iOS OcclusionCovers. */
object OcclusionCovers {
    /** The label this card asks about: a strong orange. */
    val targetRgb = Triple(0.93, 0.45, 0.09)
    /** Every other label on the picture: a flat, neutral grey. */
    val otherRgb = Triple(0.56, 0.58, 0.62)
    const val drawPadding: Double = 0.0
    const val drawMinimum: Double = 6.0

    /** The other labels on this card's picture: its own siblings, or (an older card) its deck's. */
    fun others(card: AnkiCard, deck: List<AnkiCard>): List<OcclusionBox> {
        val found = ArrayList(card.siblings)
        if (found.isEmpty() && card.imageIndex != null) {
            for (other in deck) if (other.id != card.id && other.type == AnkiCardType.OCCLUSION && other.imageIndex == card.imageIndex) other.occlusion?.let(found::add)
        }
        val kept = ArrayList<OcclusionBox>()
        for (box in found) {
            val target = card.occlusion
            if (target != null && overlapShare(box, target) > 0.5) continue
            if (kept.any { it.x == box.x && it.y == box.y && it.w == box.w && it.h == box.h }) continue
            kept.add(box)
        }
        return kept
    }

    /** How much of the smaller box the two share, 0...1. */
    fun overlapShare(a: OcclusionBox, b: OcclusionBox): Double {
        val w = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
        val h = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
        if (w <= 0 || h <= 0) return 0.0
        val smaller = min(a.w * a.h, b.w * b.h)
        return if (smaller > 0) (w * h) / smaller else 0.0
    }

    data class Rect(val x: Double, val y: Double, val w: Double, val h: Double)

    /** Where a cover goes on a picture [width] x [height]: grown, at least [minimum] across, kept on it, snapped outward. */
    fun rect(box: OcclusionBox, width: Double, height: Double, padding: Double = drawPadding, minimum: Double = drawMinimum, pixelScale: Double = 1.0): Rect? {
        if (width <= 0 || height <= 0) return null
        var x0 = box.x * width - padding; var y0 = box.y * height - padding
        var x1 = (box.x + box.w) * width + padding; var y1 = (box.y + box.h) * height + padding
        if (x1 - x0 < minimum) { val grow = (minimum - (x1 - x0)) / 2; x0 -= grow; x1 += grow }
        if (y1 - y0 < minimum) { val grow = (minimum - (y1 - y0)) / 2; y0 -= grow; y1 += grow }
        x0 = max(0.0, x0); y0 = max(0.0, y0); x1 = min(width, x1); y1 = min(height, y1)
        if (x1 <= x0 || y1 <= y0) return null
        val s = max(pixelScale, 1.0)
        val minX = floor(x0 * s) / s; val minY = floor(y0 * s) / s
        val maxX = ceil(x1 * s) / s; val maxY = ceil(y1 * s) / s
        return Rect(minX, minY, maxX - minX, maxY - minY)
    }
}
