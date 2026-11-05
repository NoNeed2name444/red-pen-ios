package com.stethoscore.app.data

import com.stethoscore.app.exam.ExamChoice
import com.stethoscore.app.exam.MemoryExamDefaults
import com.stethoscore.app.quiz.ExamTrack
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.Instant
import java.time.ZoneId

/** The widgets' digest (GlanceDigest.kt), against iOS GlanceDigest.swift and GlancePublisher.swift. */
class GlanceDigestTest {
    @get:Rule val folder = TemporaryFolder()
    private val utc: ZoneId = ZoneId.of("UTC")
    private fun at(iso: String): Long = Instant.parse(iso).toEpochMilli()

    @After fun resetGoal() { DailyGoal.store = DailyGoal.MemoryStore() }

    private val full = GlanceDigest(
        madeAt = at("2026-11-05T08:30:00Z"), dueNow = 24,
        topDecks = listOf(GlanceDigest.DueDeck("7C9E6679-7425-40DE-944B-E07FC1F90AE7", "Cardiology / Renal \"core\"", 14)),
        nextDue = at("2026-11-05T09:00:00Z"), examName = "Step 1", examDate = at("2027-02-03T00:00:00Z"),
        today = 32, streak = 6, goal = 50,
    )

    // A1: JSONEncoder with .iso8601 and .sortedKeys, byte for byte

    @Test fun encodesAsSwiftsJSONEncoderDoes() {
        val expected = "{\"dueNow\":24,\"examDate\":\"2027-02-03T00:00:00Z\",\"examName\":\"Step 1\",\"goal\":50," +
            "\"madeAt\":\"2026-11-05T08:30:00Z\",\"nextDue\":\"2026-11-05T09:00:00Z\",\"streak\":6,\"today\":32," +
            "\"topDecks\":[{\"count\":14,\"id\":\"7C9E6679-7425-40DE-944B-E07FC1F90AE7\",\"name\":\"Cardiology \\/ Renal \\\"core\\\"\"}]," +
            "\"version\":1}"
        assertEquals(expected, GlanceDigest.encode(full))
    }

    @Test fun absentValuesAreLeftOutAsSwiftLeavesOutNil() {
        val text = GlanceDigest.encode(GlanceDigest.empty)
        assertEquals("{\"dueNow\":0,\"madeAt\":\"1970-01-01T00:00:00Z\",\"streak\":0,\"today\":0,\"topDecks\":[],\"version\":1}", text)
        listOf("nextDue", "examName", "examDate", "goal").forEach { assertFalse(it, text.contains("\"$it\"")) }
    }

    @Test fun roundTripsAndReadsAnIOSFileWithoutTheGoal() {
        assertEquals(full, GlanceDigest.decode(GlanceDigest.encode(full)))
        // what the iOS app writes today (GlancePublisher.save): no goal, the Swift UUID upper-case
        val ios = "{\"dueNow\":3,\"examDate\":\"2027-02-03T00:00:00Z\",\"examName\":\"PLAB 1\",\"madeAt\":\"2026-11-05T08:30:00Z\"," +
            "\"streak\":2,\"today\":5,\"topDecks\":[{\"count\":3,\"id\":\"7C9E6679-7425-40DE-944B-E07FC1F90AE7\",\"name\":\"Renal\"}],\"version\":1}"
        val read = GlanceDigest.decode(ios)!!
        assertNull(read.goal); assertEquals(50, read.goalShown); assertEquals(3, read.dueNow); assertEquals("PLAB 1", read.examName)
        assertEquals(ios, GlanceDigest.encode(read))
    }

    @Test fun aNewerOrBrokenFileReadsAsNothing() {
        assertNull(GlanceDigest.decode(GlanceDigest.encode(full.copy(version = 2))))
        assertNull(GlanceDigest.decode("{"))
        assertNull(GlanceDigest.decode("{\"dueNow\":1,\"madeAt\":\"2026-11-05T08:30:00Z\",\"today\":0,\"topDecks\":[],\"version\":1}")) // no streak: Swift's decoder refuses it
        assertNull(GlanceDigest.decode(GlanceDigest.encode(full).replace("\"dueNow\":24", "\"dueNow\":2.5")))
    }

