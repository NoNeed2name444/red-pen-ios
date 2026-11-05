package com.stethoscore.app.widget

import com.stethoscore.app.data.DailyGoal
import com.stethoscore.app.data.GlanceDigest
import com.stethoscore.app.data.StudyStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** The widgets are told once, after a burst of digests stops, and only of a digest that changed. */
class WidgetUpdatesTest {
    @get:Rule val folder = TemporaryFolder()
    private var hookBefore: ((GlanceDigest) -> Unit)? = StudyStore.onAnyGlanceWritten

    @After fun tearDown() {
        StudyStore.onAnyGlanceWritten = hookBefore
        DailyGoal.store = DailyGoal.MemoryStore()
    }

    /** A timer the test runs by hand. */
    private class HandTimer : Debouncer.Timer {
        val waiting = mutableListOf<Pair<Long, () -> Unit>>()
        var cancelled = 0
        override fun schedule(delayMs: Long, action: () -> Unit): () -> Unit {
            val item = delayMs to action
            waiting += item
            return { if (waiting.remove(item)) cancelled++ }
        }
        fun fire() { val due = waiting.toList(); waiting.clear(); due.forEach { it.second() } }
    }

    @Test fun aBurstRunsOnceAfterTheDelay() {
        val timer = HandTimer()
        val debouncer = Debouncer(WidgetUpdates.delayMs, timer)
        var runs = 0
        repeat(5) { debouncer.submit { runs++ } }
        assertEquals("nothing runs before the delay", 0, runs)
        assertEquals(1, timer.waiting.size)
        assertEquals(4, timer.cancelled)
        assertEquals(2_000L, timer.waiting.single().first)
        timer.fire()
        assertEquals(1, runs)
        debouncer.submit { runs++ }
        timer.fire()
        assertEquals(2, runs)
    }

    @Test fun theStoreTellsTheProcessHookOnlyOfANewDigest() {
        val written = mutableListOf<GlanceDigest>()
        StudyStore.onAnyGlanceWritten = { written += it }
        val store = StudyStore(folder.root)
        assertEquals("the first digest is written at load", 1, written.size)
        store.publishGlance()
        assertEquals("the same numbers tell no one", 1, written.size)
    }
}
