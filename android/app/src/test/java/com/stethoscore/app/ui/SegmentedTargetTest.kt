package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import com.stethoscore.app.data.ReviewScheduler
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.ward.WardSegmented
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// T0244: FoldLayoutTest found Settings' scheduler segment ("Classic") 38 dp tall in the book posture
// (Android CI run 43186101851). Each segment of WardSegmented is the clickable node, and it was only
// as tall as the segment drawn (36 dp, or its words); the capsule's 48 dp slot round it is not the
// segment's own bounds. Here each segment's own bounds and its touch bounds are at least 48 dp both
// ways, as the Settings screen composes the control, at the default font scale and at 1.3.
// Native graphics, so the words are measured as the device measures them.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SegmentedTargetTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    // The segment's own bounds, not only its touch bounds: Compose reaches a clickable's touch bounds
    // toward 48 dp where nothing clips them, so a short node can read 48 there and prove nothing
    // (AuditHitAreaTest says the same).
    private fun SemanticsNodeInteraction.assertTarget(name: String) {
        val own = getUnclippedBoundsInRoot()
        val least = WardControlSize.target.dp
        assertTrue("$name is $least wide: ${own.width}", own.width >= least)
        assertTrue("$name is $least tall: ${own.height}", own.height >= least)
        val touch = fetchSemanticsNode().touchBoundsInRoot
        val wide = with(compose.density) { touch.width.toDp() }
        val tall = with(compose.density) { touch.height.toDp() }
        assertTrue("$name's touch area is $least wide: $wide", wide >= least)
        assertTrue("$name's touch area is $least tall: $tall", tall >= least)
    }

    private val chosen = mutableStateOf(ReviewScheduler.CLASSIC)

    // As EditorSettings composes it: the scheduler on the Review card.
    private fun settingsScheduler(scale: Float) {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, scale)) {
                StethoscoreTheme {
                    WardCard(Modifier.fillMaxWidth()) {
                        WardSegmented(chosen.value, ReviewScheduler.entries, {}, Modifier.semantics { contentDescription = "Scheduler" }) { s, style, ink ->
                            Text(s.title, style = style, color = ink)
                        }
                    }
                }
            }
        }
    }

    // Each segment, with each of the two chosen: the chosen one is drawn heavier and its words may be wider.
    private fun eachSegmentIsATarget(scale: Float) {
        settingsScheduler(scale)
        for (pick in ReviewScheduler.entries) {
            chosen.value = pick
            compose.waitForIdle()
            for (option in ReviewScheduler.entries)
                compose.onNode(isSelectable() and hasText(option.title)).assertTarget("The ${option.title} segment (${pick.title} chosen) at font scale $scale")
        }
    }

    @Test fun eachSchedulerSegmentIsA48DpTarget() = eachSegmentIsATarget(1f)

    @Test fun eachSchedulerSegmentIsA48DpTargetAtFontScale1Point3() = eachSegmentIsATarget(1.3f)

    // The bounds are not the whole proof: a tap 1 dp inside the node's top and bottom edges, in the
    // reach above and below the 36 dp segment drawn (and past the capsule's edge), is delivered to that
    // segment by the pointer input itself, now that the node stands outside the drawn parts. It passes
    // on the old code too, where Compose's own touch reach delivered such a tap; it pins that the new
    // structure keeps delivering it.
    @Test fun aTapInTheReachAboveAndBelowASegmentSelectsIt() {
        val picked = mutableListOf<ReviewScheduler>()
        compose.setContent {
            StethoscoreTheme {
                WardCard(Modifier.fillMaxWidth()) {
                    WardSegmented(ReviewScheduler.CLASSIC, ReviewScheduler.entries, { picked += it }, Modifier.semantics { contentDescription = "Scheduler" }) { s, style, ink ->
                        Text(s.title, style = style, color = ink)
                    }
                }
            }
        }
        val fsrs = compose.onNode(isSelectable() and hasText(ReviewScheduler.FSRS.title))
        fsrs.performTouchInput { click(Offset(centerX, 1.dp.toPx())) }
        fsrs.performTouchInput { click(Offset(centerX, height - 1.dp.toPx())) }
        assertEquals("a tap in the reach above and one below select FSRS", listOf(ReviewScheduler.FSRS, ReviewScheduler.FSRS), picked)
    }
}
