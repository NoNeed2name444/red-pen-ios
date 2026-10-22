package com.stethoscore.app.ui.sources

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.performTextInput
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.reading.ContentSources
import com.stethoscore.app.ui.book.BookReaderScreen
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The batch 9 screens on a phone: the textbook reader's header, paging and
// kept place; the sources library, empty and with a lecture; the lecture
// reader's search; and the credits, for a set with nothing recorded and for
// one made from a lecture. The words are iOS's (fed0105).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReaderScreensTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val book = StudySet(name = "Cardiology", subject = "Cardiology", kind = StudySetKind.BOOK,
        bookMarkdown = "# Heart\n\nThe heart has four chambers.\n\n# Valves\n\nFour valves keep blood moving.\n\n# Murmurs\n\nListen at the apex.")
    private val lecture = SourceDoc(name = "Renal lecture", kind = "pdf",
        pages = listOf(SourcePage(1, "Nephritic syndrome\nHaematuria and casts"), SourcePage(2, "Nephrotic syndrome\nHaematuria is rare")))
    private val renal = StudySet(name = "Renal MCQs", kind = StudySetKind.MCQ, sources = listOf(lecture),
        questions = listOf(MCQQuestion(stem = "Casts?", options = listOf("Red cell", "Fatty"), correctIndex = 0, source = "Renal lecture, p. 1")))

    @Test fun bookPagesForwardAndKeepsItsPlace() {
        val store = StudyStore(folder.newFolder("book"))
        compose.setContent { BookReaderScreen(book, store, onBack = {}) }
        compose.onNodeWithText("Page 1 of 3").assertIsDisplayed()
        compose.onNodeWithText("The heart has four chambers.").assertExists()
        compose.onNodeWithText("Next page").performClick()
        compose.onNodeWithText("Page 2 of 3").assertIsDisplayed()
        compose.onNodeWithText("Four valves keep blood moving.").assertExists()
        compose.waitForIdle()
        assertEquals(1, store.readingProgress[book.id]?.position)
        compose.onNodeWithText("Next page").performClick()
        // the last page: Done in place of Next page
        compose.onNodeWithText("Done").assertExists()
        compose.onNodeWithText("Next page").assertDoesNotExist()
    }

    @Test fun bookOpensAtTheSavedPageAndListsItsContents() {
        val store = StudyStore(folder.newFolder("saved"))
        store.saveReadingProgress(book.id, 2)
        compose.setContent { BookReaderScreen(book, store, onBack = {}) }
        compose.onNodeWithText("Page 3 of 3").assertIsDisplayed()
        compose.onNodeWithContentDescription("Contents").performClick()
        compose.waitForIdle()
        compose.onNodeWithContentDescription("You are here").assertExists()
        // a tap by its action: Robolectric does not place a bottom sheet's window where a touch lands
        compose.onNodeWithText("Valves").performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        compose.onNodeWithContentDescription("You are here").assertDoesNotExist()
        compose.onNodeWithText("Page 2 of 3").assertExists()
        compose.onNodeWithText("Four valves keep blood moving.").assertExists()
    }

    @Test fun emptySourcesSayHowToAddOne() {
        val store = StudyStore(folder.newFolder("none"))
        var added = false
        compose.setContent { SourcesLibraryScreen(store, onBack = {}, onAdd = { added = true }) }
        compose.onNodeWithText("No sources yet").assertIsDisplayed()
        compose.onNodeWithText("Add a lecture").performClick()
        assertEquals(true, added)
    }

    @Test fun aLectureOpensToReadAndSearch() {
        val store = StudyStore(folder.newFolder("lecture"))
        store.addSet(renal)
        compose.setContent { SourcesLibraryScreen(store, onBack = {}, onAdd = {}) }
        assertEquals(1, compose.onAllNodesWithTag("source-row").fetchSemanticsNodes().size)
        compose.onNodeWithText("PDF · 2 pages · 1 set").assertExists()
        compose.onNodeWithText("Renal lecture").performClick()
        compose.onNodeWithText("PAGE 1").assertExists()
        compose.onNodeWithText("Search this pdf").performTextInput("haematuria")
        // a section header, in small capitals
        compose.onNodeWithText("2 MENTIONS ON 2 PAGES").assertExists()
    }

    @Test fun creditsForASetWithNothingRecorded() {
        compose.setContent { SetCreditsScreen(StudySet(name = "Typed", kind = StudySetKind.ANKI), onBack = {}, onLicences = {}) }
        compose.onNodeWithText("Sources and licences").assertIsDisplayed()
        compose.onNodeWithText("Nothing recorded for this set").assertExists()
        compose.onNodeWithText("Every source and licence").assertExists()
    }

    @Test fun creditsForASetMadeFromALecture() {
        var licences = false
        compose.setContent { SetCreditsScreen(renal, onBack = {}, onLicences = { licences = true }) }
        compose.onNodeWithText("Renal lecture").assertExists()
        compose.onNodeWithText("Cited by 1 question").assertExists()
        compose.onNodeWithText(CreditsWords.madeFromFooter).assertExists()
        compose.onNodeWithText("Every source and licence").performClick()
        assertEquals(true, licences)
    }

    @Test fun licencesListEverySource() {
        compose.setContent { ContentLicencesScreen(onBack = {}) }
        compose.onNodeWithText(CreditsWords.yourMaterial).assertExists()
        ContentSources.all.forEach { compose.onNodeWithText(it.attribution).assertExists() }
    }
}
