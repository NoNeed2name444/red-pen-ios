package com.stethoscore.app.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The Space theme's physics and shaders, mirroring iOS SpaceStyleTests (cases P1 to P9 and
 * E1 to E3, the same numbers), plus what only Android has: the limb darkening curve on the
 * CPU, the level of detail that turns a point into its body, the styles from link counts,
 * the Earth maps' packing and the bodies and beams a frame picks.
 */
class SpaceStyleTest {
    private val x = Vec3(1f, 0f, 0f)
    private val y = Vec3(0f, 1f, 0f)
    private val z = Vec3(0f, 0f, 1f)
    private fun unit(v: Vec3) = SpaceOptics.unit(v, y)
    private fun close(a: Float, b: Float, tolerance: Float = 1e-4f) = abs(a - b) <= tolerance
    private val pi = PI.toFloat()

    // ---- P1 the black hole's disk ----

    @Test fun p1KeplerDiskAndBeaming() {
        val inner = SpaceOptics.DISK_INNER
        assertTrue("P1 the inner edge turns at the full rate", close(SpaceOptics.keplerRate(inner), 1f))
        assertTrue("P1 twice as far out turns 2^-1.5 as fast (Kepler)", close(SpaceOptics.keplerRate(inner * 2), 2f.pow(-1.5f), 1e-5f))
        var last = 2f
        for (k in 0..20) {
            val rate = SpaceOptics.keplerRate(inner + k * (1 - inner) / 20)
            assertTrue("P1 every lane further out turns slower", rate <= last)
            last = rate
        }
        assertTrue("P1 inside the inner edge holds at the edge's rate", close(SpaceOptics.keplerRate(0.1f), 1f))
        assertTrue("P1 the gas is fastest at the inner edge, half light's speed",
            close(SpaceOptics.diskSpeed(inner), 0.5f) && SpaceOptics.diskSpeed(1f) < 0.5f)
        assertTrue("P1 its speed falls as 1/sqrt(r)", close(SpaceOptics.diskSpeed(inner * 4), 0.25f, 1e-5f))
        val toward = SpaceOptics.beaming(0.4f, 1f)
        val away = SpaceOptics.beaming(0.4f, -1f)
        val across = SpaceOptics.beaming(0.4f, 0f)
        assertTrue("P1 the side coming towards the eye is brightest (beaming): $toward $across $away", toward > across && across > away)
        assertTrue("P1 square to the eye, no beaming", close(across, 1f))
        assertEquals("P1 beaming held to 0.3...3.5", 3.5f, SpaceOptics.beaming(0.5f, 1f), 0f)
        assertEquals("P1 beaming held to 0.3...3.5", 0.3f, SpaceOptics.beaming(0.5f, -1f), 0f)
    }

    // ---- P2 light and the terminator ----

    @Test fun p2LightAndTerminator() {
        val sun = floatArrayOf(10f, 0f, 0f, 1f)
        assertTrue("P2 one sun: the light comes from it", SpaceOptics.light(Vec3.ZERO, listOf(sun), y).dot(x) > 0.999f)
        val both = SpaceOptics.light(Vec3.ZERO, listOf(floatArrayOf(0f, 2f, 0f, 1f), floatArrayOf(20f, 0f, 0f, 1f)), x)
        assertTrue("P2 two suns: the nearer one wins (inverse square)", both.dot(y) > 0.9f)
        assertTrue("P2 no suns: the key light", SpaceOptics.light(Vec3.ZERO, emptyList(), z).dot(z) > 0.999f)
        assertTrue("P2 a slot with no sun adds nothing",
            SpaceOptics.light(Vec3.ZERO, listOf(floatArrayOf(0f, 0f, 0f, 0f), sun), y).dot(x) > 0.999f)
        assertTrue("P2 the side facing the light is in full day", close(SpaceOptics.day(x, x), 1f))
        assertTrue("P2 the far side is night", close(SpaceOptics.day(x * -1f, x), 0f))
        val edge = SpaceOptics.day(y, x)
        assertTrue("P2 the terminator is soft (partly lit): $edge", edge > 0.1f && edge < 0.6f)
        for (k in 0 until 12) {
            val a = k * 0.52f
            val l = unit(Vec3(cos(a), 0.4f * sin(a * 1.7f), sin(a)))
            var lit = Vec3.ZERO
            for (j in 0 until 200) {
                val u = j * 2.399963f
                val h = 1 - (j + 0.5f) * 2 / 200
                val ring = sqrt(max(1 - h * h, 0f))
                val n = Vec3(cos(u) * ring, h, sin(u) * ring)
                lit = lit + n * SpaceOptics.day(n, l)
            }
            assertTrue("P2 the day side faces the light, whichever way it comes", unit(lit).dot(l) >= 0.99f)
        }
        val duskOn = SpaceOptics.dusk(unit(Vec3(0.04f, 1f, 0f)), x)
        assertTrue("P2 the reddened band sits on the terminator: $duskOn", duskOn > 0.8f
            && SpaceOptics.dusk(x, x) < 0.01f && SpaceOptics.dusk(x * -1f, x) < 0.01f)
    }

