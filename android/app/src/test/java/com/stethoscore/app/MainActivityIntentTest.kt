package com.stethoscore.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.ui.library.IncomingFiles
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// What MainActivity does with the intents it is handed: the keyboard resizes
// its window, a file is taken once (never again from a restore or from
// Recents), and a new intent becomes the activity's own.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class MainActivityIntentTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val shared = Uri.parse("content://com.android.providers.downloads.documents/document/7")

    @Before @After fun fresh() {
        ProcessStore.forget()
        context.filesDir.listFiles()?.forEach { it.deleteRecursively() }
        IncomingFiles.waiting.clear()
        IncomingFiles.refused = 0
        AppLinks.pending = null
    }

    private fun opened(uri: Uri = shared) = Intent(Intent.ACTION_VIEW, uri).setClass(context, MainActivity::class.java)

    // Without adjustResize, on Android 8 to 10 (API 26 to 29) the keyboard pans
    // the window and never reaches Compose as insets, so imePadding() adds
    // nothing and isImeVisible stays false (the home bar rides over the results).
    @Test fun theKeyboardResizesTheWindow() {
        val info = context.packageManager.getActivityInfo(ComponentName(context, MainActivity::class.java), 0)
        assertEquals("windowSoftInputMode adjust", WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE,
            info.softInputMode and WindowManager.LayoutParams.SOFT_INPUT_MASK_ADJUST)
    }

    @Test fun aFileOpenedWithTheAppWaitsForTheLibrary() {
        Robolectric.buildActivity(MainActivity::class.java, opened()).create().use {
            assertEquals(listOf(shared), IncomingFiles.waiting.toList())
        }
    }

    @Test fun reopenedFromRecentsTheFileIsNotTakenAgain() {
        val fromRecents = opened().addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)
        Robolectric.buildActivity(MainActivity::class.java, fromRecents).create().use {
            assertTrue("the share is not replayed", IncomingFiles.waiting.isEmpty())
            assertEquals(0, IncomingFiles.refused)
        }
        assertNull(MainActivity.firstIntent(fromRecents, restored = false))
    }

    @Test fun restoredTheFileIsNotTakenAgain() {
        Robolectric.buildActivity(MainActivity::class.java, opened()).create(Bundle()).use {
            assertTrue(IncomingFiles.waiting.isEmpty())
        }
    }

    @Test fun aPathIntoTheAppIsRefusedAtTheStart() {
        val path = Uri.parse("file:///data/user/0/com.stethoscore.app/files/library.json")
        Robolectric.buildActivity(MainActivity::class.java, opened(path)).create().use {
            assertTrue(IncomingFiles.waiting.isEmpty())
            assertEquals(1, IncomingFiles.refused)
        }
    }

    @Test fun aNewIntentBecomesTheActivitysOwn() {
        Robolectric.buildActivity(MainActivity::class.java, Intent(context, MainActivity::class.java)).create().use { controller ->
            val due = Intent(Intent.ACTION_VIEW, Uri.parse("stethoscore://due")).setClass(context, MainActivity::class.java)
            controller.newIntent(due)
            assertSame("getIntent() sees the new one", due, controller.get().intent)
            assertEquals(AppLink.ReviewDue, AppLinks.pending)
            assertTrue("a link is not a file", IncomingFiles.waiting.isEmpty())
            val file = opened()
            controller.newIntent(file)
            assertSame(file, controller.get().intent)
            assertEquals(listOf(shared), IncomingFiles.waiting.toList())
        }
    }
}