    @Test fun makeCountsTheBusiestDecksAndKeepsWholeSeconds() {
        val now = at("2026-11-05T08:30:00.789Z")
        val due = List(5) { "a" to "Renal" } + List(5) { "b" to "Cardio" } + List(2) { "c" to "Neuro" } + listOf("d" to "Endo")
        val d = GlanceDigest.make(now, due, nextDue = at("2026-11-05T09:00:00.500Z"), examName = "Step 1",
            examDate = at("2027-02-03T00:00:00Z"), today = 4, streak = 1, goal = 80, zone = utc)
        assertEquals(13, d.dueNow)
        assertEquals(listOf("Cardio" to 5, "Renal" to 5, "Neuro" to 2), d.topDecks.map { it.name to it.count })
        assertEquals(at("2026-11-05T08:30:00Z"), d.madeAt); assertEquals(at("2026-11-05T09:00:00Z"), d.nextDue)
        assertEquals(d, GlanceDigest.decode(GlanceDigest.encode(d)))
        // an exam day already gone is left out, and its name with it; today's still counts
        val gone = GlanceDigest.make(now, emptyList(), null, "Step 1", at("2026-11-04T00:00:00Z"), 0, 0, 50, utc)
        assertNull(gone.examDate); assertNull(gone.examName)
        assertEquals("Step 1 today", GlanceDigest.make(now, emptyList(), null, "Step 1", at("2026-11-05T00:00:00Z"), 0, 0, 50, utc).countdown(now, utc))
    }

    // A1: home's name and sentence

    @Test fun theSentenceIsHomes() {
        val now = at("2026-11-05T08:30:00Z")
        assertEquals("Step 1 in 90 days", full.copy(examDate = at("2027-02-03T00:00:00Z")).countdown(now, utc))
        assertEquals("Step 1 tomorrow", full.copy(examDate = at("2026-11-06T00:00:00Z")).countdown(now, utc))
        assertEquals("Finals in 90 days", full.copy(examName = null).countdown(now, utc))
        assertNull(full.copy(examDate = null, examName = null).countdown(now, utc))
    }

    @Test fun theStoreTakesHomesExamName() {
        val store = StudyStore(folder.root)
        store.setExamDate(at("2099-01-01T00:00:00Z"))
        assertNull("general revision: no name, so the sentence says Finals", store.glanceShelf.read()!!.examName)
        val defaults = MemoryExamDefaults()
        defaults.set(ExamTrack.storageKey, ExamTrack.usmle.rawValue)
        defaults.set(ExamChoice.primaryKey, "step1")
        store.examDefaults = defaults
        assertEquals("Step 1", store.glanceShelf.read()!!.examName)
        defaults.remove(ExamChoice.primaryKey); defaults.set(ExamTrack.storageKey, ExamTrack.plab.rawValue)
        store.setExamDate(at("2098-01-01T00:00:00Z"))
        assertEquals("PLAB 1", store.glanceShelf.read()!!.examName)
    }

    // A3: the goal, 50 until one is chosen, clamped to DailyGoal.range

    @Test fun theGoalDefaultsTo50AndIsClamped() {
        assertEquals(50, GoalProgress.goal(0)); assertEquals(10, GoalProgress.goal(3)); assertEquals(300, GoalProgress.goal(5000)); assertEquals(120, GoalProgress.goal(120))
        assertEquals(50, full.copy(goal = null).goalShown); assertEquals(300, full.copy(goal = 999).goalShown)
        val store = StudyStore(folder.root)
        assertEquals(50, store.glanceShelf.read()!!.goal)
        DailyGoal.store.set(DailyGoal.key, 5000)
        store.setExamDate(null) // any save
        assertEquals(300, store.glanceShelf.read()!!.goal)
        DailyGoal.store.set(DailyGoal.key, 4)
        assertEquals(10, store.glanceDigest().goal)
    }

    // A3: the three states

