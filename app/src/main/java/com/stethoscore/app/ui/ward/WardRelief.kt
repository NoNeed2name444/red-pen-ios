package com.stethoscore.app.ui.ward

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

// A port of the Foundation part of upstream/ios/RedPen/Shared/Ward/WardRelief.swift:
// the lifts, the two lights, the relief and the rim, the press and the ECG
// paper's ink and panel. (WardEdge, the frame-line join geometry, is not
// ported yet: docs/parity.md, batch 2.) Pure Kotlin, tested on the JVM.

/** How far a soft UI surface stands off the base. Not Comparable on purpose: order by [rawValue]. */
@Suppress("EnumEntryName")
enum class WardLift(val rawValue: Int) {
    low(1), mid(2), high(3), peak(4);

    /** One step nearer the base, never below low. */
    val lower: WardLift get() = entries.firstOrNull { it.rawValue == rawValue - 1 } ?: low
}

/** One of the two lights a relief is drawn with: colour, strength, where it falls, how soft. */
data class WardReliefLight(
    val hex: Int,
    val alpha: Double,
    val x: Double,
    val y: Double,
    val radius: Double,
) {
    /** Lights below the visible threshold are omitted from rendering. */
    val lit: Boolean get() = alpha > 1e-4

    companion object
}

/** A relief: a highlight from the top left and a shade to the bottom right; `inner` when pressed in. */
data class WardReliefSpec(
    val highlight: WardReliefLight,
    val shade: WardReliefLight,
    val inner: Boolean,
    /** The ink edge's strength; 0 draws none. */
    val edgeAlpha: Double,
) {
    /** Raised to pressed in and back: the lights stay where they are. */
    fun mirrored(): WardReliefSpec = copy(inner = !inner)

    companion object
}

/** The soft UI light, per mode and lift. */
object WardRelief {
    const val lightShade: Int = 0xA3B1C6
    const val highContrastShadeGain = 0.15
    /** A control's edge, light and dark, in the paper's ink: about 3.3:1 on the base in both. */
    const val lightEdge = 0.85
    const val darkEdge = 0.7
    const val highContrastEdge = 1.0
    /** A card's or a slab's edge under Increase Contrast; none otherwise. */
    const val containerHighContrastEdge = 0.35
    /** The least a control's boundary may read against the base (WCAG 1.4.11). */
    const val edgeContrast = 3.0

    fun edgeAlpha(dark: Boolean, highContrast: Boolean = false): Double =
        if (highContrast) highContrastEdge else if (dark) darkEdge else lightEdge

    fun containerEdgeAlpha(highContrast: Boolean = false): Double =
        if (highContrast) containerHighContrastEdge else 0.0

    /** The ink of a control's edge: the ECG paper's ink outside any section. */
    fun edgeHex(dark: Boolean): Int = WardPaper.ink(dark = dark, highContrast = false).hex

    /** A control's edge as it lands on the base. */
    fun edgeColor(dark: Boolean, highContrast: Boolean = false): Int =
        composite(WardReliefLight(edgeHex(dark), edgeAlpha(dark, highContrast), 0.0, 0.0, 0.0), on = base(dark))

    fun offset(lift: WardLift): Double = when (lift) {
        WardLift.low -> 2.0
        WardLift.mid -> 5.0
        WardLift.high -> 8.0
        WardLift.peak -> 11.0
    }

    fun radius(lift: WardLift): Double = when (lift) {
        WardLift.low -> 3.0
        WardLift.mid -> 8.0
        WardLift.high -> 12.0
        WardLift.peak -> 16.0
    }

    /** Per lift, low to peak. */
    val lightHighlight = listOf(0.75, 0.8, 0.85, 0.9)
    val lightShadeAlpha = listOf(0.5, 0.55, 0.6, 0.65)
    val darkHighlight = listOf(0.05, 0.06, 0.07, 0.08)
    val darkShadeAlpha = listOf(0.45, 0.5, 0.55, 0.6)

    fun highlightAlpha(lift: WardLift, dark: Boolean): Double =
        (if (dark) darkHighlight else lightHighlight)[lift.rawValue - 1]

    fun shadeAlpha(lift: WardLift, dark: Boolean, highContrast: Boolean = false): Double {
        val alpha = (if (dark) darkShadeAlpha else lightShadeAlpha)[lift.rawValue - 1]
        return if (highContrast) alpha + highContrastShadeGain else alpha
    }

    /** The ground both lights fall on. */
    fun base(dark: Boolean): Int = WardPalette.hex(WardToken.background, dark)

    /** A surface raised off the base; with [control] a control's face, which carries the ink edge. */
    fun raised(lift: WardLift, dark: Boolean, highContrast: Boolean = false, control: Boolean = false): WardReliefSpec {
        val d = offset(lift)
        val r = radius(lift)
        return WardReliefSpec(
            highlight = WardReliefLight(0xFFFFFF, highlightAlpha(lift, dark), -d, -d, r),
            shade = WardReliefLight(if (dark) 0x000000 else lightShade, shadeAlpha(lift, dark, highContrast), d, d, r),
            inner = false,
            edgeAlpha = if (control) edgeAlpha(dark, highContrast) else containerEdgeAlpha(highContrast),
        )
    }

