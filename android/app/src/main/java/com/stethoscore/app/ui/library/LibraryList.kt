package com.stethoscore.app.ui.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.GpsFixed
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.LooksOne
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.Inbox
import androidx.compose.material.icons.rounded.Download
import androidx.compose.ui.draw.rotate
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.LibrarySearch
import com.stethoscore.app.data.LibraryStats
import com.stethoscore.app.data.StudyFolder
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.modeIcon
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardChipButton
import com.stethoscore.app.ui.ward.WardIconSquare
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTile
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardRaised
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

// The library's list on home (iOS LibraryView, LibraryRows,
// LibrarySearchResults and LibraryCategory): the sets of the chosen
// category, loose and in folders, each with its menu; picking several to
// move, mix, combine or delete; the search's scope chips and results; Build
// a session; and the category's tiles. Home's own parts (its header, the
// ward round, the dock) are WardHome's, in ui/home and StethoscoreApp.

/** What the library is doing that outlives one frame: picking sets, a menu, a sheet. */
@Stable class LibraryState {
    var selecting by mutableStateOf(false)
    var selected by mutableStateOf(setOf<String>())
    /** The set whose menu is open, and whether it shows its folders. */
    var menuFor by mutableStateOf<String?>(null)
    var menuFolders by mutableStateOf(false)
    var folderMenu by mutableStateOf<String?>(null)
    var naming by mutableStateOf<Naming?>(null)
    var pendingDelete by mutableStateOf<List<String>?>(null)
    var scope by mutableStateOf(LibrarySearch.Scope.ALL)
    /** Build a session, with the words it starts from. */
    var session by mutableStateOf<String?>(null)
    var foundCard by mutableStateOf<Pair<StudySet, AnkiCard>?>(null)
    var nothingYet by mutableStateOf<CategoryFeature?>(null)
    var morePractise by mutableStateOf(false)
    var moveMenu by mutableStateOf(false)

    fun stopSelecting() { selecting = false; selected = emptySet() }
    fun toggle(id: String) { selected = if (id in selected) selected - id else selected + id }
}

/** Which name sheet is up (iOS NamingSheet, renaming and renamingFolder). */
sealed class Naming {
    data class RenameSet(val id: String, val name: String) : Naming()
    data class RenameFolder(val id: String, val name: String) : Naming()
    object NewFolder : Naming()
    object Combine : Naming()
}

/** What the library asks of the app around it. */
class LibraryActions(
    val open: (StudySet) -> Unit,
    val quiz: (LibraryQuiz) -> Unit,
    /** A custom session's cards, reviewed where they live. */
    val review: (StudySet) -> Unit,
    val newSet: (StudySetKind) -> Unit,
    val shelf: (CategoryFeature) -> Unit,
    val stats: () -> Unit,
    /** Cards due today (iOS showingDue). */
    val due: () -> Unit,
    val ideas: () -> Unit,
    val exportPdf: (StudySet) -> Unit,
    val shareJson: (StudySet) -> Unit,
    /** A library change: a failed save is shown, never a crash. */
    val change: (() -> Unit) -> Unit,
    /** Edit cards or Edit questions (batch 6's editors), for the kinds that have one. */
    val edit: ((StudySet) -> Unit)? = null,
)

/** The search's answer for the words typed, worked out off the main thread (iOS LibrarySearchModel). */
data class LibrarySearchState(val results: LibrarySearch.Results = LibrarySearch.Results(), val busy: Boolean = false)

@Composable fun rememberLibrarySearch(store: StudyStore, revision: Int, query: String, scope: LibrarySearch.Scope): LibrarySearchState {
    val trimmed = query.trim()
    val index by produceState(LibrarySearch.Index(), revision, store.library, store.notes) {
        value = withContext(Dispatchers.Default) {
            LibrarySearch.build(store.library, store.notes.map { LibrarySearch.NoteText(it.id, it.title, it.body, it.tags) })
        }
    }
    val state by produceState(LibrarySearchState(), trimmed, scope, index) {
        if (trimmed.isEmpty()) { value = LibrarySearchState(); return@produceState }
        value = value.copy(busy = true)
        delay(150)
        val found = withContext(Dispatchers.Default) { LibrarySearch.search(trimmed, index, scope) }
        value = LibrarySearchState(found, busy = false)
    }
    return state
}

