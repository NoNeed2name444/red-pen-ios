package com.stethoscore.app.ui.ward

import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// A port of upstream/ios/RedPen/Tests/WardReliefTests.swift, same cases and
// numbers. Soft UI relief: in light and dark, at every lift, the highlight is
// lighter than the base and the shade darker, the two read apart but softly,
// they grow with the lift, the dark highlight never glares, the same input
// gives the same relief, and pressed in is raised mirrored. Then the press,
// the rim, the paper and the frame line's joins (WardEdge).
class WardReliefTest {

    private fun f(x: Double) = f3(x)
    private fun near(a: Double, b: Double) = abs(a - b) <= 1e-9
    private fun nearTol(a: Double, b: Double, eps: Double = 0.01) = abs(a - b) <= eps

    @Test fun relief() = checks {
        for (dark in listOf(false, true)) {
            val mode = if (dark) "dark" else "light"
            val base = WardRelief.base(dark)
            check("$mode: the relief falls on the palette's base", base == WardPalette.hex(WardToken.background, dark))

            var last: WardReliefSpec? = null
            for (lift in WardLift.entries) {
                val tag = "$mode $lift"
                val spec = WardRelief.raised(lift, dark)
                val hi = WardRelief.composite(spec.highlight, on = base)
                val sh = WardRelief.composite(spec.shade, on = base)
                val lb = WardPalette.luminance(base)
                val lh = WardPalette.luminance(hi)
                val ls = WardPalette.luminance(sh)

                check("$tag: the highlight is lighter than the base", lh > lb, "${f(lh)} vs ${f(lb)}")
                check("$tag: the shade is darker than the base", ls < lb, "${f(ls)} vs ${f(lb)}")
                val apart = WardPalette.contrast(hi, sh)
                check("$tag: highlight and shade read apart, softly", apart >= 1.25 && apart <= 2.5, f(apart))
                check("$tag: each light shows on the base",
                    WardPalette.contrast(hi, base) >= 1.08 && WardPalette.contrast(sh, base) >= 1.08,
                    "${f(WardPalette.contrast(hi, base))} / ${f(WardPalette.contrast(sh, base))}")

                // lit from the top left
                check("$tag: the highlight falls up and left, the shade down and right",
                    spec.highlight.x < 0 && spec.highlight.y < 0 && spec.shade.x > 0 && spec.shade.y > 0 &&
                        spec.highlight.x == -spec.shade.x && spec.highlight.y == -spec.shade.y)
                check("$tag: the highlight is white", spec.highlight.hex == 0xFFFFFF)

                // the ranges the design asks for
                if (dark) {
                    check("$tag: white at 0.05 to 0.09", spec.highlight.alpha in 0.05..0.09, f(spec.highlight.alpha))
                    check("$tag: black at 0.45 to 0.6", spec.shade.hex == 0x000000 && spec.shade.alpha in 0.45..0.6, f(spec.shade.alpha))
                    check("$tag: no white glare", WardPalette.contrast(hi, base) <= 1.4, f(WardPalette.contrast(hi, base)))
                } else {
                    check("$tag: white at 0.7 to 0.9", spec.highlight.alpha in 0.7..0.9, f(spec.highlight.alpha))
                    check("$tag: #A3B1C6 at 0.5 to 0.65", spec.shade.hex == 0xA3B1C6 && spec.shade.alpha in 0.5..0.65, f(spec.shade.alpha))
                }

                // grows with the lift
                last?.let { last ->
                    check("$tag: stands further off than the lift below",
                        spec.shade.x > last.shade.x && spec.shade.radius > last.shade.radius &&
                            spec.highlight.alpha >= last.highlight.alpha && spec.shade.alpha >= last.shade.alpha)
                    val wasApart = WardPalette.contrast(WardRelief.composite(last.highlight, on = base),
                        WardRelief.composite(last.shade, on = base))
                    check("$tag: reads at least as strongly as the lift below", apart >= wasApart, "${f(apart)} vs ${f(wasApart)}")
                }
                last = spec

                // deterministic, and pressed in mirrors raised
                check("$tag: the same input gives the same relief", WardRelief.raised(lift, dark) == spec)
                val inset = WardRelief.inset(lift, dark)
                check("$tag: raised drops its lights outside, pressed in casts them inside", !spec.inner && inset.inner)
                check("$tag: pressed in is raised mirrored", inset == spec.mirrored() && inset.mirrored() == spec)
                check("$tag: pressed in keeps the lights where they are", inset.highlight == spec.highlight && inset.shade == spec.shade)

                // A control's face has an ink edge at 3:1 or more; a card or a slab
                // has none until Increase Contrast, which strengthens both
                val control = WardRelief.raised(lift, dark, control = true)
                val strong = WardRelief.raised(lift, dark, highContrast = true)
                val strongControl = WardRelief.raised(lift, dark, highContrast = true, control = true)
                val edge = WardPalette.contrast(WardRelief.edgeColor(dark), base)
                val strongEdge = WardPalette.contrast(WardRelief.edgeColor(dark, highContrast = true), base)
                check("$tag: a control's edge reads at least 3:1 on the base",
                    control.edgeAlpha == WardRelief.edgeAlpha(dark) && edge >= WardRelief.edgeContrast, f(edge))
                check("$tag: a card has no edge", spec.edgeAlpha == 0.0)
                check("$tag: a control's face is a card's with the edge",
                    control.highlight == spec.highlight && control.shade == spec.shade && control.inner == spec.inner)
                check("$tag: pressed in keeps the edge",
                    inset.edgeAlpha == spec.edgeAlpha && WardRelief.inset(lift, dark, control = true).edgeAlpha == control.edgeAlpha)
                check("$tag: Increase Contrast edges a card",
                    strong.edgeAlpha == WardRelief.containerHighContrastEdge && strong.edgeAlpha > 0)
                check("$tag: Increase Contrast strengthens a control's edge, past a card's",
                    strongControl.edgeAlpha > control.edgeAlpha && strongEdge > edge && strongControl.edgeAlpha > strong.edgeAlpha,
                    "${f(strongEdge)} vs ${f(edge)}")
                check("$tag: Increase Contrast deepens the shade",
                    strong.shade.alpha > spec.shade.alpha && WardPalette.luminance(WardRelief.composite(strong.shade, on = base)) < ls)
                check("$tag: Increase Contrast keeps the geometry and the highlight",
                    strong.highlight == spec.highlight && strong.shade.x == spec.shade.x && strong.shade.radius == spec.shade.radius)
                check("$tag: Increase Contrast pressed in mirrors too",
                    WardRelief.inset(lift, dark, highContrast = true) == strong.mirrored())
            }
        }

        val liftOrder = WardLift.entries.map { it.rawValue }
        check("the lifts are ordered low to peak", liftOrder == liftOrder.sorted() && liftOrder.first() == WardLift.low.rawValue &&
            liftOrder.last() == WardLift.peak.rawValue)
        check("pressed in sinks one lift, never below low",
            WardLift.peak.lower == WardLift.high && WardLift.high.lower == WardLift.mid && WardLift.mid.lower == WardLift.low &&
                WardLift.low.lower == WardLift.low)
        check("a light on its own colour at full strength is that colour",
            WardRelief.composite(WardReliefLight(0x123456, 1.0, 0.0, 0.0, 0.0), on = 0xFFFFFF) == 0x123456)
        check("a light at no strength leaves the base",
            WardRelief.composite(WardReliefLight(0x123456, 0.0, 0.0, 0.0, 0.0), on = 0xE0E5EC) == 0xE0E5EC)

        for ((alpha, expected) in listOf(0.0 to false, 1e-4 to false, 2e-4 to true)) {
            check("light visibility at $alpha", WardReliefLight(0xFFFFFF, alpha, 0.0, 0.0, 0.0).lit == expected)
        }
    }

