package com.stethoscore.app.ui.ward

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.interaction.FocusInteraction
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.addOutline
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.node.CompositionLocalConsumerModifierNode
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.currentValueOf
import androidx.compose.ui.platform.LocalContext
import com.stethoscore.app.ui.LocalWardLook
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.wardInk
import com.stethoscore.app.ui.wardRgb
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// The soft UI faces the controls stand on, from WardRelief's and WardPress's
// numbers (the port of WardSurfaces.swift's WardPressFace and WardReliefFace,
// as far as the controls need them; the rest of the surfaces are batch 2):
// lights cast round a raised face, lights inside a pressed one, the face's
// fill and a control's 1-point ink edge; the 2-point chosen edge; Android's
// focus ring; the small sink a held control makes (capPop); and the press a
// plain clickable shows in place of a ripple (WardPressIndication). Lights
// are framework shadow layers on the face's outline; the inner ones fall
// inside it from a frame drawn round it and clipped away.

/**
 * Draws the controls inside as held, with no finger on them: the states
 * gallery (WardStatesGallery) shows each control's held look this way. A
 * disabled control ignores it, as it ignores a finger. Off everywhere else.
 */
val LocalWardShowsPressed = staticCompositionLocalOf { false }

/**
 * Faces drawn without their lights (iOS WardUnlitKey): no shade cast round
 * them, only the face, its edge and, held or chosen, the hollow inside it;
 * a control keeps its small rim, the one soft light the app allows. For
 * what floats over a page (the home's New set and dock, the Ideas bar, the
 * folded study deck: the owner, 9 Oct, "remove the glow around the deck and
 * floating buttons"). Off everywhere else.
 */
val LocalWardUnlit = staticCompositionLocalOf { false }

