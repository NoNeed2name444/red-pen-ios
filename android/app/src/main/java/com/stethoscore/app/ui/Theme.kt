package com.stethoscore.app.ui

import android.app.Activity
import android.content.ContextWrapper
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.ui.ward.*

// Every colour comes from the Ward core (ui/ward: WardPalette, WardSection,
// WardLook), the port of the iOS Ward look: the palette's tokens for the
// grounds, text and meanings, and the section's ink, accent and fill for the
// accents. Material 3 is fed a scheme built from them, so a screen that reads
// MaterialTheme.colorScheme gets the Ward colours; wardColor(token) and
// wardInk() give the rest.
//
// How the tokens land in Material: the tint (primary) is what iOS's
// AccentColor is, the section's fill by day and its accent at night (so text
// buttons and icons read 4.5:1 on every tier); primaryContainer is the fill
// under white words. outline is the section's ink at a control's edge
// strength, as it lands on the base (WardRelief.edgeColor).
val LocalWardDark = staticCompositionLocalOf { false }
val LocalWardLook = staticCompositionLocalOf { WardLook(dark = false, section = WardSection.outside) }

/** A 0xRRGGBB colour as an opaque Compose colour. */
fun wardRgb(hex: Int): Color = Color(0xFF000000.toInt() or hex)

/** The Material scheme for [look]: every slot from the Ward palette and the section. */
fun wardColorScheme(look: WardLook): ColorScheme {
    val dark = look.dark
    val glide = WardGlide.rest(look)
    fun c(token: WardToken) = wardRgb(glide.hex(token, dark))
    val tint = wardRgb(if (dark) look.section.accent(true) else look.section.fill(false))
    val onTint = if (dark) c(WardToken.background) else c(WardToken.onPrimary)
    val edge = wardRgb(WardRelief.edgeColor(look.section, dark))
    val base = if (dark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = tint, onPrimary = onTint,
        primaryContainer = c(WardToken.primary), onPrimaryContainer = c(WardToken.onPrimary),
        inversePrimary = c(WardToken.primaryInk),
        secondary = c(WardToken.ecg), onSecondary = c(WardToken.onPrimary),
        tertiary = c(WardToken.success), onTertiary = c(WardToken.onPrimary),
        background = c(WardToken.background), onBackground = c(WardToken.ink),
        surface = c(WardToken.surface), onSurface = c(WardToken.ink),
        surfaceVariant = c(WardToken.well), onSurfaceVariant = c(WardToken.inkSecondary),
        surfaceTint = Color.Transparent,
        surfaceContainerLowest = c(WardToken.well), surfaceContainerLow = c(WardToken.background),
        surfaceContainer = c(WardToken.surface), surfaceContainerHigh = c(WardToken.raised),
        surfaceContainerHighest = c(WardToken.raised),
        surfaceBright = c(WardToken.raised), surfaceDim = c(WardToken.well),
        error = c(WardToken.danger), onError = c(WardToken.onPrimary),
        outline = edge, outlineVariant = c(WardToken.hairline),
    )
}

/** A Ward palette colour for the look on show (the section's, for primary and primaryInk). */
@Composable fun wardColor(token: WardToken, held: Boolean = false): Color {
    val look = LocalWardLook.current
    val dark = if (held) true else look.dark
    // this frame of the section's glide (rememberWardGlide), or the look at rest
    val glide = LocalWardGlide.current ?: WardGlide.rest(look)
    return wardRgb(glide.hex(token, dark, held))
}

/** The section's ink on show: the grid's lines and the controls' edges. */
@Composable fun wardInk(): Color {
    val look = LocalWardLook.current
    val glide = LocalWardGlide.current ?: WardGlide.rest(look)
    return wardRgb(glide.ink(look.dark))
}

