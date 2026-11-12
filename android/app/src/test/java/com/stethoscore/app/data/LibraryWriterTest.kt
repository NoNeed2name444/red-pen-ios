package com.stethoscore.app.data

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * The library's one writer (T0210): a rating returns before any file work,
 * bursts are coalesced, order holds, and a cut-off write keeps the old file.
 */
class LibraryWriterTest {
    @get:Rule val folder = TemporaryFolder()
    private val file get() = File(folder.root, "stethoscore.json")

    /** Holds what the writer hands it until the test runs it. */
    private class Held : Executor {
        val tasks = mutableListOf<Runnable>()
        override fun execute(command: Runnable) { synchronized(tasks) { tasks += command } }
        fun runAll() { while (true) { val next = synchronized(tasks) { tasks.removeFirstOrNull() } ?: return; next.run() } }
    }
    private fun direct() = LibraryWriter(Executor { it.run() })
    private fun deck(cards: Int = 1) = StudySet(id = "deck", name = "Renal", kind = StudySetKind.ANKI, createdAt = 0,
        cards = (1..cards).map { AnkiCard(id = "c$it", front = "Q$it", bullets = listOf("A")) })

    // A1: a library file written before this change loads and saves byte for byte the same

    @Test fun anExistingLibraryFileRoundTripsByteForByte() {
        file.writeText(FIXTURE)
        val store = StudyStore(folder.root, direct())
        assertNull(store.loadError)
        assertEquals(FIXTURE, store.libraryText())
        store.save()
        assertEquals(FIXTURE, file.readText())
        // a background save writes the same format: what a store opened over it reads back
        store.saveReadingProgress("book", 3)
        store.flush()
        assertEquals(StudyStore(folder.root, direct()).libraryText(), file.readText())
        assertEquals(3, JSONObject(file.readText()).getJSONObject("readingProgress").getJSONObject("book").getInt("position"))
    }

    // A2: a rating does no file work on the calling thread

    @Test fun aRatingReturnsBeforeAnyFileWork() {
        val held = Held()
        val writer = LibraryWriter(held)
        val store = StudyStore(folder.root, writer)
        store.addSet(deck())
        held.runAll()
        val before = file.readBytes()
        val writingThreads = mutableListOf<Thread>()
        writer.beforeWrite = { synchronized(writingThreads) { writingThreads += Thread.currentThread() } }
        val kept = store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
        assertTrue("no write on the calling thread", writingThreads.isEmpty())
        assertArrayEquals("the file is untouched until the writer runs", before, file.readBytes())
        // memory has the rating at once, before it is written
        assertEquals(kept, store.reviews["c1"])
        assertTrue(store.dueCards(store.library.single()).isEmpty())
        val background = Thread({ held.runAll() }, "writer-test").apply { start(); join(5_000) }
        assertEquals(listOf(background), writingThreads)
        assertEquals(kept.due, StudyStore(folder.root, direct()).reviews["c1"]?.due)
    }

    // A3: a burst is coalesced, and the file ends as the last state

    @Test fun aHundredRatingsTakeAFewWritesAndEndAsTheLastState() {
        val thread = Executors.newSingleThreadExecutor()
        try {
            val writer = LibraryWriter(thread)
            val store = StudyStore(folder.root, writer)
            store.addSet(deck(100))
            val writesBefore = writer.writes
            val release = CountDownLatch(1)
            var first = true
            writer.beforeWrite = { if (first) { first = false; release.await(5, TimeUnit.SECONDS) } }
            for (card in store.library.single().cards) store.rateCard(card, AnkiRating.GOOD)
            release.countDown()
            store.flush()
            val writes = writer.writes - writesBefore
            assertTrue("100 ratings took $writes writes", writes in 1..3)
            assertEquals(store.libraryText(), file.readText())
            assertEquals(100, StudyStore(folder.root, direct()).reviews.size)
        } finally { thread.shutdownNow() }
    }

    @Test fun anEarlierSnapshotNeverOverwritesALaterOne() {
        val held = Held()
        val writer = LibraryWriter(held)
        val written = mutableListOf<Long>()
        fun job(n: Long) = LibraryWriter.Job(n, { written += n }, {}, {})
        writer.submit(job(4))
        writer.writeNow(job(5))
        writer.submit(job(3))
        held.runAll()
        assertEquals(listOf(5L), written)
        writer.submit(job(6)); writer.submit(job(7))
        held.runAll()
        assertEquals("only the newest waiting snapshot is written", listOf(5L, 7L), written)
    }

