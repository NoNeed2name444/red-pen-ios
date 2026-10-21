package com.stethoscore.app.ui.home

import com.stethoscore.app.ui.ward.WardPartLedger
import com.stethoscore.app.ui.ward.WardRect
import com.stethoscore.app.ui.ward.checks
import com.stethoscore.app.ui.ward.wardBookedTop
import org.junit.Test
import kotlin.math.abs

// The port of upstream/ios/RedPen/Tests/HomeFitTests.swift, check for check
// and number for number: which windows count as short, how many beds the
// round shows there, how much of the page shows above the bar (the page's
// cut), the check run on a laid-out home, and the parts book
// (WardPartLedger) the cut reads.
class HomeFitTest {
    private fun box(y0: Double, y1: Double, x0: Double = 16.0, x1: Double = 359.0) = HomeFit.Box(x0, y0, x1, y1)
    private fun rect(x: Double, y: Double, w: Double, h: Double) = WardRect(x, y, w, h)
    private fun List<String>.joined() = joinToString("; ")

    @Test fun shortWindows() = checks {
        // iPhone SE, mini and 16e, inside the status bar and home indicator
        for (height in listOf(647.0, 728.0, 763.0)) check("${height.toInt()} points tall is short", HomeFit.isShort(height, broad = false))
        // a Pro, a Pro Max
        for (height in listOf(778.0, 840.0)) check("${height.toInt()} points tall is not short", !HomeFit.isShort(height, broad = false))
        check("a wide iPad keeps New set at the bottom", !HomeFit.isShort(700.0, broad = true))
        check("nothing measured yet is not short", !HomeFit.isShort(0.0, broad = false))
    }

    @Test fun bedsShown() = checks {
        check("a short window shows two of four beds", HomeFit.shownBeds(4, short = true) == 2)
        check("a short window shows a lone bed", HomeFit.shownBeds(1, short = true) == 1)
        check("a tall window shows every bed", HomeFit.shownBeds(4, short = false) == 4)
        check("no beds stay none", HomeFit.shownBeds(0, short = true) == 0)
        // large text: a bed comes off while the cut slices Start, one always stays
        check("a trim takes a bed off a tall window", HomeFit.shownBeds(3, short = false, trimmed = 1) == 2)
        check("a trim goes on from a short window's two", HomeFit.shownBeds(4, short = true, trimmed = 1) == 1)
        check("a trim leaves one bed", HomeFit.shownBeds(3, short = false, trimmed = 9) == 1)
        check("a trim leaves none as none", HomeFit.shownBeds(0, short = false, trimmed = 2) == 0)
        // the cut through a button (the iPad at AX1: Start 967-1025, cut 1020)
        check("a cut through the middle slices", HomeFit.slices(967.0, 1025.0, 1020.0))
        check("a button wholly above the cut is not sliced", !HomeFit.slices(600.0, 656.0, 1020.0))
        check("a button wholly past the cut is not sliced", !HomeFit.slices(1049.0, 1107.0, 768.0))
        check("a button ending on the cut is not sliced", !HomeFit.slices(964.0, 1020.0, 1020.0))
    }

    @Test fun thePreviewsCheck() = checks {
        val fitting = HomeFit.faults(box(204.0, 527.0), box(460.0, 510.0), box(557.0, 647.0), box(8.0, 52.0, x0 = 300.0, x1 = 344.0))
        check("a home that fits has no faults", fitting.isEmpty(), fitting.joined())
        // the r7 SE picture: the card to 603, the bar from 570
        val cut = HomeFit.faults(box(204.0, 603.0), box(538.0, 590.0), box(570.0, 720.0), box(580.0, 632.0, x0 = 232.0, x1 = 359.0))
        check("the button and the card past the cut are both caught",
            cut.size == 2 && cut[0].startsWith("Start ward round") && cut[1].startsWith("the round card"), cut.joined())
        // on a short window New set is up in the top row: on the card there, it is caught
        val up = HomeFit.faults(box(120.0, 500.0), box(440.0, 490.0), box(557.0, 647.0), box(131.0, 175.0, x0 = 300.0, x1 = 344.0))
        check("New set on the card's top is caught", up.size == 1 && up[0].startsWith("New set"), up.joined())
    }

