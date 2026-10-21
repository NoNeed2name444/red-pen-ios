package com.stethoscore.app.ui

import androidx.compose.runtime.Composable
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.ideas.IdeasView

/** Ideas: the idea dump, its board and its space (ui/ideas, a port of iOS Features/Notes). */
@Composable fun IdeasScreen(store: StudyStore, onBack: () -> Unit) = IdeasView(store, onBack)
