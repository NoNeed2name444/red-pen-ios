package com.stethoscore.app.data

import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone
import kotlin.math.abs

// A port of ios/RedPen/Tests/PhotoOcclusionTests.swift (fed0105), case
// for case and number for number: the size a picture is kept at, covers
// dragged, stretched, drawn and hit, and the cards the covers make.
class PhotoOcclusionTest {
    private val PO = PhotoOcclusion
    private fun near(a: Double, b: Double) = abs(a - b) < 1e-9
    private fun inPicture(box: OcclusionBox): Boolean {
        val right = box.x + box.w
        val bottom = box.y + box.h
        return box.x >= -1e-9 && box.y >= -1e-9 && right <= 1 + 1e-9 && bottom <= 1 + 1e-9
    }
    private fun check(label: String, ok: Boolean, detail: Any? = null) = assertTrue(if (detail == null) label else "$label  | $detail", ok)

    @Test fun downscale() {
        val phone = PO.fitted(4032, 3024)
        check("a phone photo is shrunk to 2048 on its long side", phone.first == 2048 && phone.second == 1536, phone)
        val tall = PO.fitted(1170, 2532)
        check("a screenshot is shrunk by its height", tall.second == 2048 && tall.first == 946, tall)
        val small = PO.fitted(800, 600)
        check("a small picture is never enlarged", small.first == 800 && small.second == 600)
        val exact = PO.fitted(2048, 10)
        check("exactly 2048 is kept", exact.first == 2048 && exact.second == 10)
        val sliver = PO.fitted(20000, 3)
        check("a sliver keeps at least a pixel", sliver.first == 2048 && sliver.second == 1, sliver)
        val none = PO.fitted(0, 100)
        check("an empty picture is nothing", none.first == 0 && none.second == 0)
    }

    private val start = OcclusionBox(0.4, 0.4, 0.2, 0.1)

    @Test fun clampingAndMoving() {
        val outside = PO.clamped(OcclusionBox(0.95, -0.2, 0.2, 0.1))
        check("a box is pulled back inside the picture", inPicture(outside) && near(outside.x, 0.8) && near(outside.y, 0.0), outside)
        val tiny = PO.clamped(OcclusionBox(0.5, 0.5, 0.001, 0.0))
        check("a box is never smaller than the least", tiny.w >= PO.minSide && tiny.h >= PO.minSide)
        val huge = PO.clamped(OcclusionBox(-1.0, -1.0, 3.0, 3.0))
        check("a box bigger than the picture is the picture", near(huge.w, 1.0) && near(huge.h, 1.0) && near(huge.x, 0.0))

        val dragged = PO.moved(start, 0.1, -0.05)
        check("a drag moves a box", near(dragged.x, 0.5) && near(dragged.y, 0.35) && near(dragged.w, 0.2))
        val pushed = PO.moved(start, 5.0, 5.0)
        check("a box dragged off the edge stops at it", near(pushed.x, 0.8) && near(pushed.y, 0.9) && near(pushed.w, 0.2), pushed)
    }

    @Test fun stretching() {
        val wider = PO.resized(start, PhotoOcclusion.Handle.bottomRight, 0.1, 0.05)
        check("the bottom-right corner stretches", near(wider.x, 0.4) && near(wider.w, 0.3) && near(wider.h, 0.15))
        val fromTopLeft = PO.resized(start, PhotoOcclusion.Handle.topLeft, -0.1, -0.1)
        check("the top-left corner stretches and the far corner stays",
            near(fromTopLeft.x, 0.3) && near(fromTopLeft.y, 0.3)
                && near(fromTopLeft.x + fromTopLeft.w, 0.6) && near(fromTopLeft.y + fromTopLeft.h, 0.5))
        val crossed = PO.resized(start, PhotoOcclusion.Handle.topLeft, 0.5, 0.5)
        check("a corner cannot cross its opposite", near(crossed.x + crossed.w, 0.6) && crossed.w >= PO.minSide - 1e-9
            && near(crossed.y + crossed.h, 0.5), crossed)
        val beyond = PO.resized(start, PhotoOcclusion.Handle.topRight, 3.0, -3.0)
        check("a corner stops at the picture's edge", inPicture(beyond) && near(beyond.y, 0.0) && near(beyond.x + beyond.w, 1.0), beyond)
        val bottomLeft = PO.resized(start, PhotoOcclusion.Handle.bottomLeft, -0.05, 0.02)
        check("the bottom-left corner stretches", near(bottomLeft.x, 0.35) && near(bottomLeft.h, 0.12)
            && near(bottomLeft.x + bottomLeft.w, 0.6))
    }

    @Test fun drawingANewCover() {
        val backwards = PO.drawn(0.6, 0.5, 0.2, 0.3)
        check("a box drawn backwards is the same box", backwards?.let { near(it.x, 0.2) && near(it.y, 0.3)
            && near(it.w, 0.4) && near(it.h, 0.2) } ?: false, backwards)
        check("a tap draws nothing", PO.drawn(0.5, 0.5, 0.501, 0.502) == null)
        val offEdge = PO.drawn(0.9, 0.9, 1.4, 1.3)
        check("a box drawn off the picture stays on it", offEdge?.let(::inPicture) ?: false)
        check("a straight swipe (a scroll that began on the picture) draws nothing",
            PO.drawn(0.5, 0.1, 0.505, 0.7) == null && PO.drawn(0.1, 0.5, 0.5, 0.5) == null)
        val label = PO.drawn(0.1, 0.5, 0.4, 0.52)
        check("a short wide box over a label is still a cover", label?.let { near(it.w, 0.3) && it.h >= PO.minSide - 1e-9 } ?: false)

        val middle = PO.added(aspect = 1.0)
        check("a new cover sits in the middle", near(middle.x + middle.w / 2, 0.5) && near(middle.y + middle.h / 2, 0.5))
        val wide = PO.added(aspect = 2.0)
        check("a new cover on a wide picture is taller as a fraction", wide.h > middle.h)
        val corner = PO.added(centreX = 0.99, centreY = 0.99)
        check("a new cover near the edge stays inside", inPicture(corner))
    }