/** The sets a category shows; while searching, every set that matched, name matches first. */
fun shownSets(store: StudyStore, category: StudyCategory, searching: Boolean, search: LibrarySearchState): List<StudySet> {
    if (!searching) return store.library.filter { it.kind in category.kinds }
    val order = search.results.sets.withIndex().associate { it.value to it.index }
    return store.library.filter { it.id in order }.sortedBy { order[it.id] ?: 0 }
}

/**
 * The library's part of home's list. [rowModifier] lets home tag each row
 * for its book of parts (HomePartBook) without the library knowing about it.
 */
fun LazyListScope.libraryItems(
    store: StudyStore, revision: Int, category: StudyCategory, query: String, search: LibrarySearchState,
    state: LibraryState, actions: LibraryActions,
    rowModifier: @Composable (StudySet) -> Modifier = { Modifier },
    /** False where the screen shows its own empty library. */
    showsEmpty: Boolean = true,
) {
    val searching = query.isNotBlank()
    val shown = shownSets(store, category, searching, search)
    val filed = store.folders.map { it.id }.toSet()
    val loose = shown.filter { set -> set.folderId?.let { it !in filed } ?: true }
    if (showsEmpty && store.library.isEmpty() && store.loadError == null) {
        item(key = "library-empty") { LibraryEmpty(category, actions) }
    }
    if (searching) item(key = "search-scope") { SearchScopeChips(state) }
    if (!searching && category.kinds.size > 1) tileSection(FeatureGroup.MODES, category, store, state, actions)
    if (!searching || state.scope == LibrarySearch.Scope.ALL) {
        if (shown.isEmpty() && searching && search.results.items.isEmpty() && !search.busy) {
            item(key = "no-results") {
                LibraryEmptyState(Icons.Rounded.Search, "No results for “${query.trim()}”", "Check the spelling or try a new search.")
            }
        } else if (shown.isEmpty() && !searching && store.library.isNotEmpty()) {
            item(key = "sets-heading-empty") { LibraryHeading(category.setsHeading) }
            item(key = "sets-empty") { EmptyCategoryRow(category, actions) }
        }
        if (loose.isNotEmpty()) {
            item(key = "sets-heading") { SetsHeader(if (searching) "Sets" else category.setsHeading, searching, category, store, state, actions) }
            items(loose, key = { "set-" + it.id }) { set -> Box(rowModifier(set)) { LibraryRow(set, store, revision, state, actions) } }
        }
        for (folder in store.folders) {
            val inside = shown.filter { it.folderId == folder.id }
            if (inside.isEmpty()) continue
            item(key = "folder-" + folder.id) { FolderHeader(folder, store, state, actions) }
            items(inside, key = { "set-" + it.id }) { set -> Box(rowModifier(set)) { LibraryRow(set, store, revision, state, actions) } }
        }
    }
    if (searching) searchItems(query.trim(), store, search, state, actions)
    if (!searching) {
        if (category == StudyCategory.QUESTIONS || category == StudyCategory.CARDS) item(key = "build-session") { BuildSessionTile { state.session = "" } }
        practiseSection(category, store, state, actions)
        tileSection(FeatureGroup.TOOLS, category, store, state, actions)
    }
}

// MARK: - Empty

