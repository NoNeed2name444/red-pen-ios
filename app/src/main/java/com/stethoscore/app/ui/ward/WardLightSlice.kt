package com.stethoscore.app.ui.ward

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// A port of upstream/ios/RedPen/Shared/Ward/WardLightSlice.swift: the Ward
// relief's soft lights, drawn once. A face's drop and inner shadows are
// blurs; drawn into an image once per style and shown from it, a face costs
// no blur per frame. This file is the maths of that, pure Kotlin so the JVM
// tests it (WardLightSliceTest): which shapes the images cover, how far a
// face's lights reach beyond its shape, how an image is cut into a
// stretchable slice so one image serves every size of a rounded rectangle,
// and what the images are keyed by. (Android's drawing of the images, iOS's
// WardLightImages, is not ported: WardSurfaces draws its lights live.)

/** Swift's `rounded()`: to the nearest, halves away from zero. */
internal fun wardRounded(x: Double): Double {
    if (!x.isFinite()) return x
    val a = abs(x)
    val f = floor(a)
    val r = if (a - f >= 0.5) f + 1 else f
    return if (x < 0) -r else r
}

/** The shapes whose lights can be drawn once. Anything else keeps the live drawing. */
sealed class WardFaceShape {
    data class Rounded(val radius: Double, val continuous: Boolean) : WardFaceShape()
    data class Capsule(val continuous: Boolean) : WardFaceShape()
    data object Circle : WardFaceShape()
    /** A ring [width] wide just inside the box's circle: the groove of a readiness ring. */
    data class Annulus(val width: Double) : WardFaceShape()
}

/** How a face is lit, which sets what its image holds. */
@Suppress("EnumEntryName")
enum class WardLightLook(val rawValue: Int) {
    /** Highlight and shade dropped outside the shape. */
    raised(0),
    /** The same two cast inside it. */
    inset(1),
    /** A pressable face at rest (depth 0): the shade dropped outside, the face and shade softened together. */
    press(2),
}

/**
 * One image's layout: what shape is drawn into it, how far it reaches beyond
 * the shape, and, where it is cut to stretch, the cap each side keeps. Points
 * throughout; every length is a whole number of points (or of pixels, on an
 * axis that is not stretched) so the caps fall on the pixel grid.
 */
data class WardLightPlan(
    /** The shape as drawn into the image (a rounded rectangle's radius clamped to the size). */
    val shape: WardFaceShape,
    /** How far the image extends beyond the shape on every side. */
    val pad: Int,
    /** The size of the shape drawn into the image. */
    val width: Double,
    val height: Double,
    /** Whether the image is cut to stretch along each axis. */
    val stretchX: Boolean,
    val stretchY: Boolean,
    /** The cap kept at each end of a stretched axis; 0 where the axis is not stretched. */
    val capX: Int,
    val capY: Int,
    /** An axis that is not stretched is keyed by its size, in pixels; 0 where it is stretched. */
    val keyWidth: Int,
    val keyHeight: Int,
) {
    /** The image's size: the shape and the room its lights reach. */
    val imageWidth: Double get() = width + 2 * pad
    val imageHeight: Double get() = height + 2 * pad

    /** Whether the shape sits in the middle of its box at its own size, as a circle does. */
    val centred: Boolean get() = shape is WardFaceShape.Circle || shape is WardFaceShape.Annulus

    data class Size(val width: Double, val height: Double)

    companion object {
        /** The size the image is shown at for a shape of this size: the shape and its reach on every side. */
        fun shown(width: Double, height: Double, pad: Int): Size = Size(width + 2 * pad, height + 2 * pad)
    }
}

/** Everything that changes an image, and nothing that does not. */
data class WardLightKey(
    val shape: Int,
    /** A rounded rectangle's radius (a ring's width), in hundredths of a point; 0 otherwise. */
    val radius: Int,
    val keyWidth: Int,
    val keyHeight: Int,
    val look: WardLightLook,
    val lift: Int,
    val control: Boolean,
    val dark: Boolean,
    val strong: Boolean,
    /** The fill's colour as 8-bit RGBA ([WardLightSlice.pack]). */
    val fill: Long,
    /** The ring's resolved section or override ink, also 8-bit RGBA. */
    val edge: Long = 0,
    /** The display scale, in hundredths. */
    val scale: Int,
)

object WardLightSlice {
    /** A continuous corner curves over this many radii along each edge (a circular one over one). */
    const val continuousCurve = 1.53
    /** How far a shadow's soft edge reaches, in blur radii (three deviations). */
    const val shadowSpread = 1.5
    /** How far a blur softens, in blur radii (its radius is the deviation). */
    const val blurSpread = 3.0
    /** The width of the stretched middle of a slice, in points. */
    const val core = 2.0
    /** The display scales the images are made for. */
    val scaleRange: ClosedFloatingPointRange<Double> = 1.0..4.0

