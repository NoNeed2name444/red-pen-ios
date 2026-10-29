package com.stethoscore.app.ui.ward

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.stethoscore.app.R
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale
import kotlin.math.roundToInt

// The Compose side of WardTokens.swift: WardType's faces as TextStyles in sp
// (so Android's font size setting scales them, as Dynamic Type does on iOS),
// in the app's own font (WardFont),
// Material's Typography from them, the scale's steps as dp, the small caps,
// the animated glide (WardLookDriver's frame loop) every Ward colour is
// drawn from while the section's hue shifts, and the motion: WardMotion's
// specs and whether animations are off (wardReduceMotion), which every
// animated surface asks, as an iOS view asks accessibilityReduceMotion.

/** A step of the scale as dp. */
val Double.wardDp: Dp get() = this.toFloat().dp

/**
 * The app's type (iOS WardType): Nunito, bundled in res/font (SIL OFL 1.1,
 * owner D5; the licences in assets/licenses), and Baloo Bhaijaan 2 when
 * the app speaks Arabic. Both are variable fonts, so each weight is the
 * same file at its own wght; a weight between them is drawn from the
 * nearest. Observations stay in the system mono.
 *
 * Arabic is a locale switch, as on iOS, not a glyph cascade: with the
 * app's language Arabic every face is Baloo Bhaijaan 2, which carries
 * Latin too, so a mixed line keeps one face. In English, Arabic letters
 * in a student's own text fall back to the system's Arabic face, since
 * Nunito has none.
 */
object WardFont {
    /** The weights each family is given, on Android's 100 to 900 scale. */
    val latinWeights = listOf(300, 400, 500, 600, 700, 800, 900)
    /** Baloo Bhaijaan 2's axis runs from 400 to 800 only. */
    val arabicWeights = listOf(400, 500, 600, 700, 800)

    val latin: FontFamily = family(R.font.nunito, latinWeights)
    val arabic: FontFamily = family(R.font.baloo_bhaijaan_2, arabicWeights)

    // a variable font's weight axis per Font is still marked experimental
    @OptIn(ExperimentalTextApi::class)
    private fun family(res: Int, weights: List<Int>): FontFamily = FontFamily(weights.map { w ->
        Font(res, FontWeight(w), FontStyle.Normal, variationSettings = FontVariation.Settings(FontVariation.weight(w)))
    })

    /** The family for a language ("en", "ar"): Baloo Bhaijaan 2 for Arabic, Nunito for every other. */
    fun forLanguage(language: String): FontFamily = if (language.startsWith("ar")) arabic else latin

    /** The family for the app's language now (Android recreates the screen when it changes). */
    val current: FontFamily get() = forLanguage(Locale.getDefault().language)
}

/** This face as a TextStyle: its size and line in sp, its weight, mono for observations. */
fun WardTypeSpec.textStyle(): TextStyle = TextStyle(
    fontSize = size.sp,
    lineHeight = line.sp,
    fontWeight = FontWeight(weight.value),
    fontFamily = if (mono) FontFamily.Monospace else WardFont.current,
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
        val scale = wardAnimatorScale(context)
        val next = WardLookDriver.go(look, glide, reduceMotion = WardMotion.reduce(scale))
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

// MARK: the motion (WardMotion)

/** The animator duration scale: 1 by default, 0 with Remove animations (Accessibility) or the developer scales off. */
fun wardAnimatorScale(context: Context): Float = try {
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
} catch (_: Throwable) { 1f }

/**
 * Whether animations are off, provided at the theme's root
 * (StethoscoreTheme, from [rememberWardReduceMotion]); null where nothing
 * provides it (a preview), and [wardReduceMotion] reads the setting itself.
 */
val LocalWardReduceMotion = staticCompositionLocalOf<Boolean?> { null }

/** Whether animations are off, read now and again whenever the setting changes. */
@Composable fun rememberWardReduceMotion(): Boolean {
    val context = LocalContext.current
    var reduce by remember(context) { mutableStateOf(WardMotion.reduce(wardAnimatorScale(context))) }
    DisposableEffect(context) {
        val watcher = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { reduce = WardMotion.reduce(wardAnimatorScale(context)) }
        }
        val watching = runCatching {
            context.contentResolver.registerContentObserver(
                Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false, watcher)
        }.isSuccess
        onDispose { if (watching) context.contentResolver.unregisterContentObserver(watcher) }
    }
    return reduce
}

/**
 * Whether animations are off here, as an iOS view reads
 * accessibilityReduceMotion: every animated surface asks, and with it on a
 * change is simply there (no travel, no sink, no fill sweeping in).
 */
@Composable fun wardReduceMotion(): Boolean {
    val provided = LocalWardReduceMotion.current
    val context = LocalContext.current
    return provided ?: WardMotion.reduce(wardAnimatorScale(context))
}

/** A Ward curve as a Compose easing. */
fun WardPress.Curve.easing(): Easing = CubicBezierEasing(x1.toFloat(), y1.toFloat(), x2.toFloat(), y2.toFloat())

/** iOS's .easeOut and .easeInOut (WardMotion). */
val WardEaseOut: Easing = WardMotion.easeOut.easing()
val WardEaseInOut: Easing = WardMotion.easeInOut.easing()

/** [seconds] as a tween's whole milliseconds. */
fun wardMillis(seconds: Double): Int = (seconds * 1000).roundToInt()

/** A change over [seconds] on iOS's ease-out; with animations off ([reduce]) it is simply there. */
fun <T> wardEaseOut(seconds: Double, reduce: Boolean): AnimationSpec<T> =
    if (reduce) snap() else tween(wardMillis(seconds), easing = WardEaseOut)

/**
 * A spring that takes about [seconds] and never passes its mark (iOS's
 * .snappy and .smooth of that duration, critically damped); with
 * animations off ([reduce]) it is simply there.
 */
fun <T> wardSpring(seconds: Double, reduce: Boolean): AnimationSpec<T> =
    if (reduce) snap() else spring(dampingRatio = WardMotion.damping.toFloat(), stiffness = WardMotion.stiffness(seconds).toFloat())
