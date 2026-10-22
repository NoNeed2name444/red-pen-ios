package com.stethoscore.app.ui.ward

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

// A port of ios/RedPen/Shared/Ward/WardIsland.swift: window
// geometry shared by the page and the paper frame. No drawing or device
// queries belong here, so the joins are checked on the JVM (WardIslandTest).

/** A rectangle in points (Swift's CGRect, never negative in size here). */
data class WardRect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX: Double get() = x
    val minY: Double get() = y
    val maxX: Double get() = x + width
    val maxY: Double get() = y + height
}

object WardIsland {
    data class Sides(val left: Boolean, val right: Boolean) {
        val any: Boolean get() = left || right
    }

    fun sides(host: WardRect, page: WardRect, covered: Boolean): Sides {
        if (covered || !(host.width > 0) || !(page.width > 0)) return Sides(left = false, right = false)
        return Sides(left = abs(host.minX - page.minX) <= 1, right = abs(host.maxX - page.maxX) <= 1)
    }

    /** Only a translation: the same solved circles are used in both places. */
    fun local(join: WardEdgeJoin, origin: WardVec): WardEdgeJoin {
        fun corner(c: WardEdgeCorner?): WardEdgeCorner? =
            c?.let { WardEdgeCorner(it.center - origin, it.radius, it.lineX - origin.x, it.join - origin) }
        return WardEdgeJoin(join.y - origin.y, corner(join.left), corner(join.right),
            join.fromX?.let { it - origin.x }, join.toX?.let { it - origin.x })
    }

    /**
     * Hard clips divide the ink at the page's actual pixel boundary. These
     * bands never include the page; the renderer also removes the frame's
     * stroke from them before filling the arc stroke.
     */
    fun clearance(panel: WardPaperPanel, page: WardRect, sides: Sides): List<WardRect> {
        val result = mutableListOf<WardRect>()
        if (sides.left && page.minX > panel.x) {
            result += WardRect(panel.x, panel.y, page.minX - panel.x, panel.height)
        }
        val right = panel.x + panel.width
        if (sides.right && page.maxX < right) {
            result += WardRect(page.maxX, panel.y, right - page.maxX, panel.height)
        }
        return result
    }

    /**
     * Distance inside a circular top corner and its two tangent straight
     * edges. Taking the smaller distance from the two corners describes a
     * slab's entire top, even when only one side joins the frame.
     */
    private fun distance(point: WardVec, center: WardVec, radius: Double, left: Boolean): Double {
        val x = if (left) center.x - point.x else point.x - center.x
        val y = center.y - point.y
        return radius - hypot(max(0.0, x), max(0.0, y)) - min(0.0, max(x, y))
    }

    /**
     * Near the window's bottom the arc passes its circle's widest point.
     * Measure the finite arc and its downward continuation, rather than
     * assuming that every join is a quarter circle on a vertical wall.
     */
    private fun distance(point: WardVec, corner: WardEdgeCorner, left: Boolean): Double {
        val sign = if (left) -1.0 else 1.0
        val v = point - corner.center
        val end = atan2(corner.join.y - corner.center.y, sign * (corner.join.x - corner.center.x))
        val angle = min(end, max(-PI / 2, atan2(v.y, sign * v.x)))
        val nearest = corner.center + WardVec(sign * corner.radius * cos(angle), corner.radius * sin(angle))
        val arc = hypot(point.x - nearest.x, point.y - nearest.y)
        val wall = hypot(point.x - corner.join.x, max(0.0, corner.join.y - point.y))
        val boundary = if (point.y < corner.join.y) {
            corner.center.x + sign * sqrt(max(0.0, corner.radius * corner.radius - v.y * v.y))
        } else {
            corner.join.x
        }
        val inside = sign * (point.x - boundary) <= 0
        return (if (inside) 1 else -1) * min(arc, wall)
    }

    data class FoldGap(val slab: Double, val island: Double)

    /**
     * The 44 by 28 pill is the convex hull of two 14-point disks. Including
     * its five-point rim in both disks bounds every visible part of it. Its
     * size is fixed at every text size; the band remains the tap target.
     */
    fun foldClearance(slab: WardRect, join: WardEdgeJoin, inset: Double): FoldGap {
        val left = WardEdge.slabTopRadius(join.left, slabSide = slab.minX, leading = true)
        val right = WardEdge.slabTopRadius(join.right, slabSide = slab.maxX, leading = false)
        val top = slab.minY + WardPaper.edgeWidth / 2
        val centers = listOf(WardVec(slab.maxX - 36 - inset, slab.minY + 22), WardVec(slab.maxX - 20 - inset, slab.minY + 22))
        val reach = 14 + WardRelief.rimReach
        var slabGap = Double.POSITIVE_INFINITY
        var islandGap = Double.POSITIVE_INFINITY
        for (p in centers) {
            slabGap = minOf(slabGap,
                distance(p, WardVec(slab.minX + left, top + left), left, left = true) - reach,
                distance(p, WardVec(slab.maxX - right, top + right), right, left = false) - reach)
            islandGap = min(islandGap, p.y - join.y - reach)
            join.left?.let { islandGap = min(islandGap, distance(p, it, left = true) - reach) }
            join.right?.let { islandGap = min(islandGap, distance(p, it, left = false) - reach) }
        }
        return FoldGap(slabGap, islandGap)
    }

    fun foldInset(slab: WardRect, join: WardEdgeJoin): Double {
        fun fits(inset: Double): Boolean {
            val gap = foldClearance(slab, join, inset)
            return min(gap.slab, gap.island) >= 2.1
        }
        if (fits(0.0)) return 0.0
        var lo = 0.0
        var hi = slab.width / 2
        repeat(40) {
            val mid = (lo + hi) / 2
            if (fits(mid)) hi = mid else lo = mid
        }
        // Move only sideways: growing the band would move the deck's line
        // while finding its corner. Round inward, with a little room beyond
        // the required two points. The pill's press only makes it smaller.
        return ceil(hi * 2) / 2
    }
}
