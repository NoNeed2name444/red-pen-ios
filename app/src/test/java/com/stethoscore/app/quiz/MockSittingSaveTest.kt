package com.stethoscore.app.quiz

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.UUID

// A port of upstream/ios/RedPen/Tests/MockSittingSaveTests.swift, case for
// case: a mock paper left part way comes back as it was left.
class MockSittingSaveTest {
    @Test fun sittingComesBackAsItWasLeft() {
        val dir = Files.createTempDirectory("mock-").toFile()
        val file = File(File(dir, "nested"), "mock-sitting.json")
        val q1 = UUID.randomUUID().toString(); val q2 = UUID.randomUUID().toString(); val q3 = UUID.randomUUID().toString()
        val started = 1_790_000_000_000L
        val sitting = MockSittingSave(
            title = "PLAB 1", specs = listOf(MockSectionSpec("Paper", 3, 180)),
            questionIds = listOf(listOf(q1, q2, q3)), wanted = 180, track = "plab", passMark = 0.63,
            section = 0, current = 2, selected = mapOf(q1 to 3, q2 to 0),
            orders = mapOf(q1 to listOf(2, 0, 1, 3, 4), q2 to listOf(0, 1, 2, 3, 4)),
            flagged = setOf(q2), struck = mapOf(q1 to setOf(1, 4)), highlights = mapOf(q3 to setOf(0, 2)),
            secondsLeft = 4_321.5, onBreak = false, spent = mapOf(q1 to 61.2, q2 to 30.0), startedAt = started)

        assertNull("nothing to resume before anything is saved", MockSittingStore.load(file))
        MockSittingStore.save(sitting, file)
        val back = MockSittingStore.load(file)
        assertEquals("a sitting comes back exactly as it was saved, in a folder made for it", sitting, back)
        assertTrue("answers, crossed-out options and flags come back by question",
            back?.selected?.get(q1) == 3 && back.struck[q1] == setOf(1, 4) && back.flagged == setOf(q2))
        assertTrue("and the clock as it was left", back?.secondsLeft == 4_321.5 && back.startedAt == started)
        assertTrue("answered and total, for the resume card", back?.answered == 2 && back.total == 3)

        val later = sitting.copy(selected = sitting.selected + (q3 to 1), current = 0)
        MockSittingStore.save(later, file)
        assertEquals("a later save replaces the earlier one", 1, MockSittingStore.load(file)?.selected?.get(q3))

        file.writeText("not a sitting")
        assertNull("a file that cannot be read is no sitting, not a crash", MockSittingStore.load(file))

        MockSittingStore.save(sitting, file)
        MockSittingStore.clear(file)
        assertNull("a finished or abandoned sitting leaves nothing to resume", MockSittingStore.load(file))

        dir.deleteRecursively()
    }
}