    // The retro press has separate click and shade tracks, with no overshoot.
    @Test fun press() = checks {
        check("press constants", WardPress.sinkScale == 0.985 && WardPress.press == 0.05 &&
            WardPress.release == 0.07 && WardPress.shadePress == 0.21 &&
            WardPress.shadeRelease == 0.26 && WardPress.depth == 1.0 &&
            WardPress.softKeep == 0.6 && WardPress.hollowSoft == 1.0)
        val curve = WardPress.quickCurve
        check("quick curve controls", near(curve.x1, 1.0 / 3) && curve.y1 == 0.5 && near(curve.x2, 2.0 / 3) && near(curve.y2, 5.0 / 6))
        for (i in 0..20) {
            val t = i / 20.0
            val v = 1 - t
            val x = 3 * v * v * t * curve.x1 + 3 * v * t * t * curve.x2 + t * t * t
            val y = 3 * v * v * t * curve.y1 + 3 * v * t * t * curve.y2 + t * t * t
            check("Bezier $i: x=t, y=quick(t)", near(x, t) && near(y, WardPress.quick(t)))
            check("glide $i", near(WardPress.glide(t), sin(t * PI / 2)))
        }
        check("progress clamps", WardPress.quick(-1.0) == 0.0 && WardPress.quick(2.0) == 1.0 &&
            WardPress.glide(-1.0) == 0.0 && near(WardPress.glide(2.0), 1.0))
        check("release completes click", WardPress.releaseHold(held = -1.0) == 0.05 &&
            WardPress.releaseHold(held = 0.0) == 0.05 && near(WardPress.releaseHold(held = 0.02), 0.03) &&
            WardPress.releaseHold(held = 0.05) == 0.0 && WardPress.releaseHold(held = 1.0) == 0.0)
        for ((lift, expected) in WardLift.entries.zip(listOf(1.0, 1.5, 2.0, 2.5))) {
            check("softness $lift", near(WardPress.soft(lift), expected))
            for (dark in listOf(false, true)) {
                for (strong in listOf(false, true)) {
                    val raised = WardRelief.raised(lift, dark, highContrast = strong, control = true)
                    fun spec(q: Double) = WardPress.spec(lift, depth = q, dark = dark, highContrast = strong)
                    check("$lift/$dark/$strong: a pressable face is a control's, edged",
                        spec(0.0).edgeAlpha == WardRelief.edgeAlpha(dark, highContrast = strong))
                    check("$lift/$dark/$strong: an icon tile's is a card's",
                        WardPress.spec(lift, depth = 0.5, dark = dark, highContrast = strong, control = false).edgeAlpha ==
                            WardRelief.containerEdgeAlpha(highContrast = strong))
                    check("$lift/$dark/$strong: depth clamps", spec(-1.0) == spec(0.0) && spec(2.0) == spec(1.0))
                    for (q in listOf(-1.0, 0.0, 0.5, 1.0, 2.0)) {
                        check("a button's outline stays crisp $lift/$dark/$strong/$q", spec(q).blur == 0.0)
                        val tile = WardPress.spec(lift, depth = q, dark = dark, highContrast = strong, control = false)
                        val extra = min(1.0, max(0.0, q))
                        check("an icon tile keeps its softness $lift/$dark/$strong/$q", near(tile.blur, expected + extra))
                        check("an icon tile casts no rim highlight $lift/$dark/$strong/$q", !tile.outerHighlight.lit)
                    }
                    val resting = spec(0.0)
                    val pressed = spec(1.0)
                    check("$lift/$dark/$strong: resting lights are the rim",
                        resting.outerShade.lit && resting.outerHighlight.lit && !resting.innerShade.lit && !resting.innerHighlight.lit)
                    check("$lift/$dark/$strong: pressed lights fall inside",
                        !pressed.outerShade.lit && !pressed.outerHighlight.lit && pressed.innerShade.lit && pressed.innerHighlight.lit)
                    val rim = WardRelief.rim(lift, dark, highContrast = strong)
                    var previous = spec(0.0)
                    for (i in 0..100) {
                        val q = i / 100.0
                        val up = 1 - q
                        val down = q
                        val current = spec(q)
                        val lights = listOf(current.outerHighlight, current.outerShade, current.innerShade, current.innerHighlight)
                        val deeper = raised.shade.copy(alpha = min(1.0, raised.shade.alpha * 1.25))
                        val originals = listOf(rim.highlight, rim.shade, deeper, raised.highlight)
                        val weights = listOf(up, up, down, down)
                        for (j in 0 until 4) {
                            val light = lights[j]
                            val original = originals[j]
                            val w = weights[j]
                            check("spec $lift/$dark/$strong/$i/$j",
                                light.hex == original.hex && near(light.alpha, original.alpha * w) &&
                                    near(light.x, original.x * w) && near(light.y, original.y * w) &&
                                    near(light.radius, original.radius * (0.6 + 0.4 * w)))
                        }
                        check("edge $i", current.edgeAlpha == raised.edgeAlpha)
                        check("a button's rim never reaches past rimReach $lift/$dark/$strong/$i",
                            WardRelief.reach(current.outerHighlight) <= WardRelief.rimReach + 1e-9 &&
                                WardRelief.reach(current.outerShade) <= WardRelief.rimReach + 1e-9)
                        val old = listOf(previous.outerHighlight, previous.outerShade, previous.innerShade, previous.innerHighlight)
                        check("continuous $lift/$dark/$strong/$i", old.zip(lights).all { (a, b) ->
                            abs(a.alpha - b.alpha) <= 0.01 + 1e-9 && abs(a.x - b.x) <= 0.12 + 1e-9 && abs(a.y - b.y) <= 0.12 + 1e-9
                        })
                        previous = current
                    }
                }
            }
        }
    }

