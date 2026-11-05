package com.stethoscore.app.widget

import androidx.compose.ui.unit.DpSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import com.stethoscore.app.data.GlanceDigest
import com.stethoscore.app.data.GlanceState
import com.stethoscore.app.exam.ExamCatalog
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.ward.WardType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

/**
 * The widgets' room budget (WidgetFit): every face at every size its widget
 * lists, in every state, draws the glyph, the number and the caption with at
 * least WidgetStyle.gap between glyph and number and nothing cut; every
 * one-line text fits the line at its least width; the fit measures at the
 * system's font scale.
 */
class WidgetFitTest {
    private val utc: ZoneId = ZoneId.of("UTC")
    private fun at(iso: String): Long = Instant.parse(iso).toEpochMilli()
    private val now = at("2026-11-05T10:00:00Z")
    private val midnight = at("2026-11-05T00:00:00Z")
    private val day = 86_400_000L
    private val digest = GlanceDigest(
        madeAt = at("2026-11-05T08:30:00Z"), dueNow = 24,
        topDecks = listOf(GlanceDigest.DueDeck("7C9E6679-7425-40DE-944B-E07FC1F90AE7", "Cardiology", 14)),
        examName = "Step 1", examDate = midnight + 90 * day, today = 32, goal = 50,
    )

    /** The sizes a widget lists for Glance, which hands its layout one of them (SizeMode.Responsive). */
    private fun sizes(widget: GlanceAppWidget): Set<DpSize> = (widget.sizeMode as SizeMode.Responsive).sizes
    private val captionSize = WardType.caption.size
    private fun DpSize.w() = width.value.toDouble()
    private fun DpSize.h() = height.value.toDouble()

    // every state

    private val dueStates: List<GlanceState> = listOf(24, 1, 120, 1200, 9999).map { GlanceState.CardsDue(digest, it) } +
        GlanceState.NothingDue(digest.copy(dueNow = 0, topDecks = emptyList())) + GlanceState.NoFile

    /** Each name the countdown can give (the catalogue's short names, the tracks', Finals) and a longer one. */
    private val examNames: List<String?> = ExamCatalog.all.map { it.shortName } +
        ExamTrack.entries.filter { it != ExamTrack.general }.map { it.rawValue.uppercase() } + null + "MRCP Part 1"

    private val countdownStates: List<GlanceState> =
        examNames.flatMap { name -> listOf(0, 1, 9, 90, 365, 999).map { GlanceState.CardsDue(digest.copy(examName = name, examDate = midnight + it * day), 24) } } +
            GlanceState.CardsDue(digest.copy(examDate = null), 24) +
            GlanceState.CardsDue(digest.copy(examDate = midnight - 4 * day), 24) + GlanceState.NoFile

    private val todayStates: List<GlanceState> =
        listOf(32 to 50, 0 to 50, 120 to 150, 300 to 300, 1200 to 300, 9999 to 10).map { (done, goal) ->
            GlanceState.CardsDue(digest.copy(today = done, goal = goal), 24)
        } + GlanceState.NoFile

    private val countdowns get() = countdownStates.map { CountdownFace.of(it, now, utc) }
    private val todays get() = todayStates.map { TodayFace.of(it, now, utc) }

    // the budget

    /** The stack at [room] for [number] and [captions] (the face's whole caption first), at the font [scale], checked as it draws. */
    private fun assertFits(what: String, number: String, captions: List<String>, room: FaceRoom, scale: Double = 1.0): StackFit {
        val fit = NumberStack.fit(number, captions, room, scale)
        val lines = WidgetText.lines(fit.caption, captionSize * scale, bold = false, widthDp = room.width)
        val clearance = NumberStack.clearance(room.height, fit.numberSize, fit.captionLines, number == WidgetWords.noNumber, scale)
        val label = "$what at ${scale}x in $room: \"$number\" at ${fit.numberSize} sp, \"${fit.caption}\""
        assertTrue("$label: glyph and number $clearance dp apart, under ${WidgetStyle.gap}", clearance >= WidgetStyle.gap)
        assertTrue("$label: the number is cut", WidgetText.width(number, fit.numberSize * scale, bold = true) <= room.width)
        assertTrue("$label: the caption takes $lines lines", lines <= NumberStack.captionLines)
        assertEquals(label, lines, fit.captionLines)
        assertTrue("$label: the dash stands below the room's foot", fit.captionHeight - fit.dashDrop >= 0)
        return fit
    }

