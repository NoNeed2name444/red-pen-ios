package com.stethoscore.app.map

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * What a note looks like in the Space theme (iOS GraphNodeStyle, GraphSpaceOptics.swift).
 * [code] is what the shaders read and also which end of a link sends: the higher code is
 * the link's A end. [bodyScale] is the body's radius over the note's radius
 * (GraphStyleKit.bodyScale), [spin] how fast it turns (radians a second, bodySpin), and
 * [extent] the half side of the one billboard that holds everything the body draws (its
 * corona, ring, beams or tails), in note radii, from the iOS planes' sides.
 */
enum class SpaceStyle(val code: Int, val label: String, val bodyScale: Float, val spin: Float, val extent: Float) {
    BLACK_HOLE(0, "Black holes", 1f, 0f, 2.1f),
    ROCKY(1, "Rocky planets", 0.9f, 0.12f, 2.4f),
    GAS_GIANT(2, "Gas giants", 1.15f, 0.2f, 3.2f),
    COMET(3, "Comets", 0.3f, 0.3f, 7.4f),
    PULSAR(4, "Pulsars", 0.3f, 0f, 6.3f),
    SUN(5, "Suns", 1.1f, 0.05f, 4.4f);

    /** Where links stop: the body, but never so far into a pulsar's or comet's core (linkRadius). */
    val linkRadius: Float get() = when (this) {
        PULSAR, COMET -> 0.45f
        BLACK_HOLE -> 0.95f
        else -> bodyScale
    }

    companion object {
        /** The order the picker lists them in (GraphNodeStyle.menuOrder). */
        val menuOrder = listOf(BLACK_HOLE, SUN, ROCKY, GAS_GIANT, PULSAR, COMET)

        fun of(code: Int): SpaceStyle = entries.firstOrNull { it.code == code } ?: ROCKY

        /**
         * Android's stand-in for the iOS Universe ("by size"): the notes have no folders yet,
         * so a note's links decide what it is. The best-linked are black holes and suns, then
         * gas giants and rocky planets; a note with one link is a pulsar, a lone one a comet.
         */
        fun forLinks(links: Int): SpaceStyle = when {
            links >= 8 -> BLACK_HOLE
            links >= 5 -> SUN
            links >= 3 -> GAS_GIANT
            links == 2 -> ROCKY
            links == 1 -> PULSAR
            else -> COMET
        }

        /** Every node's style code, from its link count. */
        fun assign(nodeCount: Int, edges: IntArray): ByteArray {
            val degree = IntArray(nodeCount)
            for (k in edges.indices) { val i = edges[k]; if (i in 0 until nodeCount) degree[i]++ }
            return ByteArray(nodeCount) { forLinks(degree[it]).code.toByte() }
        }
    }
}

/**
 * The Space theme's colours as far points, by style code: each the colour its body reads
 * as from afar (a black hole its hot ring, a sun gold, a rocky planet blue ...), so a point
 * that grows into its body keeps its colour, and a chunk's summary shows the mix.
 */
object SpacePalette {
    val rgb = floatArrayOf(
        1.0f, 0.55f, 0.22f,
        0.45f, 0.68f, 1.0f,
        0.92f, 0.78f, 0.58f,
        0.62f, 0.98f, 0.88f,
        0.72f, 0.8f, 1.0f,
        1.0f, 0.84f, 0.45f,
    )

    /** How big a far point is beside its note's radius, so it grows into its body's own size. */
    val pointScale = floatArrayOf(0.75f, 0.9f, 1.15f, 0.5f, 0.45f, 1.1f)
}

/**
 * The Space bodies' physics on the CPU, the same as in their shaders (SpaceShaders), so it is
 * checked on the JVM. A port of iOS SpaceOptics (GraphSpaceOptics.swift); its tests mirror
 * SpaceStyleTests' cases and numbers.
 */
object SpaceOptics {
    // ---- the black hole's disk ----