/** An empty library (iOS LibraryRows.emptyState): one sentence, New set, and two quiet links. */
@Composable private fun LibraryEmpty(category: StudyCategory, actions: LibraryActions) {
    Column(Modifier.fillMaxWidth().padding(vertical = WardSpace.xl.wardDp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(WardSpace.l.wardDp)) {
        Row(horizontalArrangement = Arrangement.spacedBy((-10).dp), modifier = Modifier.semantics { contentDescription = "" }) {
            listOf(StudySetKind.MCQ to -10f, StudySetKind.ANKI to 0f, StudySetKind.OSCE to 10f).forEach { (kind, angle) ->
                WardIconSquare(modeIcon(kind), Modifier.rotate(angle), tone = WardTone.Blue, size = 52.0)
            }
        }
        Text("Make your first set", style = WardTextStyle.title3.textStyle(WardWeight.bold), color = wardColor(WardToken.ink))
        Text("Add a lecture and Stethoscore turns it into questions or flashcards to study.", style = WardTextStyle.subheadline.textStyle(),
            color = wardColor(WardToken.inkSecondary), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        WardButtonBox({ actions.newSet(category.mainKind) }, Modifier.widthIn(max = 280.dp).fillMaxWidth(), fills = false) {
            Icon(Icons.Rounded.Add, null, Modifier.size(18.dp)); Text("New set")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            WardTextButton("Your lectures", { actions.ideas() }, kind = WardButtonKind.quiet, fills = false)
        }
    }
}

/** A category with no sets of its own (iOS emptyCategoryRow). */
@Composable private fun EmptyCategoryRow(category: StudyCategory, actions: LibraryActions) {
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).wardRaised(WardRadius.card, WardLift.low).padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(modeIcon(category.mainKind), null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.width(40.dp).size(24.dp))
        Text(category.emptySets, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary), modifier = Modifier.weight(1f))
        WardTextButton("Make one", { actions.newSet(category.mainKind) }, kind = WardButtonKind.compact, fills = false)
    }
}

// MARK: - Headers

@Composable private fun HeaderButton(title: String, onClick: () -> Unit) {
    Box(Modifier.heightIn(min = WardControlSize.target.wardDp).widthIn(min = WardControlSize.target.wardDp).clickable(role = Role.Button, onClick = onClick), contentAlignment = Alignment.Center) {
        Text(title, style = WardTextStyle.footnote.textStyle(WardWeight.semibold), color = wardColor(WardToken.primaryInk), maxLines = 1)
    }
}

/** Over the loose sets: the heading, "See all" for a one-kind category, and Select or Done (iOS setsHeader). */
@Composable private fun SetsHeader(title: String, searching: Boolean, category: StudyCategory, store: StudyStore, state: LibraryState, actions: LibraryActions) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        LibraryHeading(title)
        Spacer(Modifier.weight(1f))
        if (!searching && category.kinds.size == 1) {
            val mode = category.features(FeatureGroup.MODES).firstOrNull()
            if (mode != null && mode.shelfSets(store.library).isNotEmpty()) HeaderButton("See all") { actions.shelf(mode) }
        }
        HeaderButton(if (state.selecting) "Done" else "Select") {
            val now = !state.selecting
            state.stopSelecting(); state.selecting = now
        }
    }
}

/** A folder's heading, with its menu: Select sets, Rename folder, Ungroup (iOS folderSection). */
@Composable private fun FolderHeader(folder: StudyFolder, store: StudyStore, state: LibraryState, actions: LibraryActions) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(Icons.Rounded.Folder, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
        WardSmallCapsText(folder.name, Modifier.weight(1f))
        Box {
            LibraryMoreFace("Folder options", { state.folderMenu = folder.id })
            DropdownMenu(state.folderMenu == folder.id, { state.folderMenu = null }, containerColor = wardColor(WardToken.raised)) {
                DropdownMenuItem({ Text("Select sets") }, { state.folderMenu = null; state.selecting = true; state.selected = emptySet() },
                    leadingIcon = { Icon(Icons.Rounded.CheckCircle, null) })
                DropdownMenuItem({ Text("Rename folder") }, { state.folderMenu = null; state.naming = Naming.RenameFolder(folder.id, folder.name) })
                DropdownMenuItem({ Text("Ungroup") }, { state.folderMenu = null; actions.change { store.ungroup(folder.id) } })
            }
        }
    }
}