    @Test fun anEditAfterAPendingRatingKeepsBoth() {
        val held = Held()
        val store = StudyStore(folder.root, LibraryWriter(held))
        store.addSet(deck()); held.runAll()
        store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
        store.rename("deck", "Kidney")
        held.runAll()
        val reopened = StudyStore(folder.root, direct())
        assertEquals("Kidney", reopened.library.single().name)
        assertNotNull(reopened.reviews["c1"])
    }

    // A4: a write cut off before the rename leaves the previous complete file

    @Test fun aWriteCutOffBeforeTheRenameKeepsThePreviousFile() {
        val store = StudyStore(folder.root, direct())
        store.addSet(deck())
        val before = file.readText()
        val errors = mutableListOf<String>()
        store.onSaveError = { errors += it }
        store.beforeRename = { throw IOException("process killed") }
        store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
        store.flush()
        assertEquals(before, file.readText())
        assertEquals(1, errors.size)
        assertTrue("memory went back to the file", store.reviews.isEmpty())
        assertThrows(IllegalStateException::class.java) { store.rename("deck", "Lost") }
        assertEquals(before, file.readText())
        assertEquals("Renal", store.library.single().name)
        assertFalse(File(folder.root, "stethoscore.json.tmp").exists())
        store.beforeRename = null
        store.rename("deck", "Kept")
        assertEquals("Kept", StudyStore(folder.root, direct()).library.single().name)
    }

    // A5: export reads what is in memory, written or not

    @Test fun exportHasARatingStillWaitingToBeWritten() {
        val held = Held()
        val store = StudyStore(folder.root, LibraryWriter(held))
        store.addSet(deck()); held.runAll()
        store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
        assertFalse(JSONObject(file.readText()).getJSONObject("reviews").has("c1"))
        assertTrue(JSONObject(store.exportJson()).getJSONObject("reviews").has("c1"))
    }

    // T0227: the writer's failure paths (a check of T0210 found five weak spots)

    /** A rating whose write fails on the writer's thread while this thread waits in flush(), as onStop waits for it. */
    private fun flushOverAFailingWrite(store: StudyStore, writer: LibraryWriter) {
        val stopping = Thread.currentThread()
        store.beforeRename = { throw IOException("disk full") }
        // the write starts only once this thread is blocked inside flush()
        writer.beforeWrite = { var waited = 0; while (stopping.state != Thread.State.WAITING && waited++ < 5_000) Thread.sleep(1) }
        store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
        store.flush()
        writer.beforeWrite = null
    }

    // item 1: the activity is recreated (a rotation) around the onStop flush

    @Test fun aFailureWithNoHandlerIsToldToTheNextOne() {
        val store = StudyStore(folder.root, direct())
        store.addSet(deck())
        val gone = mutableListOf<String>(); val next = mutableListOf<String>(); val later = mutableListOf<String>()
        store.onSaveError = { gone += it }
        store.onSaveError = null
        store.beforeRename = { throw IOException("disk full") }
        store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
        assertTrue("nobody was there to tell", gone.isEmpty())
        store.onSaveError = { next += it }
        assertEquals(1, next.size)
        assertTrue(next.single(), "Your latest changes were undone" in next.single())
        store.onSaveError = null
        store.onSaveError = { later += it }
        assertTrue("told once", later.isEmpty())
    }

    @Test fun aFailureFromTheFlushOfAStoppingActivityIsToldToTheRecreatedOne() {
        val thread = Executors.newSingleThreadExecutor()
        try {
            val writer = LibraryWriter(thread)
            val store = StudyStore(folder.root, writer)
            store.addSet(deck())
            val stopping = mutableListOf<String>(); val recreated = mutableListOf<String>()
            store.onSaveError = { stopping += it }
            flushOverAFailingWrite(store, writer)
            assertEquals("the stopping activity's handler was told", 1, stopping.size)
            // onDestroy: its handler goes and the notice it had posted is dropped; the new activity brings its own
            store.onSaveError = null
            store.onSaveError = { recreated += it }
            assertEquals(stopping, recreated)
        } finally { thread.shutdownNow() }
    }