    @Test fun everyFaceFitsEverySizeItsWidgetListsInEveryState() {
        var checked = 0
        for (size in sizes(DueCardsWidget())) for (state in dueStates) {
            val face = DueFace.of(state)
            // as DueCards lays it out: the medium's left column from 200 dp wide, else the 2x2
            val room = if (DueLayout.isMedium(size.w())) FaceRoom.mediumLeft(size.w(), size.h()) else FaceRoom.small(size.w(), size.h())
            val fit = assertFits("Due $size", face.number, face.captions, room)
            if (face.hasFile) assertEquals("with a file the caption is never swapped", face.caption, fit.caption)
            checked++
        }
        for ((widget, faces) in listOf(ExamCountdownWidget() to countdowns.map { it.number to it.captions to it.hasFile },
            DoneTodayWidget() to todays.map { it.number to it.captions to it.hasFile })) {
            // the one-line sizes are checked below; the rest draw the 2x2
            for (size in sizes(widget).filter { it.h() >= WidgetSizes.oneLineHeight }) for ((pair, hasFile) in faces) {
                val (number, captions) = pair
                val fit = assertFits("${widget::class.simpleName} $size", number, captions, FaceRoom.small(size.w(), size.h()))
                if (hasFile) assertEquals(captions.first(), fit.caption)
                checked++
            }
        }
        assertTrue("each widget, its sizes and states: $checked", checked > 300)
    }

    @Test fun theNumberStepsDownOnlyWhereItMust() {
        val floor = FaceRoom.small(WidgetSizes.smallFloor.w(), WidgetSizes.smallFloor.h())
        val small = FaceRoom.small(WidgetSizes.small.w(), WidgetSizes.small.h())
        assertEquals(FaceRoom(78.0, 86.0), floor)
        assertEquals(FaceRoom(78.0, 98.0), small)
        val today = TodayFace.of(GlanceState.CardsDue(digest, 24), now, utc)
        // "of 50 done today" takes two lines in 78 dp: 34 sp from 122 dp tall (w06), 22 sp below it (w06b)
        assertEquals(34.0, NumberStack.fit(today.number, today.captions, small, 1.0).numberSize, 0.0)
        assertEquals(22.0, NumberStack.fit(today.number, today.captions, floor, 1.0).numberSize, 0.0)
        // "due now" takes one: 44 sp from 122 dp tall (w01), 34 sp at the floor (w01b)
        val due = DueFace.of(GlanceState.CardsDue(digest, 24))
        assertEquals(44.0, NumberStack.fit(due.number, due.captions, small, 1.0).numberSize, 0.0)
        assertEquals(34.0, NumberStack.fit(due.number, due.captions, floor, 1.0).numberSize, 0.0)
        // three digits at 44 sp are wider than 78 dp: 34 sp, as iOS's minimumScaleFactor shrinks them
        assertEquals(34.0, NumberStack.fit("120", due.captions, small, 1.0).numberSize, 0.0)
        val longName = CountdownFace.of(GlanceState.CardsDue(digest.copy(examName = "MRCP Part 1"), 24), now, utc)
        assertEquals("days to MRCP Part 1", longName.caption)
        assertEquals(2, NumberStack.fit(longName.number, longName.captions, floor, 1.0).captionLines)
        assertEquals(2, NumberStack.fit(longName.number, longName.captions, small, 1.0).captionLines)
        assertEquals(22.0, NumberStack.fit(longName.number, longName.captions, floor, 1.0).numberSize, 0.0)
        // a two-line exam name at 110x122 (w04c) steps down as Done today's two-line caption does
        assertEquals(34.0, NumberStack.fit(longName.number, longName.captions, small, 1.0).numberSize, 0.0)
        assertEquals(listOf(44.0, 34.0, 28.0, 22.0), NumberStack.numberSizes)
    }