    // The rim: the one soft light the app keeps, on buttons only (the owner,
    // 14 Oct). Small: 2 points of blur and at most 3 of offset, the whole of it
    // within rimReach, which is less than the smallest gap between two
    // controls, so it never reaches another control or the words beside it.
    @Test fun rim() = checks {
        check("the rim's reach is under the scale's smallest gap between controls",
            WardRelief.rimReach < WardScale.s && WardRelief.rimReach <= WardRelief.rimMaxOffset + WardRelief.rimMaxBlur)
        for (dark in listOf(false, true)) {
            val base = WardRelief.base(dark)
            var lastReach = 0.0
            for (lift in WardLift.entries) {
                for (strong in listOf(false, true)) {
                    val tag = "rim ${if (dark) "dark" else "light"} $lift${if (strong) " strong" else ""}"
                    val rim = WardRelief.rim(lift, dark, highContrast = strong)
                    val wide = WardRelief.raised(lift, dark, highContrast = strong)
                    check("$tag: a blur of 2 points", rim.highlight.radius in 2.0..WardRelief.rimMaxBlur && rim.shade.radius == rim.highlight.radius)
                    check("$tag: a small offset, up and left then down and right",
                        rim.highlight.x < 0 && rim.highlight.y < 0 && rim.shade.x > 0 && rim.shade.y > 0 &&
                            rim.shade.x <= WardRelief.rimMaxOffset && rim.highlight.x == -rim.shade.x)
                    check("$tag: within its reach", WardRelief.reach(rim.highlight) <= WardRelief.rimReach &&
                        WardRelief.reach(rim.shade) <= WardRelief.rimReach)
                    check("$tag: never wider than the relief a card keeps",
                        WardRelief.reach(rim.shade) <= WardRelief.reach(wide.shade) || lift == WardLift.low)
                    check("$tag: raised, outside the face", !rim.inner)
                    check("$tag: a control's edge", rim.edgeAlpha == WardRelief.edgeAlpha(dark, highContrast = strong))
                    val hi = WardRelief.composite(rim.highlight, on = base)
                    val sh = WardRelief.composite(rim.shade, on = base)
                    check("$tag: the highlight is lighter than the base and the shade darker",
                        WardPalette.luminance(hi) > WardPalette.luminance(base) && WardPalette.luminance(sh) < WardPalette.luminance(base))
                    check("$tag: the two read apart", WardPalette.contrast(hi, sh) >= 1.3, f(WardPalette.contrast(hi, sh)))
                    if (dark) check("$tag: no white glare", WardPalette.contrast(hi, base) <= 1.4, f(WardPalette.contrast(hi, base)))
                    if (strong) {
                        check("$tag: Increase Contrast deepens the shade", rim.shade.alpha > WardRelief.rim(lift, dark).shade.alpha)
                    }
                }
                val reach = WardRelief.reach(WardRelief.rim(lift, dark).shade)
                check("rim $dark $lift: a higher button's rim reaches no less", reach >= lastReach)
                lastReach = reach
            }
        }
    }

