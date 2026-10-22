package com.stethoscore.app.ui

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.ward.WardGround
import com.stethoscore.app.ui.ward.WardPaper

// Home's ground (WardGround: the base with the section's wash and the ECG
// paper's grid), drawn as vectors at the screen's density, never a picture:
// the window's background from the first frame the app draws
// (WardGroundDrawable, set by MainActivity before the first frame), and home
// behind its content (WardGroundBackground). Both count the grid from the
// window's top left with the same cell, bold rhythm and line weight, so
// nothing steps at the hand-over. Before the app's code runs, the system's
// starting window shows the theme's ward_ground colour, the same base.

/** Each grid line's position in pixels and whether it is bold, for [lengthPx] at [cellPx] a cell. */
internal fun wardGridLines(lengthPx: Float, cellPx: Float): List<Pair<Float, Boolean>> {
    if (!(cellPx > 0f) || !(lengthPx > 0f)) return emptyList()
    val points = lengthPx / cellPx * WardPaper.cell
    return WardPaper.lines(points.toDouble()).map { (it.at / WardPaper.cell).toFloat() * cellPx to it.bold }
}

/** The ground as the window's background: base, then the grid, drawn at the screen's [density]. */
class WardGroundDrawable(private val ground: WardGround, private val density: Float) : Drawable() {
    private val paint = Paint().apply { isAntiAlias = true; style = Paint.Style.FILL }

    override fun draw(canvas: Canvas) {
        val b = bounds
        canvas.drawColor(0xFF000000.toInt() or ground.base)
        if (ground.ink.fine <= 0 && ground.ink.bold <= 0) return
        val cell = (WardPaper.cell * density).toFloat()
        val line = (WardPaper.line * density).toFloat()
        fun alpha(bold: Boolean) = ((if (bold) ground.ink.bold else ground.ink.fine) * 255 + 0.5).toInt().coerceIn(0, 255)
        // the same lines Compose draws: centred on k·cell, `line` wide
        for ((x, bold) in wardGridLines(b.width().toFloat(), cell)) {
            paint.color = (alpha(bold) shl 24) or ground.ink.hex
            canvas.drawRect(b.left + x - line / 2, b.top.toFloat(), b.left + x + line / 2, b.bottom.toFloat(), paint)
        }
        for ((y, bold) in wardGridLines(b.height().toFloat(), cell)) {
            paint.color = (alpha(bold) shl 24) or ground.ink.hex
            canvas.drawRect(b.left.toFloat(), b.top + y - line / 2, b.right.toFloat(), b.top + y + line / 2, paint)
        }
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.OPAQUE
}

/**
 * The ground behind a page, filling [modifier]'s bounds from the window's top
 * left. With [gridBottom] (window pixels, read as it draws) the paper's grid
 * is a band from the window's top down to that line and the plain base below
 * it, as iOS WardPaperBand (home: the owner, 9 Oct, "the grid from upwards
 * till under the stethoscore word"); a null bottom draws no grid. Without
 * it, the grid fills the page.
 */
@Composable fun WardGroundBackground(ground: WardGround, modifier: Modifier = Modifier, gridBottom: (() -> Float?)? = null) {
    val base = wardRgb(ground.base)
    val ink = wardRgb(ground.ink.hex)
    val origin = remember { floatArrayOf(0f) }
    Canvas(modifier.onGloballyPositioned { origin[0] = it.positionInWindow().y }) {
        drawRect(base)
        if (ground.ink.fine <= 0 && ground.ink.bold <= 0) return@Canvas
        val height = if (gridBottom == null) size.height else (gridBottom() ?: return@Canvas) - origin[0]
        val band = minOf(size.height, height)
        if (band <= 0f) return@Canvas
        val cell = WardPaper.cell.toFloat().dp.toPx()
        val line = WardPaper.line.toFloat().dp.toPx()
        fun color(bold: Boolean) = ink.copy(alpha = (if (bold) ground.ink.bold else ground.ink.fine).toFloat())
        clipRect(bottom = band) {
            for ((x, bold) in wardGridLines(size.width, cell)) {
                drawRect(color(bold), Offset(x - line / 2, 0f), androidx.compose.ui.geometry.Size(line, band))
            }
            for ((y, bold) in wardGridLines(band, cell)) {
                drawRect(color(bold), Offset(0f, y - line / 2), androidx.compose.ui.geometry.Size(size.width, line))
            }
        }
    }
}