    /** The disk's inner edge (the innermost stable orbit), as a share of its outer radius. */
    const val DISK_INNER = 0.43f

    /** How fast the disk turns at [r] over the inner edge's: (inner / r)^1.5, Kepler's third law. */
    fun keplerRate(r: Float, inner: Float = DISK_INNER): Float = (inner / max(r, inner)).pow(1.5f)

    /** The gas's speed at [r], as a share of light's: half at the inner edge, falling as 1 / sqrt(r). */
    fun diskSpeed(r: Float, inner: Float = DISK_INNER): Float = 0.5f * sqrt(inner / max(r, inner))

    /**
     * Relativistic beaming: D^3, D = 1 / (1 - beta cos), [towardEye] the cosine between the gas's
     * motion and the line to the eye; held to 0.3...3.5 so the receding side never vanishes.
     */
    fun beaming(speed: Float, towardEye: Float): Float {
        val d = 1f / max(1f - speed * towardEye, 0.05f)
        return (d * d * d).coerceIn(0.3f, 3.5f)
    }

    // ---- light ----

    /**
     * The light on a body at [p]: the suns (x, y, z their places, w 1 when there is a sun) each
     * weighted by 1 / distance^2, and a trace of the [key] light when there is none; unit length.
     */
    fun light(p: Vec3, suns: List<FloatArray>, key: Vec3): Vec3 {
        var l = key * 0.0001f
        for (s in suns.take(4)) {
            val d = Vec3(s[0], s[1], s[2]) - p
            val e = max(d.dot(d), 0.0001f)
            l += d * (s[3] / (e * sqrt(e)))
        }
        return unit(l, unit(key, Vec3(0f, 1f, 0f)))
    }

    /** How much of the day a surface with normal [n] sees from light [l]: a soft terminator (rp_day). */
    fun day(n: Vec3, l: Vec3): Float = smoothstep(-0.08f, 0.22f, n.dot(l))

    /** The reddened band along the terminator: 1 on it, falling off either side (rp_dusk). */
    fun dusk(n: Vec3, l: Vec3): Float { val x = n.dot(l) - 0.04f; return exp(-x * x * 90f) }

    /**
     * A sun's limb darkening, which also reddens the edge: I = 1 - 0.56 (1 - mu) - 0.22 (1 - mu)^2,
     * mu the cosine between the surface's normal and the eye (sunBody's rp_limb).
     */
    fun limbDarkening(mu: Float): Float { val lm = 1f - mu.coerceIn(0f, 1f); return 1f - 0.56f * lm - 0.22f * lm * lm }

    // ---- a gas giant and its ring ----

    /**
     * Whether the planet's shadow falls on the ring at (x, y) in the ring's plane (planet radii),
     * the light along [l] in the planet's own frame (z square to the ring).
     */
    fun planetShadowsRing(x: Float, y: Float, l: Vec3): Boolean {
        val along = x * l.x + y * l.y
        val off = x * x + y * y - along * along
        return along < 0f && off < 1f
    }

    /**
     * Where the line from cloud point [p] (unit sphere, the ring in y = 0) towards the light [l]
     * crosses the ring's plane: its distance from the centre in planet radii, or null.
     */
    fun ringShadowRadius(p: Vec3, l: Vec3): Float? {
        val ly = if (abs(l.y) < 0.001f) 0.001f else l.y
        val t = -p.y / ly
        if (t < 0f) return null
        val hx = p.x + l.x * t; val hz = p.z + l.z * t
        return sqrt(hx * hx + hz * hz)
    }

    /** The ring's density at [rho] planet radii, 0...1: a faint C ring inside, the Cassini division dark. */
    fun ringDensity(rho: Float): Float {
        val body = smoothstep(1.3f, 1.36f, rho) * (1f - smoothstep(2.2f, 2.3f, rho))
        val gd = (rho - 1.95f) / 0.03f
        val gap = 1f - 0.85f * exp(-gd * gd)
        val cring = 0.35f + 0.65f * smoothstep(1.42f, 1.52f, rho)
        return body * gap * cring
    }