    @Test fun largeTextThePageScrolls() = checks {
        val xxl = HomeFit.faults(box(283.0, 797.0), box(725.0, 781.0), box(708.0, 860.0), box(708.0, 764.0, x0 = 232.0, x1 = 386.0), large = true)
        check("at XXL a home that runs on and scrolls fits", xxl.isEmpty(), xxl.joined())
        val xxlDefault = HomeFit.faults(box(283.0, 797.0), box(725.0, 781.0), box(708.0, 860.0), box(708.0, 764.0, x0 = 232.0, x1 = 386.0))
        check("the same page at the standard sizes does not", xxlDefault.size == 2, xxlDefault.joined())
        val sliced = HomeFit.faults(box(283.0, 760.0), box(680.0, 736.0), box(708.0, 860.0), null, large = true)
        check("a Start button sliced by the cut is caught", sliced.size == 1 && sliced[0].contains("sliced"), sliced.joined())
        val whole = HomeFit.faults(box(283.0, 700.0), box(620.0, 676.0), box(708.0, 860.0), null, large = true)
        check("a Start button wholly above the cut is fine", whole.isEmpty(), whole.joined())
    }

    @Test fun sliversAndWords() = checks {
        val sliver = HomeFit.faults(box(204.0, 527.0), box(460.0, 510.0), box(557.0, 647.0), null, tiles = box(539.0, 700.0))
        check("6 points of the tiles over the cut is a sliver", sliver.size == 1 && sliver[0].contains("sliver"), sliver.joined())
        for ((tiles, what) in listOf(box(500.0, 700.0) to "a good part of the tiles", box(560.0, 700.0) to "tiles wholly under the cut")) {
            val f = HomeFit.faults(box(204.0, 480.0), box(420.0, 470.0), box(557.0, 647.0), null, tiles = tiles)
            check("$what is fine", f.isEmpty(), f.joined())
        }
        val broken = HomeFit.faults(box(204.0, 527.0), box(460.0, 510.0), box(557.0, 647.0), null,
            words = listOf(HomeFit.Words("the Vitals tile's streak", 46.0, 52.0), HomeFit.Words("the brain map's line", 120.0, 48.0)))
        check("a text narrower than its widest word is caught, and only that one",
            broken.size == 1 && broken[0].startsWith("the Vitals tile's streak breaks inside a word"), broken.joined())
    }