    // ---- P3 a gas giant and its ring ----

    @Test fun p3RingAndShadows() {
        assertTrue("P3 the planet shadows the ring behind it from the sun", SpaceOptics.planetShadowsRing(-1.6f, 0f, x))
        assertFalse("P3 not on the sun's side", SpaceOptics.planetShadowsRing(1.6f, 0f, x))
        assertFalse("P3 not beside the shadow", SpaceOptics.planetShadowsRing(-1.6f, 1.4f, x))
        assertTrue("P3 the shadow is a planet wide", SpaceOptics.planetShadowsRing(-2.0f, 0.9f, x)
            && !SpaceOptics.planetShadowsRing(-2.0f, 1.1f, x))
        val high = unit(Vec3(1f, 0.5f, 0f))
        val south = unit(Vec3(-0.2f, -0.45f, 0.3f))
        val north = unit(Vec3(-0.2f, 0.45f, 0.3f))
        assertNotNull("P3 the ring's shadow falls on the hemisphere away from the sun", SpaceOptics.ringShadowRadius(south, high))
        assertNull("P3 ... and not on the sun's", SpaceOptics.ringShadowRadius(north, high))
        var banded = 0
        for (k in 0 until 60) {
            val p = unit(Vec3(0.6f, -k / 60f, 0.2f))
            val rho = SpaceOptics.ringShadowRadius(p, high)
            if (rho != null && SpaceOptics.ringDensity(rho) > 0.3f) banded++
        }
        assertTrue("P3 ... as a band where the ring is dense: $banded", banded in 4..56)
        assertTrue("P3 the Cassini division is dark", SpaceOptics.ringDensity(1.95f) < SpaceOptics.ringDensity(1.8f) * 0.3f
            && SpaceOptics.ringDensity(1.95f) < SpaceOptics.ringDensity(2.1f) * 0.3f)
        assertTrue("P3 nothing inside the C ring or beyond the A ring", SpaceOptics.ringDensity(1.1f) == 0f && SpaceOptics.ringDensity(2.4f) == 0f)
        assertTrue("P3 the C ring is faint", SpaceOptics.ringDensity(1.4f) < SpaceOptics.ringDensity(1.7f) * 0.6f)
    }

    // ---- P4 the pulsar ----

