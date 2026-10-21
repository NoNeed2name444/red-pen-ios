package com.stethoscore.app.ui.ward

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

// A port of upstream/ios/RedPen/Shared/Ward/WardPalette.swift, value for value.
//
// The Ward Round palette (docs/design/targets-2026-10-01.md §1): one table of
// light and dark values that every colour in the app is drawn from, and the
// contrast each text colour is promised against the surface it sits on.
//
// Soft UI on four close tiers per mode: a well pressed in, the matte base, a
// card a shade off it, and a sheet or a bar a shade further, so a card is told
// from the ground by its relief (WardRelief) and a whisper of colour, never by
// an edge. Day is cool grey paper (#E9EDF2) with slate Chart Ink; night is a
// deep blue-black ward (#171C24) with near-white ink. The primary is Cards'
// Care Blue (WardSection.outside), the look outside any section. Every hue is
// the owner's 2026-10-21 palette (iOS repo docs/design/palette-2026-10-21.md);
// words on any fill are near-black (onPrimary), as white reads under 4.5:1.
//
// Pure Kotlin (no Android imports), so the promises are tested on the JVM
// (WardPaletteTest); ui/Theme.kt turns the table into Compose colours.
// Colours are Ints holding 0xRRGGBB.

/** The palette's tokens. Names match iOS's WardToken cases. */
@Suppress("EnumEntryName")
enum class WardToken {
    /** The matte base every screen sits on */
    background,
    /** Cards and rows: a shade off the base, raised by relief */
    surface,
    /** Sheets, floating bars, popovers: a shade further than a card */
    raised,
    /** Wells pressed into the base: fields, tracks, a chosen segment */
    well,
    /** The primary as a fill (Cards' fill, the look outside any section) */
    primary,
    /** The primary as text and glyphs on a surface (Cards' accent) */
    primaryInk,
    /** White on a primary fill */
    onPrimary,
    /** ECG Red: the secondary accent */
    ecg,
    /** Pager Amber: the progress beam, the countdown pill */
    beam,
    /** Discharge Green */
    success,
    /** Caution Amber */
    warning,
    /** Resus Red */
    danger,
    /** Chart Ink: text */
    ink,
    /** Biro Grey: secondary text and small caps */
    inkSecondary,
    /** A groove: separators and the empty part of a track */
    hairline,
    /** The vitals monitor's well, dark in both modes */
    monitor,
    /** A wrong answer's row: a ground that has stepped back */
    faded,
    /** The words, strike and cross on the faded row */
    fadedInk,
}

/** A (light, dark) pair of 0xRRGGBB colours. */
data class WardPair(val light: Int, val dark: Int) {
    fun of(dark: Boolean): Int = if (dark) this.dark else light
}

/** A text colour, what it sits on, and the contrast it is promised. */
data class WardPromise(val text: WardToken, val on: WardToken, val ratio: Double)

/** A text colour promised on the always-dark monitor. */
data class WardMonitorPromise(val text: WardToken, val ratio: Double)

data class WardRgb(val r: Double, val g: Double, val b: Double)

object WardPalette {
    /** (light, dark) as 0xRRGGBB. */
    val table: Map<WardToken, WardPair> = mapOf(
        WardToken.background to WardPair(0xE9EDF2, 0x171C24),
        WardToken.surface to WardPair(0xEEF1F5, 0x242B35),
        WardToken.raised to WardPair(0xF1F4F8, 0x2E353F),
        WardToken.well to WardPair(0xDDE2E8, 0x090E15),
        WardToken.primary to WardPair(0x3B82F6, 0x3B82F6),
        WardToken.primaryInk to WardPair(0x0251C2, 0x84B2FD),
        WardToken.onPrimary to WardPair(0x090E15, 0x090E15),
        WardToken.ecg to WardPair(0xBB2A34, 0xF57875),
        WardToken.beam to WardPair(0x9F7818, 0xFBBF24),
        WardToken.success to WardPair(0x316E56, 0x6EE7B7),
        WardToken.warning to WardPair(0x7D5E14, 0xFBBF24),
        WardToken.danger to WardPair(0xBB2A34, 0xF57875),
        WardToken.ink to WardPair(0x232C39, 0xF1F4F8),
        WardToken.inkSecondary to WardPair(0x536171, 0xB8C2D0),
        WardToken.hairline to WardPair(0xCFD7E2, 0x04070B),
        WardToken.monitor to WardPair(0x0E1B2C, 0x0E1B2C),
        WardToken.faded to WardPair(0xDDE2E8, 0x40444B),
        WardToken.fadedInk to WardPair(0x52606F, 0xBEC8D3),
    )

    /** The tiers from deepest to highest: a well, the base, a card, a sheet. */
    val tiers: List<WardToken> = listOf(WardToken.well, WardToken.background, WardToken.surface, WardToken.raised)

    fun hex(token: WardToken, dark: Boolean): Int = table.getValue(token).of(dark)

    /** 0...1 components. */
    fun rgb(hex: Int): WardRgb =
        WardRgb(((hex shr 16) and 0xFF) / 255.0, ((hex shr 8) and 0xFF) / 255.0, (hex and 0xFF) / 255.0)

    internal fun linear(c: Double): Double = if (c <= 0.04045) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
    internal fun gamma(c: Double): Double = if (c <= 0.0031308) c * 12.92 else 1.055 * c.pow(1 / 2.4) - 0.055

