package com.stethoscore.app.ui.home

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// A port of ios/RedPen/Shared/Learn/HomeFit.swift. Pure Kotlin
// (HomeFitTest, every case of HomeFitTests).
//
// Home's first screen on a short phone. The round card, its Start ward
// round button and the bar at the bottom (New set over the dock) have to
// share the height. On a short window the round shows its first two beds,
// so the card ends above the dock.
//
// The page ends at a clean cut `cutRoom` above the bar (`shown` is how tall
// it is): nothing scrolled under the dock shows, and there is no strip or
// line under it, so the page reads unbroken to the bottom. `faults` is the
// check on a laid-out home: the card above the cut, no sliver of the tiles
// peeking over it, New set off the card, and no word of home's text broken
// across two lines.

/** Swift's `rounded()`: to the nearest, a half away from zero. */
internal fun roundedHalfAway(x: Double): Double = if (x >= 0) floor(x + 0.5) else ceil(x - 0.5)

object HomeFit {
    /** Window heights (points, inside the safe area) under this are short: an iPhone SE (647), a mini (728), a 16e (763). A Pro (778) is not. */
    const val shortHeight: Double = 770.0
    /** How many beds the round shows on a short window. */
    const val shortBeds: Int = 2
    /** The least room between the card's end and the bar. */
    const val gap: Double = 8.0
    /** The room between the page's cut and the bar's top. */
    const val cutRoom: Double = 12.0
    /** The least of a row that may show over the cut at rest: less reads as a stray line, not as more to scroll to. */
    const val leastShown: Double = 12.0
    /** How far under the header's last line home's grid band ends (iOS HomeBandTrack.belowHeader). */
    const val belowHeader: Double = 10.0

    /**
     * Where the page's cut falls, from the page's top: `cutRoom` above the
     * bar, however tall the page's own frame is. Null, no cut: there is no
     * bar or it has not been measured. Global points in. [tops] are the
     * global tops, at rest, of the rows and parts that can meet the cut
     * (settledCut).
     */
    fun cut(barTop: Double?, pageTop: Double, tops: List<Double> = emptyList()): Double? {
        if (barTop == null || !barTop.isFinite() || !(barTop > pageTop)) return null
        return max(0.0, settledCut(barTop - cutRoom, tops) - pageTop)
    }

    /**
     * How tall a page with this much room is, from its top: down to the
     * cut, or all of it. [scale] is the screen's pixels to a point, 0 when
     * unknown: the cut is settled onto the grid at or above itself, and the
     * height onto the grid again, so the page's end falls at or above the
     * cut however the frame is snapped.
     */
    fun shown(barTop: Double?, pageTop: Double, pageHeight: Double, tops: List<Double> = emptyList(), scale: Double = 0.0): Double {
        val cut = cut(barTop, pageTop, tops) ?: return pageHeight
        if (!(scale > 0) || !scale.isFinite()) return min(pageHeight, cut)
        val end = onGrid(pageTop + cut, scale)
        return min(pageHeight, max(0.0, onGrid(end - pageTop, scale)))
    }

    /** The pixel line at or above [value] (a hair of slack for the float error of a value already on the grid). */
    fun onGrid(value: Double, scale: Double): Double = floor(value * scale + 1e-6) / scale

    /**
     * The cut (global points) once no part shows less than `leastShown`
     * over it: where a part's top falls within `leastShown` above the cut,
     * the cut moves up to that top. Moving the cut up can bring another top
     * into that band, so it goes on until none is.
     */
    fun settledCut(cut: Double, tops: List<Double>): Double {
        var at = cut
        var moved = true
        while (moved) {
            moved = false
            for (top in tops) {
                if (top.isFinite() && top < at && at - top < leastShown) {
                    at = top
                    moved = true
                }
            }
        }
        return at
    }

    /**
     * Whether a push and back showed home covered by the pushed page: a part
     * of home left the book during the push, or, when every face booked
     * before it lay wholly at or below home's cut, at least one went away
     * and was kept by that cut.
     */
    fun pushCovered(faces: List<Double>, cut: Double?, removed: Int, kept: Int): Boolean {
        if (removed > 0) return true
        if (cut == null || faces.isEmpty() || kept <= 0) return false
        return faces.all { it + 1e-6 >= cut }
    }

