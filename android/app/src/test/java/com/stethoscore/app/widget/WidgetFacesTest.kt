package com.stethoscore.app.widget

import com.stethoscore.app.AppLink
import com.stethoscore.app.data.GlanceDigest
import com.stethoscore.app.data.GlanceShelf
import com.stethoscore.app.data.GlanceState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.Instant
import java.time.ZoneId

/** What the three widgets say in each state, against iOS's DueCardsWidget, ExamCountdownWidget and DoneTodayWidget. */
class WidgetFacesTest {
    @get:Rule val folder = TemporaryFolder()
    private val utc: ZoneId = ZoneId.of("UTC")
    private fun at(iso: String): Long = Instant.parse(iso).toEpochMilli()
    private val now = at("2026-11-05T10:00:00Z")
    private val deckA = "7C9E6679-7425-40DE-944B-E07FC1F90AE7"
    private val deckB = "16FD2706-8BAF-433B-82EB-8C7FADA847DA"

    private val digest = GlanceDigest(
        madeAt = at("2026-11-05T08:30:00Z"), dueNow = 24,
        topDecks = listOf(GlanceDigest.DueDeck(deckA, "Cardiology", 14), GlanceDigest.DueDeck(deckB, "Renal", 7),
            GlanceDigest.DueDeck("C56A4180-65AA-42EC-A945-5FD21DEC0538", "Neuro", 3)),
        nextDue = null, examName = "Step 1", examDate = at("2027-02-03T00:00:00Z"),
        today = 32, streak = 6, goal = 40,
    )
    private val nothing = digest.copy(dueNow = 0, topDecks = emptyList(), examName = null, examDate = null, goal = null)

    /** The state as the widget reads it: from the file on disk, through GlanceShelf. */
    private fun stateOf(d: GlanceDigest?): GlanceState {
        val shelf = GlanceShelf(folder.root)
        d?.let { assertTrue(shelf.write(it)) }
        return shelf.state(now)
    }

    // no file

    @Test fun noFileSaysOpenStethoscoreOnEveryWidget() {
        val state = stateOf(null)
        assertEquals(GlanceState.NoFile, state)
        val due = DueFace.of(state)
        assertFalse(due.hasFile)
        assertEquals("–", due.number)
        assertEquals("Open Stethoscore to see your cards", due.caption)
        assertFalse("no Review without a file", due.showsReview)
        assertTrue(due.decks.isEmpty())
        val countdown = CountdownFace.of(state, now, utc)
        assertEquals("–", countdown.number)
        assertEquals("Open Stethoscore to see your countdown", countdown.caption)
        assertEquals("Open Stethoscore", countdown.line)
        assertFalse("the en dash is never read out", countdown.spoken.contains("–"))
        val today = TodayFace.of(state, now, utc)
        assertEquals("–", today.number)
        assertEquals("Open Stethoscore to see today’s count", today.caption)
        assertEquals("Open Stethoscore", today.line)
        assertEquals(listOf("Open Stethoscore", "Open app"), today.lineForms)
        assertEquals(listOf("Open Stethoscore", "Open app"), countdown.lineForms)
        assertEquals("a column too narrow for the caption says only", listOf(today.caption, "Open Stethoscore"), today.captions)
        assertEquals(listOf(due.caption, "Open Stethoscore"), due.captions)
        assertEquals("the 2x2 says the caption aloud", "Open Stethoscore to see today\u2019s count", today.spoken)
    }

    // nothing due

    @Test fun nothingDueIsAllCaughtUp() {
        val face = DueFace.of(stateOf(nothing))
        assertTrue(face.hasFile)
        assertEquals("0", face.number)
        assertEquals("All caught up", face.caption)
        assertFalse(face.showsReview)
        assertEquals(AppLink.ReviewDue, face.link)
    }

    // due N

    @Test fun dueCountsTheCardsAndListsTheDecks() {
        val face = DueFace.of(stateOf(digest))
        assertEquals("24", face.number)
        assertEquals("due now", face.caption)
        assertEquals("24 cards due", face.spoken)
        assertTrue(face.showsReview)
        assertEquals(listOf("Cardiology", "Renal", "Neuro"), face.decks.map { it.name })
        assertEquals(AppLink.OpenSet(deckA.lowercase()), face.decks[0].link)
        assertEquals("redpen://set/${deckA.lowercase()}", face.decks[0].link.url)
        assertEquals(face.decks[0].link, AppLink.parse(face.decks[0].link.url))
        assertEquals("Cardiology, 14 cards due", face.decks[0].spoken)
        assertEquals("1 card due", DueFace.of(stateOf(digest.copy(dueNow = 1))).spoken)
    }

    @Test fun aCardComeDueSinceTheFileReadsAsAtLeastOne() {
        val face = DueFace.of(stateOf(nothing.copy(nextDue = at("2026-11-05T09:00:00Z"))))
        assertEquals("1", face.number)
        assertEquals("due now", face.caption)
    }

