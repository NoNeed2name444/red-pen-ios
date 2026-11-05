package com.stethoscore.app.widget

import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardType
import kotlin.math.ceil

// How much room the widgets' words and numbers take, in plain Kotlin, so every
// face is checked at every size on the JVM (WidgetFitTest). A launcher's
// RemoteViews cannot shrink text to fit, as iOS's minimumScaleFactor does, so
// each face picks its number size, its caption and its one-line words from
// these figures before Glance draws it. Widget text is in sp, so it grows with
// the reader's font size: every size is measured in the dp the platform turns
// its sp into at the system's font scale (TextScale).

/**
 * Roboto, the face Glance's text draws in: its advance widths, in 1/2048 em,
 * and its line heights with the font padding Glance's Text keeps (a line
 * stands [above] em over its baseline and [below] em under it, each further
 * line adds [lineStep] em, and each line draws up to [lineRounding] dp more;
 * the round digits' tops are [digits] em up and the en dash's ink runs from
 * [dashFoot] to [dash] em up, Roboto Bold's own bounds). Checked against
 * Android CI run 42014339195's widget pictures and T0206's measurements of
 * them (WidgetFitTest). Sizes here are in dp.
 */
object WidgetText {
    const val above = 1.0566
    const val below = 0.2715
    const val lineStep = 1.172
    /** 0, 2, 3, 8 and 9 overshoot the flat digits' 0.711 em. */
    const val digits = 0.721
    const val dash = 0.405
    const val dashFoot = 0.294
    /**
     * Android rounds a line's top and foot out to whole pixels, so a line draws
     * up to about a pixel taller at each: 0.6 dp a line keeps the model at or
     * over the heights CI's pictures measured, and its clearances at or under
     * the measured ones.
     */
    const val lineRounding = 0.6

    /** Widths are rounded up: regular by 2 %; bold, which measured about 4 % wider than regular, by 6 %. */
    const val regularSlack = 1.02
    const val boldSlack = 1.06

    private val advance: Map<Char, Int> = buildMap {
        "abcdefghijklmnopqrstuvwxyz".toList().zip(listOf(1088, 1122, 1046, 1128, 1058, 694, 1122, 1102, 486, 477, 1014, 486, 1754,
            1104, 1140, 1122, 1128, 677, 1031, 654, 1102, 968, 1502, 991, 945, 991)).forEach { (c, w) -> put(c, w) }
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ".toList().zip(listOf(1336, 1275, 1333, 1343, 1164, 1132, 1395, 1460, 557, 1130, 1284, 1102, 1788,
            1460, 1408, 1292, 1408, 1260, 1217, 1222, 1328, 1302, 1817, 1284, 1230, 1226)).forEach { (c, w) -> put(c, w) }
        "0123456789".forEach { put(it, 1150) }
        mapOf(' ' to 507, '.' to 539, ',' to 402, ':' to 496, ';' to 433, '/' to 844, '-' to 565, '–' to 1350,
            '—' to 1590, '’' to 400, '‘' to 400, '\'' to 357, '(' to 700, ')' to 712, '!' to 527,
            '?' to 967, '&' to 1272, '+' to 1134, '%' to 1500, '#' to 1229).forEach { (c, w) -> put(c, w) }
    }

    /** A letter the table lacks: 0.6 em, or a full em for CJK. */
    private fun units(c: Char): Int = advance[c] ?: if (c.code >= 0x2E80) 2048 else 1229

    /** How wide [text] draws at [size] dp. */
    fun width(text: String, size: Double, bold: Boolean): Double =
        text.sumOf { units(it) } / 2048.0 * size * (if (bold) boldSlack else regularSlack)

    /** How many lines [text] at [size] dp takes in [widthDp], broken at spaces, a word wider than the line broken inside it. */
    fun lines(text: String, size: Double, bold: Boolean, widthDp: Double): Int {
        val space = width(" ", size, bold)
        var lines = 1
        var used = 0.0
        for (word in text.split(' ').filter { it.isNotEmpty() }) {
            val w = width(word, size, bold)
            when {
                used == 0.0 -> used = w
                used + space + w <= widthDp -> used += space + w
                else -> { lines++; used = w }
            }
            if (used > widthDp) {
                lines += ceil(used / widthDp).toInt() - 1
                used = used % widthDp
            }
        }
        return lines
    }

    /** How tall [lines] lines of [size] dp text draw, in dp. */
    fun height(size: Double, lines: Int = 1): Double = size * (above + below) + (lines - 1) * size * lineStep + lines * lineRounding
}

/**
 * How a text's sp become dp at the system's font size. The widgets take the
 * platform's own conversion (GlanceWidgets): sp times the font scale below
 * API 34; from Android 14 a curve, on which large text grows less than small.
 */