    /** Whether a window this tall is short. A wide tablet keeps New set at the bottom beside the rail. */
    fun isShort(height: Double, broad: Boolean): Boolean = !broad && height > 0 && height < shortHeight

    /**
     * How many of the round's beds are shown. [trimmed] is how many more
     * were taken off, one at a time, while the page's cut sliced Start ward
     * round at large text (slices); one bed always stays.
     */
    fun shownBeds(count: Int, short: Boolean, trimmed: Int = 0): Int {
        val base = if (short) min(count, shortBeds) else count
        return max(min(base, 1), base - max(0, trimmed))
    }

    /** Whether a cut at [cut] falls inside something spanning [minY] to [maxY]: neither wholly above it nor wholly below. */
    fun slices(minY: Double, maxY: Double, cut: Double): Boolean = minY < cut && maxY > cut

    /** A laid-out thing's edges, in one coordinate space. */
    data class Box(val minX: Double, val minY: Double, val maxX: Double, val maxY: Double) {
        fun overlaps(other: Box): Boolean = minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
        val text: String get() = "${roundedHalfAway(minY).toInt()}-${roundedHalfAway(maxY).toInt()}"
    }

    /** A row or part of the page that can meet the cut, as laid out at rest. */
    data class Part(val name: String, val box: Box)

    /** A text as laid out, and the width of its widest word on its own. */
    data class Words(val name: String, val width: Double, val widest: Double)

    /**
     * What is wrong with home as laid out at rest; empty when it fits. At
     * the standard text sizes the round card and its Start ward round
     * button end above the page's cut. At the larger sizes ([large]) the
     * page may run on past the cut and scroll, but the cut must not slice
     * the Start button and no sliver of the card or the tiles may peek over
     * it. At any size New set sits on no part of the card that shows, and
     * no word of home's text is broken across two lines. [pageEnd] is where
     * the page was actually cut, when measured.
     */
    fun faults(card: Box?, start: Box?, bar: Box?, newSet: Box?, tiles: Box? = null,
               large: Boolean = false, words: List<Words> = emptyList(),
               pageEnd: Double? = null, parts: List<Part> = emptyList()): List<String> {
        if (card == null) return listOf("no round card was laid out")
        if (start == null) return listOf("no Start ward round button was laid out")
        if (bar == null) return listOf("no bottom bar was laid out")
        val out = mutableListOf<String>()
        val cut = min(bar.minY - cutRoom, pageEnd ?: Double.POSITIVE_INFINITY)
        val at = "${roundedHalfAway(cut).toInt()}"
        if (large) {
            if (slices(start.minY, start.maxY, cut)) out.add("Start ward round (${start.text}) is sliced by the page's cut at $at")
        } else {
            if (start.maxY > cut) out.add("Start ward round (${start.text}) runs past the page's cut at $at, above the bar")
            if (card.maxY > cut) out.add("the round card (${card.text}) runs past the page's cut at $at")
        }
        val named = mutableListOf<Pair<String, Box?>>("the round card" to card, "the tiles" to tiles)
        named += parts.map { it.name to it.box }
        for ((name, box) in named) {
            if (box == null || !(box.minY < cut) || !(cut - box.minY < leastShown)) continue
            val line = "a sliver of $name (${box.text}) peeks over the page's cut at $at"
            if (line !in out) out.add(line)
        }
        // the part of the card that shows: down to the cut
        if (newSet != null && card.minY < cut) {
            val shown = card.copy(maxY = min(card.maxY, cut))
            if (newSet.overlaps(shown)) out.add("New set (${newSet.text}) sits on the round card (${shown.text})")
        }
        for (w in words) if (w.widest > w.width + 0.5) {
            out.add("${w.name} breaks inside a word: its widest word needs ${roundedHalfAway(w.widest).toInt()} pt, " +
                "it has ${roundedHalfAway(w.width).toInt()}")
        }
        return out
    }
}
