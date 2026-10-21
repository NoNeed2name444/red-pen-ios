package com.stethoscore.app.data

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

// A port of upstream/ios/RedPen/Shared/PhotoOcclusion.swift (fed0105): picture
// cards from your own photo, screenshot or scan, the decisions. How small a
// picture is kept, where a cover goes when it is dragged or stretched, which
// cover a finger landed on, and which covers become cards. The device half
// (decoding, shrinking) is ui/editors/PhotoPages.kt. Pure Kotlin
// (PhotoOcclusionTest, every iOS PhotoOcclusionTests case).
//
// Every box is a fraction of the picture with the origin at the top left, the
// same OcclusionBox the review screen and the exports already draw.

object PhotoOcclusion {

    /** The longest side a picture is kept at. */
    const val maxSide: Int = 2048

    /** The smallest a cover may be made, as a fraction of the picture. */
    const val minSide: Double = 0.015

    /**
     * The size a picture is shrunk to so its longest side is at most
     * [maxSide], keeping its proportions. Nothing is ever enlarged.
     */
    fun fitted(width: Int, height: Int, maxSide: Int = PhotoOcclusion.maxSide): Pair<Int, Int> {
        if (width <= 0 || height <= 0 || maxSide <= 0) return 0 to 0
        val longest = max(width, height)
        if (longest <= maxSide) return width to height
        val scale = maxSide.toDouble() / longest.toDouble()
        val w = max(1, Math.round(width * scale).toInt())
        val h = max(1, Math.round(height * scale).toInt())
        return min(w, maxSide) to min(h, maxSide)
    }

    // MARK: - Covers being edited

    /** One cover on the picture and the answer under it, while it is still being adjusted. */
    data class Cover(val id: String = newId(), val box: OcclusionBox, val answer: String)

    /** The corner a cover is stretched from. */
    enum class Handle { topLeft, topRight, bottomLeft, bottomRight }

    /** A box kept inside the picture and no smaller than [minSide] each way. */
    fun clamped(box: OcclusionBox, minSide: Double = PhotoOcclusion.minSide): OcclusionBox {
        val side = min(max(minSide, 0.0), 1.0)
        val w = min(max(box.w, side), 1.0)
        val h = min(max(box.h, side), 1.0)
        val x = min(max(box.x, 0.0), 1 - w)
        val y = min(max(box.y, 0.0), 1 - h)
        return OcclusionBox(x, y, w, h)
    }

    /** A box dragged by a finger: the same size, as far as the picture's edge allows. */
    fun moved(box: OcclusionBox, dx: Double, dy: Double): OcclusionBox {
        val w = min(box.w, 1.0)
        val h = min(box.h, 1.0)
        val x = min(max(box.x + dx, 0.0), 1 - w)
        val y = min(max(box.y + dy, 0.0), 1 - h)
        return OcclusionBox(x, y, w, h)
    }

    /**
     * A box stretched from one corner. The opposite corner stays where it is;
     * the dragged corner stops at the picture's edge and never crosses the
     * fixed one, so a cover cannot be turned inside out.
     */
    fun resized(box: OcclusionBox, handle: Handle, dx: Double, dy: Double, minSide: Double = PhotoOcclusion.minSide): OcclusionBox {
        var left = box.x
        var top = box.y
        var right = box.x + box.w
        var bottom = box.y + box.h
        when (handle) {
            Handle.topLeft -> {
                left = min(max(left + dx, 0.0), right - minSide)
                top = min(max(top + dy, 0.0), bottom - minSide)
            }
            Handle.topRight -> {
                right = max(min(right + dx, 1.0), left + minSide)
                top = min(max(top + dy, 0.0), bottom - minSide)
            }
            Handle.bottomLeft -> {
                left = min(max(left + dx, 0.0), right - minSide)
                bottom = max(min(bottom + dy, 1.0), top + minSide)
            }
            Handle.bottomRight -> {
                right = max(min(right + dx, 1.0), left + minSide)
                bottom = max(min(bottom + dy, 1.0), top + minSide)
            }
        }
        return clamped(OcclusionBox(left, top, right - left, bottom - top), minSide)
    }

    /**
     * A new cover drawn by dragging across the picture, whichever way the
     * drag went; null for a drag too short to mean a box (a tap, or a slip),
     * or one along a single line (a scroll swipe that began on the picture).
     */
    fun drawn(fromX: Double, fromY: Double, toX: Double, toY: Double, minSide: Double = PhotoOcclusion.minSide): OcclusionBox? {
        val a = min(max(fromX, 0.0), 1.0)
        val b = min(max(toX, 0.0), 1.0)
        val c = min(max(fromY, 0.0), 1.0)
        val d = min(max(toY, 0.0), 1.0)
        val w = abs(b - a)
        val h = abs(d - c)
        if (!(w >= minSide && h >= minSide)) return null
        return clamped(OcclusionBox(min(a, b), min(c, d), w, h), minSide)
    }

    /** A cover put in the middle, for "Add a cover": about a short label's size, in the picture's own proportions. */
    fun added(centreX: Double = 0.5, centreY: Double = 0.5, aspect: Double = 1.0): OcclusionBox {
        val ratio = if (aspect > 0) aspect else 1.0
        val w = 0.22
        val h = min(0.9, max(minSide, 0.06 * ratio))
        return clamped(OcclusionBox(centreX - w / 2, centreY - h / 2, w, h))
    }