    @Test fun sliversOfAnyRowOrPart() = checks {
        // the iPad at the default size: the PRACTISE tiles' tops at 1098, the bar from 1118
        val ipadTiles = HomeFit.Part("a Practise tile", box(1098.0, 1190.0))
        val ipadBar = box(1118.0, 1194.0)
        val ipadSliver = HomeFit.faults(box(300.0, 980.0), box(920.0, 976.0), ipadBar, null, parts = listOf(ipadTiles))
        check("iPad at the default size: 8 points of the Practise tiles are caught",
            ipadSliver.size == 1 && ipadSliver[0].contains("a Practise tile (1098-1190)") && ipadSliver[0].contains("cut at 1106"), ipadSliver.joined())
        check("the cut moves up to the tiles' top", HomeFit.settledCut(1106.0, listOf(1098.0)) == 1098.0)
        check("the page, cut there, shows none of them", HomeFit.cut(1118.0, 0.0, listOf(1098.0)) == 1098.0)
        val ipadHonoured = HomeFit.faults(box(300.0, 980.0), box(920.0, 976.0), ipadBar, null, pageEnd = 1098.0, parts = listOf(ipadTiles))
        check("with the cut moved up, the tiles are no sliver", ipadHonoured.isEmpty(), ipadHonoured.joined())

        // AX1: the top of bed 1's Due chip, 682.3-700, over the cut at 686 (bar 698)
        val dueChip = HomeFit.Part("bed 1's Due chip", box(682.3, 700.0, x0 = 300.0, x1 = 359.0))
        val ax1Bar = box(698.0, 860.0)
        val ax1Sliver = HomeFit.faults(box(283.0, 900.0), box(820.0, 876.0), ax1Bar, null, large = true, parts = listOf(dueChip))
        check("AX1: 4 points of the Due chip over the cut are caught",
            ax1Sliver.size == 1 && ax1Sliver[0].contains("bed 1's Due chip"), ax1Sliver.joined())
        check("AX1: the cut moves up to the chip's top", HomeFit.settledCut(686.0, listOf(682.3)) == 682.3)
        val ax1Honoured = HomeFit.faults(box(283.0, 900.0), box(820.0, 876.0), ax1Bar, null, large = true, pageEnd = 682.3, parts = listOf(dueChip))
        check("AX1: with the cut moved up, the chip is no sliver", ax1Honoured.isEmpty(), ax1Honoured.joined())

        // AX1 phone: the frame snapped to the 3x grid ended at 682.67; on the
        // grid at or above the cut, the end is 682.0
        val ax1Height = HomeFit.shown(698.0, 0.0, 874.0, listOf(682.3), scale = 3.0)
        check("AX1: the page ends on the 3x grid at or above the chip's top",
            ax1Height <= 682.3 && ax1Height > 682.3 - 1.0 / 3 && roundedHalfAway(ax1Height * 3) == ax1Height * 3, "$ax1Height")
        for (top in listOf(0.0, 0.17, 59.4, 62.5)) {
            val h = HomeFit.shown(698.0, top, 874.0, listOf(682.3), scale = 3.0)
            val grid = (top + h) * 3
            check("AX1: from a page top at $top, an end snapped to the grid either way is not below the chip",
                top + h <= 682.3 + 1e-9 && (roundedHalfAway(grid) / 3) <= 682.3 + 1e-9, "${top + h}")
        }
        val ax1Snapped = HomeFit.faults(box(413.0, 1173.0), box(1098.0, 1156.0), box(698.0, 840.0), box(698.0, 755.0),
            large = true, pageEnd = 682 + 0.0, parts = listOf(dueChip))
        check("AX1: the snapped page end clears the chip in the gate", ax1Snapped.isEmpty(), ax1Snapped.joined())
        check("no scale known: the cut as it was", HomeFit.shown(698.0, 0.0, 874.0, listOf(682.3)) == 682.3)

        // the cut is left alone by tops at it, 12 or more over it, or past it
        check("a top at the cut leaves it", HomeFit.settledCut(686.0, listOf(686.0)) == 686.0)
        check("a top 12 points over the cut leaves it", HomeFit.settledCut(686.0, listOf(674.0)) == 686.0)
        check("a top past the cut leaves it", HomeFit.settledCut(686.0, listOf(690.0, 900.0)) == 686.0)
        check("no tops, no move", HomeFit.settledCut(686.0, emptyList()) == 686.0)
        // moving up can bring another top into the band: it goes on until none is
        check("a chain of tops moves the cut to the last", HomeFit.settledCut(686.0, listOf(680.0, 670.0, 640.0)) == 670.0)
        check("tops in any order settle the same", HomeFit.settledCut(686.0, listOf(670.0, 640.0, 680.0)) == 670.0)
        // a part twice reported is one sliver
        val twice = HomeFit.faults(box(204.0, 480.0), box(420.0, 470.0), box(557.0, 647.0), null,
            tiles = box(539.0, 700.0), parts = listOf(HomeFit.Part("the tiles", box(539.0, 700.0))))
        check("the same sliver reported twice is one fault", twice.size == 1, twice.joined())
        // a part wholly past the cut, or well over it, is fine
        val partsFine = HomeFit.faults(box(204.0, 480.0), box(420.0, 470.0), box(557.0, 647.0), null,
            parts = listOf(HomeFit.Part("a row", box(545.0, 600.0)), HomeFit.Part("a tile", box(400.0, 500.0))))
        check("parts wholly past the cut or well over it are fine", partsFine.isEmpty(), partsFine.joined())
    }

