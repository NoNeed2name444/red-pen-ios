package com.stethoscore.app.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tan

/**
 * The Space theme's depth fade and near-only loading, mirroring iOS SpaceDepthTests (cases D1
 * to D12, the same numbers): the fade curve (D1), the band following the camera's focus at
 * every zoom, along the view's depth (D2), the Graphics tier's reach (D3), Increase Contrast
 * (D4), what is fully faded is not drawn and dissolves with no pop (D5), shader detail by size
 * on screen (D6), the point level with its gap (D7, D8), the view volume (D9), the shaders'
 * fade and detail pieces (D10, GLSL here), the fade colour against the sky (D11) and the
 * morphing noise octaves (D12). Plus the iOS defect fixed in this port: a focus at or behind
 * the eye has no band.
 */
class SpaceDepthTest {
    private fun near(a: Float, b: Float, tolerance: Float = 1e-5f) = abs(a - b) <= tolerance
    private val pi = PI.toFloat()

    // ---- D1 the curve ----

    private val band = SpaceDepthBand(10f, 30f, 1.25f, 1f)

    @Test fun d1Curve() {
        val mid = band.fade(20f)
        assertTrue("D1 crisp up to the start, gone at the end",
            band.fade(0f) == 0f && band.fade(10f) == 0f && band.fade(30f) == 1f && band.fade(500f) == 1f)
        assertTrue("D1 f = clamp((z - start) / (end - start), 0, 1)^k: $mid", near(mid, 0.5f.pow(1.25f)))
        var rising = true
        var last = -1f
        for (k in 0..400) {
            val f = band.fade(k * 0.1f)
            if (f < last) rising = false
            last = f
        }
        assertTrue("D1 never fades back in as depth grows", rising)
        assertTrue("D1 additive light goes to nothing: light = 1 - f", near(band.light(20f), 1 - mid) && band.light(30f) == 0f)
        assertTrue("D1 a band never set fades nothing",
            SpaceDepthBand.OFF.fade(1000f) == 0f && SpaceDepthBand.OFF.uniform.contentEquals(floatArrayOf(0f, 0f, 0f, 0f)))
    }

    // ---- D2 the band follows the focus ----

    @Test fun d2BandFollowsTheFocus() {
        var focusCrisp = true
        var sameAtEveryScale = true
        for (focus in listOf(0.01f, 0.3f, 1f, 7f, 40f, 900f)) {
            val b = SpaceDepth.band(focus, GraphicsTier.HIGH)
            if (!(b.fade(focus) == 0f && b.crisp(focus) && !b.gone(focus))) focusCrisp = false
            val unit = SpaceDepth.band(1f, GraphicsTier.HIGH)
            if (focus >= SpaceDepth.NEAREST_FOCUS) {
                var z = 0f
                while (z <= 4f) {
                    if (!near(b.fade(z * focus), unit.fade(z), 1e-4f)) sameAtEveryScale = false
                    z += 0.25f
                }
            }
        }
        assertTrue("D2 what the camera looks at is crisp at every zoom", focusCrisp)
        assertTrue("D2 start and end are multiples of the focus's depth: a small note up close fades as the whole map", sameAtEveryScale)
        val eye = Vec3(0f, 0f, 10f)
        val ahead = Vec3(0f, 0f, -1f)
        val straight = SpaceDepth.depth(Vec3(0f, 0f, 0f), eye, ahead)
        val aside = SpaceDepth.depth(Vec3(6f, -4f, 0f), eye, ahead)
        assertTrue("D2 depth is view-space z: a body off to the side at the same z fades the same: $straight $aside",
            straight == 10f && aside == 10f)
        val farSide = Vec3(0f, 0f, -8f)
        val b10 = SpaceDepth.band(10f, GraphicsTier.HIGH)
        val before = b10.fade(SpaceDepth.depth(farSide, eye, ahead))
        val turnedEye = Vec3(0f, 0f, -10f)
        val turnedAhead = Vec3(0f, 0f, 1f)
        val after = b10.fade(SpaceDepth.depth(farSide, turnedEye, turnedAhead))
        val nearSideAfter = b10.fade(SpaceDepth.depth(Vec3(0f, 0f, 8f), turnedEye, turnedAhead))
        assertTrue("D2 turned round the focus, the far side sharpens and the near side fades: $before $after $nearSideAfter",
            before > 0.3f && after == 0f && nearSideAfter > 0.3f)
    }

