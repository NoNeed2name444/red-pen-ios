package com.stethoscore.app.ui.ward

import org.junit.Test
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// A port of upstream/ios/RedPen/Tests/WardLightSliceTests.swift, same cases
// and numbers: how far each look's lights reach, how an image is cut so one
// serves every size of a rounded rectangle, what it is keyed by, and, by
// drawing both with a Gaussian, that stretching a cut image gives the picture
// drawing the shape at the larger size gives.
class WardLightSliceTest {

    private val scale = 3.0
    private fun px(x: Double) = wardRounded(x * scale).toInt()
    private val lowReach = WardLightSlice.reach(WardRelief.raised(WardLift.low, dark = false)) // 8
    private val midReach = WardLightSlice.reach(WardRelief.raised(WardLift.mid, dark = false)) // 18
    private val rounded16 = WardFaceShape.Rounded(16.0, continuous = true)
    private val pill = WardFaceShape.Capsule(continuous = true)

    @Test fun reach() = checks {
        for (dark in listOf(false, true)) {
            val reaches = WardLift.entries.map { WardLightSlice.reach(WardRelief.raised(it, dark)) }
            check("raised reach, low to peak: offset plus 1.5 blur radii, rounded up, one spare (${if (dark) "dark" else "light"})",
                reaches == listOf(8, 18, 27, 36), "$reaches")
            check("an inset face reaches as far as a raised one", WardLift.entries.all {
                WardLightSlice.reach(WardRelief.inset(it, dark)) == WardLightSlice.reach(WardRelief.raised(it, dark))
            })
            check("the reach grows with the lift", reaches == reaches.sorted() && reaches.toSet().size == 4)
            val rest = WardLift.entries.map { WardLightSlice.reach(WardPress.spec(it, depth = 0.0, dark = dark)) }
            // a button at rest keeps only its small rim (the owner, 14 Oct; WardReliefTest's rimReach)
            check("a pressable face at rest reaches only its rim, short of a raised one (${if (dark) "dark" else "light"})",
                rest.zip(reaches).all { (a, b) -> a < b } && rest == listOf(6, 7, 7, 7), "$rest")
        }
        val unlit = WardReliefLight(0, 0.0, 9.0, 9.0, 9.0)
        check("a light that is not lit reaches nowhere", WardLightSlice.reach(of = unlit) == 0.0)
    }

    private fun key(plan: WardLightPlan, look: WardLightLook = WardLightLook.raised, lift: WardLift = WardLift.low,
                    control: Boolean = false, dark: Boolean = false, strong: Boolean = false, fill: Long = 0xF2F4F8FFL,
                    scale: Double = 3.0): WardLightKey =
        WardLightSlice.key(plan, look, lift, control, dark, strong, fill, scale)

