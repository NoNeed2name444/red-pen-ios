package com.stethoscore.app.ui.ward

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.LocalWardDark
import com.stethoscore.app.ui.LocalWardLook
import com.stethoscore.app.ui.wardRgb
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min

// The Compose side of ios/RedPen/Shared/Ward/WardSurfaces.swift:
// soft UI, one matte base and every surface shaped out of it by two lights
// from the top left. Raised, a highlight falls up and left of the shape and a
// shade down and right; pressed in, the same two fall inside it. The numbers
// are WardRelief's and WardPress's (tested on the JVM); this file draws them.
//
// Where Compose differs: Compose has no inner shadow, so an inset face's
// lights are the shadow of a frame round the shape, clipped to the shape
// (the shadow falls inward). Shadows are Android's shadow layer, set to the
// Gaussian SwiftUI uses (its radius twice the deviation). Corners are
// circular, as Compose draws them (WardDockTest checks both kinds); the
// paper frame's opening keeps iOS's continuous corners, from WardEdge.outline.
// The lights are drawn live every frame: the images iOS caches them in
// (WardLightImages; WardLightSlice has the maths) are not ported.

/** The surfaces' sizes, on the scale (WardScale): iOS's WardRadius and WardSpace values these faces use. */
object WardFaceMetrics {
    /** A card's corner (WardRadius.card) and its padding (WardSpace.gutter). */
    const val cardRadius = WardScale.l
    const val cardPadding = WardScale.l
    /** A field's or a row tile's corner (WardRadius.field). */
    const val fieldRadius = WardScale.m
    /** A bar's or a slab's corner (WardRadius.bar). */
    const val barRadius = WardScale.xl
    /** The monitor's bezel round its well (MonitorCard). */
    const val monitorBezel = 6.0
}

/** A light's colour as a framework ARGB int. */
private fun argb(light: WardReliefLight): Int =
    (((light.alpha.coerceIn(0.0, 1.0) * 255) + 0.5).toInt() shl 24) or (light.hex and 0xFFFFFF)

/**
 * Android's shadow-layer radius for a SwiftUI shadow radius of [points]:
 * SwiftUI's radius is twice the Gaussian's deviation, Android's deviation is
 * 0.57735 of its radius plus half a pixel.
 */
private fun DrawScope.shadowRadius(points: Double): Float =
    max(0.01f, ((points / 2).toFloat() * density - 0.5f) / 0.57735f)

private fun roundRectPath(size: Size, radius: Float): Path = Path().apply {
    addRoundRect(RoundRect(Rect(Offset.Zero, size), CornerRadius(min(radius, size.minDimension / 2))))
}

/**
 * One face: [outer] lights dropped outside it, the fill, [inner] lights cast
 * inside it, and a 1-pt edge at [edgeAlpha] in [edge]. Shared by every face
 * below, as WardReliefDrawing and WardPressDrawing share one drawing on iOS.
 */
internal fun DrawScope.drawWardFace(radiusDp: Double, fill: Color, outer: List<WardReliefLight>, inner: List<WardReliefLight>,
                                    edgeAlpha: Double, edge: Color) =
    drawWardFace(WardCornerRadii.all(radiusDp), fill, outer, inner, edgeAlpha, edge)

/** The face's outline with a radius per corner, in pixels, each at most half the shorter side, inset by [by]. */
private fun DrawScope.cornerPath(radiiDp: WardCornerRadii, by: Float = 0f): Path = Path().apply {
    fun c(r: Double) = CornerRadius(max(0f, min(r.toFloat() * density, size.minDimension / 2) - by))
    addRoundRect(RoundRect(Rect(by, by, size.width - by, size.height - by),
        c(radiiDp.topLeft), c(radiiDp.topRight), c(radiiDp.bottomRight), c(radiiDp.bottomLeft)))
}

