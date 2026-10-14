package com.stethoscore.app.export

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.util.Base64
import com.stethoscore.app.data.StudySet
import java.io.OutputStream

/**
 * Writes a set as a printable flashcard deck: a cover, a contents index, then one question
 * to a page with its answer on the very next page, so nothing is spoiled while you test
 * yourself. Every page carries the mode's colour. Port of ios/RedPen/Shared/DeckPDF*.swift;
 * Android's PdfDocument has no link annotations, so the index lists page numbers instead
 * of tappable links.
 */
object DeckPdf {
    const val PAGE_W = 595
    const val PAGE_H = 842
    private const val MARGIN = 46f
    private const val BAR = 34f
    private const val BASE_SIZE = 13.5f
    private const val CONTENT_TOP = MARGIN + BAR + 74f
    private val questionPictureLimit = PAGE_H * 0.42f
    private val answerPictureLimit = PAGE_H * 0.36f

    fun fileName(set: StudySet) = set.name.replace(Regex("[^A-Za-z0-9 _-]"), "").trim().ifEmpty { "Stethoscore deck" } + ".pdf"

    /** Writes the deck; returns the number of pages, or throws for a set that does not print. */
    fun write(set: StudySet, out: OutputStream): Int {
        require(DeckBuilder.printsAsPdf(set.kind)) { "Card decks keep their schedule and masks only as a deck file, so they are not printed." }
        val cards = DeckBuilder.cards(set)
        require(cards.isNotEmpty()) { "This set has nothing to print yet." }
        val palette = DeckPalette.of(set.kind)
        val pictures = HashMap<Int, Bitmap?>()
        fun picture(index: Int?): Bitmap? = index?.let { i -> pictures.getOrPut(i) { decode(set.images.getOrNull(i)) } }

        val width = PAGE_W - 2 * MARGIN
        val questionScale = DeckFit.scale(cards.map { PAGE_H - MARGIN - top(picture(it.imageIndex), questionPictureLimit) }) { i, s ->
            height(cards[i].question, palette, BASE_SIZE * s, width)
        }
        val answerScale = DeckFit.scale(cards.map { PAGE_H - MARGIN - 30 - CONTENT_TOP }) { i, s -> height(cards[i].answer, palette, BASE_SIZE * s, width) }

        val doc = PdfDocument()
        var pageNumber = 0
        fun page(draw: (Canvas) -> Unit) {
            pageNumber++
            val p = doc.startPage(PdfDocument.PageInfo.Builder(PAGE_W, PAGE_H, pageNumber).create())
            draw(p.canvas)
            doc.finishPage(p)
        }
        try {
            page { cover(it, set, cards.size, palette) }
            val rows = DeckIndex.rows(cards)
            val perPage = 30
            val indexPages = (rows.size + perPage - 1) / perPage
            val firstCardPage = 2 + indexPages
            rows.chunked(perPage).forEachIndexed { k, chunk -> page { contents(it, set, chunk, k == 0, palette, firstCardPage) } }
            for (card in cards) {
                page { c ->
                    header(c, set, card, palette, "QUESTION")
                    var y = CONTENT_TOP
                    picture(card.imageIndex)?.let { y = drawPicture(c, it, y, questionPictureLimit) }
                    drawBlocks(c, card.question, y, palette, BASE_SIZE * questionScale, width)
                    footer(c, card, cards.size, palette, "Answer on the next page")
                }
                page { c ->
                    header(c, set, card, palette, "ANSWER")
                    val y = drawBlocks(c, card.answer, CONTENT_TOP, palette, BASE_SIZE * answerScale, width)
                    card.source?.let { source -> text(c, source, MARGIN, y + 10, width, 9f, 0xFF6B7280.toInt(), italic = true) }
                    footer(c, card, cards.size, palette, "")
                }
            }
            doc.writeTo(out)
        } finally {
            doc.close()
        }
        return pageNumber
    }

    // ---- pages ----

