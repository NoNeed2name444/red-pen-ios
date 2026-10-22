package com.stethoscore.app.ui.ward

import org.junit.Test
import java.io.File

// The tokens of ios/RedPen/Shared/Ward/WardTokens.swift, as WardTokens.kt
// and WardType.kt carry them: the type (every face a text style, so the font
// size setting scales it), spacing and radii on WardScale (WardPaletteTests'
// scale: 4, 8, 12, 16, 24, 32), the small caps, and the animated glide's
// steps (WardLookDriver). The numbers are iOS's.
class WardTokensTest {

    @Test fun spacingAndRadiiAreOnTheScale() = checks {
        check("the spacing is iOS's: xs 4, s 8, m 12, gutter 16, l 16, xl 24, xxl 32, section 24, leading 4",
            WardSpace.xs == 4.0 && WardSpace.s == 8.0 && WardSpace.m == 12.0 && WardSpace.gutter == 16.0 &&
                WardSpace.l == 16.0 && WardSpace.xl == 24.0 && WardSpace.xxl == 32.0 && WardSpace.section == 24.0 &&
                WardSpace.leading == WardScale.leading)
        for (gap in listOf(WardSpace.xs, WardSpace.s, WardSpace.m, WardSpace.gutter, WardSpace.l, WardSpace.xl, WardSpace.xxl, WardSpace.section)) {
            check("the gap $gap is on the scale", WardScale.onScale(gap))
        }
        check("the radii are iOS's: card 16, tile 24, button 16, field 12, icon 12, bar 24",
            WardRadius.card == 16.0 && WardRadius.tile == 24.0 && WardRadius.button == 16.0 &&
                WardRadius.field == 12.0 && WardRadius.icon == 12.0 && WardRadius.bar == 24.0)
        for (r in listOf(WardRadius.card, WardRadius.tile, WardRadius.button, WardRadius.field, WardRadius.icon, WardRadius.bar)) {
            check("the radius $r is on the scale", WardScale.onScale(r))
        }
        check("the dock's panel is WardRadius.bar (WardScale.xl)", WardRadius.bar == WardScale.xl && WardDock.panelRadius == WardRadius.bar)
    }

    @Test fun theTypeIsTextStyles() = checks {
        // iOS's text styles at the default (Large) size: point and line
        val sizes = mapOf(
            WardTextStyle.largeTitle to (34.0 to 41.0), WardTextStyle.title to (28.0 to 34.0), WardTextStyle.title2 to (22.0 to 28.0),
            WardTextStyle.title3 to (20.0 to 25.0), WardTextStyle.headline to (17.0 to 22.0), WardTextStyle.body to (17.0 to 22.0),
            WardTextStyle.callout to (16.0 to 21.0), WardTextStyle.subheadline to (15.0 to 20.0), WardTextStyle.footnote to (13.0 to 18.0),
            WardTextStyle.caption to (12.0 to 16.0), WardTextStyle.caption2 to (11.0 to 13.0),
        )
        check("every text style is listed", sizes.keys == WardTextStyle.entries.toSet())
        for ((style, pl) in sizes) check("$style is ${pl.first} on ${pl.second}", style.size == pl.first && style.line == pl.second)
        check("display is largeTitle bold", WardType.display == WardTypeSpec(WardTextStyle.largeTitle, WardWeight.bold))
        check("title is title3 semibold", WardType.title == WardTypeSpec(WardTextStyle.title3, WardWeight.semibold))
        check("headline is headline (semibold)", WardType.headline == WardTypeSpec(WardTextStyle.headline, WardWeight.semibold))
        check("body and caption are regular", WardType.body == WardTypeSpec(WardTextStyle.body, WardWeight.regular) &&
            WardType.caption == WardTypeSpec(WardTextStyle.caption, WardWeight.regular))
        check("observations are mono: body, and title2 semibold",
            WardType.obs == WardTypeSpec(WardTextStyle.body, WardWeight.regular, mono = true) &&
                WardType.obsLarge == WardTypeSpec(WardTextStyle.title2, WardWeight.semibold, mono = true))
        check("the buttons: primary headline bold, secondary and destructive headline, compact and quiet subheadline semibold",
            WardType.buttonPrimary == WardTypeSpec(WardTextStyle.headline, WardWeight.bold) &&
                WardType.button == WardTypeSpec(WardTextStyle.headline, WardWeight.semibold) &&
                WardType.buttonSmall == WardTypeSpec(WardTextStyle.subheadline, WardWeight.semibold))
        check("a chip subheadline semibold, a status chip caption semibold, a pill subheadline bold, the timer mono",
            WardType.chip == WardTypeSpec(WardTextStyle.subheadline, WardWeight.semibold) &&
                WardType.statusChip == WardTypeSpec(WardTextStyle.caption, WardWeight.semibold) &&
                WardType.pill == WardTypeSpec(WardTextStyle.subheadline, WardWeight.bold) && WardType.timer.mono)
        // every face scales with the font size: WardType.kt sets them in sp, never dp or px
        val source = File("src/main/java/com/stethoscore/app/ui/ward/WardType.kt").takeIf { it.exists() }?.readText() ?: ""
        check("found WardType.kt", source.isNotEmpty())
        check("a face's size and line are in sp", source.contains("fontSize = size.sp") && source.contains("lineHeight = line.sp"))
        check("the theme uses the Ward typography",
            (File("src/main/java/com/stethoscore/app/ui/Theme.kt").takeIf { it.exists() }?.readText() ?: "").contains("typography=wardTypography()"))
    }

