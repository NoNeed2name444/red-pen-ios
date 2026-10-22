package com.stethoscore.app.ui.ward

import android.view.View
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.LocalWardLook
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.wardRgb
import java.lang.ref.WeakReference
import kotlin.math.max

// The bottom study deck, one for every screen: a port of StudyActionBar and
// DeckFoldBand (ios/RedPen/Shared/Theme.swift) on WardDeckSlab, WardDeckShape,
// wardBarBase, WardEdgeHost, WardScrollEdgeLine and WardEdgeStore
// (Shared/Ward/WardSurfaces.swift). The open deck stands on a strip in the
// page's wash with the frame's line along its top, the line's ends curving
// down into the paper frame's ring (WardEdge's arcs); the slab is the same
// wash, flat, since it always holds a control. Folded, one round button
// floats at the trailing edge with no strip and no glow.
//
// Where Android differs: the fold has no motion yet; a broad window keeps
// the slab centred at most 700 wide, as the readable column, rather than
// hugging its buttons at the trailing hand (that needs the content's
// intrinsic width, which subcomposed content cannot give); the slab's bottom
// corners are circular, as Compose draws them; and its edge, which iOS shows
// only under Increase Contrast, is not drawn, as no Android face reads it.

/**
 * The paper frame on show, as the bars see it (iOS WardEdgeStore's window
 * and panel): where it lies in its window and its opening, in points.
 */
internal class WardEdgeWindow(view: View, val bounds: WardRect, val pad: Boolean) {
    private val view = WeakReference(view)
    val panel: WardPaperPanel? = WardPaper.panel(bounds.width, bounds.height, pad = pad)
    /** The outline the frame strokes, the very one the joins are solved on. */
    val outline: List<WardVec> = panel?.let { WardEdge.outline(it, pointsPerCurve = 12) } ?: emptyList()

    fun frames(view: View): Boolean = this.view.get() === view
    fun same(view: View, bounds: WardRect, pad: Boolean): Boolean = frames(view) && this.bounds == bounds && this.pad == pad
}

/**
 * Set by WardPaperFrame while it is drawn (iOS setWindow). A bar in another
 * window (a dialog), or with no frame round it (a sheet over home), finds
 * none and keeps a plain line.
 */
internal object WardEdgeStore {
    var window: WardEdgeWindow? by mutableStateOf(null)
        private set

    fun setWindow(view: View, bounds: WardRect, pad: Boolean) {
        if (window?.same(view, bounds, pad) == true) return
        window = WardEdgeWindow(view, bounds, pad)
    }

    fun leave(view: View) {
        if (window?.frames(view) == true) window = null
    }
}

/**
 * One bar's line joined into the frame's opening (iOS WardEdgeStore.Entry):
 * [host] is the bar, [join] its line, both in the frame's points.
 */
internal class WardDeckEdge(val host: WardRect, val panel: WardPaperPanel, val outline: List<WardVec>, val join: WardEdgeJoin) {
    /** The join in the bar's own points (Entry.local). */
    val local: WardEdgeJoin get() = WardIsland.local(join, WardVec(host.x, host.y))

    companion object {
        /**
         * iOS WardEdgeStore.resolve: the line at the bar's top, joined on the
         * sides where the bar meets the page's edges; null where it meets
         * neither, or the frame has no opening.
         */
        fun solve(host: WardRect, page: WardRect, panel: WardPaperPanel?, outline: List<WardVec>): WardDeckEdge? {
            if (panel == null) return null
            val sides = WardIsland.sides(host, page, covered = false)
            if (!sides.any) return null
            val join = WardEdge.join(outline, host.minY + WardPaper.edgeWidth / 2, panel.radius, sides.left, sides.right) ?: return null
            return WardDeckEdge(host, panel, outline, join)
        }
    }
}

/** A layout's place in its window, in points. */
internal fun LayoutCoordinates.wardWindowRect(density: Float): WardRect {
    val at = positionInWindow()
    return WardRect((at.x / density).toDouble(), (at.y / density).toDouble(),
        (size.width / density).toDouble(), (size.height / density).toDouble())
}