/** As above, with a radius per corner (WardCorner.radii); one radius draws exactly as before. */
internal fun DrawScope.drawWardFace(radiiDp: WardCornerRadii, fill: Color, outer: List<WardReliefLight>, inner: List<WardReliefLight>,
                                    edgeAlpha: Double, edge: Color) {
    if (size.width <= 0f || size.height <= 0f) return
    val uniform = radiiDp.uniform
    val r = min(radiiDp.topLeft.toFloat() * density, size.minDimension / 2)
    val shape = if (uniform) roundRectPath(size, r) else cornerPath(radiiDp)
    drawIntoCanvas { canvas ->
        val native = canvas.nativeCanvas
        val paint = Paint().asFrameworkPaint().apply { isAntiAlias = true; color = fill.toArgb() }
        fun face() = if (uniform) native.drawRoundRect(0f, 0f, size.width, size.height, r, r, paint)
            else native.drawPath(shape.asAndroidPath(), paint)
        // raised: each light is the face drawn again with its shadow, the shade over the highlight
        val lit = outer.filter { it.lit }
        if (lit.isEmpty()) {
            face()
        } else for (light in lit) {
            paint.setShadowLayer(shadowRadius(light.radius), light.x.toFloat() * density, light.y.toFloat() * density, argb(light))
            face()
        }
        paint.clearShadowLayer()
    }
    // pressed in: the shadow of a frame round the shape, clipped to the shape
    val inside = inner.filter { it.lit }
    if (inside.isNotEmpty()) clipPath(shape) {
        val reach = inside.maxOf { WardLightSlice.reach(of = it) }.toFloat() * density + 2f
        val frame = Path().apply {
            fillType = PathFillType.EvenOdd
            addRect(Rect(-reach, -reach, size.width + reach, size.height + reach))
            addPath(shape)
        }
        drawIntoCanvas { canvas ->
            val paint = Paint().asFrameworkPaint().apply { isAntiAlias = true; color = android.graphics.Color.BLACK }
            for (light in inside) {
                paint.setShadowLayer(shadowRadius(light.radius), light.x.toFloat() * density, light.y.toFloat() * density, argb(light))
                canvas.nativeCanvas.drawPath(frame.asAndroidPath(), paint)
            }
        }
    }
    if (edgeAlpha > 0) {
        val w = 1.dp.toPx()
        if (uniform) drawRoundRect(edge.copy(alpha = edgeAlpha.toFloat()), Offset(w / 2, w / 2), Size(size.width - w, size.height - w),
            CornerRadius(max(0f, r - w / 2)), style = Stroke(w))
        else drawPath(cornerPath(radiiDp, by = w / 2), edge.copy(alpha = edgeAlpha.toFloat()), style = Stroke(w))
    }
}

/** What the faces need from the look on show: dark or not, and the colours. */
private class FaceLook(val dark: Boolean, val fill: Color, val edge: Color)

@Composable private fun faceLook(fill: WardToken, held: Boolean): FaceLook {
    val look = LocalWardLook.current
    val dark = held || LocalWardDark.current
    val glide = WardGlide.rest(look)
    return FaceLook(dark, wardRgb(glide.hex(fill, dark, held)), wardRgb(look.section.ink(dark)))
}

/**
 * Raised off the base (iOS wardRaised, WardReliefFace): a card or a slab by
 * its two lights alone, or with [control] a control's face (a row to tap, a
 * segmented control), which stands on its small rim (WardRelief.rim) with
 * the section's ink edge. Unlit (LocalWardUnlit), a card or a slab keeps
 * only its fill and edge; a control keeps its rim.
 */
@Composable fun Modifier.wardRaised(radius: Double = WardFaceMetrics.cardRadius, lift: WardLift = WardLift.mid,
                                    fill: WardToken = WardToken.surface, control: Boolean = false,
                                    held: Boolean = false): Modifier =
    wardRaised(WardCornerRadii.all(radius), lift, fill, control, held)

/** As wardRaised, with a radius per corner (a corner element's WardCorner.radii, from rememberWardCorners). */
@Composable fun Modifier.wardRaised(radii: WardCornerRadii, lift: WardLift = WardLift.mid,
                                    fill: WardToken = WardToken.surface, control: Boolean = false,
                                    held: Boolean = false): Modifier {
    val f = faceLook(fill, held)
    val spec = if (control) WardRelief.rim(lift, f.dark) else WardRelief.raised(lift, f.dark)
    val lights = if (LocalWardUnlit.current && !control) emptyList() else listOf(spec.highlight, spec.shade)
    return drawBehind { drawWardFace(radii, f.fill, lights, emptyList(), spec.edgeAlpha, f.edge) }
}

/**
 * What corner elements are concentric with on this screen (WardCornerFrame):
 * the paper frame's ring on a framed page, the screen with the display's
 * corner where there is none; null until the window is measured.
 */
val LocalWardCornerFrame = compositionLocalOf<WardCornerFrame?> { null }

/**
 * The window's root (it must fill the window from its top left): measures
 * it and gives [content] the frame its corner elements follow, the ring
 * when [framed], otherwise the screen.
 */