// MARK: - Rows

/**
 * One set's row: opens it normally, ticks it while picking, and its menu
 * behind the ellipsis beside it (iOS LibraryRows.row).
 */
@Composable fun LibraryRow(set: StudySet, store: StudyStore, revision: Int, state: LibraryState, actions: LibraryActions) {
    val due = remember(revision, set) { if (set.kind == StudySetKind.ANKI) store.dueCards(set).size else 0 }
    val progress = remember(revision, set) { LibraryStats.progress(store, set) }
    val tile = Modifier.fillMaxWidth().wardRaised(WardRadius.card, WardLift.low)
    if (state.selecting) {
        val on = set.id in state.selected
        Row(tile.toggleable(on, role = Role.Checkbox) { state.toggle(set.id) }.semantics { selected = on }
            .padding(start = 20.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(if (on) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null,
                tint = wardColor(if (on) WardToken.primaryInk else WardToken.inkSecondary), modifier = Modifier.size(22.dp))
            LibrarySetRow(set, due, progress, Modifier.weight(1f))
        }
    } else {
        Row(tile.padding(start = 20.dp, end = 8.dp, top = 10.dp, bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            LibrarySetRow(set, due, progress, Modifier.weight(1f).clickable(role = Role.Button) { actions.open(set) })
            Box {
                LibraryMoreFace("More for ${set.name}", { state.menuFolders = false; state.menuFor = set.id })
                RowMenu(set, store, state, actions)
            }
        }
    }
}

/** A set's menu (iOS rowMenu), of the actions Android has. */
@Composable private fun RowMenu(set: StudySet, store: StudyStore, state: LibraryState, actions: LibraryActions) {
    val open = state.menuFor == set.id
    fun close() { state.menuFor = null; state.menuFolders = false }
    DropdownMenu(open, ::close, containerColor = wardColor(WardToken.raised)) {
        if (state.menuFolders) {
            store.folders.forEach { folder ->
                DropdownMenuItem({ Text(folder.name) }, { close(); actions.change { store.move(set.id, folder.id) } })
            }
            DropdownMenuItem({ Text("New folder…") }, { close(); state.selected = setOf(set.id); state.naming = Naming.NewFolder })
            if (set.folderId != null) {
                HorizontalDivider()
                DropdownMenuItem({ Text("Remove from folder") }, { close(); actions.change { store.move(set.id, null) } })
            }
        } else {
            DropdownMenuItem({ Text("Select") }, {
                close()
                if (state.selecting) state.selected = state.selected + set.id else { state.selecting = true; state.selected = setOf(set.id) }
            })
            DropdownMenuItem({ Text("Rename") }, { close(); state.naming = Naming.RenameSet(set.id, set.name) })
            if (actions.edit != null && (set.kind == StudySetKind.ANKI || set.kind == StudySetKind.MCQ))
                DropdownMenuItem({ Text(if (set.kind == StudySetKind.MCQ) "Edit questions" else "Edit cards") }, { close(); actions.edit.invoke(set) },
                    leadingIcon = { Icon(Icons.Rounded.Edit, null) })
            DropdownMenuItem({ Text("Move to folder") }, { state.menuFolders = true },
                trailingIcon = { Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null) })
            if (set.kind != StudySetKind.ANKI) DropdownMenuItem({ Text("Export PDF") }, { close(); actions.exportPdf(set) })
            DropdownMenuItem({ Text("Share as JSON") }, { close(); actions.shareJson(set) })
            HorizontalDivider()
            DropdownMenuItem({ Text("Delete", color = wardColor(WardToken.danger)) }, { close(); state.pendingDelete = listOf(set.id) },
                leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = wardColor(WardToken.danger)) })
        }
    }
}

// MARK: - Picking several

/**
 * The bar in the dock's place while picking sets (iOS selectionBar): Done,
 * the count, then Move, Quiz, Combine and Delete.
 */
