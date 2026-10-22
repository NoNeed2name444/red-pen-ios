package com.stethoscore.app.ui.ward

import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// The Compose side of WardTokens.swift: WardType's faces as TextStyles in sp
// (so Android's font size setting scales them, as Dynamic Type does on iOS),
// Material's Typography from them, the scale's steps as dp, the small caps,
// and the animated glide (WardLookDriver's frame loop) every Ward colour is
// drawn from while the section's hue shifts.

/** A step of the scale as dp. */
val Double.wardDp: Dp get() = this.toFloat().dp

/** This face as a TextStyle: its size and line in sp, its weight, mono for observations. */
fun WardTypeSpec.textStyle(): TextStyle = TextStyle(
    fontSize = size.sp,
    lineHeight = line.sp,
    fontWeight = FontWeight(weight.value),
    fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default,
    lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
)

/** A text style at a weight, as a TextStyle. */
fun WardTextStyle.textStyle(weight: WardWeight = WardWeight.regular, mono: Boolean = false): TextStyle =
    WardTypeSpec(this, weight, mono).textStyle()

/**
 * Material's type roles from iOS's text styles, so a screen that reads
 * MaterialTheme.typography gets the Ward scale: display is largeTitle,
 * headline the titles, title the headline, body the body, label the small
 * words of a control.
 */
fun wardTypography(): Typography = Typography(
    displayLarge = WardType.display.textStyle(),
    displayMedium = WardType.display.textStyle(),
    displaySmall = WardTextStyle.title.textStyle(WardWeight.bold),
    headlineLarge = WardTextStyle.title.textStyle(WardWeight.bold),
    headlineMedium = WardTextStyle.title2.textStyle(WardWeight.semibold),
    headlineSmall = WardType.title.textStyle(),
    titleLarge = WardType.title.textStyle(),
    titleMedium = WardType.headline.textStyle(),
    titleSmall = WardTextStyle.subheadline.textStyle(WardWeight.semibold),
    bodyLarge = WardType.body.textStyle(),
    bodyMedium = WardTextStyle.subheadline.textStyle(),
    bodySmall = WardTextStyle.footnote.textStyle(),
    labelLarge = WardType.buttonSmall.textStyle(),
    labelMedium = WardType.smallCaps.textStyle(),
    labelSmall = WardTextStyle.caption2.textStyle(WardWeight.semibold),
)

/** Whether the reader's font scale is at iOS's accessibility sizes. */
@Composable fun wardAccessibilitySize(): Boolean = WardType.isAccessibilitySize(LocalDensity.current.fontScale.toDouble())

/** The small caps' style: caption semibold, letters spaced at the standard sizes only (WardSmallCaps). */
@Composable fun wardSmallCapsStyle(): TextStyle {
    val tracking = WardSmallCaps.tracking(LocalDensity.current.fontScale.toDouble())
    return WardSmallCaps.font.textStyle().copy(letterSpacing = tracking.sp)
}

/**
 * The shift this frame, provided by [rememberWardGlide] at the theme's root;
 * null where nothing drives one (a preview), and the look at rest is drawn.
 */
val LocalWardGlide = staticCompositionLocalOf<WardGlide?> { null }

/**
 * The glide toward [look], one value for the whole tree (WardLookDriver):
 * light and dark arrive in one step; a new section's hue is stepped every
 * frame for WardGlide.duration, then left at rest. With animations off
 * (animator duration scale 0) a new look arrives at once.
 */
@Composable fun rememberWardGlide(look: WardLook): WardGlide {
    val context = LocalContext.current
    var glide by remember { mutableStateOf(WardGlide.rest(look)) }
    LaunchedEffect(look) {
        val scale = try {
            android.provider.Settings.Global.getFloat(context.contentResolver,
                android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
        } catch (_: Throwable) { 1f }
        val next = WardLookDriver.go(look, glide, reduceMotion = scale == 0f)
        glide = next
        if (next.settled) return@LaunchedEffect
        val startProgress = next.progress
        val start = withFrameNanos { it }
        while (!glide.settled) {
            val now = withFrameNanos { it }
            glide = WardLookDriver.step(next, startProgress, (now - start) / 1e9 / scale)
        }
    }
    return glide
}