    /** The cover under a point: of all the covers holding it, the smallest. */
    fun hit(x: Double, y: Double, covers: List<Cover>, slack: Double = 0.0): Int? {
        var best: Int? = null
        var bestArea = Double.MAX_VALUE
        covers.forEachIndexed { index, cover ->
            val box = cover.box
            val inX = x >= box.x - slack && x <= box.x + box.w + slack
            val inY = y >= box.y - slack && y <= box.y + box.h + slack
            if (inX && inY) {
                val area = box.w * box.h
                if (area < bestArea) {
                    bestArea = area
                    best = index
                }
            }
        }
        return best
    }

    /** The corner of a box a point is on, within [toleranceX] across and [toleranceY] down. */
    fun handle(x: Double, y: Double, box: OcclusionBox, toleranceX: Double, toleranceY: Double): Handle? {
        val corners = listOf(
            Triple(Handle.topLeft, box.x, box.y),
            Triple(Handle.topRight, box.x + box.w, box.y),
            Triple(Handle.bottomLeft, box.x, box.y + box.h),
            Triple(Handle.bottomRight, box.x + box.w, box.y + box.h),
        )
        var best: Handle? = null
        var bestDistance = Double.MAX_VALUE
        for ((corner, cx, cy) in corners) {
            val across = abs(x - cx)
            val down = abs(y - cy)
            if (across > toleranceX || down > toleranceY) continue
            val distance = across / max(toleranceX, 1e-9) + down / max(toleranceY, 1e-9)
            if (distance < bestDistance) {
                bestDistance = distance
                best = corner
            }
        }
        return best
    }

    // MARK: - From the labels OCR found, and back to cards

    /** The covers OcclusionPhrases placed, as covers to edit. */
    fun covers(found: List<OcclusionPhrases.Cover>): List<Cover> = found.map { Cover(box = clamped(it.box), answer = it.answer) }

    /** A cover's answer as it will be kept: trimmed, one line. */
    fun tidied(answer: String): String = OcclusionPhrases.tidy(answer)

    /** The covers that will make cards: those with an answer typed or read. */
    fun answered(covers: List<Cover>): List<Cover> = covers.filter { tidied(it.answer).isNotEmpty() }

    /**
     * One picture card per answered cover, through the same builder the
     * lecture diagrams use: every other cover stays grey after reveal, and a
     * term labelled twice is asked once. One label is enough for a photo.
     */
    fun cards(covers: List<Cover>, imageIndex: Int, question: String = "What is labelled here?", source: String? = null): List<AnkiCard> {
        val asked = answered(covers)
        if (asked.isEmpty()) return emptyList()
        val unasked = covers.filter { tidied(it.answer).isEmpty() }.map { it.box }
        val phrased = asked.map { OcclusionPhrases.Cover(box = it.box, answer = tidied(it.answer), lines = emptyList()) }
        return OcclusionPhrases.cards(phrased, imageIndex, question, minimumLabels = 1)
            .map { it.copy(siblings = it.siblings + unasked, source = source) }
    }

    // MARK: - Naming and the lecture

    /** A deck's name when the student gives none: what it is and the day. */
    fun defaultName(on: Date, scanned: Boolean): String {
        val day = SimpleDateFormat("d MMM", Locale.UK).format(on)
        return if (scanned) "Scanned pages, $day" else "Picture cards, $day"
    }

    /** Where a card says it came from: the deck, and the page when there are several. */
    fun source(name: String, page: Int, pages: Int): String = if (pages > 1) "$name, p. $page" else name

    /** A page's words, top to bottom, one line each, blanks dropped. */
    fun pageText(lines: List<String>): String = lines.map { it.trim() }.filter { it.isNotEmpty() }.joinToString("\n")
}

/**
 * The part of upstream/ios/RedPen/Shared/OcclusionPhrases.swift the editors
 * use: a cover as the label grouping hands it over, and the card builder
 * every picture card goes through. The grouping of OCR words into labels
 * itself waits for an on-device text reader on Android.
 */
object OcclusionPhrases {
    /** What one card hides: a single rectangle and the words under it. */
    data class Cover(val box: OcclusionBox, val answer: String, val lines: List<List<Int>>)

    /**
     * One card per label: the label's own cover hidden, every other label's
     * cover kept as a sibling; a label read twice is asked once.
     */
    fun cards(covers: List<Cover>, imageIndex: Int, question: String = "What is labelled here?", minimumLabels: Int = 2): List<AnkiCard> {
        if (covers.isEmpty() || covers.size < minimumLabels) return emptyList()
        val asked = mutableListOf<String>()
        val cards = mutableListOf<AnkiCard>()
        for (i in covers.indices) {
            val key = compact(covers[i].answer)
            if (key in asked) continue
            asked += key
            cards += AnkiCard(type = AnkiCardType.OCCLUSION, front = question, bullets = listOf(covers[i].answer), why = "",
                imageIndex = imageIndex, occlusion = covers[i].box,
                siblings = covers.indices.filter { it != i }.map { covers[it].box })
        }
        return cards
    }

    /** Whitespace collapsed to single spaces, ends trimmed. */
    fun tidy(text: String): String {
        val words = mutableListOf<String>()
        val word = StringBuilder()
        for (ch in text) {
            if (ch.isWhitespace()) { if (word.isNotEmpty()) { words += word.toString(); word.clear() } } else word.append(ch)
        }
        if (word.isNotEmpty()) words += word.toString()
        return words.joinToString(" ")
    }

    /** Letters and digits only, lower case: what two readings of a word share. */
    fun compact(text: String): String = text.lowercase().filter { it.isLetter() || it.isDigit() ||
        Character.getType(it).let { t -> t == Character.LETTER_NUMBER.toInt() || t == Character.OTHER_NUMBER.toInt() } }
}