    /** The iOS defect fixed here: a focus at or behind the eye leaves nothing to follow, so no fade. */
    @Test fun d2FocusAtOrBehindTheEyeIsOff() {
        for (focus in listOf(0f, -0.01f, -3f, -900f, Float.NEGATIVE_INFINITY)) {
            for (tier in GraphicsTier.entries) {
                assertEquals("D2 focus at $focus has no band", SpaceDepthBand.OFF, SpaceDepth.band(focus, tier))
                assertEquals("D2 nor with Increase Contrast", SpaceDepthBand.OFF, SpaceDepth.band(focus, tier, contrast = true))
            }
        }
        val off = SpaceDepth.band(-5f, GraphicsTier.HIGH)
        assertTrue("D2 so nothing in front fades, culls or dissolves",
            off.fade(1e6f) == 0f && !off.culls && !off.gone(1e6f) && off.dissolve(1e6f) == 1f && off.crisp(0f))
        // a focus just in front still has its band, at the nearest focus
        val tiny = SpaceDepth.band(0.001f, GraphicsTier.HIGH)
        assertTrue("D2 a focus just in front of the eye keeps the nearest band",
            near(tiny.start, SpaceDepth.NEAREST_FOCUS * 1.15f) && tiny.culls)
        // eye walked past the focus: the camera's own target behind it
        val eye = Vec3(0f, 0f, -2f)
        val forward = Vec3(0f, 0f, -1f)
        val behind = SpaceDepth.depth(Vec3(0f, 0f, 0f), eye, forward)
        assertTrue("D2 a focus behind the eye has negative depth: $behind", behind < 0f)
        assertEquals(SpaceDepthBand.OFF, SpaceDepth.band(behind, GraphicsTier.SMOOTH))
    }

    // ---- D3 the tier sets the reach ----

    @Test fun d3TierReach() {
        val high = SpaceDepth.band(10f, GraphicsTier.HIGH)
        val smooth = SpaceDepth.band(10f, GraphicsTier.SMOOTH)
        assertTrue("D3 Smooth pulls the end in (less drawn), High pushes it out: $smooth $high",
            smooth.end < high.end && smooth.start > 10f && high.start > 10f)
        assertTrue("D3 every tier reaches the background, so what is past it is not drawn", high.culls && smooth.culls)
    }

    // ---- D4 Increase Contrast ----

    @Test fun d4IncreaseContrast() {
        val plain = SpaceDepth.band(10f, GraphicsTier.HIGH)
        val contrast = SpaceDepth.band(10f, GraphicsTier.HIGH, contrast = true)
        assertTrue("D4 with Increase Contrast the fade starts later and stops short of the sky",
            contrast.start > plain.start && contrast.fade(1e6f) < 1f && contrast.fade(1e6f) > 0.3f)
        assertTrue("D4 nothing stopped short is culled or dissolved",
            !contrast.culls && !contrast.gone(1e6f) && contrast.dissolve(1e6f) == 1f)
    }

    // ---- D5 fully faded is not drawn, with no pop ----

    @Test fun d5GoneWithNoPop() {
        val plain = SpaceDepth.band(10f, GraphicsTier.HIGH)
        assertTrue("D5 past the end is gone, before it is not", plain.gone(plain.end) && !plain.gone(plain.end - 0.01f))
        var dissolveSmooth = true
        var lastDissolve = 1f
        for (k in 0..2000) {
            val z = plain.start + (plain.end - plain.start) * k / 2000f
            val d = plain.dissolve(z)
            if (abs(d - lastDissolve) > 0.01f) dissolveSmooth = false
            lastDissolve = d
        }
        assertTrue("D5 a solid body keeps its opacity until nearly faded, then goes smoothly to nothing at the end: ${plain.dissolve(plain.end)}",
            plain.dissolve(plain.start) == 1f && dissolveSmooth && plain.dissolve(plain.end) == 0f)
        val lastBit = plain.dissolve(plain.end - (plain.end - plain.start) * 0.001f)
        assertTrue("D5 just before it is culled nothing of it is left to pop: $lastBit", lastBit < 0.001f)
        val atHalf = plain.start + (plain.end - plain.start) * 0.85f.pow(1 / SpaceDepth.EXPONENT)
        assertTrue("D5 the dissolve starts only where f is 0.85", near(plain.dissolve(atHalf - 0.01f), 1f, 1e-3f))
    }