@Composable fun LibrarySelectionBar(store: StudyStore, state: LibraryState, actions: LibraryActions, modifier: Modifier = Modifier) {
    val chosen = store.library.filter { it.id in state.selected }
    val canMix = chosen.any { it.kind == StudySetKind.MCQ && it.questions.isNotEmpty() }
    val canCombine = chosen.size >= 2 && chosen.map { it.kind }.toSet().size == 1
    val count = state.selected.size
    Row(modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = WardSpace.m.wardDp)
        .wardRaised(WardRadius.bar, WardLift.high).padding(WardSpace.m.wardDp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(WardControlSize.target.wardDp).clickable(role = Role.Button) { state.stopSelecting() }.semantics { contentDescription = "Done" },
            contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Close, null, tint = wardColor(WardToken.ink), modifier = Modifier.size(18.dp))
        }
        Text(if (count == 0) "Select sets" else "$count selected", style = WardType.caption.textStyle().copy(fontWeight = FontWeight.Medium),
            color = wardColor(WardToken.inkSecondary), maxLines = 1, modifier = Modifier.weight(1f))
        Box {
            SelectionAction("Move", Icons.Rounded.Folder, count > 0) { state.moveMenu = true }
            DropdownMenu(state.moveMenu, { state.moveMenu = false }, containerColor = wardColor(WardToken.raised)) {
                store.folders.forEach { folder ->
                    DropdownMenuItem({ Text(folder.name) }, {
                        state.moveMenu = false
                        val ids = state.selected
                        actions.change { ids.forEach { store.move(it, folder.id) } }
                        state.stopSelecting()
                    }, leadingIcon = { Icon(Icons.Rounded.Folder, null) })
                }
                DropdownMenuItem({ Text("New folder…") }, { state.moveMenu = false; state.naming = Naming.NewFolder })
            }
        }
        SelectionAction("Quiz", Icons.Rounded.Shuffle, canMix) {
            LibraryStats.mixedQuiz(chosen)?.let { quiz -> state.stopSelecting(); actions.quiz(LibraryQuiz(quiz)) }
        }
        SelectionAction("Combine", Icons.Rounded.Layers, canCombine) { state.naming = Naming.Combine }
        SelectionAction("Delete", Icons.Rounded.Delete, count > 0, danger = true) { state.pendingDelete = state.selected.toList() }
    }
}

@Composable private fun SelectionAction(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, enabled: Boolean, danger: Boolean = false, onClick: () -> Unit) {
    WardButtonBox(onClick, kind = WardButtonKind.compact, enabled = enabled, fills = false) {
        Icon(icon, title, Modifier.size(18.dp), tint = if (danger && enabled) wardColor(WardToken.danger) else androidx.compose.material3.LocalContentColor.current)
    }
}

/** The library's sheets and questions, wherever the list is (iOS LibrarySheets). */
@Composable fun LibraryOverlays(store: StudyStore, state: LibraryState, actions: LibraryActions) {
    when (val naming = state.naming) {
        is Naming.RenameSet -> NameSheet("Rename set", "Set name", naming.name, "Rename", { state.naming = null }) { name ->
            actions.change { store.rename(naming.id, name) }
        }
        is Naming.RenameFolder -> NameSheet("Rename folder", "Folder name", naming.name, "Rename", { state.naming = null }) { name ->
            actions.change { store.renameFolder(naming.id, name) }
        }
        Naming.NewFolder -> NameSheet("New folder", "Folder name", "", "Create folder", { state.naming = null }) { name ->
            val ids = state.selected
            actions.change { store.group(ids, name) }
            state.stopSelecting()
        }
        Naming.Combine -> {
            val first = store.library.firstOrNull { it.id in state.selected }?.name
            NameSheet("Combined set", "Name the combined set", first?.let { "$it — combined" } ?: "", "Create combined set", { state.naming = null }) { name ->
                val ids = store.library.filter { it.id in state.selected }.map { it.id }
                actions.change { store.combine(ids, name) }
                state.stopSelecting()
            }
        }
        null -> {}
    }
    state.pendingDelete?.let { ids ->
        DeleteSetsDialog(ids.size, {
            actions.change { ids.forEach(store::deleteSet) }
            state.selected = state.selected - ids.toSet()
            if (state.selecting && state.selected.isEmpty()) state.selecting = false
        }) { state.pendingDelete = null }
    }
    state.session?.let { text ->
        CustomSessionSheet(store, text, { state.session = null }) { set, mode ->
            if (mode == com.stethoscore.app.data.CustomSession.Mode.REVIEW) actions.review(set) else actions.quiz(LibraryQuiz(set))
        }
    }
    state.foundCard?.let { (set, card) -> FoundCardSheet(set, card, { state.foundCard = null }, actions.open) }
    state.nothingYet?.let { feature -> LibraryAlert("Nothing here yet", feature.emptyText) { state.nothingYet = null } }
}

