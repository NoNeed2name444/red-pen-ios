package com.stethoscore.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiRating
import com.stethoscore.app.data.LibraryWriter
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

// Going to the background (onStop) puts the ratings still waiting for the
// library's writer on disk, as the process may be ended there (T0210).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class MainActivityStopTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Before @After fun fresh() {
        LibraryWriter.of(context.filesDir).beforeWrite = null
        ProcessStore.forget()
        context.filesDir.listFiles()?.forEach { it.deleteRecursively() }
    }

    @Test fun stoppingWritesWhatIsWaiting() {
        Robolectric.buildActivity(MainActivity::class.java).create().start().resume().use { activity ->
            val store = ProcessStore.get(context)
            store.addSet(StudySet(id = "deck", name = "Renal", kind = StudySetKind.ANKI, cards = listOf(AnkiCard(id = "c1", front = "Q", bullets = listOf("A")))))
            // a slow disk: the rating's write is still running when the app goes to the background
            LibraryWriter.of(context.filesDir).beforeWrite = { Thread.sleep(500) }
            store.rateCard(store.library.single().cards.single(), AnkiRating.EASY)
            val file = File(context.filesDir, "stethoscore.json")
            assertFalse("not written yet", JSONObject(file.readText()).getJSONObject("reviews").has("c1"))
            activity.pause().stop()
            assertTrue("on disk once onStop returns", JSONObject(file.readText()).getJSONObject("reviews").has("c1"))
        }
    }
}
