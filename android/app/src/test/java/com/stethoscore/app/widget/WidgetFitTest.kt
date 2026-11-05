package com.stethoscore.app.widget

import android.content.Context
import android.content.res.Configuration
import androidx.compose.ui.unit.DpSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.GlanceDigest
import com.stethoscore.app.data.GlanceState
import com.stethoscore.app.exam.ExamCatalog
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.ward.WardType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.time.ZoneId

private fun DpSize.w() = width.value.toDouble()
private fun DpSize.h() = height.value.toDouble()
private fun DpSize.label() = "${w().toInt()}x${h().toInt()}"

/** The sizes a widget lists for Glance, which hands its layout one of them (SizeMode.Responsive). */
private fun sizes(widget: GlanceAppWidget): Set<DpSize> = (widget.sizeMode as SizeMode.Responsive).sizes

/**
 * Every face each widget can show, at every size it lists, in every state,
 * and the sweep that checks them at a font scale as they draw: nothing meets,
 * nothing is squeezed, the glyph keeps its gap or gives way only where no
 * number size keeps it, and only what still does not fit takes the last
 * resort (WidgetFitTest, WidgetTextScaleTest).
 */
internal object EveryFace {
    val utc: ZoneId = ZoneId.of("UTC")
    fun at(iso: String): Long = Instant.parse(iso).toEpochMilli()
    val now = at("2026-11-05T10:00:00Z")
    val midnight = at("2026-11-05T00:00:00Z")
    const val day = 86_400_000L
    val digest = GlanceDigest(
        madeAt = at("2026-11-05T08:30:00Z"), dueNow = 24,
        topDecks = listOf(GlanceDigest.DueDeck("7C9E6679-7425-40DE-944B-E07FC1F90AE7", "Cardiology", 14)),
        examName = "Step 1", examDate = midnight + 90 * day, today = 32, goal = 50,
    )
    val captionSize = WardType.caption.size

    val dueStates: List<GlanceState> = listOf(24, 1, 120, 1200, 9999).map { GlanceState.CardsDue(digest, it) } +
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

    val countdowns: List<CountdownFace> get() = countdownStates.map { CountdownFace.of(it, now, utc) }
    val todays: List<TodayFace> get() = todayStates.map { TodayFace.of(it, now, utc) }

    /** One big-number face in the room its widget lays it out in, at one of the sizes it lists. */
    class Stack(val widget: String, val size: DpSize, val number: String, val captions: List<String>, val hasFile: Boolean, val room: FaceRoom)

    /** As DueCards, ExamCountdown and DoneToday lay them out: the medium's left column from 200 dp wide, else the 2x2. */
    val stacks: List<Stack> get() = buildList {
        for (size in sizes(DueCardsWidget())) for (state in dueStates) {
            val face = DueFace.of(state)
            val room = if (DueLayout.isMedium(size.w())) FaceRoom.mediumLeft(size.w(), size.h()) else FaceRoom.small(size.w(), size.h())
            add(Stack("Due", size, face.number, face.captions, face.hasFile, room))
        }
        val faces = listOf(
            Triple("Countdown", ExamCountdownWidget(), countdowns.map { Triple(it.number, it.captions, it.hasFile) }),
            Triple("Today", DoneTodayWidget(), todays.map { Triple(it.number, it.captions, it.hasFile) }),
        )
        for ((name, widget, list) in faces) for (size in sizes(widget).filter { it.h() >= WidgetSizes.oneLineHeight }) {
            for ((number, captions, hasFile) in list) add(Stack(name, size, number, captions, hasFile, FaceRoom.small(size.w(), size.h())))
        }
    }

    /** The one-line sizes' words, TalkBack's sentence first. */
    val lineForms: List<List<String>> get() = countdowns.map { it.lineForms } + todays.map { it.lineForms }