    private fun cover(c: Canvas, set: StudySet, count: Int, palette: DeckPalette) {
        val fill = Paint().apply { color = palette.argb() }
        c.drawRect(0f, 0f, PAGE_W.toFloat(), PAGE_H * 0.38f, fill)
        text(c, set.kind.label.uppercase(), MARGIN, 70f, PAGE_W - 2 * MARGIN, 11f, 0xFFFFFFFF.toInt(), bold = true)
        val h = text(c, set.name, MARGIN, 100f, PAGE_W - 2 * MARGIN, 30f, 0xFFFFFFFF.toInt(), bold = true)
        text(c, set.subject, MARGIN, 108f + h, PAGE_W - 2 * MARGIN, 14f, palette.tint(0.75).argb())
        val y = PAGE_H * 0.38f + 40
        text(c, "$count cards · question on one page, answer on the next", MARGIN, y, PAGE_W - 2 * MARGIN, 13f, 0xFF1F2937.toInt())
        text(c, "Cover the next page, answer out loud, then turn over.", MARGIN, y + 24, PAGE_W - 2 * MARGIN, 11f, 0xFF4B5563.toInt())
        text(c, "Stethoscore is a study aid. Source material has not been independently verified for clinical use.", MARGIN, PAGE_H - MARGIN - 24, PAGE_W - 2 * MARGIN, 9f, 0xFF6B7280.toInt())
    }

    private fun contents(c: Canvas, set: StudySet, rows: List<DeckIndexRow>, first: Boolean, palette: DeckPalette, firstCardPage: Int) {
        text(c, if (first) "Contents" else "Contents (continued)", MARGIN, MARGIN, PAGE_W - 2 * MARGIN, 22f, palette.shade().argb(), bold = true)
        var y = MARGIN + 44
        val rule = Paint().apply { color = palette.tint(0.8).argb(); strokeWidth = 0.6f }
        for (row in rows) {
            text(c, row.topic, MARGIN, y, PAGE_W - 2 * MARGIN - 130, 11.5f, 0xFF1F2937.toInt())
            val pages = "cards ${row.range} · p. ${firstCardPage + (row.first - 1) * 2}"
            text(c, pages, PAGE_W - MARGIN - 125, y, 125f, 10f, palette.shade().argb(), align = Layout.Alignment.ALIGN_OPPOSITE)
            y += 22
            c.drawLine(MARGIN, y - 6, PAGE_W - MARGIN, y - 6, rule)
        }
    }

    private fun header(c: Canvas, set: StudySet, card: DeckCard, palette: DeckPalette, side: String) {
        c.drawRect(RectF(0f, 0f, PAGE_W.toFloat(), MARGIN + BAR - 12), Paint().apply { color = palette.argb() })
        text(c, set.name, MARGIN, 18f, PAGE_W - 2 * MARGIN - 120, 10f, 0xFFFFFFFF.toInt(), bold = true, maxLines = 1)
        text(c, "${card.number} · $side", PAGE_W - MARGIN - 120, 18f, 120f, 10f, 0xFFFFFFFF.toInt(), bold = true, align = Layout.Alignment.ALIGN_OPPOSITE)
        // the topic and a chip with the card's kind
        val chip = Paint().apply { color = palette.tint().argb() }
        c.drawRoundRect(RectF(MARGIN, MARGIN + BAR, MARGIN + 60, MARGIN + BAR + 18), 9f, 9f, chip)
        text(c, card.kindLabel, MARGIN, MARGIN + BAR + 3, 60f, 8.5f, palette.shade().argb(), bold = true, align = Layout.Alignment.ALIGN_CENTER)
        text(c, card.topic, MARGIN, MARGIN + BAR + 28, PAGE_W - 2 * MARGIN, 15f, palette.shade().argb(), bold = true, maxLines = 2)
    }

    private fun footer(c: Canvas, card: DeckCard, total: Int, palette: DeckPalette, hint: String) {
        text(c, "${card.number} of $total", MARGIN, PAGE_H - MARGIN + 10, 120f, 9f, 0xFF6B7280.toInt())
        if (hint.isNotEmpty()) text(c, hint, PAGE_W - MARGIN - 200, PAGE_H - MARGIN + 10, 200f, 9f, palette.shade().argb(), align = Layout.Alignment.ALIGN_OPPOSITE)
    }

    // ---- blocks ----

    private fun top(picture: Bitmap?, limit: Float) = CONTENT_TOP + (picture?.let { pictureHeight(it, limit) + 14 } ?: 0f)