@Composable fun WardCornerScope(framed: Boolean, content: @Composable () -> Unit) {
    var size by remember { mutableStateOf(IntSize.Zero) }
    val safe = wardSystemInsets()
    val device = wardDisplayCorner()
    val pad = LocalConfiguration.current.smallestScreenWidthDp >= 600
    val density = LocalDensity.current.density.toDouble()
    val frame = remember(size, safe, device, pad, framed, density) {
        if (size.width <= 0 || size.height <= 0) null else {
            val w = size.width / density
            val h = size.height / density
            if (framed) WardPaper.panel(w, h, safe, device, pad)?.let(WardCornerFrame::ring)
            else WardCornerFrame.screen(w, h, device ?: WardPaper.deviceRadius(w, h, pad))
        }
    }
    Box(Modifier.fillMaxSize().onSizeChanged { size = it }) {
        CompositionLocalProvider(LocalWardCornerFrame provides frame, content = content)
    }
}

/**
 * A corner element's radii (WardCorner.radii against LocalWardCornerFrame)
 * and the modifier that measures where it stands: put the modifier on the
 * element, draw its corners with the radii. [own] until it is measured, and
 * anywhere away from the frame's corners.
 */
@Composable fun rememberWardCorners(own: Double): Pair<Modifier, WardCornerRadii> {
    val frame = LocalWardCornerFrame.current
    var bounds by remember { mutableStateOf<WardRect?>(null) }
    val density = LocalDensity.current.density.toDouble()
    val radii = remember(frame, bounds, own) {
        val b = bounds
        if (frame == null || b == null) WardCornerRadii.all(own) else WardCorner.radii(b, frame, own)
    }
    return Modifier.onGloballyPositioned {
        val r = it.boundsInWindow()
        bounds = WardRect(r.left / density, r.top / density, r.width / density, r.height / density)
    } to radii
}

/** A Compose shape from per-corner radii in dp. */
fun WardCornerRadii.shape(): androidx.compose.foundation.shape.RoundedCornerShape =
    androidx.compose.foundation.shape.RoundedCornerShape(topLeft.dp, topRight.dp, bottomRight.dp, bottomLeft.dp)

/**
 * Pressed into the base (iOS wardInset): fields, tracks, wells and whatever
 * is chosen; the shade lines the top-left wall and the highlight the
 * bottom-right one, in the well's fill (WardControlStates.wellFill, the page
 * colour) unless [fill] says otherwise (the monitor's dark well). [control]
 * for a field or a switch's track: it takes the ink edge. [held] draws it at
 * night whatever the look (the monitor's well).
 */
@Composable fun Modifier.wardInset(radius: Double = WardFaceMetrics.fieldRadius, lift: WardLift = WardLift.low,
                                   fill: WardToken = WardControlStates.wellFill, control: Boolean = false,
                                   held: Boolean = false): Modifier {
    val f = faceLook(fill, held)
    val spec = WardRelief.inset(lift, f.dark, control = control)
    return drawBehind { drawWardFace(radius, f.fill, emptyList(), listOf(spec.shade, spec.highlight), spec.edgeAlpha, f.edge) }
}

/**
 * Raised on its rim at rest; glides into a hollow at the same lift while
 * [pressed] (iOS wardRelief, WardPressFace), over WardPress's shade times on
 * its glide curve. A control, with its ink edge, unless [control] is false
 * (an icon tile that only shows a choice, which keeps the wide shade, and
 * drops it where the page is unlit, LocalWardUnlit).
 */
@Composable fun Modifier.wardRelief(pressed: Boolean, radius: Double = WardFaceMetrics.fieldRadius, lift: WardLift = WardLift.low,
                                    fill: WardToken = WardToken.surface, control: Boolean = true): Modifier {
    val f = faceLook(fill, held = false)
    // WardPress's shade times on its glide curve; with animations off simply down or up
    val depth by wardDepth(pressed)
    val spec = WardPress.spec(lift, depth.toDouble(), f.dark, control = control)
    val lit = control || !LocalWardUnlit.current
    return drawBehind {
        drawWardFace(radius, f.fill, if (lit) listOf(spec.outerHighlight, spec.outerShade) else emptyList(),
            listOf(spec.innerShade, spec.innerHighlight), spec.edgeAlpha, f.edge)
    }
}

