package com.stethoscore.app.ui.vitals

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.RuleWriter
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.editors.LocalLLMService
import com.stethoscore.app.ui.ward.LocalWardReduceMotion
import com.stethoscore.app.ui.ward.LocalWindowShape
import com.stethoscore.app.ui.ward.WindowShape
import org.junit.After
import org.junit.Before
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// T0236: "Write N rules with AI" on the Android rule sheet (iOS
// RuleSheetView's Write with AI and RuleWritingProgress), tapped from the
// screen to the store with a stand-in worker (FakeServer: nothing goes on the
// network). Only where Android already allows a model call is the button
// offered; while the model writes the buttons give way to the progress; a run
// that brings nothing back leaves the plain rules and says so; and the button,
// the progress and the note are each at least one 48 dp target tall, with
// their words spoken. The run belongs to the process (RuleWriting): a sheet
// re-created mid-run (a rotation or a fold recreates the activity) shows the
// same run, not the buttons, and nothing is sent twice; a save that fails
// stops the run, and the next tap can start another.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RuleSheetWriteTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val seen = CopyOnWriteArrayList<FakeServer.Request>()
    /** While set, the worker waits for it before it answers, so the busy state can be looked at. */
    @Volatile private var hold: CountDownLatch? = null
    @Volatile private var chat: () -> BackendClient.Reply = {
        FakeServer.chat("{\"rules\": [\"Thenar wasting → median nerve\", \"Ptosis + miosis → Horner syndrome\"]}")
    }

    // the run belongs to the process, so nothing of one test may reach the next
    @Before fun clean() { RuleWriting.forget() }

    @After fun release() {
        hold?.countDown()
        if (RuleWriting.running) until { !RuleWriting.running }
        RuleWriting.forget()
    }

    private val first = MCQQuestion(stem = "A hand shows thenar wasting. Which nerve is compressed?", options = listOf("Ulnar", "Median"),
        correctIndex = 1, explanation = "The median nerve runs under the flexor retinaculum. Wrist splints help.")
    private val second = MCQQuestion(stem = "A drooping lid and a small pupil: which syndrome?", options = listOf("Horner", "Adie"),
        correctIndex = 0, explanation = "")

    /** Two plain rules on the sheet, the first the newer. */
    private fun storeWithRules(): StudyStore {
        val store = StudyStore(folder.newFolder())
        store.addRules(listOf(RuleWriter.plainRule(first, "Anatomy").copy(date = 2_000L), RuleWriter.plainRule(second, "Neurology").copy(date = 1_000L)))
        return store
    }

    private fun plainText(q: MCQQuestion) = RuleWriter.plainRule(q, "x").text

    /** The owner's build's service on the stand-in worker; an empty [key] is a public build, without Pro. */
    private fun service(key: String = FakeServer.standInKey(), spend: OwnerSpend = OwnerSpend(OwnerSpend.MemoryStore())): LLMService =
        LLMService(key, { null }, FakeServer.BASE, FakeServer { request ->
            seen += request
            hold?.await(20, TimeUnit.SECONDS)
            chat()
        }, spend)

    private fun show(llm: LLMService, store: StudyStore) {
        compose.setContent {
            CompositionLocalProvider(LocalLLMService provides llm) { StethoscoreTheme { RuleSheetScreen(store, onBack = {}) } }
        }
        compose.waitForIdle()
    }

    private fun until(done: () -> Boolean) {
        compose.waitUntil(timeoutMillis = 20_000) {
            if (!done()) compose.mainClock.advanceTimeBy(500)
            done()
        }
    }

    private fun shown(text: String): Boolean = compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    private fun assertAtLeastOneTarget(what: String, nodeHeight: androidx.compose.ui.unit.Dp) =
        assertTrue("$what is ${nodeHeight.value} dp tall, under 48", nodeHeight >= 48.dp)

    private val hint = "Rewrites each plain rule as one exam-style line, ten at a time"

    // ---- gating: only where a model call is already allowed

    @Test fun withNoModelOnlyThePlainRulesAreOffered() {
        show(service(key = ""), storeWithRules())
        assertTrue("the plain rules are shown", shown(plainText(first)) && shown(plainText(second)))
        assertTrue("no write button without Pro", !shown("Write 2 rules with AI"))
        assertTrue("nothing was sent", seen.isEmpty())
    }

    @Test fun onceTheSpendCapIsReachedTheButtonGoesToo() {
        show(service(spend = OwnerSpend(OwnerSpend.MemoryStore(), capMicros = 0)), storeWithRules())
        assertTrue("the plain rules are shown", shown(plainText(first)))
        assertTrue("no write button at the cap", !shown("Write 2 rules with AI"))
        assertTrue("nothing was sent", seen.isEmpty())
    }

    @Test fun withNothingPlainThereIsNothingToWrite() {
        val store = storeWithRules()
        store.applyWrittenRules(mapOf(first.id to "Already written", second.id to "Also written"))
        show(service(), store)
        assertTrue(!shown("Write 0 rules with AI") && !shown("Write 2 rules with AI"))
    }

    // ---- the write, its busy state, its result

    @Test fun theButtonWritesTheRulesThroughTheStore() {
        val store = storeWithRules()
        hold = CountDownLatch(1)
        show(service(), store)

        val button = compose.onNodeWithText("Write 2 rules with AI")
        button.assertExists()
        assertAtLeastOneTarget("the write button", button.getUnclippedBoundsInRoot().height)
        button.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, hint))
        button.performClick()

        // busy: the buttons give way to the progress, spoken as one
        until { compose.onAllNodesWithTag("ruleWritingProgress").fetchSemanticsNodes().isNotEmpty() }
        val busy = compose.onNodeWithTag("ruleWritingProgress")
        busy.assertContentDescriptionEquals("Writing rules with AI, 0 of 2. Ten at a time. You can keep using the app while it works.")
        assertAtLeastOneTarget("the progress", busy.getUnclippedBoundsInRoot().height)
        assertTrue("the write button is gone while it works", !shown("Write 2 rules with AI"))
        until { seen.any { it.path == "/v1/chat/completions" } }
        assertEquals("the plain rules are still there while the model works", plainText(first), store.ruleSheet.getValue(first.id).text)

        hold!!.countDown()
        until { shown("Rewrote 2 of 2 rules.") }
        val written = store.ruleSheet
        assertEquals("Thenar wasting → median nerve", written.getValue(first.id).text)
        assertEquals("Ptosis + miosis → Horner syndrome", written.getValue(second.id).text)
        assertTrue("both marked as written with AI", written.values.all { it.byAI })
        assertEquals(2, compose.onAllNodesWithText("Written with AI").fetchSemanticsNodes().size)
        assertTrue("the progress is gone", compose.onAllNodesWithTag("ruleWritingProgress").fetchSemanticsNodes().isEmpty())
        assertTrue("nothing plain is left to write", !shown("Write 2 rules with AI") && !shown("Write 0 rules with AI"))

        val sent = seen.single { it.path == "/v1/chat/completions" }
        assertEquals(FakeServer.standInKey(), sent.bearer)
        val content = sent.body!!.getJSONArray("messages").getJSONObject(0).getString("content")
        assertTrue("newest first, numbered", content.contains("Question 1: " + first.stem) && content.contains("Question 2: " + second.stem))
        val note = compose.onNodeWithTag("ruleSheetNote")
        assertAtLeastOneTarget("the note", note.getUnclippedBoundsInRoot().height)
        note.assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
    }

    private fun assertAFailureLeavesThePlainRules(store: StudyStore) {
        show(service(), store)
        compose.onNodeWithText("Write 2 rules with AI").performClick()
        val says = "The model did not answer in a usable way; your rules are unchanged. Try again later."
        until { shown(says) }
        assertEquals(says, WRITE_FAILED)
        val kept = store.ruleSheet
        assertEquals(plainText(first), kept.getValue(first.id).text)
        assertEquals(plainText(second), kept.getValue(second.id).text)
        assertTrue("still plain, not marked written", kept.values.none { it.byAI })
        assertTrue("no written chip", !shown("Written with AI"))
        val note = compose.onNodeWithTag("ruleSheetNote")
        assertAtLeastOneTarget("the error", note.getUnclippedBoundsInRoot().height)
        note.assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
        assertTrue("the button is back, to try again", shown("Write 2 rules with AI"))
        assertTrue("the progress is gone", compose.onAllNodesWithTag("ruleWritingProgress").fetchSemanticsNodes().isEmpty())
    }

    @Test fun aReplyThatIsNotTheJsonLeavesThePlainRulesAndSaysSo() {
        chat = { FakeServer.chat("Sorry, I can't help with that.") }
        assertAFailureLeavesThePlainRules(storeWithRules())
    }

    @Test fun aWorkerThatRefusesLeavesThePlainRulesAndSaysSo() {
        chat = { BackendClient.Reply(500, "boom") }
        assertAFailureLeavesThePlainRules(storeWithRules())
    }

    // ---- a recreated sheet, and a save that fails

    private val chatPath = "/v1/chat/completions"

    @Test fun aRecreatedSheetKeepsTheRunAndDoesNotStartASecond() {
        val store = storeWithRules()
        hold = CountDownLatch(1)
        val llm = service()
        // StateRestorationTester saves and restores as a recreated activity does: a new sheet with
        // none of the old one's remember state. The ECG loop is off, so the test can wait for idle.
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            CompositionLocalProvider(LocalWardReduceMotion provides true, LocalLLMService provides llm) {
                StethoscoreTheme { RuleSheetScreen(store, onBack = {}) }
            }
        }
        compose.waitForIdle()
        compose.onNodeWithText("Write 2 rules with AI").performClick()
        until { seen.any { it.path == chatPath } && compose.onAllNodesWithTag("ruleWritingProgress").fetchSemanticsNodes().isNotEmpty() }

        restoration.emulateSavedInstanceStateRestore()
        compose.waitForIdle()

        assertTrue("the new sheet shows the run", compose.onAllNodesWithTag("ruleWritingProgress").fetchSemanticsNodes().isNotEmpty())
        compose.onNodeWithTag("ruleWritingProgress")
            .assertContentDescriptionEquals("Writing rules with AI, 0 of 2. Ten at a time. You can keep using the app while it works.")
        assertTrue("and not the write button", !shown("Write 2 rules with AI"))
        assertEquals("one request, not two", 1, seen.count { it.path == chatPath })

        hold!!.countDown()
        until { shown("Rewrote 2 of 2 rules.") }
        assertEquals("still one request", 1, seen.count { it.path == chatPath })
        assertTrue("the new sheet filled in as the batch landed", compose.onAllNodesWithText("Written with AI").fetchSemanticsNodes().size == 2)
        assertEquals("Thenar wasting → median nerve", store.ruleSheet.getValue(first.id).text)
        assertTrue("the run is over", !RuleWriting.running)
    }

    @Test fun aSaveThatFailsStopsTheRunWithTheFailureNoteAndANewTapStartsAgain() {
        val store = storeWithRules()
        store.beforeRename = { throw IOException("disk full") }
        show(service(), store)
        compose.onNodeWithText("Write 2 rules with AI").performClick()
        until { shown(WRITE_FAILED) }

        assertTrue("the run is over, not stuck", !RuleWriting.running)
        assertEquals(plainText(first), store.ruleSheet.getValue(first.id).text)
        assertEquals(plainText(second), store.ruleSheet.getValue(second.id).text)
        assertTrue("the plain rules are as they were", store.ruleSheet.values.none { it.byAI })
        assertTrue("no written chip", !shown("Written with AI"))
        assertTrue("the button is back", shown("Write 2 rules with AI"))

        store.beforeRename = null
        compose.onNodeWithText("Write 2 rules with AI").performClick()
        until { shown("Rewrote 2 of 2 rules.") }
        assertTrue("the second run wrote them", store.ruleSheet.values.all { it.byAI })
        assertEquals("one request for each run", 2, seen.count { it.path == chatPath })
    }

    @Test fun aSaveThatFailsAfterABatchKeepsWhatWasWritten() {
        val store = StudyStore(folder.newFolder())
        val questions = (1..12).map { MCQQuestion(stem = "Stem $it: which one?", options = listOf("a", "b"), correctIndex = 1, explanation = "") }
        store.addRules(questions.mapIndexed { i, q -> RuleWriter.plainRule(q, "Anatomy").copy(date = 10_000L - i) })
        chat = { FakeServer.chat("{\"rules\": [" + (1..10).joinToString(", ") { "\"Rule $it\"" } + "]}") }
        var saves = 0
        store.beforeRename = { if (++saves == 2) throw IOException("disk full") }
        show(service(), store)
        compose.onNodeWithText("Write 12 rules with AI").performClick()
        until { shown("Rewrote 10 of 12 rules.") }

        assertEquals("ten written, two left plain", 10, store.ruleSheet.values.count { it.byAI })
        assertEquals(2, store.ruleSheet.values.count { !it.byAI })
        assertTrue("the run is over, not stuck", !RuleWriting.running)
        assertTrue("two plain rules are still offered", shown("Write 2 rules with AI"))
    }

    // ---- the slab's layout

    private fun buttons(width: Double) {
        compose.setContent {
            StethoscoreTheme {
                CompositionLocalProvider(LocalWindowShape provides WindowShape(width, 800.0)) {
                    RuleSheetButtons(missed = 2, plain = 3, onAdd = {}, onWrite = {})
                }
            }
        }
        compose.waitForIdle()
    }

    @Test fun onAPhoneTheTwoButtonsStackWriteFirst() {
        buttons(400.0)
        val write = compose.onNodeWithText("Write 3 rules with AI").getUnclippedBoundsInRoot()
        val add = compose.onNodeWithText("Add 2 from your recent mistakes").getUnclippedBoundsInRoot()
        assertTrue("write above add (${write.bottom} <= ${add.top})", write.bottom <= add.top)
        assertAtLeastOneTarget("write", write.height)
        assertAtLeastOneTarget("add", add.height)
    }

    @Test fun whenWideTheTwoButtonsStandSideBySideWithTheAddButtonAtTheEnd() {
        buttons(900.0)
        val write = compose.onNodeWithText("Write 3 rules with AI").getUnclippedBoundsInRoot()
        val add = compose.onNodeWithText("Add 2 from your recent mistakes").getUnclippedBoundsInRoot()
        assertTrue("write before add (${write.right} <= ${add.left})", write.right <= add.left)
        assertEquals("level with each other", write.top, add.top)
    }
}