    @Test fun theCut() = checks {
        // a card: radius 16, continuous, standing low
        val card = WardLightSlice.plan(rounded16, 300.0, 120.0, reach = lowReach, inner = false, scale = scale)
        if (card != null) {
            check("a card is cut both ways", card.stretchX && card.stretchY)
            // curve 16 x 1.53 = 24.48 -> 25; cap = pad 8 + curve 25 + reach 8
            check("its caps hold the pad, the corner's curve and the lights' reach",
                card.capX == 41 && card.capY == 41 && card.pad == 8, "$card")
            check("the cut image is two caps and a core", card.imageWidth == 2 * 41 + WardLightSlice.core &&
                card.imageHeight == 2 * 41 + WardLightSlice.core, "${card.imageWidth} x ${card.imageHeight}")
            check("a cut axis is not keyed by its size", card.keyWidth == 0 && card.keyHeight == 0)
            check("the shape is drawn at the least it needs, with the radius it really has",
                card.width == 68.0 && card.height == 68.0 && card.shape == rounded16)
            val shown = WardLightPlan.shown(300.0, 120.0, card.pad)
            check("shown, it reaches the pad beyond the shape on every side", shown.width == 316.0 && shown.height == 136.0)
        } else check("a card has a plan", false)

        // a button: a continuous rounded rectangle too short to cut downwards
        val button = WardLightSlice.plan(WardFaceShape.Rounded(14.0, true), 200.0, 44.0, reach = midReach, inner = false, scale = scale)
        if (button != null) {
            check("a button is cut along its length only", button.stretchX && !button.stretchY, "$button")
            check("and keyed by its height in pixels", button.keyWidth == 0 && button.keyHeight == px(44.0))
            check("drawn at its own height", button.height == 44.0 && button.capY == 0 && button.capX > 0)
        } else check("a button has a plan", false)

        // a capsule is keyed by its height
        val pillTall = WardLightSlice.plan(pill, 220.0, 44.0, reach = lowReach, inner = false, scale = scale)
        val pillWide = WardLightSlice.plan(pill, 340.0, 44.0, reach = lowReach, inner = false, scale = scale)
        check("a capsule is cut along its length and keyed by its height",
            pillTall?.stretchX == true && pillTall.stretchY == false && pillTall.keyHeight == px(44.0))
        val pillKey = { p: WardLightPlan -> key(p, control = true) }
        check("two capsules of one height share a key whatever their length",
            pillTall != null && pillWide != null && pillKey(pillTall) == pillKey(pillWide))
        val pillShort = WardLightSlice.plan(pill, 50.0, 44.0, reach = midReach, inner = false, scale = scale)
        check("a capsule too short to cut is drawn and keyed at its own size",
            pillShort?.stretchX == false && pillShort.keyWidth == px(50.0) && pillShort.keyHeight == px(44.0), "$pillShort")

        // a circle is keyed by its diameter
        val dot = WardLightSlice.plan(WardFaceShape.Circle, 44.0, 44.0, reach = lowReach, inner = false, scale = scale)
        check("a circle is drawn at its diameter and keyed by it",
            dot?.stretchX == false && !dot.stretchY && dot.keyWidth == px(44.0) && dot.keyHeight == px(44.0))
        val basePlan0 = WardLightSlice.plan(rounded16, 300.0, 120.0, reach = 8, inner = false, scale = 3.0)
        // a circle in a box that is not square is its shorter side across, in the middle
        val offSquare = WardLightSlice.plan(WardFaceShape.Circle, 44.0, 60.0, reach = lowReach, inner = false, scale = scale)
        check("a circle in a box that is not square is drawn at the shorter side and shown in the middle",
            offSquare?.width == 44.0 && offSquare.height == 44.0 && offSquare.centred &&
                offSquare.keyWidth == px(44.0) && offSquare.keyHeight == px(44.0), "$offSquare")
        val wideBox = WardLightSlice.plan(WardFaceShape.Circle, 70.0, 44.0, reach = lowReach, inner = false, scale = scale)
        check("so a tall and a wide box of the same diameter share a key",
            offSquare != null && wideBox != null && pillKey(offSquare) == pillKey(wideBox))
        check("a rounded rectangle and a capsule fill their box", basePlan0?.centred == false && pillTall?.centred == false)

        // a readiness ring's groove: a ring `width` wide in the box's circle, pressed in
        val groove = WardLightSlice.plan(WardFaceShape.Annulus(10.0), 72.0, 72.0, reach = lowReach, inner = true, scale = scale)
        check("a ring is drawn at its box, keyed by it, with no room round it for inset lights",
            groove?.shape == WardFaceShape.Annulus(10.0) && groove.centred && groove.pad == 0 &&
                !groove.stretchX && groove.keyWidth == px(72.0), "$groove")
        val thinner = WardLightSlice.plan(WardFaceShape.Annulus(8.0), 72.0, 72.0, reach = lowReach, inner = true, scale = scale)
        val circle72 = WardLightSlice.plan(WardFaceShape.Circle, 72.0, 72.0, reach = lowReach, inner = true, scale = scale)
        val ringKey = { p: WardLightPlan -> key(p, look = WardLightLook.inset) }
        check("a ring's width and a circle each change the key", groove != null && thinner != null && circle72 != null &&
            ringKey(groove) != ringKey(thinner) && ringKey(groove) != ringKey(circle72) && ringKey(thinner) != ringKey(circle72))
        check("a ring in a box that is not square is its shorter side across",
            WardLightSlice.plan(WardFaceShape.Annulus(10.0), 72.0, 90.0, reach = lowReach, inner = true, scale = scale)?.width == 72.0)
        check("no plan for a ring that is not one",
            WardLightSlice.plan(WardFaceShape.Annulus(-1.0), 72.0, 72.0, reach = 8, inner = true, scale = scale) == null &&
                WardLightSlice.plan(WardFaceShape.Annulus(Double.NaN), 72.0, 72.0, reach = 8, inner = true, scale = scale) == null)

        // an inset face's lights fall inside it: nothing is drawn round it
        val well = WardLightSlice.plan(WardFaceShape.Rounded(12.0, true), 300.0, 56.0, reach = lowReach, inner = true, scale = scale)
        check("an inset face needs no room round its shape", well?.pad == 0 && well.imageWidth == well.width)
        check("but its caps still hold the curve and the reach", well?.capX == 19 + lowReach, "$well")

        // a radius larger than the box is held to the box, as SwiftUI does
        val held = WardLightSlice.plan(WardFaceShape.Rounded(30.0, false), 40.0, 40.0, reach = lowReach, inner = false, scale = scale)
        check("a radius larger than half the box is held to it", held?.shape == WardFaceShape.Rounded(20.0, false), "$held")

        // sizes that are not sizes
        for ((w, h) in listOf(0.0 to 10.0, 10.0 to 0.0, -1.0 to 10.0, Double.NaN to 10.0, 10.0 to Double.POSITIVE_INFINITY)) {
            check("no plan for $w x $h",
                WardLightSlice.plan(WardFaceShape.Rounded(8.0, true), w, h, reach = 8, inner = false, scale = scale) == null)
        }
        check("no plan for a scale that is not one",
            WardLightSlice.plan(WardFaceShape.Circle, 10.0, 10.0, reach = 8, inner = false, scale = 0.0) == null &&
                WardLightSlice.plan(WardFaceShape.Circle, 10.0, 10.0, reach = 8, inner = false, scale = Double.NaN) == null)
        check("no plan for a radius that is not one",
            WardLightSlice.plan(WardFaceShape.Rounded(-1.0, true), 99.0, 99.0, reach = 8, inner = false, scale = 2.0) == null)

        // the boundary: exactly two caps and a core is cut, a point less is not
        val least = 2.0 * (25 + 8) + WardLightSlice.core
        check("a side of exactly two caps and a core is cut",
            WardLightSlice.plan(rounded16, least, least, reach = 8, inner = false, scale = 2.0)?.stretchX == true)
        check("a side a point shorter is drawn whole",
            WardLightSlice.plan(rounded16, least - 1, least, reach = 8, inner = false, scale = 2.0)?.stretchX == false)
    }

