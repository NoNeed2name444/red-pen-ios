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
// The page is not cut above the bar (the owner, 22 Oct: the band under
// New set and the tabs was wrong). The list runs on to the window's bottom
// edge behind New set and the dock, which float on the page with nothing
// behind them but the page itself; a row as tall as the bar, and `endRoom`
// more, ends the list (`endSpace`), so the last tile scrolls wholly clear
// above them (`lastRowBottom`). `faults` checks the first screen: at the
// standard sizes the card and its button end `barRoom` above the bar, at
// the large sizes the bar's line slices no button, New set sits on no part
// of the card above that line, and no word of home's text is broken across
// two lines.

/** Swift's `rounded()`: to the nearest, a half away from zero. */
internal fun roundedHalfAway(x: Double): Double = if (x >= 0) floor(x + 0.5) else ceil(x - 0.5)

object HomeFit {
    /** Window heights (points, inside the safe area) under this are short: an iPhone SE (647), a mini (728), a 16e (763). A Pro (778) is not. */
    const val shortHeight: Double = 770.0
    /** How many beds the round shows on a short window. */
    const val shortBeds: Int = 2
    /** The least room between the card's end and the bar. */
    const val gap: Double = 8.0
    /** How far under the header's last line home's grid band ends (iOS HomeBandTrack.belowHeader). */
    const val belowHeader: Double = 10.0

    /**
     * At the standard text sizes, the least room between the round card's
     * end (and its Start ward round button's) and the bar's top. Not a line
     * on screen: where the first screen's round has to end.
     */
    const val barRoom: Double = 12.0
    /** The room under the last row once the list has scrolled to its end. */
    const val endRoom: Double = 24.0

    /** The bar's line: `barRoom` above its top (global points). */
    fun barLine(barTop: Double): Double = barTop - barRoom

    /**
     * How tall the row that ends the list is: as tall as the bar (New set
     * over the dock, or the selection bar), and `endRoom` more. Nothing cuts
     * the page, so this row is all that keeps the last tile clear of the
     * bar: the list's own inset for the bar is not relied on.
     */
    fun endSpace(barHeight: Double): Double = max(0.0, if (barHeight.isFinite()) barHeight else 0.0) + endRoom

    /**
     * Where the last row's bottom rests once the list has scrolled to its
     * end, the list running on to the bar's bottom (it is not cut above the
     * bar). [insetHonoured]: the list also keeps its own inset for the bar,
     * which only lifts the row further. Global points.
     */
    fun lastRowBottom(barTop: Double, barHeight: Double, insetHonoured: Boolean = false): Double {
        val listEnd = barTop + max(0.0, barHeight)
        return listEnd - endSpace(barHeight) - (if (insetHonoured) max(0.0, barHeight) else 0.0)
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
     * were taken off, one at a time, while the bar's line sliced Start ward
     * round at large text (slices); one bed always stays.
     */
    fun shownBeds(count: Int, short: Boolean, trimmed: Int = 0): Int {
        val base = if (short) min(count, shortBeds) else count
        return max(min(base, 1), base - max(0, trimmed))
    }

    /** Whether a line at [cut] falls inside something spanning [minY] to [maxY]: neither wholly above it nor wholly below. */
    fun slices(minY: Double, maxY: Double, cut: Double): Boolean = minY < cut && maxY > cut

    /** A laid-out thing's edges, in one coordinate space. */
    data class Box(val minX: Double, val minY: Double, val maxX: Double, val maxY: Double) {
        fun overlaps(other: Box): Boolean = minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
        val text: String get() = "${roundedHalfAway(minY).toInt()}-${roundedHalfAway(maxY).toInt()}"
    }

    /** A row or part of the page, as laid out at rest: a Practise tile, a set's row, the Due chip inside the round card. */
    data class Part(val name: String, val box: Box)

    /** A text as laid out, and the width of its widest word on its own. */
    data class Words(val name: String, val width: Double, val widest: Double)

    /**
     * What is wrong with home as laid out at rest; empty when it fits. At
     * the standard text sizes the round card and its Start ward round
     * button end `barRoom` above the bar, so the first screen holds the
     * whole round. At the larger sizes ([large]) the page may run on behind
     * the bar and scroll, but the bar's line must not slice the Start button
     * (whole above it or wholly past it). At any size New set sits on no
     * part of the card above the bar's line, and no word of home's text is
     * broken across two lines. Rows and tiles past the line are not faults:
     * they pass behind New set and the dock, and scroll clear (`endSpace`).
     */
    fun faults(card: Box?, start: Box?, bar: Box?, newSet: Box?,
               large: Boolean = false, words: List<Words> = emptyList()): List<String> {
        if (card == null) return listOf("no round card was laid out")
        if (start == null) return listOf("no Start ward round button was laid out")
        if (bar == null) return listOf("no bottom bar was laid out")
        val out = mutableListOf<String>()
        val line = barLine(bar.minY)
        val at = "${roundedHalfAway(line).toInt()}"
        if (large) {
            if (slices(start.minY, start.maxY, line)) out.add("Start ward round (${start.text}) is sliced by the bar's line at $at")
        } else {
            if (start.maxY > line) out.add("Start ward round (${start.text}) runs past the bar's line at $at, above the bar")
            if (card.maxY > line) out.add("the round card (${card.text}) runs past the bar's line at $at")
        }
        // the part of the card on the first screen: down to the bar's line
        if (newSet != null && card.minY < line) {
            val shown = card.copy(maxY = min(card.maxY, line))
            if (newSet.overlaps(shown)) out.add("New set (${newSet.text}) sits on the round card (${shown.text})")
        }
        for (w in words) if (w.widest > w.width + 0.5) {
            out.add("${w.name} breaks inside a word: its widest word needs ${roundedHalfAway(w.widest).toInt()} pt, " +
                "it has ${roundedHalfAway(w.width).toInt()}")
        }
        return out
    }
}