@Composable fun StethoscoreTheme(dark:Boolean=false, section:WardSection=WardSection.outside, content:@Composable ()->Unit) {
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val activity = generateSequence(view.context) { (it as? ContextWrapper)?.baseContext }
                .filterIsInstance<Activity>().firstOrNull()
            activity?.let {
                WindowCompat.getInsetsController(it.window, view).apply {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
            }
        }
    }
    val look = WardLook(dark = dark, section = section)
    // the one animated value: light and dark in one step, a section's hue glides (WardLookDriver)
    val glide = rememberWardGlide(look)
    SideEffect { WardLookNow.shared.set(glide) }
    // whether animations are off (Remove animations), watched once for every surface that moves (wardReduceMotion)
    val reduceMotion = rememberWardReduceMotion()
    CompositionLocalProvider(LocalWardDark provides dark, LocalWardLook provides look, LocalWardGlide provides glide,
        LocalWardReduceMotion provides reduceMotion) {
        MaterialTheme(colorScheme=wardColorScheme(look), typography=wardTypography()) {
            // a plain clickable sinks and shades as a Ward face does, never a ripple (iOS PressableRowStyle)
            CompositionLocalProvider(LocalIndication provides WardPressIndication, content=content)
        }
    }
}

/** A card (iOS wardCard): raised mid off the base by WardRelief's two lights, iOS's card radius and gutter (WardSurfaces). */
@Composable fun WardCard(modifier:Modifier=Modifier, content:@Composable ColumnScope.()->Unit) = WardCardFace(modifier, content=content)
/** A Ward button (ui/ward/WardControls): a soft capsule raised off the base, its kind in the label's colour. */
@Composable fun WardButton(text:String,onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,kind:WardButtonKind=WardButtonKind.secondary) {
    WardTextButton(text,onClick,modifier,kind=kind,enabled=enabled)
}
/** A section's small-caps label (WardSmallCaps). */
@Composable fun SectionLabel(text:String) { WardSmallCapsText(text) }
@Composable fun ScreenHeader(title:String,subtitle:String,onBack:()->Unit) {
    Row(Modifier.fillMaxWidth().padding(bottom=8.dp),verticalAlignment=androidx.compose.ui.Alignment.CenterVertically) {
        IconButton(onClick=onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack,contentDescription="Back") }
        Column(Modifier.weight(1f)) { Text(title,fontSize=25.sp,fontWeight=FontWeight.Bold); if(subtitle.isNotBlank()) Text(subtitle,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}
/** The ECG paper (WardPaper): a line every cell, bold every fifth, in the section's ink at the paper's strengths. */
@Composable fun EcgGrid(modifier:Modifier=Modifier) {
    val look=LocalWardLook.current
    val ink=WardPaper.ink(WardGlide.rest(look), look.dark, highContrast=false)
    val color=wardRgb(ink.hex)
    Canvas(modifier) {
        val step=WardPaper.cell.toFloat().dp.toPx()
        val w=WardPaper.line.toFloat().dp.toPx()
        WardPaper.lines(size.width/step*WardPaper.cell).forEach { l -> val x=(l.at/WardPaper.cell).toFloat()*step; drawLine(color.copy(alpha=(if(l.bold) ink.bold else ink.fine).toFloat()),Offset(x,0f),Offset(x,size.height),w) }
        WardPaper.lines(size.height/step*WardPaper.cell).forEach { l -> val y=(l.at/WardPaper.cell).toFloat()*step; drawLine(color.copy(alpha=(if(l.bold) ink.bold else ink.fine).toFloat()),Offset(0f,y),Offset(size.width,y),w) }
    }
}
@Composable fun PulseLine(modifier:Modifier=Modifier) {
    val color=wardColor(WardToken.ecg)
    Canvas(modifier) {
        val pts=listOf(0f to .55f,.24f to .55f,.31f to .4f,.4f to .65f,.5f to .05f,.61f to .92f,.69f to .45f,.8f to .55f,1f to .55f)
        pts.zipWithNext().forEach { (a,b)-> drawLine(color,Offset(a.first*size.width,a.second*size.height),Offset(b.first*size.width,b.second*size.height),3.dp.toPx(),cap=androidx.compose.ui.graphics.StrokeCap.Round) }
    }
}
