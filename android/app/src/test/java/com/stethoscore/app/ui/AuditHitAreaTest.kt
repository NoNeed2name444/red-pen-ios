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
import org.robolectric.annotation.GraphicsMode

// T0217: the controls iOS's default-size audit found too small to hit (app build run
// 42142451702, AUDIT-NIL): home's Open plan, the library's search field and the study
// screens' More. Here each one's touch target is at least 48 dp both ways. Native graphics, so
// the words are measured as the device measures them, not by Robolectric's legacy text.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
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

    // At the standard sizes the row is trimmed to the words' height in its row by design, so its own
    // height is not the target (the node reads 42 dp under native graphics); Compose reaches the
    // touch to 48 dp round the words, and the control is its words wide (81 dp). No floor is added
    // there, so this test has nothing of the app's to catch: it records the width and the reach.
    @Test fun openPlanIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { HomePlanButton(onPlan = {}) } }
        compose.onNodeWithText("Open plan").assertTarget("Open plan", ownHeight = false)
    }

    // At the accessibility sizes the row keeps its whole target's height, the words and 12 dp a side:
    // 54 dp at 1.65 and 59 dp at 2.0 under native graphics, with no floor in the app. With the
    // padding removed they read 30 and 35 dp and these two fail; that is what they catch.
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
