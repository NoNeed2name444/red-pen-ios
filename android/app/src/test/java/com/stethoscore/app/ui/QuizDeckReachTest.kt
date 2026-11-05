package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.ui.ward.WardSection
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// T0211 A2: on the review's phone (run 42028140747, 411 x 914 dp) the How sure? deck covered
// option D of the Nephrology example and Check answer sat below the fold. Back and the main
// action are on the deck now, so Check answer is on screen from the start; at the accessibility
// sizes they stay in the page, under the options, where the deck would cover most of it.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w411dp-h914dp-xxhdpi")
class QuizDeckReachTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private fun show(fontScale: Float) {
        val store = StudyStore(folder.newFolder("s$fontScale")).also { it.loadExamples() }
        val set = store.library.first { it.kind == StudySetKind.MCQ && it.subject == "Nephrology" }
        compose.setContent {
            val d = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(d.density, fontScale)) {
                StethoscoreTheme(false, WardSection.fromKindRaw(StudySetKind.MCQ.rawValue)) {
                    Box(Modifier.fillMaxSize()) {
                        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { QuizScreen(set, store, {}, minReadSeconds = 0) }
                    }
                }
            }
        }
        compose.waitForIdle()
    }

    // before an answer is picked the main action says so; once one is, it is Check answer
    private val pick = ChartQuiz.primaryTitle(false, false, false, false, false)
    private val check = ChartQuiz.primaryTitle(false, true, false, false, false)
    // where a node is laid out, not clipped by the scrolling page (boundsInRoot is empty below its fold)
    private fun bounds(n: SemanticsNode): Rect = Rect(n.positionInRoot, androidx.compose.ui.geometry.Size(n.size.width.toFloat(), n.size.height.toFloat()))
    private fun checkNode(title: String = check) = compose.onAllNodes(hasText(title) and hasClickAction()).fetchSemanticsNodes().single()
    private fun options() = compose.onAllNodes(hasContentDescription("Answer ", substring = true)).fetchSemanticsNodes()
        .filter { n -> n.config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].any { it.startsWith("Answer ") } }

    @Test fun theMainActionIsOnTheDeckAtTheDefaultSize() {
        show(1f)
        val root = compose.onRoot().fetchSemanticsNode().let(::bounds)
        val deckTop = bounds(compose.onAllNodes(hasContentDescription("Hide buttons")).fetchSemanticsNodes().single()).top
        val action = bounds(checkNode(pick))
        val last = options().maxBy { bounds(it).bottom }.let(::bounds)
        println("T0211 A2 default: screen ${root.height}px, deck top $deckTop, ${check} ${action.top}..${action.bottom}, last option ${last.top}..${last.bottom}")
        assertTrue("$check is on screen without scrolling: $action in $root", action.top >= root.top && action.bottom <= root.bottom)
        assertTrue("$check is on the deck: $action, deck from $deckTop", action.top >= deckTop)
        assertTrue("the last option is clear of the deck without scrolling: $last, deck from $deckTop", last.bottom <= deckTop)
        assertTrue("Back is on the deck too", bounds(compose.onAllNodes(hasContentDescription("Previous question")).fetchSemanticsNodes().single()).top >= deckTop)
        // the last option scrolled to stands clear of the deck, and the answer can be checked
        val lastSaid = options().maxBy { bounds(it).bottom }.config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].first()
        compose.onAllNodes(hasContentDescription(lastSaid)).onFirst().performScrollTo().performClick()
        compose.waitForIdle()
        val scrolled = options().maxBy { bounds(it).bottom }.let(::bounds)
        assertTrue("the last option clears the deck once scrolled to: $scrolled, deck from $deckTop", scrolled.bottom <= deckTop + 1)
        val enabled = !checkNode().config.contains(androidx.compose.ui.semantics.SemanticsProperties.Disabled)
        assertTrue("$check is ready once an option is picked", enabled)
    }

    @Test fun theMainActionStaysInThePageAtTheAccessibilitySizes() {
        show(2f)
        val action = checkNode(pick)
        val last = options().maxBy { bounds(it).bottom }.let(::bounds)
        assertTrue("$check is under the options, in the page: ${bounds(action)} after $last", bounds(action).top >= last.bottom)
        compose.onAllNodes(hasText(pick) and hasClickAction()).onFirst().performScrollTo()
    }
}
