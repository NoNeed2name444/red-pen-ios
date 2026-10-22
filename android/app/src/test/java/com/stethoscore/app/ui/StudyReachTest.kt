package com.stethoscore.app.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performScrollToNode
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.OsceChecklist
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.exam.NewSetPreset
import com.stethoscore.app.exam.WardCalc
import com.stethoscore.app.llm.FakeJobs
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.quiz.ConfidenceSetting
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.book.BookReaderScreen
import com.stethoscore.app.ui.coverage.CoverageScreen
import com.stethoscore.app.ui.editors.LocalLLMService
import com.stethoscore.app.ui.learn.LearnRouter
import com.stethoscore.app.ui.learn.LearnRouterClosed
import com.stethoscore.app.ui.library.LibraryNewSetScreen
import com.stethoscore.app.ui.osce.OsceReviewScreen
import com.stethoscore.app.network.BackendClient
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.CopyOnWriteArrayList

// T0115b2 A2: what iOS reaches that Android could not, tapped from the screen
// to the result with a stand-in worker (FakeServer: nothing goes on the
// network). Check accuracy in the More menu of the quiz, card review, due
// today, OSCE review and the book (iOS studyMoreMenu, then AccuracyWhySheet
// with checksWhenUnchecked); New set from a preset, on Make with the question
// writer, from Coverage's Generate questions, the exam card's Study next and
// the Ward pocket's Practise this (iOS NewSetView(preset:)); and the dock's
// floating copy of Make (iOS FloatingAction).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class StudyReachTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private val seen = CopyOnWriteArrayList<FakeServer.Request>()

    /** The worker: the accuracy check votes once on every item sent; jobs are [jobs]'s. */
    private fun worker(request: FakeServer.Request, jobs: FakeJobs?): BackendClient.Reply {
        if (request.method == "POST" && request.path == "/accuracy/check") {
            val items = request.body!!.getJSONArray("items")
            val out = JSONArray()
            for (i in 0 until items.length()) out.put(JSONObject().put("id", items.getJSONObject(i).getString("id"))
                .put("votes", JSONArray().put(JSONObject().put("model", "stand-in-checker").put("risk", 1).put("evidence", "supports")
                    .put("issues", JSONArray().put("Nothing wrong found.")))))
            return FakeServer.ok(JSONObject().put("items", out))
        }
        return jobs?.answer(request) ?: BackendClient.Reply(404, "{}")
    }

    /** The owner's build's service (Stethoscore Cloud chosen, a stand-in key) on the stand-in worker. */
    private fun owner(jobs: FakeJobs? = null): LLMService = LLMService(
        LLMService.MemoryPrefs().also { it.set(LLMService.CHOICE_KEY, "cloud") }, FakeServer.standInKey(), { null }, FakeServer.BASE,
        FakeServer { seen += it; worker(it, jobs) }, OwnerSpend(OwnerSpend.MemoryStore()))

    private fun store(name: String): StudyStore = StudyStore(folder.newFolder(name))

    private fun show(llm: LLMService, content: @androidx.compose.runtime.Composable () -> Unit) {
        LearnRouter.close()
        compose.setContent { CompositionLocalProvider(LocalLLMService provides llm) { StethoscoreTheme { content() } } }
    }

    private fun until(done: () -> Boolean) {
        compose.waitUntil(timeoutMillis = 20_000) {
            if (!done()) compose.mainClock.advanceTimeBy(500)
            done()
        }
    }

    private fun sent(path: String): FakeServer.Request {
        until { seen.any { it.method == "POST" && it.path == path } }
        return seen.first { it.method == "POST" && it.path == path }
    }

    /** More, Check accuracy, then the sheet checks the item at once and shows the checkers' vote. */
    private fun checkAccuracy(kind: String): JSONObject {
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithTag("checkAccuracy").performClick()
        until { compose.onAllNodesWithText("Accuracy").fetchSemanticsNodes().isNotEmpty() }
        val item = sent("/accuracy/check").body!!.getJSONArray("items").getJSONObject(0)
        assertEquals(kind, item.getString("kind"))
        until { compose.onAllNodesWithText("stand-in-checker").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("CHECKER MODELS").assertExists()
        compose.onNodeWithText("No error").assertExists()
        compose.onNodeWithText("Nothing wrong found.").assertExists()
        // nothing is Verified without an official source's proof
        compose.onNodeWithText("Check this").assertExists()
        compose.onAllNodesWithText("Done").onLast().performClick()
        compose.waitForIdle()
        assertTrue(compose.onAllNodesWithText("CHECKER MODELS").fetchSemanticsNodes().isEmpty())
        return item
    }

    private val stem = "A 54-year-old diabetic with hypertension needs a first drug; which is best?"
    private val options = listOf("Atenolol tablets", "Amlodipine tablets", "Ramipril tablets", "Indapamide tablets", "Doxazosin tablets")

    // 1. Check accuracy

    @org.junit.Before fun forget() { AccuracySeen.records.clear() }

    @Test fun theQuizChecksTheAnsweredQuestion() {
        ApplicationProvider.getApplicationContext<Context>().getSharedPreferences("appearance", Context.MODE_PRIVATE)
            .edit().putBoolean(ConfidenceSetting.key, false).commit()
        val store = store("quiz")
        val set = StudySet(name = "Hypertension", subject = "Cardiology", kind = StudySetKind.MCQ,
            questions = listOf(MCQQuestion(stem = stem, options = options, correctIndex = 2, explanation = "ACE inhibitors first in diabetes.")))
        store.addSet(set)
        show(owner()) { QuizScreen(set, store, onBack = {}) }
        // before an answer, Check accuracy shows nothing: the check would give the answer away
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithTag("checkAccuracy").performClick()
        compose.waitForIdle()
        assertTrue(compose.onAllNodesWithText("CHECKER MODELS").fetchSemanticsNodes().isEmpty())
        assertTrue(seen.isEmpty())
        compose.onNode(hasContentDescription("Ramipril tablets", substring = true)).performClick()
        compose.onNodeWithText("Check answer").performScrollTo().performClick()
        val item = checkAccuracy("mcq")
        assertEquals(stem, item.getString("stem"))
        assertEquals(2, item.getInt("key"))
    }

    private fun deck(store: StudyStore): StudySet {
        val set = StudySet(name = "Lupus", subject = "Rheumatology", kind = StudySetKind.ANKI, cards = listOf(
            AnkiCard(front = "Rash across the cheeks in lupus?", bullets = listOf("Malar rash"), why = "Spares the nasolabial folds")))
        store.addSet(set)
        return set
    }

    @Test fun theCardReviewChecksTheCard() {
        val store = store("cards")
        val set = deck(store)
        show(owner()) { AnkiReviewScreen(set, store, onBack = {}) }
        val item = checkAccuracy("card")
        assertEquals(set.cards.single().id, item.getString("id"))
        assertTrue(item.getString("text").contains("Malar rash"))
    }

    @Test fun dueTodayChecksTheCardDue() {
        val store = store("due")
        val set = deck(store)
        show(owner()) { DueTodayScreen(store, onBack = {}) }
        val item = checkAccuracy("card")
        assertEquals(set.cards.single().id, item.getString("id"))
    }

    @Test fun theOsceReviewChecksTheStation() {
        val store = store("osce")
        val set = StudySet(name = "Exams", subject = "Clinical skills", kind = StudySetKind.OSCE, osceChecklists = listOf(
            OsceChecklist(title = "Cardiovascular examination", steps = listOf("Wash hands and introduce yourself", "Inspect from the end of the bed", "Feel the radial pulse"))))
        store.addSet(set)
        show(owner()) { OsceReviewScreen(set, store, onBack = {}) }
        val item = checkAccuracy("fact")
        assertTrue(item.getString("text").startsWith("Cardiovascular examination\n- Wash hands"))
    }

    @Test fun theBookChecksThePage() {
        val store = store("book")
        val set = StudySet(name = "Renal", subject = "Nephrology", kind = StudySetKind.BOOK,
            bookMarkdown = "# Acute kidney injury\n\nA rise in creatinine of 26 umol/L within 48 hours defines acute kidney injury.")
        store.addSet(set)
        show(owner()) { BookReaderScreen(set, store, onBack = {}) }
        val item = checkAccuracy("fact")
        assertTrue(item.getString("text").startsWith("Acute kidney injury\n"))
    }

    // 2. New set from a preset, on Make with the question writer

    private fun questions(): String = JSONObject().put("questions", JSONArray().put(JSONObject().put("stem", stem)
        .put("options", JSONArray(options)).put("correctIndex", 2).put("explanation", "Key point: ACE inhibitors first."))).toString()

    /** Make on the preset's New set reaches the writer with the preset's notes as its material. */
    private fun makeReachesTheWriter(material: String) {
        compose.onAllNodesWithText("Make 8 questions").onFirst().performScrollTo().performClick()
        val job = sent("/jobs").body!!
        assertEquals("questions", job.getString("extract"))
        assertTrue("the preset is what it writes from", job.getJSONArray("sources").getString(0).contains(material))
        until { compose.onAllNodesWithText(stem, substring = true).fetchSemanticsNodes().isNotEmpty() }
    }

    @Test fun coveragesGenerateQuestionsOpensTheWriter() {
        val store = store("coverage")
        show(owner(FakeJobs(listOf(questions())))) {
            var preset by remember { mutableStateOf<NewSetPreset?>(null) }
            // the app's route "new" with a preset (StethoscoreApp)
            preset?.let { LibraryNewSetScreen(store, it.kind, {}, {}, preset = it) } ?: CoverageScreen(store, {}) { preset = it }
        }
        until { compose.onAllNodesWithText("Generate questions").fetchSemanticsNodes().isNotEmpty() }
        compose.onAllNodesWithText("Generate questions").onFirst().performScrollTo().performClick()
        makeReachesTheWriter("Write exam questions on ")
    }

    @Test fun theExamCardsStudyNextOpensTheWriter() {
        ApplicationProvider.getApplicationContext<Context>().getSharedPreferences("appearance", Context.MODE_PRIVATE)
            .edit().putString(ExamTrack.storageKey, ExamTrack.plab.rawValue).commit()
        val store = StudyStore(folder.newFolder("exam")).also { it.loadExamples() }
        LearnRouter.close()
        compose.setContent { CompositionLocalProvider(LocalLLMService provides owner(FakeJobs(listOf(questions())))) { StethoscoreApp(store, forceDark = false) } }
        // the card stands on home's Questions page
        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollToIndex)).performScrollToNode(hasTestTag("examDashboard"))
        val studyNext = SemanticsMatcher("Study next's row") {
            it.config.getOrElseNullable(SemanticsActions.OnClick) { null }?.label?.startsWith("Makes a question set on it") == true
        }
        until { compose.onAllNodes(studyNext).fetchSemanticsNodes().isNotEmpty() }
        // home's New set button and dock float over the list's foot, where a row scrolled to can stand
        compose.onAllNodes(studyNext).onFirst().performScrollTo().performSemanticsAction(SemanticsActions.OnClick)
        makeReachesTheWriter("Write PLAB 1 (UKMLA) questions on ")
    }

    @Test fun theWardPocketsPractiseThisOpensTheWriter() {
        val store = store("pocket")
        val set = StudySet(name = "Hypertension", subject = "Cardiology", kind = StudySetKind.MCQ,
            questions = listOf(MCQQuestion(stem = stem, options = options, correctIndex = 2)))
        store.addSet(set)
        show(owner(FakeJobs(listOf(questions())))) { QuizScreen(set, store, onBack = {}) }
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithTag("wardPocket").performClick()
        compose.onNodeWithText(WardCalc.anionGap.title).performScrollTo().performClick()
        compose.onNode(hasContentDescription("Practise this", substring = true)).performScrollTo().performClick()
        makeReachesTheWriter(WardCalc.anionGap.title)
    }

    // 4. The dock's floating copy of Make

    @Config(qualifiers = "w360dp-h360dp")
    @Test fun theDockFloatsMakeWhileItIsScrolledAway() {
        val store = store("floating")
        val preset = NewSetPreset(StudySetKind.MCQ, "Ramipril", "Cardiology", "Ramipril is an ACE inhibitor, first for hypertension in diabetes; check potassium.")
        show(owner(FakeJobs(listOf(questions())))) { LibraryNewSetScreen(store, preset.kind, {}, {}, preset = preset) }
        // the real Make is below the fold, so its copy is in the dock
        until { compose.onAllNodesWithTag("floatingAction").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("floatingAction").performClick()
        val job = sent("/jobs").body!!
        assertEquals("Writing 8 questions", job.getString("title"))
        assertTrue(job.getJSONArray("sources").getString(0).contains("ACE inhibitor"))
    }

    @Config(qualifiers = "w360dp-h360dp")
    @Test fun theCopyGoesWhenTheRealMakeIsInSight() {
        val store = store("insight")
        val preset = NewSetPreset(StudySetKind.MCQ, "Ramipril", "Cardiology", "Ramipril is an ACE inhibitor.")
        show(owner()) { LibraryNewSetScreen(store, preset.kind, {}, {}, preset = preset) }
        until { compose.onAllNodesWithTag("floatingAction").fetchSemanticsNodes().isNotEmpty() }
        compose.onAllNodesWithText("Make 8 questions").onFirst().performScrollTo()
        until { compose.onAllNodesWithTag("floatingAction").fetchSemanticsNodes().isEmpty() }
    }
}