fun interface TextScale {
    fun dp(sp: Double): Double

    companion object {
        /** sp times [fontScale]: Android's conversion below API 34. */
        fun linear(fontScale: Double): TextScale = TextScale { it * fontScale }
    }
}

/** The room a face has inside its margins, in dp. */
data class FaceRoom(val width: Double, val height: Double) {
    companion object {
        /** A 2x2: 16 dp at the sides, 12 above and below. */
        fun small(widthDp: Double, heightDp: Double) =
            FaceRoom(widthDp - 2 * WidgetStyle.margin, heightDp - 2 * WidgetStyle.smallVerticalMargin)

        /** The medium Due widget's left column: half of what is left after the margins and the 16 dp between the columns. */
        fun mediumLeft(widthDp: Double, heightDp: Double) =
            FaceRoom((widthDp - 3 * WidgetStyle.margin) / 2, heightDp - 2 * WidgetStyle.mediumVerticalMargin)

        /** The one-line size: 16 dp at the sides, [vertical] above and below (8, or less at a large font: OneLineFit.margin). */
        fun oneLine(widthDp: Double, heightDp: Double, vertical: Double = WidgetStyle.mediumVerticalMargin) =
            FaceRoom(widthDp - 2 * WidgetStyle.margin, heightDp - 2 * vertical)
    }
}

/**
 * What the big number's stack draws: the caption and the lines it is held to
 * (its maxLines) with their height in dp, the number's size in sp, whether the
 * glyph is drawn, and, for the en dash, how far below a number's place it is
 * drawn (NumberStack.dashDrop; 0 for a number). [lastResort]: nothing fitted
 * whole, so the number is at the largest of NumberStack.lastResortSizes at
 * which its digits fit whole, and the caption is held to the lines that fit,
 * which Glance's Text ends with an ellipsis.
 */
data class StackFit(
    val caption: String,
    val captionLines: Int,
    val numberSize: Double,
    val captionHeight: Double,
    val dashDrop: Double,
    val glyph: Boolean,
    val lastResort: Boolean,
)

/**
 * The big number's stack (iOS's bigCount): the glyph at the top, the number
 * and its caption at the foot. The glyph stands in the number's top line
 * padding, where nothing is drawn, so it needs room only above the number's
 * ink: at least [WidgetStyle.gap] of it, as iOS's stack keeps its spacing.
 * The glyph is decorative, so where no number size keeps that gap it gives
 * way, before anything the face says is cut.
 */
object NumberStack {
    /** The caption's most lines, as iOS's lineLimit(2). */
    const val captionLines = 2

    /** iOS's 44 sp first, then the Ward title sizes down to 22, half of it, as far as iOS's minimumScaleFactor(0.5) goes. */
    val numberSizes: List<Double> = listOf(WidgetStyle.numberSize, WardTextStyle.largeTitle.size, WardTextStyle.title.size, WardTextStyle.title2.size)

    /**
     * The last resort's sizes: the ladder's 22 sp foot, then the Ward sizes
     * from headline's 17 down to the caption's 12. A count is never cut, as
     * "12…" reads as twelve, so there the number goes on below iOS's floor
     * until its digits fit whole.
     */
    val lastResortSizes: List<Double> = listOf(WardTextStyle.title2.size, WardTextStyle.headline.size, WardTextStyle.callout.size,
        WardTextStyle.subheadline.size, WardTextStyle.footnote.size, WardTextStyle.caption.size)

    private val captionSize: Double get() = WardType.caption.size

    /** How tall [lines] lines of caption draw at the font [scale], in dp. */
    fun captionHeight(lines: Int, scale: TextScale): Double = WidgetText.height(scale.dp(captionSize), lines)

    /**
     * How far the en dash, at [numberSp] and the font [scale], is drawn below
     * a number's place, in dp. A digit's ink stands on its baseline and the
     * dash's [WidgetText.dashFoot] em over it, so the dash comes down by that
     * much, into the caption's top line padding, where nothing is drawn, and
     * its foot is as far from the caption as a number's.
     */
    fun dashDrop(numberSp: Double, scale: TextScale): Double = scale.dp(numberSp) * WidgetText.dashFoot

    /** How far above the number's box the room goes on, in dp; below 0 the boxes do not fit and Android squeezes the caption. */
    fun headroom(roomHeight: Double, numberSp: Double, captionLines: Int, dash: Boolean, scale: TextScale): Double {
        val foot = captionHeight(captionLines, scale) - if (dash) dashDrop(numberSp, scale) else 0.0
        return roomHeight - foot - WidgetText.height(scale.dp(numberSp))
    }

