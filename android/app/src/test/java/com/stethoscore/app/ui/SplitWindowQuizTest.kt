package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.ForcedSize
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.ChartQuiz
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// T0247: the Android CI's split-screen pass (ScreenshotTest.WindowShots, the medium phone) never came back from
// quizChecked. At 412x302 dp the title bar, the header and the deck took the whole window, the question area was
// 0 px tall, and performScrollTo (which loops until the node is in view) looped for good. This drives the same steps
// at the six sizes of that pass, at the phone's 420 dpi. Scrolling is bounded here, so a question area that cannot
// show an option fails the test instead of hanging it, and a timeout bounds the whole run as well.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w412dp-h915dp-420dpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SplitWindowQuizTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val size = mutableStateOf<DpSize?>(null)

    private fun waitFor(what: String, matcher: SemanticsMatcher) {
        try { compose.waitUntil(20_000) { compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() } }
        catch (e: ComposeTimeoutException) { throw AssertionError("no $what", e) }
    }

    private fun delta(a: Float, b: Float): Float =
        if (Math.signum(a) == Math.signum(b)) (if (Math.abs(a) < Math.abs(b)) a else b) else 0f

    /**
     * performScrollTo's own steps (it scrolls by the gap between the node and its scrollable parent until there is
     * none), a few at a time at most. False when the node cannot be brought into view, or when the scrollable parent
     * is less than one touch target tall: a page that small shows the reader nothing to answer with.
     */
    private fun scrollsIntoView(target: SemanticsNodeInteraction): Boolean {
        repeat(8) {
            compose.waitForIdle()
            val node = target.fetchSemanticsNode()
            val scroller = generateSequence(node.parent) { it.parent }.firstOrNull { SemanticsActions.ScrollBy in it.config } ?: return true
            val coords = scroller.layoutInfo.coordinates
            val view = coords.boundsInParent().translate(coords.parentLayoutCoordinates?.positionInRoot() ?: Offset.Zero)
            val me = Rect(node.positionInRoot, androidx.compose.ui.geometry.Size(node.size.width.toFloat(), node.size.height.toFloat()))
            val dx = delta(me.left - view.left, me.right - view.right)
            val dy = delta(me.top - view.top, me.bottom - view.bottom)
            if (view.height < 48.dp.value * compose.density.density) return false
            if (dx == 0f && dy == 0f) return true
            compose.runOnUiThread { scroller.config[SemanticsActions.ScrollBy].action?.invoke(dx, dy) }
        }
        return false
    }

    private fun reach(what: String, matcher: SemanticsMatcher): SemanticsNodeInteraction {
        waitFor(what, matcher)
        val node = compose.onAllNodes(matcher).onFirst()
        check(scrollsIntoView(node)) { "$what cannot be scrolled into view: the question area has no room for it" }
        // a node with no scrollable parent (the deck's buttons) makes performScrollTo throw at once, as ScreenshotTest's tap expects
        try { node.performScrollTo() } catch (_: AssertionError) {}
        node.assertIsDisplayed()
        return node
    }

    private fun tap(what: String, matcher: SemanticsMatcher) {
        reach(what, matcher).performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
    }

    private fun quizChecked(z: DpSize) {
        val stores = HashMap<DpSize, StudyStore>()
        compose.setContent {
            val zz = size.value
            key(zz) {
                if (zz != null) {
                    val s = stores.getOrPut(zz) { StudyStore(folder.newFolder()).also { it.loadExamples() } }
                    DeviceConfigurationOverride(DeviceConfigurationOverride.ForcedSize(zz)) { StethoscoreApp(s) }
                }
            }
        }
        compose.runOnIdle { size.value = z }
        compose.waitForIdle()
        val set = stores.getValue(z).library.first { it.kind == StudySetKind.MCQ }
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText(set.name))
        tap("the set's row", hasText(set.name) and hasClickAction())
        val q = set.questions.first()
        // every option, not only the right one: where the options are shuffled to is not the test's to know
        for (option in q.options) reach("the option '${option.take(20)}'", hasClickAction() and hasContentDescription(": $option", substring = true))
        tap("the right answer", hasClickAction() and hasContentDescription(": " + q.options[q.correctIndex], substring = true))
        tap("Check answer", hasText(ChartQuiz.primaryTitle(false, true, false, false, false)) and hasClickAction())
        waitFor("Next question", hasText(ChartQuiz.primaryTitle(true, true, false, false, false)))
    }

    @Test(timeout = 120_000) fun at412x302() = quizChecked(DpSize(412.dp, 302.dp))
    @Test(timeout = 120_000) fun at412x453() = quizChecked(DpSize(412.dp, 453.dp))
    @Test(timeout = 120_000) fun at412x604() = quizChecked(DpSize(412.dp, 604.dp))
    @Test(timeout = 120_000) fun at302x412() = quizChecked(DpSize(302.dp, 412.dp))
    @Test(timeout = 120_000) fun at453x412() = quizChecked(DpSize(453.dp, 412.dp))
    @Test(timeout = 120_000) fun at604x412() = quizChecked(DpSize(604.dp, 412.dp))
}
