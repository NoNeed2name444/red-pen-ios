package com.stethoscore.app.ui.editors

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.onFirst
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.StateRestorationTester
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.exam.NewSetPreset
import com.stethoscore.app.llm.CloudEndpoint
import com.stethoscore.app.llm.CloudJobRules
import com.stethoscore.app.llm.CloudJobs
import com.stethoscore.app.llm.FakeJobs
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.learn.LearnRouter
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.ui.library.LibraryNewSetScreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Before
import org.junit.rules.TemporaryFolder
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ActivityController
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

// GenerationCenter and its card as iOS's Shared/GenerationCenter.swift has
// them: one job at a time, late reports ignored, Cancel the one way to stop,
// closing a screen stopping only its own job, and the card's words.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GenerationCenterTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @get:Rule val folder = TemporaryFolder()

    private lateinit var ioBefore: kotlinx.coroutines.CoroutineDispatcher
    @Before fun blockingWorkInPlace() { ioBefore = CloudJobs.io; CloudJobs.io = kotlinx.coroutines.Dispatchers.Unconfined }
    @After fun clear() { GenerationCenter.cancel(); CloudJobs.io = ioBefore }

    @Test fun oneJobAtATimeAndTheRunningOneIsNotStopped() {
        var stopped = 0
        val first = GenerationCenter.begin("Writing 40 questions", 40) { stopped++ }
        assertNotNull(first)
        assertNull("a second is refused", GenerationCenter.begin("Writing 3 cases", 3) { stopped++ })
        assertEquals(0, stopped)
        assertEquals("Writing 40 questions", GenerationCenter.job?.title)
        assertTrue(GenerationCenter.busy!!.startsWith("Still writing 40 questions"))
    }

    @Test fun aLateReportCannotBringTheCardBack() {
        val id = GenerationCenter.begin("Writing 8 questions", 8) {}!!
        GenerationCenter.update(id, 3, 8)
        assertEquals(3, GenerationCenter.job?.done)
        GenerationCenter.end(id)
        GenerationCenter.update(id, 4, 8)
        assertNull(GenerationCenter.job)
        assertNull(GenerationCenter.busy)
        // and ending another job's id changes nothing
        val next = GenerationCenter.begin("Writing 8 questions", 8) {}!!
        GenerationCenter.end(UUID.randomUUID())
        assertEquals(next, GenerationCenter.job?.id)
    }

    @Test fun cancelStopsTheWorkAndClosingStopsOnlyItsOwn() {
        var stopped = 0
        val mine = UUID.randomUUID()
        GenerationCenter.begin("Writing 8 questions", 8, owner = mine) { stopped++ }
        GenerationCenter.cancel(startedBy = UUID.randomUUID())
        assertNotNull("another screen closing leaves it", GenerationCenter.job)
        GenerationCenter.cancel(startedBy = mine)
        assertNull(GenerationCenter.job)
        assertEquals(1, stopped)
        GenerationCenter.cancel()
        assertEquals("nothing left to stop", 1, stopped)
    }

    // T0237: begin(keeping = delivery) as iOS's begin(_:total:owner:keeping:onCancel:)

    private val handOver = CloudJobRules.StopFate.handOver
    private val delete = CloudJobRules.StopFate.delete

    @Test fun aRunTheSystemStoppedTellsItsDeliveryAndStops() {
        val delivery = CloudJobs.Delivery()
        var stopped = 0
        val id = GenerationCenter.begin("Writing 8 cards", 8, keeping = delivery) { stopped++ }!!
        assertEquals("nobody has stopped it yet", CloudJobRules.Stop.student, delivery.stoppedBy)
        GenerationCenter.stopAtExpiry(appActive = true)
        assertEquals(CloudJobRules.Stop.system, delivery.stoppedBy)
        assertEquals(handOver, CloudJobRules.afterStop(delivery.stoppedBy))
        assertEquals("the work was stopped, once", 1, stopped)
        assertNull(GenerationCenter.job)
        // a late report cannot bring the card back
        GenerationCenter.update(id, 5, 8)
        assertNull(GenerationCenter.job)
        assertFalse(GenerationCenter.end(id))
    }

    @Test fun anExpiryWhileAwayIsTakenForTheStudentsOwnStop() {
        val delivery = CloudJobs.Delivery()
        var stopped = 0
        GenerationCenter.begin("Writing 8 cards", 8, keeping = delivery) { stopped++ }
        GenerationCenter.stopAtExpiry(appActive = false)
        assertEquals(CloudJobRules.Stop.student, delivery.stoppedBy)
        assertEquals(delete, CloudJobRules.afterStop(delivery.stoppedBy))
        assertEquals(1, stopped)
        assertNull(GenerationCenter.job)
    }

    @Test fun aFinishedOrCancelledRunKeepsNoDeliveryForAnExpiryToTouch() {
        val finished = CloudJobs.Delivery()
        val id = GenerationCenter.begin("Writing 8 cards", 8, keeping = finished) {}!!
        assertTrue(GenerationCenter.end(id))
        val cancelled = CloudJobs.Delivery()
        GenerationCenter.begin("Writing 8 cards", 8, keeping = cancelled) {}
        GenerationCenter.cancel()
        val closed = CloudJobs.Delivery()
        val screen = UUID.randomUUID()
        GenerationCenter.begin("Writing 8 cards", 8, owner = screen, keeping = closed) {}
        GenerationCenter.cancel(startedBy = screen)
        // an expiry with nothing running changes nothing
        GenerationCenter.stopAtExpiry(appActive = true)
        // and one for the next run touches only the next run's delivery
        val next = CloudJobs.Delivery()
        GenerationCenter.begin("Writing 8 cards", 8, keeping = next) {}
        GenerationCenter.stopAtExpiry(appActive = true)
        for (old in listOf(finished, cancelled, closed)) assertEquals(CloudJobRules.Stop.student, old.stoppedBy)
        assertEquals(CloudJobRules.Stop.system, next.stoppedBy)
    }

    @Test fun aRefusedRunLeavesTheRunningOnesDeliveryAlone() {
        val running = CloudJobs.Delivery()
        val refused = CloudJobs.Delivery()
        var stopped = 0
        GenerationCenter.begin("Writing 40 questions", 40, keeping = running) { stopped++ }
        assertNull(GenerationCenter.begin("Writing 3 cases", 3, keeping = refused) { stopped++ })
        GenerationCenter.stopAtExpiry(appActive = true)
        assertEquals(CloudJobRules.Stop.system, running.stoppedBy)
        assertEquals("the one refused was never begun", CloudJobRules.Stop.student, refused.stoppedBy)
        assertEquals(1, stopped)
    }

    @Test fun aRunWithNoDeliveryStillStopsAtExpiry() {
        var stopped = 0
        GenerationCenter.begin("Writing 8 questions", 8) { stopped++ }
        GenerationCenter.stopAtExpiry(appActive = true)
        assertEquals(1, stopped)
        assertNull(GenerationCenter.job)
    }

    // the whole of it: the work reads who stopped it as it ends, and the cloud job goes the way that says

    /** A job id of the shape the client accepts (BackendClient.jobId): a cancel for any other is never sent. */
    private val jobId = "0f8fad5b-d9cb-469f-a165-70867728950e"

    private fun running(): FakeServer = FakeServer { request ->
        when {
            request.method == "POST" && request.path == "/jobs" ->
                FakeServer.ok(JSONObject().put("job", JSONObject().put("id", jobId).put("status", "queued")))
            request.method == "GET" && request.path == "/jobs/$jobId" ->
                FakeServer.ok(JSONObject().put("job", JSONObject().put("id", jobId).put("status", "running").put("done", 0).put("total", 2)))
            request.method == "DELETE" -> FakeServer.ok(JSONObject().put("ok", true))
            else -> BackendClient.Reply(404, "{}")
        }
    }

    /** A cloud job under [delivery] that is still writing, begun on the card, stopped by [stop]; its record and the server afterwards. */
    private fun stoppedRun(delivery: CloudJobs.Delivery, stop: () -> Unit): Pair<CloudJobs.MemoryStore, FakeServer> = runBlocking {
        val server = running()
        val store = CloudJobs.MemoryStore()
        val at = CloudEndpoint(server.client("bearer"), "owner", null)
        val spec = CloudJobs.Spec("Writing 2 questions", "loop", "questions", 2, listOf("source"), listOf(CloudJobs.Step("s", "u", 0, 100, 0.7)))
        val work = launch(Dispatchers.Default + CloudJobs.Context("{}", delivery)) {
            CloudJobs.run(spec, at, store, pause = { delay(60_000) })
        }
        withTimeout(10_000) { while (store.all().isEmpty()) delay(5) }
        GenerationCenter.begin("Writing 2 questions", 2, keeping = delivery) { work.cancel() }
        stop()
        work.join()
        store to server
    }

    @Test fun aCloudRunTheSystemStoppedIsLeftToFinishForTheCollector() {
        val (store, server) = stoppedRun(CloudJobs.Delivery()) { GenerationCenter.stopAtExpiry(appActive = true) }
        assertNull("handed over: no run of the app is watching it", store.all().single().launch)
        assertEquals("and the server is not told to forget it", 0, server.requests.count { it.method == "DELETE" })
    }

    @Test fun aCloudRunTheStudentStoppedIsStoppedAndForgotten() {
        val (store, server) = stoppedRun(CloudJobs.Delivery()) { GenerationCenter.cancel() }
        assertTrue(store.all().isEmpty())
        assertEquals("the server is told to stop it, once", 1, server.requests.count { it.method == "DELETE" && it.path == "/jobs/$jobId" })
    }

    @Test fun aCloudRunStoppedByAnExpiryWhileAwayIsTreatedAsTheStudents() {
        val (store, server) = stoppedRun(CloudJobs.Delivery()) { GenerationCenter.stopAtExpiry(appActive = false) }
        assertTrue(store.all().isEmpty())
        assertEquals("the server is told to stop it, once", 1, server.requests.count { it.method == "DELETE" && it.path == "/jobs/$jobId" })
    }

    @Test fun timeLeftWaitsForAPace() {
        val start = 1_000_000L
        val job = GenerationCenter.Job(UUID.randomUUID(), "Writing 20 questions", 0, 20, started = start)
        assertNull("nothing done yet", job.secondsLeft(start + 60_000))
        val some = job.copy(done = 8)
        assertNull("under five seconds", some.secondsLeft(start + 4_000))
        assertEquals(225, some.secondsLeft(start + 150_000))
        assertNull("all done", some.copy(done = 20).secondsLeft(start + 150_000))
        assertEquals(1.0, some.copy(done = 25).fraction, 0.0)
        assertEquals(0.0, some.copy(total = 0).fraction, 0.0)
    }

    @Test fun theCardsWords() {
        val start = 1_000_000L
        val job = GenerationCenter.Job(UUID.randomUUID(), "Writing 20 questions", 8, 20, started = start)
        assertEquals("8 of 20 · 12 left", GenerationWords.counts(job))
        assertEquals("Starting…", GenerationWords.counts(job.copy(total = 0)))
        assertNull(GenerationWords.timeLeft(job, start + 1_000))
        assertEquals("~4 min left", GenerationWords.timeLeft(job, start + 150_000))
        assertEquals("<1 min left", GenerationWords.timeLeft(job, start + 20_000))
        assertEquals("40%", GenerationWords.shown(job.fraction))
        assertEquals("40 percent done", GenerationWords.spoken(job.fraction))
    }

    @Test fun theCardShowsTheJobAndItsCancelStopsIt() {
        var stopped = false
        compose.setContent { StethoscoreTheme { GenerationHUD() } }
        compose.onNodeWithText("Writing 20 questions").assertDoesNotExist()
        val id = GenerationCenter.begin("Writing 20 questions", 20) { stopped = true }!!
        GenerationCenter.update(id, 8, 20)
        compose.onNodeWithText("Writing 20 questions").assertIsDisplayed()
        compose.onNodeWithText("8 of 20 · 12 left").assertIsDisplayed()
        compose.onNodeWithContentDescription("40 percent done").assertExists()
        compose.onNodeWithTag("cancelGeneration").performClick()
        compose.waitForIdle()
        assertTrue(stopped)
        assertNull(GenerationCenter.job)
        compose.onNodeWithText("Writing 20 questions").assertDoesNotExist()
    }

    // R2: a rotation recreates the activity; the screen keeps its owner, and
    // the run, its card and its progress carry on (iOS's shared center does)
    @Test fun aRunSurvivesItsScreenBeingRecreated() {
        var recreating = false
        var owner: UUID? = null
        val tester = StateRestorationTester(compose)
        tester.setContent { StethoscoreTheme { owner = rememberGenerationOwner(changing = { recreating }); GenerationHUD() } }
        val first = owner!!
        var stopped = false
        val id = GenerationCenter.begin("Writing 8 questions", 8, owner = first) { stopped = true }!!
        GenerationCenter.update(id, 3, 8)
        recreating = true
        tester.emulateSavedInstanceStateRestore()
        compose.waitForIdle()
        assertEquals("the new screen is the same owner", first, owner)
        assertTrue(GenerationCenter.runs(first))
        assertEquals(id, GenerationCenter.job?.id)
        assertTrue("nothing was stopped", !stopped)
        compose.onNodeWithText("3 of 8 \u00B7 5 left").assertIsDisplayed()
        // and the run goes on reporting to the recreated card
        GenerationCenter.update(id, 4, 8)
        compose.onNodeWithText("4 of 8 \u00B7 4 left").assertIsDisplayed()
    }

    // R3: the status under Make is read from the center, so a recreated form
    // never shows a count from a run that is no longer going
    @Test fun noStaleStatusOnceNothingRuns() {
        val owner = UUID.randomUUID()
        val tester = StateRestorationTester(compose)
        tester.setContent {
            StethoscoreTheme {
                CompositionLocalProvider(LocalGenerationOwner provides owner) {
                    var text by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf("Ramipril is an ACE inhibitor.") }
                    MCQGenerateForm(text, { text = it }, 8, {}, false, {}, null, {}, "", {}, name = "", step = LectureStep.make, onGenerated = {})
                }
            }
        }
        compose.onNodeWithText("Writing", substring = true).assertDoesNotExist()
        val id = GenerationCenter.begin("Writing 8 questions", 8, owner = owner) {}!!
        GenerationCenter.update(id, 3, 8)
        compose.onNodeWithText("Writing 3 of 8 questions\u2026").assertExists()
        tester.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("Writing 3 of 8 questions\u2026").assertExists()
        // the run ends while the screen is away: nothing is left saying it writes
        GenerationCenter.end(id)
        tester.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("Writing", substring = true).assertDoesNotExist()
        compose.onNodeWithText("Make 8 questions").assertExists()
        // a run's last word is the center's too, and goes with its screen
        GenerationCenter.note(owner, "Cancelled.")
        compose.onNodeWithText("Cancelled.").assertExists()
        GenerationCenter.forget(owner)
        compose.onNodeWithText("Cancelled.").assertDoesNotExist()
    }

    // R4: Android may destroy the activity in the background without the
    // student leaving; the run (paid work) goes on. Finishing it stops the run.
    private class Hosted(val activity: ActivityController<ComponentActivity>, val owner: UUID, val disposed: () -> Boolean)

    private fun hosted(): Hosted {
        val controller = Robolectric.buildActivity(ComponentActivity::class.java).setup()
        var owner: UUID? = null
        var disposed = false
        controller.get().setContent {
            owner = rememberGenerationOwner()
            DisposableEffect(Unit) { onDispose { disposed = true } }
        }
        shadowOf(Looper.getMainLooper()).idle()
        return Hosted(controller, owner!!) { disposed }
    }

    @Test fun aBackgroundDestroyKeepsTheRunAndFinishingStopsIt() {
        assertTrue(GenerationLife.goesOn(finishing = false, changingConfigurations = false, destroyed = true))
        assertTrue(GenerationLife.goesOn(finishing = false, changingConfigurations = true, destroyed = true))
        assertTrue(!GenerationLife.goesOn(finishing = true, changingConfigurations = false, destroyed = true))
        assertTrue(!GenerationLife.goesOn(finishing = false, changingConfigurations = false, destroyed = false))

        val away = hosted()
        var stopped = false
        val id = GenerationCenter.begin("Writing 8 questions", 8, owner = away.owner) { stopped = true }!!
        away.activity.pause().stop().destroy()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("the screen went with its activity", away.disposed())
        assertTrue("a background destroy stops nothing", !stopped)
        assertTrue(GenerationCenter.runs(away.owner))
        GenerationCenter.end(id)

        val left = hosted()
        var stoppedOnLeaving = false
        GenerationCenter.begin("Writing 8 questions", 8, owner = left.owner) { stoppedOnLeaving = true }!!
        left.activity.get().finish()
        left.activity.pause().stop().destroy()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(left.disposed())
        assertTrue("finishing the activity stops the run", stoppedOnLeaving)
        assertNull(GenerationCenter.job)
    }

    // R5: the questions a run wrote, open in New set's quiz, are kept when
    // the screen is recreated (a rotation), until they are saved or discarded
    private val stem = "A 54-year-old diabetic with hypertension needs a first drug; which is best?"

    private fun questions(): String = JSONObject().put("questions", JSONArray().put(JSONObject().put("stem", stem)
        .put("options", JSONArray(listOf("Atenolol tablets", "Amlodipine tablets", "Ramipril tablets", "Indapamide tablets", "Doxazosin tablets")))
        .put("correctIndex", 2).put("explanation", "Key point: ACE inhibitors first."))).toString()

    /** Marks the test's activity as being recreated for a configuration change, as a rotation does. */
    private fun rotating(on: Boolean) {
        val field = android.app.Activity::class.java.getDeclaredField("mChangingConfigurations")
        field.isAccessible = true
        field.setBoolean(compose.activity, on)
    }

    private fun until(done: () -> Boolean) {
        compose.waitUntil(timeoutMillis = 20_000) {
            if (!done()) compose.mainClock.advanceTimeBy(500)
            done()
        }
    }

    @Test fun theFinishedSetSurvivesTheScreenBeingRecreatedUntilItIsTaken() {
        val store = StudyStore(folder.newFolder("held"))
        val jobs = FakeJobs(listOf(questions()))
        val llm = LLMService(FakeServer.standInKey(), { null }, FakeServer.BASE,
            FakeServer { jobs.answer(it) }, OwnerSpend(OwnerSpend.MemoryStore()))
        val preset = NewSetPreset(StudySetKind.MCQ, "Ramipril", "Cardiology", "Ramipril is an ACE inhibitor, first for hypertension in diabetes.")
        LearnRouter.close()
        val tester = StateRestorationTester(compose)
        tester.setContent {
            CompositionLocalProvider(LocalLLMService provides llm) {
                StethoscoreTheme { LibraryNewSetScreen(store, preset.kind, {}, {}, preset = preset) }
            }
        }
        compose.onAllNodesWithText("Make 8 questions").onFirst().performScrollTo().performClick()
        until { compose.onAllNodesWithText(stem, substring = true).fetchSemanticsNodes().isNotEmpty() }

        rotating(true)
        tester.emulateSavedInstanceStateRestore()
        rotating(false)
        compose.waitForIdle()
        assertTrue("the set is still open after the screen is recreated",
            compose.onAllNodesWithText(stem, substring = true).fetchSemanticsNodes().isNotEmpty())
        assertTrue("nothing was saved yet", store.library.none { set -> set.questions.any { it.stem == stem } })

        // Back asks; Discard takes the set, and a later recreation does not bring it back
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.onNodeWithText("Discard").performClick()
        compose.waitForIdle()
        assertTrue(compose.onAllNodesWithText(stem, substring = true).fetchSemanticsNodes().isEmpty())
        rotating(true)
        tester.emulateSavedInstanceStateRestore()
        rotating(false)
        compose.waitForIdle()
        assertTrue(compose.onAllNodesWithText(stem, substring = true).fetchSemanticsNodes().isEmpty())
        compose.onAllNodesWithText("Make 8 questions").onFirst().assertExists()
    }
}