    @Test fun smallCaps() = checks {
        check("caption semibold in Biro Grey", WardSmallCaps.font == WardTypeSpec(WardTextStyle.caption, WardWeight.semibold) &&
            WardSmallCaps.colour == WardToken.inkSecondary)
        check("spaced 0.8 at the standard sizes", WardSmallCaps.tracking(1.0) == 0.8 && WardSmallCaps.tracking(1.3) == 0.8)
        check("not spaced at the accessibility sizes (the AX5 audit's clipped date)",
            WardSmallCaps.tracking(28.0 / 17) == 0.0 && WardSmallCaps.tracking(2.0) == 0.0)
    }

    @Test fun controlSizes() = checks {
        check("buttons 56, compact and quiet 44, at most 360 wide", WardControlSize.button == 56.0 &&
            WardControlSize.buttonSmall == 44.0 && WardControlSize.buttonMaxWidth == 360.0)
        check("the least target is 48 on Android, Android's own (the owner, 22 Oct; iOS keeps 44)", WardControlSize.target == 48.0)
        check("an icon square's corner is WardRadius.icon, less on a small one",
            kotlin.math.abs(WardControlSize.iconRadius(40.0) - 11.2) < 1e-9 && WardControlSize.iconRadius(100.0) == WardRadius.icon)
        check("a big icon square stands at mid", WardControlSize.iconLift(56.0) == WardLift.mid && WardControlSize.iconLift(40.0) == WardLift.low &&
            WardControlSize.iconRadius(56.0) == WardRadius.icon)
        check("a ring's groove clears its arc by 2, or a third of a thin one",
            WardControlSize.ringClear(8.0) == 2.0 && WardControlSize.ringClear(3.0) == 1.0)
        check("the timer: Time at zero, minutes, hours over an hour",
            wardTimerText(0) == "Time" && wardTimerText(59) == "0:59" && wardTimerText(3900) == "1:05:00")
    }

    @Test fun theGlide() = checks {
        val light = WardLook(dark = false, section = WardSection.cards)
        val rest = WardGlide.rest(light)
        check("asking for the look it is at changes nothing", WardLookDriver.go(light, rest, reduceMotion = false) == rest)
        val dark = WardLook(dark = true, section = WardSection.cards)
        check("light and dark arrive in one step", WardLookDriver.go(dark, rest, reduceMotion = false) == WardGlide.rest(dark))
        val cases = WardLook(dark = false, section = WardSection.cases)
        val shift = WardLookDriver.go(cases, rest, reduceMotion = false)
        check("a new section's hue shifts from where it is", !shift.settled && shift.from == light && shift.to == cases && shift.progress == 0.0)
        check("with animations off it arrives at once", WardLookDriver.go(cases, rest, reduceMotion = true) == WardGlide.rest(cases))
        val half = WardLookDriver.step(shift, 0.0, WardGlide.duration / 2)
        check("half way through the duration, half way", !half.settled && kotlin.math.abs(half.progress - 0.5) < 1e-9, f3(half.progress))
        check("at the end of the duration, at rest", WardLookDriver.step(shift, 0.0, WardGlide.duration) == WardGlide.rest(cases))
        check("a shift taken up part way keeps its start", WardLookDriver.step(shift, 0.4, WardGlide.duration * 0.3).progress.let { kotlin.math.abs(it - 0.7) < 1e-9 })
        check("the glide is the scheme's 0.35 seconds", WardGlide.duration == 0.35)
    }

    /** Where a cubic Bézier easing [c] is at [x] of the time (x(u) is monotonic for these curves). */
    private fun ease(c: WardPress.Curve, x: Double): Double {
        fun bez(p1: Double, p2: Double, u: Double): Double { val m = 1 - u; return 3 * m * m * u * p1 + 3 * m * u * u * p2 + u * u * u }
        var lo = 0.0
        var hi = 1.0
        repeat(60) { val mid = (lo + hi) / 2; if (bez(c.x1, c.x2, mid) < x) lo = mid else hi = mid }
        return bez(c.y1, c.y2, (lo + hi) / 2)
    }

    /** A spring from rest one unit from its mark, at [damping] and [stiffness] (unit mass): its lowest point and when it is last more than 1% away. */
    private fun spring(damping: Double, stiffness: Double): Pair<Double, Double> {
        val w = kotlin.math.sqrt(stiffness)
        var x = 1.0
        var v = 0.0
        var lowest = 1.0
        var settled = 0.0
        val dt = 1e-5
        var t = 0.0
        while (t < 3.0) {
            v += (-stiffness * x - 2 * damping * w * v) * dt
            x += v * dt
            t += dt
            lowest = minOf(lowest, x)
            if (kotlin.math.abs(x) > 0.01) settled = t
        }
        return lowest to settled
    }

