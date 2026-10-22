package com.stethoscore.app.ui.editors

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.OcclusionBox
import com.stethoscore.app.data.PhotoOcclusion
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.wardColor

// A port of ios/RedPen/Features/Library/OcclusionCoverEditor.swift
// (fed0105): the picture with its covers, to adjust with a finger or a stylus.
// - Tap a cover to choose it; drag it to move it.
// - Drag a chosen cover's corner to stretch it.
// - Drag across an empty part of the picture to draw a new cover.
// - Tap an empty part to choose nothing.
// Covers are drawn see-through while they are edited, so the label under each
// can be checked; the review screen draws them solid. The decisions are
// PhotoOcclusion's (PhotoOcclusionTest).

/** What the drag under way is doing, decided where it started. */
private sealed class Edit {
    data class Move(val id: String, val from: OcclusionBox) : Edit()
    data class Stretch(val id: String, val corner: PhotoOcclusion.Handle, val from: OcclusionBox) : Edit()
    data class Draw(val x: Double, val y: Double) : Edit()
}

/** A fingertip, in dp: how near a corner counts as on it. */
private const val REACH = 24f
private const val HANDLE_SIZE = 16f

@Composable fun OcclusionCoverEditor(
    image: ImageBitmap?,
    aspect: Double,
    covers: List<PhotoOcclusion.Cover>,
    onCovers: (List<PhotoOcclusion.Cover>) -> Unit,
    selected: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = wardColor(WardToken.primary),
) {
    val ratio = if (aspect > 0) aspect.toFloat() else 1f
    val shape = RoundedCornerShape(WardRadius.card.wardDp)
    val beam = wardColor(WardToken.beam)
    val surface = wardColor(WardToken.surface)
    var drawing by remember { mutableStateOf<OcclusionBox?>(null) }
    val nowCovers by rememberUpdatedState(covers)
    val nowSelected by rememberUpdatedState(selected)
    val setCovers by rememberUpdatedState(onCovers)
    val select by rememberUpdatedState(onSelect)
    val answered = covers.count { PhotoOcclusion.tidied(it.answer).isNotEmpty() }
    Box(
        modifier.fillMaxWidth().aspectRatio(ratio)
            // the picture raised just off the base
            .wardRaised(WardRadius.card, WardLift.low)
            .clip(shape)
            .semantics {
                contentDescription = "Picture with ${covers.size} covers"
                stateDescription = "$answered answered. Drag across the picture to draw a cover. Each cover's answer can also be edited in the list below."
            },
    ) {
        if (image != null) Image(image, null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
        else Box(Modifier.fillMaxSize().background(surface))
        Canvas(Modifier.fillMaxSize().pointerInput(Unit) {
            fun fraction(p: Offset): Pair<Double, Double> = (p.x / size.width.coerceAtLeast(1)).toDouble() to (p.y / size.height.coerceAtLeast(1)).toDouble()
            fun set(id: String, box: OcclusionBox) { setCovers(nowCovers.map { if (it.id == id) it.copy(box = box) else it }) }
            fun begin(start: Offset): Edit {
                val (ax, ay) = fraction(start)
                val tx = (REACH.dp.toPx() / size.width.coerceAtLeast(1)).toDouble()
                val ty = (REACH.dp.toPx() / size.height.coerceAtLeast(1)).toDouble()
                // the chosen cover's corners first: they sit on its edge, where a neighbouring cover may also be
                val chosen = nowSelected?.let { id -> nowCovers.firstOrNull { it.id == id } }
                if (chosen != null) {
                    PhotoOcclusion.handle(ax, ay, chosen.box, tx, ty)?.let { return Edit.Stretch(chosen.id, it, chosen.box) }
                }
                val slack = (6.dp.toPx() / size.width.coerceAtLeast(1)).toDouble()
                PhotoOcclusion.hit(ax, ay, nowCovers, slack)?.let { index ->
                    val cover = nowCovers[index]
                    select(cover.id)
                    return Edit.Move(cover.id, cover.box)
                }
                return Edit.Draw(ax, ay)
            }
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                down.consume()
                val start = down.position
                val edit = begin(start)
                fun changed(at: Offset) {
                    val dx = ((at.x - start.x) / size.width.coerceAtLeast(1)).toDouble()
                    val dy = ((at.y - start.y) / size.height.coerceAtLeast(1)).toDouble()
                    when (edit) {
                        is Edit.Move -> set(edit.id, PhotoOcclusion.moved(edit.from, dx, dy))
                        is Edit.Stretch -> set(edit.id, PhotoOcclusion.resized(edit.from, edit.corner, dx, dy))
                        is Edit.Draw -> { val (ex, ey) = fraction(at); drawing = PhotoOcclusion.drawn(edit.x, edit.y, ex, ey) }
                    }
                }
                changed(start)
                var last = start
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                    if (change.positionChange() != Offset.Zero) { last = change.position; changed(last) }
                    change.consume()
                    if (!change.pressed) break
                }
                if (edit is Edit.Draw) {
                    val box = drawing
                    if (box != null) {
                        val made = PhotoOcclusion.Cover(box = box, answer = "")
                        setCovers(nowCovers + made)
                        select(made.id)
                    } else select(null) // a tap on the picture itself
                    drawing = null
                }
            }
        }) {
            covers.forEach { cover -> drawCover(cover, cover.id == selected, tint, beam, surface) }
            drawing?.let { box ->
                val (o, s) = rect(box)
                drawRect(tint.copy(alpha = 0.2f), o, s)
                drawRect(tint, o, s, style = Stroke(2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx()))))
            }
        }
    }
}

private fun DrawScope.rect(box: OcclusionBox): Pair<Offset, Size> =
    Offset((box.x * size.width).toFloat(), (box.y * size.height).toFloat()) to Size((box.w * size.width).toFloat(), (box.h * size.height).toFloat())

private fun DrawScope.drawCover(cover: PhotoOcclusion.Cover, chosen: Boolean, tint: Color, beam: Color, surface: Color) {
    val (o, s) = rect(cover.box)
    val answered = PhotoOcclusion.tidied(cover.answer).isNotEmpty()
    // Pager Amber: a strong warm colour that still shows on a photo
    val fill = if (chosen) tint.copy(alpha = 0.35f) else beam.copy(alpha = if (answered) 0.35f else 0.15f)
    val edge = if (chosen) tint else beam
    val width = (if (chosen) 2.5f else 1.5f).dp.toPx()
    drawRect(fill, o, s)
    // strokeBorder: the line inside the box
    val inner = Offset(o.x + width / 2, o.y + width / 2)
    val innerSize = Size((s.width - width).coerceAtLeast(0f), (s.height - width).coerceAtLeast(0f))
    drawRect(edge, inner, innerSize, style = Stroke(width, pathEffect = if (answered) null else PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))))
    if (chosen) {
        val r = HANDLE_SIZE.dp.toPx() / 2
        listOf(o, Offset(o.x + s.width, o.y), Offset(o.x, o.y + s.height), Offset(o.x + s.width, o.y + s.height)).forEach { c ->
            drawCircle(surface, r, c)
            drawCircle(tint, r - 1.25.dp.toPx(), c, style = Stroke(2.5.dp.toPx()))
        }
    }
}