    @Test fun howMuchOfThePageShows() = checks {
        check("no bar measured: all of the page", HomeFit.shown(null, 0.0, 874.0) == 874.0)
        check("a bar at 700: down to 688", HomeFit.shown(700.0, 0.0, 874.0) == 688.0)
        check("measured from the page's own top", HomeFit.shown(700.0, 100.0, 774.0) == 588.0)
        check("a bar not below the page's top: all of it", HomeFit.shown(50.0, 100.0, 774.0) == 774.0)
        check("an endless bar top: all of it", HomeFit.shown(Double.POSITIVE_INFINITY, 0.0, 874.0) == 874.0)
        check("the cut, from the page's top", HomeFit.cut(700.0, 100.0) == 588.0)
        check("the cut below a short page's frame is kept", HomeFit.cut(700.0, 100.0) == 588.0 && HomeFit.shown(700.0, 100.0, 500.0) == 500.0)
        check("no bar, no cut", HomeFit.cut(null, 0.0) == null)
        check("a bar over the page's top, no cut", HomeFit.cut(50.0, 100.0) == null)
        check("a bar just under the page's top cuts at its top", HomeFit.cut(105.0, 100.0) == 0.0)

        val close = HomeFit.faults(box(204.0, 553.0), box(500.0, 545.0), box(557.0, 647.0), null)
        check("ending 4 points above the bar is too close", close.size == 1, close.joined())
        check("nothing laid out is a fault", HomeFit.faults(null, null, null, null).size == 1)
        check("a card with no button is a fault", HomeFit.faults(box(0.0, 1.0), null, null, null).size == 1)
    }

    @Test fun thePartsBook() = checks {
        // N3: a top is booked floored onto the pixel grid, never rounded to a half point
        val booked682 = wardBookedTop(682.78, 3.0)
        check("682.78 at 3x books at the pixel line above, 682.667", abs(booked682 - 2048.0 / 3) < 1e-9, "$booked682")
        check("a booked top is never below the real one", booked682 <= 682.78 && (682.78 - booked682) < 1.0 / 3)
        check("a top already on the grid keeps its place", wardBookedTop(683.0, 3.0) == 683.0)
        check("a top on a 2x pixel line keeps its place", wardBookedTop(100.5, 2.0) == 100.5)
        var neverBelow = true
        for (scale in listOf(1.0, 2.0, 3.0)) for (step in 0 until 3000) {
            val y = 600 + step * 0.0137
            val top = wardBookedTop(y, scale)
            if (top > y + 1e-9 || y - top >= 1 / scale + 1e-9) neverBelow = false
        }
        check("every booked top is at or above the real one, within a pixel", neverBelow)
        check("an unknown scale floors to a whole point", wardBookedTop(682.78, 0.0) == 682.0)

        // the ledger books that top, and the cut moves up to it
        val ledger = WardPartLedger<Int>()
        ledger.set(1, "chip", rect(0.0, 682.78, 80.0, 24.0), reach = 0.0, scale = 3.0)
        check("the ledger lists the floored top", ledger.tops.size == 1 && abs(ledger.tops[0] - 2048.0 / 3) < 1e-9, "${ledger.tops}")
        check("a cut at 683 settles on the chip's pixel line", abs(HomeFit.settledCut(683.0, ledger.tops) - 2048.0 / 3) < 1e-9)
        // a row's tile stands out above its frame
        ledger.set(2, "row", rect(0.0, 700.0, 300.0, 60.0), reach = 8.0, scale = 2.0)
        check("reach lifts a row's top", ledger.entries[2]?.top == 692.0 && ledger.entries[2]?.rect?.height == 68.0)

        // N2: a part whose view went away leaves the book; a new page clears it
        ledger.drop(1)
        check("a dropped part leaves the book", ledger.entries[1] == null && ledger.tops == listOf(692.0))
        ledger.drop(99)
        check("dropping a part that is not there changes nothing", ledger.tops == listOf(692.0))
        ledger.set(3, "gone", WardRect(0.0, 0.0, 0.0, 0.0), reach = 4.0, scale = 2.0)
        check("an empty frame is not kept", ledger.entries[3] == null)
        ledger.clear()
        check("a new page empties the ledger", ledger.entries.isEmpty() && ledger.tops.isEmpty())
        // the same top from two parts counts once, and survives one of them going
        ledger.set(4, "a", rect(0.0, 500.0, 10.0, 10.0), reach = 0.0, scale = 2.0)
        ledger.set(5, "b", rect(0.0, 500.0, 10.0, 10.0), reach = 0.0, scale = 2.0)
        check("two parts at one top book it once", ledger.tops == listOf(500.0))
        ledger.drop(4)
        check("the top stays while another part holds it", ledger.tops == listOf(500.0))
    }

