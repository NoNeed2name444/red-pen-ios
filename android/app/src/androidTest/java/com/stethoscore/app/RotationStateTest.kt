package com.stethoscore.app

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelected
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.ui.learn.LearnRouter
import com.stethoscore.app.ui.library.NewSetPath
import com.stethoscore.app.ui.library.NewSetWords
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The real app turned on the emulator (T0139): natural, left, right and natural again, and on a
 * foldable folded and unfolded too, each of which recreates MainActivity. After every turn the
 * quiz is still on question 3 with its choice, the mock sitting on its part and question with its
 * choice and its open sheet (the question grid), home's list where it was scrolled with its typed search, and New
 * set's typed draft. The name sheet's typed name is RotationRestoreTest's (Robolectric). The fold steps are the device states the script found on this image
 * (instrumentation argument "foldStates", from `cmd device_state print-states`); none on a phone.
 */
@RunWith(AndroidJUnit4::class)
class RotationStateTest {
    @get:Rule val compose = createEmptyComposeRule()
    @get:Rule val learnClosed = LearnRouterClosed()
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val device get() = UiDevice.getInstance(instrumentation)
    private lateinit var scenario: ActivityScenario<MainActivity>
    private lateinit var store: StudyStore

    @Before fun seed() {
        val context = instrumentation.targetContext
        // the app's own library, as MainActivity opens it: the examples and a mock's worth of questions
        context.filesDir.listFiles()?.forEach { it.deleteRecursively() }
        store = StudyStore(context.filesDir).also { it.loadExamples() }
        store.addSet(StudySet(name = "Renal drill", subject = "Nephrology", kind = StudySetKind.MCQ,
            questions = List(12) { i -> MCQQuestion(stem = "Drill question ${i + 1}?", options = listOf("One", "Two", "Three", "Four"), correctIndex = i % 4) }))
        device.setOrientationNatural()
        scenario = ActivityScenario.launch(MainActivity::class.java)
        instrumentation.runOnMainSync { LearnRouter.close() }
        compose.waitForIdle()
    }

    @After fun tearDown() {
        runCatching { device.setOrientationNatural(); device.unfreezeRotation() }
        foldStates().firstOrNull()?.let { runCatching { device.executeShellCommand("cmd device_state state reset") } }
        scenario.close()
    }

    /** The device states to pass through after the turns: none unless the script found a foldable's. */
    private fun foldStates(): List<String> =
        InstrumentationRegistry.getArguments().getString("foldStates").orEmpty().split(',').map { it.trim() }.filter { it.isNotEmpty() }

    private fun exists(matcher: SemanticsMatcher) = compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()

    private fun waitFor(what: String, matcher: SemanticsMatcher) {
        try { compose.waitUntil(20_000) { exists(matcher) } } catch (e: androidx.compose.ui.test.ComposeTimeoutException) { throw AssertionError("no $what", e) }
    }

    /** Tapped by its click action (a bar's button can lie below the fold of a short landscape window), brought into view first where it scrolls. */
    private fun tap(what: String, matcher: SemanticsMatcher) {
        waitFor(what, matcher)
        val node = compose.onAllNodes(matcher).onFirst()
        try { node.performScrollTo() } catch (_: AssertionError) {}
        node.performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
    }

    /**
     * Natural, left, right, natural, then each fold state and back: after each, [check] runs on
     * the recreated activity. Left and right must be wider than tall where natural is taller.
     */
    private fun turnAndCheck(check: (String) -> Unit) {
        val natural = device.displayWidth to device.displayHeight
        val steps: List<Pair<String, () -> Unit>> = listOf(
            "left" to { device.setOrientationLeft() },
            "right" to { device.setOrientationRight() },
            "natural" to { device.setOrientationNatural() },
        ) + foldStates().map { state -> "device state $state" to { device.executeShellCommand("cmd device_state state $state"); Unit } } +
            (if (foldStates().isEmpty()) emptyList() else listOf("device state reset" to { device.executeShellCommand("cmd device_state state reset"); Unit }))
        for ((name, turn) in steps) {
            turn()
            device.waitForIdle()
            compose.waitForIdle()
            if (name == "left" || name == "right") {
                val turned = device.displayWidth to device.displayHeight
                assertEquals("$name swaps the display's sides", natural.first > natural.second, turned.first < turned.second)
            }
            instrumentation.runOnMainSync { LearnRouter.close() }
            check(name)
        }
    }