    // Paper frame: exact ink, strict size threshold and grid endpoints.
    @Test fun paper() = checks {
        check("paper constants", WardPaper.frame == 12.0 && WardPaper.cell == 6.0 &&
            WardPaper.boldEvery == 5 && WardPaper.line == 1.0 && WardPaper.edgeWidth == 1.5 &&
            near(WardPaper.cornerShare, 53.33 / 428))
        for (dark in listOf(false, true)) {
            for (strong in listOf(false, true)) {
                val ink = WardPaper.ink(dark, highContrast = strong)
                // the ink outside any section (Cards' Care Blue, the 2026-10-21 palette)
                check("paper ink $dark/$strong",
                    ink.hex == (if (dark) 0x84B2FD else 0x2A71E5) &&
                        ink.fine == (if (strong) 0.0 else if (dark) 0.07 else 0.09) &&
                        ink.bold == (if (strong) 0.0 else if (dark) 0.14 else 0.18) &&
                        ink.edge == (if (dark) 0.5 else 0.55))
            }
        }
        check("paper panel excludes threshold", WardPaper.panel(48.0, 500.0) == null && WardPaper.panel(500.0, 48.0) == null)
        val smallest = WardPaper.panel(49.0, 49.0)
        if (smallest != null) {
            check("paper smallest panel", smallest.x == 12.0 && smallest.y == 12.0 &&
                smallest.width == 25.0 && smallest.height == 25.0 && near(smallest.radius, 25 * 53.33 / 428))
        } else {
            check("paper smallest panel exists", false)
        }
        for ((width, height) in listOf(428.0 to 926.0, 926.0 to 428.0)) {
            val panel = WardPaper.panel(width, height)
            if (panel != null) {
                check("paper panel ${width}x$height", panel.x == 12.0 && panel.y == 12.0 &&
                    panel.width == width - 24 && panel.height == height - 24 && near(panel.radius, 404 * 53.33 / 428))
            } else {
                check("paper phone panel exists", false)
            }
        }
        // The home page's opening, moved down under its header: same sides, bottom
        // and corners; held to the frame above and to room for its corners below.
        val base = WardPaper.panel(402.0, 874.0)
        val low = WardPaper.panel(402.0, 874.0, top = 280.0)
        val high = WardPaper.panel(402.0, 874.0, top = 4.0)
        val deep = WardPaper.panel(402.0, 874.0, top = 870.0)
        if (base != null && low != null && high != null && deep != null) {
            check("paper panel moved down", low.y == 280.0 && low.x == base.x && low.width == base.width &&
                low.y + low.height == base.y + base.height && low.radius == base.radius)
            check("paper panel never above the frame", high == base)
            check("paper panel keeps room for its corners", near(deep.height, 2 * base.radius) &&
                deep.y + deep.height == base.y + base.height)
        } else {
            check("paper moved panel exists", false)
        }
        val paper30 = WardPaper.lines(30.0)
        val paper31 = WardPaper.lines(31.0)
        check("paper grid excludes endpoint", paper30.size == 5 &&
            paper30.map { it.at } == listOf(0.0, 6.0, 12.0, 18.0, 24.0) && paper30.filter { it.bold }.map { it.at } == listOf(0.0))
        check("paper grid includes next bold", paper31.size == 6 &&
            paper31.map { it.at } == listOf(0.0, 6.0, 12.0, 18.0, 24.0, 30.0) && paper31.filter { it.bold }.map { it.at } == listOf(0.0, 30.0))
        check("paper nonpositive grid empty", WardPaper.lines(0.0).isEmpty() && WardPaper.lines(-5.0).isEmpty())

        // A band from a global origin: the frame's lines, in local positions.
        check("paper band from zero is the frame grid",
            WardPaper.lines(31.0, from = 0.0).map { it.at } == paper31.map { it.at } &&
                WardPaper.lines(31.0, from = 0.0).map { it.bold } == paper31.map { it.bold })
        val band = WardPaper.lines(20.0, from = 10.0)
        check("paper band shifts into local positions",
            band.map { it.at } == listOf(2.0, 8.0, 14.0) && band.map { it.bold } == listOf(false, false, false), "${band.map { it.at }}")
        val bandBold = WardPaper.lines(25.0, from = 27.0)
        check("paper band keeps the global bold lines",
            bandBold.map { it.at } == listOf(3.0, 9.0, 15.0, 21.0) && bandBold.filter { it.bold }.map { it.at } == listOf(3.0),
            "${bandBold.map { it.at to it.bold }}")
        val bandOnLine = WardPaper.lines(12.0, from = 30.0)
        check("paper band includes a line on its origin, excludes its end",
            bandOnLine.map { it.at } == listOf(0.0, 6.0) && bandOnLine.firstOrNull()?.bold == true)
        val bandAbove = WardPaper.lines(14.0, from = -8.0)
        check("paper band above the origin counts bold lines the same way",
            bandAbove.map { it.at } == listOf(2.0, 8.0) && bandAbove.map { it.bold } == listOf(false, true),
            "${bandAbove.map { it.at to it.bold }}")
        check("paper band empty for no length", WardPaper.lines(0.0, from = 40.0).isEmpty() &&
            WardPaper.lines(-3.0, from = 40.0).isEmpty() && WardPaper.lines(Double.POSITIVE_INFINITY, from = 0.0).isEmpty())
        var aligned = true
        var origin = -37.5
        while (origin <= 211.0) {
            for (line in WardPaper.lines(90.0, from = origin)) {
                val global = line.at + origin
                val k = wardRounded(global / WardPaper.cell)
                if (abs(k * WardPaper.cell - global) > 1e-9 || line.at < 0 || line.at >= 90 ||
                    line.bold != (k.toInt() % 5 == 0)) aligned = false
            }
            origin += 3.25
        }
        check("paper band lines sit on the frame's grid", aligned)
    }