    @Test fun pushPopScrollAndTheLoopGuard() = checks {
        // 1. Push and pop with no movement (onAppear re-booking from the remembered spot)
        run {
            val book = WardPartLedger<Int>()
            val changes = mutableListOf<List<Double>>()
            val r = rect(16.0, 1098.0, 300.0, 92.0)
            if (book.set(1, "a Practise tile", r, reach = 3.0, scale = 2.0, atRest = true)) changes.add(book.told)
            check("initial rest sighting books the tile and publishes once",
                book.entries[1] != null && book.sightings[1] != null && book.tops == listOf(1095.0) && changes == listOf(listOf(1095.0)))
            if (book.drop(1, atRest = true)) changes.add(book.told)
            check("push disappear drops both entry and sighting",
                book.entries[1] == null && book.sightings[1] == null && book.tops.isEmpty() && changes == listOf(listOf(1095.0), emptyList()))
            if (book.set(1, "a Practise tile", r, reach = 3.0, scale = 2.0, atRest = true)) changes.add(book.told)
            check("onAppear re-books the identical rect and publishes once",
                book.entries[1]?.top == 1095.0 && book.tops == listOf(1095.0) && changes == listOf(listOf(1095.0), emptyList(), listOf(1095.0)))
        }

        // 2. Push and pop during a transition (atRest: false then rebook())
        run {
            val book = WardPartLedger<Int>()
            val changes = mutableListOf<List<Double>>()
            val r = rect(16.0, 682.3, 60.0, 18.0)
            if (book.set(1, "bed 1's Due chip", r, reach = 0.0, scale = 3.0, atRest = true)) changes.add(book.told)
            val chipTop = wardBookedTop(682.3, 3.0)
            check("chip booked at rest before transition", book.tops == listOf(chipTop) && changes.size == 1)
            val droppedWhileMoving = book.drop(1, atRest = false)
            check("mid-push drop clears entry without publishing mid-transition",
                !droppedWhileMoving && book.entries[1] == null && book.sightings[1] == null && book.told == listOf(chipTop))
            val sightedWhileMoving = book.set(1, "bed 1's Due chip", r, reach = 0.0, scale = 3.0, atRest = false)
            check("mid-pop sighting is kept in sightings without booking or publishing",
                !sightedWhileMoving && book.sightings[1] != null && book.entries[1] == null && book.told == listOf(chipTop))
            val secondRect = rect(16.0, 740.0, 300.0, 56.0)
            book.set(2, "a set row", secondRect, reach = 4.0, scale = 3.0, atRest = false)
            if (book.rebook()) changes.add(book.told)
            check("rebook on rest restores the popped part and publishes once",
                book.entries[1]?.top == chipTop && book.entries[2]?.top == 736.0 && book.tops == listOf(chipTop, 736.0) && changes.size == 2)
        }

        // 3. Scroll settlement (atRest: false -> rebook())
        run {
            val book = WardPartLedger<Int>()
            val changes = mutableListOf<List<Double>>()
            if (book.set(1, "row 1", rect(0.0, 500.0, 300.0, 50.0), reach = 4.0, scale = 2.0, atRest = true)) changes.add(book.told)
            for (y in listOf(480.0, 440.0, 410.0)) {
                if (book.set(1, "row 1", rect(0.0, y, 300.0, 50.0), reach = 4.0, scale = 2.0, atRest = false)) changes.add(book.told)
            }
            check("scrolling updates sightings without changing entries or told",
                book.entries[1]?.top == 496.0 && book.told == listOf(496.0) && changes.size == 1)
            if (book.rebook()) changes.add(book.told)
            check("rebook at scroll settlement updates entries to final sighting and fires once",
                book.entries[1]?.top == 406.0 && book.tops == listOf(406.0) && changes == listOf(listOf(496.0), listOf(406.0)))
            if (book.rebook()) changes.add(book.told)
            check("a second rebook with no change does not fire again", changes.size == 2)
        }

        // 4. Row recycled off-screen while scrolling (drop + rebook)
        run {
            val book = WardPartLedger<Int>()
            val changes = mutableListOf<List<Double>>()
            book.set(1, "row 1", rect(0.0, 300.0, 300.0, 50.0), reach = 0.0, scale = 2.0, atRest = true)
            if (book.set(2, "row 2", rect(0.0, 600.0, 300.0, 50.0), reach = 0.0, scale = 2.0, atRest = true)) changes.add(book.told)
            val midDrop = book.drop(1, atRest = false)
            check("row recycled mid-scroll does not publish until settlement",
                !midDrop && book.entries[1] == null && book.sightings[1] == null && book.told == listOf(300.0, 600.0))
            if (book.rebook()) changes.add(book.told)
            check("settlement after mid-scroll recycle publishes remaining row once",
                book.entries[1] == null && book.entries[2]?.top == 600.0 && book.tops == listOf(600.0) && book.told == listOf(600.0)
                    && changes.last() == listOf(600.0))
        }

        // 5. Cut moves above a part at rest (loop guard) vs normal removal above the cut
        run {
            val book = WardPartLedger<Int>()
            book.cut = 686.0
            book.set(1, "chip", rect(0.0, 682.0, 60.0, 18.0), reach = 0.0, scale = 2.0, atRest = true)
            book.set(2, "upper row", rect(0.0, 400.0, 300.0, 50.0), reach = 0.0, scale = 2.0, atRest = true)
            val movedCut = HomeFit.settledCut(686.0, book.tops)
            check("the chip at 682 moves the cut from 686 to 682", movedCut == 682.0)
            book.cut = movedCut
            val loopDrop = book.drop(1, atRest = true, cut = 682.0)
            check("dropping a part at or below the settled cut keeps its entry so settledCut stays at 682",
                !loopDrop && book.entries[1]?.top == 682.0 && book.sightings[1] != null && HomeFit.settledCut(686.0, book.tops) == 682.0)
            // the next rest books the hidden part where it was: nothing published
            val restAfterHide = book.rebook()
            check("a part hidden by the cut stays booked through the next rest",
                !restAfterHide && book.entries[1]?.top == 682.0 && 682.0 in book.tops)
            val normalDrop = book.drop(2, atRest = true, cut = 682.0)
            check("dropping a part above the cut removes it from entries and tops",
                normalDrop && book.entries[2] == null && book.sightings[2] == null && book.tops == listOf(682.0))
        }

        // 6. Dedup across set / drop / rebook
        run {
            val book = WardPartLedger<Int>()
            val first = book.set(1, "a", rect(0.0, 500.0, 100.0, 40.0), reach = 0.0, scale = 2.0, atRest = true)
            val sameId = book.set(1, "a", rect(10.0, 500.0, 120.0, 40.0), reach = 0.0, scale = 2.0, atRest = true)
            val secondSameTop = book.set(2, "b", rect(140.0, 500.0, 100.0, 40.0), reach = 0.0, scale = 2.0, atRest = true)
            val dropOneOfTwo = book.drop(1, atRest = true)
            val rebookSame = book.rebook()
            val dropLast = book.drop(2, atRest = true)
            val dropEmpty = book.drop(99, atRest = true)
            check("told deduplicates identical sorted tops across set, drop and rebook",
                first && !sameId && !secondSameTop && !dropOneOfTwo && !rebookSame && dropLast && !dropEmpty)
        }
    }

