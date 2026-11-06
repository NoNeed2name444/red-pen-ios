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
import androidx.compose.ui.unit.Dp
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
    // one row at 1.0, too wide for one at 2.0 (at 2.0, Sodium 128 mmol/L L just fits: 296 dp of 296)
    private val potassium = PatientChart.Lab("Potassium", "6.8", "mmol/L", PatientChart.Flag.high)

    private val labs = mutableStateOf(listOf<PatientChart.Lab>())
    private val scale = mutableStateOf(1f)
    // each text's last layout, by column and words: "wide:Albumin", "stacked:22"
    private val layouts = mutableMapOf<String, TextLayoutResult>()
    private var composed = false

    /** The table at `size` with `shown`: composed once per test, then the results and the scale change in place. */
    private fun show(size: Float, vararg shown: PatientChart.Lab) {
        labs.value = shown.toList()
        scale.value = size
        if (!composed) {
            composed = true
            compose.setContent {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale.value), LocalLabTextLayouts provides layouts) {
                    StethoscoreTheme { Box(Modifier.width(320.dp)) { ChartLabsTable(labs.value) } }
                }
            }
        }
        compose.waitForIdle()
    }

    private fun bounds(lab: PatientChart.Lab) =
        compose.onAllNodesWithContentDescription(ChartQuiz.spoken(lab)).onFirst().getUnclippedBoundsInRoot()

    /** One line of the table's text: its value, which is one line in either column. */
    private fun line(lab: PatientChart.Lab): Dp {
        val value = layouts["stacked:${lab.value}"] ?: layouts.getValue("wide:${lab.value}")
        return with(compose.density) { value.size.height.toDp() }
    }

    /** The column `lab` is placed in, read from its placed height: stacked is more than one and a half lines. */
    private fun column(lab: PatientChart.Lab): String = if (bounds(lab).height > line(lab) * 1.5f) "stacked" else "wide"

    /** `words`' layout in the column `lab` is placed in. */
    private fun text(lab: PatientChart.Lab, words: String): TextLayoutResult = layouts.getValue(column(lab) + ":" + words)

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

    private fun words(lab: PatientChart.Lab) = listOf(lab.name, lab.value, lab.unit, lab.flag!!.rawValue)

    /** Placed as one row: as tall as one line of its name, within 1 dp. */
    private fun oneRow(lab: PatientChart.Lab) {
        assertEquals("${lab.name} is not placed wide", "wide", column(lab))
        val row = bounds(lab).height
        val name = with(compose.density) { text(lab, lab.name).size.height.toDp() }
        assertTrue("${lab.name}'s row is $row, a line is $name", row <= name + 1.dp)
        for (w in words(lab)) whole(text(lab, w), w)
        oneNode(lab)
    }

    /** Placed stacked, its name broken only between words and its value, unit and flag whole. */
    private fun stackedWhole(lab: PatientChart.Lab) {
        assertEquals("${lab.name} is not stacked", "stacked", column(lab))
        assertTrue("${lab.name} is not stacked", bounds(lab).height > line(lab) * 1.5f)
        breaksOnlyBetweenWords(text(lab, lab.name), lab.name)
        for (w in words(lab).drop(1)) whole(text(lab, w), w)
        oneNode(lab)
    }

    @Test fun atFontScale2ALongResultStacksWhole() {
        show(2f, long)
        stackedWhole(long)
        // stacked: the value starts a line of its own, under the name
        assertTrue("the name is squeezed beside the value", text(long, long.name).size.width > text(long, long.value).size.width * 2)
    }

    // At the default size the table is one ViewThatFits, as on iOS: a short result
    // alone keeps its one row; beside one too long for a row, both are stacked;
    // changed in place, back to the short one alone, it is one row again.
    @Test fun atTheDefaultSizeTheTableStacksAsAWhole() {
        show(1f, short)
        oneRow(short)
        show(1f, long, short)
        stackedWhole(long)
        stackedWhole(short)
        show(1f, short)
        oneRow(short)
    }

    // The text size changed while the table is on screen: wide at 1.0, stacked at
    // 2.0, wide again at 1.0, as a new table at each size would be.
    @Test fun aFontScaleChangedInPlaceStacksAndUnstacks() {
        show(1f, potassium)
        oneRow(potassium)
        show(2f, potassium)
        stackedWhole(potassium)
        show(1f, potassium)
        oneRow(potassium)
    }
}

private fun androidx.compose.ui.test.SemanticsNodeInteractionCollection.onFirst() = this[0]
