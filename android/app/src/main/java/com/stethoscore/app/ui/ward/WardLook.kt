package com.stethoscore.app.ui.ward

import kotlin.math.max
import kotlin.math.min

// A port of ios/RedPen/Shared/Ward/WardLook.swift: what the app looks
// like at rest (light or dark, and which section), the one animated value
// every Ward colour is drawn from (WardGlide), the look as it is drawn now
// (WardLookNow), and the relief, press and paper specs mixed part way from
// light to dark. Pure Kotlin, tested on the JVM (WardLookTest).

/** What the app looks like at rest: light or dark, and which section. */
data class WardLook(val dark: Boolean, val section: WardSection)

/**
 * A move from one look to another, [progress] 0 to 1 over [duration]. Every
 * colour of a frame is taken from the same progress, so no frame mixes two
 * looks. Colours mix in linear light (WardPalette.mix); nothing fades.
 */
data class WardGlide(val from: WardLook, val to: WardLook, val progress: Double) {

    val settled: Boolean get() = progress >= 1 || from == to

    /** Ease in and out (smoothstep), so the shift starts and ends gently. */
    val eased: Double
        get() {
            val p = min(1.0, max(0.0, progress))
            return p * p * (3 - 2 * p)
        }

    /**
     * A new destination. Back to where this shift started: the same path in
     * reverse from where it is. Anywhere else: the shift so far is finished
     * at once and a new one starts from there.
     */
    fun retargeted(look: WardLook): WardGlide {
        if (look == to) return this
        if (settled) return WardGlide(to, look, 0.0)
        if (look == from) return WardGlide(to, from, 1 - min(1.0, max(0.0, progress)))
        return WardGlide(to, look, 0.0)
    }

    /**
     * How dark the palette is, 0 to 1, for something drawn in [dark]. A part
     * [held] in one mode (the vitals monitor), or drawn in the other mode,
     * stays where it is.
     */
    fun night(dark: Boolean, held: Boolean = false): Double {
        if (held || from.dark == to.dark || dark != to.dark) return if (dark) 1.0 else 0.0
        val a = if (from.dark) 1.0 else 0.0
        val b = if (to.dark) 1.0 else 0.0
        return a + (b - a) * eased
    }

    /** A palette colour this frame. The accents (primary, primaryInk) are the section's fill and accent. */
    fun hex(token: WardToken, dark: Boolean, held: Boolean = false): Int = when (token) {
        WardToken.primary -> sectioned(dark, held) { it.fill }
        WardToken.primaryInk -> sectioned(dark, held) { it.accent }
        else -> paletteHex(token, dark, held)
    }

    /** The palette's own colour this frame, whatever the section. */
    fun paletteHex(token: WardToken, dark: Boolean, held: Boolean = false): Int {
        val n = night(dark, held)
        if (n <= 0) return WardPalette.hex(token, dark = false)
        if (n >= 1) return WardPalette.hex(token, dark = true)
        return WardPalette.mix(WardPalette.hex(token, dark = false), WardPalette.hex(token, dark = true), n)
    }

    /** The section's ink this frame (grid and edges): the hue and the mode move together. */
    fun ink(dark: Boolean, held: Boolean = false): Int = sectioned(dark, held) { it.ink }

    /** The section's wash this frame (the ground behind every page): shifts with the section, like the grid's ink. */
    fun wash(dark: Boolean, held: Boolean = false): Int = sectioned(dark, held) { it.wash }

    /** A given section's ink this frame, mixed for the night but with no hue shift. */
    fun ink(section: WardSection, dark: Boolean, held: Boolean = false): Int {
        val n = night(dark, held)
        if (n <= 0) return section.ink.light
        if (n >= 1) return section.ink.dark
        return WardPalette.mix(section.ink.light, section.ink.dark, n)
    }

    /** One of a section's colours this frame, part way to the next section's while the hue shifts. */
    fun sectioned(dark: Boolean, held: Boolean = false, pair: (WardSection) -> WardPair): Int {
        val n = night(dark, held)
        fun at(section: WardSection): Int {
            val p = pair(section)
            if (n <= 0) return p.light
            if (n >= 1) return p.dark
            return WardPalette.mix(p.light, p.dark, n)
        }
        if (from.section == to.section || settled) return at(to.section)
        return WardPalette.mix(at(from.section), at(to.section), eased)
    }

    companion object {
        const val duration = WardSchemeGlide.duration

        fun rest(look: WardLook): WardGlide = WardGlide(look, look, 1.0)

        /**
         * Where the look goes next. Light and dark change in one step, every
         * colour at once (a mix of the palettes is grey on grey); a move
         * between sections shifts over [duration].
         */
        fun toward(look: WardLook, from: WardGlide): WardGlide {
            if (look.dark != from.to.dark) return rest(look)
            return from.retargeted(look)
        }

        /** The look a face or the paper draws this frame: the rest it was handed, else this frame of the shift. */
        fun drawn(rest: WardLook?, live: WardGlide): WardGlide = rest?.let { Companion.rest(it) } ?: live
    }
}

/**
 * The look the app is at this moment, read where a colour is drawn, so a
 * colour made before the section was set still shows the section on show.
 */
class WardLookNow(glide: WardGlide = WardGlide.rest(WardLook(dark = false, section = WardSection.outside))) {
    private val lock = Any()
    private var current: WardGlide = glide

    val glide: WardGlide get() = synchronized(lock) { current }

    fun set(glide: WardGlide) { synchronized(lock) { current = glide } }