    // reach

    /** How far one light reaches beyond the shape: its offset and the spread of its soft edge. */
    fun reach(of: WardReliefLight): Double =
        if (of.lit) max(abs(of.x), abs(of.y)) + shadowSpread * of.radius else 0.0

    /** Whole points a raised or inset face's lights reach beyond its shape, with one to spare. */
    fun reach(spec: WardReliefSpec): Int = ceil(max(reach(of = spec.highlight), reach(of = spec.shade))).toInt() + 1

    /** The same for a pressable face at rest: the shade, and the softening of the whole group by its blur. */
    fun reach(spec: WardPressSpec): Int =
        ceil(maxOf(reach(of = spec.outerShade), reach(of = spec.innerShade), reach(of = spec.innerHighlight))
            + blurSpread * spec.blur).toInt() + 1

    // pixels

    /** A length on the pixel grid. */
    fun quantised(points: Double, scale: Double): Double = wardRounded(points * scale) / scale

    fun pixels(points: Double, scale: Double): Int = wardRounded(points * scale).toInt()

    /** An 8-bit RGBA colour as one number: what a fill is keyed by. */
    fun pack(red: Double, green: Double, blue: Double, alpha: Double): Long {
        fun byte(x: Double): Long = wardRounded(min(1.0, max(0.0, x)) * 255).toLong()
        return (byte(red) shl 24) or (byte(green) shl 16) or (byte(blue) shl 8) or byte(alpha)
    }

    // the cut

    /**
     * The layout of the image for a shape of this size, or null for a size
     * that is not a size (or a scale or radius that is not one). [reach] is
     * how far the lights fall, [inner] whether they all fall inside the
     * shape, which then needs no room around it.
     *
     * A rounded rectangle is cut like a nine-slice: its four corners, and the
     * strips between them stretched. Each cap is the pad, the curve and the
     * reach, and a side shorter than two caps and a core is not cut: it is
     * drawn at its own size and keyed by it. A capsule is the same with its
     * radius half its short side. A circle or a ring is drawn at its own
     * size, its diameter the shorter side, and shown in the middle of the box.
     */
    fun plan(shape: WardFaceShape, width: Double, height: Double, reach: Int, inner: Boolean, scale: Double): WardLightPlan? {
        if (!(width.isFinite() && height.isFinite() && width > 0 && height > 0 && scale.isFinite()
                && scale in scaleRange && reach >= 0)) return null
        val pad = if (inner) 0 else reach
        val qw = quantised(width, scale)
        val qh = quantised(height, scale)
        if (!(qw > 0 && qh > 0)) return null

        val curve: Double
        var drawn = shape
        when (shape) {
            is WardFaceShape.Circle, is WardFaceShape.Annulus -> {
                // a circle fills the shorter side, in the middle of the box
                var ring: WardFaceShape = shape
                if (shape is WardFaceShape.Annulus) {
                    val w = shape.width
                    if (!(w.isFinite() && w >= 0)) return null
                    ring = WardFaceShape.Annulus(wardRounded(w * 100) / 100)
                }
                val d = min(qw, qh)
                return WardLightPlan(ring, pad, d, d, stretchX = false, stretchY = false, capX = 0, capY = 0,
                    keyWidth = pixels(d, scale), keyHeight = pixels(d, scale))
            }
            is WardFaceShape.Rounded -> {
                val r = shape.radius
                if (!(r.isFinite() && r >= 0)) return null
                val radius = wardRounded(minOf(r, width / 2, height / 2) * 100) / 100
                curve = ceil(if (shape.continuous) radius * continuousCurve else radius)
                drawn = WardFaceShape.Rounded(radius, shape.continuous)
            }
            is WardFaceShape.Capsule -> {
                val radius = min(width, height) / 2
                curve = ceil(if (shape.continuous) radius * continuousCurve else radius)
            }
        }

        // each cap: the pad, the curve and the reach; the core between them
        val cap = pad + curve.toInt() + reach
        val least = (2 * (curve.toInt() + reach)).toDouble() + core
        val stretchX = width >= least
        val stretchY = height >= least
        val w = if (stretchX) least else qw
        val h = if (stretchY) least else qh
        return WardLightPlan(drawn, pad, w, h, stretchX, stretchY,
            capX = if (stretchX) cap else 0, capY = if (stretchY) cap else 0,
            keyWidth = if (stretchX) 0 else pixels(w, scale),
            keyHeight = if (stretchY) 0 else pixels(h, scale))
    }