    @Test fun theGlyphKeepsTheGapIOSKeepsAboveTheNumber() {
        // iOS's bigCount: VStack(spacing: 4) with a Spacer between the glyph and the number (DueCardsWidget.swift:127-131)
        assertEquals(4.0, WidgetStyle.gap, 0.0)
        val small = FaceRoom.small(WidgetSizes.small.w(), WidgetSizes.small.h())
        val floor = FaceRoom.small(WidgetSizes.smallFloor.w(), WidgetSizes.smallFloor.h())
        val today = TodayFace.of(GlanceState.CardsDue(digest, 24), now, utc)
        val due = DueFace.of(GlanceState.CardsDue(digest, 24))
        // w06 and w01b met or crowded the glyph at 44 sp; at 44 sp they would still be under the gap
        assertTrue(NumberStack.clearance(small.height, 44.0, 2, dash = false, scale = 1.0) < WidgetStyle.gap)
        assertTrue(NumberStack.clearance(floor.height, 44.0, 1, dash = false, scale = 1.0) < WidgetStyle.gap)
        assertEquals(34.0, assertFits("w06", today.number, today.captions, small).numberSize, 0.0)
        assertEquals(34.0, assertFits("w01b", due.number, due.captions, floor).numberSize, 0.0)
    }

    // the system's font scale

    @Test fun theFitMeasuresAtTheSystemFontScale() {
        val small = FaceRoom.small(WidgetSizes.small.w(), WidgetSizes.small.h())
        val today = TodayFace.of(GlanceState.CardsDue(digest, 24), now, utc)
        // at 1.3x the caption is 15.6 dp and "of 50 done today" still takes two lines: the number steps to 22 sp (w06c)
        val large = assertFits("w06c", today.number, today.captions, small, 1.3)
        assertEquals(22.0, large.numberSize, 0.0)
        assertEquals(2, large.captionLines)
        assertTrue("the caption's height grows with the font", large.captionHeight > NumberStack.fit(today.number, today.captions, small, 1.0).captionHeight)
        // the one-line size: "Step 1 today" fits 78 dp at 1.0x, at 1.3x the short form does
        val line = FaceRoom.oneLine(WidgetSizes.oneLine.w(), WidgetSizes.oneLine.h())
        val examDay = CountdownFace.of(GlanceState.CardsDue(digest.copy(examDate = midnight), 24), now, utc)
        assertEquals("Step 1 today", OneLineFit.pick(examDay.lineForms, line, 1.0))
        assertEquals("Today", OneLineFit.pick(examDay.lineForms, line, 1.3))
        assertFalse(OneLineFit.fits("Step 1 today", line, 1.3))
    }

    @Test fun atATextSizeOf130PercentTheMediumAndThe122dp2x2StillFit() {
        val scale = 1.3
        var checked = 0
        for (size in sizes(DueCardsWidget()).filter { DueLayout.isMedium(it.w()) }) for (state in dueStates) {
            val face = DueFace.of(state)
            assertFits("Due $size", face.number, face.captions, FaceRoom.mediumLeft(size.w(), size.h()), scale)
            checked++
        }
        val small = FaceRoom.small(WidgetSizes.small.w(), WidgetSizes.small.h())
        val faces = dueStates.map { DueFace.of(it).let { f -> f.number to f.captions } } +
            countdowns.map { it.number to it.captions } + todays.map { it.number to it.captions }
        val tooLong = mutableSetOf<String>()
        for ((number, captions) in faces) {
            // a caption that takes three lines at 15.6 dp in 78 dp cannot show whole on the ladder alone (T0206's notes)
            if (captions.none { WidgetText.lines(it, captionSize * scale, bold = false, widthDp = small.width) <= NumberStack.captionLines }) {
                tooLong += captions.last()
                continue
            }
            assertFits("2x2 ${WidgetSizes.small}", number, captions, small, scale)
            checked++
        }
        assertEquals(setOf(WidgetWords.openApp, "day to MRCP Part 1", "days to MRCP Part 1"), tooLong)
        assertTrue("faces checked at 1.3x: $checked", checked > 150)
    }

    // the no-file dash