    private fun pictureHeight(b: Bitmap, limit: Float): Float {
        val w = PAGE_W - 2 * MARGIN
        return minOf(limit, b.height * (w / b.width))
    }

    private fun drawPicture(c: Canvas, b: Bitmap, y: Float, limit: Float): Float {
        val h = pictureHeight(b, limit)
        val w = b.width * (h / b.height)
        val x = (PAGE_W - w) / 2
        c.drawBitmap(b, null, RectF(x, y, x + w, y + h), Paint(Paint.FILTER_BITMAP_FLAG))
        return y + h + 14
    }

    /** Heights as drawn, for the fit; measured with the same layouts that draw. */
    fun height(blocks: List<DeckBlock>, palette: DeckPalette, size: Float, width: Float): Float =
        blocks.sumOf { layoutOf(it, palette, size, width).let { l -> (l.height + gap(size)).toDouble() } }.toFloat()

    private fun drawBlocks(c: Canvas, blocks: List<DeckBlock>, top: Float, palette: DeckPalette, size: Float, width: Float): Float {
        var y = top
        for (block in blocks) {
            val layout = layoutOf(block, palette, size, width)
            if (block is DeckBlock.Option && block.correct) {
                val band = Paint().apply { color = palette.tint(0.84).argb() }
                c.drawRoundRect(RectF(MARGIN - 6, y - 4, MARGIN + width + 6, y + layout.height + 4), 8f, 8f, band)
            }
            c.save(); c.translate(MARGIN, y); layout.draw(c); c.restore()
            y += layout.height + gap(size)
        }
        return y
    }

    private fun gap(size: Float) = size * 0.75f

    private fun layoutOf(block: DeckBlock, palette: DeckPalette, size: Float, width: Float): StaticLayout {
        val text = SpannableStringBuilder()
        val accent = palette.shade().argb()
        fun lead(s: String) {
            val start = text.length; text.append(s)
            text.setSpan(ForegroundColorSpan(accent), start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            text.setSpan(StyleSpan(Typeface.BOLD), start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        var textSize = size
        var color = 0xFF111827.toInt()
        when (block) {
            is DeckBlock.Text -> { text.append(DeckBuilder.plain(block.text)); textSize = size * 1.25f }
            is DeckBlock.Bullet -> {
                text.append("•  ")
                if (!block.lead.isNullOrBlank()) { lead(block.lead); if (block.text.isNotBlank()) text.append("  ") }
                text.append(DeckBuilder.plain(block.text))
            }
            is DeckBlock.Option -> {
                lead(block.letter + "   ")
                text.append(DeckBuilder.plain(block.text))
                if (block.correct) text.append("   ✓")
            }
            is DeckBlock.Note -> {
                lead(block.label + "  ")
                text.append(DeckBuilder.plain(block.text))
                textSize = size * 0.9f; color = 0xFF374151.toInt()
            }
        }
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { this.textSize = textSize; this.color = color }
        return StaticLayout.Builder.obtain(text, 0, text.length, paint, width.toInt()).setLineSpacing(0f, 1.18f).build()
    }

    private fun text(c: Canvas, s: String, x: Float, y: Float, width: Float, size: Float, color: Int, bold: Boolean = false, italic: Boolean = false,
                     align: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL, maxLines: Int = Int.MAX_VALUE): Float {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size; this.color = color
            typeface = Typeface.create(Typeface.DEFAULT, when { bold && italic -> Typeface.BOLD_ITALIC; bold -> Typeface.BOLD; italic -> Typeface.ITALIC; else -> Typeface.NORMAL })
        }
        val layout = StaticLayout.Builder.obtain(s, 0, s.length, paint, width.toInt().coerceAtLeast(1)).setAlignment(align)
            .setMaxLines(maxLines).setEllipsize(if (maxLines == Int.MAX_VALUE) null else android.text.TextUtils.TruncateAt.END).build()
        c.save(); c.translate(x, y); layout.draw(c); c.restore()
        return layout.height.toFloat()
    }

    private fun decode(encoded: String?): Bitmap? = runCatching {
        if (encoded == null || encoded.startsWith("blob:")) null else {
            val bytes = Base64.decode(encoded.substringAfter("base64,", encoded), Base64.DEFAULT)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }
    }.getOrNull()
}
