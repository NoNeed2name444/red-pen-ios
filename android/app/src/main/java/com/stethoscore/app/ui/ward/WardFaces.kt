package com.stethoscore.app.ui.ward

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.addOutline
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import com.stethoscore.app.ui.LocalWardLook
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.wardInk

// The soft UI faces the controls stand on, from WardRelief's and WardPress's
// numbers (the port of WardSurfaces.swift's WardPressFace and WardReliefFace,
// as far as the controls need them; the rest of the surfaces are batch 2):
// lights cast round a raised face, lights inside a pressed one, the face's
// fill and a control's 1-point ink edge; the 2-point chosen edge; Android's
// focus ring; and the small sink a held control makes (capPop). Lights are
// framework shadow layers on the face's outline; the inner ones fall inside
// it from a frame drawn round it and clipped away.

/**
 * Draws the controls inside as held, with no finger on them: the states
 * gallery (WardStatesGallery) shows each control's held look this way. A
 * disabled control ignores it, as it ignores a finger. Off everywhere else.
 */
val LocalWardShowsPressed = staticCompositionLocalOf { false }

/** How far to dark the look is this frame: the glide's, or the look's at rest. */
@Composable fun wardNight(): Double {
    val look = LocalWardLook.current
    val glide = LocalWardGlide.current ?: WardGlide.rest(look)
    return glide.night(look.dark)
}

private fun argb(hex: Int, alpha: Double): Int = ((alpha.coerceIn(0.0, 1.0) * 255 + 0.5).toInt() shl 24) or (hex and 0xFFFFFF)

private fun DrawScope.outlinePath(shape: Shape, size: Size = this.size): Path =
    Path().apply { addOutline(shape.createOutline(size, layoutDirection, this@outlinePath)) }

/** One light cast round [path], under the face. */
private fun DrawScope.outerLight(path: Path, light: WardReliefLight, face: Color) {
    if (!light.lit) return
    drawIntoCanvas { canvas ->
        val paint = Paint()
        val p = paint.asFrameworkPaint()
        p.isAntiAlias = true
        p.color = face.toArgb()
        p.setShadowLayer(light.radius.wardDp.toPx().coerceAtLeast(0.01f), light.x.wardDp.toPx(),
            light.y.wardDp.toPx(), argb(light.hex, light.alpha))
        canvas.drawPath(path, paint)
    }
}

/** One light inside [path]: cast by a frame round it, the frame clipped away. */
private fun DrawScope.innerLight(path: Path, light: WardReliefLight) {
    if (!light.lit) return
    val reach = (WardRelief.reach(light) * 2 + 4).wardDp.toPx()
    val frame = Path().apply {
        fillType = PathFillType.EvenOdd
        addRect(Rect(-reach, -reach, size.width + reach, size.height + reach))
        addPath(path)
    }
    clipPath(path) {
        drawIntoCanvas { canvas ->
            val paint = Paint()
            val p = paint.asFrameworkPaint()
            p.isAntiAlias = true
            p.color = argb(light.hex, 1.0)
            p.setShadowLayer(light.radius.wardDp.toPx().coerceAtLeast(0.01f), light.x.wardDp.toPx(),
                light.y.wardDp.toPx(), argb(light.hex, light.alpha))
            canvas.drawPath(frame, paint)
        }
    }
}

/** A line [width] dp wide just inside [path]. */
private fun DrawScope.innerStroke(path: Path, color: Color, width: Double) {
    if (width <= 0) return
    clipPath(path) { drawPath(path, color, style = Stroke(width = (2 * width).wardDp.toPx())) }
}

/**
 * A pressable face (WardPressFace): raised by its lights at [lift] at depth
 * 0, pressed into the base with the lights inside at depth 1, every depth
 * between as the press glides. A control's face (`control`) stands on its
 * small rim and carries the 1-point ink edge; [flat] drops every light.
 */
fun Modifier.wardPressFace(
    shape: Shape,
    lift: WardLift,
    depth: () -> Float,
    fill: Color,
    night: Double,
    ink: Color,
    control: Boolean = true,
    flat: Boolean = false,
    edge: Color? = null,
): Modifier = drawBehind {
    val path = outlinePath(shape)
    val spec = WardPress.spec(lift, depth().toDouble(), night, highContrast = false, control = control)
    if (!flat) {
        outerLight(path, spec.outerShade, fill)
        outerLight(path, spec.outerHighlight, fill)
    }
    drawPath(path, fill)
    if (!flat) {
        innerLight(path, spec.innerShade)
        innerLight(path, spec.innerHighlight)
    }
    if (control) innerStroke(path, edge ?: ink.copy(alpha = spec.edgeAlpha.toFloat()), 1.0)
}