    // ---- D6 shader detail by size on screen ----

    @Test fun d6DetailBySize() {
        assertTrue("D6 up close the whole detail, every pixel the same as before",
            SpaceDepth.detail(SpaceShaders.DETAIL_HIGH) == 1f && SpaceDepth.detail(400f) == 1f)
        assertTrue("D6 small on screen, the simple path",
            SpaceDepth.detail(SpaceShaders.DETAIL_LOW) == 0f && SpaceDepth.detail(1f) == 0f)
        var detailSmooth = true
        var lastDetail = 0f
        for (k in 0..4000) {
            val px = k * 0.01f
            val w = SpaceDepth.detail(px)
            if (w < lastDetail || w - lastDetail > 0.002f) detailSmooth = false
            lastDetail = w
        }
        assertTrue("D6 detail falls gradually and smoothly as it zooms out: no step anywhere", detailSmooth)
        val focal = SpaceDepth.focal(800f, 55 * pi / 180)
        assertTrue("D6 size on screen is the Performance theme's (radius x focal / depth)",
            near(SpaceDepth.pixelRadius(2f, 10f, 800f, 55 * pi / 180), SpaceDepth.pixelRadius(2f, 10f, focal))
                && near(focal, 400 / tan(27.5f * pi / 180), 1e-2f))
    }

    // ---- D7 the point level, with a gap ----

    @Test fun d7PointLevelWithAGap() {
        var state = SpaceBodyLevel.BODY
        var flips = 0
        for (k in 0 until 200) {
            val px = 1.85f + 0.25f * sin(k * 0.3f)
            val next = SpaceDepth.level(state, px, 0f, gone = false, inView = true)
            if (next != state) flips++
            state = next
        }
        assertTrue("D7 a body at the edge of the point size does not flicker: $flips", flips == 0 && state == SpaceBodyLevel.BODY)
        val toPoint = SpaceDepth.level(SpaceBodyLevel.BODY, 1.4f, 0f, gone = false, inView = true)
        val staysPoint = SpaceDepth.level(SpaceBodyLevel.POINT, 2.0f, 0f, gone = false, inView = true)
        val backToBody = SpaceDepth.level(SpaceBodyLevel.POINT, 2.3f, 0f, gone = false, inView = true)
        assertTrue("D7 under 1.5 points a point; back to its body only from 2.25",
            toPoint == SpaceBodyLevel.POINT && staysPoint == SpaceBodyLevel.POINT && backToBody == SpaceBodyLevel.BODY)
        val fadedPoint = SpaceDepth.level(SpaceBodyLevel.BODY, 2.9f, 0.7f, gone = false, inView = true)
        val crispBody = SpaceDepth.level(SpaceBodyLevel.BODY, 2.9f, 0.2f, gone = false, inView = true)
        assertTrue("D7 detail drops sooner only where the body has mostly faded (f 0.6)",
            fadedPoint == SpaceBodyLevel.POINT && crispBody == SpaceBodyLevel.BODY)
        assertTrue("D7 outside the view or past the band: gone",
            SpaceDepth.level(SpaceBodyLevel.BODY, 50f, 0f, gone = false, inView = false) == SpaceBodyLevel.GONE
                && SpaceDepth.level(SpaceBodyLevel.POINT, 50f, 1f, gone = true, inView = true) == SpaceBodyLevel.GONE)
        assertTrue("D7 coming back into view it takes the level its size says",
            SpaceDepth.level(SpaceBodyLevel.GONE, 40f, 0f, gone = false, inView = true) == SpaceBodyLevel.BODY
                && SpaceDepth.level(SpaceBodyLevel.GONE, 1f, 0f, gone = false, inView = true) == SpaceBodyLevel.POINT)
    }

    // ---- D8 the point is the body's size ----

    @Test fun d8PointIsTheBodysSize() {
        assertTrue("D8 a point is drawn at the body's own size on screen, never under a point",
            SpaceDepth.pointRadius(1.4f) == 1.4f && SpaceDepth.pointRadius(0.2f) == 1f)
    }