    @Test fun p4PulsarBeamsBeatAndNebula() {
        val period = SpaceOptics.PULSAR_PERIOD
        assertTrue("P4 the beams come round once a period",
            close(SpaceOptics.beamPhase(0.37f, 0.2f), SpaceOptics.beamPhase(0.37f + period, 0.2f), 1e-3f))
        assertTrue("P4 half a period: half a turn",
            close(SpaceOptics.beamPhase(period / 2, 0f) - SpaceOptics.beamPhase(0f, 0f), pi, 1e-3f))
        val b0 = SpaceOptics.beam(z, x, y, 0f)
        val b1 = SpaceOptics.beam(z, x, y, 2f)
        assertTrue("P4 a beam stays at its tilt from the spin axis as it sweeps",
            close(acos(b0.dot(z)), 0.61f, 1e-4f) && close(acos(b1.dot(z)), 0.61f, 1e-4f))
        assertTrue("P4 the links beat twice a turn", close(SpaceOptics.linkBeat * period, 2f))
        assertTrue("P4 the link shader beats at that rate", SpaceShaders.link.contains("rp_t * 1.3333333")
            && close(1.3333333f, SpaceOptics.linkBeat, 1e-6f))
        assertTrue("P4 the core and nebula flash at it too", SpaceShaders.pulsarCore.contains("rp_t * 1.3333333")
            && SpaceShaders.pulsarGlow.contains("rp_t * 1.3333333"))
        assertTrue("P4 3000 s of clock is a whole number of turns (no jump at the wrap)",
            close((3000f / period).roundToInt().toFloat(), 3000f / period, 1e-3f) && SpaceOptics.CLOCK_PERIOD == 3000f)
        val faceOn = SpaceOptics.nebula(z, z, x, y)
        val edgeOn = SpaceOptics.nebula(y, z, x, y)
        val sideways = SpaceOptics.nebula(x, z, x, y)
        assertTrue("P4 the axis at the eye: the nebula a round ring", faceOn.second < 0.01f && close(SpaceOptics.nebulaRatio(faceOn.second), 1f, 1e-3f))
        assertTrue("P4 the axis across the sky: the torus seen edge on", close(edgeOn.second, 1f, 1e-4f) && SpaceOptics.nebulaRatio(edgeOn.second) < 0.01f)
        assertTrue("P4 its +y turned along the axis as seen: ${edgeOn.first} ${sideways.first}",
            close(edgeOn.first, 0f, 1e-5f) && close(sideways.first, -pi / 2, 1e-5f))
    }

    // ---- P5 the comet ----

    @Test fun p5CometTails() {
        val at = Vec3(5f, 0f, 0f)
        val rest = SpaceOptics.cometTails(at, Vec3.ZERO, Vec3.ZERO, y)
        assertTrue("P5 at rest both tails point straight away from the light", rest.first.dot(x) > 0.999f && rest.second.dot(x) > 0.999f)
        val flying = Vec3(0f, 0.1f, 0f)
        val slow = SpaceOptics.cometTails(at, flying, Vec3.ZERO, y)
        assertTrue("P5 moving: the ion tail still exactly away from the light", slow.first.dot(x) > 0.9999f)
        assertTrue("P5 the dust tail lags behind the motion", slow.second.dot(flying) < 0f && slow.second.dot(x) > 0f)
        val lagSlow = acos(min(slow.second.dot(slow.first), 1f))
        val fast = SpaceOptics.cometTails(at, flying * 20f, Vec3.ZERO, y)
        val lagFast = acos(min(fast.second.dot(fast.first), 1f))
        assertTrue("P5 a slow orbit bends the dust tail visibly; faster bends it more: $lagSlow $lagFast", lagSlow > 0.15f && lagFast > lagSlow)
        assertTrue("P5 never past square to the light", lagFast < pi / 2 && fast.second.dot(x) > 0.5f)
        val key = SpaceOptics.cometTails(at, Vec3.ZERO, null, y)
        assertTrue("P5 with no sun, away from the key light", key.first.dot(y * -1f) > 0.999f)
        val along = SpaceOptics.cometTails(at, x, Vec3.ZERO, y)
        assertTrue("P5 flying straight away from the sun: no lag sideways", along.second.dot(x) > 0.999f)
    }

    // ---- P6 the corona's number ----

    @Test fun p6CoronaCode() {
        for (k in 0 until 64) {
            val seed = k / 64f
            var m = 0f
            while (m <= 1f) {
                val (s, motion) = SpaceOptics.coronaRead(SpaceOptics.coronaCode(seed, m))
                assertTrue("P6 a corona's code gives back its seed (to 1/32) and motion: $seed $m",
                    close(s, kotlin.math.floor(seed * 32) / 32, 1e-4f) && close(motion, m, 2e-3f))
                m += 0.125f
            }
        }
        assertTrue("P6 the code stays between 2 and 3 (the shader's |z| - 2)",
            SpaceOptics.coronaCode(0.999f, 1f) < 3f && SpaceOptics.coronaCode(0f, 0f) >= 2f)
        assertTrue("P6 the shader reads it the same way", SpaceShaders.sunCorona.contains("floor(rp_code * 32.0) / 32.0")
            && SpaceShaders.sunCorona.contains("* 32.0 / 0.96"))
    }

    // ---- P7 sparks ----

