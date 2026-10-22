package com.stethoscore.app.ui.ward

import kotlin.math.min

// A port of the framework-free parts of ios/RedPen/Shared/Ward/WardTokens.swift:
// the type, spacing and radii, the small caps, and the step of the animated
// glide (WardLookDriver). The colours themselves come from WardPalette,
// WardSection and WardLook; the Compose side (TextStyles in sp, dp, the
// driver's frame loop) is WardType.kt. Pure Kotlin (WardTokensTest).

/** Gaps and padding, every one a step of WardScale (4, 8, 12, 16, 24, 32), in points (dp). */
object WardSpace {
    const val xs = WardScale.xs
    const val s = WardScale.s
    const val m = WardScale.m
    /** The screen's side gutter, and a card's padding. */
    const val gutter = WardScale.l
    const val l = WardScale.l
    const val xl = WardScale.xl
    const val xxl = WardScale.xxl
    /** Between the sections of a page. */
    const val section = WardScale.xl
    /** Extra room between the lines of a paragraph. */
    const val leading = WardScale.leading
}

/** Corner radii, on the same scale, in points (dp). */
object WardRadius {
    const val card = WardScale.l
    const val tile = WardScale.xl
    const val button = WardScale.l
    const val field = WardScale.m
    const val icon = WardScale.m
    const val bar = WardScale.xl
}

/** The text styles iOS's Dynamic Type has, at its default (Large) size: point size and line height. */
enum class WardTextStyle(val size: Double, val line: Double) {
    largeTitle(34.0, 41.0),
    title(28.0, 34.0),
    title2(22.0, 28.0),
    title3(20.0, 25.0),
    headline(17.0, 22.0),
    body(17.0, 22.0),
    callout(16.0, 21.0),
    subheadline(15.0, 20.0),
    footnote(13.0, 18.0),
    caption(12.0, 16.0),
    caption2(11.0, 13.0),
}

/** A face's weight, as the 100 to 900 scale Android's FontWeight takes. */
enum class WardWeight(val value: Int) { regular(400), medium(500), semibold(600), bold(700) }

/**
 * One of WardType's faces: a text style (so it scales with the reader's text
 * size: on Android its size is in sp), a weight and, for observations, mono.
 */
data class WardTypeSpec(val style: WardTextStyle, val weight: WardWeight, val mono: Boolean = false) {
    val size: Double get() = style.size
    val line: Double get() = style.line
}

/**
 * The type: system fonts only (Roboto on Android, Roboto Mono or the system
 * monospace for observations), every one a text style so the font size
 * setting scales it.
 */
object WardType {
    val display = WardTypeSpec(WardTextStyle.largeTitle, WardWeight.bold)
    val title = WardTypeSpec(WardTextStyle.title3, WardWeight.semibold)
    /** headline is semibold on iOS. */
    val headline = WardTypeSpec(WardTextStyle.headline, WardWeight.semibold)
    val body = WardTypeSpec(WardTextStyle.body, WardWeight.regular)
    val caption = WardTypeSpec(WardTextStyle.caption, WardWeight.regular)
    /** Observations: BP 128/82. */
    val obs = WardTypeSpec(WardTextStyle.body, WardWeight.regular, mono = true)
    val obsLarge = WardTypeSpec(WardTextStyle.title2, WardWeight.semibold, mono = true)

    // the controls' own faces (WardControls)
    val buttonPrimary = WardTypeSpec(WardTextStyle.headline, WardWeight.bold)
    val button = WardTypeSpec(WardTextStyle.headline, WardWeight.semibold)
    val buttonSmall = WardTypeSpec(WardTextStyle.subheadline, WardWeight.semibold)
    val chip = WardTypeSpec(WardTextStyle.subheadline, WardWeight.semibold)
    val statusChip = WardTypeSpec(WardTextStyle.caption, WardWeight.semibold)
    val pill = WardTypeSpec(WardTextStyle.subheadline, WardWeight.bold)
    val timer = WardTypeSpec(WardTextStyle.subheadline, WardWeight.semibold, mono = true)
    val segment = WardTypeSpec(WardTextStyle.subheadline, WardWeight.regular)
    val segmentChosen = WardTypeSpec(WardTextStyle.subheadline, WardWeight.semibold)
    val circleGlyph = WardTypeSpec(WardTextStyle.body, WardWeight.semibold)
    val smallCaps = WardTypeSpec(WardTextStyle.caption, WardWeight.semibold)

