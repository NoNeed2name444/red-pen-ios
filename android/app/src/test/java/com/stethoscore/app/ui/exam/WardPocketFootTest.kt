package com.stethoscore.app.ui.exam

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.Dp
import com.stethoscore.app.exam.WardCalc
import com.stethoscore.app.exam.WardScores
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.StethoscoreTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The tour (r050) showed the score page's last row, "Practise this", under the
// floating total and the disclaimer chip. Scrolled to its end, each page's last
// row ends above what floats at its foot.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WardPocketFootTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun scrollToTheEnd() {
        compose.onNode(hasScrollAction()).performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, 1_000_000f) }
        compose.waitForIdle()
    }

    private fun SemanticsNodeInteraction.bottom(): Dp = getBoundsInRoot().bottom
    private fun SemanticsNodeInteraction.top(): Dp = getBoundsInRoot().top

    @Test fun theScorePageEndsAboveItsTotal() {
        val score = WardScores.all.first()
        compose.setContent { StethoscoreTheme { WardPocketScreen(ExamTrack.general, {}, {}, start = WardPocketTab.scores) } }
        compose.onNode(hasText(score.name, substring = true) and hasClickAction()).performClick()
        compose.waitForIdle()
        scrollToTheEnd()
        val last = compose.onNodeWithTag("wardPractise").bottom()
        val total = compose.onNodeWithTag("wardScoreTotal").top()
        assertTrue("Practise this ends at $last, above the total at $total", last <= total)
    }

    @Test fun theCalculatorListEndsAboveTheDisclaimer() {
        compose.setContent { StethoscoreTheme { WardPocketScreen(ExamTrack.general, {}, {}) } }
        scrollToTheEnd()
        val last = compose.onNode(hasText(WardCalc.calculators.last().title) and hasClickAction()).bottom()
        val chip = compose.onNodeWithTag("wardDisclaimer").top()
        assertTrue("the last calculator ends at $last, above the disclaimer at $chip", last <= chip)
    }
}
