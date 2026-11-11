package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import com.stethoscore.app.ui.home.HomePlanButton
import com.stethoscore.app.ui.ward.WardControlSize
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
        val least = WardControlSize.target.dp
        assertTrue("$name is $least wide: ${own.width}", own.width >= least)
        if (ownHeight) assertTrue("$name is $least tall: ${own.height}", own.height >= least)
        val touch = fetchSemanticsNode().touchBoundsInRoot
        val tall = with(compose.density) { touch.height.toDp() }
        assertTrue("$name's touch area is $least tall: $tall", tall >= least)
    }

    // At the standard sizes the row is trimmed to the words' height by design, so its own height is
    // not the target; Compose reaches the touch to 48 dp round it, and its width is the control's.
    @Test fun openPlanIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { HomePlanButton(onPlan = {}) } }
        compose.onNodeWithText("Open plan").assertTarget("Open plan", ownHeight = false)
    }

    // At the accessibility sizes the row keeps its whole target's height: its own bounds are the
    // target (the words and 12 dp a side, floored at the least target). Robolectric measures it
    // 60 dp tall at 1.65 and 59 dp at 2.0, so the floor alone is not what these tests catch; they
    // fail if the padding goes (35 dp) and pass again with the floor in place (48 dp).
    private fun openPlanAt(scale: Float) {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, scale)) {
                StethoscoreTheme { HomePlanButton(onPlan = {}) }
            }
        }
        compose.onNodeWithText("Open plan").assertTarget("Open plan at font scale $scale")
    }

    @Test fun openPlanIsA48DpTallWhereTheAccessibilitySizesBegin() = openPlanAt(1.65f)

    @Test fun openPlanIsA48DpTallAtFontScale2() = openPlanAt(2f)

    @Test fun theSearchFieldIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { HomeSearchRow("", {}, onSources = {}, onSettings = {}) } }
        compose.onNode(hasSetTextAction()).assertTarget("the search field")
    }

    @Test fun studyMoreIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { StudyMoreButton { } } }
        compose.onNodeWithContentDescription("More").assertTarget("More")
    }
}
