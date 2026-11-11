package com.stethoscore.app.data

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Writes that overlap and writes that fail (T0210 repair 1): a revert never
 * goes back past what is on disk, and a failed older write does not undo
 * changes a newer write carries.
 */
class StudyStoreOverlapTest {
    @get:Rule val folder = TemporaryFolder()
    private val file get() = File(folder.root, "stethoscore.json")
    private fun deck() = StudySet(id = "deck", name = "Renal", kind = StudySetKind.ANKI, createdAt = 0,
        cards = listOf(AnkiCard(id = "c1", front = "Q1", bullets = listOf("A")), AnkiCard(id = "c2", front = "Q2", bullets = listOf("A"))))
    private fun reopened() = StudyStore(folder.root, LibraryWriter(java.util.concurrent.Executor { it.run() }))

    /** Runs [body] with a writer on its own thread, shut down after. */
    private fun withWriter(body: (LibraryWriter) -> Unit) {
        val thread = Executors.newSingleThreadExecutor()
        try { body(LibraryWriter(thread)) } finally { thread.shutdownNow() }
    }

    // D1: a write has reached the disk but its callback has not yet told the store

    @Test fun aFailingSaveDoesNotRevertPastAWriteAlreadyOnDisk() = withWriter { writer ->
        val store = StudyStore(folder.root, writer)
        store.addSet(deck())
        val onDisk = CountDownLatch(1); val release = CountDownLatch(1)
        writer.beforeCallback = { onDisk.countDown(); release.await(10, TimeUnit.SECONDS) }
        val card = store.library.single().cards.first()
        store.rateCard(card, AnkiRating.EASY)
        assertTrue("the rating's write finished", onDisk.await(10, TimeUnit.SECONDS))
        // the callback (written) is held back: the store's saved state is still from before the rating
        store.beforeRename = { throw IOException("disk full") }
        assertThrows(IllegalStateException::class.java) { store.rename("deck", "Lost") }
        assertNotNull("the rating is on disk, so it stays in memory", store.reviews["c1"])
        assertEquals("Renal", store.library.single().name)
        release.countDown()
        store.flush()
        store.beforeRename = null
        store.rename("deck", "Kept")
        val back = reopened()
        assertNotNull("the next save keeps the rating", back.reviews["c1"])
        assertEquals("Kept", back.library.single().name)
    }

    @Test fun aFailingSaveWaitingOnARunningWriteKeepsItsChange() = withWriter { writer ->
        val store = StudyStore(folder.root, writer)
        store.addSet(deck())
        val writing = CountDownLatch(1); val release = CountDownLatch(1)
        var first = true
        writer.beforeWrite = { if (first) { first = false; writing.countDown(); release.await(10, TimeUnit.SECONDS) } }
        store.rateCard(store.library.single().cards.first(), AnkiRating.EASY)
        assertTrue(writing.await(10, TimeUnit.SECONDS))
        // only the saver's own write fails; the running background write goes through
        store.beforeRename = { if (Thread.currentThread().name == "saver") throw IOException("disk full") }
        var thrown: Throwable? = null
        val saver = Thread({ try { store.rename("deck", "Lost") } catch (e: Throwable) { thrown = e } }, "saver").apply { start() }
        // the saver waits on the writer's lock behind the running write
        val until = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
        while (saver.state == Thread.State.RUNNABLE && System.nanoTime() < until) Thread.sleep(5)
        release.countDown()
        saver.join(10_000)
        assertTrue(thrown is IllegalStateException)
        assertNotNull(store.reviews["c1"])
        store.flush()
        assertNotNull("the rating reached the disk", reopened().reviews["c1"])
    }

    // D2: an older write fails while a newer snapshot is waiting

    @Test fun aFailedOlderWriteDoesNotUndoWhatANewerOneCarries() = withWriter { writer ->
        val store = StudyStore(folder.root, writer)
        store.addSet(deck())
        val errors = mutableListOf<String>()
        store.onSaveError = { synchronized(errors) { errors += it } }
        val writing = CountDownLatch(1); val release = CountDownLatch(1)
        var first = true
        writer.beforeWrite = { if (first) { first = false; writing.countDown(); release.await(10, TimeUnit.SECONDS) } }
        var failures = 1
        store.beforeRename = { if (failures-- > 0) throw IOException("transient") }
        val cards = store.library.single().cards
        store.rateCard(cards[0], AnkiRating.EASY)
        assertTrue(writing.await(10, TimeUnit.SECONDS))
        store.rateCard(cards[1], AnkiRating.EASY) // waits behind the first, which is about to fail
        release.countDown()
        store.flush()
        assertTrue("nothing is reported: the newer write carried both", synchronized(errors) { errors.isEmpty() })
        assertEquals(setOf("c1", "c2"), store.reviews.keys)
        assertEquals(setOf("c1", "c2"), reopened().reviews.keys)
    }

    @Test fun theNewestWriteFailingStillRevertsAndSaysSo() = withWriter { writer ->
        val store = StudyStore(folder.root, writer)
        store.addSet(deck())
        val errors = mutableListOf<String>()
        store.onSaveError = { synchronized(errors) { errors += it } }
        store.beforeRename = { throw IOException("disk full") }
        store.rateCard(store.library.single().cards.first(), AnkiRating.EASY)
        store.flush()
        assertTrue(store.reviews.isEmpty())
        assertEquals(1, errors.size)
        assertTrue(errors.single(), errors.single().endsWith("Changes since the last save were undone."))
        assertTrue(reopened().reviews.isEmpty())
    }
}
