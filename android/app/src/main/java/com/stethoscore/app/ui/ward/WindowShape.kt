package com.stethoscore.app.ui.ward

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.foundation.layout.absolutePadding
import androidx.compose.ui.unit.dp
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import kotlin.math.min

// The window's shape (T0139): how wide the window is, by class, and the fold
// when there is one. Every layout that changes with size reads this, never the
// display, the device's model or a "tablet" flag: a tablet split to a third is
// a phone-wide window and is laid out as one. The size is the window's own
// (what the app is given to lay out in), the fold androidx.window's
// FoldingFeature in that window's coordinates. Pure Kotlin but for the
// provider at the bottom (WindowShapeTest).

/** The width classes Android's window guidance names, at its thresholds. */
enum class WardWidthClass { compact, medium, expanded }

/** A fold or hinge across the window, in dp from the window's top left (androidx.window FoldingFeature). */
data class WardFold(
    val state: State,
    val orientation: Orientation,
    val bounds: WardRect,
    /** Whether the fold splits the window into two areas (a hinge, or a fold half open). */
    val isSeparating: Boolean,
    val occlusion: Occlusion,
) {
    enum class State { flat, halfOpened }
    /** Vertical: the fold runs top to bottom (a book); horizontal: side to side (a laptop on a table). */
    enum class Orientation { vertical, horizontal }
    /** Full: the fold hides what is under it (a hinge between two screens). */
    enum class Occlusion { none, full }
}

/** How the window is held: one area, a half-open fold lying flat (tabletop), or one stood like a book. */
enum class WardPosture { flat, tabletop, book }

data class WindowShape(val width: Double, val height: Double, val fold: WardFold? = null) {
    val widthClass: WardWidthClass get() = widthClass(width)
    /** iOS WindowSpan.broad: 700 points and wider, where two columns stop being a squeeze. */
    val isBroad: Boolean get() = isBroad(width)
    /** The window's shorter side. */
    val shortSide: Double get() = min(width, height)
    /** A window a tablet's size whichever way it is held (the frame's and home's iPad measures). */
    val isPadSized: Boolean get() = shortSide >= compactMax
    val isLandscape: Boolean get() = width > height
    /** Home's dock stands up as a rail at the leading edge in a broad window, as iOS's (LibraryView.swift:654). */
    val dockIsRail: Boolean get() = isBroad
    /** Whether the fold, as the window has it, splits the content into two areas. */
    val separatingFold: WardFold? get() = fold?.takeIf { it.isSeparating || it.occlusion == WardFold.Occlusion.full }

    val posture: WardPosture get() {
        val f = fold ?: return WardPosture.flat
        if (f.state != WardFold.State.halfOpened && separatingFold == null) return WardPosture.flat
        return if (f.orientation == WardFold.Orientation.horizontal) WardPosture.tabletop else WardPosture.book
    }

    /**
     * The two areas the window is laid out in, clear of the hinge: above and
     * below a horizontal fold, either side of a vertical one; for an expanded
     * window without one, a leading list beside the open item ([listShare] of
     * the width). Null where the window is one area.
     */
    fun panes(listShare: Double = 0.4): Pair<WardRect, WardRect>? {
        val f = separatingFold
        if (f != null) return if (f.orientation == WardFold.Orientation.horizontal)
            WardRect(0.0, 0.0, width, f.bounds.minY) to WardRect(0.0, f.bounds.maxY, width, height - f.bounds.maxY)
        else WardRect(0.0, 0.0, f.bounds.minX, height) to WardRect(f.bounds.maxX, 0.0, width - f.bounds.maxX, height)
        if (widthClass != WardWidthClass.expanded) return null
        val lead = (width * listShare).coerceAtLeast(320.0)
        return WardRect(0.0, 0.0, lead, height) to WardRect(lead, 0.0, width - lead, height)
    }

    /** Whether [rect] (dp, window coordinates) meets the hinge of a separating fold. */
    fun meetsHinge(rect: WardRect): Boolean {
        val b = separatingFold?.bounds ?: return false
        // a fold with no thickness is a line: it is met by whatever crosses it
        fun across(lo: Double, hi: Double, from: Double, to: Double) = lo < to && hi > from
        return across(rect.minX, rect.maxX, b.minX, b.maxX) && across(rect.minY, rect.maxY, b.minY, b.maxY)
    }

    /** Room to leave on each side of a page so it keeps clear of the hinge, in dp: left, top, right, bottom. */
    data class Clearance(val left: Double = 0.0, val top: Double = 0.0, val right: Double = 0.0, val bottom: Double = 0.0)

    /**
     * How far a page laid out over [box] (dp, window coordinates) is drawn in
     * so nothing of it lies in a separating fold: on the larger side of the
     * fold, either way it runs, and on the reading side (above a horizontal
     * fold, left of a vertical one) when they match, as iOS's
     * DevicePosture.clearPane. Nothing where the fold does not split.
     */
    fun hingeClearance(box: WardRect): Clearance {
        val f = separatingFold ?: return Clearance()
        val b = f.bounds
        if (f.orientation == WardFold.Orientation.horizontal) {
            val topPane = b.minY
            val bottomPane = height - b.maxY
            return if (topPane >= bottomPane) Clearance(bottom = maxOf(0.0, box.maxY - b.minY))
            else Clearance(top = maxOf(0.0, b.maxY - box.minY))
        }
        val leftPane = b.minX
        val rightPane = width - b.maxX
        return if (leftPane >= rightPane) Clearance(right = maxOf(0.0, box.maxX - b.minX))
        else Clearance(left = maxOf(0.0, b.maxX - box.minX))
    }