    @Test fun quizKeepsQuestionThreeAndItsChoice() {
        val set = store.library.first { it.kind == StudySetKind.MCQ && it.questions.size >= 3 }
        store.clearQuizProgress(set.id)
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText(set.name))
        tap("the set's row", hasText(set.name) and hasClickAction())
        for (q in set.questions.take(2)) {
            tap("the right answer", hasClickAction() and hasContentDescription(": " + q.options[q.correctIndex], substring = true))
            tap("Check answer", hasText(ChartQuiz.primaryTitle(false, true, false, false, false)) and hasClickAction())
            tap("Next question", hasText(ChartQuiz.primaryTitle(true, true, false, false, false)) and hasClickAction())
        }
        val third = set.questions[2]
        val pick = third.options[(third.correctIndex + 1) % third.options.size]
        tap("a choice on question 3", hasClickAction() and hasContentDescription(": $pick", substring = true))
        turnAndCheck { step ->
            waitFor("question 3 after $step", hasText(third.stem.take(40), substring = true))
            assertTrue("question 3's choice after $step", exists(hasContentDescription(": $pick", substring = true) and isSelected()))
        }
    }

    @Test fun mockKeepsPartQuestionChoiceAndSheet() {
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasContentDescription("Mock paper", substring = true))
        tap("the Mock paper tile", hasContentDescription("Mock paper", substring = true) and hasClickAction())
        tap("Start mock", hasText("Start mock") and hasClickAction())
        tap("answer A", hasClickAction() and hasContentDescription("Answer A:", substring = true))
        tap("Next", hasText("Next") and hasClickAction())
        tap("answer B", hasClickAction() and hasContentDescription("Answer B:", substring = true))
        // the question grid, a sheet, open over it
        tap("Review", hasText("Review") and hasClickAction())
        turnAndCheck { step ->
            waitFor("the sitting's question 2 after $step", hasText("Question 2 of", substring = true))
            assertTrue("the grid sheet still open after $step", exists(hasText("Done") and hasClickAction()))
        }
        tap("the sheet's Done", hasText("Done") and hasClickAction())
        assertTrue("question 2's choice kept", exists(hasContentDescription("Answer B:", substring = true) and isSelected()))
        // "Part n", never "Block", where the paper has parts
        assertTrue("no Block in the sitting", !exists(hasText("Block", substring = true)))
    }

    @Test fun homeKeepsItsScrollAndTypedSearch() {
        // enough sets that home's list runs well past any window's height, the app opened on them
        scenario.close()
        store.addSets(List(40) { i -> StudySet(name = "Scroll filler ${i + 1}", subject = "Nephrology", kind = StudySetKind.MCQ,
            questions = listOf(MCQQuestion(stem = "Filler ${i + 1}?", options = listOf("One", "Two"), correctIndex = 0))) })
        scenario = ActivityScenario.launch(MainActivity::class.java)
        instrumentation.runOnMainSync { LearnRouter.close() }
        compose.waitForIdle()
        val list = hasScrollToNodeAction()
        waitFor("home's list", hasContentDescription("Account and settings"))
        compose.onNode(list).performScrollToNode(hasText("Study aid", substring = true))
        compose.waitForIdle()
        assertTrue("home's list scrolled past its header", !exists(hasContentDescription("Account and settings")))
        turnAndCheck { step ->
            waitFor("home after $step", hasText("Study aid", substring = true))
            // the list is not back at its top
            assertTrue("home's list kept its place after $step", !exists(hasContentDescription("Account and settings")))
        }
        compose.onNode(list).performScrollToNode(hasContentDescription("Search"))
        compose.onAllNodes(hasSetTextAction() and hasContentDescription("Search")).onFirst().performTextInput("nephr")
        compose.waitForIdle()
        turnAndCheck { step -> assertTrue("the typed search after $step", exists(hasSetTextAction() and hasText("nephr", substring = true))) }
    }

    @Test fun newSetKeepsItsDraft() {
        tap("New set", hasContentDescription("New set.", substring = true) and hasClickAction())
        tap("the questions kind", hasText(NewSetWords.plainName(StudySetKind.MCQ)) and hasClickAction())
        tap("Type or paste", hasText(NewSetPath.TYPE.title) and hasClickAction())
        val draft = hasSetTextAction() and hasContentDescription(NewSetPath.TYPE.title)
        waitFor("the draft field", draft)
        compose.onAllNodes(draft).onFirst().performTextInput("Which nerve? | Ulnar; Median; Radial | B | Thenar wasting.")
        compose.waitForIdle()
        turnAndCheck { step -> assertTrue("the draft after $step", exists(draft and hasText("Which nerve?", substring = true))) }
    }

}