    /** Swift's `.rounded()`: to nearest, halves away from zero. */
    internal fun round(x: Double): Int = if (x >= 0) kotlin.math.floor(x + 0.5).toInt() else -kotlin.math.floor(-x + 0.5).toInt()

    /**
     * A colour part way from [a] to [b] ([t] 0 to 1), mixed in linear light so
     * the middle of a light-to-dark shift is not muddy.
     */
    fun mix(a: Int, b: Int, t: Double): Int {
        val tt = min(1.0, max(0.0, t))
        val p = rgb(a)
        val q = rgb(b)
        fun channel(x: Double, y: Double): Int {
            val v = gamma(linear(x) + (linear(y) - linear(x)) * tt)
            return round(min(1.0, max(0.0, v)) * 255)
        }
        return (channel(p.r, q.r) shl 16) or (channel(p.g, q.g) shl 8) or channel(p.b, q.b)
    }

    /** WCAG 2 relative luminance. */
    fun luminance(hex: Int): Double {
        val c = rgb(hex)
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /** WCAG 2 contrast ratio, 1...21. */
    fun contrast(a: Int, b: Int): Double {
        val x = luminance(a)
        val y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /**
     * Each text colour, what it sits on, and the ratio it is promised: 4.5 for
     * text, 3 for the beam (large text and graphics only).
     */
    val promises: List<WardPromise> = listOf(
        WardPromise(WardToken.ink, WardToken.surface, 4.5), WardPromise(WardToken.ink, WardToken.background, 4.5),
        WardPromise(WardToken.ink, WardToken.raised, 4.5), WardPromise(WardToken.ink, WardToken.well, 4.5),
        WardPromise(WardToken.inkSecondary, WardToken.raised, 4.5), WardPromise(WardToken.inkSecondary, WardToken.well, 4.5),
        WardPromise(WardToken.primaryInk, WardToken.raised, 4.5), WardPromise(WardToken.primaryInk, WardToken.well, 4.5),
        WardPromise(WardToken.inkSecondary, WardToken.surface, 4.5), WardPromise(WardToken.inkSecondary, WardToken.background, 4.5),
        WardPromise(WardToken.primaryInk, WardToken.surface, 4.5), WardPromise(WardToken.primaryInk, WardToken.background, 4.5),
        WardPromise(WardToken.onPrimary, WardToken.primary, 4.5),
        WardPromise(WardToken.ecg, WardToken.surface, 4.5), WardPromise(WardToken.success, WardToken.surface, 4.5),
        WardPromise(WardToken.warning, WardToken.surface, 4.5), WardPromise(WardToken.danger, WardToken.surface, 4.5),
        WardPromise(WardToken.beam, WardToken.surface, 3.0),
        // a chip or a pill is pressed into a well, so every ink they use is promised on it too
        WardPromise(WardToken.ecg, WardToken.well, 4.5), WardPromise(WardToken.success, WardToken.well, 4.5),
        WardPromise(WardToken.warning, WardToken.well, 4.5), WardPromise(WardToken.danger, WardToken.well, 4.5),
        WardPromise(WardToken.beam, WardToken.well, 3.0),
        // soft UI tints labels and glyphs, not fills, so the accents sit on the ground too
        WardPromise(WardToken.ecg, WardToken.background, 4.5), WardPromise(WardToken.success, WardToken.background, 4.5),
        WardPromise(WardToken.warning, WardToken.background, 4.5), WardPromise(WardToken.danger, WardToken.background, 4.5),
        WardPromise(WardToken.beam, WardToken.background, 3.0),
        // a wrong answer's words, strike and cross on its faded row
        WardPromise(WardToken.fadedInk, WardToken.faded, 4.5),
    )

    /** The monitor's well wears the dark values in both modes, so each is promised on it too. */
    val monitorPromises: List<WardMonitorPromise> = listOf(
        WardMonitorPromise(WardToken.ink, 4.5), WardMonitorPromise(WardToken.inkSecondary, 4.5),
        WardMonitorPromise(WardToken.primaryInk, 4.5), WardMonitorPromise(WardToken.ecg, 4.5),
        WardMonitorPromise(WardToken.success, 4.5), WardMonitorPromise(WardToken.warning, 4.5),
        WardMonitorPromise(WardToken.danger, 4.5), WardMonitorPromise(WardToken.beam, 3.0),
    )
}

/**
 * The one spacing scale: every gap, padding and radius in the soft UI is a
 * step of it (dp on Android, points on iOS).
 */
object WardScale {
    val steps: List<Double> = listOf(4.0, 8.0, 12.0, 16.0, 24.0, 32.0)
    const val xs = 4.0
    const val s = 8.0
    const val m = 12.0
    const val l = 16.0
    const val xl = 24.0
    const val xxl = 32.0
    /** Extra room between the lines of a paragraph, on top of the style's own leading. */
    const val leading = 4.0

    fun onScale(value: Double): Boolean = steps.contains(value)
}

/** Light to dark and back: the colours move to the other palette over about a third of a second. */
object WardSchemeGlide {
    const val duration = 0.35

    /** One frame of the shift, [t] of the way from light to dark. */
    fun frame(token: WardToken, t: Double): Int =
        WardPalette.mix(WardPalette.hex(token, dark = false), WardPalette.hex(token, dark = true), t)
}