    @Test fun keys() = checks {
        val basePlan = WardLightSlice.plan(rounded16, 300.0, 120.0, reach = 8, inner = false, scale = 3.0)!!
        val k = key(basePlan)
        val wider = WardLightSlice.plan(rounded16, 411.3, 97.0, reach = 8, inner = false, scale = 3.0)!!
        check("every size of a cut rounded rectangle shares one key", k == key(wider))
        check("the look, the lift and the control edge each change the key",
            k != key(basePlan, look = WardLightLook.inset) && k != key(basePlan, look = WardLightLook.press) &&
                k != key(basePlan, lift = WardLift.mid) && k != key(basePlan, control = true))
        check("the colour scheme, Increase Contrast and the fill each change the key",
            k != key(basePlan, dark = true) && k != key(basePlan, strong = true) && k != key(basePlan, fill = 0x1E232BFFL))
        check("the display scale changes the key", k != key(basePlan, scale = 2.0))
        val radius12 = WardLightSlice.plan(WardFaceShape.Rounded(12.0, true), 300.0, 120.0, reach = 8, inner = false, scale = 3.0)!!
        val circular16 = WardLightSlice.plan(WardFaceShape.Rounded(16.0, false), 300.0, 120.0, reach = 8, inner = false, scale = 3.0)!!
        check("the radius and the corner style change the key", k != key(radius12) && k != key(circular16))
        val h44 = WardLightSlice.plan(pill, 200.0, 44.0, reach = 8, inner = false, scale = 3.0)!!
        val h44b = WardLightSlice.plan(pill, 200.0, 44.1, reach = 8, inner = false, scale = 3.0)!!
        val h45 = WardLightSlice.plan(pill, 200.0, 44.4, reach = 8, inner = false, scale = 3.0)!!
        check("an uncut axis is keyed by its pixel, not its fraction of one", key(h44) == key(h44b) && key(h44) != key(h45))
        check("a capsule is not a rounded rectangle", key(h44) != key(basePlan))
        check("fills pack to RGBA bytes",
            WardLightSlice.pack(1.0, 0.0, 0.5, 1.0) == 0xFF0080FFL && WardLightSlice.pack(-1.0, 2.0, 0.0, 0.0) == 0x00FF0000L)
    }

