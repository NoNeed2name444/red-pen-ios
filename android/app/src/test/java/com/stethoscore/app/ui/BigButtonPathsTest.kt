package com.stethoscore.app.ui

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// The owner, 22 Oct: no filled coloured buttons; the main button is a
// page-coloured raised capsule with its words in the section's ink, as iOS
// .bigPrimary (WardButtonStyle primary, Shared/Ward/WardControls.swift). Every
// big-button path on Android draws through WardButtonBox and none paints
// the section's colour (or white words) behind it.
class BigButtonPathsTest {
    private val ui = File("src/main/java/com/stethoscore/app/ui")

    private fun body(file: String, fn: String): String {
        val text = File(ui, file).readText()
        val start = text.indexOf("fun $fn(")
        assertTrue("found $fn in $file", start >= 0)
        val ends = listOf("\n@Composable", "\n/**", "\ninternal fun", "\nprivate fun", "\nfun ")
            .map { text.indexOf(it, start + 1) }.filter { it > 0 }
        return text.substring(start, ends.minOrNull() ?: text.length)
    }

    private val paths = listOf(
        "ChartQuizViews.kt" to "QuizBigButton",
        "AnkiReviewScreen.kt" to "CardsPrimaryButton",
        "cases/CaseKit.kt" to "CaseButton",
        "mock/MockKit.kt" to "BigButton",
    )

    @Test fun everyBigButtonDrawsThroughWardButtonBox() {
        for ((file, fn) in paths) assertTrue("$fn draws through WardButtonBox", body(file, fn).contains("WardButtonBox("))
    }

    @Test fun noBigButtonIsFilledInTheSectionColour() {
        val filled = listOf("WardToken.primary)", "WardToken.onPrimary", "containerColor", "buttonColors(")
        // Material's filled Button (an OutlinedButton is not a fill)
        val material = Regex("(?<![A-Za-z])Button\\(")
        for ((file, fn) in paths) {
            val b = body(file, fn)
            for (f in filled) assertTrue("$fn uses $f (a filled primary)", !b.contains(f))
            assertTrue("$fn uses Material's filled Button", !material.containsMatchIn(b.replace("fun $fn(", "")))
        }
    }
}