    // ---- the pulsar ----

    /** How long a pulsar takes to turn once (seconds). */
    const val PULSAR_PERIOD = 1.5f

    /** The shaders' clock wraps at this many seconds: a whole number of pulsar turns. */
    const val CLOCK_PERIOD = 3000f

    /** The links' beats a second: two a turn (the shaders' 1.3333333). */
    val linkBeat: Float get() = 2f / PULSAR_PERIOD

    /** Where the beams are round the spin axis at [time] (radians, plus the seed's turn). */
    fun beamPhase(time: Float, seed: Float): Float {
        val turn = time / PULSAR_PERIOD
        return (turn - floor(turn)) * 2f * PI.toFloat() + seed * 2f * PI.toFloat()
    }

    /** One beam's direction: tilted [tilt] from the spin axis [n], at [phase] round it. */
    fun beam(n: Vec3, e1: Vec3, e2: Vec3, phase: Float, tilt: Float = 0.61f): Vec3 {
        val around = e1 * cos(phase) + e2 * sin(phase)
        return unit(n * cos(tilt) + around * sin(tilt), n)
    }

    /**
     * The wind nebula's place on screen: the angle to turn its plane so its +y runs along the
     * spin axis as seen (from the screen's right), and how edge-on its torus is (0 a round ring,
     * 1 a thin line).
     */
    fun nebula(axis: Vec3, toEye: Vec3, right: Vec3, up: Vec3): Pair<Float, Float> {
        val ax = axis.dot(right); val ay = axis.dot(up)
        val seen = sqrt(ax * ax + ay * ay)
        val edgeOn = min(unit(toEye, Vec3(0f, 0f, 1f)).cross(axis).length(), 1f)
        val turn = if (seen > 0.00001f) atan2(ay, ax) - PI.toFloat() / 2 else 0f
        return turn to edgeOn
    }

    /** The torus's height over its width on screen, for [edgeOn]. */
    fun nebulaRatio(edgeOn: Float): Float = sqrt(max(1f - edgeOn * edgeOn, 0f))

    // ---- the comet ----

    /**
     * The two tails of a comet at [p] moving at [v], lit from [light] (a place; null: the key
     * light's direction [key]): the ion tail straight away from the light, the dust tail bent
     * back towards where the comet has been, more the faster, never past square to the light.
     */
    fun cometTails(p: Vec3, v: Vec3, light: Vec3?, key: Vec3): Pair<Vec3, Vec3> {
        var away = unit(key, Vec3(0f, 1f, 0f)) * -1f
        if (light != null) away = unit(p - light, away)
        val speed = v.length()
        if (speed <= 0.0001f) return away to away
        val across = v - away * v.dot(away)
        val lag = min(speed * 2.5f, 0.7f)
        val dust = unit(away - unit(across, Vec3.ZERO) * lag, away)
        return away to dust
    }

    // ---- the corona's and the black hole's numbers ----

    /** A sun's corona carries its seed (to 1/32) and motion (0...1) in one number: 2 + seed + motion * 0.03. */
    fun coronaCode(seed: Float, motion: Float): Float {
        val s = floor(seed.coerceIn(0f, 0.999f) * 32f) / 32f
        return 2f + s + motion.coerceIn(0f, 1f) * (0.96f / 32f)
    }

    /** The seed and motion back from a corona's code, as the shader reads it. */
    fun coronaRead(code: Float): Pair<Float, Float> {
        val v = (code - 2f).coerceIn(0f, 0.9999f)
        val s = floor(v * 32f) / 32f
        return s to ((v - s) * 32f / 0.96f).coerceIn(0f, 1f)
    }