/**
 * The bottom study deck (StudyActionBar): an open slab with the screen's
 * buttons, and, when it [folds], a 44-point band whose small pill folds it
 * away into one round button at the trailing edge. Hidden (not [shown]), it
 * takes no room and keeps its fold for the next question. It starts open.
 */
@Composable fun StudyActionBar(folds: Boolean = false, shown: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    var folded by rememberSaveable { mutableStateOf(false) }
    if (!shown) return
    val density = LocalDensity.current.density
    val view = LocalView.current
    val window = WardEdgeStore.window?.takeIf { it.frames(view) }
    // the bar and its slab in the window's points, then in the frame's
    var host by remember { mutableStateOf<WardRect?>(null) }
    var slab by remember { mutableStateOf<WardRect?>(null) }
    val edge = remember(window, host) {
        val w = window
        val h = host
        if (w == null || h == null) null
        else WardDeckEdge.solve(WardRect(h.x - w.bounds.x, h.y - w.bounds.y, h.width, h.height),
            WardRect(0.0, 0.0, w.bounds.width, w.bounds.height), w.panel, w.outline)
    }
    val local = remember(window, slab) {
        val w = window
        val s = slab
        if (w == null || s == null || !(s.width > 0)) null else WardRect(s.x - w.bounds.x, s.y - w.bounds.y, s.width, s.height)
    }
    val inset = remember(edge, local) { if (edge != null && local != null) WardIsland.foldInset(local, edge.join) else 0.0 }
    val open = !(folds && folded)
    Box(Modifier.fillMaxWidth()
        .onGloballyPositioned { host = it.wardWindowRect(density) }
        // the slab holds controls, so it is flat and casts nothing up: the
        // strip and its line start at the slab's top
        .wardBarBase(edge, shown = open)
        .padding(horizontal = 12.dp).padding(bottom = 8.dp), contentAlignment = Alignment.BottomCenter) {
        if (!open) {
            // folded, it floats over the page with no strip: no glow to haze what scrolls under it
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) { WardUnlit {
                WardButtonBox({ folded = false }, Modifier.semantics { contentDescription = "Show buttons" },
                    kind = WardButtonKind.secondary, fills = false) {
                    Icon(Icons.Rounded.KeyboardArrowUp, null, Modifier.size(16.dp))
                }
            } }
        } else {
            Column(Modifier.widthIn(max = 700.dp).fillMaxWidth()
                .onGloballyPositioned { slab = it.wardWindowRect(density) }
                .wardDeckSlab(edge, local)) {
                if (folds) DeckFoldBand(inset) { folded = true }
                Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = if (folds) 0.dp else 12.dp, bottom = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
            }
        }
    }
}

/**
 * The open deck's folding band (DeckFoldBand): the chevron in a small pill
 * at the trailing end, [inset] clear of the line's arc (WardIsland.foldInset),
 * raised off the slab with a control's edge and pressed in while held. The
 * whole band is the target.
 */
@Composable private fun DeckFoldBand(inset: Double, onFold: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val held by source.collectIsPressedAsState()
    val focused by source.collectIsFocusedAsState()
    Row(Modifier.fillMaxWidth().height(44.dp)
        .clickable(source, indication = null, role = Role.Button, onClick = onFold)
        .semantics { contentDescription = "Hide buttons" },
        horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.padding(end = inset.wardDp).size(56.dp, 44.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.size(44.dp, 28.dp).capPop(held)
                .wardFocusRing(CircleShape, focused, wardColor(WardControlStates.focusInk))
                .wardPressFace(CircleShape, WardLift.low, wardDepth(held)), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.KeyboardArrowDown, null, Modifier.size(18.dp), tint = wardColor(WardToken.ink))
            }
        }
    }
}

/**
 * The strip under an open deck and the line along its top (iOS
 * wardBarBase(room: 0), WardEdgeHost, WardScrollEdgeLine): the page's wash,
 * from the line down to the window's foot, and over the bar one stroke of
 * the frame's edge ink whose ends curve into the frame's ring. The frame
 * owns its own stroke where the two meet. With no frame to join, a plain
 * line runs across the top.
 */
