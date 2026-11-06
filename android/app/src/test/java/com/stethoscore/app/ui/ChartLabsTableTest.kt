package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.quiz.PatientChart
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// The quiz's results table (iOS ChartLabsTable): at large text a long result is
// stacked, its name broken only between words and its value and flag whole; at
// the default size it is the one row it always was. Each result is one TalkBack
// node, read as ChartQuiz.spoken says, however it is laid out. Native graphics, so
// the text is measured as a phone measures it.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w360dp-h800dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ChartLabsTableTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val long = PatientChart.Lab("Alkaline phosphatase", "1,250", "mmol/L", PatientChart.Flag.high)
    private val short = PatientChart.Lab("Albumin", "22", "g/L", PatientChart.Flag.low)

    private fun show(scale: Float, vararg labs: PatientChart.Lab): Map<String, TextLayoutResult> {
        val layouts = mutableMapOf<String, TextLayoutResult>()
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalLabTextLayouts provides layouts) {
                StethoscoreTheme { Box(Modifier.width(320.dp)) { ChartLabsTable(labs.toList()) } }
            }
        }
        compose.waitForIdle()
        return layouts
    }

    /** Every line but the last ends at a space: no word is split across lines. */
    private fun breaksOnlyBetweenWords(layout: TextLayoutResult, words: String) {
        for (line in 0 until layout.lineCount - 1) {
            val end = layout.getLineEnd(line)
            assertTrue("\"$words\" broken inside a word at $end", words[end - 1] == ' ' || words.getOrNull(end) == ' ')
        }
    }

    private fun whole(layout: TextLayoutResult, words: String) {
        assertEquals("\"$words\" on more than one line", 1, layout.lineCount)
        assertFalse("\"$words\" cut", layout.hasVisualOverflow)
    }

    private fun oneNode(lab: PatientChart.Lab) {
        val nodes = compose.onAllNodesWithContentDescription(ChartQuiz.spoken(lab)).fetchSemanticsNodes()
        assertEquals(1, nodes.size)
        assertEquals(listOf(ChartQuiz.spoken(lab)), nodes[0].config.getOrNull(SemanticsProperties.ContentDescription))
        // the words are drawn, not read one by one
        assertEquals(0, compose.onAllNodesWithText(lab.name).fetchSemanticsNodes().size)
    }

    @Test fun atFontScale2ALongResultStacksWhole() {
        val layouts = show(2f, long)
        breaksOnlyBetweenWords(layouts.getValue(long.name), long.name)
        whole(layouts.getValue(long.value), long.value)
        whole(layouts.getValue("H"), "H")
        // stacked: the value starts a line of its own, under the name
        val name = layouts.getValue(long.name)
        assertTrue("the name is squeezed beside the value", name.size.width > layouts.getValue(long.value).size.width * 2)
        oneNode(long)
    }

    @Test fun atTheDefaultSizeEachResultIsOneLine() {
        val layouts = show(1f, long, short)
        for (lab in listOf(long, short)) {
            for (words in listOf(lab.name, lab.value, lab.unit, lab.flag!!.rawValue)) whole(layouts.getValue(words), words)
            oneNode(lab)
        }
        // one line each: the row is as tall as one line of its text
        val row = compose.onAllNodesWithContentDescription(ChartQuiz.spoken(short)).onFirst().getUnclippedBoundsInRoot()
        val line = with(compose.density) { layouts.getValue(short.name).size.height.toDp() }
        assertTrue("the row is ${row.height}, a line is $line", row.height <= line + 1.dp)
    }
}

private fun androidx.compose.ui.test.SemanticsNodeInteractionCollection.onFirst() = this[0]