    /**
     * A black hole's number: 2 + side * (sin i to 1/255 over 256, + (0.02 + motion * 0.96) / 256),
     * i the angle between the disk's axis and the eye; the shader (bhRing) reads it back.
     */
    fun holeCode(tilt: Float, above: Boolean, motion: Float): Float {
        val q = floor(tilt.coerceIn(0f, 1f) * 255f)
        val v = (q + 0.02f + motion.coerceIn(0f, 1f) * 0.96f) / 256f
        return 2f + if (above) v else -v
    }

    data class Hole(val tilt: Float, val above: Boolean, val motion: Float)

    fun holeRead(code: Float): Hole {
        val v = min(abs(code - 2f), 0.99999f)
        val q = floor(v * 256f)
        return Hole(q / 255f, code - 2f >= 0f, ((v * 256f - q - 0.02f) / 0.96f).coerceIn(0f, 1f))
    }

    // ---- sparks when a body moves ----

    /** How one style's sparks look (iOS SpaceOptics.Trail). Colours are sRGB, first to last. */
    data class Trail(val life: Float, val size: Float, val speed: Float, val spread: Float, val stretch: Float,
                     val colours: List<FloatArray>, val backward: Boolean, val rate: Float)

    /** By style code: 0 black hole, 1 rocky, 2 gas giant, 3 comet, 4 pulsar, 5 sun. */
    fun trail(code: Int): Trail = when (code) {
        0 -> Trail(1.1f, 0.05f, 0.45f, 22f, 0.08f, listOf(floatArrayOf(0.62f, 0.08f, 0f)), true, 0f)
        5 -> Trail(0.7f, 0.045f, 0.3f, 180f, 0.03f, listOf(floatArrayOf(1f, 0.95f, 0.75f), floatArrayOf(1f, 0.55f, 0.12f)), false, 200f)
        3 -> Trail(0.9f, 0.03f, 0.15f, 60f, 0.02f, listOf(floatArrayOf(0.85f, 1f, 1f), floatArrayOf(0.45f, 0.85f, 1f)), true, 170f)
        4 -> Trail(0.4f, 0.012f, 0.4f, 180f, 0.02f, listOf(floatArrayOf(0.6f, 0.62f, 1f), floatArrayOf(0.4f, 0.3f, 0.9f)), false, 45f)
        2 -> Trail(0.55f, 0.035f, 0.12f, 180f, 0f, listOf(floatArrayOf(1f, 0.86f, 0.6f), floatArrayOf(0.8f, 0.55f, 0.3f)), false, 140f)
        else -> Trail(0.5f, 0.03f, 0.12f, 180f, 0f, listOf(floatArrayOf(0.75f, 0.85f, 1f), floatArrayOf(0.5f, 0.6f, 0.8f)), false, 140f)
    }

    // ---- per body, fixed for the note ----

    /** A note's own number, 0...1, from its index (phases, flares, which way a beam starts). */
    fun seed(index: Int): Float { val v = sin(index * 12.9898f + 78.233f) * 43758.5453f; return v - floor(v) }

    /** A spin axis leaning up to [maxTilt] from straight up, its way round set by [seed]. */
    fun tiltedAxis(seed: Float, maxTilt: Float): Vec3 {
        val a = seed * 2f * PI.toFloat()
        val f = seed * 7.31f
        val t = maxTilt * (0.5f + 0.5f * (f - floor(f)))
        return Vec3(sin(t) * cos(a), cos(t), sin(t) * sin(a))
    }

    /** Where a rocky planet's moon is at [time], in note radii from the planet: 2.3 body radii out, its orbit inclined. */
    fun moonOffset(time: Float, seed: Float): Vec3 {
        val a = time * MOON_RATE + seed * 2f * PI.toFloat()
        return unit(Vec3(cos(a), 0.2f * sin(a), sin(a)), Vec3(1f, 0f, 0f)) * (2.3f * SpaceStyle.ROCKY.bodyScale)
    }

    /** The moon's turn rate (radians a second): a whole number of turns in the clock's period. */
    val MOON_RATE: Float = (2.0 * PI * 160 / CLOCK_PERIOD).toFloat()

