package com.stethoscore.app

import androidx.activity.ComponentActivity
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.window.layout.FoldingFeature
import androidx.window.testing.layout.FoldingFeature
import androidx.window.testing.layout.TestWindowLayoutInfo
import androidx.window.testing.layout.WindowLayoutInfoPublisherRule
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.ward.WardRect
import com.stethoscore.app.ui.ward.WindowShape
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import org.junit.rules.TestRule
import org.junit.runner.RunWith
import java.io.File

/**
 * The hinge, proved without the emulator folding (T0139): androidx.window's
 * WindowLayoutInfoPublisherRule hands the app a fake FoldingFeature for each
 * posture (book: half open, upright; tabletop: half open, across; a flat fold
 * that does not split), and on each of the core screens no clickable node's
 * bounds meet the hinge and every clickable node's touch area is at least
 * 48 dp each way (WardControlSize.target). The script runs this class once in
 * each orientation (natural, left, right), the device turned before it starts.
 */
@RunWith(AndroidJUnit4::class)
class FoldLayoutTest {
    private val publisher = WindowLayoutInfoPublisherRule()
    private val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val rules: TestRule = RuleChain.outerRule(publisher).around(compose).around(LearnRouterClosed())

    private val screens = listOf("home", "settings", "mock", "due", "quiz")
    private val screen = mutableStateOf("home")

    private fun store(): StudyStore {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        return StudyStore(File(context.cacheDir, "fold-${System.nanoTime()}")).also { it.loadExamples() }
    }

    /** Publishes a fold through the window's middle, [state] and [orientation], and returns its bounds in dp. */
    private fun fold(state: FoldingFeature.State, orientation: FoldingFeature.Orientation): WindowShape {
        lateinit var shape: WindowShape
        compose.activityRule.scenario.onActivity { activity ->
            val view = activity.window.decorView
            val center = if (orientation == FoldingFeature.Orientation.VERTICAL) view.width / 2 else view.height / 2
            val feature = FoldingFeature(activity, center, 0, state, orientation)
            publisher.overrideWindowLayoutInfo(TestWindowLayoutInfo(listOf(feature)))
            val density = activity.resources.displayMetrics.density.toDouble()
            shape = WindowShape(view.width / density, view.height / density, WindowShape.fold(feature, density))
        }
        compose.waitForIdle()
        return shape
    }

    private fun rect(node: SemanticsNode, density: Double, touch: Boolean = false): WardRect {
        val b = if (touch) node.touchBoundsInRoot else node.boundsInWindow
        return WardRect(b.left / density, b.top / density, b.width / density, b.height / density)
    }

    /** Every clickable node on [name]: out of the hinge, and a finger's size. */
    private fun checkScreen(name: String, shape: WindowShape, posture: String): Int {
        val density = InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.density.toDouble()
        val nodes = compose.onAllNodes(hasClickAction()).fetchSemanticsNodes()
        assertTrue("$posture, $name: clickable nodes laid out", nodes.isNotEmpty())
        for (node in nodes) {
            val r = rect(node, density)
            if (r.width <= 0 || r.height <= 0) continue
            val label = node.config.getOrElseNullable(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription) { null }?.joinToString()
                ?: node.config.getOrElseNullable(androidx.compose.ui.semantics.SemanticsProperties.Text) { null }?.joinToString() ?: "node ${node.id}"
            assertTrue("$posture, $name: \"$label\" at $r meets the hinge ${shape.separatingFold?.bounds}", !shape.meetsHinge(r))
            val t = rect(node, density, touch = true)
            assertTrue("$posture, $name: \"$label\" is ${t.width} x ${t.height} dp, under ${WardControlSize.target}",
                t.width >= WardControlSize.target - 0.5 && t.height >= WardControlSize.target - 0.5)
        }
        return nodes.size
    }

    private fun eachScreen(state: FoldingFeature.State, orientation: FoldingFeature.Orientation, posture: String) {
        val s = store()
        compose.setContent { key(screen.value) { StethoscoreApp(s, initialScreen = if (screen.value == "quiz") "home" else screen.value) } }
        compose.waitForIdle()
        val shape = fold(state, orientation)
        var checked = 0
        for (name in screens) {
            screen.value = name
            compose.waitForIdle()
            if (name == "quiz") {
                val set = s.library.first { it.kind == StudySetKind.MCQ }
                compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText(set.name))
                compose.onAllNodes(hasText(set.name) and hasClickAction()).onFirst().performSemanticsAction(SemanticsActions.OnClick)
                compose.waitForIdle()
            }
            checked += checkScreen(name, shape, posture)
        }
        assertTrue("$posture: nodes checked", checked > 0)
    }

    @Test fun bookHalfOpen() = eachScreen(FoldingFeature.State.HALF_OPENED, FoldingFeature.Orientation.VERTICAL, "book")
    @Test fun tabletopHalfOpen() = eachScreen(FoldingFeature.State.HALF_OPENED, FoldingFeature.Orientation.HORIZONTAL, "tabletop")
    @Test fun flatOpenVertical() = eachScreen(FoldingFeature.State.FLAT, FoldingFeature.Orientation.VERTICAL, "flat, upright fold")
    @Test fun flatOpenHorizontal() = eachScreen(FoldingFeature.State.FLAT, FoldingFeature.Orientation.HORIZONTAL, "flat, fold across")
}