    /**
     * [hingeClearance] for a page whose place is not measured yet: laid over the
     * whole window, so the first frame is already clear of the hinge and does not
     * jump once the page has measured itself.
     */
    fun clearanceFor(box: WardRect?): Clearance = hingeClearance(box ?: WardRect(0.0, 0.0, width, height))

    /**
     * The area a page cleared of the hinge (hingeClearance) is laid out in, as a
     * window of its own and with no fold in it: the larger side of the fold (the
     * reading side on a tie), as hingeClearance. What decides from the size (the dock's rail, broad
     * layouts, home's short window) reads this inside that page, not the whole
     * window. The window itself where no fold splits it.
     */
    val pagePane: WindowShape get() {
        val f = separatingFold ?: return this
        val b = f.bounds
        if (f.orientation == WardFold.Orientation.horizontal) {
            val top = b.minY
            val bottom = height - b.maxY
            return WindowShape(width, maxOf(0.0, if (top >= bottom) top else bottom), null)
        }
        val left = b.minX
        val right = width - b.maxX
        return WindowShape(maxOf(0.0, if (left >= right) left else right), height, null)
    }

    companion object {
        /** Compact below 600, medium below 840, expanded from 840 dp. */
        const val compactMax = 600.0
        const val mediumMax = 840.0
        /** iOS WindowSpan.broad. */
        const val broad = 700.0

        fun widthClass(width: Double): WardWidthClass = when {
            width < compactMax -> WardWidthClass.compact
            width < mediumMax -> WardWidthClass.medium
            else -> WardWidthClass.expanded
        }
        fun isBroad(width: Double): Boolean = width >= broad
        fun isExpanded(width: Double): Boolean = width >= mediumMax

        /** androidx.window's fold, in px of the window, as a WardFold in dp. */
        fun fold(feature: FoldingFeature, density: Double): WardFold {
            val b = feature.bounds
            return WardFold(
                state = if (feature.state == FoldingFeature.State.HALF_OPENED) WardFold.State.halfOpened else WardFold.State.flat,
                orientation = if (feature.orientation == FoldingFeature.Orientation.HORIZONTAL) WardFold.Orientation.horizontal else WardFold.Orientation.vertical,
                bounds = WardRect(b.left / density, b.top / density, b.width() / density, b.height() / density),
                isSeparating = feature.isSeparating,
                occlusion = if (feature.occlusionType == FoldingFeature.OcclusionType.FULL) WardFold.Occlusion.full else WardFold.Occlusion.none,
            )
        }
    }
}

/** The window's shape, from WindowShapeHost; null outside one (a screen composed on its own, as in a test). */
val LocalWindowShape = compositionLocalOf<WindowShape?> { null }

/**
 * The window's shape: the host's when there is one, otherwise the window's
 * size as the configuration gives it (screenWidthDp and screenHeightDp are
 * the window's, not the display's, in split screen and free-form too), no fold.
 */
@Composable fun currentWindowShape(): WindowShape {
    LocalWindowShape.current?.let { return it }
    val config = LocalConfiguration.current
    return WindowShape(config.screenWidthDp.toDouble(), config.screenHeightDp.toDouble())
}

private tailrec fun Context.activity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.activity()
    else -> null
}

/**
 * The app's root: lays [content] out in the whole window and publishes its
 * shape, the window's size measured here and the fold from androidx.window's
 * WindowInfoTracker (none where the platform reports none, or off an activity).
 */
@Composable fun WindowShapeHost(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val density = LocalDensity.current.density.toDouble()
    var fold by remember { mutableStateOf<WardFold?>(null) }
    LaunchedEffect(context, density) {
        val activity = context.activity() ?: return@LaunchedEffect
        val tracker = runCatching { WindowInfoTracker.getOrCreate(activity) }.getOrNull() ?: return@LaunchedEffect
        runCatching {
            tracker.windowLayoutInfo(activity).collect { info ->
                fold = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()?.let { WindowShape.fold(it, density) }
            }
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val shape = WindowShape(maxWidth.value.toDouble(), maxHeight.value.toDouble(), fold)
        CompositionLocalProvider(LocalWindowShape provides shape, content = content)
    }
}

/**
 * Keeps a page clear of a fold that splits the window (WindowShape.hingeClearance):
 * the page measures where it lies in the window and draws itself in from the
 * hinge, so no control or text is ever under it. Nothing changes without a fold.
 */
@Composable fun Modifier.wardClearOfHinge(shape: WindowShape): Modifier {
    if (shape.separatingFold == null) return this
    val density = LocalDensity.current.density.toDouble()
    var box by remember { mutableStateOf<WardRect?>(null) }
    val clear = shape.clearanceFor(box)
    return onGloballyPositioned { c ->
        val p = c.positionInWindow()
        box = WardRect(p.x / density, p.y / density, c.size.width / density, c.size.height / density)
    }.absolutePadding(clear.left.dp, clear.top.dp, clear.right.dp, clear.bottom.dp)
}

/**
 * A page kept clear of the hinge (wardClearOfHinge) and told its own size: inside
 * it, LocalWindowShape is the pane the page lies in (WindowShape.pagePane), so a
 * book-held fold's half is laid out as the phone-wide window it is.
 */
@Composable fun WardHingePane(shape: WindowShape, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.wardClearOfHinge(shape)) {
        val scope = this
        CompositionLocalProvider(LocalWindowShape provides shape.pagePane) { scope.content() }
    }
}