    /** The angle between two unit vectors. */
    fun angle(a: Vec3, b: Vec3): Float = acos(a.dot(b).coerceIn(-1f, 1f))

    fun unit(v: Vec3, fallback: Vec3): Vec3 { val n = v.length(); return if (n > 0.00001f) v * (1f / n) else fallback }
}

/**
 * Which detail a note gets, by its size on screen (plan 4e: detail follows pixels, and the
 * change is by size, never by fading): a far note is a point in its body's colour, sized to
 * its body; from [BODY_PIXELS] across it is drawn as its body. [maxBodies] caps the bodies
 * a frame draws (nearest first), scaled by the frame budget's detail, and [shaderDetail] is the
 * shaders' rpDetail (the finer noise, the second lensed image, the clouds' shadows).
 */
object SpaceLod {
    enum class Level { POINT, BODY }

    /** A note this many pixels across (its radius doubled) or more is drawn as its body. */
    const val BODY_PIXELS = 10f

    fun pixels(nodeRadius: Float, focalPixels: Float, depth: Float, openness: Float = 1f): Float =
        if (depth <= 1e-4f) Float.MAX_VALUE else 2f * nodeRadius * focalPixels / depth * openness

    fun level(pixels: Float): Level = if (pixels >= BODY_PIXELS) Level.BODY else Level.POINT

    fun maxBodies(detail: Float): Int = (64f * detail).toInt().coerceIn(12, 96)

    fun shaderDetail(detail: Float): Float = if (detail >= 0.9f) 1f else 0f

    /** Links drawn as glowing beams in a frame, at most. */
    const val MAX_BEAMS = 512
}

/** The Earth's maps (assets/earth; their sources, credits and licences are in SOURCES.md). */
object EarthMaps {
    const val FOLDER = "earth"
    const val DAY = "earth-day.jpg"
    const val CLOUDS = "earth-clouds.jpg"
    const val LIGHTS = "earth-lights.jpg"
    const val WATER = "earth-water.png"
    const val LARGE_WIDTH = 4096
    const val SMALL_WIDTH = 2048

    /** GL_REPEAT round the longitudes, GL_CLAMP_TO_EDGE at the poles. */
    const val WRAP_S = 0x2901
    const val WRAP_T = 0x812F

    /** The 4096 day map only where the device holds it easily, as iOS keeps it to its High tier. */
    fun useLarge(maxTextureSize: Int, heapBytes: Long, detail: Float): Boolean =
        maxTextureSize >= LARGE_WIDTH && heapBytes >= 384L * 1024 * 1024 && detail >= 0.9f

    /** Where a point on the unit sphere (y north, z towards longitude 0) falls on the maps: u east, v down from the north pole. */
    fun uv(p: Vec3): Pair<Float, Float> =
        (0.5f + atan2(p.x, p.z) * 0.15915494f) to (0.5f - kotlin.math.asin(p.y.coerceIn(-1f, 1f)) * 0.31830989f)

    /** One row of the day map: the colour from [day] (ARGB), the cloud cover from [clouds]' grey in alpha. */
    fun packDay(day: IntArray, clouds: IntArray, out: ByteArray, offset: Int, count: Int) {
        for (i in 0 until count) {
            val d = day[i]; val o = offset + 4 * i
            out[o] = (d ushr 16 and 0xFF).toByte(); out[o + 1] = (d ushr 8 and 0xFF).toByte(); out[o + 2] = (d and 0xFF).toByte()
            out[o + 3] = (clouds[i] ushr 16 and 0xFF).toByte()
        }
    }

    /** One row of the second map: the lights at night in red, the open water in green. */
    fun packAux(lights: IntArray, water: IntArray, out: ByteArray, offset: Int, count: Int) {
        for (i in 0 until count) {
            val o = offset + 2 * i
            out[o] = (lights[i] ushr 16 and 0xFF).toByte(); out[o + 1] = (water[i] ushr 16 and 0xFF).toByte()
        }
    }
}