// MARK: - Search

@Composable private fun SearchScopeChips(state: LibraryState) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).semantics { contentDescription = "Search in" },
        horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        LibrarySearch.Scope.entries.forEach { scope ->
            WardChipButton(scope.title, { state.scope = scope }, on = state.scope == scope)
        }
    }
}

private fun LazyListScope.searchItems(query: String, store: StudyStore, search: LibrarySearchState, state: LibraryState, actions: LibraryActions) {
    val hits = search.results.items
    if (hits.isNotEmpty()) {
        item(key = "hits-heading") { LibraryHeading(itemsHeading(state.scope)) }
        items(hits, key = { "hit-" + it.id }) { hit -> SearchRow(hit) { openHit(hit, store, state, actions) } }
        if (search.results.more) item(key = "hits-more") {
            Text("The first ${LibrarySearch.itemLimit}. Add a word to narrow it.", style = WardTextStyle.footnote.textStyle(),
                color = wardColor(WardToken.inkSecondary))
        }
    } else if (state.scope != LibrarySearch.Scope.ALL && !search.busy) {
        item(key = "hits-none") {
            LibraryEmptyState(Icons.Rounded.Search, "No results",
                "Nothing in ${state.scope.title.lowercase()} matches “$query”. Check the spelling or try another word.")
        }
    }
    if (hits.isNotEmpty() && state.scope != LibrarySearch.Scope.NOTES && state.scope != LibrarySearch.Scope.LECTURES) {
        item(key = "hits-session") { BuildSessionTile { state.session = query } }
    }
}

fun itemsHeading(scope: LibrarySearch.Scope): String = when (scope) {
    LibrarySearch.Scope.ALL -> "Questions & cards"
    LibrarySearch.Scope.QUESTIONS -> "Questions"
    LibrarySearch.Scope.CARDS -> "Cards"
    LibrarySearch.Scope.NOTES -> "Notes"
    LibrarySearch.Scope.LECTURES -> "Lectures"
}

/** Where a hit was found: "Question · Heart", "Note · Ideas", "Lecture · Slides.pdf, p. 3" (iOS whereFound). */
fun whereFound(hit: LibrarySearch.Hit): String {
    val dot = " · "
    return when (hit.kind) {
        LibrarySearch.Kind.LECTURE -> hit.kind.label + dot + hit.sourceName + (hit.page?.let { ", p. $it" } ?: "")
        LibrarySearch.Kind.NOTE -> hit.kind.label + dot + "Ideas"
        else -> hit.kind.label + dot + hit.setName
    }
}

private fun hitIcon(kind: LibrarySearch.Kind) = when (kind) {
    LibrarySearch.Kind.SET -> Icons.Rounded.Layers
    LibrarySearch.Kind.QUESTION -> modeIcon(StudySetKind.MCQ)
    LibrarySearch.Kind.CARD -> modeIcon(StudySetKind.ANKI)
    LibrarySearch.Kind.NOTE -> Icons.Rounded.Search
    LibrarySearch.Kind.LECTURE -> modeIcon(StudySetKind.BOOK)
}

