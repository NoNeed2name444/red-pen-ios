package com.stethoscore.app.ui.ward

import kotlin.math.sqrt

// A port of WardDock from ios/RedPen/Shared/Ward/WardControlStates.swift.
//
// The dock's geometry (home's bottom bar): its panel, and the chosen tab's
// hollow and ring inside it. The ring is concentric with the panel: its
// corner radius is the panel's less the inset between them, so the two
// curves run parallel round every corner (the owner, 21 Oct: "the corner of
// the part doesn't match the corner around it"). The chosen tab's name sits
// wholly inside the ring's inner edge, clear of its corners. Pure Kotlin
// (WardDockTest).
//
// iOS draws SwiftUI's continuous corner; Compose's RoundedCornerShape is a
// circular one. Both are kept here: the continuous maths as iOS has it, and
// the circle Android draws (insideCircle, labelFitsCircle), checked alike.

// The chosen tab's ring is WardControlStates.chosenEdgeWidth (WardControlStates.kt).

object WardDock {
    /** The panel's corner radius (WardRadius.bar). */
    const val panelRadius = WardScale.xl
    /** From the panel's edge to the tab's: the bar along the bottom, and the wide screen's rail. */
    const val barInset = 4.0
    const val railInset = 5.0
    /** The ring round the chosen tab: the accent edge, drawn inside its hollow's shape. */
    const val ringWidth = WardControlStates.chosenEdgeWidth

    /** The tab's hollow (and its ring's outer edge), concentric with the panel. */
    fun tabRadius(inset: Double): Double = panelRadius - inset
    val barTabRadius: Double get() = tabRadius(barInset)
    val railTabRadius: Double get() = tabRadius(railInset)

    /** Round a tab's symbol and name: above and below, and at each side. */
    const val labelVertical = 8.0
    const val labelSide = 10.0
    /** The least room between the name and the ring's inner edge. */
    const val labelClearance = 1.0
    /** A tab's least height. */
    const val tabMinHeight = 56.0

    // The row along the bottom, on every phone (iOS T0112: the full row at
    // every text size short of the accessibility ones).

    /** The bar: room at its sides, the Ideas pill's width, the gap between the panel and the pill, and the widest the bar grows. */
    const val barSide = 10.0
    const val ideasWidth = 56.0
    const val barSpacing = 6.0
    const val barMaxWidth = 560.0
    /** A tab is never narrower than a finger: the least target (48 on Android, iOS 44). */
    const val leastTab = WardControlSize.target
    /** How small a name may get (all five by the same amount) so the row still fits: never its side room, so it stays clear of the ring. */
    const val leastNameScale = 0.5

    /** How much the names shrink so the tabs, each a name with its side room ([ideals]), fit [room]: 1 when they fit as they are. */
    fun nameScale(ideals: List<Double>, room: Double): Double {
        val total = ideals.sum()
        if (total <= room) return 1.0
        val sides = 2 * labelSide * ideals.size
        val names = ideals.sumOf { maxOf(0.0, it - 2 * labelSide) }
        if (names <= 0) return 0.0
        return minOf(1.0, maxOf(0.0, (room - sides) / names))
    }

    /**
     * The tabs' widths in [room]: where there is spare room the narrower tabs
     * share it equally (water-filling); where there is too little, every name
     * shrinks by the same amount and each keeps its side room.
     */
    fun tabWidths(ideals: List<Double>, room: Double): List<Double> {
        val total = ideals.sum()
        if (total <= 0) return ideals
        val width = maxOf(0.0, room)
        if (width < total) {
            val scale = nameScale(ideals, width)
            return ideals.map { 2 * labelSide + maxOf(0.0, it - 2 * labelSide) * scale }
        }
        var remaining = width
        var count = ideals.size
        var level = 0.0
        for (ideal in ideals.sortedDescending()) {
            level = remaining / count
            if (ideal <= level) break
            remaining -= ideal
            count -= 1
        }
        return ideals.map { maxOf(it, level) }
    }

    /** Where the chosen hollow lies along the row: its left edge and its width. */
    data class Span(val left: Double, val width: Double)

    /**
     * The chosen tab's hollow among tabs [widths] wide, side by side from 0,
     * at [at] tabs along: on a tab at a whole number, and between two while
     * it travels, its left edge and its width taken that far from one tab's
     * to the next. It never leaves the first or the last tab. iOS moves one
     * hollow between the tabs with the choice (matchedGeometryEffect,
     * StudyCategory.swift:748) rather than one per tab shown and hidden.
     */
    fun hollow(widths: List<Double>, at: Double): Span {
        if (widths.isEmpty()) return Span(0.0, 0.0)
        val along = at.coerceIn(0.0, (widths.size - 1).toDouble())
        val i = along.toInt()
        val left = widths.take(i).sum()
        if (i == widths.size - 1) return Span(left, widths[i])
        val f = along - i
        return Span(left + widths[i] * f, widths[i] + (widths[i + 1] - widths[i]) * f)
    }