    // Raised and pressed in read apart at a glance, in light and dark, at every
    // lift (the owner, 16 Oct). Raised, the rim stands at the largest offset its
    // reach allows (2, 2.5, 3, 3), with a crisp blur of 2 and a darker shade
    // (0.9 by day, 0.85 at night), and reaches 4 to 5 points. Pressed in, the
    // face sinks the whole of its lift's lights, the inner shade a quarter
    // stronger. The shade still starts in at the speed it had at the old depth.
    @Test fun raisedAndPressedReadApart() = checks {
        for ((lift, offset) in WardLift.entries.zip(listOf(2.0, 2.5, 3.0, 3.0))) {
            check("raised $lift: offset $offset, blur 2", WardRelief.rimOffset(lift) == offset && WardRelief.rimBlur(lift) == 2.0)
            for (dark in listOf(false, true)) {
                for (strong in listOf(false, true)) {
                    val tag = "$lift ${if (dark) "dark" else "light"}${if (strong) " strong" else ""}"
                    val rim = WardRelief.rim(lift, dark, highContrast = strong)
                    val shade = min(1.0, (if (dark) 0.85 else 0.9) + (if (strong) 0.15 else 0.0))
                    check("raised $tag: the rim's lights", near(rim.shade.alpha, shade) &&
                        rim.highlight.alpha == (if (dark) 0.1 else 0.95) && rim.shade.x == offset && rim.shade.y == offset &&
                        rim.highlight.x == -offset && rim.shade.radius == 2.0 && rim.highlight.radius == 2.0,
                        "${rim.shade.alpha} ${rim.shade.x} ${rim.shade.radius}")
                    for (light in listOf(rim.highlight, rim.shade)) {
                        check("raised $tag: reaches ${offset + 2}, within rimReach, under the gap between controls",
                            near(WardRelief.reach(light), offset + 2) && WardRelief.reach(light) <= WardRelief.rimReach &&
                                WardRelief.rimReach == 5.0 && WardRelief.rimReach < WardScale.s)
                    }
                    val raised = WardRelief.raised(lift, dark, highContrast = strong, control = true)
                    val pressed = WardPress.spec(lift, depth = 1.0, dark = dark, highContrast = strong)
                    check("pressed $tag: the whole of the lift's shade, a quarter stronger",
                        near(pressed.innerShade.alpha, min(1.0, raised.shade.alpha * 1.25)) &&
                            near(pressed.innerShade.x, WardRelief.offset(lift)) && near(pressed.innerShade.y, WardRelief.offset(lift)) &&
                            near(pressed.innerShade.radius, WardRelief.radius(lift)),
                        "${pressed.innerShade.alpha} ${pressed.innerShade.x} ${pressed.innerShade.radius}")
                    check("pressed $tag: and the whole of its highlight",
                        near(pressed.innerHighlight.alpha, raised.highlight.alpha) && near(pressed.innerHighlight.x, -WardRelief.offset(lift)))
                }
            }
        }
        check("the shade starts in as fast as at the old depth",
            abs(WardPress.depth / WardPress.shadePress - 0.7 / 0.15) <= 0.03 * 0.7 / 0.15 &&
                abs(WardPress.depth / WardPress.shadeRelease - 0.7 / 0.18) <= 0.03 * 0.7 / 0.18 &&
                WardPress.press == 0.05 && WardPress.release == 0.07)
    }

    // Island geometry: continuous arcs joining horizontal lines to the paper frame outline

