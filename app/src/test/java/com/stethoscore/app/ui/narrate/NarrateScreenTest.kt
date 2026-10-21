package com.stethoscore.app.ui.narrate

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.semantics.SemanticsActions
import com.stethoscore.app.audio.LectureAudio
import com.stethoscore.app.audio.LectureLanguage
import com.stethoscore.app.audio.LectureTranscriber
import com.stethoscore.app.data.NarrateSegment
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The batch 12 screen on a phone, in iOS's words (fed0105): the header and
// its line count, a tapped line, a word held and fixed (and the fix undone),
// the empty transcript's way to add a recording, and the importer saying, in
// iOS's own words for both transcribers failing, that neither is set up.
@RunWith(RobolectricTestRunner::class)
// a phone the size of a Pixel 7
@Config(sdk = [35], qualifiers = "w411dp-h891dp")
class NarrateScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val lecture = StudySet(name = "Acid-base", subject = "Physiology", kind = StudySetKind.NARRATE,
        narrateSegments = listOf(
            NarrateSegment(text = "Buffers act in seconds"),
            NarrateSegment(text = "the lungs in minutes"),
            NarrateSegment(text = "the kidneys take days")))

    @Test fun headerFollowsATappedLine() {
        val store = StudyStore(folder.newFolder("tap")).also { it.addSet(lecture) }
        compose.setContent { NarrateReviewScreen(lecture, store, onBack = {}) }
        compose.onNodeWithText("Line 1 of 3").assertIsDisplayed()
        compose.onNodeWithText("Tap a line to read from it · hold a word to fix it").assertIsDisplayed()
        compose.onNodeWithText("Physiology").assertIsDisplayed()
        compose.onNodeWithText("kidneys").performClick()
        compose.onNodeWithText("Line 3 of 3").assertIsDisplayed()
        // read aloud, not a recording: Play, the reading speed and the way to add one
        compose.onNodeWithText("Play").assertExists()
        compose.onNodeWithContentDescription("Reading speed, 1×").assertExists()
        compose.onNodeWithContentDescription("Add an audio file").assertExists()
        compose.onNodeWithContentDescription("Sleep timer").assertExists()
    }

    @Test fun aHeldWordIsFixedAndUndone() {
        val store = StudyStore(folder.newFolder("fix")).also { it.addSet(lecture) }
        compose.setContent { NarrateReviewScreen(lecture, store, onBack = {}) }
        compose.onNodeWithText("Buffers").performTouchInput { longClick() }
        compose.onNodeWithText("Fix this word").assertIsDisplayed()
        compose.onNodeWithText("HEARD AS").assertExists()
        compose.onNodeWithText("Every other word that sounds the same is fixed too, and remembered for next time.").assertExists()
        compose.onNodeWithText("the correct spelling").performTextInput("Bufferz")
        // the bar's Fix, under the thumb (the sheet's buttons are pressed by their action: a sheet in Robolectric is a window of its own)
        compose.onAllNodesWithText("Fix")[1].performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        compose.onNodeWithText("Bufferz").assertExists()
        compose.onNodeWithText("Fixed, and remembered").assertIsDisplayed()
        assertEquals("Bufferz act in seconds", store.library.first { it.id == lecture.id }.narrateSegments[0].text)
        compose.onNodeWithText("Undo").performClick()
        compose.onNodeWithText("Buffers").assertExists()
        compose.onNodeWithText("Fixed, and remembered").assertDoesNotExist()
        assertEquals("Buffers act in seconds", store.library.first { it.id == lecture.id }.narrateSegments[0].text)
    }

    @Test fun anEmptyTranscriptOffersAudio() {
        val empty = StudySet(name = "New lecture", subject = "", kind = StudySetKind.NARRATE)
        val store = StudyStore(folder.newFolder("empty")).also { it.addSet(empty) }
        compose.setContent { NarrateReviewScreen(empty, store, onBack = {}) }
        compose.onNodeWithText("Narrate").assertIsDisplayed()
        compose.onNodeWithText("Line 1 of 0").assertIsDisplayed()
        compose.onNodeWithText("Nothing to read yet").assertIsDisplayed()
        compose.onNodeWithText("This transcript is empty. Tap Add audio below to add a recording of the lecture.").assertIsDisplayed()
        compose.onNodeWithText("Add audio").performClick()
        compose.onNodeWithText("Transcribe the recording with").assertIsDisplayed()
        compose.onNodeWithText("Gemini (Pro) — Arabic + English lecture").assertExists()
        compose.onNodeWithText("This phone only — English, offline").assertExists()
        compose.onNodeWithText("Cancel").performSemanticsAction(SemanticsActions.OnClick)
        compose.onNodeWithText("Transcribe the recording with").assertDoesNotExist()
        // More holds the same way in
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Add recording").assertIsDisplayed()
    }

    @Test fun neitherTranscriberIsSetUp() {
        val dir = LectureAudio.folder(folder.newFolder("nobackup"))
        val importer = LectureImporter()
        val kept = runBlocking {
            importer.attach({ "a lecture".byteInputStream() }, "M4A", "set-1", dir, LectureImporter.Engine.cloud, LectureLanguage.mixed) {}
        }
        assertEquals("the recording is kept under the set's id", "set-1.m4a", kept?.name)
        assertEquals("both ways failing is one message, in iOS's words",
            "Gemini: ${LectureTranscriber.Failure.cloudNotSetUp}\n\nOn this phone: ${LectureTranscriber.Failure.deviceNotSetUp}", importer.trouble)
        assertNull("no transcript", importer.produced)
        assertNull("and nothing is still working", importer.working)
        assertNull("nor a notice left over", importer.notice)

        // the phone alone: its own reason, nothing about Gemini
        runBlocking { importer.transcribe(kept!!, LectureImporter.Engine.device, LectureLanguage.english) {} }
        assertEquals(LectureTranscriber.Failure.deviceNotSetUp, importer.trouble)

        // a transcriber that hears something: learned spellings applied before the student sees it
        val hearing = LectureImporter(device = { _, _ ->
            LectureTranscriber.lines(listOf(LectureTranscriber.SpokenWord("acidosis", 0.0, 0.5)))
        })
        runBlocking { hearing.transcribe(kept!!, LectureImporter.Engine.cloud, LectureLanguage.english) { it[0] = it[0].uppercase() } }
        assertEquals("ACIDOSIS", hearing.produced?.single()?.text)
        assertEquals("en", hearing.produced?.single()?.lang)
        assertTrue("the cloud falling back says so", hearing.notice?.startsWith("Transcribed on this phone instead. ") == true)
    }

    @Test fun theWords() {
        assertEquals("Line 2 of 5", NarrateWords.status(1, 5))
        assertEquals("an empty transcript still reads as line 1", "Line 1 of 0", NarrateWords.status(0, 0))
        assertEquals("by lines done, not the line on", 0.2, NarrateWords.fraction(1, false, 5), 1e-9)
        assertEquals("finished counts the last line", 1.0, NarrateWords.fraction(4, true, 5), 1e-9)
        assertEquals("Following the recording · hold a word to fix it", NarrateWords.detail(true, true))
        assertEquals("Getting the voice ready…", NarrateWords.detail(false, true))
        assertEquals("Your recording is being transcribed. The transcript appears here when it's ready.", NarrateWords.emptyLine(true, true))
        assertEquals("This transcript is empty. Replace the recording from More.", NarrateWords.emptyLine(false, true))
        assertEquals("Replace recording", NarrateWords.recordingItem(true))
        assertEquals(4, NarrateWords.engines.size)
    }
}
