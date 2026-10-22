package com.stethoscore.app.ui

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// The twin of iOS b3b21c29 ("drop the top scroll line"): no line where a
// page's content scrolls away under its header. The page header draws none,
// and no screen puts a divider straight under it.
class ScrollEdgeTest {
    private val ui = File("src/main/java/com/stethoscore/app/ui")

    @Test fun theHeaderDrawsNoLine() {
        val theme = File(ui, "Theme.kt").readText()
        val start = theme.indexOf("@Composable fun ScreenHeader")
        assertTrue("found ScreenHeader", start >= 0)
        val header = theme.substring(start, theme.indexOf("\n@Composable", start + 1))
        for (line in listOf("Divider", "border(", "drawLine", "drawBehind")) assertTrue("ScreenHeader draws $line", !header.contains(line))
    }

    @Test fun noDividerUnderAHeader() {
        val files = ui.walkTopDown().filter { it.extension == "kt" }.toList()
        assertTrue("found the screens", files.size > 3)
        for (file in files) {
            val lines = file.readLines()
            for ((i, line) in lines.withIndex()) if (line.contains("ScreenHeader(") && !line.contains("fun ScreenHeader")) {
                val next = lines.drop(i + 1).take(2).joinToString("\n")
                assertTrue("${file.name}:${i + 1}: a line under the page header", !next.contains("Divider"))
            }
        }
    }
}
