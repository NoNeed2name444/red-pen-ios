package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import com.stethoscore.app.data.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// Card review's four ratings stand in one row of words (the owner, 22 Oct), and a
// word is never clipped: on a 360 dp phone at large text (font scale 1.3 and 1.45,
// below the one-to-a-row sizes) each word, and the time under it ("4 d"), is on one
// line inside its button, shrunk to fit if it must, never cut (CardReview.leastWordScale).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w360dp-h800dp")
class RatingWordFitTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    @Test fun atFontScale130TheWordsFit() = wordsFit(1.3f)

    @Test fun atFontScale145TheWordsFit() = wordsFit(1.45f)

    private fun wordsFit(scale: Float) {
        val store = StudyStore(folder.newFolder("fit"))
        val set = StudySet(name = "Lupus", subject = "Rheumatology", kind = StudySetKind.ANKI, cards = listOf(
            AnkiCard(front = "Rash across the cheeks?", bullets = listOf("**Malar** rash")),
        ))
        store.addSet(set)
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                StethoscoreTheme { AnkiReviewScreen(set, store, onBack = {}) }
            }
        }
        compose.onNodeWithText("Reveal").performClick()
        // the times the screen shows, worked out as the screen works them out
        val labels = ReviewOptions.previewLabels(ReviewPlan.record(set.cards.first(), store.reviews), System.currentTimeMillis(), store.examDate, store.reviewSettings.scheduler)
        val tops = mutableSetOf<Float>()
        for (rating in AnkiRating.entries) {
            val word = CardReview.title(rating)
            val button = compose.onNodeWithContentDescription("$word, back in", substring = true).getUnclippedBoundsInRoot()
            tops += button.top.value
            fitsOnOneLine(scale, word, button.left, button.right)
            val time = CardReview.bareInterval(labels[rating] ?: "")
            assertTrue("$scale: $word has a time", time.isNotEmpty())
            fitsOnOneLine(scale, time, button.left, button.right, after = word)
        }
        assertEquals("$scale: still one row", 1, tops.size)
    }

    /** [text] (the one under [after], where two buttons show the same) is one unclipped line between [left] and [right]. */
    private fun fitsOnOneLine(scale: Float, text: String, left: Dp, right: Dp, after: String? = null) {
        val name = if (after == null) text else "$after's $text"
        val node = compose.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes()
            .firstOrNull { val b = it.boundsInRoot; b.left >= left.value * it.layoutInfo.density.density - 0.5f &&
                b.right <= right.value * it.layoutInfo.density.density + 0.5f }
        assertTrue("$scale: $name inside its button", node != null)
        val layouts = mutableListOf<TextLayoutResult>()
        node!!.config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
        val layout = layouts.single()
        assertEquals("$scale: $name on one line", 1, layout.lineCount)
        assertFalse("$scale: $name is not clipped", layout.hasVisualOverflow)
    }
}
