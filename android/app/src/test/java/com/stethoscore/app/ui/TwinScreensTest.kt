package com.stethoscore.app.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.quiz.ConfidenceSetting
import com.stethoscore.app.quiz.TwinBook
import com.stethoscore.app.quiz.TwinSets
import com.stethoscore.app.quiz.TwinWriter
import com.stethoscore.app.ui.editors.LocalLLMService
import com.stethoscore.app.ui.learn.LearnRouter
import com.stethoscore.app.ui.learn.LearnRouterClosed
import com.stethoscore.app.ui.library.CategoryFeature
import com.stethoscore.app.ui.library.LibraryAlert
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.CopyOnWriteArrayList

// Write a twin on screen (T0133): a question missed in the quiz, Write a twin
// tapped, the stand-in worker (FakeServer: nothing goes on the network)
// writes the twin, and the quiz says when it comes back; with no writer set
// up it says so; and the Twins tile's Nothing here yet, light and dark, closed
// with Done. The steps behind these are quiz/TwinFlowTest.kt.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TwinScreensTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private val seen = CopyOnWriteArrayList<FakeServer.Request>()

    private val stem = "A 54-year-old diabetic with hypertension needs a first drug; which is best?"
    private val options = listOf("Atenolol tablets", "Amlodipine tablets", "Ramipril tablets", "Indapamide tablets", "Doxazosin tablets")
    private val twinStem = "A 61-year-old woman with type 2 diabetes and protein in her urine has a raised blood pressure at two visits. Which drug should she start?"

    /** The stand-in worker: writes a twin for the question it is sent. */
    private fun worker(request: FakeServer.Request): BackendClient.Reply {
        if (request.method == "POST" && request.path == "/v1/chat/completions" && request.body.toString().contains("twin")) {
            val twin = JSONObject().put("questions", JSONArray().put(JSONObject().put("stem", twinStem)
                .put("options", JSONArray(listOf("Lisinopril", "Bisoprolol", "Nifedipine", "Bendroflumethiazide", "Doxazosin")))
                .put("correctIndex", 0).put("explanation", "An ACE inhibitor protects the kidney in diabetes.")))
            return FakeServer.chat(twin.toString())
        }
        return BackendClient.Reply(404, "{}")
    }

    private fun service(choice: String): LLMService = LLMService(
        LLMService.MemoryPrefs().also { it.set(LLMService.CHOICE_KEY, choice) }, FakeServer.standInKey(), { null }, FakeServer.BASE,
        FakeServer { seen += it; worker(it) }, OwnerSpend(OwnerSpend.MemoryStore()))

    @Before fun noConfidenceAsked() {
        ApplicationProvider.getApplicationContext<Context>().getSharedPreferences("appearance", Context.MODE_PRIVATE)
            .edit().putBoolean(ConfidenceSetting.key, false).commit()
    }

    private fun until(done: () -> Boolean) {
        compose.waitUntil(timeoutMillis = 20_000) {
            if (!done()) compose.mainClock.advanceTimeBy(500)
            done()
        }
    }

    private fun shows(text: String) = compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    /** Which sitting of the quiz is on screen; a new one starts it afresh. */
    private var sitting by mutableStateOf(0)

    private fun missAgain() {
        compose.onNode(hasContentDescription("Atenolol tablets", substring = true)).performScrollTo().performClick()
        compose.onNodeWithText("Check answer").performScrollTo().performClick()
        compose.waitForIdle()
    }

    /** A quiz of one question, missed: Atenolol chosen, Ramipril right. */
    private fun missed(llm: LLMService): Pair<StudyStore, StudySet> {
        val store = StudyStore(folder.newFolder("quiz"))
        val set = StudySet(name = "Hypertension", subject = "Cardiology", kind = StudySetKind.MCQ,
            questions = listOf(MCQQuestion(stem = stem, options = options, correctIndex = 2, explanation = "ACE inhibitors first in diabetes.")))
        store.addSet(set)
        LearnRouter.close()
        compose.setContent {
            CompositionLocalProvider(LocalLLMService provides llm) { StethoscoreTheme { androidx.compose.runtime.key(sitting) { QuizScreen(set, store, onBack = {}, keepsProgress = false) } } }
        }
        missAgain()
        return store to set
    }

    /** The chip sits in a row that scrolls sideways, past the test window's edge: tapped as TalkBack would. */
    private fun tapWriteATwin() {
        compose.onNodeWithText("Write a twin").performScrollTo()
        compose.onNode(hasText("Write a twin") and hasClickAction()).performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
    }

    @Test fun s2MissWriteATwinTheStandInWritesIt() {
        val (store, set) = missed(service("cloud"))
        tapWriteATwin()
        until { shows(TwinWriter.noWriter) || shows("Twin written. It comes back in 2 days, under Questions → Twins.") }
        compose.onNodeWithText("Twin written. It comes back in 2 days, under Questions → Twins.").assertExists()
        // the chip goes once the twin is asked for: one twin per miss
        assertTrue(compose.onAllNodesWithText("Write a twin").fetchSemanticsNodes().isEmpty())
        val asked = seen.single { it.path == "/v1/chat/completions" }.body.toString()
        assertTrue("the worker is told the missed stem and the choice", asked.contains(stem) && asked.contains("The student chose: Atenolol tablets"))
        assertTrue("the twin is on the way", store.twinShelf.isOnTheWay(set.questions[0].id))
        assertEquals("and kept in its subject's Twins set", listOf(twinStem),
            store.library.single { it.name == "Twins · Cardiology" }.questions.map { it.stem })
        // after a relaunch it waits; two days on it is in the Twins quiz
        val reopened = StudyStore(java.io.File(folder.root, "quiz"))
        val due = store.twinShelf.book.queue.entries.single().dueAt
        assertTrue(TwinSets.quiz(reopened, due - 1).questions.isEmpty())
        assertEquals(listOf(twinStem), TwinSets.quiz(reopened, due).questions.map { it.stem })
    }

    @Test fun s2OneTwinPerMissOnScreen() {
        val llm = service("cloud")
        val (store, set) = missed(llm)
        tapWriteATwin()
        until { shows("Twin written. It comes back in 2 days, under Questions → Twins.") }
        // the same question missed again in a later sitting
        compose.runOnUiThread { sitting += 1 }
        compose.waitForIdle()
        missAgain()
        tapWriteATwin()
        until { shows(TwinBook.alreadyOnTheWay) }
        assertEquals("the worker was asked once", 1, seen.count { it.path == "/v1/chat/completions" })
        assertEquals("one twin", 1, store.library.single { it.name == "Twins · Cardiology" }.questions.size)
    }

    @Test fun s6TheTwinAnsweredInTheQuizMovesOn() {
        val store = StudyStore(folder.newFolder("due"))
        val twin = MCQQuestion(stem = twinStem, options = listOf("Lisinopril", "Bisoprolol", "Nifedipine", "Bendroflumethiazide", "Doxazosin"),
            correctIndex = 0, explanation = "An ACE inhibitor protects the kidney in diabetes.")
        TwinSets.add(store, twin, "Cardiology", 0)
        store.twinShelf.addTwin(twin.id, "parent", confident = false, guessed = false, now = 0)
        val quiz = TwinSets.quiz(store)
        assertEquals(listOf(twinStem), quiz.questions.map { it.stem })
        LearnRouter.close()
        compose.setContent { CompositionLocalProvider(LocalLLMService provides service("off")) { StethoscoreTheme { QuizScreen(quiz, store, onBack = {}, keepsProgress = false) } } }
        compose.onNode(hasContentDescription("Lisinopril", substring = true)).performScrollTo().performClick()
        compose.onNodeWithText("Check answer").performScrollTo().performClick()
        compose.waitForIdle()
        assertTrue("answered right in the Twins quiz, the twin leaves the queue", store.twinShelf.book.queue.waiting.isEmpty())
        assertEquals(true, store.twinShelf.book.queue.entries.single().answeredCorrectly)
    }

    @Test fun s2NoWriterSetUpSaysSo() {
        val (store, set) = missed(service("off"))
        tapWriteATwin()
        until { shows(TwinWriter.noWriter) }
        assertTrue("nothing is sent", seen.isEmpty())
        assertTrue("and nothing waits", !store.twinShelf.isOnTheWay(set.questions[0].id))
    }

    private fun nothingYet(dark: Boolean) {
        var open by mutableStateOf(true)
        compose.setContent {
            StethoscoreTheme(dark = dark) {
                if (open) LibraryAlert("Nothing here yet", CategoryFeature.TWINS.emptyText) { open = false }
            }
        }
        compose.onNodeWithText("Nothing here yet").assertExists()
        compose.onNodeWithText(TwinBook.nothingYet).assertExists()
        compose.onNodeWithText("Done").performClick()
        compose.waitForIdle()
        assertTrue("Done closes it", !open && !shows("Nothing here yet"))
    }

    @Test fun s5NothingYetLightThenDone() = nothingYet(dark = false)

    @Test fun s5NothingYetDarkThenDone() = nothingYet(dark = true)
}