    /** [stack] at [scale], checked as it draws. */
    fun check(stack: Stack, scale: TextScale, name: String): StackFit {
        val room = stack.room
        val fit = NumberStack.fit(stack.number, stack.captions, room, scale)
        val dash = stack.number == WidgetWords.noNumber
        val label = "$name ${stack.widget} ${stack.size.label()}: \"${stack.number}\" at ${fit.numberSize} sp, \"${fit.caption}\" on ${fit.captionLines}"
        val needed = WidgetText.lines(fit.caption, scale.dp(captionSize), bold = false, widthDp = room.width)
        fun across(sp: Double) = WidgetText.width(stack.number, scale.dp(sp), bold = true) <= room.width
        fun stands(sp: Double) = NumberStack.headroom(room.height, sp, needed, dash, scale) >= 0
        fun clear(sp: Double) = NumberStack.clearance(room.height, sp, needed, dash, scale) >= WidgetStyle.gap
        // nothing meets: the number's box and the caption's lines stand one on the other inside the room, so Android
        // squeezes neither, and the glyph, where it is drawn, keeps the gap above the number's ink
        assertTrue("$label: squeezed", NumberStack.headroom(room.height, fit.numberSize, fit.captionLines, dash, scale) >= 0)
        assertTrue("$label: the dash stands below the room's foot", fit.captionHeight - fit.dashDrop >= 0)
        assertTrue(label, fit.captionLines in 1..NumberStack.captionLines)
        if (fit.glyph) {
            val clearance = NumberStack.clearance(room.height, fit.numberSize, fit.captionLines, dash, scale)
            assertTrue("$label: glyph and number $clearance dp apart", clearance >= WidgetStyle.gap)
        }
        if (stack.hasFile) assertEquals("$label: with a file the caption is never swapped", stack.captions.first(), fit.caption)
        // the largest size that fits whole with the glyph; else without it; else the last resort
        val withGlyph = if (needed <= NumberStack.captionLines) NumberStack.numberSizes.firstOrNull { across(it) && stands(it) && clear(it) } else null
        val without = if (needed <= NumberStack.captionLines) NumberStack.numberSizes.firstOrNull { across(it) && stands(it) } else null
        when {
            withGlyph != null -> {
                assertTrue("$label: the glyph gave way where $withGlyph sp keeps it", fit.glyph)
                assertEquals(label, withGlyph, fit.numberSize, 0.0)
            }
            without != null -> {
                assertFalse("$label: the glyph is drawn without its gap", fit.glyph)
                assertEquals(label, without, fit.numberSize, 0.0)
            }
            else -> assertEquals("$label: the last resort is the ladder's foot", NumberStack.numberSizes.last(), fit.numberSize, 0.0)
        }
        assertEquals("$label: the last resort only where nothing fits whole", without == null, fit.lastResort)
        if (!fit.lastResort) assertEquals("$label: the caption whole", needed, fit.captionLines)
        return fit
    }

    /**
     * Every face at [scale]: each checked as it draws, and each one-line text
     * at the one-line size's 48 dp and its least 40 dp. Prints, and returns,
     * for each size how many faces keep the glyph, give it way and take the
     * last resort, and names those that take it.
     */
    fun sweep(scale: TextScale, name: String): Map<String, IntArray> {
        val counts = linkedMapOf<String, IntArray>()
        val lastResort = linkedMapOf<String, MutableSet<String>>()
        for (stack in stacks) {
            val fit = check(stack, scale, name)
            val count = counts.getOrPut(stack.size.label()) { IntArray(3) }
            when {
                fit.lastResort -> count[2]++
                fit.glyph -> count[0]++
                else -> count[1]++
            }
            if (fit.lastResort) {
                val cut = WidgetText.width(stack.number, scale.dp(fit.numberSize), bold = true) > stack.room.width
                lastResort.getOrPut(stack.size.label()) { linkedSetOf() } +=
                    "${stack.widget} \"${stack.number}\"${if (cut) " (cut)" else ""} / \"${fit.caption}\" on ${fit.captionLines}"
            }
        }
        val line = IntArray(3)
        val shortest = linkedSetOf<String>()
        for (widget in listOf(ExamCountdownWidget(), DoneTodayWidget())) {
            for (size in sizes(widget).filter { it.h() < WidgetSizes.oneLineHeight }) for (height in listOf(size.h(), OneLineFit.leastHeight)) {
                val room = FaceRoom.oneLine(size.w(), height, OneLineFit.margin(scale))
                assertTrue("$name: a ${OneLineFit.lineHeight(scale)} dp line is squeezed in $room", OneLineFit.lineHeight(scale) <= room.height)
                for (forms in lineForms) {
                    val picked = OneLineFit.pick(forms, room, scale)
                    if (OneLineFit.fits(picked, room, scale)) {
                        line[0]++
                        assertEquals("$name: the first form that fits", forms.first { OneLineFit.fits(it, room, scale) }, picked)
                    } else {
                        line[2]++
                        assertTrue("$name: \"$picked\" though a form fits", forms.none { OneLineFit.fits(it, room, scale) })
                        assertEquals("$name: the shortest form, ended with an ellipsis", forms.last(), picked)
                        shortest += picked
                    }
                }
            }
        }
        counts["one line (48 and 40 dp)"] = line
        println("$name: per size [with the glyph, glyph gives way, last resort]")
        for ((size, count) in counts) println("  $size: ${count.toList()}")
        for ((size, faces) in lastResort) println("  last resort at $size (${faces.size}): ${faces.joinToString("; ")}")
        if (shortest.isNotEmpty()) println("  one line ellipsized (${shortest.size}): ${shortest.joinToString("; ")}")
        return counts
    }
}