    /**
     * The gap between the glyph's foot and the top of the number's ink when
     * the number, at [numberSp], and [captionLines] of caption stand at the
     * foot of [roomHeight], at the font [scale]; below 0 they meet.
     */
    fun clearance(roomHeight: Double, numberSp: Double, captionLines: Int, dash: Boolean, scale: TextScale): Double {
        val size = scale.dp(numberSp)
        val inkTop = size * (WidgetText.above - if (dash) WidgetText.dash else WidgetText.digits)
        return headroom(roomHeight, numberSp, captionLines, dash, scale) + inkTop - WidgetStyle.glyph
    }

    /**
     * The first of [captions] that fits two lines of [room] (the last one
     * otherwise) and, measured at the system's font [scale], the largest
     * number size that fits across the room with the caption under it and
     * [WidgetStyle.gap] below the glyph; else the largest that fits without
     * the glyph; else the last resort: the largest of [lastResortSizes] whose
     * digits fit across whole with a line of caption under them, the caption
     * held to the lines that fit, ended with an ellipsis. The number itself
     * is never ended with one: it is drawn at a size it fits.
     */
    fun fit(number: String, captions: List<String>, room: FaceRoom, scale: TextScale): StackFit {
        fun linesOf(text: String) = WidgetText.lines(text, scale.dp(captionSize), bold = false, widthDp = room.width)
        val caption = captions.firstOrNull { linesOf(it) <= captionLines } ?: captions.last()
        val needed = linesOf(caption)
        val dash = number == WidgetWords.noNumber
        fun across(size: Double) = WidgetText.width(number, scale.dp(size), bold = true) <= room.width
        fun stands(size: Double, lines: Int) = headroom(room.height, size, lines, dash, scale) >= 0
        fun clear(size: Double, lines: Int) = clearance(room.height, size, lines, dash, scale) >= WidgetStyle.gap
        fun stack(size: Double, lines: Int, glyph: Boolean, lastResort: Boolean) =
            StackFit(caption, lines, size, captionHeight(lines, scale), if (dash) dashDrop(size, scale) else 0.0, glyph, lastResort)
        if (needed <= captionLines) {
            numberSizes.firstOrNull { across(it) && stands(it, needed) && clear(it, needed) }?.let { return stack(it, needed, glyph = true, lastResort = false) }
            numberSizes.firstOrNull { across(it) && stands(it, needed) }?.let { return stack(it, needed, glyph = false, lastResort = false) }
        }
        // where even 12 sp is too wide, or too tall for a line of caption, the test that sweeps every face names it
        val size = lastResortSizes.firstOrNull { across(it) && stands(it, 1) } ?: lastResortSizes.firstOrNull { across(it) } ?: lastResortSizes.last()
        val lines = (minOf(needed, captionLines) downTo 1).firstOrNull { stands(size, it) } ?: 1
        return stack(size, lines, glyph = clear(size, lines), lastResort = true)
    }
}

/** The one-line sizes' words: the first form that fits the line at the system's font scale, else the shortest, ended with an ellipsis. */
object OneLineFit {
    /** How short a one-line widget can be made (widget_countdown.xml, widget_today.xml); Responsive hands it the 48 dp layout. */
    const val leastHeight = 40.0

    /** How tall the line draws at the font [scale], in dp. */
    fun lineHeight(scale: TextScale): Double = WidgetText.height(scale.dp(WidgetStyle.lineFace.size))

    /**
     * The margin above and below the line: 8 dp, less where the line at the
     * font [scale] is taller than a 40 dp widget leaves inside them, so it is
     * never squeezed. The line is centred, so the margin shows only then.
     */
    fun margin(scale: TextScale): Double = ((leastHeight - lineHeight(scale)) / 2).coerceIn(0.0, WidgetStyle.mediumVerticalMargin)

    fun fits(text: String, room: FaceRoom, scale: TextScale): Boolean =
        WidgetText.width(text, scale.dp(WidgetStyle.lineFace.size), bold = true) <= room.width && lineHeight(scale) <= room.height

    fun pick(forms: List<String>, room: FaceRoom, scale: TextScale): String = forms.firstOrNull { fits(it, room, scale) } ?: forms.last()
}

/**
 * Done today's one-line words: its forms, then, with a file, the count alone.
 * The shortest form is ended with an ellipsis where none fits, and a cut
 * count misreads ("1200/3…", or "120…" at 2.0x), so the count, which fits
 * the line at every font scale (WidgetFitTest), comes last.
 */
val TodayFace.oneLineForms: List<String> get() = if (hasFile) lineForms + number else lineForms