    @Test fun hitting() {
        val big = PhotoOcclusion.Cover(box = OcclusionBox(0.1, 0.1, 0.6, 0.6), answer = "Heart")
        val inner = PhotoOcclusion.Cover(box = OcclusionBox(0.3, 0.3, 0.1, 0.05), answer = "Aorta")
        val far = PhotoOcclusion.Cover(box = OcclusionBox(0.8, 0.8, 0.1, 0.1), answer = "Apex")
        val placed = listOf(big, inner, far)
        check("the smaller of two covers is the one hit", PO.hit(0.35, 0.32, placed) == 1)
        check("the big cover around it is hit elsewhere", PO.hit(0.15, 0.6, placed) == 0)
        check("empty picture is no cover", PO.hit(0.75, 0.05, placed) == null)
        check("slack lets a finger just outside count", PO.hit(0.79, 0.85, placed, slack = 0.02) == 2)

        val box = OcclusionBox(0.2, 0.2, 0.4, 0.2)
        check("a corner is found near it", PO.handle(0.61, 0.41, box, 0.03, 0.03) == PhotoOcclusion.Handle.bottomRight)
        check("the top-left too", PO.handle(0.19, 0.2, box, 0.03, 0.03) == PhotoOcclusion.Handle.topLeft)
        check("the middle of an edge is no corner", PO.handle(0.4, 0.2, box, 0.03, 0.03) == null)
        val thin = OcclusionBox(0.2, 0.2, 0.02, 0.02)
        check("on a tiny box the nearest corner wins", PO.handle(0.221, 0.221, thin, 0.05, 0.05) == PhotoOcclusion.Handle.bottomRight)
    }

    @Test fun fromOcrAndToCards() {
        val found = listOf(OcclusionPhrases.Cover(box = OcclusionBox(0.9, 0.1, 0.3, 0.05), answer = "Left atrium", lines = listOf(listOf(0, 1))))
        val editable = PO.covers(found)
        check("OCR covers become editable ones, inside the picture",
            editable.size == 1 && editable[0].answer == "Left atrium" && inPicture(editable[0].box))

        check("answers are tidied to one line", PO.tidied("  Superior vena\ncava ") == "Superior vena cava")

        var covers = listOf(
            PhotoOcclusion.Cover(box = OcclusionBox(0.1, 0.1, 0.2, 0.05), answer = "Right atrium"),
            PhotoOcclusion.Cover(box = OcclusionBox(0.6, 0.1, 0.2, 0.05), answer = " Aorta "),
            PhotoOcclusion.Cover(box = OcclusionBox(0.1, 0.8, 0.2, 0.05), answer = "   "),
            PhotoOcclusion.Cover(box = OcclusionBox(0.6, 0.8, 0.2, 0.05), answer = "aorta"),
        )
        val cards = PO.cards(covers, imageIndex = 3, source = "Scan, p. 2")
        check("one card per answered label, a repeat asked once", cards.size == 2, cards.size)
        check("cards are picture cards on the right picture", cards.all { it.type == AnkiCardType.OCCLUSION && it.imageIndex == 3 })
        check("the answer is the tidied label", cards.first().bullets == listOf("Right atrium") && cards.last().bullets == listOf("Aorta"))
        check("each card carries its source", cards.all { it.source == "Scan, p. 2" })
        val blank = covers[2].box
        check("an unanswered cover still hides its place on every card", cards.all { blank in it.siblings })
        check("a card's own cover is not among its siblings", cards.all { card -> (card.occlusion ?: blank) !in card.siblings })
        check("the repeated label's second place stays covered on the first", covers[3].box in cards.last().siblings)

        covers = listOf(PhotoOcclusion.Cover(box = OcclusionBox(0.1, 0.1, 0.2, 0.05), answer = "Aorta"))
        check("one label is enough for a photo", PO.cards(covers, imageIndex = 0).size == 1)
        check("no answers, no cards", PO.cards(listOf(PhotoOcclusion.Cover(box = blank, answer = "")), imageIndex = 0).isEmpty())
        check("nothing, nothing", PO.cards(emptyList(), imageIndex = 0).isEmpty())
    }

    @Test fun namesAndText() {
        val calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        calendar.clear()
        calendar.set(2026, Calendar.SEPTEMBER, 5, 12, 0)
        val day = calendar.time
        check("a scan is named for its day", PO.defaultName(day, scanned = true).startsWith("Scanned pages, "))
        check("a photo deck is named for its day", PO.defaultName(day, scanned = false).startsWith("Picture cards, "))
        check("a one-page source is just the name", PO.source("Heart", 1, 1) == "Heart")
        check("a page of several says which", PO.source("Heart", 2, 3) == "Heart, p. 2")
        check("page text drops blank lines", PO.pageText(listOf("  Aorta ", "", "Left atrium", " \n")) == "Aorta\nLeft atrium")
    }
}