    fun inset(lift: WardLift, dark: Boolean, highContrast: Boolean = false, control: Boolean = false): WardReliefSpec =
        raised(lift, dark, highContrast, control).mirrored()

    // The rim: the one soft light a button keeps, within rimReach of the face.
    const val rimReach = 5.0
    const val rimMaxBlur = 2.0
    const val rimMaxOffset = 3.0

    fun rimOffset(lift: WardLift): Double = when (lift) {
        WardLift.low -> 2.0
        WardLift.mid -> 2.5
        WardLift.high, WardLift.peak -> 3.0
    }

    @Suppress("UNUSED_PARAMETER")
    fun rimBlur(lift: WardLift): Double = rimMaxBlur

    const val rimLightHighlight = 0.95
    const val rimLightShade = 0.9
    const val rimDarkHighlight = 0.1
    const val rimDarkShade = 0.85

    /** A button's face raised by its rim, with the control's ink edge. */
    fun rim(lift: WardLift, dark: Boolean, highContrast: Boolean = false): WardReliefSpec {
        val d = rimOffset(lift)
        val r = rimBlur(lift)
        val shade = (if (dark) rimDarkShade else rimLightShade) + (if (highContrast) highContrastShadeGain else 0.0)
        return WardReliefSpec(
            highlight = WardReliefLight(0xFFFFFF, if (dark) rimDarkHighlight else rimLightHighlight, -d, -d, r),
            shade = WardReliefLight(if (dark) 0x000000 else lightShade, min(1.0, shade), d, d, r),
            inner = false,
            edgeAlpha = edgeAlpha(dark, highContrast),
        )
    }

    /** How far past the face a light can show: its offset plus its blur. */
    fun reach(light: WardReliefLight): Double = max(abs(light.x), abs(light.y)) + light.radius

    /**
     * How much of a pressed-in face's inner shade reaches [depth] points in
     * from its edge, 0 to 1 (a SwiftUI radius is twice the blur's standard
     * deviation).
     */
    fun shadeCoverage(lift: WardLift, depth: Double): Double {
        val sigma = radius(lift) / 2
        return 0.5 * (1 - erf((depth - offset(lift)) / sigma / sqrt(2.0)))
    }

    /** What a pressed-in face of [fill] really is [depth] points in from its edge: the ground a chip's words sit on. */
    fun insetGround(fill: Int, lift: WardLift, dark: Boolean, highContrast: Boolean, depth: Double): Int {
        val alpha = shadeAlpha(lift, dark, highContrast) * shadeCoverage(lift, depth)
        return composite(WardReliefLight(if (dark) 0x000000 else lightShade, alpha, 0.0, 0.0, 0.0), on = fill)
    }

    /** What a light looks like where it lies at full strength on [on]. */
    fun composite(light: WardReliefLight, on: Int): Int {
        val p = WardPalette.rgb(on)
        val q = WardPalette.rgb(light.hex)
        fun mix(a: Double, b: Double): Int = WardPalette.round((a + (b - a) * light.alpha) * 255)
        return (mix(p.r, q.r) shl 16) or (mix(p.g, q.g) shl 8) or mix(p.b, q.b)
    }
}

/**
 * The error function to double precision (Swift's Foundation `erf`): a
 * Taylor series near zero, a continued fraction for erfc further out.
 */
internal fun erf(x: Double): Double {
    if (x.isNaN()) return x
    val ax = abs(x)
    val r = if (ax < 3.0) {
        var term = ax
        var sum = ax
        var n = 0
        while (abs(term) > 1e-17 * abs(sum) && n < 200) {
            n += 1
            term *= -ax * ax / n
            sum += term / (2 * n + 1)
        }
        2 / sqrt(PI) * sum
    } else if (ax > 6.0) {
        1.0
    } else {
        // erfc(x) = exp(-x^2)/sqrt(pi) * 1/(x + 1/2/(x + 1/(x + 3/2/(x + ...)))), by Lentz
        val tiny = 1e-300
        var f = ax
        var c = ax
        var d = 0.0
        var i = 1
        while (i < 500) {
            val a = i / 2.0
            d = ax + a * d
            if (abs(d) < tiny) d = tiny
            c = ax + a / c
            if (abs(c) < tiny) c = tiny
            d = 1 / d
            val delta = c * d
            f *= delta
            if (abs(delta - 1) < 1e-16) break
            i += 1
        }
        1 - exp(-ax * ax) / sqrt(PI) / f
    }
    return if (x < 0) -r else r
}

/** Continuous control relief, independent of the animation clock. */
data class WardPressSpec(
    val blur: Double,
    val outerHighlight: WardReliefLight,
    val outerShade: WardReliefLight,
    val innerShade: WardReliefLight,
    val innerHighlight: WardReliefLight,
    val edgeAlpha: Double,
) {
    companion object
}

