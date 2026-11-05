package com.stethoscore.app

import android.app.Activity
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.stethoscore.app.data.DailyGoal
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.exam.ExamChoice
import com.stethoscore.app.exam.ExamDefaults
import com.stethoscore.app.llm.CloudJobCollector
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.WardGroundDrawable
import com.stethoscore.app.ui.library.IncomingFiles
import com.stethoscore.app.ui.ward.WardGround
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Home's ground for the section home opens on, in the app's own mode,
        // from the first frame the app draws: the starting window's colour
        // (the theme's ward_ground) with home's grid over it, so nothing
        // changes when home draws over it.
        val dark = getSharedPreferences("appearance", Context.MODE_PRIVATE).getBoolean("dark", false)
        showGround(this, dark)
        // the process's one library: a recreated activity (a rotation) shares it
        val store = ProcessStore.get(this)
        // a table or a backup opened from another app waits for the library to show it
        if (savedInstanceState == null && !AppLink.isLink(intent)) IncomingFiles.take(intent)
        // a stethoscore:// link (a widget's tap): the due queue opens as the first
        // screen, the others once the app is up; a recreated activity, or one
        // reopened from Recents, has had it
        val link = coldLink(intent, restored = savedInstanceState != null)
        // a learning sheet left open in this process would cover the due screen (as StethoscoreApp's link effect)
        if (link == AppLink.ReviewDue) com.stethoscore.app.ui.learn.LearnRouter.close()
        if (link != null && link != AppLink.ReviewDue) AppLinks.pending = link
        // cloud jobs finished while the app was closed become sets (iOS RedPenApp)
        CloudJobCollector.start(this, store)
        setContent { StethoscoreApp(store, initialScreen = AppLink.initialScreen(link)) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (!AppLink.isLink(intent)) IncomingFiles.take(intent)
        // a link while the app is open goes to the app on screen (iOS AppRouter.open)
        AppLink.from(intent)?.let { AppLinks.pending = it }
    }

    companion object {
        /**
         * The link a starting activity follows: none when it was restored from
         * saved state, or reopened from Recents (the system hands back the
         * intent that first started the task, so its link would play again).
         */
        internal fun coldLink(intent: Intent?, restored: Boolean): AppLink? {
            if (restored || intent == null) return null
            if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
            return AppLink.from(intent)
        }

        /**
         * Sets the window's background to home's ground in [dark], and from
         * Android 12 tells the system the app's mode, so the next starting
         * window (ward_ground, light or night) is in it too.
         */
        fun showGround(activity: Activity, dark: Boolean) {
            activity.window.setBackgroundDrawable(
                WardGroundDrawable(WardGround.home(dark = dark), activity.resources.displayMetrics.density))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = activity.getSystemService(UiModeManager::class.java) ?: return
                val mode = if (dark) UiModeManager.MODE_NIGHT_YES else UiModeManager.MODE_NIGHT_NO
                // only on a change: a new mode is a configuration change
                val night = activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
                val shown = night == Configuration.UI_MODE_NIGHT_YES
                if (shown != dark) runCatching { manager.setApplicationNightMode(mode) }
            }
        }
    }
}

/**
 * Holds the process's one [StudyStore]. Two stores over the same files would
 * overwrite each other's saves, so every activity, and the cloud collector it
 * starts, uses this one.
 */
object ProcessStore {
    @Volatile private var store: StudyStore? = null

    /**
     * The app's store, with the settings the widgets' digest reads: the chosen
     * exam (ExamChoice.defaults) and the daily goal, both in the "appearance"
     * preferences, as iOS reads them from UserDefaults.
     */
    fun get(context: Context): StudyStore {
        val app = context.applicationContext
        return get(app.filesDir, ExamChoice.defaults(app),
            DailyGoal.PrefsStore(app.getSharedPreferences("appearance", Context.MODE_PRIVATE)))
    }

    /**
     * The store over [directory], made on the first call only. [goals] is
     * handed to DailyGoal before the store's first digest, and [exam] to the
     * store, which writes the digest again with the exam's name.
     */
    internal fun get(directory: File, exam: ExamDefaults? = null, goals: DailyGoal.Store? = null): StudyStore =
        store ?: synchronized(this) {
            store ?: run {
                goals?.let { DailyGoal.store = it }
                StudyStore(directory).also { made -> exam?.let { made.examDefaults = it }; store = made }
            }
        }

    /** Lets a test start from no store. */
    internal fun forget() { synchronized(this) { store = null } }
}
