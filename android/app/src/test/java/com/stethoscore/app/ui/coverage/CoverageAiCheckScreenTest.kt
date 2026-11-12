package com.stethoscore.app.ui.coverage

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.coverage.CoverageCloudCheck
import com.stethoscore.app.coverage.Syllabus
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.llm.CloudJobs
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.editors.LocalLLMService
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
import kotlin.coroutines.CoroutineContext

// The Syllabus screen's AI check, as the student meets it (iOS CoverageView's
// aiSection and its slab control): it runs the engine against a stand-in
// worker (FakeServer: nothing goes on the network), shows the check running,
// its result, its failure, and says why it cannot run where no model is
// allowed. The gate is LLMService's own: Pro (the personal build), a bearer
// and the owner key's $20 cap.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CoverageAiCheckScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val seen = CopyOnWriteArrayList<FakeServer.Request>()
    private val areas = Syllabus.areas(ExamTrack.general)
    private val preferred = "gemini-3.1-pro-preview"

    private val signIn = "Sign in to have Stethoscore Cloud check this too. Until then the keyword check below is all there is."
    private val pro = "The AI check uses Stethoscore Cloud, which is part of Pro. The keyword check below still works."
    private val hint = "The keyword check below is instant. Check with AI reads what your matching items actually say."

    private lateinit var ioBefore: CoroutineDispatcher

    // The rule's effects never dispatch, so the blocking requests run in place on the test thread
    // (CloudJobs.io), as in StudyReachTest; the running state is held with [Parked] instead.
    @Before fun setUp() {
        ioBefore = CloudJobs.io
        CloudJobs.io = Dispatchers.Unconfined
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("appearance", Context.MODE_PRIVATE).edit().putString(ExamTrack.storageKey, ExamTrack.general.rawValue).commit()
        File(context.filesDir, "Coverage").deleteRecursively()
    }

    @After fun tearDown() { CloudJobs.io = ioBefore }

    /** A dispatcher that keeps what it is given until the test runs it: a request stays in flight. */
    private class Parked : CoroutineDispatcher() {
        private val queue = ArrayDeque<Runnable>()
        override fun dispatch(context: CoroutineContext, block: Runnable) { synchronized(queue) { queue.addLast(block) } }
        val waiting: Int get() = synchronized(queue) { queue.size }
        fun runAll() {
            while (true) (synchronized(queue) { queue.removeFirstOrNull() } ?: break).run()
        }
        /** Lets the oldest waiting request go, and only that one. */
        fun runOne() {
            (synchronized(queue) { queue.removeFirstOrNull() } ?: return).run()
        }
    }

    // the worker and the builds

    private fun areaOf(request: FakeServer.Request): String {
        val prompt = request.body!!.getJSONArray("messages").getJSONObject(0).getString("content")
        return Regex("area \"(.*)\"\\.").find(prompt.lineSequence().first())!!.groupValues[1]
    }

    /** A check's reply for the area asked about: the first subtopic covered, the second thin, the rest missing. */
    private fun verdicts(request: FakeServer.Request, source: String = preferred): BackendClient.Reply {
        val area = areaOf(request)
        val list = JSONArray()
        for (n in 1..40) list.put(JSONObject().put("id", "s$n").put("status", when (n) { 1 -> "covered"; 2 -> "thin"; else -> "missing" })
            .put("evidence", "Seen in $area").put("suggestion", "Add cards on $area"))
        val content = JSONObject().put("subtopics", list).toString()
        return FakeServer.ok(JSONObject().put("source", source)
            .put("choices", JSONArray().put(JSONObject().put("message", JSONObject().put("content", content)))))
    }

    private fun worker(answer: (FakeServer.Request) -> BackendClient.Reply = { verdicts(it) }) = FakeServer { seen += it; answer(it) }

    /** The owner's personal build: a stand-in key, Pro's cloud, the $20 cap. */
    private fun owner(server: FakeServer = worker(), spend: OwnerSpend = OwnerSpend(OwnerSpend.MemoryStore())) =
        LLMService(FakeServer.standInKey(), { null }, FakeServer.BASE, server, spend)

    /** A public build: no owner key, so never Pro; with or without a saved session. */
    private fun publicBuild(session: String?) = LLMService("", { session }, FakeServer.BASE, worker(), OwnerSpend(OwnerSpend.MemoryStore()))

    private fun show(llm: LLMService) {
        val store = StudyStore(folder.newFolder())
        compose.setContent { CompositionLocalProvider(LocalLLMService provides llm) { StethoscoreTheme { CoverageScreen(store, {}) } } }
        until { compose.onAllNodesWithText("Gaps only").fetchSemanticsNodes().isNotEmpty() }
    }

    private fun until(done: () -> Boolean) {
        compose.waitUntil(timeoutMillis = 20_000) {
            if (!done()) compose.mainClock.advanceTimeBy(500)
            done()
        }
    }

    /** The checks kept on the device, by file name. */
    private fun kept(): List<String> =
        File(ApplicationProvider.getApplicationContext<Context>().filesDir, "Coverage").listFiles().orEmpty()
            .map { it.name }.filter { it.startsWith("check-") }

    private fun there(text: String) = compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
    private fun thereContaining(text: String) = compose.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty()

    /** A control's own bounds are 48 dp each way (the target Android asks for), and it can be clicked. */
    private fun SemanticsNodeInteraction.assertTarget(name: String) {
        assertHasClickAction()
        val own = getUnclippedBoundsInRoot()
        assertTrue("$name is 48 dp wide: ${own.width}", own.width >= 48.dp)
        assertTrue("$name is 48 dp tall: ${own.height}", own.height >= 48.dp)
    }

    // where no model is allowed

    @Test fun withNoSignInTheSectionSaysSoAndOffersNoCheck() {
        show(publicBuild(null))
        assertTrue(there(signIn))
        assertTrue(!there("Check with AI"))
        assertTrue("the hint is for when the check can run", !there(hint))
    }

    @Test fun signedInWithoutProTheSectionSaysTheCheckIsPartOfPro() {
        show(publicBuild("s".repeat(40)))
        assertTrue(there(pro))
        assertTrue(!there(signIn))
        assertTrue(!there("Check with AI"))
        assertTrue("nothing was asked of the worker", seen.isEmpty())
    }

    @Test fun theOwnersBuildPastItsCapIsToldSoAndCannotCheck() {
        show(owner(spend = OwnerSpend(OwnerSpend.MemoryStore(OwnerSpend.CAP_MICROS))))
        assertTrue(there(OwnerSpend.CAP_REACHED))
        assertTrue(!there("Check with AI"))
    }

    // where one is

    @Test fun whereAModelIsAllowedTheSectionOffersTheCheckWithItsHint() {
        show(owner())
        assertTrue(there(hint))
        assertTrue(!there(signIn) && !there(pro))
        compose.onNodeWithText("Check with AI").assertTarget("Check with AI")
        // the keyword check below still stands: the rows say what the keywords found, none is the AI's yet
        assertTrue(thereContaining("Nothing in your library mentions it"))
        assertTrue(!thereContaining("Seen in"))
    }

    @Test fun theRunShowsItsProgressWithAStopThatIsATargetAndIsNamed() {
        val parked = Parked()
        CloudJobs.io = parked
        show(owner())
        compose.onNodeWithText("Check with AI").performClick()
        val busy = "Checking 0 of ${areas.size} areas…"
        until { there(busy) }
        // said as it changes, so a screen reader hears each area finish
        compose.onNode(hasText(busy)).assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
        compose.onNode(hasContentDescription("Stop the AI check")).assertTarget("Stop")
        compose.onNodeWithText("Stop").assertExists()
        assertTrue("the check cannot be started twice", !there("Check with AI") && !there("Check again"))
        // three requests at a time (iOS CoverageChecker.parallel), none sent until the test lets them go
        assertEquals(3, parked.waiting)
        assertTrue(seen.isEmpty())

        // one answer in, and the count says so (the real number of areas, not a stand-in); the next request takes its place
        parked.runOne()
        until { there("Checking 1 of ${areas.size} areas…") }
        assertEquals(1, seen.size)
        assertEquals("a finished request makes room for the next", 3, parked.waiting)

        parked.runAll()
        until { thereContaining("Checked by") }
        assertEquals("one request for each area", areas.size, seen.size)
        assertTrue(!there(busy) && !thereContaining("Checking "))
    }

    @Test fun stopEndsTheRunAndKeepsNothing() {
        val parked = Parked()
        CloudJobs.io = parked
        show(owner())
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checking 0 of") }
        compose.onNode(hasContentDescription("Stop the AI check")).performClick()
        until { there("Check with AI") }
        assertTrue(!thereContaining("Checking "))
        // what was still waiting goes nowhere
        parked.runAll()
        compose.waitForIdle()
        assertTrue("nothing was sent after Stop", seen.isEmpty())
        assertTrue(!thereContaining("Checked by"))
        assertTrue(there(hint))
    }

    @Test fun stopWhileARequestIsBeingAnsweredKeepsNothing() {
        val parked = Parked()
        CloudJobs.io = parked
        var tapped = false
        // Stop is tapped from inside the worker, so the request has begun and its answer is still on the way
        show(owner(worker {
            if (!tapped) {
                tapped = true
                compose.onNode(hasContentDescription("Stop the AI check")).performClick()
            }
            verdicts(it)
        }))
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checking 0 of") }
        parked.runOne()
        assertTrue("the request had begun", tapped)
        until { there("Check with AI") }
        assertTrue(!thereContaining("Checking "))
        // the other requests, still waiting, go nowhere; the answer that was on its way is dropped
        parked.runAll()
        compose.waitForIdle()
        assertEquals("only the request that had begun reached the worker", 1, seen.size)
        assertTrue(!thereContaining("Checked by") && !thereContaining("Seen in"))
        assertTrue("nothing was kept: ${kept()}", kept().isEmpty())
        assertTrue(there(hint))
    }

    @Test fun leavingTheScreenWithRequestsWaitingSendsNothingAndKeepsNothing() {
        val parked = Parked()
        CloudJobs.io = parked
        val spend = OwnerSpend(OwnerSpend.MemoryStore())
        val llm = owner(spend = spend)
        val store = StudyStore(folder.newFolder())
        var open by mutableStateOf(true)
        compose.setContent { CompositionLocalProvider(LocalLLMService provides llm) { StethoscoreTheme { if (open) CoverageScreen(store, {}) } } }
        until { there("Check with AI") }
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checking 0 of") }
        assertEquals(3, parked.waiting)

        compose.runOnIdle { open = false }
        compose.waitForIdle()
        assertTrue(!there("Gaps only"))
        parked.runAll()
        compose.waitForIdle()
        assertTrue("nothing was sent after the screen was left", seen.isEmpty())
        assertEquals("nothing was counted against the cap", 0L, spend.spentMicros)
        assertTrue("nothing was kept: ${kept()}", kept().isEmpty())
    }

    @Test fun aRunForAServiceThatIsReplacedStopsWithIt() {
        // the screen stays; the service it was given is swapped, so the checker built on the old one goes. Its run goes too.
        val parked = Parked()
        CloudJobs.io = parked
        val spend = OwnerSpend(OwnerSpend.MemoryStore())
        var llm by mutableStateOf(owner(spend = spend))
        val store = StudyStore(folder.newFolder())
        compose.setContent { CompositionLocalProvider(LocalLLMService provides llm) { StethoscoreTheme { CoverageScreen(store, {}) } } }
        until { there("Check with AI") }
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checking 0 of") }
        assertEquals(3, parked.waiting)

        compose.runOnIdle { llm = owner() }
        until { there("Check with AI") }
        assertTrue(!thereContaining("Checking "))
        parked.runAll()
        compose.waitForIdle()
        assertTrue("the old run sent nothing: ${seen.size}", seen.isEmpty())
        assertEquals("and counted nothing", 0L, spend.spentMicros)
        assertTrue("and kept nothing: ${kept()}", kept().isEmpty())
    }

    @Test fun aFinishedCheckSaysWhoMadeItAndMarksEachRow() {
        val server = worker()
        show(owner(server))
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checked by Gemini 3.1 Pro") }
        // the button now offers another go; the hint and the failure line are gone
        assertTrue(there("Check again") && !there("Check with AI") && !there(hint))
        assertTrue(!thereContaining("could not be checked this time"))
        // what the AI read, what to add, and where it disagrees with the keywords (iOS row, :391-407)
        val first = areas.first().name
        assertTrue(thereContaining("Seen in $first"))
        assertTrue(thereContaining("Add cards on $first"))
        assertTrue(there("Keywords said not covered"))
        // every request was the writer's route, with the preferred model asked for, on the owner key
        assertTrue(seen.all { it.path == "/v1/chat/completions" && it.bearer == FakeServer.standInKey() })
        assertTrue(seen.all { it.body!!.getString("prefer") == preferred && it.body!!.getString("model") == "cramdown-writer" })
        compose.onNodeWithText("Check again").assertTarget("Check again")
    }

    @Test fun aCheckMadeJustNowSaysNowNotZeroSeconds() {
        show(owner())
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checked by") }
        assertTrue(there("Checked by Gemini 3.1 Pro \u00B7 now"))
        assertTrue(!thereContaining("seconds ago"))
    }

    @Test fun aCheckIsNowForAMinuteThenTheRelativeTime() {
        val then = 1_700_000_000_000L
        assertEquals("now", CoverageWords.checkedWhen(then, then))
        assertEquals("now", CoverageWords.checkedWhen(then, then + 59_999))
        assertEquals("1 minute ago", CoverageWords.checkedWhen(then, then + 60_000))
        assertEquals("5 minutes ago", CoverageWords.checkedWhen(then, then + 5 * 60_000))
        assertEquals("2 hours ago", CoverageWords.checkedWhen(then, then + 2 * 3_600_000))
    }

    // when two models answered, the one that answered more areas is named, and is first in the kept check
    @Test fun theModelThatAnsweredMostAreasIsTheOneNamed() {
        val few = areas.first().name
        show(owner(worker { verdicts(it, if (areaOf(it) == few) "model-few" else "model-many") }))
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checked by") }
        assertTrue(thereContaining("Checked by model-many"))
        assertTrue(!thereContaining("Checked by model-few"))
        // most areas first (CoverageChecker.kt: sources ranked by how many areas each answered; iOS CoverageChecker.swift:109)
        val check = CoverageCloudCheck.load(File(ApplicationProvider.getApplicationContext<Context>().filesDir, "Coverage"), ExamTrack.general)
        assertEquals(listOf("model-many", "model-few"), check?.sources)
    }

    @Test fun aCheckAnotherModelMadeSaysThePreferredOneWasNotThere() {
        show(owner(worker { verdicts(it, "some-other-model") }))
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checked by some-other-model") }
        assertTrue(there("Gemini 3.1 Pro wasn't available, so some-other-model checked it."))
    }

    @Test fun aKeptCheckComesBackWhenTheScreenIsOpenedAgain() {
        val llm = owner()
        val store = StudyStore(folder.newFolder())
        var open by mutableStateOf(true)
        compose.setContent { CompositionLocalProvider(LocalLLMService provides llm) { StethoscoreTheme { if (open) CoverageScreen(store, {}) } } }
        until { there("Check with AI") }
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checked by") }
        val requests = seen.size
        compose.runOnIdle { open = false }
        compose.waitForIdle()
        assertTrue(!there("Gaps only"))
        compose.runOnIdle { open = true }
        until { thereContaining("Checked by") && there("Check again") }
        assertTrue(thereContaining("Seen in ${areas.first().name}"))
        assertEquals("opening it again asks nothing", requests, seen.size)
    }

    // when it goes wrong

    @Test fun anAreaThatFailsIsNamedAndTheRestStand() {
        val first = areas.first().name
        show(owner(worker { if (areaOf(it) == first) BackendClient.Reply(500, "{}") else verdicts(it) }))
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checked by") }
        assertTrue(there("1 area could not be checked this time: $first."))
        assertTrue(!thereContaining("Seen in $first"))
        assertTrue(thereContaining("Seen in ${areas.last().name}"))
    }

    @Test fun anAreaWhoseReplyCannotBeReadIsNamedAndTheRestStand() {
        val first = areas.first().name
        show(owner(worker { if (areaOf(it) == first) FakeServer.chat("I could not do that.") else verdicts(it) }))
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("Checked by") }
        assertTrue(there("1 area could not be checked this time: $first."))
        assertTrue(!thereContaining("Seen in $first"))
        assertTrue(thereContaining("Seen in ${areas.last().name}"))
        val check = CoverageCloudCheck.load(File(ApplicationProvider.getApplicationContext<Context>().filesDir, "Coverage"), ExamTrack.general)
        assertEquals(listOf(first), check?.failedAreas)
    }

    @Test fun whenNothingComesBackTheBannerSaysWhyAndTheKeywordCheckStands() {
        show(owner(worker { BackendClient.Reply(500, "{}") }))
        compose.onNodeWithText("Check with AI").performClick()
        val failure = "The cloud check did not answer."
        until { there(failure) }
        // said when it appears
        compose.onNode(hasText(failure)).assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
        assertTrue(!thereContaining("Checked by") && !thereContaining("Checking "))
        // another go is one tap away, and the rows are still the keyword check's
        assertTrue(there("Check with AI"))
        assertTrue(thereContaining("Nothing in your library mentions it"))
        assertEquals("every area was tried once", areas.size, seen.size)
    }

    @Test fun aReplyWithNoVerdictsInItIsTheGenericFailure() {
        show(owner(worker { FakeServer.chat("I could not do that.") }))
        compose.onNodeWithText("Check with AI").performClick()
        until { there("The cloud check did not come back. The keyword check below still stands.") }
        assertTrue(!thereContaining("Checked by"))
    }

    @Test fun aRefusalIsSaidInTheWorkersWordsOrIosFallback() {
        show(owner(worker { BackendClient.Reply(402, "{}") }))
        compose.onNodeWithText("Check with AI").performClick()
        until { there("The cloud check is part of Pro.") }
    }

    @Test fun theOwnerKeyIsStoppedAtTheCapMidRunAndTheSectionSaysSo() {
        // one reply's worst case takes the build past its cap: the areas still to be asked are not
        val spend = OwnerSpend(OwnerSpend.MemoryStore(OwnerSpend.CAP_MICROS - 1))
        show(owner(worker(), spend))
        compose.onNodeWithText("Check with AI").performClick()
        until { thereContaining("could not be checked this time") }
        assertTrue("the cap held the rest back: ${seen.size} of ${areas.size}", seen.size in 1 until areas.size)
        assertTrue(spend.capReached)
        // the section now says why there is no button
        until { there(OwnerSpend.CAP_REACHED) }
        assertTrue(!there("Check again") && !there("Check with AI"))
    }
}