/** A card (iOS wardCard, WardCardStyle): raised [lift] off the base, padded by the gutter. */
@Composable fun WardCardFace(modifier: Modifier = Modifier, lift: WardLift = WardLift.mid,
                             padding: Dp = WardFaceMetrics.cardPadding.dp, spacing: Dp = WardScale.m.dp,
                             content: @Composable ColumnScope.() -> Unit) {
    // a card near the frame's corner is concentric with it (WardCorner.radii)
    val (measure, radii) = rememberWardCorners(WardFaceMetrics.cardRadius)
    Column(modifier.then(measure).wardRaised(radii, lift).padding(padding),
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(spacing), content = content)
}

/**
 * The vitals monitor (iOS MonitorCard): a dark well, the monitor's colour
 * in both modes, pressed into a bezel raised [lift] off the base.
 */
@Composable fun WardMonitorCard(modifier: Modifier = Modifier, lift: WardLift = WardLift.mid, spacing: Dp = WardSpace.m.wardDp,
                                content: @Composable ColumnScope.() -> Unit) {
    val bezel = WardFaceMetrics.monitorBezel
    Box(modifier.wardRaised(WardFaceMetrics.cardRadius, lift).padding(bezel.dp)) {
        Column(Modifier.fillMaxWidth().wardInset(WardFaceMetrics.cardRadius - bezel, fill = WardToken.monitor, held = true)
            .padding((WardScale.l - bezel / 2).dp),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(spacing), content = content)
    }
}

/** The opening's outline with iOS's continuous corners (WardEdge.outline), in pixels. */
internal fun wardOutlinePath(points: List<WardVec>, density: Float): Path = Path().apply {
    points.forEachIndexed { i, p ->
        val x = p.x.toFloat() * density
        val y = p.y.toFloat() * density
        if (i == 0) moveTo(x, y) else lineTo(x, y)
    }
    close()
}

/**
 * A line across the opening joined to its outline by [join]'s arcs (iOS
 * WardIslandPath), in pixels; a side with no arc ends at the join's own end,
 * or at [from] / [to] when that side is not joined. With [filledTo] (points),
 * the island under the line, closed down to that depth (iOS `filled`).
 */
internal fun wardIslandPath(join: WardEdgeJoin, from: Double, to: Double, density: Float,
                            filledTo: Double? = null): Path = Path().apply {
    fun deg(rad: Double) = (rad * 180 / PI).toFloat()
    fun box(c: WardEdgeCorner) = Rect(
        ((c.center.x - c.radius) * density).toFloat(), ((c.center.y - c.radius) * density).toFloat(),
        ((c.center.x + c.radius) * density).toFloat(), ((c.center.y + c.radius) * density).toFloat())
    val left = join.left
    val right = join.right
    if (left != null) {
        val start = deg(atan2(left.join.y - left.center.y, left.join.x - left.center.x))
        val from0 = if (start < 0) start + 360 else start
        moveTo((left.join.x * density).toFloat(), (left.join.y * density).toFloat())
        arcTo(box(left), from0, 270f - from0, forceMoveTo = false)
    } else {
        moveTo(((join.fromX ?: from) * density).toFloat(), (join.y * density).toFloat())
    }
    lineTo(((join.toX ?: to) * density).toFloat(), (join.y * density).toFloat())
    if (right != null) {
        val end = deg(atan2(right.join.y - right.center.y, right.join.x - right.center.x))
        arcTo(box(right), -90f, end + 90f, forceMoveTo = false)
    }
    if (filledTo != null) {
        val foot = (filledTo * density).toFloat()
        lineTo(((right?.join?.x ?: join.toX ?: to) * density).toFloat(), foot)
        lineTo(((left?.join?.x ?: join.fromX ?: from) * density).toFloat(), foot)
        close()
    }
}

/** How far the system bars and cut-outs reach in (WindowInsets.safeDrawing, what the pages pad by), in dp. */
@Composable fun wardSystemInsets(): WardSystemInsets {
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val safe = WindowInsets.safeDrawing
    val d = density.density.toDouble()
    return WardSystemInsets(top = safe.getTop(density) / d, bottom = safe.getBottom(density) / d,
        left = safe.getLeft(density, direction) / d, right = safe.getRight(density, direction) / d)
}

/**
 * The display's own corner radius in dp, as the device reports it
 * (WindowInsets.getRoundedCorner, Android 12 and later; the largest of the
 * four corners); null below Android 12 or when the device reports none, so
 * the caller takes WardPaper.deviceRadius.
 */
