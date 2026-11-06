package com.stethoscore.app

import android.app.Activity
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
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
import com.stethoscore.app.widget.WidgetUpdates
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Home's ground for the section home opens on, in the app's own mode,
        // from the first frame the app draws: the starting window's colour
        // (the theme's ward_ground) with home's grid over it, so nothing
        // changes when home draws over it. The bars go edge to edge in that
        // mode too (showBars).
        val dark = getSharedPreferences("appearance", Context.MODE_PRIVATE).getBoolean("dark", false)
        showGround(this, dark)
        // the process's one library: a recreated activity (a rotation) shares it
        val store = ProcessStore.get(this)
        // a table or a backup opened from another app waits for the library to show it;
        // like a link, a file is taken once, never again from a restore or from Recents
        val first = firstIntent(intent, restored = savedInstanceState != null)
        if (first != null && !AppLink.isLink(first)) IncomingFiles.take(first, this)
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

    override fun onStart() {
        super.onStart()
        // back in front: the widgets catch up with what changed meanwhile (the day, cards come due)
        WidgetUpdates.republish(ProcessStore.get(this))
    }

    override fun onStop() {
        super.onStop()
        // to the background, where the process may be ended: the ratings and answers
        // still waiting for the library's writer reach the disk first
        ProcessStore.get(this).flush()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // a later getIntent() sees this intent, not the one that first started the activity
        setIntent(intent)
        if (!AppLink.isLink(intent)) IncomingFiles.take(intent, this)
        // a link while the app is open goes to the app on screen (iOS AppRouter.open)
        AppLink.from(intent)?.let { AppLinks.pending = it }
    }

    companion object {
        /**
         * The intent a starting activity acts on: none when it was restored
         * from saved state, or reopened from Recents (the system hands back
         * the intent that first started the task, so its link or its file
         * would play again).
         */
        internal fun firstIntent(intent: Intent?, restored: Boolean): Intent? {
            if (restored || intent == null) return null
            if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
            return intent
        }

        /** The link a starting activity follows: [firstIntent]'s, if it is one. */
        internal fun coldLink(intent: Intent?, restored: Boolean): AppLink? = AppLink.from(firstIntent(intent, restored))

        /** androidx.activity's own scrims for a three-button navigation bar before Android 10 (EdgeToEdge.kt). */
        private val lightScrim = Color.argb(0xe6, 0xFF, 0xFF, 0xFF)
        private val darkScrim = Color.argb(0x80, 0x1b, 0x1b, 0x1b)

        /**
         * Edge to edge in the app's own mode, [dark], not the system's: dark
         * icons in light, light icons in dark; the status bar clear; the
         * navigation bar clear from Android 10 (the system's scrim follows the
         * icons) and on a scrim of that mode before it. enableEdgeToEdge()
         * alone reads the system's mode, which matches the app's only from
         * Android 12 (showGround sets it).
         */
        fun showBars(activity: ComponentActivity, dark: Boolean) {
            activity.enableEdgeToEdge(
                statusBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT) { dark },
                navigationBarStyle = SystemBarStyle.auto(lightScrim, darkScrim) { dark })
        }

        /**
         * Sets the window's background to home's ground in [dark] and the bars
         * to it (showBars), and from Android 12 tells the system the app's
         * mode, so the next starting window (ward_ground, light or night) is
         * in it too. Called at the start and whenever Settings changes the mode.
         */
        fun showGround(activity: Activity, dark: Boolean) {
            (activity as? ComponentActivity)?.let { showBars(it, dark) }
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
        // each new digest updates the home-screen widgets, from the store's first one on
        WidgetUpdates.install(app)
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
