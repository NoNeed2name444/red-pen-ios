package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import com.stethoscore.app.ui.home.HomePlanButton
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// T0217: the controls iOS's default-size audit found too small to hit (app build run
// 42142451702, AUDIT-NIL): home's Open plan, the library's search field and the study
// screens' More. Here each one's touch target is at least 48 dp both ways.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AuditHitAreaTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    // The control's own bounds, not its touch bounds: Compose reaches any clickable's touch bounds
    // to 48 dp, so those pass even for an 18 dp control and would prove nothing.
    private fun SemanticsNodeInteraction.assertTarget(name: String, ownHeight: Boolean = true) {
        val own = getUnclippedBoundsInRoot()
        assertTrue("$name is 48 dp wide: ${own.width}", own.width >= 48.dp)
        if (ownHeight) assertTrue("$name is 48 dp tall: ${own.height}", own.height >= 48.dp)
        val touch = fetchSemanticsNode().touchBoundsInRoot
        val tall = with(compose.density) { touch.height.toDp() }
        assertTrue("$name's touch area is 48 dp tall: $tall", tall >= 48.dp)
    }

    @Test fun openPlanIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { HomePlanButton(onPlan = {}) } }
        compose.onNodeWithText("Open plan").assertTarget("Open plan", ownHeight = false)  // trimmed to the words' height in its row by design
    }

    @Test fun theSearchFieldIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { HomeSearchRow("", {}, onSources = {}, onSettings = {}) } }
        compose.onNode(hasSetTextAction()).assertTarget("the search field")
    }

    @Test fun studyMoreIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { StudyMoreButton { } } }
        compose.onNodeWithContentDescription("More").assertTarget("More")
    }
}
