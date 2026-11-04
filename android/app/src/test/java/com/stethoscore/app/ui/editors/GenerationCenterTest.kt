package com.stethoscore.app.ui.editors

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.StateRestorationTester
import com.stethoscore.app.ui.StethoscoreTheme
import org.junit.After
import org.junit.Assert.assertEquals
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

    @After fun clear() { GenerationCenter.cancel() }

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
}