    private fun joinTangencyDevDeg(corner: WardEdgeCorner, poly: List<WardVec>): Double {
        val radiusV = corner.join - corner.center
        val radiusLen = hypot(radiusV.x, radiusV.y)
        if (radiusLen <= 1e-9) return 0.0
        val radiusN = radiusV / radiusLen
        var bestDist = Double.POSITIVE_INFINITY
        var bestSegIndex = 0
        for (k in 0 until poly.size - 1) {
            val a = poly[k]
            val b = poly[k + 1]
            val ab = b - a
            val abLenSq = ab.x * ab.x + ab.y * ab.y
            if (abLenSq < 1e-12) continue
            val t = max(0.0, min(1.0, ((corner.join.x - a.x) * ab.x + (corner.join.y - a.y) * ab.y) / abLenSq))
            val proj = a + t * ab
            val d = hypot(corner.join.x - proj.x, corner.join.y - proj.y)
            if (d < bestDist) {
                bestDist = d
                bestSegIndex = k
            }
        }
        val segV = poly[bestSegIndex + 1] - poly[bestSegIndex]
        val segLen = hypot(segV.x, segV.y)
        if (segLen <= 1e-9) return 0.0
        val segT = segV / segLen
        val dot = abs(radiusN.x * segT.x + radiusN.y * segT.y)
        return asin(min(1.0, dot)) * 180.0 / PI
    }

    private fun minPolylineDist(pt: WardVec, poly: List<WardVec>): Double {
        var dMin = Double.POSITIVE_INFINITY
        for (k in 0 until poly.size - 1) {
            val a = poly[k]
            val b = poly[k + 1]
            val ab = b - a
            val abLenSq = ab.x * ab.x + ab.y * ab.y
            if (abLenSq < 1e-12) {
                dMin = min(dMin, hypot(pt.x - a.x, pt.y - a.y))
            } else {
                val t = max(0.0, min(1.0, ((pt.x - a.x) * ab.x + (pt.y - a.y) * ab.y) / abLenSq))
                val proj = a + t * ab
                dMin = min(dMin, hypot(pt.x - proj.x, pt.y - proj.y))
            }
        }
        return dMin
    }

    private fun pointInPoly(pt: WardVec, poly: List<WardVec>): Boolean {
        var inside = false
        var prev = poly.size - 1
        for (curr in poly.indices) {
            val pi = poly[curr]
            val pj = poly[prev]
            if ((pi.y > pt.y) != (pj.y > pt.y) && pt.x < (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y) + pi.x) inside = !inside
            prev = curr
        }
        return inside
    }

