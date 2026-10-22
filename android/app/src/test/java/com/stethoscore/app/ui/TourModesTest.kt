package com.stethoscore.app.ui

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// The tour shoots every screen in light and dark (r060, bedtime, had no light
// picture: its row was limited to dark because the panel is always dark, but
// the sheet round it is not). A row may not pick one mode.
class TourModesTest {
    @Test fun noRowIsShotInOneModeOnly() {
        val tour = File("src/androidTest/java/com/stethoscore/app/TourTest.kt")
        assertTrue("the tour's source is where the test looks for it", tour.exists())
        val oneMode = Regex("""listOf\(\s*Mode\.(LIGHT|DARK)\s*\)""")
        val found = tour.readLines().withIndex().filter { oneMode.containsMatchIn(it.value) }.map { "TourTest.kt:${it.index + 1}" }
        assertTrue("rows shot in one mode only: $found", found.isEmpty())
    }
}
