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
            WardControlSize.buttonSmall == 44.0 && WardControlSize.buttonMaxWidth == 360.0 && WardControlSize.target == 44.0)
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
}