    @Test fun p7Sparks() {
        val ice = SpaceOptics.trail(3)
        assertEquals("P7 a black hole throws nothing off: it swallows", 0f, SpaceOptics.trail(0).rate, 0f)
        assertTrue("P7 a pulsar's motes are few and fine, so its core keeps its edge",
            SpaceOptics.trail(4).rate <= 60f && SpaceOptics.trail(4).size <= 0.015f)
        assertTrue("P7 a sun's plasma is warm", SpaceOptics.trail(5).colours.all { it[0] >= it[2] })
        assertTrue("P7 a comet's dust is icy and left behind", ice.backward && ice.colours.first()[2] >= ice.colours.first()[0] - 0.2f
            && ice.colours.last()[2] > ice.colours.last()[0])
        assertTrue("P7 every colour on screen's scale, every life positive",
            (0..5).map { SpaceOptics.trail(it) }.all { t -> t.life > 0f && t.colours.all { c -> c.min() >= 0f && c.max() <= 1f } })
    }

    // ---- P8 the shaders keep the physics ----

    @Test fun p8ShadersKeepThePhysics() {
        assertTrue("P8 the rocky terminator is the tested one", SpaceShaders.rockBody.contains("smoothstep(-0.08, 0.22, rp_ndl)"))
        assertTrue("P8 the ring shadow on the clouds only with a ring", SpaceShaders.gasBody.contains("* rpRinged"))
        // iOS scales the beam by the node's transform; here the beam's plane is in note radii already
        assertTrue("P8 a pulsar's beam is never drawn over its core's disc as seen",
            SpaceShaders.pulsarBeam.contains("rp_k = rp_k * smoothstep(1.0, 1.35, rp_off)"))
        assertTrue("P8 the beams reach the billboard's extent", SpaceStyle.PULSAR.extent >= 6f * 1.05f)
        assertTrue("P8 the disk's Kepler shear", SpaceShaders.bhRing.contains("pow(rp_rin / rp_lc, 1.5)") && close(0.43f, SpaceOptics.DISK_INNER))
    }

    // ---- P9 the black hole's code ----

    @Test fun p9HoleCode() {
        var k = 0f
        while (k <= 1f) {
            var m = 0f
            while (m <= 1f) {
                for (above in listOf(true, false)) {
                    val back = SpaceOptics.holeRead(SpaceOptics.holeCode(k, above, m))
                    assertTrue("P9 a black hole's code gives back its tilt (to 1/255), side and motion: $k $above $m",
                        abs(back.tilt - k) <= 1f / 255 + 1e-4f && back.above == above && abs(back.motion - m) <= 0.02f)
                }
                m += 0.25f
            }
            k += 0.05f
        }
        assertTrue("P9 the code stays within 1 of 2 (the shader's |z| - 2)",
            SpaceOptics.holeCode(1f, true, 1f) < 3f && SpaceOptics.holeCode(1f, false, 1f) > 1f)
        assertTrue("P9 the shader reads it the same way", SpaceShaders.bhRing.contains("floor(rp_v * 256.0)")
            && SpaceShaders.bhRing.contains("rp_kq / 255.0") && SpaceShaders.bhRing.contains("/ 0.96"))
    }

    // ---- E the Earth's maps (assets/earth), their sources, and how the shader reads them ----

    private val earthFolder: File = run {
        // unit tests run from the module; from the repository root as a fallback
        listOf(File("src/main/assets/earth"), File("app/src/main/assets/earth")).firstOrNull { it.isDirectory } ?: File("src/main/assets/earth")
    }

    /** A PNG's or JPEG's pixel size, read from its header. */
    private fun pictureSize(b: ByteArray): Pair<Int, Int>? {
        fun be16(i: Int) = (b[i].toInt() and 0xFF) shl 8 or (b[i + 1].toInt() and 0xFF)
        if (b.size > 24 && b[0] == 0x89.toByte() && b[1] == 0x50.toByte() && b[2] == 0x4E.toByte() && b[3] == 0x47.toByte()) {
            return (be16(16) shl 16 or be16(18)) to (be16(20) shl 16 or be16(22))
        }
        if (b.size <= 4 || b[0] != 0xFF.toByte() || b[1] != 0xD8.toByte()) return null
        var i = 2
        while (i + 9 < b.size && b[i] == 0xFF.toByte()) {
            val marker = b[i + 1].toInt() and 0xFF
            if (marker == 0xFF) { i += 1; continue }
            // a start of frame: C0 to CF but for DHT (C4), JPG (C8) and DAC (CC)
            if (marker in 0xC0..0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) return be16(i + 7) to be16(i + 5)
            i += 2 + be16(i + 2)
        }
        return null
    }