object WardPress {
    const val sinkScale = 0.985
    const val press = 0.05
    const val release = 0.07
    const val shadePress = 0.21
    const val shadeRelease = 0.26
    const val depth = 1.0
    const val innerShadeGain = 1.25
    const val softKeep = 0.6
    const val hollowSoft = 1.0

    fun soft(lift: WardLift): Double = (lift.rawValue + 1) / 2.0

    data class Curve(val x1: Double, val y1: Double, val x2: Double, val y2: Double)
    val quickCurve = Curve(1.0 / 3, 0.5, 2.0 / 3, 5.0 / 6)

    fun quick(u: Double): Double {
        val v = min(1.0, max(0.0, u))
        return v * (1.5 - 0.5 * v)
    }

    fun glide(u: Double): Double = sin(min(1.0, max(0.0, u)) * PI / 2)

    fun releaseHold(held: Double): Double = max(0.0, press - max(0.0, held))

    /** A pressable face at depth [q] (0 raised, 1 pressed in). */
    fun spec(lift: WardLift, depth: Double, dark: Boolean, highContrast: Boolean = false, control: Boolean = true): WardPressSpec {
        val q = min(1.0, max(0.0, depth))
        val up = 1 - q
        val down = this.depth * q
        val raised = WardRelief.raised(lift, dark, highContrast, control)
        val rim = WardRelief.rim(lift, dark, highContrast)
        fun light(original: WardReliefLight, weight: Double): WardReliefLight =
            WardReliefLight(original.hex, original.alpha * weight, original.x * weight, original.y * weight,
                original.radius * (softKeep + (1 - softKeep) * weight))
        val none = WardReliefLight(0xFFFFFF, 0.0, 0.0, 0.0, 0.0)
        val deeper = raised.shade.copy(alpha = min(1.0, raised.shade.alpha * innerShadeGain))
        return WardPressSpec(
            blur = if (control) 0.0 else soft(lift) + hollowSoft * q,
            outerHighlight = if (control) light(rim.highlight, up) else none,
            outerShade = light(if (control) rim.shade else raised.shade, up),
            innerShade = light(deeper, down),
            innerHighlight = light(raised.highlight, down),
            edgeAlpha = raised.edgeAlpha,
        )
    }
}

/** ECG paper ink, independent of the rendering framework. */
data class WardPaperInk(val hex: Int, val fine: Double, val bold: Double, val edge: Double)

data class WardPaperPanel(val x: Double, val y: Double, val width: Double, val height: Double, val radius: Double)

data class WardPaperLine(val at: Double, val bold: Boolean)

object WardPaper {
    const val frame = 12.0
    /** Keep controls four points inside the paper frame line. */
    const val sideInset = frame + 4
    const val cell = 6.0
    const val boldEvery = 5
    const val line = 1.0
    const val edgeWidth = 1.5
    const val cornerShare = 53.33 / 428
    /** The rounded iPad screen, including its smaller multitasking windows. */
    const val padRadius = 18.0

    fun ink(dark: Boolean, highContrast: Boolean): WardPaperInk =
        // the ink outside any section (WardSection.outside, Cards' indigo)
        WardPaperInk(
            hex = if (dark) 0xA5B6FE else 0x5866E5,
            fine = if (highContrast) 0.0 else if (dark) 0.07 else 0.09,
            bold = if (highContrast) 0.0 else if (dark) 0.14 else 0.18,
            edge = if (dark) 0.5 else 0.55,
        )

    fun panel(width: Double, height: Double, pad: Boolean = false): WardPaperPanel? {
        if (!(width > 4 * frame && height > 4 * frame)) return null
        return WardPaperPanel(frame, frame, width - 2 * frame, height - 2 * frame,
            if (pad) padRadius else (min(width, height) - 2 * frame) * cornerShare)
    }

    /** The panel with its top moved down to [top], held to what fits. */
    fun panel(width: Double, height: Double, top: Double, pad: Boolean = false): WardPaperPanel? {
        val p = panel(width, height, pad) ?: return null
        val bottom = p.y + p.height
        val y = min(max(top, p.y), bottom - 2 * p.radius)
        if (!(y > p.y)) return p
        return p.copy(y = y, height = bottom - y)
    }

    fun lines(length: Double): List<WardPaperLine> = lines(length, from = 0.0)

    /** The frame's lines (k·cell, bold every fifth) that fall in [origin, origin + length), local to origin. */
    fun lines(length: Double, from: Double): List<WardPaperLine> {
        if (!(length > 0 && from.isFinite() && length.isFinite())) return emptyList()
        val result = mutableListOf<WardPaperLine>()
        var k = kotlin.math.ceil(from / cell).toInt()
        while (k * cell < from + length) {
            val at = k * cell - from
            if (at >= 0) result.add(WardPaperLine(at, ((k % boldEvery) + boldEvery) % boldEvery == 0))
            k += 1
        }
        return result
    }
}