    // A rounded rectangle's lights drawn the way the app draws them: the shape's
    // coverage moved by the light's offset and blurred by a Gaussian (a shadow
    // radius is twice its deviation), the face's own coverage blurred by the
    // press's softening. The corner is a circle of the curve's length, the
    // widest the continuous curve gets.
    private fun gaussian(sigma: Double): DoubleArray {
        if (!(sigma > 0)) return doubleArrayOf(1.0)
        val n = ceil(4 * sigma).toInt()
        val k = DoubleArray(2 * n + 1) { i -> val d = (i - n).toDouble(); exp(-(d * d) / (2 * sigma * sigma)) }
        val total = k.sum()
        return DoubleArray(k.size) { k[it] / total }
    }

    private fun blur(grid: Array<DoubleArray>, sigma: Double): Array<DoubleArray> {
        val k = gaussian(sigma)
        val n = k.size / 2
        val h = grid.size
        val w = grid[0].size
        val across = Array(h) { DoubleArray(w) }
        for (y in 0 until h) for (x in 0 until w) {
            var sum = 0.0
            for (i in -n..n) { val xx = x + i; if (xx in 0 until w) sum += grid[y][xx] * k[i + n] }
            across[y][x] = sum
        }
        val down = Array(h) { DoubleArray(w) }
        for (y in 0 until h) for (x in 0 until w) {
            var sum = 0.0
            for (i in -n..n) { val yy = y + i; if (yy in 0 until h) sum += across[yy][x] * k[i + n] }
            down[y][x] = sum
        }
        return down
    }

    /** Coverage of a rounded rectangle at (0,0) of size w x h, sampled at cell centres, with shifts. */
    private fun coverage(w: Double, h: Double, corner: Double, pad: Int, dx: Double, dy: Double): Array<DoubleArray> {
        val rows = h.toInt() + 2 * pad
        val cols = w.toInt() + 2 * pad
        return Array(rows) { y ->
            DoubleArray(cols) { x ->
                val px = (x - pad) + 0.5 - dx - w / 2
                val py = (y - pad) + 0.5 - dy - h / 2
                val qx = abs(px) - (w / 2 - corner)
                val qy = abs(py) - (h / 2 - corner)
                val outside = sqrt(max(qx, 0.0) * max(qx, 0.0) + max(qy, 0.0) * max(qy, 0.0))
                val inside = min(max(qx, qy), 0.0)
                if (outside + inside - corner <= 0) 1.0 else 0.0
            }
        }
    }

    /** What a raised face (or a pressable one at rest, with [soften]) draws outside its shape. */
    private fun lights(w: Double, h: Double, radius: Double, spec: WardReliefSpec, soften: Double, pad: Int): Array<DoubleArray> {
        val corner = ceil(radius * WardLightSlice.continuousCurve)
        var total: Array<DoubleArray>? = null
        for (light in listOf(spec.shade, spec.highlight)) {
            val sigma = sqrt(light.radius / 2 * light.radius / 2 + soften * soften)
            val g = blur(coverage(w, h, corner, pad, light.x, light.y), sigma)
            for (row in g) for (i in row.indices) row[i] *= light.alpha
            total = total?.let { t -> Array(t.size) { y -> DoubleArray(t[y].size) { x -> t[y][x] + g[y][x] } } } ?: g
        }
        return total!!
    }

    private fun WardChecks.compare(look: String, lift: WardLift, spec: WardReliefSpec, soften: Double, reach: Int) {
        val radius = 16.0
        val plan = WardLightSlice.plan(WardFaceShape.Rounded(radius, true), 400.0, 400.0, reach = reach, inner = false, scale = 1.0)
        if (plan == null) { check("$look $lift: a plan", false); return }
        val small = lights(plan.width, plan.height, radius, spec, soften, plan.pad)
        val big = lights(plan.width + 37, plan.height + 23, radius, spec, soften, plan.pad)
        var worst = 0.0
        for (y in big.indices) {
            val sy = WardLightSlice.sourceIndex(y, shown = big.size, source = small.size, cap = plan.capY)
            for (x in big[0].indices) {
                val sx = WardLightSlice.sourceIndex(x, shown = big[0].size, source = small[0].size, cap = plan.capX)
                worst = max(worst, abs(big[y][x] - small[sy][sx]))
            }
        }
        // an 8-bit channel steps by 1/255
        check("$look $lift: the stretched slice matches the larger drawing to within one 8-bit step",
            worst < 1.0 / 255, "worst ${worst * 255} steps")
    }