    private val earthMaps = listOf(
        Triple(EarthMaps.DAY, 4096, 2048), Triple(EarthMaps.CLOUDS, 4096, 2048),
        Triple(EarthMaps.LIGHTS, 2048, 1024), Triple(EarthMaps.WATER, 2048, 1024),
    )

    @Test fun e1TheMapsAreTheSizesTheLoaderPacks() {
        var bytes = 0L
        for ((file, w, h) in earthMaps) {
            val data = File(earthFolder, file).readBytes()
            bytes += data.size
            assertEquals("E1 $file is $w x $h, as EarthLoader packs it", w to h, pictureSize(data))
        }
        assertTrue("E1 the four maps stay compressed: under 6 MB together ($bytes bytes)", bytes in 1_000_001..5_999_999)
        assertEquals("E1 the large day map is the 4096 one", 4096, EarthMaps.LARGE_WIDTH)
        assertEquals("E1 the small one is a 2x sample of it", 2, EarthMaps.LARGE_WIDTH / EarthMaps.SMALL_WIDTH)
    }

    @Test fun e2SourcesAndLicences() {
        val text = File(earthFolder, "SOURCES.md").readText()
        val flat = text.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        assertTrue("E2 SOURCES.md sits beside the maps", text.isNotEmpty())
        for ((file, _, _) in earthMaps) {
            val section = text.split("### `$file`").drop(1).firstOrNull() ?: ""
            val part = section.split("\n### ").first().split(Regex("\\s+")).joinToString(" ")
            assertTrue("E2 SOURCES.md gives $file its page, its download with a SHA-256, its credit and how it was made",
                part.contains("- Page: https://") && part.contains("- File: https://") && part.contains("SHA-256 `")
                    && part.contains("- Credit:") && part.contains("- Processing:"))
        }
        assertTrue("E2 the licences are named and linked", flat.contains("generally are not subject to copyright in the United States")
            && flat.contains("https://www.nasa.gov/nasa-brand-center/images-and-media/") && flat.contains("https://gpm.nasa.gov/data/policy"))
        assertTrue("E2 NASA Earth Observatory is credited as it asks", flat.contains("please credit 'NASA Earth Observatory.'")
            && flat.contains("Nothing here implies that NASA endorses the app."))
        assertTrue("E2 the Android loader and shader are named", flat.contains("SpaceShaders.rockBody") && flat.contains("EarthLoader"))
    }

    @Test fun e3HowTheShaderReadsTheMaps() {
        val rock = SpaceShaders.rockBody
        assertTrue("E3 the rocky planet reads both maps", rock.contains("uniform sampler2D rpEarthDay;") && rock.contains("uniform sampler2D rpEarthAux;"))
        assertEquals("E3 the maps wrap round in longitude (GL_REPEAT)", 0x2901, EarthMaps.WRAP_S)
        assertEquals("E3 ... and stop at the poles (GL_CLAMP_TO_EDGE)", 0x812F, EarthMaps.WRAP_T)
        assertTrue("E3 no seam at the date line: the gradients wrap too",
            rock.contains("rp_gx.x = rp_gx.x - round(rp_gx.x)") && rock.contains("textureGrad(rpEarthDay, rp_uv, rp_gx, rp_gy)"))
        assertTrue("E3 longitude 0 faces the eye at rest, north up", rock.contains("0.5 + atan(rp_p.x, rp_p.z) * 0.15915494")
            && rock.contains("0.5 - asin(clamp(rp_p.y, -1.0, 1.0)) * 0.31830989"))
        assertTrue("E3 the glint only on open water, the lights only at night",
            rock.contains("rp_aux.y * (1.0 - smoothstep(0.05, 0.2, rp_lum))") && rock.contains("rp_aux.x * rp_aux.x * rp_night"))
        // the CPU's uv is the shader's
        val (u0, v0) = EarthMaps.uv(z)
        assertTrue("E3 longitude 0 at the map's middle, the equator half way down", close(u0, 0.5f) && close(v0, 0.5f))
        assertTrue("E3 north at the top", close(EarthMaps.uv(y).second, 0f))
        assertTrue("E3 east to the right", EarthMaps.uv(unit(Vec3(0.3f, 0f, 1f))).first > 0.5f)
    }

