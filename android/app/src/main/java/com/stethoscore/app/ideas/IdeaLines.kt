package com.stethoscore.app.ideas

import com.stethoscore.app.map.Vec3
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// A port of ios/RedPen/Features/Notes/GraphLineStyle.swift (fed0105).
//
// Lines: Curved / Straight. One choice for both Ideas modes: how a link
// between two ideas is drawn. Curved (the standard) keeps the 3D map's own
// shape and bows the board's connectors gently; Straight draws every link as
// one direct segment between its two ends, on the map and on the board.
// Pure Kotlin: LineStyleTest mirrors LineStyleTests L1 to L6.

/** How links are drawn in the Ideas map and on the board. */
enum class GraphLineStyle(val rawValue: String, val title: String) {
    CURVED("curved", "Curved"),
    STRAIGHT("straight", "Straight");

    val isStraight: Boolean get() = this == STRAIGHT

    companion object {
        /** Where it is stored: a Boolean, true for Straight. */
        const val KEY = "vignette.ideas.straightLines"
        /** Until the owner chooses: Curved. */
        val standard = CURVED

        fun of(raw: String): GraphLineStyle? = entries.firstOrNull { it.rawValue == raw }

        /** The stored Boolean read back (nothing stored: the standard). */
        fun stored(straight: Boolean?): GraphLineStyle = when (straight) {
            null -> standard
            true -> STRAIGHT
            false -> CURVED
        }

        /** `-ideasLines straight` (or `curved`): that style for a design-preview run; null without it. */
        fun parse(arguments: List<String>): GraphLineStyle? {
            val at = arguments.indexOf("-ideasLines")
            if (at < 0 || at + 1 >= arguments.size) return null
            return of(arguments[at + 1])
        }

        /** Android has no launch arguments for the app: never forced. */
        val launchOverride: GraphLineStyle? = null

        /** The style in force, given the stored Boolean. */
        fun inForce(stored: Boolean): GraphLineStyle = launchOverride ?: if (stored) STRAIGHT else CURVED
    }
}

/**
 * A link drawn Straight in the 3D map: `count + 1` points evenly spaced on the direct
 * segment from its start towards its end, as far as it has grown.
 */
object GraphStraightLine {
    /** The points and their length coordinates; reused, grown as needed, never shrunk. */
    class Buffers(var points: Array<Vec3> = emptyArray(), var lengths: FloatArray = FloatArray(0))

    /** Fills [into] and returns the drawn length. [grow] (0 to 1) is how far the link has grown. */
    fun sample(start: Vec3, end: Vec3, grow: Float, count: Int, into: Buffers): Float {
        val n = max(count, 1)
        if (into.points.size < n + 1) into.points = Array(n + 1) { Vec3.ZERO }
        if (into.lengths.size < n + 1) into.lengths = FloatArray(n + 1)
        val grown = min(max(grow, 0f), 1f)
        val run = (end - start) * grown
        val total = size(run)
        val step = 1f / n
        for (k in 0..n) {
            val f = k * step
            into.points[k] = start + run * f
            into.lengths[k] = total * f
        }
        // the last point exactly on the end, free of rounding
        into.points[n] = start + run
        into.lengths[n] = total
        return total
    }

    fun size(v: Vec3): Float = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
}

/** A point on the board, in points (dp). */
data class BoardPoint(val x: Double, val y: Double)

/**
 * A connector's shape on the idea board, between two card centres `p` and `q` (always passed
 * in the same order for a pair). Curved: a quadratic bow to the left of p-to-q, its control
 * [BOW] of the length off the middle; several links between one pair fan out. Straight: the
 * direct segment, lanes side by side [LANE_GAP] apart.
 */
object IdeaLinkShape {
    const val BOW = 0.18
    const val FAN_STEP = 0.14
    const val LANE_GAP = 10.0

    /** Lane [lane] of [lanes], centred on 0: -0.5 and 0.5 for two. */
    fun laneOffset(lane: Int, lanes: Int): Double {
        val count = max(lanes, 1)
        val middle = (count - 1) / 2.0
        return lane - middle
    }

    fun bowFactor(lane: Int, lanes: Int): Double = BOW + FAN_STEP * laneOffset(lane, lanes)

    /** The quadratic's control point for a curved link. */
    fun control(p: BoardPoint, q: BoardPoint, lane: Int = 0, lanes: Int = 1): BoardPoint {
        val factor = bowFactor(lane, lanes)
        val dx = q.x - p.x
        val dy = q.y - p.y
        val midX = (p.x + q.x) / 2
        val midY = (p.y + q.y) / 2
        return BoardPoint(midX - dy * factor, midY + dx * factor)
    }

    /** A straight link's two ends, moved sideways for its lane. */
    fun straightEnds(p: BoardPoint, q: BoardPoint, lane: Int = 0, lanes: Int = 1): Pair<BoardPoint, BoardPoint> {
        val shift = laneOffset(lane, lanes) * LANE_GAP
        val dx = q.x - p.x
        val dy = q.y - p.y
        val length = sqrt(dx * dx + dy * dy)
        if (length <= 0.0001 || shift == 0.0) return p to q
        val sideX = -dy / length * shift
        val sideY = dx / length * shift
        return BoardPoint(p.x + sideX, p.y + sideY) to BoardPoint(q.x + sideX, q.y + sideY)
    }

