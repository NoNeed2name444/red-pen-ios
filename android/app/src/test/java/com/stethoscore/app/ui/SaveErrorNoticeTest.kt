package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiRating
import com.stethoscore.app.data.LibraryWriter
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.learn.LearnRouterClosed
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.IOException
import java.util.concurrent.Executors

// A save that fails on the library's writer thread reaches the screen as a notice,
// posted to the main thread (the notice and the revision are its state).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SaveErrorNoticeTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    @Test fun aFailedBackgroundSaveShowsTheNotice() {
        val thread = Executors.newSingleThreadExecutor()
        try {
            val store = StudyStore(folder.root, LibraryWriter(thread))
            store.addSet(StudySet(id = "deck", name = "Renal", kind = StudySetKind.ANKI, cards = listOf(AnkiCard(id = "c1", front = "Q", bullets = listOf("A")))))
            compose.setContent { StethoscoreApp(store, initialScreen = "home", forceDark = false) }
            compose.waitForIdle()
            store.beforeRename = { throw IOException("disk full") }
            store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
            store.flush()
            compose.waitForIdle()
            compose.onNodeWithText("Changes since the last save were undone.", substring = true).assertExists()
        } finally { thread.shutdownNow() }
    }
}