@Composable private fun SearchRow(hit: LibrarySearch.Hit, onClick: () -> Unit) {
    val beam = wardColor(WardToken.beam).copy(alpha = 0.3f)
    val marked = remember(hit) {
        val lo = hit.range.first.coerceIn(0, hit.snippet.length)
        val hi = (hit.range.last + 1).coerceIn(lo, hit.snippet.length)
        buildAnnotatedString {
            append(hit.snippet.substring(0, lo))
            withStyle(SpanStyle(fontWeight = FontWeight.Bold, background = beam)) { append(hit.snippet.substring(lo, hi)) }
            append(hit.snippet.substring(hi))
        }
    }
    Row(Modifier.fillMaxWidth().wardRaised(WardRadius.card, WardLift.low).clickable(role = Role.Button, onClick = onClick)
        .padding(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        Icon(hitIcon(hit.kind), null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.width(24.dp).size(18.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(marked, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.ink), maxLines = 3, overflow = TextOverflow.Ellipsis)
            Text(whereFound(hit), style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1,
                overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Opens a hit where it is (iOS openHit): a question as a quiz from it on, a card in a sheet, a note in Ideas. */
fun openHit(hit: LibrarySearch.Hit, store: StudyStore, state: LibraryState, actions: LibraryActions) {
    val set = hit.setId?.let { id -> store.library.firstOrNull { it.id == id } }
    when (hit.kind) {
        LibrarySearch.Kind.SET -> set?.let(actions.open)
        LibrarySearch.Kind.QUESTION -> {
            val id = hit.itemId ?: return
            set ?: return
            actions.quiz(LibraryQuiz(LibrarySearch.opening(set, id) ?: set))
        }
        LibrarySearch.Kind.CARD -> {
            set ?: return
            val card = set.cards.firstOrNull { it.id == hit.itemId }
            if (card != null) state.foundCard = set to card else actions.open(set)
        }
        LibrarySearch.Kind.NOTE -> actions.ideas()
        // the source reader comes with batch 9; until then the lecture's set
        LibrarySearch.Kind.LECTURE -> set?.let(actions.open)
    }
}

/** Build a session's tile (iOS buildSessionButton). */
@Composable fun BuildSessionTile(onClick: () -> Unit) {
    WardTile(onClick, Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().padding(14.dp), horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp),
            verticalAlignment = Alignment.CenterVertically) {
            WardIconSquare(Icons.Rounded.Tune, tone = WardTone.Blue)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Build a session", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
                Text("Missed this week, a subject, a tag, what’s due", style = WardTextStyle.caption2.textStyle(),
                    color = wardColor(WardToken.inkSecondary), maxLines = 2)
            }
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
        }
    }
}

// MARK: - The category's tiles

private fun LazyListScope.tileSection(group: FeatureGroup, category: StudyCategory, store: StudyStore, state: LibraryState, actions: LibraryActions) {
    val features = category.features(group)
    if (features.isEmpty()) return
    item(key = "tiles-heading-" + group.name) { LibraryHeading(group.title) }
    items(features.chunked(2), key = { "tiles-" + it.first().rawValue }) { pair -> TileRow(pair, store, state, actions) }
}

private fun LazyListScope.practiseSection(category: StudyCategory, store: StudyStore, state: LibraryState, actions: LibraryActions) {
    val features = category.features(FeatureGroup.PRACTISE)
    if (features.isEmpty()) return
    item(key = "tiles-heading-practise") { LibraryHeading(FeatureGroup.PRACTISE.title) }
    items(features.take(4).chunked(2), key = { "tiles-" + it.first().rawValue }) { pair -> TileRow(pair, store, state, actions) }
    val rest = features.drop(4)
    if (rest.isEmpty()) return
    item(key = "more-practise") {
        Row(Modifier.fillMaxWidth().heightIn(min = WardControlSize.target.wardDp).clickable(role = Role.Button) { state.morePractise = !state.morePractise }
            .padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("More ways to practise", style = WardTextStyle.footnote.textStyle(WardWeight.semibold), color = wardColor(WardToken.primaryInk),
                modifier = Modifier.weight(1f))
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.primaryInk),
                modifier = Modifier.size(18.dp).then(if (state.morePractise) Modifier.rotate(90f) else Modifier))
        }
    }
    if (state.morePractise) items(rest.chunked(2), key = { "tiles-" + it.first().rawValue }) { pair -> TileRow(pair, store, state, actions) }
}