@Composable private fun Modifier.wardBarBase(edge: WardDeckEdge?, shown: Boolean): Modifier {
    if (!shown) return this
    val look = LocalWardLook.current
    val ink = WardPaper.ink(WardGlide.rest(look), look.dark, highContrast = false)
    val line = wardRgb(ink.hex).copy(alpha = ink.edge.toFloat())
    val wash = wardColor(WardToken.background)
    return drawWithContent {
        val w = (WardPaper.edgeWidth * density).toFloat()
        val side = WardPaper.sideInset
        if (edge == null) {
            drawRect(wash)
            drawContent()
            val out = (side * density).toFloat()
            drawRect(line, Offset(-out, 0f), Size(size.width + 2 * out, w))
            return@drawWithContent
        }
        val host = edge.host
        val foot = max((size.height / density).toDouble(), edge.panel.y + edge.panel.height - host.minY + WardPaper.frame)
        drawPath(wardIslandPath(edge.local, -side, host.width + side, density, filledTo = foot), wash)
        drawContent()
        val stroke = wardIslandPath(edge.local, -side, host.width + side, density)
        val hole = wardOutlinePath(edge.outline, density)
        drawIntoCanvas { canvas ->
            canvas.saveLayer(stroke.getBounds().inflate(w), Paint())
            drawPath(stroke, line, style = Stroke(w))
            translate((-host.x * density).toFloat(), (-host.y * density).toFloat()) {
                drawPath(hole, Color.Black, style = Stroke(w), blendMode = BlendMode.Clear)
            }
            canvas.restore()
        }
    }
}

/**
 * The deck's slab (WardDeckSlab): the strip's own wash, not the cards'
 * surface, so the dock reads as one tone with the screen (the owner, 21
 * Oct). Joined, its top corners follow the line's arcs (WardEdge.slabTopRadius)
 * and the island cuts it where a join passes its circle's widest point.
 */
@Composable private fun Modifier.wardDeckSlab(edge: WardDeckEdge?, slab: WardRect?): Modifier {
    val wash = wardColor(WardToken.background)
    return drawBehind {
        if (edge != null && slab != null) {
            val left = WardEdge.slabTopRadius(edge.join.left, slabSide = slab.minX, leading = true)
            val right = WardEdge.slabTopRadius(edge.join.right, slabSide = slab.maxX, leading = false)
            val island = wardIslandPath(WardIsland.local(edge.join, WardVec(slab.x, slab.y)), -WardPaper.sideInset,
                slab.width + WardPaper.sideInset, density, filledTo = (size.height / density).toDouble())
            clipPath(island) { drawPath(deckShape(size, left, right, density), wash) }
        } else {
            drawRoundRect(wash, cornerRadius = CornerRadius((WardRadius.bar * density).toFloat()))
        }
    }
}

/** WardDeckShape, joined: circular top corners of [left] and [right] points from the line's middle, the bar's corners below. */
private fun deckShape(size: Size, left: Double, right: Double, density: Float): Path = Path().apply {
    val top = (WardPaper.edgeWidth / 2 * density).toFloat()
    val half = size.width / 2
    val l = (left * density).toFloat().coerceIn(0f, half)
    val r = (right * density).toFloat().coerceIn(0f, half)
    val b = (WardRadius.bar * density).toFloat().coerceIn(0f, minOf(half, size.height / 2))
    moveTo(0f, top + l)
    arcTo(Rect(0f, top, 2 * l, top + 2 * l), 180f, 90f, forceMoveTo = false)
    lineTo(size.width - r, top)
    arcTo(Rect(size.width - 2 * r, top, size.width, top + 2 * r), 270f, 90f, forceMoveTo = false)
    lineTo(size.width, size.height - b)
    arcTo(Rect(size.width - 2 * b, size.height - 2 * b, size.width, size.height), 0f, 90f, forceMoveTo = false)
    lineTo(b, size.height)
    arcTo(Rect(0f, size.height - 2 * b, 2 * b, size.height), 90f, 90f, forceMoveTo = false)
    close()
}