    // ---- Android: limb darkening, level of detail, styles, packing ----

    @Test fun limbDarkeningCurve() {
        assertTrue("the disc's centre is full brightness", close(SpaceOptics.limbDarkening(1f), 1f))
        assertTrue("the limb keeps 0.22", close(SpaceOptics.limbDarkening(0f), 0.22f, 1e-6f))
        assertTrue("half way: 1 - 0.28 - 0.055", close(SpaceOptics.limbDarkening(0.5f), 0.665f, 1e-6f))
        var last = 0f
        for (k in 0..20) { val v = SpaceOptics.limbDarkening(k / 20f); assertTrue("darker towards the limb", v >= last); last = v }
        assertTrue("the sun shader darkens its limb the same way", SpaceShaders.sunBody.contains("1.0 - 0.56 * rp_lm - 0.22 * rp_lm * rp_lm"))
    }

    @Test fun levelOfDetailTurnsAPointIntoItsBody() {
        // a note of radius 0.5, focal 1000 px: 10 px across at depth 100
        assertTrue(close(SpaceLod.pixels(0.5f, 1000f, 100f), 10f))
        assertEquals(SpaceLod.Level.BODY, SpaceLod.level(SpaceLod.pixels(0.5f, 1000f, 100f)))
        assertEquals(SpaceLod.Level.POINT, SpaceLod.level(SpaceLod.pixels(0.5f, 1000f, 101f)))
        assertEquals("a half-open chunk's notes are half as big", SpaceLod.Level.POINT, SpaceLod.level(SpaceLod.pixels(0.5f, 1000f, 60f, 0.5f)))
        assertEquals("behind the eye: never a body by accident", Float.MAX_VALUE, SpaceLod.pixels(0.5f, 1000f, 0f), 0f)
        assertEquals(64, SpaceLod.maxBodies(1f))
        assertEquals("a slow frame still draws a dozen", 12, SpaceLod.maxBodies(0.1f))
        assertEquals("never more than the buffer holds", 96, SpaceLod.maxBodies(3f))
        assertEquals(1f, SpaceLod.shaderDetail(1f), 0f)
        assertEquals("the finer noise goes first under load", 0f, SpaceLod.shaderDetail(0.8f), 0f)
    }

    @Test fun billboardsHoldEverythingABodyDraws() {
        // in note radii, from the iOS planes: BH ring plane 4.2 wide, a sun's corona 4 bodies,
        // a rocky planet's moon at 2.3 bodies, a gas giant's ring to 2.3 planet radii, a
        // pulsar's beams 6 out, a comet's ion tail 7 long
        assertTrue(SpaceStyle.BLACK_HOLE.extent >= 2.1f)
        assertTrue(SpaceStyle.SUN.extent >= 4f * SpaceStyle.SUN.bodyScale - 1e-4f)
        assertTrue(SpaceStyle.ROCKY.extent >= (2.3f + 0.27f) * SpaceStyle.ROCKY.bodyScale)
        assertTrue(SpaceStyle.GAS_GIANT.extent >= 2.3f * SpaceStyle.GAS_GIANT.bodyScale)
        assertTrue(SpaceStyle.PULSAR.extent >= 6f)
        assertTrue(SpaceStyle.COMET.extent >= 7f)
        assertEquals(listOf(1f, 0.9f, 1.15f, 0.3f, 0.3f, 1.1f), (0..5).map { SpaceStyle.of(it).bodyScale })
        assertEquals("the higher code is a link's A end: suns send, black holes swallow", listOf(0, 1, 2, 3, 4, 5), SpaceStyle.entries.map { it.code })
    }

    @Test fun stylesFollowLinks() {
        assertEquals(SpaceStyle.COMET, SpaceStyle.forLinks(0))
        assertEquals(SpaceStyle.PULSAR, SpaceStyle.forLinks(1))
        assertEquals(SpaceStyle.ROCKY, SpaceStyle.forLinks(2))
        assertEquals(SpaceStyle.GAS_GIANT, SpaceStyle.forLinks(4))
        assertEquals(SpaceStyle.SUN, SpaceStyle.forLinks(5))
        assertEquals(SpaceStyle.BLACK_HOLE, SpaceStyle.forLinks(8))
        // a star: the hub has 5 links, the spokes 1, a lone note none
        val edges = intArrayOf(0, 1, 0, 2, 0, 3, 0, 4, 0, 5)
        assertEquals(listOf(5, 4, 4, 4, 4, 4, 3), SpaceStyle.assign(7, edges).map { it.toInt() })
    }

