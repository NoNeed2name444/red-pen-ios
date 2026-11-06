package com.stethoscore.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.DailyGoal
import com.stethoscore.app.exam.ExamChoice
import com.stethoscore.app.quiz.ExamTrack
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The app's store reads the digest's exam and goal from what Settings and the
 * exam picker stored (the "appearance" preferences), not the defaults (T0193's gaps).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ProcessStoreSettingsTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val prefs get() = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
    private val farOff = java.time.Instant.parse("2099-01-01T00:00:00Z").toEpochMilli()
    private var goalsBefore: DailyGoal.Store? = null

    @Before fun setUp() {
        goalsBefore = DailyGoal.store
        ProcessStore.forget()
        context.filesDir.listFiles()?.forEach { it.deleteRecursively() }
        prefs.edit().clear().commit()
    }

    @After fun tearDown() {
        ProcessStore.forget()
        goalsBefore?.let { DailyGoal.store = it }
        prefs.edit().clear().commit()
    }

    @Test fun theDigestCarriesTheChosenExamAndGoal() {
        prefs.edit().putString(ExamTrack.storageKey, ExamTrack.usmle.rawValue).putString(ExamChoice.primaryKey, "step1")
            .putInt(DailyGoal.key, 120).commit()
        val store = ProcessStore.get(context)
        assertEquals(120, store.glanceShelf.read()!!.goal)
        // the digest names the exam only beside its date
        store.setExamDate(farOff); store.flush()  // a background save is written off the calling thread: wait for it
        val digest = store.glanceShelf.read()!!
        assertEquals("Step 1", digest.examName)
        assertEquals(120, digest.goal)
        assertEquals(120, DailyGoal.current)
    }

    @Test fun aGoalChosenLaterReachesTheNextDigest() {
        val store = ProcessStore.get(context)
        store.setExamDate(farOff); store.flush()  // a background save is written off the calling thread: wait for it
        assertEquals("nothing chosen: 50", 50, store.glanceShelf.read()!!.goal)
        assertNull("general revision has no name", store.glanceShelf.read()!!.examName)
        DailyGoal.current = 80
        assertEquals("kept where Settings keeps it", 80, prefs.getInt(DailyGoal.key, 0))
        prefs.edit().putString(ExamTrack.storageKey, ExamTrack.plab.rawValue).commit()
        store.publishGlance()
        assertEquals(80, store.glanceShelf.read()!!.goal)
        assertEquals("PLAB 1", store.glanceShelf.read()!!.examName)
    }
}
