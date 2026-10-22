package com.stethoscore.app.ui.sources

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Article
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.reading.sourceKind
import com.stethoscore.app.ui.modeIcon
import com.stethoscore.app.ui.ward.*

// A port of ios/RedPen/Features/Sources/SourcesLibraryView.swift (fed0105):
// every lecture in the library, whichever sets it went into - and, before
// there are any, a clear way to add the first one. Adding a lecture is the
// screen's one main button: at the bottom under the thumb on a phone, in the
// bar with its name on a wide screen. Holding a lecture lists every set made
// from it, to read it beside that set's cards.

/** One lecture, once, with the sets made from it. */
data class SourceEntry(val source: SourceDoc, val sets: List<StudySet>) {
    val id: String get() = source.fileBlob ?: "${source.name}|${source.pages.size}"
}

object SourcesLibrary {
    /** Every lecture once, newest first, with the sets made from it in library order. */
    fun entries(library: List<StudySet>): List<SourceEntry> {
        val byId = LinkedHashMap<String, SourceEntry>()
        for (set in library) for (source in set.sources) {
            val entry = SourceEntry(source, listOf(set))
            val known = byId[entry.id]
            byId[entry.id] = if (known == null) entry else known.copy(sets = known.sets + set)
        }
        return byId.values.sortedByDescending { it.source.addedAt }
    }

    /** "PDF · 12 pages · 2 sets". */
    fun detail(entry: SourceEntry): String {
        val kind = entry.source.sourceKind
        val pages = entry.source.pages.size
        val length = "$pages ${kind.pageNoun.lowercase()}${if (pages == 1) "" else "s"}"
        val sets = entry.sets.size
        val made = "$sets set${if (sets == 1) "" else "s"}"
        return "${kind.label} · $length · $made"
    }
}

/** A lecture to read, beside the cards of one of its sets. */
private data class SourceOpen(val source: SourceDoc, val set: StudySet?)

@Composable fun SourcesLibraryScreen(store: StudyStore, onBack: () -> Unit, onAdd: () -> Unit) {
    val all = remember(store.library) { SourcesLibrary.entries(store.library) }
    var opening by remember { mutableStateOf<SourceOpen?>(null) }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val broad = isBroad(maxWidth)
        Column(Modifier.fillMaxSize()) {
            ReaderNavBar("Sources", leading = { ReaderBackButton(onBack) }, trailing = {
                // a wide screen has the room for the words, at the top; the empty screen has its own big button
                if (broad && all.isNotEmpty()) WardButtonBox(onAdd, kind = WardButtonKind.compact, fills = false) {
                    Icon(Icons.Rounded.Add, null, Modifier.size(18.dp)); Text("Add a lecture")
                }
            })
            if (all.isEmpty()) {
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    WardEmptyState(Icons.AutoMirrored.Rounded.Article, "No sources yet",
                        "Lectures, slides and notes you make sets from appear here, to read again page by page.") {
                        WardTextButton("Add a lecture", onAdd, kind = WardButtonKind.primary)
                    }
                }
            } else {
                LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)) {
                    items(all, key = { it.id }) { entry -> SourceRow(entry) { set -> opening = SourceOpen(entry.source, set) } }
                }
                if (!broad) StudyActionBar {
                    WardButtonBox(onAdd, kind = WardButtonKind.primary) {
                        Icon(Icons.Rounded.Add, null, Modifier.size(20.dp)); Text("Add a lecture", maxLines = 1)
                    }
                }
            }
        }
    }
    opening?.let { open -> SourcePreviewSheet(open.source, open.set, 1) { opening = null } }
}

/** One lecture: its kind, its name, how long it is and how many sets came from it; held, the sets made from it. */
@OptIn(ExperimentalFoundationApi::class)
@Composable private fun SourceRow(entry: SourceEntry, open: (StudySet?) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Box(Modifier.fillMaxWidth()
            .combinedClickable(role = Role.Button, onLongClickLabel = "Made from it", onLongClick = { menu = true }) { open(entry.sets.firstOrNull()) }
            .semantics { testTag = "source-row" }
            .wardRowTile()) {
            WardRowItem(kindIcon(entry.source.sourceKind), entry.source.name, SourcesLibrary.detail(entry), chevron = false)
        }
        DropdownMenu(menu, { menu = false }) {
            DropdownMenuItem(text = { Text("Read") }, leadingIcon = { Icon(Icons.AutoMirrored.Rounded.MenuBook, null) },
                onClick = { menu = false; open(entry.sets.firstOrNull()) })
            HorizontalDivider()
            WardSmallCapsText("Made from it", Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
            entry.sets.forEach { set ->
                DropdownMenuItem(text = { Text(set.name) }, leadingIcon = { Icon(modeIcon(set.kind), null) },
                    onClick = { menu = false; open(set) })
            }
        }
    }
}
