package com.stethoscore.app.ui.library

import android.content.Context
import android.content.Intent
import android.content.pm.ProviderInfo
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreTheme
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

// The activity is exported, so any app can hand it a file. Only a content://
// file from another app's provider is taken; a file:// path, a resource, or one
// of this app's own providers would be read with this app's rights, and is
// refused with one plain reason.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class IncomingFilesTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val own = "com.stethoscore.app"

    @Before @After fun nothingWaits() { IncomingFiles.waiting.clear(); IncomingFiles.refused = 0 }

    private fun view(uri: String) = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
    private fun send(uri: String) = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, Uri.parse(uri)).setType("text/csv")

    private fun taken(intent: Intent): Boolean {
        nothingWaits()
        IncomingFiles.take(intent, context)
        val took = IncomingFiles.waiting.toList() == listOf(intent.data ?: intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java))
        assertEquals("taken or refused, never both or neither", if (took) 0 else 1, IncomingFiles.refused)
        if (!took) assertTrue(IncomingFiles.waiting.isEmpty())
        return took
    }

    @Test fun anotherAppsSharedFileIsTaken() {
        assertTrue(taken(view("content://com.android.providers.downloads.documents/document/7")))
        assertTrue(taken(send("content://com.google.android.apps.docs.storage/document/acc%3D1%3Bdoc%3D9")))
        assertTrue("another user's provider of another app", taken(view("content://10@media/external/file/3")))
    }

    @Test fun aPathIntoTheAppsOwnFilesIsRefused() {
        assertFalse(taken(view("file:///data/user/0/$own/files/library.json")))
        assertFalse(taken(send("file:///data/data/$own/shared_prefs/appearance.xml")))
        assertFalse(taken(view("android.resource://$own/raw/examples")))
        assertFalse("no authority", taken(view("content:///library.json")))
        assertFalse("not a file at all", taken(view("https://example.com/deck.csv")))
    }

    @Test fun theAppsOwnProvidersAreRefused() {
        assertFalse(taken(view("content://$own.fileprovider/files/library.json")))
        assertFalse("for another user", taken(view("content://0@$own.fileprovider/files/library.json")))
        assertFalse("whatever its case", taken(view("content://COM.STETHOSCORE.APP.fileprovider/files/library.json")))
        assertFalse(taken(view("content://$own.androidx-startup/x")))
        // an own provider under a name of its own is found by the package that declares it
        shadowOf(context.packageManager).addOrUpdateProvider(ProviderInfo().apply {
            authority = "stethoscore.files"; packageName = own; name = "$own.Files"
        })
        assertTrue(IncomingFiles.owns(context, "stethoscore.files"))
        assertFalse(taken(view("content://stethoscore.files/library.json")))
        // the same kind of name declared by another app is another app's
        shadowOf(context.packageManager).addOrUpdateProvider(ProviderInfo().apply {
            authority = "notes.files"; packageName = "org.example.notes"; name = "org.example.notes.Files"
        })
        assertFalse(IncomingFiles.owns(context, "notes.files"))
        assertTrue(taken(view("content://notes.files/deck.csv")))
        assertFalse("a name that only starts like the package", IncomingFiles.owns(context, "${own}x.files"))
    }

    @Test fun nothingCarriedIsNothingTaken() {
        IncomingFiles.take(Intent(Intent.ACTION_MAIN), context)
        IncomingFiles.take(Intent(Intent.ACTION_VIEW), context)
        IncomingFiles.take(null, context)
        assertTrue(IncomingFiles.waiting.isEmpty())
        assertEquals(0, IncomingFiles.refused)
    }

    @Test fun theLibrarySaysWhyOnce() {
        IncomingFiles.take(view("file:///data/user/0/$own/files/library.json"), context)
        IncomingFiles.take(send("content://$own.fileprovider/x.csv"), context)
        assertEquals(2, IncomingFiles.refused)
        val store = StudyStore(folder.newFolder("host"))
        compose.setContent { StethoscoreTheme { IncomingImportHost(store, busy = false, onChanged = {}) } }
        compose.waitForIdle()
        compose.onNodeWithText("Couldn’t open this file").assertExists()
        compose.onNodeWithText("Stethoscore can’t safely open a file sent this way. Share it from a files app instead.").assertExists()
        assertEquals("told, so not told again", 0, IncomingFiles.refused)
        compose.onNodeWithText("Done").performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Couldn’t open this file").assertDoesNotExist()
    }

    @Test fun aRefusalWaitsWhileTheScreenIsBusy() {
        IncomingFiles.take(view("file:///sdcard/Download/deck.csv"), context)
        val store = StudyStore(folder.newFolder("busy"))
        compose.setContent { StethoscoreTheme { IncomingImportHost(store, busy = true, onChanged = {}) } }
        compose.waitForIdle()
        compose.onNodeWithText("Couldn’t open this file").assertDoesNotExist()
        assertEquals(1, IncomingFiles.refused)
    }
}
