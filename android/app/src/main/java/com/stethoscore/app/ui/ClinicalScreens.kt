package com.stethoscore.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.wardDp

@Composable
fun ClinicalScreen(set: StudySet, store: StudyStore, onBack: () -> Unit) {
    when (set.kind) {
        StudySetKind.OSCE -> com.stethoscore.app.ui.osce.OsceReviewScreen(set, store, onBack)
        StudySetKind.BOOK -> com.stethoscore.app.ui.book.BookReaderScreen(set, store, onBack)
        StudySetKind.NARRATE -> com.stethoscore.app.ui.narrate.NarrateReviewScreen(set, store, onBack)
        StudySetKind.CASES -> com.stethoscore.app.ui.cases.CaseListScreen(set, store, onBack)
        else -> Column(Modifier.fillMaxSize().padding(WardSpace.gutter.wardDp)) {
            ScreenHeader(set.name, set.kind.label, onBack)
            Text("Open this set from the library to start a review.")
        }
    }
}