    @Test fun theNoFileDashSitsAsNearItsCaptionAsANumber() {
        val floor = FaceRoom.small(WidgetSizes.smallFloor.w(), WidgetSizes.smallFloor.h())
        val left = FaceRoom.mediumLeft(WidgetSizes.medium.w(), WidgetSizes.medium.h())
        val noFile = DueFace.of(GlanceState.NoFile)
        // w03 at the floor; at 1.3x the medium's column, as "Open Stethoscore" takes three lines in a 2x2 there
        for ((room, scale) in listOf(floor to 1.0, left to 1.0, left to 1.3)) {
            val fit = assertFits("no file", noFile.number, noFile.captions, room, scale)
            val size = fit.numberSize * scale
            // a number's box stands on its caption and its ink on its baseline, the box's foot padding over the caption
            val footPadding = size * WidgetText.below + WidgetText.lineRounding
            val numberGap = footPadding
            // the dash's box stands dashDrop lower, its ink dashFoot em over its baseline
            val dashGap = (fit.captionHeight - fit.dashDrop) + footPadding + size * WidgetText.dashFoot - fit.captionHeight
            assertEquals("at ${scale}x", numberGap, dashGap, 1e-9)
            assertEquals(size * WidgetText.dashFoot, fit.dashDrop, 1e-9)
        }
        // at 44 sp the dash comes down about 13 dp, which it stood higher than a number before T0206
        val fit = NumberStack.fit(noFile.number, noFile.captions, floor, 1.0)
        assertEquals(44.0, fit.numberSize, 0.0)
        assertEquals(12.9, fit.dashDrop, 0.1)
        assertEquals("a number is not moved", 0.0, NumberStack.fit("24", listOf("due now"), floor, 1.0).dashDrop, 0.0)
    }

    @Test fun withNoFileA2x2SaysOpenStethoscoreAndTheMediumSaysItAll() {
        val floor = FaceRoom.small(WidgetSizes.smallFloor.w(), WidgetSizes.smallFloor.h())
        val countdown = CountdownFace.of(GlanceState.NoFile, now, utc)
        // "Open Stethoscore to see your countdown" takes four lines in 78 dp; TalkBack still reads it whole (spoken)
        assertEquals(4, WidgetText.lines(countdown.caption, captionSize, bold = false, widthDp = floor.width))
        assertEquals(WidgetWords.openApp, NumberStack.fit(countdown.number, countdown.captions, floor, 1.0).caption)
        assertEquals(countdown.caption, countdown.spoken)
        val due = DueFace.of(GlanceState.NoFile)
        assertEquals(WidgetWords.openApp, NumberStack.fit(due.number, due.captions, floor, 1.0).caption)
        val left = FaceRoom.mediumLeft(WidgetSizes.medium.w(), WidgetSizes.medium.h())
        assertEquals(101.0, left.width, 0.0)
        assertEquals(due.caption, NumberStack.fit(due.number, due.captions, left, 1.0).caption)
    }

    // the one-line sizes

    @Test fun everyOneLineTextFitsAt110dpWithoutAnEllipsis() {
        // widget_countdown.xml and widget_today.xml resize to 110 dp wide and 40 dp tall
        val faces = countdowns.map { it.line to it.lineForms } + todays.map { it.line to it.lineForms }
        for (widget in listOf(ExamCountdownWidget(), DoneTodayWidget())) {
            val lines = sizes(widget).filter { it.h() < WidgetSizes.oneLineHeight }
            assertEquals(listOf(WidgetSizes.oneLine), lines)
            for (size in lines) for (height in listOf(size.h(), 40.0)) {
                val room = FaceRoom.oneLine(size.w(), height)
                for ((line, forms) in faces) {
                    assertEquals("TalkBack reads the sentence, the first form", line, forms.first())
                    val picked = OneLineFit.pick(forms, room, 1.0)
                    assertTrue("\"$picked\" (for \"$line\") in $room", OneLineFit.fits(picked, room, 1.0))
                }
            }
        }
    }

