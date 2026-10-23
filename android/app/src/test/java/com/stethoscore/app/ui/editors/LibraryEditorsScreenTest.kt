package com.stethoscore.app.ui.editors

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.AnkiRating
import com.stethoscore.app.data.DiagramCards
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.ReadSource
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The library editors as iOS's CardsEditorView, CardEditSheets,
// PictureFromPhotoView, MCQGenerateForm and LectureWriterSection run them
// (fed0105): their words, what can and cannot be saved, and the path taken
// when no writer is set up on the phone.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LibraryEditorsScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    @Test fun aDeletedCardIsSavedAndItsReviewsForgotten() {
        val store = StudyStore(folder.newFolder("edit"))
        val gone = AnkiCard(front = "Rash across the cheeks?", bullets = listOf("Malar rash"))
        val kept = AnkiCard(type = AnkiCardType.CLOZE, clozeText = "Anti-{{c1::dsDNA}} is specific")
        val set = StudySet(name = "Lupus", subject = "Rheumatology", kind = StudySetKind.ANKI, cards = listOf(gone, kept))
        store.addSet(set)
        store.rateCard(gone, AnkiRating.EASY)
        store.rateCard(kept, AnkiRating.EASY)
        var closed = false
        compose.setContent { StethoscoreTheme { CardsEditorScreen(set, store) { closed = true } } }
        compose.onNodeWithText("Edit cards").assertExists()
        compose.onNodeWithText("SET TAGS").assertExists()
        compose.onNodeWithText("Save changes").assertDoesNotExist()
        compose.onNodeWithText("Edit").performClick()
        compose.onAllNodesWithContentDescription("Delete")[0].performClick()
        compose.onNodeWithText("Rash across the cheeks?").assertDoesNotExist()
        compose.onNodeWithText("Save changes").performClick()
        assertTrue(closed)
        val saved = store.library.first { it.id == set.id }
        assertEquals(listOf(kept.id), saved.cards.map { it.id })
        assertFalse("a deleted card's reviews go with it", store.reviews.containsKey(gone.id))
        assertTrue(store.reviews.containsKey(kept.id))
    }

    @Test fun aClozeWithNothingHiddenCannotBeSaved() {
        var card by mutableStateOf(AnkiCard(type = AnkiCardType.CLOZE, clozeText = "Anti-dsDNA is specific"))
        compose.setContent { StethoscoreTheme { CardEditSheet(card, emptyList(), onCancel = {}) {} } }
        compose.onNodeWithText("Edit card").assertExists()
        compose.onNodeWithText("SENTENCE").assertExists()
        compose.onNodeWithText("Nothing is hidden yet — wrap the tested words in {{c1::...}}.").assertExists()
        compose.onNodeWithText("Done").assertIsNotEnabled()
        card = AnkiCard(type = AnkiCardType.CLOZE, clozeText = "Anti-{{c1::dsDNA}} is specific")
        compose.onNodeWithText("Wrap the tested words in {{c1::...}}.").assertExists()
        compose.onNodeWithText("Done").assertIsEnabled()
    }

    @Test fun aQuestionIsSavedOnlyWithItsAnswerMarked() {
        val question = MCQQuestion(stem = "First-line for SLE skin disease?", options = listOf("Hydroxychloroquine", "Rituximab", " "), correctIndex = 2)
        var saved: MCQQuestion? = null
        compose.setContent { StethoscoreTheme { QuestionEditSheet(question, emptyList(), onCancel = {}) { saved = it } } }
        compose.onNodeWithText("Edit question").assertExists()
        compose.onNodeWithText("No answer is marked correct — tap the circle beside the right one.").assertExists()
        compose.onNodeWithText("Done").assertIsNotEnabled()
        compose.onAllNodesWithContentDescription("Mark correct")[0].performClick()
        compose.onNodeWithText("Tap the circle beside the right answer.").assertExists()
        compose.onNodeWithText("Add an option").assertExists()
        compose.onNodeWithText("Done").performClick()
        assertEquals(listOf("Hydroxychloroquine", "Rituximab"), saved?.options)
        assertEquals(0, saved?.correctIndex)
    }

    @Test fun aPhotoStartsFromPhotosOrFilesWithNoScanner() {
        val store = StudyStore(folder.newFolder("photo"))
        compose.setContent { StethoscoreTheme { PictureFromPhotoScreen(store, onBack = {}, onOpen = {}) } }
        compose.onNodeWithText("From a photo or scan").assertExists()
        compose.onNodeWithText("Photos").assertExists()
        compose.onNodeWithText("Files").assertExists()
        // ML Kit's document scanner is not among this build's libraries
        compose.onNodeWithText("Scan pages").assertDoesNotExist()
        assertFalse(DocumentScanning.isAvailable)
    }

    @Test fun theQuestionFormSaysNoWriterIsSetUp() {
        var step by mutableStateOf(LectureStep.material)
        compose.setContent {
            StethoscoreTheme {
                var text by remember { mutableStateOf("") }
                var count by remember { mutableIntStateOf(10) }
                var highYield by remember { mutableStateOf(false) }
                var source by remember { mutableStateOf<ReadSource?>(null) }
                var subject by remember { mutableStateOf("") }
                MCQGenerateForm(text, { text = it }, count, { count = it }, highYield, { highYield = it }, source, { source = it },
                    subject, { subject = it }, name = "", step = step, onGenerated = {})
            }
        }
        compose.onNodeWithText("ADD A FILE").assertExists()
        compose.onNodeWithText("Choose a lecture file").assertExists()
        compose.onNodeWithText("OR PASTE YOUR NOTES").assertExists()
        compose.onNodeWithText("The questions are written from this text. A file you add above lands here too.").assertExists()
        step = LectureStep.make
        compose.onNodeWithText("How many questions").assertExists()
        compose.onNodeWithText(NoWriter.questions).assertExists()
        // the reason Make is greyed is the cloud's own: the default build has no Pro
        compose.onNodeWithText("Stethoscore Cloud is part of Pro.").assertExists()
        // nothing is written on the phone, and nothing says it might be
        compose.onNodeWithText("On-device", substring = true).assertDoesNotExist()
        compose.onNodeWithText("Make 10 questions").assertIsNotEnabled()
        compose.onNodeWithText("More options").performClick()
        compose.onNodeWithText("Focus on high-yield facts").assertExists()
    }

    @Test fun theCardWriterSaysNoModelIsReady() {
        var step by mutableStateOf(LectureStep.material)
        val notes = "The malar rash of lupus spares the nasolabial folds. ".repeat(6)
        compose.setContent {
            StethoscoreTheme {
                var source by remember { mutableStateOf<ReadSource?>(null) }
                var name by remember { mutableStateOf("") }
                var diagrams by remember { mutableStateOf(DiagramCards()) }
                var subject by remember { mutableStateOf("") }
                LectureWriterSection(StudySetKind.ANKI, "", {}, source, { source = it }, name, { name = it }, diagrams, { diagrams = it },
                    subject, { subject = it }, step, presetNotes = notes)
            }
        }
        compose.onNodeWithText("ADD A FILE").assertExists()
        compose.onNodeWithText("PDF, Word or PowerPoint. It is read on this device.").assertExists()
        compose.onNodeWithText("Or paste your notes").assertExists()
        step = LectureStep.make
        compose.onNodeWithText("Card type").assertExists()
        compose.onNodeWithText("Mixed (all types)").assertExists()
        compose.onNodeWithText("How many cards").assertExists()
        compose.onNodeWithText("Make 12 cards").performClick()
        compose.onNodeWithText("No model is ready to write with.").assertExists()
        compose.onNodeWithText("Go back and add a lecture first.").assertDoesNotExist()
        compose.onNodeWithText("Mixed (all types)").performClick()
        compose.onNodeWithText("Image occlusion").performClick()
        compose.onNodeWithText("Add 0 image cards").assertIsNotEnabled()
        compose.onNodeWithText("How many cards").assertDoesNotExist()
    }
}
