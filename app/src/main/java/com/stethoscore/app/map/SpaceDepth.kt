package com.stethoscore.app.map

import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tan

// The Space theme's depth fade and near-only loading, as numbers: a port of iOS
// GraphSpaceDepth.swift. How far along the camera's view a body starts to dissolve into the
// sky and where it is gone, the band following what the camera looks at; how much of a body's
// fine shader detail its size on screen earns; when a far, tiny body is drawn as a glowing
// point instead; and which bodies are outside the view and so neither drawn nor animated.
//
// The shaders (SpaceShaders) apply the fade and the detail weight themselves, from the same
// constants; SpaceBodies and the GL renderer apply the rest each frame and hand the shaders
// the band. Pure Kotlin, so SpaceDepthTest checks it on the JVM.

/** The Graphics setting's two tiers (iOS GraphicsTier): High reaches further, Smooth less. */
enum class GraphicsTier { HIGH, SMOOTH }

/**
 * Where the fade starts and ends along the view (view-space depth, scene units), how it
 * curves ([exponent], k in f = clamp((z - start) / (end - start), 0, 1)^k) and how far it may
 * go ([cap]: 1 dissolves into the sky, under 1, for Increase Contrast, it stops short).
 */
data class SpaceDepthBand(val start: Float, val end: Float, val exponent: Float, val cap: Float) {
    /** How far a thing at view depth [depth] has faded, 0 (crisp) to [cap]: the shaders' rp_dfF. */
    fun fade(depth: Float): Float {
        val width = end - start
        if (!(width > 0.0001f) || !(cap > 0f)) return 0f
        val t = min(max((depth - start) / width, 0f), 1f)
        return t.pow(max(exponent, 0.0001f)) * cap
    }

    /** What is left of an additive light (a glow, a beam, a link): it fades to nothing. */
    fun light(depth: Float): Float = 1f - fade(depth)

    /** In the crisp zone (nothing faded): where name labels may show. */
    fun crisp(depth: Float): Boolean = depth <= start

    /** Whether the far end reaches the background, so what lies past it is not drawn. */
    val culls: Boolean get() = cap >= 1f && end - start > 0.0001f

    /** Fully faded, so not drawn, not animated and not pickable. */
    fun gone(depth: Float): Boolean = culls && depth >= end

    /**
     * The last of a solid body's dissolve: its opacity, 1 until it is nearly faded (f 0.85),
     * then to 0 at the band's end. 1 throughout when the band stops short.
     */
    fun dissolve(depth: Float): Float {
        if (!culls) return 1f
        return 1f - smoothstep(0.85f, 1f, fade(depth))
    }

    /** What the shaders' rpFade carries: start, end, exponent, cap. */
    val uniform: FloatArray get() = floatArrayOf(start, end, exponent, cap)

    companion object {
        /** No fade at all: what a shader reads when nothing set its band (all four 0). */
        val OFF = SpaceDepthBand(0f, 0f, 0f, 0f)
    }
}

/** A body's level of detail beyond its shader's own weight. */
enum class SpaceBodyLevel {
    /** Its whole look (the shaders weigh their fine detail by its size). */
    BODY,
    /** Too small on screen for its look to show: one glowing point in its colour, at its size. */
    POINT,
    /** Outside the view or fully faded: nothing drawn or animated. */
    GONE,
}

/** A plane: [normal] . p - [d] is how far p lies on its outer side (GraphPerfPlane). */
data class ViewPlane(val normal: Vec3, val d: Float) {
    fun distance(p: Vec3): Float = normal.dot(p) - d
}

/** A view volume as six outward planes (iOS GraphPerfFrustum). */
data class ViewFrustum(val planes: List<ViewPlane>) {
    /** Whether any of a ball reaches inside. */
    fun touches(centre: Vec3, radius: Float): Boolean = planes.none { it.distance(centre) > radius }

