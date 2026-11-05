package com.stethoscore.app.widget

import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardType
import kotlin.math.ceil

// How much room the widgets' words and numbers take, in plain Kotlin, so every
// face is checked at every size on the JVM (WidgetFitTest). A launcher's
// RemoteViews cannot shrink text to fit, as iOS's minimumScaleFactor does, so
// each face picks its number size, its caption and its one-line words from
// these figures before Glance draws it.

/**
 * Roboto, the face Glance's text draws in: its advance widths, in 1/2048 em,
 * and its line heights with the font padding Glance's Text keeps (a line
 * stands [above] em over its baseline and [below] em under it, each further
 * line adds [lineStep] em; digits are [digits] em tall and the en dash's top
 * is [dash] em up). Checked against Android CI run 42014339195's widget
 * pictures (WidgetFitTest).
 */
object WidgetText {
    const val above = 1.0566
    const val below = 0.2715
    const val lineStep = 1.172
    const val digits = 0.711
    const val dash = 0.40

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

    /** How wide [text] draws at [sp], in dp. */
    fun width(text: String, sp: Double, bold: Boolean): Double =
        text.sumOf { units(it) } / 2048.0 * sp * (if (bold) boldSlack else regularSlack)

    /** How many lines [text] takes in [widthDp], broken at spaces, a word wider than the line broken inside it. */
    fun lines(text: String, sp: Double, bold: Boolean, widthDp: Double): Int {
        val space = width(" ", sp, bold)
        var lines = 1
        var used = 0.0
        for (word in text.split(' ').filter { it.isNotEmpty() }) {
            val w = width(word, sp, bold)
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

    /** How tall [lines] lines of [sp] text draw, in dp. */
    fun height(sp: Double, lines: Int = 1): Double = sp * (above + below) + (lines - 1) * sp * lineStep
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

        /** The one-line size: 16 dp at the sides, 8 above and below. */
        fun oneLine(widthDp: Double, heightDp: Double) =
            FaceRoom(widthDp - 2 * WidgetStyle.margin, heightDp - 2 * WidgetStyle.mediumVerticalMargin)
    }
}

/** What the big number's stack draws: the caption, its lines, and the number's size. */
data class StackFit(val caption: String, val captionLines: Int, val numberSize: Double)

/**
 * The big number's stack (iOS's bigCount): the glyph at the top, the number
 * and its caption at the foot. The glyph stands in the number's top line
 * padding, where nothing is drawn, so it needs room only above the number's ink.
 */
object NumberStack {
    /** The caption's most lines, as iOS's lineLimit(2). */
    const val captionLines = 2

    /** iOS's 44 sp first, then the Ward title sizes down to 22, half of it, as far as iOS's minimumScaleFactor(0.5) goes. */
    val numberSizes: List<Double> = listOf(WidgetStyle.numberSize, WardTextStyle.largeTitle.size, WardTextStyle.title.size, WardTextStyle.title2.size)

    private val captionSize: Double get() = WardType.caption.size

    /**
     * The gap between the glyph's foot and the top of the number's ink when
     * the number, at [numberSp], and [captionLines] of caption stand at the
     * foot of [roomHeight]; below 0 they meet. The en dash's ink sits low.
     */
    fun clearance(roomHeight: Double, numberSp: Double, captionLines: Int, dash: Boolean): Double {
        val numberTop = roomHeight - WidgetText.height(captionSize, captionLines) - WidgetText.height(numberSp)
        val inkTop = numberSp * (WidgetText.above - if (dash) WidgetText.dash else WidgetText.digits)
        return numberTop + inkTop - WidgetStyle.glyph
    }

    /**
     * The first of [captions] that fits two lines of [room] (the last one
     * otherwise), and the largest number size that fits beside the glyph and
     * across the room.
     */
    fun fit(number: String, captions: List<String>, room: FaceRoom): StackFit {
        fun linesOf(text: String) = WidgetText.lines(text, captionSize, bold = false, widthDp = room.width)
        val caption = captions.firstOrNull { linesOf(it) <= captionLines } ?: captions.last()
        val lines = linesOf(caption).coerceAtMost(captionLines)
        val dash = number == WidgetWords.noNumber
        val size = numberSizes.firstOrNull {
            WidgetText.width(number, it, bold = true) <= room.width && clearance(room.height, it, lines, dash) >= 0
        } ?: numberSizes.last()
        return StackFit(caption, lines, size)
    }
}

/** The one-line sizes' words: the first form that fits the line, the shortest otherwise. */
object OneLineFit {
    fun fits(text: String, room: FaceRoom): Boolean =
        WidgetText.width(text, WidgetStyle.lineFace.size, bold = true) <= room.width &&
            WidgetText.height(WidgetStyle.lineFace.size) <= room.height

    fun pick(forms: List<String>, room: FaceRoom): String = forms.firstOrNull { fits(it, room) } ?: forms.last()
}