    // platform.md: a change moves for 200 to 320 ms on an ease-out, with no
    // bounce and no overshoot; the durations and curves are iOS's.
    @Test fun theMotion() = checks {
        check("the band is 200 to 320 ms", WardMotion.shortest == 0.2 && WardMotion.longest == 0.32)
        check("iOS's durations: the switch 0.2 (.snappy), a travel 0.3 (.snappy), a fill 0.3 (.easeOut, .smooth)",
            WardMotion.toggle == 0.2 && WardMotion.travel == 0.3 && WardMotion.fill == 0.3)
        for ((name, s) in listOf("toggle" to WardMotion.toggle, "travel" to WardMotion.travel, "fill" to WardMotion.fill,
            "the press's shade in" to WardPress.shadePress, "the press's shade out" to WardPress.shadeRelease)) {
            check("$name (${f2(s)} s) is in the band", WardMotion.inBand(s))
        }
        check("kept outside the band as iOS keeps them: the spoken word's 0.1 and the working trace's 1.2",
            WardMotion.word == 0.1 && WardMotion.trace == 1.2 && !WardMotion.inBand(WardMotion.word) && !WardMotion.inBand(WardMotion.trace))
        check("the band's edges are in it, and a 0.9 or 0.6 is not (the old rings and score)",
            WardMotion.inBand(0.2) && WardMotion.inBand(0.32) && !WardMotion.inBand(0.9) && !WardMotion.inBand(0.6) && !WardMotion.inBand(0.45))
        check("iOS's curves: ease-out (0, 0, 0.58, 1), ease-in-out (0.42, 0, 0.58, 1)",
            WardMotion.easeOut == WardPress.Curve(0.0, 0.0, 0.58, 1.0) && WardMotion.easeInOut == WardPress.Curve(0.42, 0.0, 0.58, 1.0))
        val samples = (0..100).map { it / 100.0 }
        for ((name, c) in listOf("ease-out" to WardMotion.easeOut, "ease-in-out" to WardMotion.easeInOut)) {
            val ys = samples.map { ease(c, it) }
            check("$name runs from 0 to 1 and never past either (no overshoot)", kotlin.math.abs(ys.first()) < 1e-6 &&
                kotlin.math.abs(ys.last() - 1) < 1e-6 && ys.all { it in -1e-9..1 + 1e-9 } && ys.zipWithNext().all { (a, b) -> b >= a - 1e-9 })
        }
        check("the ease-out is fast at the start and settles gently",
            ease(WardMotion.easeOut, 0.25) > 0.35 && ease(WardMotion.easeOut, 0.5) > 0.6 && ease(WardMotion.easeOut, 0.9) > 0.97,
            "${f3(ease(WardMotion.easeOut, 0.25))} ${f3(ease(WardMotion.easeOut, 0.5))} ${f3(ease(WardMotion.easeOut, 0.9))}")
        check("a spring is critically damped", WardMotion.damping == 1.0)
        check("a spring's stiffness is (2π / duration)²: 438.65 for 0.3 s, 986.96 for 0.2 s",
            kotlin.math.abs(WardMotion.stiffness(0.3) - 438.65) < 0.01 && kotlin.math.abs(WardMotion.stiffness(0.2) - 986.96) < 0.01,
            "${f2(WardMotion.stiffness(0.3))} ${f2(WardMotion.stiffness(0.2))}")
        for ((name, s) in listOf("toggle" to WardMotion.toggle, "travel" to WardMotion.travel, "fill" to WardMotion.fill)) {
            val (lowest, settled) = spring(WardMotion.damping, WardMotion.stiffness(s))
            check("$name's spring never passes its mark", lowest >= -1e-6, f3(lowest))
            check("$name's spring is within 1% of its mark inside the band's 0.32 s", settled <= WardMotion.longest, f3(settled))
        }
        val (bounced, _) = spring(0.85, 600.0)
        check("the old (0.85, 600) spring passed its mark (the check bites)", bounced < -1e-3, f3(bounced))
        check("animations are off only at the scale's 0 (Remove animations)",
            WardMotion.reduce(0f) && !WardMotion.reduce(1f) && !WardMotion.reduce(0.5f) && !WardMotion.reduce(10f))
        val type = File("src/main/java/com/stethoscore/app/ui/ward/WardType.kt").takeIf { it.exists() }?.readText() ?: ""
        check("the flag is the animator duration scale, watched as it changes",
            type.contains("Settings.Global.ANIMATOR_DURATION_SCALE") && type.contains("registerContentObserver") &&
                type.contains("unregisterContentObserver"))
        check("with animations off a Ward spec is simply there", type.contains("if (reduce) snap() else tween(") &&
            type.contains("if (reduce) snap() else spring("))
        check("the theme provides the flag to every surface",
            (File("src/main/java/com/stethoscore/app/ui/Theme.kt").takeIf { it.exists() }?.readText() ?: "")
                .contains("LocalWardReduceMotion provides reduceMotion"))
    }
}