    /**
     * Where Android's font scale reaches iOS's accessibility sizes: body at
     * AX1 is 28 points against Large's 17.
     */
    const val accessibilityScale = 28.0 / 17.0

    fun isAccessibilitySize(fontScale: Double): Boolean = fontScale >= accessibilityScale
}

/**
 * A small-caps label ("TODAY'S WARD ROUND"): the source string stays in mixed
 * case so TalkBack reads words, not letters. Its letters are spaced at the
 * standard sizes, where they are small; at the accessibility sizes they are
 * big enough to read apart, and a wrapped date with the spacing ran past its
 * frame (the AX5 audit's "Text clipped", 15 Oct).
 */
object WardSmallCaps {
    /** The letter spacing at the standard sizes, in points. */
    const val tracking = 0.8
    val font: WardTypeSpec = WardType.smallCaps
    val colour: WardToken = WardToken.inkSecondary

    fun tracking(fontScale: Double): Double = if (WardType.isAccessibilitySize(fontScale)) 0.0 else tracking
}

/** The controls' sizes, in points (dp): WardControls'. */
object WardControlSize {
    /** A button, a field's row: 56 tall; compact and quiet, 44. */
    const val button = 56.0
    const val buttonSmall = 44.0
    /**
     * The least tap target: 48 on Android, Android's own (the owner, 22 Oct;
     * iOS keeps 44). The touch area grows to it, never what is drawn, so a
     * control still looks as on iOS: the theme hands it to Material's
     * minimumInteractiveComponentSize, which the Ward controls wear.
     */
    const val target = 48.0
    /** A broad screen's widest button. */
    const val buttonMaxWidth = 360.0
    /** A segment's least height, and the segmented capsule's padding. */
    const val segment = 36.0
    const val segmentedPadding = 4.0
    /** The switch: its track and knob. */
    const val toggleWidth = 52.0
    const val toggleHeight = 32.0
    const val knob = 24.0
    /** An icon square, and its glyph's share of it. */
    const val iconSquare = 40.0
    const val iconGlyph = 0.42
    const val iconRadiusShare = 0.28
    /** A ring's arc. */
    const val ringLine = 8.0
    const val ringNumeral = 26.0

    /** An icon square's corner: WardRadius.icon, or less on a small one. */
    fun iconRadius(size: Double): Double = min(WardRadius.icon, size * iconRadiusShare)

    /** An icon square stands at mid from 56 points up, low under it. */
    fun iconLift(size: Double): WardLift = if (size >= 56) WardLift.mid else WardLift.low

    /** A ring's groove clearance either side of the arc. */
    fun ringClear(lineWidth: Double): Double = min(2.0, lineWidth / 3)
}

/**
 * Runs the shift (WardLookDriver): light and dark arrive in one step, every
 * Ward colour in the same frame; a new section's hue is stepped each frame
 * for WardGlide.duration, then left at rest. With animations off (Android's
 * animator duration scale at 0, iOS's Reduce Motion) a new look arrives at
 * once. The frame loop is WardType.kt's rememberWardGlide; these are its
 * steps.
 */
object WardLookDriver {
    /** Where a shift goes when [look] is asked for while the app is at [now]. */
    fun go(look: WardLook, now: WardGlide, reduceMotion: Boolean): WardGlide {
        if (look == now.to) return now
        if (reduceMotion) return WardGlide.rest(look)
        return WardGlide.toward(look, now)
    }

    /** The shift [elapsed] seconds after it started at [startProgress]; at its end, at rest. */
    fun step(glide: WardGlide, startProgress: Double, elapsed: Double): WardGlide {
        val progress = min(1.0, startProgress + elapsed / WardGlide.duration)
        return if (progress >= 1) WardGlide.rest(glide.to) else glide.copy(progress = progress)
    }
}