    @Test fun aNoticeShownBeforeTheNextStopIsNotToldAgain() {
        val thread = Executors.newSingleThreadExecutor()
        try {
            val writer = LibraryWriter(thread)
            val store = StudyStore(folder.root, writer)
            store.addSet(deck())
            val shown = mutableListOf<String>(); val recreated = mutableListOf<String>()
            store.onSaveError = { shown += it }
            flushOverAFailingWrite(store, writer)
            assertEquals(1, shown.size)
            // the person came back and saw it; the next stop's flush is the next turn of the main thread
            store.flush()
            store.onSaveError = null
            store.onSaveError = { recreated += it }
            assertTrue(recreated.isEmpty())
        } finally { thread.shutdownNow() }
    }

    @Test fun aNoticeHandedOutsideAFlushIsNotToldAgain() {
        val store = StudyStore(folder.root, direct())
        store.addSet(deck())
        val shown = mutableListOf<String>(); val recreated = mutableListOf<String>()
        store.onSaveError = { shown += it }
        store.beforeRename = { throw IOException("disk full") }
        store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
        assertEquals(1, shown.size)
        store.onSaveError = null
        store.onSaveError = { recreated += it }
        assertTrue(recreated.isEmpty())
    }

    // item 2: the test hook before the callback

    @Test fun aHookThatThrowsBeforeTheCallbackNeitherEscapesNorSkipsIt() {
        val writer = direct()
        val told = mutableListOf<String>()
        writer.beforeCallback = { throw IllegalStateException("hook") }
        writer.submit(LibraryWriter.Job(writer.nextGeneration(), {}, { told += "written" }, { told += "failed" }))
        assertEquals(listOf("written"), told)
        writer.beforeCallback = null
        writer.submit(LibraryWriter.Job(writer.nextGeneration(), {}, { told += "again" }, {}))
        assertEquals("the writer went on", listOf("written", "again"), told)
    }

    // item 3: a write whose directory is gone (the library's directory cannot be made again: its parent is now a file)

    @Test fun aWriteIntoADirectoryThatIsGoneReportsAFailedSave() {
        val parent = folder.newFolder("parent")
        val store = StudyStore(File(parent, "library"), direct())
        store.addSet(deck())
        val errors = mutableListOf<String>()
        store.onSaveError = { errors += it }
        assertTrue(parent.deleteRecursively())
        parent.writeText("not a directory")
        store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
        assertEquals(1, errors.size)
        assertTrue(errors.single(), "Could not create the library directory" in errors.single())
        assertTrue("memory went back", store.reviews.isEmpty())
        val thrown = assertThrows(IllegalStateException::class.java) { store.rename("deck", "Lost") }
        assertTrue(thrown.message, "Could not create the library directory" in thrown.message.orEmpty())
        assertEquals("Renal", store.library.single().name)
    }

    // item 5: a write that ends in anything but an Exception

    @Test fun aWriteThatEndsInAnErrorIsToldAsAFailedSave() {
        val writer = direct()
        val failures = mutableListOf<Exception>()
        val written = mutableListOf<Long>()
        val first = writer.nextGeneration()
        writer.submit(LibraryWriter.Job(first, { throw Error("disk driver") }, { written += first }, { failures += it }))
        assertEquals(1, failures.size)
        assertEquals("disk driver", failures.single().cause?.message)
        assertTrue(written.isEmpty())
        val second = writer.nextGeneration()
        writer.submit(LibraryWriter.Job(second, { }, { written += second }, { failures += it }))
        assertEquals("the writer went on", listOf(second), written)
        writer.flush()
    }

    @Test fun anInterruptedWriteIsToldAndTheInterruptIsKept() {
        val writer = direct()
        val failures = mutableListOf<Exception>()
        try {
            writer.submit(LibraryWriter.Job(writer.nextGeneration(), { throw InterruptedException("cut off") }, {}, { failures += it }))
            assertEquals("the snapshot did not land, so the store is told", 1, failures.size)
            assertTrue("the thread is still interrupted for its owner", Thread.currentThread().isInterrupted)
        } finally { Thread.interrupted() }
    }