    // ---- D9 the view volume ----

    @Test fun d9ViewVolume() {
        // iOS GraphPerfCamera: yaw 0.7, pitch 0.3, distance 20, fovY pi / 3
        val orbit = OrbitCamera(target = Vec3(0f, 0f, 0f), distance = 20f, yaw = 0.7f, pitch = 0.3f, fovY = pi / 3)
        val theirs = orbit.frustum(390f, 844f, 0.1f, 100f)
        val ours = SpaceDepth.frustum(orbit.eye(), orbit.forward(), orbit.right(), orbit.up(), orbit.fovY, 390f, 844f, 0.1f, 100f)
        assertEquals("D9 the same view volume as the map's camera", theirs.planes, ours.planes)
        assertTrue("D9 the camera's forward is eye to target", (orbit.forward() - (orbit.target - orbit.eye()).normalized()).length() < 1e-5f)
        val volume = SpaceDepth.frustum(Vec3(0f, 0f, 10f), Vec3(0f, 0f, -1f), Vec3(1f, 0f, 0f), Vec3(0f, 1f, 0f),
            55 * pi / 180, 390f, 844f, 0.01f, 1000f)
        assertTrue("D9 a body in front is in view", SpaceDepth.inView(volume, Vec3(0f, 0f, 0f), 0.2f, 4f))
        assertFalse("D9 a body behind the camera is not", SpaceDepth.inView(volume, Vec3(0f, 0f, 14f), 0.2f, 4f))
        assertFalse("D9 a body far off to the side is not", SpaceDepth.inView(volume, Vec3(30f, 0f, 0f), 0.2f, 4f))
        val edgeX = 10 * tan(atan(tan(27.5f * pi / 180) * 390 / 844))
        val offLeft = Vec3(-edgeX - 1, 0f, 0f)
        assertTrue("D9 a comet just off screen whose tail reaches in is kept",
            !SpaceDepth.inView(volume, offLeft, 0.2f, 1f) && SpaceDepth.inView(volume, offLeft, 0.2f, SpaceDepth.reachOfLook(3)))
        assertTrue("D9 every look reaches past its body", (0..5).all { SpaceDepth.reachOfLook(it) >= 3f })
    }

    // ---- D10 the shaders' pieces (GLSL) ----