    @Test fun stretchingIsDrawingLarger() = checks {
        for (lift in WardLift.entries) {
            val raised = WardRelief.raised(lift, dark = false)
            compare("raised", lift, raised, 0.0, WardLightSlice.reach(raised))
            val press = WardPress.spec(lift, depth = 0.0, dark = false)
            compare("press at rest", lift, WardRelief.rim(lift, dark = false), press.blur, WardLightSlice.reach(press))
        }

        // a cap one point too small shows the test can fail
        val raised = WardRelief.raised(WardLift.high, dark = false)
        val reach = WardLightSlice.reach(raised)
        val plan = WardLightSlice.plan(rounded16, 400.0, 400.0, reach = reach, inner = false, scale = 1.0)!!
        val small = lights(plan.width, plan.height, 16.0, raised, 0.0, plan.pad)
        val tooSmall = lights(40.0, 40.0, 16.0, raised, 0.0, plan.pad)
        var differs = false
        for (x in 0 until min(small[0].size, tooSmall[0].size)) {
            if (abs(small[plan.capY][x] - tooSmall[plan.capY][x]) > 1.0 / 255) differs = true
        }
        check("a shape smaller than the cut needs is not the same picture (so it is drawn whole)", differs)
    }

    @Test fun countingTheFaces() = checks {
        val live = { r: WardLiveReason -> WardReliefPath.Live(r) }
        check("a path's tag says how it was drawn",
            WardReliefPath.Cached.tag == "cached" && live(WardLiveReason.Shape).tag == "live:shape" &&
                live(WardLiveReason.Plan(12, 40)).tag == "live:plan@12x40" &&
                live(WardLiveReason.Bare).tag == "live:none" && live(WardLiveReason.Late).tag == "live:late" &&
                live(WardLiveReason.Fill).tag == "live:fill" && live(WardLiveReason.Failed).tag == "live:failed" &&
                live(WardLiveReason.Press).tag == "live:press" && live(WardLiveReason.Off).tag == "live:off" &&
                live(WardLiveReason.Empty).tag == "live:empty")
        check("a face with lights that drew live is a miss; cached, lightless and empty ones are not",
            live(WardLiveReason.Shape).missed && live(WardLiveReason.Late).missed && live(WardLiveReason.Press).missed &&
                live(WardLiveReason.Plan(1, 1)).missed && live(WardLiveReason.Failed).missed &&
                !WardReliefPath.Cached.missed && !live(WardLiveReason.Bare).missed && !live(WardLiveReason.Empty).missed)
        val p0 = live(WardLiveReason.Plan(0, 0))
        val sample = listOf(p0, WardReliefPath.Cached, live(WardLiveReason.Shape), WardReliefPath.Cached, p0, WardReliefPath.Cached, p0)
        val field = WardReliefCensus.field(sample, made = 15, seconds = 0.0424)
        check("the field counts the faces by tag, cached first, then the images made",
            field == " relief=cached:3,live:plan@0x0:3,live:shape:1 made=15/42ms", field)
        check("with no faces it says none; failures are added after",
            WardReliefCensus.field(emptyList(), made = 0, seconds = 0.0) == " relief=none made=0/0ms" &&
                WardReliefCensus.field(listOf(WardReliefPath.Cached), made = 1, seconds = 0.002, failures = 2) == " relief=cached:1 made=1/2ms failed=2")
        check("the field is one line", !WardReliefCensus.field(sample, made = 1, seconds = 1.0).contains("\n"))

        val census = WardReliefCensus()
        val first = census.newFace()
        val second = census.newFace()
        check("faces are numbered from 1, each its own", first >= 1 && second == first + 1)
        census.note(first, live(WardLiveReason.Late)); census.note(second, WardReliefPath.Cached)
        census.note(first, WardReliefPath.Cached)
        census.made(seconds = 0.010); census.made(seconds = 0.005); census.failure()
        check("a face redrawn counts once, as it was last drawn", census.field() == " relief=cached:2 made=2/15ms failed=1", census.field())
        census.forget(second)
        check("a face that goes is dropped from the count", census.field() == " relief=cached:1 made=2/15ms failed=1", census.field())
    }
}
