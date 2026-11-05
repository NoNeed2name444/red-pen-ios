package com.stethoscore.app.widget

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.color.ColorProvider
import androidx.glance.text.FontWeight
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.ward.WardPalette
import com.stethoscore.app.ui.ward.WardScale
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardTypeSpec
import com.stethoscore.app.ui.ward.WardWeight

/**
 * The widgets' look, as iOS's GlanceStyle: the app's flat ground and ink by
 * day and at night, and Vital Coral for the glyphs and the Review capsule's
 * wash, every colour taken from the Ward palette, never repeated here.
 * Sizes are the Ward scale's; the 44 sp number is iOS's widget number.
 */
object WidgetStyle {
    /** The least tap target: 48 dp, Android's (WardControlSize.target; iOS keeps 44 pt). */
    const val target = WardControlSize.target
    /** The medium Due widget's top and bottom margin, so two rows and the button fit (iOS mediumVerticalMargin). */
    const val mediumVerticalMargin = WardScale.s
    /** The 2x2 faces' top and bottom margin, so the glyph, the number and its caption fit a 110 dp widget (NumberStack). */
    const val smallVerticalMargin = WardScale.m
    /** Between a deck's name and its count (iOS's Spacer(minLength: 4)). */
    const val gap = WardScale.xs
    /** The widget's side margins and the gap between its columns. */
    const val margin = WardScale.l
    /** The big count, as iOS's widgets draw it (44 pt, bold, no theme face of that size). */
    const val numberSize = 44.0
    /** The glyphs' size: Material's 24 dp. */
    const val glyph = WardScale.xl
    /**
     * The Review capsule's coral wash, as iOS's pen.opacity(0.15): the capsule
     * drawable is tinted [pen] and drawn at this alpha. Glance tints with
     * SRC_ATOP, which keeps the drawable's own alpha, so a tint at 0.15 on an
     * opaque capsule would come out opaque (pale pink at night, under light ink).
     */
    const val reviewWash = 0.15f

    val ground: ColorProvider get() = pair(WardToken.background)
    val ink: ColorProvider get() = pair(WardToken.ink)
    val inkSecondary: ColorProvider get() = pair(WardToken.inkSecondary)
    /** Vital Coral, iOS's GlanceStyle.pen: the Ward palette's ECG Red, one value in both modes. */
    val pen: ColorProvider get() = pair(WardToken.ecg)

    val number: TextStyle get() = TextStyle(color = ink, fontSize = numberSize.sp, fontWeight = FontWeight.Bold)
    val caption: TextStyle get() = style(WardType.caption, inkSecondary)
    /**
     * The one-line sizes' text, on one line: footnote, semibold, as the app
     * writes a short emphatic line (WardPocketScreen's disclaimer). Headline,
     * iOS's rectangular widget's, took two lines in a 2x1 that can be 40 dp tall.
     */
    val lineFace = WardTypeSpec(WardTextStyle.footnote, WardWeight.semibold)
    val line: TextStyle get() = style(lineFace, ink)
    val deck: TextStyle get() = style(WardType.segment, ink)
    /** The Review label: Chart Ink on the coral wash, 10.5:1 by day and 12.5:1 at night (coral itself was 2.1:1 by day). */
    val review: TextStyle get() = style(WardType.buttonSmall, ink)

    fun dp(value: Double): Dp = value.dp

    private fun style(spec: WardTypeSpec, colour: ColorProvider): TextStyle =
        TextStyle(color = colour, fontSize = spec.size.sp as TextUnit, fontWeight = weight(spec.weight))

    private fun weight(w: WardWeight): FontWeight = when (w) {
        WardWeight.regular -> FontWeight.Normal
        WardWeight.medium -> FontWeight.Medium
        WardWeight.semibold, WardWeight.bold -> FontWeight.Bold
    }

    private fun pair(token: WardToken, alpha: Float = 1f): ColorProvider =
        ColorProvider(day = color(WardPalette.hex(token, dark = false), alpha), night = color(WardPalette.hex(token, dark = true), alpha))

    private fun color(hex: Int, alpha: Float): Color = Color(0xFF000000.toInt() or hex).copy(alpha = alpha)
}
