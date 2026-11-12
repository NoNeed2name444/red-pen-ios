package com.stethoscore.app.ui.home

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performScrollToKey
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.learn.LearnRouterClosed
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// T0250: RotationStateTest.homeKeepsItsScrollAndTypedSearch failed on the small profile (720x1280 px at
// 320 dpi, 360x640 dp upright, 640x360 dp turned) and passed on tablet7 (600x960 dp, 960x600 dp). A turn keeps
// home's list on the same first row at the same offset, so a row further down than the shorter window is
// tall is not composed after it. The device test put "Scroll filler 20" in view with performScrollToNode,
// which walks the list a window's height at a time and stops where the row first shows: the row is left
// wherever that walk ended, not at the top. Here the row is put at the top by its key, and the list
// must come back from each turn at the same place, with that row still its first.
//
// The window sizes are laid out at a fixed density, so a place saved in pixels means the same dp after a
// turn, as it does on a device (DeviceConfigurationOverride.ForcedSize changes the density to fit its size
// in the host window, which moves a saved offset).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w360dp-h640dp-xhdpi")
class HomeTurnKeepsPlaceTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private val phone = DpSize(360.dp, 640.dp)
    private val phoneTurned = DpSize(640.dp, 360.dp)
    private val tablet7 = DpSize(600.dp, 960.dp)
    private val tablet7Turned = DpSize(960.dp, 600.dp)

    private fun exists(matcher: SemanticsMatcher) = compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()

    private fun list() = compose.onAllNodes(hasScrollToNodeAction()).onFirst()

    /** The list's scroll value: 500 for each row above the first visible one, and the pixels scrolled into that row. */
    private fun place(): Float =
        list().fetchSemanticsNode().config.getOrElseNullable(SemanticsProperties.VerticalScrollAxisRange) { null }?.value?.invoke() ?: Float.NaN

    /** Whether the row is the list's first: its top is less than its own height below the list's top. */
    private fun isFirstRow(name: String): Boolean {
        val row = compose.onAllNodes(hasText(name)).onFirst().getUnclippedBoundsInRoot()
        val below = row.top - list().getUnclippedBoundsInRoot().top
        return below < row.bottom - row.top
    }

    /**
     * Home with 40 sets after the examples, put at [portrait]'s size with "Scroll filler [n]" at the top of
     * its list, then turned to [turned], back, and to [turned] again: after each turn the list is at the
     * same place and that row is still its first.
     */
    private fun turnsKeepTheRowOnTop(n: Int, portrait: DpSize, turned: DpSize) {
        val name = "Scroll filler $n"
        val store = StudyStore(folder.newFolder()).also { it.loadExamples() }
        store.addSet(StudySet(name = "Renal drill", subject = "Nephrology", kind = StudySetKind.MCQ,
            questions = List(12) { i -> MCQQuestion(stem = "Drill question ${i + 1}?", options = listOf("One", "Two", "Three", "Four"), correctIndex = i % 4) }))
        store.addSets(List(40) { i -> StudySet(id = "filler-${i + 1}", name = "Scroll filler ${i + 1}", subject = "Nephrology", kind = StudySetKind.MCQ,
            questions = listOf(MCQQuestion(stem = "Filler ${i + 1}?", options = listOf("One", "Two"), correctIndex = 0))) })
        var size by mutableStateOf(portrait)
        val restoration = StateRestorationTester(compose)
        restoration.setContent { Box(Modifier.requiredSize(size)) { StethoscoreApp(store, forceDark = false) } }
        compose.waitForIdle()
        assertTrue("home opens on its header", exists(hasContentDescription("Account and settings")))

        compose.onNode(hasScrollToNodeAction()).performScrollToKey("set-filler-$n")
        compose.waitForIdle()
        assertTrue("home's list scrolled past its header", !exists(hasContentDescription("Account and settings")))
        assertTrue("$name is composed at $portrait", exists(hasText(name)))
        assertTrue("$name is the list's first row at $portrait", isFirstRow(name))
        val placed = place()

        for (next in listOf(turned, portrait, turned)) {
            size = next
            restoration.emulateSavedInstanceStateRestore()
            compose.waitForIdle()
            assertTrue("$name is composed after the turn to $next", exists(hasText(name)))
            assertTrue("home's list kept its place after the turn to $next", !exists(hasContentDescription("Account and settings")))
            assertEquals("the list's place after the turn to $next", placed, place(), 0f)
            assertTrue("$name is still the list's first row after the turn to $next", isFirstRow(name))
        }
    }

    /** The device test's own row, on the small profile. */
    @Test fun smallPhoneKeepsSet20OnTop() = turnsKeepTheRowOnTop(20, phone, phoneTurned)

    /** The same on tablet7, which the device test passed. */
    @Test fun tablet7KeepsSet20OnTop() = turnsKeepTheRowOnTop(20, tablet7, tablet7Turned)

    /** A row the walk of performScrollToNode leaves below the turned phone's window (397 dp down, a 360 dp window). */
    @Test fun smallPhoneKeepsSet22OnTop() = turnsKeepTheRowOnTop(22, phone, phoneTurned)

    /** And on tablet7: set 29 is left 647 dp down by that walk, a 600 dp window. */
    @Test fun tablet7KeepsSet29OnTop() = turnsKeepTheRowOnTop(29, tablet7, tablet7Turned)
}