/** The Ward faces inside [content] are drawn without their lights (iOS wardUnlit). */
@Composable fun WardUnlit(unlit: Boolean = true, content: @Composable () -> Unit) =
    CompositionLocalProvider(LocalWardUnlit provides unlit, content = content)

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
 * small rim and carries the 1-point ink edge; [flat] drops every light;
 * [unlit] (LocalWardUnlit) drops the lights round a face that is not a
 * control's, keeping its hollow.
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
    unlit: Boolean = false,
): Modifier = drawBehind {
    val path = outlinePath(shape)
    val spec = WardPress.spec(lift, depth().toDouble(), night, highContrast = false, control = control)
    // a button keeps its small rim even where the page is unlit (WardRelief.rim)
    if ((control || !unlit) && !flat) {
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
 * stands on its rim as a button does. [unlit] (LocalWardUnlit) drops the
 * lights round a raised face that is not on its rim; a well keeps its own.
 */
fun Modifier.wardReliefFace(
    shape: Shape,
    lift: WardLift,
    fill: Color,
    night: Double,
    ink: Color,
    inset: Boolean = false,
    control: Boolean = false,
    unlit: Boolean = false,
): Modifier = drawBehind {
    val path = outlinePath(shape)
    val rim = control && !inset
    val spec = when {
        inset -> WardRelief.inset(lift, night, control = control)
        rim -> WardRelief.rim(lift, night)
        else -> WardRelief.raised(lift, night, control = control)
    }
    if (!spec.inner && !(unlit && !rim)) {
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
): Modifier = wardPressFace(shape, lift, { depth.value }, fill, wardNight(), wardInk(), control, flat, edge, LocalWardUnlit.current)

@Composable fun Modifier.wardRelief(
    shape: Shape, lift: WardLift = WardLift.mid, fill: Color = wardColor(WardToken.surface),
    inset: Boolean = false, control: Boolean = false,
): Modifier = wardReliefFace(shape, lift, fill, wardNight(), wardInk(), inset, control, LocalWardUnlit.current)

/** Pressed into the base: a well in the well's fill (the page colour), with a control's edge (wardInset). */
@Composable fun Modifier.wardInset(shape: Shape, lift: WardLift = WardLift.low, control: Boolean = false): Modifier =
    wardRelief(shape, lift, wardColor(WardControlStates.wellFill), inset = true, control = control)

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

/**
 * A face's depth, gliding in over WardPress.shadePress and out over
 * shadeRelease; with animations off it is simply down or up (iOS:
 * reduceMotion ? nil : .wardShade(down:)).
 */
@Composable fun wardDepth(down: Boolean): State<Float> {
    val reduce = wardReduceMotion()
    return animateFloatAsState(
        targetValue = if (down) 1f else 0f,
        animationSpec = if (reduce) snap() else tween(wardMillis(if (down) WardPress.shadePress else WardPress.shadeRelease), easing = WardShadeEasing),
        label = "wardDepth",
    )
}

/**
 * Held, the whole control sinks a little (WardPress.sinkScale), quickly,
 * rather than dimming; with animations off it does not sink at all (iOS
 * CapPop: pressed && !reduceMotion ? sinkScale : 1).
 */
fun Modifier.capPop(held: Boolean): Modifier = composed {
    val reduce = wardReduceMotion()
    val scale by animateFloatAsState(
        targetValue = if (held && !reduce) WardPress.sinkScale.toFloat() else 1f,
        animationSpec = if (reduce) snap() else tween(wardMillis(if (held) WardPress.press else WardPress.release), easing = WardQuickEasing),
        label = "capPop",
    )
    graphicsLayer { scaleX = scale; scaleY = scale }
}

/**
 * The press of a plain clickable (iOS PressableRowStyle, Shared/Theme.swift):
 * held, what it draws sinks to WardPress.sinkScale and shades a little
 * (SwiftUI's brightness -0.04), both on the press's quick curve, and a quick
 * tap still shows the whole sink before it lets go (WardPress.releaseHold,
 * as iOS's capPop holds it). The theme gives it as LocalIndication, so a
 * plain clickable never draws Material's ink; focused from a keyboard, it
 * takes the Ward focus ring round its bounds. A Ward control draws its own
 * press face and passes indication = null.
 */
object WardPressIndication : IndicationNodeFactory {
    /** SwiftUI's brightness(-0.04) on a held row (iOS PressableRowFace), as a share of full white. */
    const val shade = 0.04

    /** The scale at [held] of the way down (0 at rest, 1 held). */
    fun scale(held: Float): Float = 1f - (1f - WardPress.sinkScale.toFloat()) * held

    /** How much darker, as a share of full white, at [held] of the way down. */
    fun shade(held: Float): Float = shade.toFloat() * held

    override fun create(interactionSource: InteractionSource): DelegatableNode = WardPressNode(interactionSource)
    override fun equals(other: Any?): Boolean = other === this
    override fun hashCode(): Int = javaClass.hashCode()
}

private class WardPressNode(private val source: InteractionSource) :
    Modifier.Node(), DrawModifierNode, CompositionLocalConsumerModifierNode {
    /** 0 at rest, 1 held: the sink and the shade together. */
    private val held = Animatable(0f)
    private var focused by mutableStateOf(false)
    private var pressedAt = 0L
    private var letGo: Job? = null

    override fun onAttach() {
        if (held.value != 0f) coroutineScope.launch { held.snapTo(0f) }
        coroutineScope.launch(start = CoroutineStart.UNDISPATCHED) {
            val presses = mutableListOf<PressInteraction.Press>()
            val focuses = mutableListOf<FocusInteraction.Focus>()
            source.interactions.collect { interaction ->
                val was = presses.isNotEmpty()
                when (interaction) {
                    is PressInteraction.Press -> presses += interaction
                    is PressInteraction.Release -> presses -= interaction.press
                    is PressInteraction.Cancel -> presses -= interaction.press
                    is FocusInteraction.Focus -> focuses += interaction
                    is FocusInteraction.Unfocus -> focuses -= interaction.focus
                }
                focused = focuses.isNotEmpty()
                val down = presses.isNotEmpty()
                if (down && !was) press() else if (!down && was) release()
            }
        }
    }

    private fun press() {
        letGo?.cancel()
        pressedAt = System.nanoTime()
        val reduce = reduce()
        coroutineScope.launch { held.animateTo(1f, if (reduce) snap() else tween(wardMillis(WardPress.press), easing = WardQuickEasing)) }
    }

    /** Remove animations, from the theme's flag (LocalWardReduceMotion) or, with none given, the system's scale (wardReduceMotion). */
    private fun reduce(): Boolean =
        currentValueOf(LocalWardReduceMotion) ?: WardMotion.reduce(wardAnimatorScale(currentValueOf(LocalContext)))

    /** Lets go once the press has had its time (WardPress.releaseHold), then rises. */
    private fun release() {
        val reduce = reduce()
        // with animations off it lets go at once, as iOS's press does
        val wait = if (reduce) 0.0 else WardPress.releaseHold((System.nanoTime() - pressedAt) / 1e9)
        letGo = coroutineScope.launch {
            delay((wait * 1000).toLong())
            held.animateTo(0f, if (reduce) snap() else tween(wardMillis(WardPress.release), easing = WardQuickEasing))
        }
    }

    override fun ContentDrawScope.draw() {
        val down = held.value
        if (down <= 0f) drawContent() else {
            val content = this
            // the layer reaches as far as the strongest light a face inside it can cast
            val reach = (WardRelief.offset(WardLift.peak) + WardRelief.radius(WardLift.peak)).wardDp.toPx()
            val dim = -255f * WardPressIndication.shade(down)
            val paint = Paint().apply {
                colorFilter = ColorFilter.colorMatrix(ColorMatrix(floatArrayOf(
                    1f, 0f, 0f, 0f, dim,
                    0f, 1f, 0f, 0f, dim,
                    0f, 0f, 1f, 0f, dim,
                    0f, 0f, 0f, 1f, 0f,
                )))
            }
            // with animations off it does not sink, it only shades (iOS CapPop: pressed && !reduceMotion)
            scale(if (reduce()) 1f else WardPressIndication.scale(down), pivot = center) {
                drawIntoCanvas { it.saveLayer(Rect(-reach, -reach, size.width + reach, size.height + reach), paint) }
                content.drawContent()
                drawIntoCanvas { it.restore() }
            }
        }
        if (focused) {
            val look = currentValueOf(LocalWardLook)
            val glide = currentValueOf(LocalWardGlide) ?: WardGlide.rest(look)
            val ink = wardRgb(glide.hex(WardControlStates.focusInk, look.dark))
            val out = (WardControlStates.focusRingGap + WardControlStates.focusRingWidth).wardDp.toPx()
            translate(-out, -out) {
                innerStroke(outlinePath(RectangleShape, Size(size.width + 2 * out, size.height + 2 * out)), ink, WardControlStates.focusRingWidth)
            }
        }
    }
}