    /** The point [t] of the way along (0 to 1). */
    fun point(style: GraphLineStyle, p: BoardPoint, q: BoardPoint, lane: Int = 0, lanes: Int = 1, t: Double): BoardPoint {
        if (style.isStraight) {
            val ends = straightEnds(p, q, lane, lanes)
            return lerp(ends.first, ends.second, t)
        }
        val k = control(p, q, lane, lanes)
        val s = 1 - t
        val w0 = s * s
        val w1 = 2 * s * t
        val w2 = t * t
        return BoardPoint(p.x * w0 + k.x * w1 + q.x * w2, p.y * w0 + k.y * w1 + q.y * w2)
    }

    /** `count + 1` points along it, end to end. */
    fun samples(style: GraphLineStyle, p: BoardPoint, q: BoardPoint, lane: Int = 0, lanes: Int = 1, count: Int = 24): List<BoardPoint> {
        val n = max(count, 1)
        return (0..n).map { k -> point(style, p, q, lane, lanes, k.toDouble() / n) }
    }

    /** The way it runs into [q], unit length (for an arrowhead there). */
    fun endDirection(style: GraphLineStyle, p: BoardPoint, q: BoardPoint, lane: Int = 0, lanes: Int = 1): BoardPoint {
        val before = point(style, p, q, lane, lanes, 0.98)
        val end = point(style, p, q, lane, lanes, 1.0)
        return unit(BoardPoint(end.x - before.x, end.y - before.y))
    }

    /** How far [spot] is from the link as drawn (for a hit test). */
    fun distance(spot: BoardPoint, style: GraphLineStyle, p: BoardPoint, q: BoardPoint, lane: Int = 0, lanes: Int = 1): Double {
        val line = samples(style, p, q, lane, lanes, if (style.isStraight) 1 else 32)
        var best = Double.MAX_VALUE
        for (k in 1 until line.size) best = min(best, segmentDistance(spot, line[k - 1], line[k]))
        return best
    }

    /** Each link's (lane, how many share the pair), from each link's pair key in order. */
    fun lanes(keys: List<String>): List<Pair<Int, Int>> {
        val counts = HashMap<String, Int>()
        for (key in keys) counts[key] = (counts[key] ?: 0) + 1
        val seen = HashMap<String, Int>()
        return keys.map { key ->
            val lane = seen[key] ?: 0
            seen[key] = lane + 1
            lane to (counts[key] ?: 1)
        }
    }

    fun lerp(a: BoardPoint, b: BoardPoint, t: Double) = BoardPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)

    fun unit(v: BoardPoint): BoardPoint {
        val length = sqrt(v.x * v.x + v.y * v.y)
        if (length <= 0.000001) return BoardPoint(1.0, 0.0)
        return BoardPoint(v.x / length, v.y / length)
    }

    /** The distance from [c] to the segment a-b. */
    fun segmentDistance(c: BoardPoint, a: BoardPoint, b: BoardPoint): Double {
        val abx = b.x - a.x
        val aby = b.y - a.y
        val acx = c.x - a.x
        val acy = c.y - a.y
        val span = abx * abx + aby * aby
        var f = 0.0
        if (span > 0.0000001) f = min(max((acx * abx + acy * aby) / span, 0.0), 1.0)
        val dx = acx - abx * f
        val dy = acy - aby * f
        return sqrt(dx * dx + dy * dy)
    }
}

/**
 * The board's opening view and "Back to the middle": the zoom and pan that put every card on
 * screen, clear of the edges, the tools and the bottom bar. Never zoomed in past 1, nor out past
 * the board's floor. A card's centre is drawn at (width / 2 + panX + x * zoom, midY + panY + y * zoom),
 * midY the middle of the part not under the bar.
 */
object IdeaBoardFit {
    data class Camera(val zoom: Double, val panX: Double, val panY: Double)
    data class Margins(val top: Double, val leading: Double, val bottom: Double, val trailing: Double)
    data class Size(val width: Double, val height: Double)

    fun camera(centres: List<BoardPoint>, card: Size, view: Size, hidden: Double, margins: Margins,
               zoomRange: ClosedFloatingPointRange<Double> = 0.3..1.0): Camera {
        val first = centres.firstOrNull() ?: return Camera(1.0, 0.0, 0.0)
        var minX = first.x; var maxX = minX; var minY = first.y; var maxY = minY
        for (c in centres) {
            minX = min(minX, c.x); maxX = max(maxX, c.x)
            minY = min(minY, c.y); maxY = max(maxY, c.y)
        }
        val width = view.width
        val seen = max(view.height - hidden, 0.0)
        val roomW = max(width - margins.leading - margins.trailing, 1.0)
        val roomH = max(seen - margins.top - margins.bottom, 1.0)
        val spanW = maxX - minX + card.width
        val spanH = maxY - minY + card.height
        val fit = min(roomW / spanW, roomH / spanH)
        val zoom = min(max(fit, zoomRange.start), zoomRange.endInclusive)
        val panX = margins.leading + roomW / 2 - width / 2 - (minX + maxX) / 2 * zoom
        val panY = margins.top + roomH / 2 - seen / 2 - (minY + maxY) / 2 * zoom
        return Camera(zoom, panX, panY)
    }
}
