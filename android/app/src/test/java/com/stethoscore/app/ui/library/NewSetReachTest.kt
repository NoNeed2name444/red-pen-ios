package com.stethoscore.app.ui.library

import android.net.Uri
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.filterToOne
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isEnabled
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.core.app.ActivityOptionsCompat
import com.stethoscore.app.data.CaseJson
import com.stethoscore.app.data.CaseSamples
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.llm.CloudJobs
import com.stethoscore.app.llm.FakeJobs
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.editors.LocalLLMService
import com.stethoscore.app.ui.learn.LearnRouter
import com.stethoscore.app.ui.learn.LearnRouterClosed
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

// T0115b1 A2: each AI mode reached the way the owner reaches it on iOS, from
// home through New set to the mode, and the request arriving at a stand-in
// worker (FakeServer: nothing goes on the network). The service is the owner's
// build's (Stethoscore Cloud chosen, a stand-in key), given through
// LocalLLMService. The jobs' 2.5 s polls pass on the test clock.
//
// The rule runs effects on an UnconfinedTestDispatcher, which never
// dispatches: a coroutine back from withContext(Dispatchers.IO) went on on the
// IO thread, its state writes, the save, New set's close and the Snapshot
// apply that wakes the recomposer beside the test thread's own frames (a
// measure on two threads, a wake lost). Here the job's blocking work runs in
// place (CloudJobs.io): the requests and the lecture read, so all of it runs
// on the test thread inside the clock's advance, as on the main thread in the
// app, and every request is checked to come from that thread.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NewSetReachTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    // the shared rule every test that drives the app wears (open() still closes too)
    @get:Rule val learnClosed = LearnRouterClosed()

    private val seen = CopyOnWriteArrayList<FakeServer.Request>()
    /** The threads the stand-in worker was asked on. */
    private val askedOn = CopyOnWriteArrayList<Thread>()
    private lateinit var ioBefore: CoroutineDispatcher

    @Before fun blockingWorkInPlace() {
        ioBefore = CloudJobs.io
        CloudJobs.io = Dispatchers.Unconfined
    }

    @After fun blockingWorkBack() {
        CloudJobs.io = ioBefore
    }

    private fun owner(jobs: FakeJobs): LLMService = LLMService(
        LLMService.MemoryPrefs().also { it.set(LLMService.CHOICE_KEY, "cloud") }, FakeServer.standInKey(), { null }, FakeServer.BASE,
        FakeServer { askedOn += Thread.currentThread(); seen += it; jobs.answer(it) }, OwnerSpend(OwnerSpend.MemoryStore()))

    /** Every request came on the test's main thread, none from an IO thread. */
    private fun allAskedOnTheMainThread() {
        assertTrue("the worker was asked", askedOn.isNotEmpty())
        assertEquals(setOf(Looper.getMainLooper().thread), askedOn.toSet())
    }

    /** A library with sets in it, so home shows its New set button. */
    private fun library(name: String): StudyStore = StudyStore(folder.newFolder(name)).also { it.loadExamples() }

    private fun open(store: StudyStore, llm: LLMService, picker: ActivityResultRegistry? = null) {
        // The learning sheet is one per app, and every test class shares the JVM: a
        // sheet another class left open would lie over these screens, its Done on Back.
        LearnRouter.close()
        compose.setContent {
            CompositionLocalProvider(LocalLLMService provides llm) {
                if (picker == null) StethoscoreApp(store, forceDark = false)
                else CompositionLocalProvider(LocalActivityResultRegistryOwner provides object : ActivityResultRegistryOwner {
                    override val activityResultRegistry: ActivityResultRegistry = picker
                }) { StethoscoreApp(store, forceDark = false) }
            }
        }
    }

    /** Waits for [done] while the test clock moves on, half a second a look. */
    private fun until(done: () -> Boolean) {
        compose.waitUntil(timeoutMillis = 20_000) {
            if (!done()) compose.mainClock.advanceTimeBy(500)
            done()
        }
    }

    private fun jobSent(): FakeServer.Request {
        until { seen.any { it.method == "POST" && it.path == "/jobs" } }
        return seen.first { it.method == "POST" && it.path == "/jobs" }
    }

    private fun startNewSetFromHome() {
        compose.onNodeWithContentDescription("New set. Make questions or cards from a lecture").performClick()
        compose.onNodeWithText("What do you want to make?").assertExists()
    }

    // Make questions (iOS NewSetView .lecture + .mcq: MCQGenerateForm)

    private val stem = "A 54-year-old diabetic with hypertension needs a first drug; which is best?"

    private fun questions(): String = JSONObject().put("questions", JSONArray().put(JSONObject().put("stem", stem)
        .put("options", JSONArray(listOf("Atenolol tablets", "Amlodipine tablets", "Ramipril tablets", "Indapamide tablets", "Doxazosin tablets")))
        .put("correctIndex", 2).put("explanation", "Key point: ACE inhibitors first."))).toString()

    @Test fun makeQuestionsFromHomeReachesTheWorker() {
        val jobs = FakeJobs(listOf(questions()))
        val store = library("questions")
        val before = store.library.size
        open(store, owner(jobs))
        startNewSetFromHome()
        compose.onNodeWithText("Practice questions (MCQ)").performScrollTo().performClick()
        compose.onNodeWithText("Add your lecture").assertExists()
        // From a lecture file comes first, and is chosen (iOS paths(for: .mcq))
        compose.onNodeWithText("From a lecture file").assertIsSelected()
        compose.onNode(hasSetTextAction() and hasContentDescription("Or paste your notes")).performScrollTo()
            .performTextInput("Hypertension in diabetes: an ACE inhibitor such as ramipril first; check potassium and creatinine after starting.")
        compose.onNodeWithText("Next").performClick()
        compose.onNodeWithText("Make it").assertExists()
        compose.onNodeWithText("Make 8 questions").performScrollTo().performClick()

        val sent = jobSent()
        assertTrue(sent.url.startsWith(FakeServer.BASE))
        assertEquals(FakeServer.standInKey(), sent.bearer)
        assertEquals("Writing 8 questions", sent.body!!.getString("title"))
        assertEquals("questions", sent.body!!.getString("extract"))
        assertTrue("the notes are what it writes from", sent.body!!.getJSONArray("sources").getString(0).contains("ramipril"))

        // the questions open in the quiz, not saved yet (iOS isUnsaved)
        until { compose.onAllNodesWithText(stem, substring = true).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Save").assertExists()
        assertEquals(before, store.library.size)
        // Back on them asks first (iOS Close: "Keep these questions?")
        compose.onNodeWithContentDescription("Back").performClick()
        // the question is a dialog, a window of its own, which can come a frame later
        until { compose.onAllNodesWithText("Keep these questions?").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Save to library").performClick()
        compose.waitForIdle()
        assertEquals(before + 1, store.library.size)
        val made = store.library.single { set -> set.questions.any { it.stem == stem } }
        assertEquals(StudySetKind.MCQ, made.kind)
        compose.onNodeWithText("YOUR STUDY WARD").assertExists()
        allAskedOnTheMainThread()
    }

    // Make patients (iOS NewSetView .lecture + .cases: CaseMakeSection)

    /** The system's file picker, answering at once with [uri]. */
    private class Picker(private val uri: Uri) : ActivityResultRegistry() {
        var launched = 0
        override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>, input: I, options: ActivityOptionsCompat?) {
            launched += 1
            dispatchResult(requestCode, uri)
        }
    }

    /** A Word file of [paragraphs], as OfficeText reads one. */
    private fun docx(name: String, paragraphs: List<String>): File {
        val file = File(folder.newFolder("files"), name)
        ZipOutputStream(file.outputStream()).use { zip ->
            zip.putNextEntry(ZipEntry("word/document.xml"))
            val body = paragraphs.joinToString("") { "<w:p><w:r><w:t>$it</w:t></w:r></w:p>" }
            zip.write("<w:document><w:body>$body</w:body></w:document>".toByteArray())
            zip.closeEntry()
        }
        return file
    }

    private fun caseReply(): String = JSONObject().put("cases", JSONArray().put(CaseJson.write(CaseSamples.breathless))).toString()

    @Test fun makePatientsFromHomeReachesTheWorker() {
        val jobs = FakeJobs(listOf(caseReply(), caseReply(), caseReply()))
        val store = library("cases")
        val lecture = docx("Heart failure.docx", listOf(
            "Heart failure presents with breathlessness on exertion, orthopnoea and paroxysmal nocturnal dyspnoea, with ankle swelling.",
            "Examination finds a raised JVP, bibasal crackles and pitting oedema.",
            "NT-proBNP is raised and the echocardiogram shows a reduced ejection fraction.",
            "Treatment is a loop diuretic for congestion, then an ACE inhibitor, a beta-blocker and an SGLT2 inhibitor.",
        ))
        val picker = Picker(Uri.fromFile(lecture))
        open(store, owner(jobs), picker)
        startNewSetFromHome()
        compose.onNodeWithText("Patient cases").performScrollTo().performClick()
        compose.onNodeWithText("From a lecture file").assertIsSelected()
        compose.onNodeWithText("Choose a lecture").performScrollTo().performClick()
        assertEquals(1, picker.launched)
        until { compose.onAllNodesWithText("Heart failure — 1 pages.").fetchSemanticsNodes().isNotEmpty() }
        // the read is done when its controls are free again (Make is disabled while reading)
        until { compose.onAllNodes(hasText("Choose a different lecture") and isEnabled()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Next").performClick()
        compose.onNodeWithText("How many patients").assertExists()
        compose.onNodeWithText("Make 3 patients").performScrollTo().performClick()

        val sent = jobSent()
        assertTrue(sent.url.startsWith(FakeServer.BASE))
        assertEquals(FakeServer.standInKey(), sent.bearer)
        assertEquals("Writing 3 cases", sent.body!!.getString("title"))
        assertEquals("each", sent.body!!.getString("mode"))

        // written, checked and saved as a set in one go, named for the lecture, which goes with it
        until { store.library.any { it.kind == StudySetKind.CASES && it.name == "Heart failure" } }
        val made = store.library.single { it.kind == StudySetKind.CASES && it.name == "Heart failure" }
        assertTrue(made.caseFiles.isNotEmpty())
        assertEquals("Heart failure", made.sources.single().name)
        // The store is not Compose state: the set is in the library before the
        // frame that closes New set. Wait for home, then look.
        compose.waitForIdle()
        until { compose.onAllNodesWithText("YOUR STUDY WARD").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("YOUR STUDY WARD").assertExists()
        allAskedOnTheMainThread()
    }

    // Paste or import (iOS NewSetView(kind:startingAt: .material))

    @Test fun pasteOrImportOpensOnTheMaterialStepWithTyping() {
        val store = StudyStore(folder.newFolder("paste"))
        compose.setContent { StethoscoreTheme { LibraryNewSetScreen(store, StudySetKind.MCQ, {}, {}, startStep = NewSetStep.MATERIAL) } }
        compose.onNodeWithText("Add your lecture").assertExists()
        // the tile, not the typing section's title of the same words
        compose.onAllNodesWithText("Type or paste").filterToOne(isSelectable()).assertIsSelected()
        compose.onNodeWithText("From a lecture file").assertExists()
    }

    @Test fun thePathsAndWhereNewSetStarts() {
        assertEquals(listOf(NewSetPath.LECTURE, NewSetPath.TYPE, NewSetPath.IMPORT_FILE), NewSetWords.paths(StudySetKind.MCQ))
        assertEquals(listOf(NewSetPath.LECTURE, NewSetPath.IMPORT_FILE), NewSetWords.paths(StudySetKind.CASES))
        assertEquals(listOf(NewSetPath.TYPE, NewSetPath.IMPORT_FILE), NewSetWords.paths(StudySetKind.NARRATE))
        // + New set: the kind's first way in; Paste or import: typing, where the kind has it
        assertEquals(NewSetPath.LECTURE, NewSetWords.startPath(StudySetKind.MCQ, NewSetStep.KIND))
        assertEquals(NewSetPath.TYPE, NewSetWords.startPath(StudySetKind.MCQ, NewSetStep.MATERIAL))
        assertEquals(NewSetPath.LECTURE, NewSetWords.startPath(StudySetKind.CASES, NewSetStep.MATERIAL))
        assertEquals(NewSetPath.TYPE, NewSetWords.startPath(StudySetKind.ANKI, NewSetStep.MATERIAL))
    }

    @Test fun thePasteOrImportTileAsksForTheMaterialStep() {
        val store = StudyStore(folder.newFolder("tile"))
        val asked = mutableListOf<String>()
        fun actions(addMaterial: (() -> Unit)?) = LibraryActions(open = {}, quiz = {}, review = {}, newSet = { asked += "newSet:${it.rawValue}" },
            shelf = {}, stats = {}, due = {}, ideas = {}, exportPdf = {}, shareJson = {}, change = { it() }, addMaterial = addMaterial)
        start(CategoryFeature.ADD, store, LibraryState(), actions { asked += "addMaterial" })
        assertEquals(listOf("addMaterial"), asked)
        asked.clear()
        start(CategoryFeature.ADD, store, LibraryState(), actions(null))
        assertEquals(listOf("newSet:${StudySetKind.MCQ.rawValue}"), asked)
    }
}
