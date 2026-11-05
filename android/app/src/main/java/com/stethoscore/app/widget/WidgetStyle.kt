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
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardTypeSpec
import com.stethoscore.app.ui.ward.WardWeight

/**
 * The widgets' look, as iOS's GlanceStyle: the app's flat ground and ink by
 * day and at night, and Vital Coral for the glyph-less accent and the Review
 * button, every colour taken from the Ward palette, never repeated here.
 * Sizes are the Ward scale's; the 44 sp number is iOS's widget number.
 */
object WidgetStyle {
    /** The least tap target: 48 dp, Android's (WardControlSize.target; iOS keeps 44 pt). */
    const val target = WardControlSize.target
    /** The medium Due widget's top and bottom margin, so two rows and the button fit (iOS mediumVerticalMargin). */
    const val mediumVerticalMargin = WardScale.s
    /** Between a deck's name and its count (iOS's Spacer(minLength: 4)). */
    const val gap = WardScale.xs
    /** The widget's side margins and the gap between its columns. */
    const val margin = WardScale.l
    /** The big count, as iOS's widgets draw it (44 pt, bold, no theme face of that size). */
    const val numberSize = 44.0
    /** The Review capsule's coral wash, as iOS's pen.opacity(0.15). */
    const val reviewWash = 0.15f

    val ground: ColorProvider get() = pair(WardToken.background)
    val ink: ColorProvider get() = pair(WardToken.ink)
    val inkSecondary: ColorProvider get() = pair(WardToken.inkSecondary)
    /** Vital Coral, iOS's GlanceStyle.pen: the Ward palette's ECG Red, one value in both modes. */
    val pen: ColorProvider get() = pair(WardToken.ecg)
    val penWash: ColorProvider get() = pair(WardToken.ecg, alpha = reviewWash)

    val number: TextStyle get() = TextStyle(color = ink, fontSize = numberSize.sp, fontWeight = FontWeight.Bold)
    val caption: TextStyle get() = style(WardType.caption, inkSecondary)
    /** The one-line sizes' sentence: headline, as iOS's rectangular widget. */
    val line: TextStyle get() = style(WardType.headline, ink)
    val deck: TextStyle get() = style(WardType.segment, ink)
    val review: TextStyle get() = style(WardType.buttonSmall, pen)

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