    @Test fun theFourthReviewsLedgerRegressions() = checks {
        // Nit 1: multiplication and division can land on opposite sides of a 3x
        // pixel line. A holder on that line must stay hidden through drop/rebook.
        run {
            var keptEveryHolder = true
            var roundedApart = 0
            for (pixel in 1800 until 2100) {
                val book = WardPartLedger<Int>()
                val y = pixel * (1.0 / 3)
                val cut = pixel / 3.0
                if (y < cut) roundedApart += 1
                book.cut = cut
                book.set(1, "holder", rect(0.0, y, 100.0, 44.0), reach = 0.0, scale = 3.0)
                val dropped = book.drop(1)
                val rebooked = book.rebook()
                keptEveryHolder = keptEveryHolder && !dropped && !rebooked && book.entries[1]?.top == cut
            }
            check("T0060 nit 1: every 3x holder survives roundoff at the cut", roundedApart > 0 && keptEveryHolder)
        }

        // Nit 2: only disappeared parts below the current cut may be retained.
        run {
            val book = WardPartLedger<Int>()
            book.cut = 682.0
            book.set(1, "old holder", rect(0.0, 682.0, 100.0, 44.0), reach = 0.0, scale = 3.0)
            book.set(2, "live row", rect(0.0, 600.0, 100.0, 44.0), reach = 0.0, scale = 3.0)
            book.drop(1)
            book.cut = 686.0
            val pruned = book.rebook()
            val prunedGhost = pruned && book.entries[1] == null && book.sightings[1] == null && book.told == listOf(600.0) &&
                HomeFit.settledCut(686.0, book.tops) == 686.0
            book.set(3, "reappeared", rect(0.0, 690.0, 100.0, 44.0), reach = 0.0, scale = 3.0)
            book.drop(3)
            book.set(3, "reappeared", rect(0.0, 680.0, 100.0, 44.0), reach = 0.0, scale = 3.0)
            book.rebook()
            val reappeared = book.entries[3]?.top == 680.0
            book.set(4, "hidden", rect(0.0, 700.0, 100.0, 44.0), reach = 0.0, scale = 3.0)
            book.drop(4)
            book.cut = null
            book.rebook()
            check("T0060 nit 2: rebook prunes ghosts above or without a cut, keeping live and reappeared rows",
                prunedGhost && reappeared && book.entries[4] == null && book.sightings[4] == null)
        }

        // Nit 3: the holder hides on the last moving frame, before the rest event.
        run {
            val book = WardPartLedger<Int>()
            book.cut = 680.0
            book.set(1, "More ways to practise", rect(0.0, 680.0, 300.0, 44.0), reach = 0.0, scale = 3.0)
            var publishedWhileMoving = false
            for (y in listOf(620.0, 650.0, 680.0)) {
                publishedWhileMoving = book.set(1, "More ways to practise", rect(0.0, y, 300.0, 44.0), reach = 0.0, scale = 3.0, atRest = false) ||
                    publishedWhileMoving
            }
            val dropped = book.drop(1, atRest = false)
            val rested = book.rebook()
            val keptHolder = !publishedWhileMoving && !dropped && !rested && book.entries[1]?.top == 680.0 &&
                book.sightings[1] != null && book.told == listOf(680.0) && HomeFit.settledCut(686.0, book.tops) == 680.0
            // The previous rest frame must not protect a row that is now above the cut.
            book.set(1, "More ways to practise", rect(0.0, 679.9, 300.0, 44.0), reach = 0.0, scale = 3.0, atRest = false)
            book.drop(1, atRest = false)
            book.rebook()
            check("T0060 nit 3: keep a self-topped holder through moving drop/rest, but recycle above-cut rows",
                keptHolder && book.entries.isEmpty() && book.sightings.isEmpty() && book.told.isEmpty())
        }

        // Nit 4: switching sections may leave pageCut numerically unchanged.
        run {
            val book = WardPartLedger<Int>()
            book.cut = 682.0
            book.set(1, "old page", rect(0.0, 682.0, 100.0, 44.0), reach = 0.0, scale = 3.0)
            book.drop(1)
            book.clear()
            book.rebook()
            val cleared = book.entries.isEmpty() && book.sightings.isEmpty() && book.told.isEmpty()
            book.set(2, "new page", rect(0.0, 682.0, 100.0, 44.0), reach = 0.0, scale = 3.0)
            val dropped = book.drop(2)
            check("T0060 nit 4: clear empties the book while preserving an unchanged cut",
                cleared && book.cut == 682.0 && !dropped && book.entries[2]?.top == 682.0)
        }
    }

