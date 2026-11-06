package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
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
// stacked, its name broken only between words and its value and flag whole; the
// table is wide or stacked as a whole, never mixed. Each result is one TalkBack
// node, read as ChartQuiz.spoken says, however it is laid out. Native graphics, so
// the text is measured as a phone measures it.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w360dp-h800dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ChartLabsTableTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val long = PatientChart.Lab("Alkaline phosphatase", "1,250", "mmol/L", PatientChart.Flag.high)
    private val short = PatientChart.Lab("Albumin", "22", "g/L", PatientChart.Flag.low)

    private val labs = mutableStateOf(listOf<PatientChart.Lab>())
    private val layouts = mutableMapOf<String, TextLayoutResult>()
    private var scale = 1f
    private var composed = false

    /** The table at `scale` with `shown`; set once per test, then the labs change in place. */
    private fun show(scale: Float, vararg shown: PatientChart.Lab): Map<String, TextLayoutResult> {
        layouts.clear()
        labs.value = shown.toList()
        if (!composed) {
            composed = true
            this.scale = scale
            compose.setContent {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, this.scale), LocalLabTextLayouts provides layouts) {
                    StethoscoreTheme { Box(Modifier.width(320.dp)) { ChartLabsTable(labs.value) } }
                }
            }
        }
        compose.waitForIdle()
        return layouts.toMap()
    }

    /** Every line but the last ends at a space: no word is split across lines. */
    private fun breaksOnlyBetweenWords(layout: TextLayoutResult, words: String) {
        for (line in 0 until layout.lineCount - 1) {
            val end = layout.getLineEnd(line)
            assertTrue("\"$words\" broken inside a word at $end", words[end - 1] == ' ' || words.getOrNull(end) == ' ')
        }
    }

    private fun whole(layout: TextLayoutResult, words: String) {
        assertEquals("\"$words\" on more than one line (laid out in ${layout.layoutInput.constraints}, ${layout.size})", 1, layout.lineCount)
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

    /** How many lines of its name tall `lab`'s row is. */
    private fun rowLines(lab: PatientChart.Lab, layouts: Map<String, TextLayoutResult>): Float {
        val row = compose.onAllNodesWithContentDescription(ChartQuiz.spoken(lab)).onFirst().getUnclippedBoundsInRoot()
        val line = with(compose.density) { layouts.getValue(lab.name).size.height.toDp() }
        return row.height / line
    }

    // At the default size the table is one ViewThatFits, as on iOS: a short result
    // alone keeps its one row; beside one too long for a row, both are stacked.
    @Test fun atTheDefaultSizeTheTableStacksAsAWhole() {
        val alone = show(1f, short)
        for (words in listOf(short.name, short.value, short.unit, short.flag!!.rawValue)) whole(alone.getValue(words), words)
        oneNode(short)
        assertTrue("a short result alone is not one row", rowLines(short, alone) < 1.1f)

        val layouts = show(1f, long, short)
        for (lab in listOf(long, short)) {
            for (words in listOf(lab.name, lab.value, lab.unit, lab.flag!!.rawValue)) whole(layouts.getValue(words), words)
            oneNode(lab)
            assertTrue("${lab.name} is not stacked with the rest of the table", rowLines(lab, layouts) > 1.5f)
        }
    }
}

private fun androidx.compose.ui.test.SemanticsNodeInteractionCollection.onFirst() = this[0]