    @Test fun edgeJoins() = checks {
        // A1 (h): The outline
        val phone = WardPaper.panel(402.0, 874.0)
        if (phone != null) {
            val poly = WardEdge.outline(phone)
            val r = phone.radius
            val t1 = WardVec(phone.x + 1.52866483 * r, phone.y)
            val t2 = WardVec(phone.x, phone.y + 1.52866483 * r)
            val d1 = poly.minOfOrNull { hypot(it.x - t1.x, it.y - t1.y) } ?: 1.0
            val d2 = poly.minOfOrNull { hypot(it.x - t2.x, it.y - t2.y) } ?: 1.0
            val minX = phone.x
            val maxX = phone.x + phone.width
            val minY = phone.y
            val maxY = phone.y + phone.height
            val insideAll = poly.all { it.x >= minX - 1e-6 && it.x <= maxX + 1e-6 && it.y >= minY - 1e-6 && it.y <= maxY + 1e-6 }
            check("outline: closed", poly.first() == poly.last())
            check("outline: all inside rect", insideAll)
            check("outline: passes through (x + 1.52866483 r, y) within 0.001", d1 <= 0.001, "$d1")
            check("outline: passes through (x, y + 1.52866483 r) within 0.001", d2 <= 0.001, "$d2")
        } else {
            check("outline: panel exists", false)
        }

        // A1 (a): Window 402 x 874, y 733
        if (phone != null) {
            val poly = WardEdge.outline(phone)
            val j = WardEdge.join(poly, y = 733.0, radius = phone.radius)
            if (j != null) {
                check("join 402x874 y 733: radius 47.10", nearTol(j.left?.radius ?: 0.0, 47.10) && nearTol(j.right?.radius ?: 0.0, 47.10))
                check("join 402x874 y 733: left center (59.10, 780.10)", nearTol(j.left?.center?.x ?: 0.0, 59.10) && nearTol(j.left?.center?.y ?: 0.0, 780.10))
                check("join 402x874 y 733: right center (342.90, 780.10)", nearTol(j.right?.center?.x ?: 0.0, 342.90) && nearTol(j.right?.center?.y ?: 0.0, 780.10))
                check("join 402x874 y 733: left join (12, 780.10)", nearTol(j.left?.join?.x ?: 0.0, 12.0) && nearTol(j.left?.join?.y ?: 0.0, 780.10))
                check("join 402x874 y 733: right join (390, 780.10)", nearTol(j.right?.join?.x ?: 0.0, 390.0) && nearTol(j.right?.join?.y ?: 0.0, 780.10))
                check("join 402x874 y 733: fromX 59.10 toX 342.90", nearTol(j.fromX ?: 0.0, 59.10) && nearTol(j.toX ?: 0.0, 342.90))
                val lc = j.left
                val rc = j.right
                if (lc != null && rc != null) {
                    val dLineL = abs(hypot(lc.lineX - lc.center.x, 733.0 - lc.center.y) - lc.radius)
                    val dJoinL = abs(hypot(lc.join.x - lc.center.x, lc.join.y - lc.center.y) - lc.radius)
                    val dLineR = abs(hypot(rc.lineX - rc.center.x, 733.0 - rc.center.y) - rc.radius)
                    val dJoinR = abs(hypot(rc.join.x - rc.center.x, rc.join.y - rc.center.y) - rc.radius)
                    check("join 402x874 y 733: arc points on circle within 0.01",
                        dLineL <= 0.01 && dJoinL <= 0.01 && dLineR <= 0.01 && dJoinR <= 0.01)
                    val degL = joinTangencyDevDeg(lc, poly)
                    val degR = joinTangencyDevDeg(rc, poly)
                    check("join 402x874 y 733: join tangent within 0.5 degrees", degL <= 0.5 && degR <= 0.5, "$degL, $degR")
                }
            } else {
                check("join 402x874 y 733: join exists", false)
            }
        }

        // A1 (b): Windows 834 x 1194, 1194 x 834 and 1032 x 1376, y 128 pt above opening bottom
        for ((w, h) in listOf(834.0 to 1194.0, 1194.0 to 834.0, 1032.0 to 1376.0)) {
            val p = WardPaper.panel(w, h) ?: continue
            val poly = WardEdge.outline(p)
            val maxY = poly.maxOfOrNull { it.y } ?: (p.y + p.height)
            val y = maxY - 128.0
            val j = WardEdge.join(poly, y = y, radius = p.radius)
            val name = "${w.toInt()}x${h.toInt()}"
            if (j != null) {
                check("join $name y=${y.toInt()}: r = 64", nearTol(j.left?.radius ?: 0.0, 64.0) && nearTol(j.right?.radius ?: 0.0, 64.0))
                for ((side, c) in listOf("left" to j.left, "right" to j.right)) {
                    if (c == null) continue
                    val dJoin = minPolylineDist(c.join, poly)
                    check("join $name $side: join on polyline within 0.1", dJoin <= 0.1, "$dJoin")
                    val deg = joinTangencyDevDeg(c, poly)
                    check("join $name $side: tangent within 1 degree", deg <= 1.0, "$deg")
                    var maxOut = 0.0
                    for (k in 0 until 360) {
                        val rad = k * 2.0 * PI / 360.0
                        val pt = WardVec(c.center.x + c.radius * cos(rad), c.center.y + c.radius * sin(rad))
                        if (!pointInPoly(pt, poly)) maxOut = max(maxOut, minPolylineDist(pt, poly))
                    }
                    check("join $name $side: 360 points inside outline within 0.1", maxOut <= 0.1, "$maxOut")
                }
            } else {
                check("join $name: join exists", false)
            }
        }

        // A1 (c): Window 402 x 874: y 800 gives r = 31 within 0.01, tangent as in (b); y 840 gives no arcs
        if (phone != null) {
            val poly = WardEdge.outline(phone)
            val j800 = WardEdge.join(poly, y = 800.0, radius = phone.radius)
            if (j800 != null) {
                check("join 402x874 y 800: r = 31", nearTol(j800.left?.radius ?: 0.0, 31.0) && nearTol(j800.right?.radius ?: 0.0, 31.0))
                j800.left?.let { lc ->
                    val dJoin = minPolylineDist(lc.join, poly)
                    val deg = joinTangencyDevDeg(lc, poly)
                    check("join 402x874 y 800: tangent as in (b)", dJoin <= 0.1 && deg <= 1.0, "dJoin=$dJoin, deg=$deg")
                }
            } else {
                check("join 402x874 y 800: join exists", false)
            }
            val j840 = WardEdge.join(poly, y = 840.0, radius = phone.radius)
            if (j840 != null) {
                check("join 402x874 y 840: no arcs", j840.left == null && j840.right == null)
                val fx = j840.fromX
                val tx = j840.toX
                if (fx != null && tx != null) {
                    val dFrom = minPolylineDist(WardVec(fx, 840.0), poly)
                    val dTo = minPolylineDist(WardVec(tx, 840.0), poly)
                    check("join 402x874 y 840: fromX and toX on outline within 0.1", dFrom <= 0.1 && dTo <= 0.1, "$dFrom, $dTo")
                } else {
                    check("join 402x874 y 840: fromX and toX exist", false)
                }
            } else {
                check("join 402x874 y 840: join exists", false)
            }
        }

        // A1 (d): In every case above, left and right mirror each other about the window's middle within 0.01 pt.
        for ((w, h, yVal) in listOf(Triple(402.0, 874.0, 733.0), Triple(834.0, 1194.0, 1194.0 - 12 - 128.0),
            Triple(402.0, 874.0, 800.0), Triple(402.0, 874.0, 840.0))) {
            val p = WardPaper.panel(w, h) ?: continue
            val j = WardEdge.join(WardEdge.outline(p), y = yVal, radius = p.radius) ?: continue
            val mid = w / 2.0
            val tag = "${w.toInt()}x${h.toInt()} y=${yVal.toInt()}"
            val lc = j.left
            val rc = j.right
            if (lc != null && rc != null) {
                check("mirroring $tag: centers", nearTol(lc.center.x + rc.center.x, 2 * mid))
                check("mirroring $tag: joins", nearTol(lc.join.x + rc.join.x, 2 * mid))
            }
            val fx = j.fromX
            val tx = j.toX
            if (fx != null && tx != null) check("mirroring $tag: fromX and toX", nearTol(fx + tx, 2 * mid))
        }

        // A1 (e): Window 402 x 874, y 733, slab sides at x 28 and 374: slabTopRadius is 31.10 on both sides within 0.01;
        // no sampled point of slab's top edge or top corner arcs is above line or outside island's arcs by > 0.01 pt.
        // Slab sides at x 120 and 282: 24.
        if (phone != null) {
            val j = WardEdge.join(WardEdge.outline(phone), y = 733.0, radius = phone.radius)
            if (j != null) {
                val rL = WardEdge.slabTopRadius(j.left, slabSide = 28.0, leading = true)
                val rR = WardEdge.slabTopRadius(j.right, slabSide = 374.0, leading = false)
                check("slabTopRadius 28 and 374: 31.10", nearTol(rL, 31.10) && nearTol(rR, 31.10))
                val rLIn = WardEdge.slabTopRadius(j.left, slabSide = 120.0, leading = true)
                val rRIn = WardEdge.slabTopRadius(j.right, slabSide = 282.0, leading = false)
                check("slabTopRadius 120 and 282: 24", rLIn == 24.0 && rRIn == 24.0)

                var slabOk = true
                val lc = j.left
                val rc = j.right
                if (lc != null && rc != null) {
                    // left corner arc
                    for (k in 0..100) {
                        val phi = k * (PI / 2.0) / 100.0
                        val pt = WardVec(28 + rL - rL * sin(phi), 733 + rL - rL * cos(phi))
                        if (pt.y < 733.0 - 0.01) slabOk = false
                        if (hypot(pt.x - lc.center.x, pt.y - lc.center.y) > lc.radius + 0.01) slabOk = false
                    }
                    // top edge straight run
                    val xStart = 28 + rL
                    val xEnd = 374 - rR
                    for (k in 0..100) {
                        val pt = WardVec(xStart + k * (xEnd - xStart) / 100.0, 733.0)
                        if (pt.y < 733.0 - 0.01) slabOk = false
                    }
                    // right corner arc
                    for (k in 0..100) {
                        val phi = k * (PI / 2.0) / 100.0
                        val pt = WardVec(374 - rR + rR * sin(phi), 733 + rR - rR * cos(phi))
                        if (pt.y < 733.0 - 0.01) slabOk = false
                        if (hypot(pt.x - rc.center.x, pt.y - rc.center.y) > rc.radius + 0.01) slabOk = false
                    }
                }
                check("slab top edge and corner arcs inside island within 0.01", slabOk)
            } else {
                check("slabTopRadius join exists", false)
            }
        }

        // A1 (f): Lines under a header: window 402 x 874, y 116: r 47.10, joins (12, 163.10) and (390, 163.10);
        // window 834 x 1194, y 90: r = the panel's radius (100.93) within 0.01, tangent as in (b).
        if (phone != null) {
            WardEdge.join(WardEdge.outline(phone), y = 116.0, radius = phone.radius)?.let { j ->
                check("header 402x874 y 116: r 47.10", nearTol(j.left?.radius ?: 0.0, 47.10))
                check("header 402x874 y 116: joins (12, 163.10) and (390, 163.10)",
                    nearTol(j.left?.join?.x ?: 0.0, 12.0) && nearTol(j.left?.join?.y ?: 0.0, 163.10) &&
                        nearTol(j.right?.join?.x ?: 0.0, 390.0) && nearTol(j.right?.join?.y ?: 0.0, 163.10))
            }
        }
        WardPaper.panel(834.0, 1194.0)?.let { p ->
            val poly = WardEdge.outline(p)
            WardEdge.join(poly, y = 90.0, radius = p.radius)?.let { j ->
                check("header 834x1194 y 90: r = 100.93", nearTol(j.left?.radius ?: 0.0, 100.93))
                j.left?.let { lc ->
                    val dJoin = minPolylineDist(lc.join, poly)
                    val deg = joinTangencyDevDeg(lc, poly)
                    check("header 834x1194 y 90: tangent as in (b)", dJoin <= 0.1 && deg <= 1.0, "$dJoin, $deg")
                }
            }
        }

        // A1 (g): left: false gives no left arc and fromX nil; the right side is as with both.
        if (phone != null) {
            val poly = WardEdge.outline(phone)
            val jBoth = WardEdge.join(poly, y = 733.0, radius = phone.radius, left = true, right = true)
            val jRightOnly = WardEdge.join(poly, y = 733.0, radius = phone.radius, left = false, right = true)
            check("left: false gives no left arc and fromX nil", jRightOnly != null && jRightOnly.left == null && jRightOnly.fromX == null)
            check("left: false keeps right side identical", jRightOnly?.right == jBoth?.right && jRightOnly?.toX == jBoth?.toX)
        }
    }
}