/**
 * The widgets' room budget (WidgetFit): every face at every size its widget
 * lists, in every state, draws the glyph, the number and the caption with at
 * least WidgetStyle.gap between glyph and number and nothing cut; every
 * one-line text fits the line at its least width; at a larger font the fit
 * steps down, the glyph gives way, and nothing meets.
 */
class WidgetFitTest {
    private val utc = EveryFace.utc
    private val now = EveryFace.now
    private val midnight = EveryFace.midnight
    private val day = EveryFace.day
    private val digest = EveryFace.digest
    private val captionSize = EveryFace.captionSize
    private val one = TextScale.linear(1.0)

    // the budget

    /** The stack at [room] for [number] and [captions] (the face's whole caption first), at [scale]: whole, with the glyph. */
    private fun assertFits(what: String, number: String, captions: List<String>, room: FaceRoom, scale: TextScale = one): StackFit {
        val fit = NumberStack.fit(number, captions, room, scale)
        val lines = WidgetText.lines(fit.caption, scale.dp(captionSize), bold = false, widthDp = room.width)
        val clearance = NumberStack.clearance(room.height, fit.numberSize, fit.captionLines, number == WidgetWords.noNumber, scale)
        val label = "$what in $room: \"$number\" at ${fit.numberSize} sp, \"${fit.caption}\""
        assertTrue("$label: the glyph gave way", fit.glyph)
        assertFalse("$label: the last resort", fit.lastResort)
        assertTrue("$label: glyph and number $clearance dp apart, under ${WidgetStyle.gap}", clearance >= WidgetStyle.gap)
        assertTrue("$label: the number is cut", WidgetText.width(number, scale.dp(fit.numberSize), bold = true) <= room.width)
        assertTrue("$label: the caption takes $lines lines", lines <= NumberStack.captionLines)
        assertEquals(label, lines, fit.captionLines)
        assertTrue("$label: squeezed", NumberStack.headroom(room.height, fit.numberSize, fit.captionLines, number == WidgetWords.noNumber, scale) >= 0)
        assertTrue("$label: the dash stands below the room's foot", fit.captionHeight - fit.dashDrop >= 0)
        return fit
    }

    @Test fun everyFaceFitsEverySizeItsWidgetListsInEveryState() {
        val stacks = EveryFace.stacks
        for (stack in stacks) {
            val fit = assertFits("${stack.widget} ${stack.size}", stack.number, stack.captions, stack.room)
            if (stack.hasFile) assertEquals("with a file the caption is never swapped", stack.captions.first(), fit.caption)
        }
        assertTrue("each widget, its sizes and states: ${stacks.size}", stacks.size > 300)
    }

