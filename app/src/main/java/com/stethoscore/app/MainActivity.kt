package com.stethoscore.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val store = StudyStore(filesDir)
        setContent { StethoscoreApp(store) }
    }
}
