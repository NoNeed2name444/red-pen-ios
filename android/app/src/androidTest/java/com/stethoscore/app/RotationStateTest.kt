package com.stethoscore.app

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelected
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToKey
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
        // MainActivity opens ProcessStore's one store, made on the process's first call only: forgotten here,
        // the activity opens a store loaded from the files just seeded (it waits for their writes), not the one
        // an earlier test left in this process
        ProcessStore.forget()
        scenario = ActivityScenario.launch(MainActivity::class.java)
        instrumentation.runOnMainSync { LearnRouter.close() }
        compose.waitForIdle()
    }

    @After fun tearDown() {
        runCatching { device.setOrientationNatural(); device.unfreezeRotation() }
        foldStates().firstOrNull()?.let { runCatching { device.executeShellCommand("cmd device_state state reset") } }
        // forgotten after the activity is gone: its onStop still reaches for the process store
        try { scenario.close() } finally { ProcessStore.forget() }
    }

    /** The device states to pass through after the turns: none unless the script found a foldable's. */
    private fun foldStates(): List<String> =
        InstrumentationRegistry.getArguments().getString("foldStates").orEmpty().split(',').map { it.trim() }.filter { it.isNotEmpty() }

    private fun exists(matcher: SemanticsMatcher) = compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()

    private fun waitFor(what: String, matcher: SemanticsMatcher) {
        try { compose.waitUntil(20_000) { exists(matcher) } } catch (e: androidx.compose.ui.test.ComposeTimeoutException) { throw AssertionError("no $what; lists at ${listsAt()}", e) }
    }

    /**
     * Where each scrolling list stands, for the failure message and the ROT-DIAG lines: its scroll value over its
     * largest, read as a lazy list gives it (500 for each row above the first visible one, then the pixels
     * scrolled into that row), and the lowest and highest "Scroll filler" rows composed, where home has them.
     */
    private fun listsAt(): String = try {
        val lists = compose.onAllNodes(hasScrollToNodeAction()).fetchSemanticsNodes().joinToString(" ") { node ->
            node.config.getOrElseNullable(SemanticsProperties.VerticalScrollAxisRange) { null }?.let {
                val row = (it.value() / 500).toInt()
                "${it.value()}/${it.maxValue()} (row $row, ${(it.value() - row * 500).toInt()} px in)"
            } ?: "-"
        }.ifEmpty { "none" }
        val fillers = compose.onAllNodes(hasText("Scroll filler ", substring = true)).fetchSemanticsNodes()
            .mapNotNull { Regex("""Scroll filler (\d+)""").find(it.config[SemanticsProperties.Text].joinToString())?.groupValues?.get(1)?.toInt() }
        lists + if (fillers.isEmpty()) "" else "; fillers composed ${fillers.min()}..${fillers.max()}"
    } catch (e: Exception) { "unread (${e.javaClass.simpleName})" }

    /** Whether the matched row is the list's first: its top lies less than its own height below the list's top. */
    private fun isFirstRow(row: SemanticsMatcher, list: SemanticsMatcher): Boolean {
        val bounds = compose.onAllNodes(row).onFirst().getUnclippedBoundsInRoot()
        return bounds.top - compose.onNode(list).getUnclippedBoundsInRoot().top < bounds.bottom - bounds.top
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
            RotDiag.snapshot("RotationStateTest after $name; lists at ${listsAt()}")
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
        // the process store the first launch made never saw the fillers (they went to this test's own store and the
        // file): forgotten, the relaunch opens a store loaded from the file that has them
        ProcessStore.forget()
        scenario = ActivityScenario.launch(MainActivity::class.java)
        instrumentation.runOnMainSync { LearnRouter.close() }
        compose.waitForIdle()
        // the app's own store holds the row, so a store made before the fillers fails here and not as a scroll-search error
        assertTrue("the app's own store lacks 'Scroll filler 20': the process store was made before the fillers were saved (a stale ProcessStore), so home's list can never show the row",
            ProcessStore.get(instrumentation.targetContext).library.any { it.name == "Scroll filler 20" })
        val list = hasScrollToNodeAction()
        // A row from the middle of the list, not its last line (T0245), put at the top of the list by its key
        // (T0250). A turn keeps the list's first row and its offset, so the row put at the top stays the top
        // row in every window. performScrollToNode does not put it there: it walks the list a window's
        // height at a time and leaves the row wherever it first showed, a few rows down a tall window. In a
        // short one (the small profile turned, 640 x 360 dp) that row lies below the window and is not
        // composed: "no home after left" with the list still at the row it was on. The last line ("Study aid",
        // the footer) failed the same way on the tablets (T0245).
        val anchor = hasText("Scroll filler 20")
        val anchorKey = "set-" + store.library.first { it.name == "Scroll filler 20" }.id
        waitFor("home's list", hasContentDescription("Account and settings"))
        compose.onNode(list).performScrollToKey(anchorKey)
        compose.waitForIdle()
        assertTrue("home's list scrolled past its header", !exists(hasContentDescription("Account and settings")))
        assertTrue("'Scroll filler 20' is the list's first row before the turns; lists at ${listsAt()}", isFirstRow(anchor, list))
        turnAndCheck { step ->
            waitFor("home after $step", anchor)
            // the row is on the screen, still where the list was put, and the list is not back at its top
            compose.onAllNodes(anchor).onFirst().assertIsDisplayed()
            assertTrue("home's list kept its place after $step", !exists(hasContentDescription("Account and settings")))
            assertTrue("'Scroll filler 20' is still the list's first row after $step; lists at ${listsAt()}", isFirstRow(anchor, list))
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