    @Test fun dropOutcomes() = checks {
        val book = WardPartLedger<Int>()
        book.cut = 680.0
        book.set(1, "chip", rect(0.0, 690.0, 60.0, 18.0), reach = 0.0, scale = 3.0)
        book.set(2, "row", rect(0.0, 600.0, 300.0, 50.0), reach = 0.0, scale = 3.0)
        val keptDrop = book.dropOutcome(1)
        val removedDrop = book.dropOutcome(2)
        val missingDrop = book.dropOutcome(99)
        check("drop reports kept below cut", keptDrop == WardPartLedger.Drop.kept && book.entries[1]?.top == 690.0)
        check("drop reports removed", removedDrop == WardPartLedger.Drop.removed && book.entries[2] == null)
        check("drop reports no such part", missingDrop == WardPartLedger.Drop.none)
    }

    @Test fun aPushAndBackShowsHomeCovered() = checks {
        // AX5 on the SE's size: every face booked lies below home's cut at 670
        val se = listOf(682.0, 971.0, 1142.0, 1219.0, 1765.0, 1812.0, 2071.0)
        check("push: kept drops show home covered when every face is below the cut", HomeFit.pushCovered(se, 670.0, removed = 0, kept = 3))
        check("push: no drop at all is no push", !HomeFit.pushCovered(se, 670.0, removed = 0, kept = 0))
        // AX5 on the phone: the round card stands above the cut at 640
        val phone = listOf(589.0, 878.0, 1177.0, 1247.0, 1775.0, 1844.0)
        check("push: a part above the cut must leave the book", !HomeFit.pushCovered(phone, 640.0, removed = 0, kept = 5))
        check("push: a part leaving the book shows home covered", HomeFit.pushCovered(phone, 640.0, removed = 1, kept = 5))
        check("push: an uncut page needs a part to leave", !HomeFit.pushCovered(listOf(100.0, 300.0), null, removed = 0, kept = 2))
        check("push: a face on the cut is below it", HomeFit.pushCovered(listOf(682.3333333333333), 682.3333333333333, removed = 0, kept = 1))
    }
}