@Composable fun wardDisplayCorner(): Double? {
    if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S) return null
    val insets = LocalView.current.rootWindowInsets ?: return null
    val density = LocalDensity.current.density.toDouble()
    val radii = listOf(android.view.RoundedCorner.POSITION_TOP_LEFT, android.view.RoundedCorner.POSITION_TOP_RIGHT,
        android.view.RoundedCorner.POSITION_BOTTOM_LEFT, android.view.RoundedCorner.POSITION_BOTTOM_RIGHT)
        .mapNotNull { insets.getRoundedCorner(it)?.radius }
    return radii.maxOrNull()?.let { it / density }
}

/**
 * A page inside the paper's opening (iOS SkyRoot's padding): clear of the
 * system bars, [WardPaper.sideInset] in from each side, and the ring's width
 * in from the top and bottom, so every control sits wholly inside the ring.
 */
fun Modifier.wardFrameClearance(): Modifier =
    safeDrawingPadding().padding(horizontal = WardPaper.sideInset.dp, vertical = WardPaper.edgeWidth.dp)

/**
 * Still ECG paper round the screen (iOS WardPaperFrame): the paper outside
 * the page's opening, its grid on the window's, and the opening's ring in the
 * paper's edge ink, the continuous corners of WardEdge.outline. The opening
 * stops short of the status and navigation bars and takes the display's
 * corner (WardPaper.panel with the system insets), so the ring never runs
 * through a bar; pages sit inside it by wardFrameClearance. With
 * [barTop] (points from the frame's top), a bar's line runs across the
 * opening there, joined into the ring by WardEdge's arcs. Fill the window
 * with it, over the page: it takes no touches. Home keeps its own ground.
 * While it is drawn, the study deck's line joins its ring (WardEdgeStore).
 */
@Composable fun WardPaperFrame(modifier: Modifier = Modifier, barTop: Double? = null) {
    val look = LocalWardLook.current
    val dark = look.dark
    val glide = WardGlide.rest(look)
    val ink = WardPaper.ink(glide, dark, highContrast = false)
    val color = wardRgb(ink.hex)
    val base = wardRgb(glide.hex(WardToken.background, dark))
    val pad = LocalConfiguration.current.smallestScreenWidthDp >= 600
    // clear of the status and navigation bars, its corners concentric with the display's
    val safe = wardSystemInsets()
    val device = wardDisplayCorner()
    val view = LocalView.current
    val points = LocalDensity.current.density
    DisposableEffect(view) { onDispose { WardEdgeStore.leave(view) } }
    Canvas(modifier.onGloballyPositioned { WardEdgeStore.setWindow(view, it.wardWindowRect(points), pad, safe, device) }) {
        val panel = WardPaper.panel((size.width / density).toDouble(), (size.height / density).toDouble(), safe, device, pad = pad)
            ?: return@Canvas
        val outline = WardEdge.outline(panel, pointsPerCurve = 12)
        val hole = wardOutlinePath(outline, density)
        // the paper, outside the opening
        clipPath(hole, ClipOp.Difference) {
            drawRect(base)
            val line = WardPaper.line.toFloat() * density
            fun drawLine(at: Float, bold: Boolean, across: Boolean) {
                val alpha = (if (bold) ink.bold else ink.fine).toFloat()
                if (alpha <= 0f) return
                if (across) drawRect(color.copy(alpha = alpha), Offset(0f, at - line / 2), Size(size.width, line))
                else drawRect(color.copy(alpha = alpha), Offset(at - line / 2, 0f), Size(line, size.height))
            }
            for (l in WardPaper.lines((size.width / density).toDouble())) drawLine(l.at.toFloat() * density, l.bold, across = false)
            for (l in WardPaper.lines((size.height / density).toDouble())) drawLine(l.at.toFloat() * density, l.bold, across = true)
        }
        // the ring and any bar's line, opaque in one layer, then the layer at the edge's strength
        val w = WardPaper.edgeWidth.toFloat() * density
        drawIntoCanvas { canvas ->
            canvas.saveLayer(Rect(Offset.Zero, size), Paint().apply { alpha = ink.edge.toFloat() })
            drawPath(hole, color, style = Stroke(w))
            val join = barTop?.let { WardEdge.join(outline, it, panel.radius) }
            if (join != null) drawPath(wardIslandPath(join, panel.x, panel.x + panel.width, density), color, style = Stroke(w))
            canvas.restore()
        }
    }
}