    @Test fun d10ShaderPieces() {
        val fragments = SpaceStyle.entries.associate { it.label to SpaceShaders.fragment(it) } + ("link" to SpaceShaders.link)
        val unfaded = fragments.filter { !it.value.contains("uniform vec4 rpFade;") || !it.value.contains("rp_dfF") }.keys
        assertTrue("D10 every Space shader fades by depth: $unfaded", unfaded.isEmpty())
        val c = SpaceShaders.fadeLinear
        val colourText = "vec3(" + c.joinToString(", ") { SpaceShaders.literal(it) } + ")"
        val fadeMix = "rp_col = mix(rp_col, $colourText, rp_dfF);"
        assertTrue("D10 the colour faded towards is the sky's near-black, in linear light: $colourText", SpaceShaders.FADE.contains(fadeMix))
        assertTrue("D10 additive light only towards nothing", SpaceShaders.FADE.contains("rp_col = rp_col * (1.0 - rp_dfF);"))
        // each style: its solid body through the faded body ending, its glows through the glow ending
        val bodies = mapOf(SpaceStyle.SUN to listOf("sunBody("), SpaceStyle.ROCKY to listOf("rockBody(", "moonBody("),
            SpaceStyle.GAS_GIANT to listOf("gasBody("), SpaceStyle.PULSAR to listOf("pulsarCore("), SpaceStyle.COMET to listOf("cometNucleus("),
            SpaceStyle.BLACK_HOLE to listOf("vec3(0.0)"))
        val glows = mapOf(SpaceStyle.SUN to listOf("sunCorona("), SpaceStyle.ROCKY to listOf("halo("), SpaceStyle.GAS_GIANT to listOf("ring,", "halo("),
            SpaceStyle.PULSAR to listOf("pulsarGlow(", "pulsarBeam("), SpaceStyle.COMET to listOf("cometComa(", "cometTail(", "cometDust("),
            SpaceStyle.BLACK_HOLE to listOf("bhRing("))
        val badBodies = bodies.filter { (s, calls) -> calls.any { !SpaceShaders.fragment(s).contains("rpFadedBody($it") } }.keys
        val badGlows = glows.filter { (s, calls) -> calls.any { !SpaceShaders.fragment(s).contains("rpFadedGlow($it") } }.keys
        assertTrue("D10 a solid body dissolves into the sky's colour; additive light only towards nothing: $badBodies $badGlows",
            badBodies.isEmpty() && badGlows.isEmpty())
        val undissolved = SpaceStyle.entries.filter { !SpaceShaders.fragment(it).contains("* rpDissolve(rp_dfF);") }
        assertTrue("D10 every body takes the last of its dissolve on its opacity: $undissolved", undissolved.isEmpty())
        assertTrue("D10 a link fades by each fragment's depth, a body by its centre's",
            SpaceShaders.link.contains("float rp_dfF = rpDepthFade(vDepth);") && SpaceShaders.linkVertex.contains("vDepth = gl_Position.w;")
                && SpaceStyle.entries.all { SpaceShaders.fragment(it).contains("rpDepthFade(dot(c - uEye, uForward))") })
        val detailed = listOf(SpaceStyle.BLACK_HOLE, SpaceStyle.SUN, SpaceStyle.ROCKY, SpaceStyle.GAS_GIANT)
        val undetailed = detailed.filter { val f = SpaceShaders.fragment(it); !(f.contains("uniform float rpFocal;") && f.contains("rpDetailFor(c, r);")) }
        val pieces = mapOf("bhRing" to SpaceShaders.bhRing, "sunBody" to SpaceShaders.sunBody, "rockBody" to SpaceShaders.rockBody,
            "moonBody" to SpaceShaders.moonBody, "gasBody" to SpaceShaders.gasBody)
        val noMorph = pieces.filter { !it.value.contains("rp_dl") }.keys
        val stepped = (SpaceStyle.entries.map { SpaceShaders.fragment(it) } + SpaceShaders.link).filter { it.contains("rpDetail > 0.5") }
        assertTrue("D10 granulation, lensing, clouds, ring shadows and city lights step down by size, with no switch left: $undetailed $noMorph ${stepped.size}",
            undetailed.isEmpty() && noMorph.isEmpty() && stepped.isEmpty())
        assertTrue("D10 the shaders' detail band is SpaceDepth's", SpaceShaders.DETAIL.contains(
            "smoothstep(" + SpaceShaders.literal(SpaceShaders.DETAIL_LOW) + ", " + SpaceShaders.literal(SpaceShaders.DETAIL_HIGH) + ", rp_lodPx)"))
        assertTrue("D10 the city lights and the ring's shadow go with size alone, so a lower tier keeps them up close",
            SpaceShaders.rockBody.contains("(1.0 - 0.85 * rp_cloud) * rp_lod;") && SpaceShaders.gasBody.contains("* rpRinged * rp_lod;"))
        assertTrue("D10 the points, links and summaries fade as light too",
            SpaceShaders.FADE.contains("rp_dfF = pow(clamp((rp_dfZ - rpFade.x) / rp_dfW, 0.0, 1.0), max(rpFade.z, 0.0001)) * rpFade.w;"))
    }

    // ---- D11 the fade colour against the sky ----

    @Test fun d11FadeColourAgainstTheSky() {
        val pole = floatArrayOf(0.004f, 0.006f, 0.022f)
        val band0 = floatArrayOf(0.018f, 0.032f, 0.095f)
        val f = SpaceShaders.FADE_SRGB
        val between = (0 until 3).all { f[it] >= pole[it] && f[it] <= band0[it] }
        val gap = max((0 until 3).maxOf { f[it] - pole[it] }, (0 until 3).maxOf { band0[it] - f[it] })
        assertTrue("D11 between the sky's darkest and its band, close to both (no grey veil, no dark hole): $gap", between && gap < 0.05f)
        assertTrue("D11 the sky's blue, not a grey", f[2] > f[1] * 2 && f[1] > f[0])
        assertTrue("D11 the linear colour is the sRGB one to the power 2.2",
            (0 until 3).all { near(SpaceShaders.fadeLinear[it], f[it].pow(2.2f), 1e-6f) })
    }

    // ---- D12 the noise octaves morph ----