    @Test fun theNumberStepsDownOnlyWhereItMust() {
        val floor = FaceRoom.small(WidgetSizes.smallFloor.w(), WidgetSizes.smallFloor.h())
        val small = FaceRoom.small(WidgetSizes.small.w(), WidgetSizes.small.h())
        assertEquals(FaceRoom(78.0, 86.0), floor)
        assertEquals(FaceRoom(78.0, 98.0), small)
        val today = TodayFace.of(GlanceState.CardsDue(digest, 24), now, utc)
        // "of 50 done today" takes two lines in 78 dp: 34 sp from 122 dp tall (w06), 22 sp below it (w06b)
        assertEquals(34.0, NumberStack.fit(today.number, today.captions, small, one).numberSize, 0.0)
        assertEquals(22.0, NumberStack.fit(today.number, today.captions, floor, one).numberSize, 0.0)
        // "due now" takes one: 44 sp from 122 dp tall (w01), 34 sp at the floor (w01b)
        val due = DueFace.of(GlanceState.CardsDue(digest, 24))
        assertEquals(44.0, NumberStack.fit(due.number, due.captions, small, one).numberSize, 0.0)
        assertEquals(34.0, NumberStack.fit(due.number, due.captions, floor, one).numberSize, 0.0)
        // three digits at 44 sp are wider than 78 dp: 34 sp, as iOS's minimumScaleFactor shrinks them
        assertEquals(34.0, NumberStack.fit("120", due.captions, small, one).numberSize, 0.0)
        val longName = CountdownFace.of(GlanceState.CardsDue(digest.copy(examName = "MRCP Part 1"), 24), now, utc)
        assertEquals("days to MRCP Part 1", longName.caption)
        assertEquals(2, NumberStack.fit(longName.number, longName.captions, floor, one).captionLines)
        assertEquals(2, NumberStack.fit(longName.number, longName.captions, small, one).captionLines)
        assertEquals(22.0, NumberStack.fit(longName.number, longName.captions, floor, one).numberSize, 0.0)
        // a two-line exam name at 110x122 (w04c) steps down as Done today's two-line caption does
        assertEquals(34.0, NumberStack.fit(longName.number, longName.captions, small, one).numberSize, 0.0)
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
        assertTrue(NumberStack.clearance(small.height, 44.0, 2, dash = false, scale = one) < WidgetStyle.gap)
        assertTrue(NumberStack.clearance(floor.height, 44.0, 1, dash = false, scale = one) < WidgetStyle.gap)
        assertEquals(34.0, assertFits("w06", today.number, today.captions, small).numberSize, 0.0)
        assertEquals(34.0, assertFits("w01b", due.number, due.captions, floor).numberSize, 0.0)
    }

    // the system's font scale

    @Test fun theFitMeasuresAtTheSystemFontScale() {
        val small = FaceRoom.small(WidgetSizes.small.w(), WidgetSizes.small.h())
        val today = TodayFace.of(GlanceState.CardsDue(digest, 24), now, utc)
        // at 1.3x the caption is 15.6 dp and "of 50 done today" still takes two lines: the number steps to 22 sp (w06c)
        val large = assertFits("w06c", today.number, today.captions, small, TextScale.linear(1.3))
        assertEquals(22.0, large.numberSize, 0.0)
        assertEquals(2, large.captionLines)
        assertTrue("the caption's height grows with the font", large.captionHeight > NumberStack.fit(today.number, today.captions, small, one).captionHeight)
        // the one-line size: "Step 1 today" fits 78 dp at 1.0x, at 1.3x the short form does
        val line = FaceRoom.oneLine(WidgetSizes.oneLine.w(), WidgetSizes.oneLine.h())
        val examDay = CountdownFace.of(GlanceState.CardsDue(digest.copy(examDate = midnight), 24), now, utc)
        assertEquals("Step 1 today", OneLineFit.pick(examDay.lineForms, line, one))
        assertEquals("Today", OneLineFit.pick(examDay.lineForms, line, TextScale.linear(1.3)))
        assertFalse(OneLineFit.fits("Step 1 today", line, TextScale.linear(1.3)))
    }