/**
 * A still face (WardReliefFace): raised off the base, or [inset] into it
 * (a well, a track, a groove); a control's carries the ink edge and, raised,
 * stands on its rim as a button does.
 */
fun Modifier.wardReliefFace(
    shape: Shape,
    lift: WardLift,
    fill: Color,
    night: Double,
    ink: Color,
    inset: Boolean = false,
    control: Boolean = false,
): Modifier = drawBehind {
    val path = outlinePath(shape)
    val rim = control && !inset
    val spec = when {
        inset -> WardRelief.inset(lift, night, control = control)
        rim -> WardRelief.rim(lift, night)
        else -> WardRelief.raised(lift, night, control = control)
    }
    if (!spec.inner) {
        outerLight(path, spec.shade, fill)
        outerLight(path, spec.highlight, fill)
    }
    drawPath(path, fill)
    if (spec.inner) {
        innerLight(path, spec.shade)
        innerLight(path, spec.highlight)
    }
    if (control) innerStroke(path, ink.copy(alpha = spec.edgeAlpha.toFloat()), 1.0)
}

/** The composable forms, reading the look on show. */
@Composable fun Modifier.wardPressFace(
    shape: Shape, lift: WardLift, depth: State<Float>, fill: Color = wardColor(WardToken.surface),
    control: Boolean = true, flat: Boolean = false, edge: Color? = null,
): Modifier = wardPressFace(shape, lift, { depth.value }, fill, wardNight(), wardInk(), control, flat, edge)

@Composable fun Modifier.wardRelief(
    shape: Shape, lift: WardLift = WardLift.mid, fill: Color = wardColor(WardToken.surface),
    inset: Boolean = false, control: Boolean = false,
): Modifier = wardReliefFace(shape, lift, fill, wardNight(), wardInk(), inset, control)

/** Pressed into the base: a well with a control's edge (wardInset). */
@Composable fun Modifier.wardInset(shape: Shape, lift: WardLift = WardLift.low, control: Boolean = false): Modifier =
    wardRelief(shape, lift, wardColor(WardToken.well), inset = true, control = control)

/**
 * A chosen control's mark: a solid edge in [color] (the section's accent)
 * round [shape], WardControlStates.chosenEdgeWidth wide, at full strength
 * over the face's own edge. It comes and goes at once, never fading in.
 */
fun Modifier.wardChosenEdge(shape: Shape, chosen: Boolean, color: Color): Modifier =
    if (!chosen) this else drawWithContent {
        drawContent()
        innerStroke(outlinePath(shape), color, WardControlStates.chosenEdgeWidth)
    }

@Composable fun Modifier.wardChosenEdge(shape: Shape, chosen: Boolean): Modifier =
    wardChosenEdge(shape, chosen, wardColor(WardControlStates.focusInk))

/**
 * Focused (Android's keyboard, D-pad or switch access): a ring in the
 * section's accent, focusRingGap outside the face and focusRingWidth wide,
 * over whatever state it is in.
 */
fun Modifier.wardFocusRing(shape: Shape, focused: Boolean, color: Color): Modifier =
    if (!focused) this else drawWithContent {
        drawContent()
        val out = (WardControlStates.focusRingGap + WardControlStates.focusRingWidth).wardDp.toPx()
        translate(-out, -out) {
            val ring = outlinePath(shape, Size(size.width + 2 * out, size.height + 2 * out))
            innerStroke(ring, color, WardControlStates.focusRingWidth)
        }
    }

/** The press's quick curve (WardPress.quickCurve) and the shade's glide (WardPress.glide). */
val WardQuickEasing: Easing = WardPress.quickCurve.let { CubicBezierEasing(it.x1.toFloat(), it.y1.toFloat(), it.x2.toFloat(), it.y2.toFloat()) }
val WardShadeEasing: Easing = Easing { WardPress.glide(it.toDouble()).toFloat() }

/** A face's depth, gliding in over WardPress.shadePress and out over shadeRelease. */
@Composable fun wardDepth(down: Boolean): State<Float> = animateFloatAsState(
    targetValue = if (down) 1f else 0f,
    animationSpec = tween(((if (down) WardPress.shadePress else WardPress.shadeRelease) * 1000).toInt(), easing = WardShadeEasing),
    label = "wardDepth",
)

/** Held, the whole control sinks a little (WardPress.sinkScale), quickly, rather than dimming. */
fun Modifier.capPop(held: Boolean): Modifier = composed {
    val scale by animateFloatAsState(
        targetValue = if (held) WardPress.sinkScale.toFloat() else 1f,
        animationSpec = tween(((if (held) WardPress.press else WardPress.release) * 1000).toInt(), easing = WardQuickEasing),
        label = "capPop",
    )
    graphicsLayer { scaleX = scale; scaleY = scale }
}
