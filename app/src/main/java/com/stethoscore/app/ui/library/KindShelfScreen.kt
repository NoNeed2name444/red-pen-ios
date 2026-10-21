package com.stethoscore.app.ui.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.modeIcon
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.wardRaised

// iOS Features/Library/CategoryShelves.swift, KindShelfView: every set of one
// kind, newest first, and at the bottom, under the thumb, "Continue" on the
// newest with "New" beside it.

@Composable fun KindShelfScreen(feature: CategoryFeature, store: StudyStore, revision: Int, onBack: () -> Unit,
                                onOpen: (StudySet) -> Unit, onNew: (StudySetKind) -> Unit) {
    val kind = feature.shelfKind ?: StudySetKind.MCQ
    val sets = remember(revision, feature) { feature.shelfSets(store.library) }
    val heading = if (sets.size == 1) "Your set" else "All ${sets.size}"
    Column(Modifier.fillMaxSize()) {
        LibraryPageTop(feature.title, onBack)
        LazyColumn(Modifier.weight(1f).fillMaxWidth().widthIn(max = 760.dp), contentPadding = PaddingValues(20.dp, 8.dp, 20.dp, 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { LibraryHeading(heading, Modifier.padding(horizontal = 4.dp)) }
            if (sets.isEmpty()) item { LibraryEmptyState(modeIcon(kind), "None yet", "Tap New to make one.") }
            items(sets, key = { it.id }) { set ->
                val due = remember(revision, set) { if (set.kind == StudySetKind.ANKI) store.dueCards(set).size else 0 }
                LibrarySetRow(set, due, null, Modifier.fillMaxWidth().wardRaised(WardRadius.card, WardLift.low)
                    .clickable(role = Role.Button) { onOpen(set) }.padding(horizontal = 20.dp, vertical = 10.dp))
            }
        }
        LibraryStudyBar {
            // New at the leading end; the hero, carry on with the newest set, at the trailing end
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                WardButtonBox({ onNew(kind) }, Modifier.semantics { contentDescription = "New ${feature.newNoun}" },
                    kind = WardButtonKind.secondary, fills = sets.isEmpty()) {
                    Icon(Icons.Rounded.Add, null, Modifier.size(18.dp)); Text("New")
                }
                sets.firstOrNull()?.let { newest ->
                    WardButtonBox({ onOpen(newest) }, Modifier.weight(1f), kind = WardButtonKind.primary) {
                        Icon(Icons.Rounded.PlayArrow, null, Modifier.size(18.dp))
                        Text("Continue: ${newest.name}", maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}