    fun hex(token: WardToken, dark: Boolean, held: Boolean = false): Int = glide.hex(token, dark, held)

    fun ink(dark: Boolean, held: Boolean = false): Int = glide.ink(dark, held)

    fun ink(section: WardSection, dark: Boolean, held: Boolean = false): Int = glide.ink(section, dark, held)

    /** The section's wash as it is drawn now. */
    fun wash(dark: Boolean, held: Boolean = false): Int = glide.wash(dark, held)

    companion object {
        val shared = WardLookNow()
    }
}

/** A control's edge in [section]'s ink as it lands on [on] (the base by default). */
fun WardRelief.edgeColor(section: WardSection, dark: Boolean, highContrast: Boolean = false, on: Int? = null): Int =
    composite(WardReliefLight(section.ink(dark), edgeAlpha(dark, highContrast), 0.0, 0.0, 0.0), on = on ?: base(dark))

/** Part way from one light to another: colour in linear light, the rest straight. */
fun WardReliefLight.Companion.mix(a: WardReliefLight, b: WardReliefLight, t: Double): WardReliefLight {
    val tt = min(1.0, max(0.0, t))
    return WardReliefLight(WardPalette.mix(a.hex, b.hex, tt), a.alpha + (b.alpha - a.alpha) * tt,
        a.x + (b.x - a.x) * tt, a.y + (b.y - a.y) * tt, a.radius + (b.radius - a.radius) * tt)
}

/** Part way from one relief to another (light to dark), so the lights move with the palette. */
fun WardReliefSpec.Companion.mix(a: WardReliefSpec, b: WardReliefSpec, t: Double): WardReliefSpec {
    if (t <= 0) return a
    if (t >= 1) return b
    return WardReliefSpec(WardReliefLight.mix(a.highlight, b.highlight, t), WardReliefLight.mix(a.shade, b.shade, t),
        b.inner, a.edgeAlpha + (b.edgeAlpha - a.edgeAlpha) * t)
}

fun WardPressSpec.Companion.mix(a: WardPressSpec, b: WardPressSpec, t: Double): WardPressSpec {
    if (t <= 0) return a
    if (t >= 1) return b
    return WardPressSpec(
        blur = a.blur + (b.blur - a.blur) * t,
        outerHighlight = WardReliefLight.mix(a.outerHighlight, b.outerHighlight, t),
        outerShade = WardReliefLight.mix(a.outerShade, b.outerShade, t),
        innerShade = WardReliefLight.mix(a.innerShade, b.innerShade, t),
        innerHighlight = WardReliefLight.mix(a.innerHighlight, b.innerHighlight, t),
        edgeAlpha = a.edgeAlpha + (b.edgeAlpha - a.edgeAlpha) * t,
    )
}

/** Raised, `night` of the way from light to dark. */
fun WardRelief.raised(lift: WardLift, night: Double, highContrast: Boolean = false, control: Boolean = false): WardReliefSpec =
    WardReliefSpec.mix(raised(lift, false, highContrast, control), raised(lift, true, highContrast, control), night)

fun WardRelief.inset(lift: WardLift, night: Double, highContrast: Boolean = false, control: Boolean = false): WardReliefSpec =
    WardReliefSpec.mix(inset(lift, false, highContrast, control), inset(lift, true, highContrast, control), night)

fun WardRelief.rim(lift: WardLift, night: Double, highContrast: Boolean = false): WardReliefSpec =
    WardReliefSpec.mix(rim(lift, false, highContrast), rim(lift, true, highContrast), night)

fun WardPress.spec(lift: WardLift, depth: Double, night: Double, highContrast: Boolean = false, control: Boolean = true): WardPressSpec =
    WardPressSpec.mix(spec(lift, depth, false, highContrast, control), spec(lift, depth, true, highContrast, control), night)

/** The paper's ink this frame of [look]'s shift, for paper drawn in [dark]. */
fun WardPaper.ink(look: WardGlide, dark: Boolean, held: Boolean = false, highContrast: Boolean): WardPaperInk =
    ink(night = look.night(dark, held), highContrast = highContrast, hex = look.ink(dark, held))

/** The paper's ink [night] of the way to dark, in [hex] (a section's ink this frame). */
fun WardPaper.ink(night: Double, highContrast: Boolean, hex: Int): WardPaperInk {
    val a = ink(dark = false, highContrast = highContrast)
    val b = ink(dark = true, highContrast = highContrast)
    val t = min(1.0, max(0.0, night))
    return WardPaperInk(hex, a.fine + (b.fine - a.fine) * t, a.bold + (b.bold - a.bold) * t, a.edge + (b.edge - a.edge) * t)
}

/**
 * Home's ground for a look at rest: the base with the section's wash and the
 * ECG paper's grid over it, in the section's ink at the mode's strengths,
 * every [WardPaper.cell] and bold every [WardPaper.boldEvery], counted from
 * the window's top left. The window's background (res/values ward_ground,
 * WardGroundDrawable) and home (WardGroundBackground) are drawn from it, so
 * the ground is one from the first frame to home at rest.
 */
data class WardGround(val base: Int, val ink: WardPaperInk) {
    companion object {
        fun home(section: WardSection = WardSection.opening, dark: Boolean, highContrast: Boolean = false): WardGround {
            val look = WardGlide.rest(WardLook(dark, section))
            return WardGround(look.wash(dark), WardPaper.ink(look, dark, highContrast = highContrast))
        }
    }
}