    /** The key an image is kept under. */
    fun key(plan: WardLightPlan, look: WardLightLook, lift: WardLift, control: Boolean, dark: Boolean, strong: Boolean,
            fill: Long, scale: Double, edge: Long = 0): WardLightKey {
        val (kind, radius) = when (val s = plan.shape) {
            is WardFaceShape.Rounded -> (if (s.continuous) 1 else 0) to wardRounded(s.radius * 100).toInt()
            is WardFaceShape.Capsule -> (if (s.continuous) 3 else 2) to 0
            is WardFaceShape.Circle -> 4 to 0
            is WardFaceShape.Annulus -> 5 to wardRounded(s.width * 100).toInt()
        }
        return WardLightKey(kind, radius, plan.keyWidth, plan.keyHeight, look, lift.rawValue, control, dark, strong,
            fill, edge, wardRounded(scale * 100).toInt())
    }

    /**
     * Which source column or row of a cut image fills column or row [i] of
     * the image shown at [shown] along an axis whose cut keeps [cap] at each
     * end of an image [source] long: the caps carry over as they are, the
     * middle repeats its first point's worth.
     */
    fun sourceIndex(i: Int, shown: Int, source: Int, cap: Int): Int {
        if (i < cap) return i
        if (i >= shown - cap) return source - (shown - i)
        return cap
    }
}

// counting the faces (for a recorded opening)

/** Why a relief face drew live instead of from its image. */
sealed class WardLiveReason(val tag: String) {
    /** A shape the images do not cover. */
    data object Shape : WardLiveReason("shape")
    /** A fill that is not a colour, or has no RGB to key by. */
    data object Fill : WardLiveReason("fill")
    /** No plan for a size, a scale or a radius that is not one (whole points). */
    data class Plan(val width: Int, val height: Int) : WardLiveReason("plan@${width}x$height")
    /** The image could not be drawn. */
    data object Failed : WardLiveReason("failed")
    /** Asked for inside the hand-off, where nothing is drawn. */
    data object Late : WardLiveReason("late")
    /** A press in motion or held. */
    data object Press : WardLiveReason("press")
    /** The section's look is shifting; cache its settled drawing afterwards. */
    data object Look : WardLiveReason("look")
    /** Nothing to light: flat, unlit, or lights that are not lit. */
    data object Bare : WardLiveReason("none")
    /** No area: a box of no size (yet). */
    data object Empty : WardLiveReason("empty")
    /** The relief-off take draws everything live. */
    data object Off : WardLiveReason("off")

    /** Whether the face draws no lights at all, so that nothing is left to cache. */
    val isLightless: Boolean get() = this == Bare || this == Empty
}

/** How a relief face was last drawn. */
sealed class WardReliefPath {
    data object Cached : WardReliefPath()
    data class Live(val reason: WardLiveReason) : WardReliefPath()

    val tag: String get() = when (this) {
        is Cached -> "cached"
        is Live -> "live:" + reason.tag
    }

    /** Whether the face has lights and drew them live: what the cache was meant to take over. */
    val missed: Boolean get() = this is Live && !reason.isLightless
}

/**
 * Every relief face on screen and how it was last drawn, for a recorded
 * opening's readout. A face counts once, however often it is redrawn; it is
 * dropped when it goes. Thread-safe.
 */
class WardReliefCensus {
    private val lock = Any()
    private var last = 0L
    private val faces = HashMap<Long, WardReliefPath>()
    private var imagesMade = 0
    private var madeSeconds = 0.0
    private var failures = 0

    /** A new face's number (never 0). */
    fun newFace(): Long = synchronized(lock) { last += 1; last }

    fun note(face: Long, path: WardReliefPath) = synchronized(lock) { faces[face] = path }

    fun forget(face: Long) = synchronized(lock) { faces.remove(face); Unit }

    /** An image was drawn, taking [seconds]. */
    fun made(seconds: Double) = synchronized(lock) { imagesMade += 1; madeSeconds += seconds }

    /** An image could not be drawn. */
    fun failure() = synchronized(lock) { failures += 1 }

    /** The readout's field, led by a space. */
    fun field(): String = synchronized(lock) { field(faces.values.toList(), imagesMade, madeSeconds, failures) }

    companion object {
        val shared = WardReliefCensus()

        /**
         * ` relief=cached:12,live:plan@0x0:2,live:shape:1 made=15/42ms`: the
         * faces by how they were drawn (cached first, the rest by name), then
         * the images drawn so far and their total time; ` failed=N` after it
         * when any image could not be drawn.
         */
        fun field(paths: List<WardReliefPath>, made: Int, seconds: Double, failures: Int = 0): String {
            val counts = LinkedHashMap<String, Int>()
            for (path in paths) counts[path.tag] = (counts[path.tag] ?: 0) + 1
            val tags = counts.keys.sortedWith { a, b ->
                if ((a == "cached") != (b == "cached")) (if (a == "cached") -1 else 1) else a.compareTo(b)
            }
            val faces = if (tags.isEmpty()) "none" else tags.joinToString(",") { "$it:${counts[it] ?: 0}" }
            val ms = wardRounded(seconds * 1000).toInt()
            return " relief=$faces made=$made/${ms}ms" + (if (failures > 0) " failed=$failures" else "")
        }
    }
}