@Composable private fun TileRow(features: List<CategoryFeature>, store: StudyStore, state: LibraryState, actions: LibraryActions) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        features.forEach { feature -> FeatureTile(feature, feature.tileDetail(store.library), Modifier.weight(1f)) { start(feature, store, state, actions) } }
        if (features.size == 1) Spacer(Modifier.weight(1f))
    }
}

/** One feature as a tile: its glyph in a small well, a name and one line (iOS FeatureTile). */
@Composable private fun FeatureTile(feature: CategoryFeature, detail: String, modifier: Modifier, onClick: () -> Unit) {
    WardTile(onClick, modifier) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            WardIconSquare(featureIcon(feature), tone = WardTone.Blue, size = 36.0)
            Text(feature.title, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink), maxLines = 2,
                overflow = TextOverflow.Ellipsis)
            Text(detail, style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

fun featureIcon(feature: CategoryFeature) = when (feature) {
    CategoryFeature.MULTIPLE_CHOICE -> modeIcon(StudySetKind.MCQ)
    CategoryFeature.FLASHCARDS -> modeIcon(StudySetKind.ANKI)
    CategoryFeature.TEXTBOOKS -> modeIcon(StudySetKind.BOOK)
    CategoryFeature.PICTURES -> Icons.Rounded.Image
    CategoryFeature.STATIONS -> modeIcon(StudySetKind.OSCE)
    CategoryFeature.LECTURES -> modeIcon(StudySetKind.NARRATE)
    CategoryFeature.PATIENTS -> modeIcon(StudySetKind.CASES)
    CategoryFeature.MIXED -> Icons.Rounded.Shuffle
    CategoryFeature.MISTAKES -> Icons.Rounded.Cancel
    CategoryFeature.FLAGGED -> Icons.Rounded.Flag
    CategoryFeature.TIMED -> Icons.Rounded.Timer
    CategoryFeature.WEAKEST -> Icons.Rounded.GpsFixed
    CategoryFeature.CONFIDENT -> Icons.Rounded.Warning
    CategoryFeature.SLOW -> Icons.Rounded.Visibility
    CategoryFeature.ONE -> Icons.Rounded.LooksOne
    CategoryFeature.SUBJECTS -> Icons.Rounded.BarChart
    CategoryFeature.DUE -> Icons.Rounded.Inbox
    CategoryFeature.ADD -> Icons.Rounded.Download
}

/** Whatever a tile does: a mode's sets, a quiz built now, By subject, or New set (iOS start(feature)). */
fun start(feature: CategoryFeature, store: StudyStore, state: LibraryState, actions: LibraryActions) {
    val kind = feature.shelfKind
    when {
        kind != null -> if (feature.shelfSets(store.library).isEmpty() && feature != CategoryFeature.PICTURES) actions.newSet(kind) else actions.shelf(feature)
        feature.isQuiz -> {
            val made = feature.quiz(store)
            if (made == null || made.set.questions.isEmpty()) state.nothingYet = feature else actions.quiz(made)
        }
        feature == CategoryFeature.SUBJECTS -> actions.stats()
        feature == CategoryFeature.DUE -> actions.due()
        feature == CategoryFeature.ADD -> actions.newSet(StudySetKind.MCQ)
        else -> {}
    }
}