    companion object {
        /** stethoscore.json as the store wrote it before T0210 (base aad4f912). */
        private const val FIXTURE = """{"folders":[{"colour":"teal","name":"Year 3","id":"f1","updatedAt":"2026-10-01T00:00:00Z"}],"notes":[{"createdAt":"2026-10-03T00:00:00Z","kind":"idea","boardX":0,"boardY":0,"links":[],"id":"n1","title":"Idea","body":"Remember [[Physiology]]","folderId":null,"updatedAt":"2026-10-04T00:00:00Z","tags":["renal"]}],"examDate":"2027-06-01T00:00:00Z","noteFolders":[{"createdAt":"2026-10-03T00:00:00Z","name":"Ward","id":"nf1","parentId":null}],"format":"stethoscore-android-v1","readingProgress":{"book":{"savedAt":"2026-10-05T00:00:00Z","position":3}},"osceProgress":{"osce":{"checklistTitle":"Wash","stepIndex":1,"checklistIndex":0,"missed":[1],"savedAt":"2026-10-05T00:00:00Z"}},"answerHistory":{"q1":[true,false]},"futureTop":{"keep":[1,2]},"library":[{"osceChecklists":[],"narrateSegments":[],"images":[],"cards":[{"clozeText":"","pictureOnBack":null,"siblings":[],"occlusion":null,"why":"","id":"c1","front":"S3 means?","source":null,"type":"qa","bullets":["Volume overload"],"imageIndex":null,"tags":[]},{"clozeText":"{{c1::Aortic}} stenosis","pictureOnBack":null,"siblings":[],"occlusion":null,"why":"","id":"c2","front":"","source":null,"type":"cloze","bullets":[],"imageIndex":null,"tags":[]}],"sources":[],"kind":"anki","subject":"Medicine","questions":[],"folderId":"f1","tags":[],"exam":null,"createdAt":"2026-10-01T08:00:00Z","lectureLanguage":null,"bookMarkdown":"","name":"Cardiology","id":"deck","caseFiles":[],"updatedAt":"2026-10-02T09:30:00Z"},{"osceChecklists":[],"narrateSegments":[],"images":[],"cards":[],"sources":[],"kind":"mcq","subject":"General","questions":[{"futureScore":0.87,"options":["A","B","C"],"id":"q1","source":null,"correctIndex":1,"explanation":"Because","stem":"Why?","imageIndex":null,"tags":[]}],"folderId":null,"tags":[],"exam":null,"createdAt":"2001-01-01T00:00:00Z","lectureLanguage":null,"bookMarkdown":"","name":"Renal MCQs","id":"quiz","caseFiles":[],"updatedAt":"2026-10-13T12:30:00Z"},{"osceChecklists":[],"narrateSegments":[],"images":[],"cards":[],"sources":[],"kind":"book","subject":"General","questions":[],"folderId":null,"tags":[],"exam":null,"createdAt":"2026-09-01T00:00:00Z","lectureLanguage":null,"bookMarkdown":"# Heading\n\nBody text","name":"Notes book","id":"book","caseFiles":[],"updatedAt":"2026-09-01T00:00:00Z"},{"payload":[1,2,3],"kind":"new-mode","id":"future"}],"reviews":{"c1":{"lapses":0,"ease":2.5,"reps":2,"reviews":0,"due":"2026-10-20T00:00:00Z","ratedAt":"2026-11-06T01:18:49.823Z","interval":3,"changedAt":"2026-10-17T00:00:00Z","intervalMin":0}},"mistakeReasons":{"q1":{"reason":"misread","at":"2026-10-06T10:00:00Z"}},"flagged":["q1"],"answerLog":[{"questionId":"q1","at":"2026-10-05T10:00:00Z","correct":true,"picked":1,"confidence":"sure"},{"questionId":"q1","at":"2026-10-06T10:00:00Z","correct":false,"hinted":true}],"quizProgress":{"quiz":{"current":1,"answers":[{"checked":true,"selected":1},{"checked":false,"selected":null}],"savedAt":"2026-10-05T00:00:00Z","questionIds":["q1"],"optionOrders":[[2,0,1]]}},"caseRuns":{"deck:case":{"taken":["s1"],"finished":false}},"ruleSheet":{"q1":{"date":"2026-11-06T01:18:49.831Z","byAI":false,"answer":"","subject":"Renal","id":"q1","text":"Read the stem twice","detail":"","explanation":"","stem":""}}}"""
    }
}