    @Test fun earthMapsPackAsTheShaderReadsThem() {
        val day = intArrayOf(0xFF102030.toInt(), 0xFFA0B0C0.toInt())
        val clouds = intArrayOf(0xFF808080.toInt(), 0xFFFEFEFE.toInt())
        val out = ByteArray(8)
        EarthMaps.packDay(day, clouds, out, 0, 2)
        assertEquals(listOf(0x10, 0x20, 0x30, 0x80, 0xA0, 0xB0, 0xC0, 0xFE), out.map { it.toInt() and 0xFF })
        val aux = ByteArray(6)
        EarthMaps.packAux(intArrayOf(0xFF333333.toInt()), intArrayOf(0xFFFFFFFF.toInt()), aux, 2, 1)
        assertEquals(listOf(0, 0, 0x33, 0xFF, 0, 0), aux.map { it.toInt() and 0xFF })
        assertTrue("the large map only where it fits", EarthMaps.useLarge(4096, 512L shl 20, 1f))
        assertFalse(EarthMaps.useLarge(2048, 512L shl 20, 1f))
        assertFalse(EarthMaps.useLarge(4096, 256L shl 20, 1f))
        assertFalse(EarthMaps.useLarge(4096, 512L shl 20, 0.5f))
    }

    @Test fun moonAndBeamsWrapWithTheClock() {
        assertEquals("the moon turns a whole number of times in the clock's period", 160.0,
            SpaceOptics.MOON_RATE * SpaceOptics.CLOCK_PERIOD / (2 * PI), 1e-3)
        val a = SpaceOptics.moonOffset(0f, 0.3f)
        val b = SpaceOptics.moonOffset(SpaceOptics.CLOCK_PERIOD, 0.3f)
        assertTrue("no jump at the wrap", (a - b).length() < 2e-3f)
        assertTrue("the moon orbits 2.3 bodies out", close(a.length(), 2.3f * SpaceStyle.ROCKY.bodyScale, 1e-4f))
        assertTrue("nor for the beams", close(SpaceOptics.beamPhase(0f, 0.4f), SpaceOptics.beamPhase(SpaceOptics.CLOCK_PERIOD, 0.4f), 2e-3f))
        assertTrue("a seed is 0...1", (0 until 500).all { SpaceOptics.seed(it) in 0f..1f })
        for (k in 0 until 50) {
            val axis = SpaceOptics.tiltedAxis(k / 50f, 0.5f)
            assertTrue("an axis leans at most its tilt", close(axis.length(), 1f) && acos(axis.dot(y)) <= 0.5f + 1e-4f)
        }
    }

    // ---- Android: the bodies and beams a frame picks ----

    /** Six notes in a row, one of each style by links, and a far one. */
    private fun scene(): Pair<Octree, MapGraph> {
        val n = 26
        val positions = FloatArray(n * 3)
        for (i in 0 until n) { positions[3 * i] = i * 2f }
        // node 0 with 8 links: a black hole; 1 with 5: a sun; the rest fewer
        val pairs = mutableListOf(0 to 1)
        for (k in 2..8) pairs += 0 to (10 + k)
        for (k in 2..5) pairs += 1 to (18 + k)
        pairs += 2 to 3
        val edges = pairs.flatMap { listOf(it.first, it.second) }.toIntArray()
        val graph = MapGraph(positions, SpaceStyle.assign(n, edges), edges)
        return Octree.build(graph, leafCapacity = 8, palette = SpacePalette.rgb) to graph
    }

    private fun openPlan(tree: Octree): FramePlan {
        val plan = FramePlan(tree.leafCount)
        for (leaf in 0 until tree.leafCount) { plan.leafState[leaf * 4 + 3] = 1f; plan.detailLeaves.add(leaf) }
        return plan
    }

