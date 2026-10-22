package com.stethoscore.app.ui

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// The tour frames each screen as the app does (r039, r008): a page inside the
// frame's ring by wardFrameClearance, as StethoscoreApp places every framed
// page, and the card and question sheets in the editor's place, never drawn
// over it (two headers, the sheet's over the status bar, labels overlapping).
class TourFramingTest {
    private fun source(name: String): String {
        val file = File("src/androidTest/java/com/stethoscore/app/$name")
        assertTrue("$name is where the test looks for it", file.exists())
        return file.readText()
    }

    @Test fun aPageSitsInsideTheRingAsInTheApp() {
        val app = File("src/main/java/com/stethoscore/app/ui/StethoscoreApp.kt")
        assertTrue("the app places a framed page by wardFrameClearance", app.readText().contains(".wardFrameClearance()"))
        val page = Regex("""@Composable fun Page\([^)]*\)[^{]*\{(.*?)\n    }""", RegexOption.DOT_MATCHES_ALL).find(source("TourCapture.kt"))
        assertTrue("TourCapture.Page is found", page != null)
        assertTrue("TourCapture.Page places its page by wardFrameClearance", page!!.groupValues[1].contains(".wardFrameClearance()"))
    }

    @Test fun anEditSheetIsNeverDrawnOverItsEditor() {
        val over = Regex("""tour\.Over\([^)]*\)\s*\{\s*(CardEditSheet|QuestionEditSheet)""")
        val found = over.findAll(source("TourTest.kt")).map { it.groupValues[1] }.toList()
        assertTrue("edit sheets drawn over a page: $found", found.isEmpty())
    }
}
