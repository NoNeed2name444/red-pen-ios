package com.stethoscore.app.ui.home

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.SettingsScreen
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.learn.LearnRouterClosed
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The owner's per-screen picks (23 Oct): home's header and empty library as
 * iOS has them, and Settings' one exam row.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HomeOwnerPicksTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    @Test fun homeHeaderHasTheAccountMenuAndNoEyebrowOrGearRow() {
        val store = StudyStore(folder.newFolder("header"))
        compose.setContent { StethoscoreApp(store, forceDark = false) }
        compose.waitForIdle()
        compose.onAllNodesWithText("YOUR STUDY WARD").assertCountEquals(0)
        compose.onAllNodesWithText("Your study ward").assertCountEquals(0)
        // Settings is reached the way iOS reaches it: through the account menu beside the search
        // the empty library's own Your lectures link, then the menu's as well once it opens
        compose.onAllNodesWithText("Your lectures").assertCountEquals(1)
        compose.onNodeWithContentDescription("Account and settings").performClick()
        compose.waitForIdle()
        compose.onAllNodesWithText("Your lectures").assertCountEquals(2)
        compose.onNodeWithText("Settings").performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Your study space").assertExists()
    }

    @Test fun emptyHomeIsTheOneLibraryCard() {
        val store = StudyStore(folder.newFolder("empty"))
        compose.setContent { StethoscoreApp(store, forceDark = false) }
        compose.waitForIdle()
        compose.onAllNodesWithTag("libraryEmpty").assertCountEquals(1)
        compose.onAllNodesWithText("Make your first set").assertCountEquals(1)
        compose.onAllNodesWithText("New set").assertCountEquals(1)
        compose.onNodeWithTag("emptyLibraryLinks").assertExists()
        compose.onAllNodesWithText("Explore example sets").assertCountEquals(0)
        compose.onAllNodesWithText("Import a Stethoscore library").assertCountEquals(0)
    }

    @Test fun settingsHasOneExamRow() {
        compose.setContent { SettingsScreen(false, {}, {}, {}, {}, {}, onExam = {}) }
        compose.waitForIdle()
        compose.onAllNodesWithTag("chooseExam").assertCountEquals(1)
        compose.onAllNodesWithText("Choose your exam").assertCountEquals(0)
        compose.onAllNodesWithText("Change exam").assertCountEquals(0)
        compose.onAllNodesWithText("Night shift").assertCountEquals(1)
    }
}