    @Test fun nearNotesBecomeBodiesFarToNearByStyle() {
        val (tree, _) = scene()
        val bodies = SpaceBodies(tree, nodeRadius = 0.5f)
        val plan = openPlan(tree)
        val near = OrbitCamera(target = Vec3(4f, 0f, 0f), distance = 12f, yaw = 0f, pitch = 0f)
        val vp = Mat4.multiply(near.projection(1f), near.view())
        val focal = near.focalPixels(1000f)
        val count = bodies.update(plan, vp, near.eye(), x, y, focal, maxBodies = 64, time = 0f)
        fun depth(node: Int) = vp[3] * tree.positions[3 * node] + vp[7] * tree.positions[3 * node + 1] + vp[11] * tree.positions[3 * node + 2] + vp[15]
        assertTrue("near notes are bodies: $count", count > 0)
        for (j in 0 until count) {
            val node = bodies.nodes[j]
            val w = vp[3] * tree.positions[3 * node] + vp[7] * tree.positions[3 * node + 1] + vp[11] * tree.positions[3 * node + 2] + vp[15]
            assertTrue("each is at least BODY_PIXELS across", SpaceLod.pixels(0.5f, focal, w) >= SpaceLod.BODY_PIXELS)
            assertTrue(bodies.isBody(node))
        }
        for (s in 0 until 6) {
            assertTrue("grouped by style", bodies.styleStart[s] <= bodies.styleStart[s + 1])
            for (j in bodies.styleStart[s] until bodies.styleStart[s + 1]) {
                assertEquals(s, tree.groups[bodies.nodes[j]].toInt())
                if (j > bodies.styleStart[s]) {
                    // by depth along the view, as billboards drawn over each other need
                    assertTrue("far to near within a style", depth(bodies.nodes[j - 1]) >= depth(bodies.nodes[j]) - 1e-4f)
                }
            }
        }
        assertEquals("every body's point hides", count, bodies.maskChanges.size)
        assertTrue((0 until bodies.maskChanges.size).all { bodies.maskChanges[it] > 0 })
        // the cap keeps the nearest
        val few = SpaceBodies(tree, nodeRadius = 0.5f)
        assertEquals(2, few.update(plan, vp, near.eye(), x, y, focal, maxBodies = 2, time = 0f))
        val second = (0 until count).map { depth(bodies.nodes[it]) }.sorted()[1]
        assertTrue("the cap keeps the nearest", (0 until 2).all { depth(few.nodes[it]) <= second + 1e-4f })
        // the camera goes far: every body is a point again, and its point shows
        val far = OrbitCamera(target = Vec3(4f, 0f, 0f), distance = 5000f, yaw = 0f, pitch = 0f)
        val vpFar = Mat4.multiply(far.projection(1f), far.view())
        assertEquals(0, bodies.update(plan, vpFar, far.eye(), x, y, far.focalPixels(1000f), 64, 0f))
        assertEquals(count, bodies.maskChanges.size)
        assertTrue((0 until bodies.maskChanges.size).all { bodies.maskChanges[it] < 0 })
        assertEquals(0, bodies.beamCount)
    }

    @Test fun bodiesLinksBecomeBeamsSentByTheHigherStyle() {
        val (tree, _) = scene()
        val bodies = SpaceBodies(tree, nodeRadius = 0.5f)
        val plan = openPlan(tree)
        val near = OrbitCamera(target = Vec3(4f, 0f, 0f), distance = 12f, yaw = 0f, pitch = 0f)
        val vp = Mat4.multiply(near.projection(1f), near.view())
        bodies.update(plan, vp, near.eye(), x, y, near.focalPixels(1000f), 64, 0f)
        assertTrue("a body's links are beams: ${bodies.beamCount}", bodies.beamCount > 0)
        val ends = HashSet<String>()
        for (b in 0 until bodies.beamCount) {
            val o = b * SpaceBodies.BEAM_STRIDE
            assertTrue("the A end has the higher style code", bodies.beams[o + 3] >= bodies.beams[o + 7])
            assertTrue("a link's seed is 0...15", bodies.beams[o + 8] in 0f..15f)
            // the beam stops at the bodies' edges, not their centres
            val ax = bodies.beams[o]; val bx = bodies.beams[o + 4]
            assertTrue("trimmed at both ends", abs(ax - Math.round(ax / 2f) * 2f) > 1e-3f || abs(bx - Math.round(bx / 2f) * 2f) > 1e-3f)
            assertTrue("each link once", ends.add("${min(ax, bx)}:${max(ax, bx)}"))
        }
    }
}
