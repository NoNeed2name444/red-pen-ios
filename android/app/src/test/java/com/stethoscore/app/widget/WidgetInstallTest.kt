package com.stethoscore.app.widget

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.ProcessStore
import com.stethoscore.app.data.DailyGoal
import com.stethoscore.app.data.StudyStore
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The app's store hands every new digest to the widgets: ProcessStore installs the hook before it makes the store. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WidgetInstallTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private var goalsBefore: DailyGoal.Store? = null

    @Before fun setUp() {
        goalsBefore = DailyGoal.store
        ProcessStore.forget()
        StudyStore.onAnyGlanceWritten = null
    }

    @After fun tearDown() {
        ProcessStore.forget()
        StudyStore.onAnyGlanceWritten = null
        goalsBefore?.let { DailyGoal.store = it }
    }

    @Test fun theProcessStoreInstallsTheWidgetHook() {
        assertNull(StudyStore.onAnyGlanceWritten)
        ProcessStore.get(context)
        assertNotNull(StudyStore.onAnyGlanceWritten)
    }
}