    @Test fun theMediumWidgetFitsTwoRowsAndTheButtonEach48dp() {
        assertEquals(48.0, WidgetStyle.target, 0.0)
        // 2 rows + the button = 144 dp, with 8 dp above and below
        assertEquals(2, DueLayout.rows(160.0, decks = 3, review = true))
        assertEquals(1, DueLayout.rows(159.0, decks = 3, review = true))
        assertEquals(1, DueLayout.rows(112.0, decks = 3, review = true))
        assertEquals(0, DueLayout.rows(110.0, decks = 3, review = true))
        assertEquals("never more decks than there are", 1, DueLayout.rows(400.0, decks = 1, review = true))
        assertEquals("never more than two", 2, DueLayout.rows(400.0, decks = 3, review = false))
        assertEquals(0, DueLayout.rows(10.0, decks = 3, review = true))
        assertFalse(DueLayout.isMedium(WidgetSizes.small.width.value.toDouble()))
        assertTrue(DueLayout.isMedium(WidgetSizes.medium.width.value.toDouble()))
        assertEquals(2, DueLayout.rows(WidgetSizes.mediumTall.height.value.toDouble(), 3, true))
        // Responsive hands the layout one of the listed sizes: a 4x2 from 112 to 159 dp tall gets mediumOneRow
        assertEquals(1, DueLayout.rows(WidgetSizes.mediumOneRow.height.value.toDouble(), 3, true))
        assertEquals(0, DueLayout.rows(WidgetSizes.medium.height.value.toDouble(), 3, true))
    }

    @Test fun theOneLineSizeFitsOneLineAt40dp() {
        // widget_countdown.xml and widget_today.xml resize down to 40 dp tall; the one-line size draws 8 dp above and below
        val room = 40.0 - 2 * WidgetStyle.mediumVerticalMargin
        assertTrue(WidgetText.height(WidgetStyle.lineFace.size) <= room)
        assertEquals("the footnote style, as far down as the line goes", 13.0, WidgetStyle.lineFace.size, 0.0)
    }

    // exam date

    @Test fun countdownSaysDaysToTheExamAsHome() {
        val face = CountdownFace.of(stateOf(digest), now, utc)
        assertEquals(90, face.days)
        assertEquals("90", face.number)
        assertEquals("days to Step 1", face.caption)
        assertEquals("Step 1 in 90 days", face.line)
        assertEquals(listOf("Step 1 in 90 days", "90 days"), face.lineForms)
        assertEquals(AppLink.ExamPlan, face.link)
    }

    @Test fun countdownTomorrowTodayAndFinals() {
        val tomorrow = CountdownFace.of(stateOf(digest.copy(examDate = at("2026-11-06T00:00:00Z"))), now, utc)
        assertEquals("day to Step 1", tomorrow.caption); assertEquals("Step 1 tomorrow", tomorrow.line)
        assertEquals(listOf("Step 1 tomorrow", "Tomorrow"), tomorrow.lineForms)
        val today = CountdownFace.of(stateOf(digest.copy(examDate = at("2026-11-05T00:00:00Z"))), now, utc)
        assertEquals("0", today.number); assertEquals("Step 1 today", today.caption); assertEquals("Step 1 today", today.line)
        assertEquals(listOf("Step 1 today", "Today"), today.lineForms)
        val finals = CountdownFace.of(stateOf(digest.copy(examName = null)), now, utc)
        assertEquals("days to Finals", finals.caption); assertEquals("Finals in 90 days", finals.line)
    }

    @Test fun noExamDateAsksForOne() {
        val face = CountdownFace.of(stateOf(nothing), now, utc)
        assertNull(face.days)
        assertEquals("–", face.number)
        assertEquals("Set your exam date", face.caption)
        assertEquals("Set your exam date", face.line)
        assertEquals("Set your exam date", face.spoken)
        assertEquals(listOf("Set your exam date", "Set a date"), face.lineForms)
        assertEquals("with a file the caption is never swapped", listOf("Set your exam date"), face.captions)
        val passed = CountdownFace.of(stateOf(digest.copy(examDate = at("2026-11-01T00:00:00Z"))), now, utc)
        assertNull("a day gone shows no countdown", passed.days)
    }

    // goal

    @Test fun doneTodayCountsAgainstTheGoal() {
        val face = TodayFace.of(stateOf(digest), now, utc)
        assertEquals("32", face.number)
        assertEquals("of 40 done today", face.caption)
        assertEquals("32 of 40 done today", face.line)
        assertEquals("32 of 40 done today", face.spoken)
        assertEquals("the 2x1 shows a short form", listOf("32 of 40 done today", "32/40 today", "32/40"), face.lineForms)
        assertEquals(AppLink.ReviewDue, face.link)
    }

    @Test fun doneTodayWithoutAGoalInTheFileUses50AndYesterdayReads0() {
        assertEquals("32 of 50 done today", TodayFace.of(stateOf(digest.copy(goal = null)), now, utc).line)
        val yesterday = TodayFace.of(stateOf(digest.copy(madeAt = at("2026-11-04T08:30:00Z"))), now, utc)
        assertEquals("0 of 40 done today", yesterday.line)
    }

    @Test fun noWidgetSaysStreakFlameXpOrRank() {
        val words = listOf(stateOf(null), stateOf(nothing), stateOf(digest)).flatMap { s ->
            val d = DueFace.of(s); val c = CountdownFace.of(s, now, utc); val t = TodayFace.of(s, now, utc)
            listOf(d.number, d.spoken, c.spoken, t.spoken) + d.captions + c.captions + c.lineForms + t.captions + t.lineForms +
                d.decks.map { it.spoken }
        }
        for (w in words) for (banned in listOf("streak", "flame", "xp", "rank", "🔥")) {
            assertFalse("$w says $banned", w.lowercase().contains(banned))
        }
    }
}