    @Test fun atATextSizeOf130PercentTheMediumAndThe122dp2x2StillFitWhole() {
        val scale = TextScale.linear(1.3)
        var checked = 0
        val tooLong = mutableSetOf<String>()
        for (stack in EveryFace.stacks.filter { it.size == WidgetSizes.small || DueLayout.isMedium(it.size.w()) }) {
            // a caption that takes three lines at 15.6 dp in 78 dp takes the last resort (the sweep below)
            if (stack.captions.none { WidgetText.lines(it, scale.dp(captionSize), bold = false, widthDp = stack.room.width) <= NumberStack.captionLines }) {
                tooLong += stack.captions.last()
                continue
            }
            assertFits("${stack.widget} ${stack.size}", stack.number, stack.captions, stack.room, scale)
            checked++
        }
        assertEquals(setOf(WidgetWords.openApp, "day to MRCP Part 1", "days to MRCP Part 1"), tooLong)
        assertTrue("faces checked at 1.3x: $checked", checked > 150)
    }

    @Test fun atEachFontScaleNothingMeetsAndOnlyWhatCannotFitTakesTheLastResort() {
        // sp times the font scale, as Android draws it below API 34; Android 14's curve, at 1.0x, 1.3x and the 2.0x
        // stock Android offers only from then, is swept in WidgetTextScaleTest
        val atOne = EveryFace.sweep(one, "1.0x")
        for ((size, count) in atOne) assertEquals("1.0x $size: every face whole with the glyph", 0, count[1] + count[2])
        val large = EveryFace.sweep(TextScale.linear(1.3), "1.3x linear")
        val floor = large.getValue(WidgetSizes.smallFloor.label())
        // the glyph gives way at the floor where a two-line caption at 15.6 dp leaves no room for it
        assertTrue("1.3x at 110x110: ${floor.toList()}", floor[0] + floor[1] >= 170)
        assertEquals("1.3x at 110x110: only three-line captions take the last resort", 8, floor[2])
        assertEquals(8, large.getValue(WidgetSizes.small.label())[2])
        for (size in listOf(WidgetSizes.medium, WidgetSizes.mediumOneRow, WidgetSizes.mediumTall)) {
            assertEquals("1.3x ${size.label()}", listOf(7, 0, 0), large.getValue(size.label()).toList())
        }
    }

    @Test fun theLastResortHoldsTheCaptionToTheLinesThatFit() {
        val floor = FaceRoom.small(WidgetSizes.smallFloor.w(), WidgetSizes.smallFloor.h())
        val noFile = DueFace.of(GlanceState.NoFile)
        // at 1.3x "Stethoscore" alone is wider than 78 dp: "Open Stethoscore" takes three lines, held to two
        val fit = NumberStack.fit(noFile.number, noFile.captions, floor, TextScale.linear(1.3))
        assertTrue(fit.lastResort)
        assertEquals(WidgetWords.openApp, fit.caption)
        assertEquals(3, WidgetText.lines(fit.caption, 12 * 1.3, bold = false, widthDp = floor.width))
        assertEquals(2, fit.captionLines)
        assertEquals(22.0, fit.numberSize, 0.0)
        // a room too short for two lines at the ladder's foot holds it to one
        val short = FaceRoom(78.0, 60.0)
        val held = NumberStack.fit("24", listOf("of 50 done today"), short, TextScale.linear(1.3))
        assertTrue(held.lastResort)
        assertFalse(held.glyph)
        assertEquals(1, held.captionLines)
        assertTrue(NumberStack.headroom(short.height, held.numberSize, held.captionLines, dash = false, scale = TextScale.linear(1.3)) >= 0)
    }

    // the no-file dash

