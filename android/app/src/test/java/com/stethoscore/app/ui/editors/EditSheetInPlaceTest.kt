package com.stethoscore.app.ui.editors

import androidx.activity.ComponentActivity
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// Editing one card or question (r039): the sheet takes the editor's place, so
// one Cancel and one title are on screen, never the list's header under the
// sheet's (the tour drew the sheet over the list, two headers and their labels
// overlapping). Light and dark.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class EditSheetInPlaceTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val dark = mutableStateOf(false)

    @Test fun aCardOpensInTheListsPlace() {
        val store = StudyStore(folder.newFolder("cards"))
        val set = StudySet(name = "Lupus", kind = StudySetKind.ANKI, cards = listOf(AnkiCard(front = "Rash across the cheeks?", bullets = listOf("Malar rash"))))
        store.addSet(set)
        inEachMode(store, set) { mode ->
            compose.onNodeWithText("Rash across the cheeks?").performClick()
            onlyTheSheet("Edit card", "Edit cards", mode)
        }
    }

    @Test fun aQuestionOpensInTheListsPlace() {
        val store = StudyStore(folder.newFolder("questions"))
        val set = StudySet(name = "Renal", kind = StudySetKind.MCQ,
            questions = listOf(MCQQuestion(stem = "Casts?", options = listOf("Red cell", "Fatty"), correctIndex = 0)))
        store.addSet(set)
        inEachMode(store, set) { mode ->
            compose.onNodeWithText("Casts?").performClick()
            onlyTheSheet("Edit question", "Edit questions", mode)
        }
    }

    /** The editor afresh in light, then in dark. */
    private fun inEachMode(store: StudyStore, set: StudySet, check: (Boolean) -> Unit) {
        compose.setContent { key(dark.value) { StethoscoreTheme(dark.value) { CardsEditorScreen(set, store) {} } } }
        for (mode in listOf(false, true)) {
            dark.value = mode
            compose.waitForIdle()
            check(mode)
        }
    }

    private fun onlyTheSheet(sheet: String, list: String, dark: Boolean) {
        val mode = if (dark) "dark" else "light"
        compose.onNodeWithText(sheet).assertExists()
        compose.onNodeWithText(list).assertDoesNotExist()
        assertEquals("$mode: one Cancel on screen", 1, compose.onAllNodesWithText("Cancel").fetchSemanticsNodes().size)
        assertEquals("$mode: no Edit button from the list under it", 0, compose.onAllNodesWithText("Edit").fetchSemanticsNodes().size)
    }
}