    @Test fun d12OctavesMorph() {
        var exact = true
        var ends = true
        var morphSmooth = true
        for (k in 0 until 50) {
            val p = Vec3(k * 0.37f, k * 0.11f + 2, 5 - k * 0.23f)
            if (ShaderKit.fbm(p, 5, 3, 1f) != ShaderKit.fbm(p, 5)) exact = false
            if (!near(ShaderKit.fbm(p, 5, 3, 0f), ShaderKit.fbm(p, 3))) ends = false
            var previous = ShaderKit.fbm(p, 5, 3, 0f)
            for (j in 1..100) {
                val v = ShaderKit.fbm(p, 5, 3, j / 100f)
                if (abs(v - previous) > 0.01f) morphSmooth = false
                previous = v
            }
        }
        assertTrue("D12 at full weight the octaves are the old ones to the bit (the look up close is unchanged)", exact)
        assertTrue("D12 at none they are the simple path's, and between they morph with no step", ends && morphSmooth)
        assertTrue("D12 the shaders use the morphing octaves",
            SpaceShaders.gasBody.contains("float rp_tb_k = rp_tb_o < 3 ? 1.0 : rp_dl;")
                && SpaceShaders.moonBody.contains("float rp_mh_k = rp_mh_o < 2 ? 1.0 : rp_dl;"))
    }

    // ---- on Android: the bodies a frame picks follow the band ----

    @Test fun bodiesPastTheBandAreGoneAndTheEdgeHasAGap() {
        // a row of suns running away from the camera, every one big enough on screen to be a body
        val n = 24
        val positions = FloatArray(n * 3)
        for (i in 0 until n) positions[3 * i + 2] = -2f * i
        val graph = MapGraph(positions, ByteArray(n) { SpaceStyle.SUN.code.toByte() }, IntArray(0))
        val tree = Octree.build(graph, leafCapacity = 8, palette = SpacePalette.rgb)
        val plan = FramePlan(tree.leafCount)
        for (leaf in 0 until tree.leafCount) { plan.leafState[leaf * 4 + 3] = 1f; plan.detailLeaves.add(leaf) }
        val camera = OrbitCamera(target = Vec3(0f, 0f, 0f), distance = 12f, yaw = 0f, pitch = 0f)
        val vp = Mat4.multiply(camera.projection(1f), camera.view())
        val focal = camera.focalPixels(1000f)
        fun depth(node: Int) = vp[3] * tree.positions[3 * node] + vp[7] * tree.positions[3 * node + 1] + vp[11] * tree.positions[3 * node + 2] + vp[15]
        val unfaded = SpaceBodies(tree, nodeRadius = 0.5f)
        val all = unfaded.update(plan, vp, camera.eye(), camera.right(), camera.up(), focal, 96, 0f)
        val band = SpaceDepth.band(SpaceDepth.depth(camera.target, camera.eye(), camera.forward()), GraphicsTier.HIGH)
        assertTrue("without a band the far suns are bodies too", (0 until all).any { band.gone(depth(unfaded.nodes[it])) })
        val faded = SpaceBodies(tree, nodeRadius = 0.5f)
        val kept = faded.update(plan, vp, camera.eye(), camera.right(), camera.up(), focal, 96, 0f, band)
        assertTrue("near suns stay bodies: $kept", kept > 0 && kept < all)
        assertTrue("nothing past the band's end is a body", (0 until kept).none { band.gone(depth(faded.nodes[it])) })
        // the edge between point and body has SpaceDepth's gap, scaled to BODY_PIXELS across
        val edge = SpaceLod.BODY_PIXELS
        assertEquals(SpaceBodyLevel.POINT, faded.level(false, edge, 0f))
        assertEquals(SpaceBodyLevel.BODY, faded.level(false, edge * 1.01f, 0f))
        assertEquals("once a body it stays one a while", SpaceBodyLevel.BODY, faded.level(true, edge * 0.7f, 0f))
        assertEquals(SpaceBodyLevel.POINT, faded.level(true, edge * 0.66f, 0f))
        assertEquals("mostly faded, it is a point sooner", SpaceBodyLevel.POINT, faded.level(true, edge * 1.3f, 0.7f))
        assertTrue(abs(SpaceBodies.KEEP - 1.5f / 2.25f) < 1e-6f)
    }
}
