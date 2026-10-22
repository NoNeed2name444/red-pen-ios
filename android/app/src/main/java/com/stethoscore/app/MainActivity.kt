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
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.WardGroundDrawable
import com.stethoscore.app.ui.library.IncomingFiles
import com.stethoscore.app.ui.ward.WardGround

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
        val store = StudyStore(filesDir)
        // a table or a backup opened from another app waits for the library to show it
        if (savedInstanceState == null) IncomingFiles.take(intent)
        setContent { StethoscoreApp(store) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        IncomingFiles.take(intent)
    }

    companion object {
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
