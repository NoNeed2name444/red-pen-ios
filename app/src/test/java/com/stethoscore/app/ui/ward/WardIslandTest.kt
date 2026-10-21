package com.stethoscore.app.ui.ward

import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.hypot
import kotlin.math.min

// A port of upstream/ios/RedPen/Tests/WardIslandTests.swift, same cases and
// numbers: which sides of a page join the frame, the joins moved into a
// strip's own coordinates, the clearance bands beside the page, the iPad's
// fixed 18-point opening, and the fold pill clearing both curves.
class WardIslandTest {

    private fun near(a: Double, b: Double, tolerance: Double = 0.01) = abs(a - b) <= tolerance
    private val phone = WardPaper.panel(402.0, 874.0)!!
    private val deck = WardEdge.join(WardEdge.outline(phone), y = 733.0, radius = phone.radius)!!
    private val page = WardRect(16.0, 0.0, 370.0, 874.0)

    @Test fun sides() = checks {
        for ((label, host, covered, lr) in listOf(
            Quad("page", WardRect(16.0, 732.25, 370.0, 130.0), false, true to true),
            Quad("sheet", WardRect(0.0, 732.25, 402.0, 130.0), false, false to false),
            Quad("trailing host", WardRect(200.0, 732.25, 186.0, 130.0), false, false to true),
            Quad("sky", WardRect(16.0, 732.25, 370.0, 130.0), true, false to false),
            Quad("one point", WardRect(17.0, 732.25, 368.0, 130.0), false, true to true),
            Quad("outside tolerance", WardRect(17.01, 732.25, 367.98, 130.0), false, false to false),
        )) {
            val sides = WardIsland.sides(host, page, covered)
            check("A1 sides: $label", sides.left == lr.first && sides.right == lr.second)
        }
    }

    private data class Quad<A, B, C, D>(val a: A, val b: B, val c: C, val d: D)

    @Test fun local() = checks {
        val local = WardIsland.local(deck, origin = WardVec(16.0, 732.25))
        check("A1 local line stays half the stroke below strip top", near(local.y, 0.75))
        check("A1 local left center", near(local.left!!.center.x, 43.10) && near(local.left!!.center.y, 47.85))
        check("A1 local right center", near(local.right!!.center.x, 326.90) && near(local.right!!.center.y, 47.85))
        check("A1 local left join", near(local.left!!.join.x, -4.0) && near(local.left!!.join.y, 47.85))
        check("A1 local right join", near(local.right!!.join.x, 374.0) && near(local.right!!.join.y, 47.85))
        check("A1 local straight ends", near(local.fromX!!, 43.10) && near(local.toX!!, 326.90))
        val half = WardEdge.join(WardEdge.outline(phone), y = 733.0, radius = phone.radius, left = false)!!
        check("translation keeps an unjoined side", WardIsland.local(half, WardVec(200.0, 732.25)).left == null &&
            WardIsland.local(half, WardVec(200.0, 732.25)).fromX == null)
    }

    @Test fun clearance() = checks {
        val bands = WardIsland.clearance(phone, page, WardIsland.Sides(left = true, right = true))
        check("A1 two clearance pieces", bands.size == 2)
        check("A1 left piece only 12...16", bands[0] == WardRect(12.0, 12.0, 4.0, 850.0))
        check("A1 right piece only 386...390", bands[1] == WardRect(386.0, 12.0, 4.0, 850.0))
        check("A1 pieces never enter the page", bands.all { it.maxX <= page.minX || it.minX >= page.maxX })
        check("one-sided clearance", WardIsland.clearance(phone, page, WardIsland.Sides(left = false, right = true)) == listOf(bands[1]))
        check("sheet and sky have no pieces", WardIsland.clearance(phone, page, WardIsland.Sides(left = false, right = false)).isEmpty())
    }

    @Test fun pad() = checks {
        for ((w, h) in listOf(834.0 to 1194.0, 1194.0 to 834.0, 1032.0 to 1376.0, 744.0 to 1133.0, 375.0 to 812.0)) {
            val pad = WardPaper.panel(w, h, pad = true)!!
            check("A1 iPad ${w}x$h, including narrow window: 18", pad.radius == 18.0)
            check("A1 moved iPad opening: 18", WardPaper.panel(w, h, top = 120.0, pad = true)!!.radius == 18.0)
            val old = WardPaper.panel(w, h)!!
            check("A1 non-iPad unchanged", near(old.radius, (min(w, h) - 24) * 53.33 / 428, 1e-10))
        }
        check("A1 phone still 47.10", near(phone.radius, 47.10))
        val pad = WardPaper.panel(834.0, 1194.0, pad = true)!!
        val padY = pad.y + pad.height - 128
        val joinedPad = WardEdge.join(WardEdge.outline(pad), y = padY, radius = pad.radius)!!
        for ((name, corner, x) in listOf(Triple("left", joinedPad.left!!, 12.0), Triple("right", joinedPad.right!!, 822.0))) {
            check("A1 iPad $name radius", near(corner.radius, 18.0))
            check("A1 iPad $name join", near(corner.join.x, x) && near(corner.join.y, padY + 18))
            val vector = corner.join - corner.center
            val angle = asin(min(1.0, abs(vector.y) / hypot(vector.x, vector.y))) * 180 / PI
            check("A1 iPad $name tangent to vertical outline within 0.5 degrees", angle <= 0.5)
            check("A1 iPad $name tangent to horizontal line", near(corner.center.y - corner.radius, padY))
        }
        val small = WardEdge.join(WardEdge.outline(pad), y = pad.y + pad.height - 30, radius = pad.radius)!!
        check("iPad radius halves the remaining room", near(small.left!!.radius, 15.0))
    }

    // The pill has a fixed point size, including at AX5. Taller decks change
    // their y, so check both heights and the reduced-room case independently.
    @Test fun fold() = checks {
        for ((name, size, isPad) in listOf(Triple("phone", 402.0 to 874.0, false), Triple("SE", 375.0 to 667.0, false),
            Triple("Pro Max", 440.0 to 956.0, false), Triple("iPad", 834.0 to 1194.0, true))) {
            val (w, h) = size
            val panel = WardPaper.panel(w, h, pad = isPad)!!
            for ((text, room) in listOf("default" to 129.0, "AX5" to 310.0, "short" to 70.0)) {
                val y = panel.y + panel.height - room
                val join = WardEdge.join(WardEdge.outline(panel), y = y, radius = panel.radius)!!
                val slab = WardRect(28.0, y - WardPaper.edgeWidth / 2, w - 56, room - 8)
                val inset = WardIsland.foldInset(slab, join)
                val gap = WardIsland.foldClearance(slab, join, inset)
                println(String.format(java.util.Locale.ROOT, "FOLD %s %s inset=%.2f slab=%.3f island=%.3f pt (rim included)",
                    name, text, inset, gap.slab, gap.island))
                check("fold $name $text clears both curves by 2pt", gap.slab >= 2 && gap.island >= 2)
                // This also bounds narrower, trailing iPad slabs: the near corner is
                // in the same position; the distant corner only gets farther away.
            }
        }
    }
}