    @Test fun theNoFileDashSitsAsNearItsCaptionAsANumber() {
        val floor = FaceRoom.small(WidgetSizes.smallFloor.w(), WidgetSizes.smallFloor.h())
        val left = FaceRoom.mediumLeft(WidgetSizes.medium.w(), WidgetSizes.medium.h())
        val noFile = DueFace.of(GlanceState.NoFile)
        // w03 at the floor; at 1.3x the medium's column, as "Open Stethoscore" takes three lines in a 2x2 there
        for ((room, scale) in listOf(floor to 1.0, left to 1.0, left to 1.3)) {
            val textScale = TextScale.linear(scale)
            val fit = assertFits("no file", noFile.number, noFile.captions, room, textScale)
            val size = textScale.dp(fit.numberSize)
            // a number's box stands on its caption and its ink on its baseline, the box's foot padding over the caption
            val footPadding = size * WidgetText.below + WidgetText.lineRounding
            val numberGap = footPadding
            // the dash's box stands dashDrop lower, its ink dashFoot em over its baseline
            val dashGap = (fit.captionHeight - fit.dashDrop) + footPadding + size * WidgetText.dashFoot - fit.captionHeight
            assertEquals("at ${scale}x", numberGap, dashGap, 1e-9)
            assertEquals(size * WidgetText.dashFoot, fit.dashDrop, 1e-9)
        }
        // at 44 sp the dash comes down about 13 dp, which it stood higher than a number before T0206
        val fit = NumberStack.fit(noFile.number, noFile.captions, floor, one)
        assertEquals(44.0, fit.numberSize, 0.0)
        assertEquals(12.9, fit.dashDrop, 0.1)
        assertEquals("a number is not moved", 0.0, NumberStack.fit("24", listOf("due now"), floor, one).dashDrop, 0.0)
    }

    @Test fun withNoFileA2x2SaysOpenStethoscoreAndTheMediumSaysItAll() {
        val floor = FaceRoom.small(WidgetSizes.smallFloor.w(), WidgetSizes.smallFloor.h())
        val countdown = CountdownFace.of(GlanceState.NoFile, now, utc)
        // "Open Stethoscore to see your countdown" takes four lines in 78 dp; TalkBack still reads it whole (spoken)
        assertEquals(4, WidgetText.lines(countdown.caption, captionSize, bold = false, widthDp = floor.width))
        assertEquals(WidgetWords.openApp, NumberStack.fit(countdown.number, countdown.captions, floor, one).caption)
        assertEquals(countdown.caption, countdown.spoken)
        val due = DueFace.of(GlanceState.NoFile)
        assertEquals(WidgetWords.openApp, NumberStack.fit(due.number, due.captions, floor, one).caption)
        val left = FaceRoom.mediumLeft(WidgetSizes.medium.w(), WidgetSizes.medium.h())
        assertEquals(101.0, left.width, 0.0)
        assertEquals(due.caption, NumberStack.fit(due.number, due.captions, left, one).caption)
    }

    // the one-line sizes

    @Test fun everyOneLineTextFitsAt110dpWithoutAnEllipsis() {
        // widget_countdown.xml and widget_today.xml resize to 110 dp wide and 40 dp tall
        val faces = EveryFace.countdowns.map { it.line to it.lineForms } + EveryFace.todays.map { it.line to it.lineForms }
        assertEquals(40.0, OneLineFit.leastHeight, 0.0)
        assertEquals("8 dp above and below at 1.0x", WidgetStyle.mediumVerticalMargin, OneLineFit.margin(one), 0.0)
        for (widget in listOf(ExamCountdownWidget(), DoneTodayWidget())) {
            val lines = sizes(widget).filter { it.h() < WidgetSizes.oneLineHeight }
            assertEquals(listOf(WidgetSizes.oneLine), lines)
            for (size in lines) for (height in listOf(size.h(), OneLineFit.leastHeight)) {
                val room = FaceRoom.oneLine(size.w(), height)
                for ((line, forms) in faces) {
                    assertEquals("TalkBack reads the sentence, the first form", line, forms.first())
                    val picked = OneLineFit.pick(forms, room, one)
                    assertTrue("\"$picked\" (for \"$line\") in $room", OneLineFit.fits(picked, room, one))
                }
            }
        }
    }