    /** Where a continuous corner leaves the straight edge, in radii from the corner. */
    const val continuousReach = 1.52866

    /**
     * SwiftUI's continuous corner for radius 1, from the edge's straight line
     * into the corner's middle: three cubic curves, as (along the edge, in
     * from it).
     */
    val continuousCorner: List<List<Pair<Double, Double>>> = listOf(
        listOf(1.52866 to 0.0, 1.08849 to 0.0, 0.86840 to 0.0, 0.66993 to 0.06814),
        listOf(0.66993 to 0.06814, 0.46213 to 0.15429, 0.15429 to 0.46213, 0.06814 to 0.66993),
        listOf(0.06814 to 0.66993, 0.0 to 0.86840, 0.0 to 1.08849, 0.0 to 1.52866),
    )

    data class Point(val x: Double, val y: Double)

    /** Points on a continuous corner of [radius], as (x, y) from the corner's two edges. */
    fun cornerPoints(radius: Double, steps: Int = 200): List<Point> {
        val points = ArrayList<Point>()
        for (curve in continuousCorner) {
            for (i in 0..steps) {
                val t = i.toDouble() / steps
                val m = 1 - t
                val w = doubleArrayOf(m * m * m, 3 * m * m * t, 3 * m * t * t, t * t * t)
                var x = 0.0
                var y = 0.0
                for (k in 0 until 4) { x += w[k] * curve[k].first; y += w[k] * curve[k].second }
                points.add(Point(x * radius, y * radius))
            }
        }
        return points
    }

    /** Points on a circular corner of [radius] (what Compose's RoundedCornerShape draws). */
    fun circlePoints(radius: Double, steps: Int = 600): List<Point> = (0..steps).map {
        val a = Math.PI / 2 * it / steps
        Point(radius - radius * kotlin.math.sin(a), radius - radius * kotlin.math.cos(a))
    }

    /** Whether a box's corner at (x, y) from a continuous corner's two edges lies inside it, at least [clearance] from its curve. */
    fun inside(x: Double, y: Double, radius: Double, clearance: Double): Boolean {
        if (x < clearance || y < clearance) return false
        val reach = continuousReach * radius
        if (x >= reach + clearance || y >= reach + clearance) return true
        val curve = cornerPoints(radius)
        if (x < depth(curve, y)) return false
        return nearest(curve, x, y) >= clearance
    }

    /** As [inside], for a circular corner of [radius]. */
    fun insideCircle(x: Double, y: Double, radius: Double, clearance: Double): Boolean {
        if (x < clearance || y < clearance) return false
        if (x >= radius + clearance || y >= radius + clearance) return true
        val dx = radius - x
        val dy = radius - y
        if (dx <= 0 || dy <= 0) return true
        return radius - sqrt(dx * dx + dy * dy) >= clearance
    }

    private fun nearest(curve: List<Point>, x: Double, y: Double): Double {
        var best = Double.POSITIVE_INFINITY
        for (p in curve) {
            val dx = x - p.x
            val dy = y - p.y
            best = minOf(best, sqrt(dx * dx + dy * dy))
        }
        return best
    }

    /** How far along the edge the corner's curve is at [y] in from it. */
    fun depth(curve: List<Point>, y: Double): Double {
        val last = curve.lastOrNull() ?: return 0.0
        if (y >= last.y) return 0.0
        for ((a, b) in curve.zipWithNext()) {
            if (a.y <= y && y <= b.y) {
                val t = if (b.y > a.y) (y - a.y) / (b.y - a.y) else 0.0
                return a.x + (b.x - a.x) * t
            }
        }
        return curve.first().x
    }

    /**
     * Whether a tab's name, [width] wide, centred across a tab [tabWidth]
     * wide whose bottom edge is [below] under the name, sits wholly inside a
     * ring of corner [radius]: its box keeps [labelClearance] from the ring's
     * inner edge, corners too.
     */
    fun labelFits(width: Double, below: Double, tabWidth: Double, radius: Double): Boolean {
        val inner = radius - ringWidth
        val side = (tabWidth - width) / 2 - ringWidth
        val under = below - ringWidth
        return inside(side, under, inner, labelClearance)
    }

    /** As [labelFits], for the circular corner Android draws. */
    fun labelFitsCircle(width: Double, below: Double, tabWidth: Double, radius: Double): Boolean {
        val inner = radius - ringWidth
        val side = (tabWidth - width) / 2 - ringWidth
        val under = below - ringWidth
        return insideCircle(side, under, inner, labelClearance)
    }
}