    @Test fun theSentencesTooWideAt110dpGiveWayToShortForms() {
        val room = FaceRoom.oneLine(WidgetSizes.oneLine.w(), WidgetSizes.oneLine.h())
        assertEquals(78.0, room.width, 0.0)
        // at the footnote size, the line's least, the sentences are still wider than 78 dp
        for (sentence in listOf("Open Stethoscore", "Step 1 in 90 days", "32 of 50 done today")) {
            assertFalse(sentence, OneLineFit.fits(sentence, room, 1.0))
        }
        fun line(state: GlanceState) = CountdownFace.of(state, now, utc).let { OneLineFit.pick(it.lineForms, room, 1.0) }
        assertEquals("Open app", line(GlanceState.NoFile))
        assertEquals("90 days", line(GlanceState.CardsDue(digest, 24)))
        assertEquals("Tomorrow", line(GlanceState.CardsDue(digest.copy(examDate = midnight + day), 24)))
        assertEquals("the sentence where it fits", "Step 1 today", line(GlanceState.CardsDue(digest.copy(examDate = midnight), 24)))
        assertEquals("Today", line(GlanceState.CardsDue(digest.copy(examName = "MRCP Part 1", examDate = midnight), 24)))
        assertEquals("Set a date", line(GlanceState.CardsDue(digest.copy(examDate = null), 24)))
        fun today(done: Int, goal: Int) = TodayFace.of(GlanceState.CardsDue(digest.copy(today = done, goal = goal), 24), now, utc)
            .let { OneLineFit.pick(it.lineForms, room, 1.0) }
        assertEquals("32/50 today", today(32, 50))
        assertEquals("120/150", today(120, 150))
        assertEquals("Open app", OneLineFit.pick(TodayFace.of(GlanceState.NoFile, now, utc).lineForms, room, 1.0))
    }

    // the model against CI's pictures

    @Test fun theTextModelMatchesTheWidgetPicturesMeasuredOnCI() {
        // ink widths measured in Android CI run 42014339195's widget pictures (2.625 px a dp); the model
        // takes each letter's whole advance and its slack, so it may be wider than the ink, never narrower
        val measured = listOf(
            Triple("of 50 done today", false, 87.6), Triple("days to Step 1", false, 71.6),
            Triple("due now", false, 43.4), Triple("Open Stethoscore to", false, 105.5),
        ).map { Triple(it.first, 12.0 to it.second, it.third) } + listOf(
            Triple("32 of 50 done", true, 103.6), Triple("today", true, 42.3),
            Triple("Step 1 in 90", true, 89.1), Triple("days", true, 35.05),
        ).map { Triple(it.first, 17.0 to it.second, it.third) }
        for ((text, face, ink) in measured) {
            val model = WidgetText.width(text, face.first, face.second)
            assertTrue("\"$text\": $model dp against $ink", model >= ink && model <= ink * 1.08)
        }
        // the 44 sp number and one and two lines of 12 sp caption draw 59, 16.4 and 30.9 dp tall: the model as tall or
        // taller, by under a dp
        for ((model, picture) in listOf(WidgetText.height(WidgetStyle.numberSize) to 59.0, WidgetText.height(captionSize) to 16.4,
            WidgetText.height(captionSize, 2) to 30.9)) {
            assertTrue("$model dp against $picture", model >= picture && model <= picture + 1.0)
        }
        assertEquals("a word wider than the line breaks inside it", 2, WidgetText.lines("Stethoscore", 12.0, false, 40.0))
    }

    @Test fun theClearanceIsNeverMoreGenerousThanThePictures() {
        // T0206's check of the same run's pictures (2.625 px a dp). w06-today-small, 110x122, "32" at 44 sp over a
        // two-line caption: the glyph's 24 dp box ends at 94.5 px and the digits' ink starts at 93 px, -0.57 dp.
        // w01b-due-small-floor, 110x110, "24" at 44 sp over one line: 1.7 dp. The model may be more careful than the
        // pictures, by under a dp, never less.
        val small = FaceRoom.small(WidgetSizes.small.w(), WidgetSizes.small.h())
        val floor = FaceRoom.small(WidgetSizes.smallFloor.w(), WidgetSizes.smallFloor.h())
        for ((model, picture) in listOf(NumberStack.clearance(small.height, 44.0, 2, dash = false, scale = 1.0) to (93.0 - 94.5) / 2.625,
            NumberStack.clearance(floor.height, 44.0, 1, dash = false, scale = 1.0) to 1.7)) {
            assertTrue("$model dp against $picture", model <= picture && model >= picture - 1.0)
        }
    }
}