    @Test fun theSentencesTooWideAt110dpGiveWayToShortForms() {
        val room = FaceRoom.oneLine(WidgetSizes.oneLine.w(), WidgetSizes.oneLine.h())
        assertEquals(78.0, room.width, 0.0)
        // at the footnote size, the line's least, the sentences are still wider than 78 dp
        for (sentence in listOf("Open Stethoscore", "Step 1 in 90 days", "32 of 50 done today")) {
            assertFalse(sentence, OneLineFit.fits(sentence, room, one))
        }
        fun line(state: GlanceState) = CountdownFace.of(state, now, utc).let { OneLineFit.pick(it.lineForms, room, one) }
        assertEquals("Open app", line(GlanceState.NoFile))
        assertEquals("90 days", line(GlanceState.CardsDue(digest, 24)))
        assertEquals("Tomorrow", line(GlanceState.CardsDue(digest.copy(examDate = midnight + day), 24)))
        assertEquals("the sentence where it fits", "Step 1 today", line(GlanceState.CardsDue(digest.copy(examDate = midnight), 24)))
        assertEquals("Today", line(GlanceState.CardsDue(digest.copy(examName = "MRCP Part 1", examDate = midnight), 24)))
        assertEquals("Set a date", line(GlanceState.CardsDue(digest.copy(examDate = null), 24)))
        fun today(done: Int, goal: Int) = TodayFace.of(GlanceState.CardsDue(digest.copy(today = done, goal = goal), 24), now, utc)
            .let { OneLineFit.pick(it.lineForms, room, one) }
        assertEquals("32/50 today", today(32, 50))
        assertEquals("120/150", today(120, 150))
        assertEquals("Open app", OneLineFit.pick(TodayFace.of(GlanceState.NoFile, now, utc).lineForms, room, one))
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
        for ((model, picture) in listOf(NumberStack.clearance(small.height, 44.0, 2, dash = false, scale = one) to (93.0 - 94.5) / 2.625,
            NumberStack.clearance(floor.height, 44.0, 1, dash = false, scale = one) to 1.7)) {
            assertTrue("$model dp against $picture", model <= picture && model >= picture - 1.0)
        }
    }
}

/**
 * The fit at the platform's own sp to dp (GlanceWidgets.platformTextScale),
 * on Android 15's runtime: Android 14's font curves, on which large text
 * grows less than small, and the 2.0x only they offer.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WidgetTextScaleTest {
    private fun scale(fontScale: Float): TextScale {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val config = Configuration(context.resources.configuration).apply { this.fontScale = fontScale }
        return platformTextScale(context.createConfigurationContext(config).resources.displayMetrics)
    }

    @Test fun thePlatformTurnsSpIntoDpOnAndroid14sCurve() {
        val sizes = listOf(WardType.caption.size, WidgetStyle.lineFace.size, 22.0, 28.0, 34.0, WidgetStyle.numberSize)
        for (fontScale in listOf(1.0f, 1.3f, 2.0f)) {
            val curve = scale(fontScale)
            println("${fontScale}x: " + sizes.joinToString { "$it sp = ${"%.1f".format(curve.dp(it))} dp" })
        }
        for (sp in sizes) assertEquals("at 1.0x $sp sp is $sp dp", sp, scale(1.0f).dp(sp), 0.01)
        // the caption grows with the scale; the big number hardly, or not at all
        assertEquals(15.6, scale(1.3f).dp(WardType.caption.size), 0.1)
        assertEquals(24.0, scale(2.0f).dp(WardType.caption.size), 0.1)
        assertEquals("44 sp at 1.3x", 44.0, scale(1.3f).dp(44.0), 0.1)
        assertTrue("44 sp at 2.0x: ${scale(2.0f).dp(44.0)} dp", scale(2.0f).dp(44.0) < 44.0 * 1.5)
        // but some sizes grow more than the scale (13 sp at 1.3x: 17.2 dp, not 16.9), so the curve is swept as well
        // as sp times the scale
        assertTrue("13 sp at 1.3x: ${scale(1.3f).dp(13.0)} dp", scale(1.3f).dp(13.0) > 13.0 * 1.3)
    }

    @Test fun onThePlatformsCurveNothingMeetsAtAnyScale() {
        val atOne = EveryFace.sweep(scale(1.0f), "1.0x curve")
        for ((size, count) in atOne) assertEquals("1.0x $size", 0, count[1] + count[2])
        val large = EveryFace.sweep(scale(1.3f), "1.3x curve")
        val floor = large.getValue(WidgetSizes.smallFloor.label())
        assertTrue("1.3x at 110x110: ${floor.toList()}", floor[0] + floor[1] >= 170)
        EveryFace.sweep(scale(2.0f), "2.0x curve")
    }
}