    @Test fun noFileNothingDueAndCardsDue() {
        val now = System.currentTimeMillis()
        assertEquals(GlanceState.NoFile, GlanceShelf(folder.root).state(now))
        File(folder.root, GlanceShelf.fileName).writeText("not json")
        assertEquals(GlanceState.NoFile, GlanceShelf(folder.root).state(now))
        File(folder.root, GlanceShelf.fileName).delete()

        val store = StudyStore(folder.root)
        assertTrue(store.glanceShelf.state(now) is GlanceState.NothingDue)
        store.addSet(StudySet(id = "deck", name = "Renal", kind = StudySetKind.ANKI,
            cards = listOf(AnkiCard(id = "c1", front = "Q1", bullets = listOf("A")), AnkiCard(id = "c2", front = "Q2", bullets = listOf("A")))))
        val due = store.glanceShelf.state(now) as GlanceState.CardsDue
        assertEquals(2, due.count); assertEquals(listOf(GlanceDigest.DueDeck("deck", "Renal", 2)), due.digest.topDecks)
        // a digest whose next card has come due since says at least one
        val stale = GlanceDigest.empty.copy(nextDue = now - 1000)
        assertEquals(1, stale.dueShown(now)); assertEquals(0, stale.copy(nextDue = now + 60_000).dueShown(now))
        assertEquals(0, full.todayShown(at("2026-11-06T08:30:00Z"), utc)); assertEquals(32, full.todayShown(at("2026-11-05T23:00:00Z"), utc))
    }

    // A2: written on save, and only when what it shows changed

    @Test fun writtenOnSaveOnlyWhenTheContentChanged() {
        val store = StudyStore(folder.root)
        val written = mutableListOf<GlanceDigest>()
        store.onGlanceWritten = { written += it }
        val deck = StudySet(id = "deck", name = "Renal", kind = StudySetKind.ANKI, cards = listOf(AnkiCard(id = "c1", front = "Q", bullets = listOf("A"))))
        store.addSet(deck)
        assertEquals(1, written.size); assertEquals(1, written.last().dueNow)
        // saves that change nothing the digest shows write nothing
        store.saveNote(Note(title = "An idea", body = "text"))
        store.saveReadingProgress("deck", 3)
        assertEquals(1, written.size)
        assertFalse(store.publishGlance())
        // a rating does
        store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
        assertEquals(2, written.size); assertEquals(0, written.last().dueNow); assertNotNull(written.last().nextDue)
        assertEquals(GlanceDigest.encode(written.last()), File(folder.root, GlanceShelf.fileName).readText())
        // a store opened over the same file, with the same numbers, leaves it alone
        val stamp = File(folder.root, GlanceShelf.fileName).readText()
        val reopened = StudyStore(folder.root)
        assertFalse(reopened.publishGlance())
        assertEquals(stamp, File(folder.root, GlanceShelf.fileName).readText())
        assertFalse(File(folder.root, GlanceShelf.fileName + ".tmp").exists())
    }

    @Test fun aThrowingListenerNeverFailsTheSave() {
        val store = StudyStore(folder.root)
        var told = 0
        store.onGlanceWritten = { told++; throw IllegalStateException("widget update failed") }
        store.addSet(StudySet(id = "deck", name = "Renal", kind = StudySetKind.ANKI, cards = listOf(AnkiCard(id = "c1", front = "Q", bullets = listOf("A")))))
        assertEquals(1, told)
        assertEquals(1, store.glanceShelf.read()!!.dueNow)
        val reopened = StudyStore(folder.root)
        assertEquals(listOf("deck"), reopened.library.map { it.id })
        // a background save goes through too, with nothing reported as an error
        val errors = mutableListOf<String>()
        store.onSaveError = { errors += it }
        store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
        assertEquals(2, told); assertTrue(errors.isEmpty())
        assertEquals(0, store.glanceShelf.read()!!.dueNow)
    }

    @Test fun aLibraryThatCannotBeOpenedWritesNoDigest() {
        File(folder.root, "stethoscore.json").writeText("{ broken")
        val store = StudyStore(folder.root)
        assertNotNull(store.loadError)
        assertFalse(store.publishGlance())
        assertEquals(GlanceState.NoFile, store.glanceShelf.state(System.currentTimeMillis()))
    }
}
