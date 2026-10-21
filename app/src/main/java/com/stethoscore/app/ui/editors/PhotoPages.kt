package com.stethoscore.app.ui.editors

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.media.ExifInterface
import android.net.Uri
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.stethoscore.app.data.PhotoOcclusion
import com.stethoscore.app.data.newId
import java.io.ByteArrayOutputStream

// The device half of picture cards from a photo (iOS PhotoOcclusionReader.swift
// and DocumentScannerSheet.swift, fed0105): a picture is decoded, turned
// upright, shrunk to 2,048 pixels on its long side (PhotoOcclusion.fitted),
// flattened onto white and kept as a JPEG. Slow work, only ever called off the
// main thread.
//
// iOS then reads the labels with Vision and covers each one. Android has no
// on-device text reader in this build (ML Kit is not among its libraries), so
// a page arrives with no words read and no covers: the student draws them,
// which is the path iOS takes when Vision finds no labels.

/** The system document camera. iOS shows "Scan pages" only where VisionKit can scan. */
object DocumentScanning {
    /**
     * Whether "Scan pages" is offered. Android's nearest way is ML Kit's
     * document scanner, which is not among this build's libraries, so the
     * tile is not shown and Photos and Files do the job, as in iOS's Swift
     * Playgrounds build.
     */
    const val isAvailable: Boolean = false
}

/** One picture being turned into cards (iOS PhotoPage). */
data class PhotoPage(
    val id: String = newId(),
    /** The picture as it will be kept: a JPEG, at most 2,048 pixels across. */
    val jpeg: ByteArray,
    val preview: ImageBitmap?,
    val pixelWidth: Int,
    val pixelHeight: Int,
    /** What was read, line by line (nothing yet on Android). */
    val lines: List<String>,
    val covers: List<PhotoOcclusion.Cover>,
    /** A page from the document camera: a whole page, with a title and a footer that are not labels. */
    val scanned: Boolean,
) {
    /** Width over height, for drawing and for a new cover's shape. */
    val aspect: Double get() = if (pixelHeight > 0) pixelWidth.toDouble() / pixelHeight else 1.0
    /** The page's words, one line each, for the lecture it can become. */
    val text: String get() = PhotoOcclusion.pageText(lines)

    override fun equals(other: Any?): Boolean = other is PhotoPage && other.id == id && other.covers == covers
    override fun hashCode(): Int = id.hashCode()
}

object PhotoPages {
    /** Where the covers are looked for (iOS PhotoOcclusionReader.Placement). */
    enum class Placement { wholePicture, diagramOnly }

    /** A picture from Photos or Files: decoded to its kept size, turned upright, read. Null when it is not a picture. */
    fun read(context: Context, uri: Uri, scanned: Boolean): PhotoPage? = runCatching {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return null
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= PhotoOcclusion.maxSide) sample *= 2
        val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) } ?: return null
        val turn = resolver.openInputStream(uri)?.use { runCatching { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }.getOrNull() }
            ?: ExifInterface.ORIENTATION_NORMAL
        page(upright(decoded, turn), scanned)
    }.getOrNull()

    /** The covers placed again, another way, from what was already read: none where nothing was read. */
    fun replaced(page: PhotoPage, placement: Placement): List<PhotoOcclusion.Cover> {
        if (page.lines.isEmpty()) return emptyList()
        return page.covers
    }

    private fun upright(bitmap: Bitmap, orientation: Int): Bitmap {
        val m = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { m.postRotate(90f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { m.postRotate(270f); m.postScale(-1f, 1f) }
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
    }

    /** The shared route once a picture is decoded: shrunk, flattened onto white, kept as a JPEG. */
    fun page(bitmap: Bitmap, scanned: Boolean): PhotoPage? {
        val (w, h) = PhotoOcclusion.fitted(bitmap.width, bitmap.height)
        if (w == 0 || h == 0) return null
        val flat = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        Canvas(flat).apply {
            drawColor(Color.WHITE)
            drawBitmap(Bitmap.createScaledBitmap(bitmap, w, h, true), 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG))
        }
        val jpeg = ByteArrayOutputStream().use { out -> flat.compress(Bitmap.CompressFormat.JPEG, 85, out); out.toByteArray() }
        val preview = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)?.asImageBitmap()
        return PhotoPage(jpeg = jpeg, preview = preview, pixelWidth = w, pixelHeight = h, lines = emptyList(), covers = emptyList(), scanned = scanned)
    }
}