    companion object {
        /**
         * The view volume of any camera: its eye, its unit forward, right and up, its vertical
         * field of view (radians), a screen this shape, and its near and far planes.
         */
        fun of(eye: Vec3, forward: Vec3, right: Vec3, up: Vec3, fovY: Float, width: Float, height: Float,
               near: Float, far: Float): ViewFrustum {
            val halfY = fovY / 2
            val halfX = atan(tan(halfY) * width / max(height, 1e-6f))
            fun side(axis: Vec3, half: Float): ViewPlane {
                val n = axis * cos(half) - forward * sin(half)
                return ViewPlane(n, n.dot(eye))
            }
            val minus = forward * -1f
            val nearPlane = ViewPlane(minus, minus.dot(eye) - near)
            val farPlane = ViewPlane(forward, forward.dot(eye) + far)
            return ViewFrustum(listOf(nearPlane, farPlane, side(right, halfX), side(right * -1f, halfX),
                side(up, halfY), side(up * -1f, halfY)))
        }
    }
}

object SpaceDepth {
    // ---- the band ----

    /**
     * The band in multiples of the focus's view depth, per Graphics tier. The start sits
     * behind the focus, so what the camera looks at is always crisp, at every zoom.
     */
    fun reach(tier: GraphicsTier): Pair<Float, Float> = when (tier) {
        GraphicsTier.HIGH -> 1.15f to 2.6f
        GraphicsTier.SMOOTH -> 1.1f to 2.0f
    }

    /** k: a little slower to start than linear, as deep water. */
    const val EXPONENT = 1.25f
    /** Increase Contrast: the fade starts later and stops short. */
    const val CONTRAST_START = 1.25f
    const val CONTRAST_CAP = 0.7f
    /** The focus is never taken as nearer than this, so a camera on its target still has a band. */
    const val NEAREST_FOCUS = 0.05f

    /**
     * The band for a camera whose focus lies [focusDepth] along its view. Start and end scale
     * with it, so zooming in on one small body looks the same as the whole map. A focus at or
     * behind the eye (depth 0 or less) has no band in front of the camera to follow, so
     * nothing fades: [SpaceDepthBand.OFF]. (iOS clamped such a focus up to [NEAREST_FOCUS],
     * which faded everything past a twentieth of a unit; the fix is ported here.)
     */
    fun band(focusDepth: Float, tier: GraphicsTier, contrast: Boolean = false): SpaceDepthBand {
        if (focusDepth <= 0f) return SpaceDepthBand.OFF
        val d = max(if (focusDepth.isFinite()) focusDepth else NEAREST_FOCUS, NEAREST_FOCUS)
        val (rs, re) = reach(tier)
        val start = rs * (if (contrast) CONTRAST_START else 1f)
        return SpaceDepthBand(d * start, d * re, EXPONENT, if (contrast) CONTRAST_CAP else 1f)
    }

    /** The view depth of [point]: how far along the camera's unit [forward] from its [eye]. */
    fun depth(point: Vec3, eye: Vec3, forward: Vec3): Float = (point - eye).dot(forward)

    // ---- detail by size on screen ----

    /** The shaders' weight on their fine detail for a body [pixelRadius] across its radius. */
    fun detail(pixelRadius: Float): Float =
        smoothstep(SpaceShaders.DETAIL_LOW, SpaceShaders.DETAIL_HIGH, pixelRadius)

    /** Under this radius on screen a body becomes a point; from [POINT_LEAVE] a body again. */
    const val POINT_ENTER = 1.5f
    const val POINT_LEAVE = 2.25f
    /** Where a body has mostly faded (f from [FADED_FROM]) it is a point from a larger size. */
    const val FADED_FROM = 0.6f
    const val FADED_POINT_ENTER = 3f
    const val FADED_POINT_LEAVE = 3.75f

    /**
     * The level for a body now, given the level it had: gone outside the view or past the
     * band; a point when small (sooner when mostly faded); else its whole body. Only the
     * point's edge has a gap.
     */
    fun level(previous: SpaceBodyLevel, pixelRadius: Float, fade: Float, gone: Boolean,
              inView: Boolean): SpaceBodyLevel {
        if (gone || !inView) return SpaceBodyLevel.GONE
        val faded = fade >= FADED_FROM
        val enter = if (faded) FADED_POINT_ENTER else POINT_ENTER
        val leave = if (faded) FADED_POINT_LEAVE else POINT_LEAVE
        return when (previous) {
            SpaceBodyLevel.POINT -> if (pixelRadius > leave) SpaceBodyLevel.BODY else SpaceBodyLevel.POINT
            SpaceBodyLevel.BODY -> if (pixelRadius < enter) SpaceBodyLevel.POINT else SpaceBodyLevel.BODY
            SpaceBodyLevel.GONE -> if (pixelRadius < (enter + leave) / 2) SpaceBodyLevel.POINT else SpaceBodyLevel.BODY
        }
    }

    /** The point's radius on screen: the body's own, never under one pixel. */
    fun pointRadius(pixelRadius: Float): Float = max(pixelRadius, 1f)

    /** GraphPerfLOD.pixelRadius: radius x focal / depth, 0 behind the eye. */
    fun pixelRadius(radius: Float, depth: Float, focal: Float): Float =
        if (depth > 0f) radius * focal / depth else 0f

    /** A body's radius on screen for a view [viewHeight] tall with a vertical field of view [fovY]. */
    fun pixelRadius(radius: Float, depth: Float, viewHeight: Float, fovY: Float): Float =
        pixelRadius(radius, depth, focal(viewHeight, fovY))

    /** The focal length in pixels (what the shaders' rpFocal carries). */
    fun focal(viewHeight: Float, fovY: Float): Float = viewHeight / 2 / tan(max(fovY, 0.001f) / 2)

    // ---- the view ----

    fun frustum(eye: Vec3, forward: Vec3, right: Vec3, up: Vec3, fovY: Float, width: Float, height: Float,
                near: Float, far: Float): ViewFrustum =
        ViewFrustum.of(eye, forward, right, up, fovY, width, height, near, far)

    /**
     * How far past its radius a body's look reaches, by SpaceStyle code (black hole, rocky,
     * gas giant, comet, pulsar, sun): its disk, ring, corona, beams or tail.
     */
    fun reachOfLook(styleCode: Int): Float = when (styleCode) {
        0 -> 4f
        1 -> 3f
        2 -> 3.5f
        3 -> 16f
        4 -> 12f
        5 -> 5f
        else -> 5f
    }

    /** Whether a body at [centre] of [radius], its look reaching [reach] radii, is in [frustum]. */
    fun inView(frustum: ViewFrustum, centre: Vec3, radius: Float, reach: Float): Boolean =
        frustum.touches(centre, radius * max(reach, 1f))
}

/** GraphShaderKit's noise on the CPU, as the GPU sums it (the shaders' rpNoise and rpFbm). */
object ShaderKit {
    /** fract(sin(n) * 43758.5453), in Float as the GPU has it. */
    fun hash(n: Float): Float {
        val v = sin(n) * 43758.5453f
        return v - floor(v)
    }

    /** The value noise at p (0..1). */
    fun value(px: Float, py: Float, pz: Float): Float {
        val ix = floor(px); val iy = floor(py); val iz = floor(pz)
        val fx = px - ix; val fy = py - iy; val fz = pz - iz
        val ux = fx * fx * (3f - fx * 2f); val uy = fy * fy * (3f - fy * 2f); val uz = fz * fz * (3f - fz * 2f)
        val n = ix + iy * 57f + iz * 113f
        val a = mix(hash(n), hash(n + 1f), ux)
        val b = mix(hash(n + 57f), hash(n + 58f), ux)
        val c = mix(hash(n + 113f), hash(n + 114f), ux)
        val d = mix(hash(n + 170f), hash(n + 171f), ux)
        return mix(mix(a, b, uy), mix(c, d, uy), uz)
    }

    fun fbm(p: Vec3, octaves: Int): Float {
        var total = 0f; var weight = 0.5f; var sum = 0f
        var x = p.x; var y = p.y; var z = p.z
        repeat(max(octaves, 0)) {
            total += value(x, y, z) * weight
            sum += weight
            x = x * 2.03f + 1.7f; y = y * 2.03f + 9.2f; z = z * 2.03f + 3.1f
            weight *= 0.5f
        }
        return total / max(sum, 0.0001f)
    }

    /** The morphing fbm: octaves from [from] on weighed by [fine], in the sum and the weight. */
    fun fbm(p: Vec3, octaves: Int, from: Int, fine: Float): Float {
        var total = 0f; var weight = 0.5f; var sum = 0f
        var x = p.x; var y = p.y; var z = p.z
        for (o in 0 until max(octaves, 0)) {
            val k = if (o < from) 1f else fine
            total += value(x, y, z) * weight * k
            sum += weight * k
            x = x * 2.03f + 1.7f; y = y * 2.03f + 9.2f; z = z * 2.03f + 3.1f
            weight *= 0.5f
        }
        return total / max(sum, 0.0001f)
    }
}
