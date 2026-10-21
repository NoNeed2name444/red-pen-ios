package com.stethoscore.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.Note
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.map.MapGraph
import com.stethoscore.app.map.NoteLike
import com.stethoscore.app.map.SyntheticGraph
import com.stethoscore.app.ui.map.Map3DView
import com.stethoscore.app.ui.map.MapScene
import com.stethoscore.app.ui.map.MapTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Native note editing, the list, and the 3D map (OpenGL ES 3, chunked level of detail) with a 1,000,000-node demo. */
@Composable fun IdeasScreen(store: StudyStore, onBack: () -> Unit) {
    var revision by remember { mutableIntStateOf(0) }
    var mode by rememberSaveable { mutableStateOf("List") }
    var query by rememberSaveable { mutableStateOf("") }
    // Only the id is kept across rotation; the editor's own fields are saveable too.
    var editingId by rememberSaveable { mutableStateOf<String?>(null) }
    var editingNew by rememberSaveable { mutableStateOf(false) }
    fun edit(note: Note?) { editingId = note?.id; editingNew = note != null && store.notes.none { it.id == note.id } }
    var error by remember { mutableStateOf<String?>(null) }
    val notes = remember(revision, query) { store.searchNotes(query) }
    val current = editingId?.let { id -> if (editingNew) remember(id) { Note(id = id, title = "") } else store.notes.firstOrNull { it.id == id } }
    if (current != null) {
        NoteEditor(current, store.notes, onSave = { note ->
            runCatching { store.saveNote(note) }.onSuccess { revision++; edit(null) }.onFailure { error = it.message }
        }, onDelete = {
            runCatching { store.deleteNote(current.id) }.onSuccess { revision++; edit(null) }.onFailure { error = it.message }
        }, onBack = { edit(null) })
    } else {
        Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            ScreenHeader("Ideas", "Your notes, connected", onBack)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FilterChip(mode == "List", { mode = "List" }, { Text("List") }, leadingIcon = { Icon(Icons.Rounded.ViewList, null, Modifier.size(18.dp)) })
                FilterChip(mode == "Map", { mode = "Map" }, { Text("3D map") }, leadingIcon = { Icon(Icons.Rounded.Hub, null, Modifier.size(18.dp)) })
                FilterChip(mode == "Demo", { mode = "Demo" }, { Text("1M demo") })
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { edit(Note(title = "")) }) { Icon(Icons.Rounded.Add, "Add idea") }
            }
            OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(), placeholder = { Text("Find an idea") }, leadingIcon = { Icon(Icons.Rounded.Search, null) }, singleLine = true, shape = RoundedCornerShape(24.dp))
            val ids = notes.map { it.id }.toSet()
            val links = notes.sumOf { note -> note.links.count { it in ids && it != note.id } }
            SectionLabel("${notes.size} ideas · $links links")
            if (mode == "Demo") {
                MillionDemo(Modifier.weight(1f).fillMaxWidth())
                Text("1,000,000 synthetic notes in a seeded test vault, not your notes. Drag to turn · Pinch to zoom", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else if (notes.isEmpty()) {
                WardCard(Modifier.fillMaxWidth()) {
                    Icon(Icons.Rounded.Lightbulb, null, Modifier.size(34.dp), tint = MaterialTheme.colorScheme.primary)
                    Text(if (query.isBlank()) "Make room for an idea" else "No matching ideas", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    Text(if (query.isBlank()) "Keep a clinical pearl, a question or a connection. Link related notes to see how they fit together." else "Try another word from a title, note or tag.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (query.isBlank()) WardButton("Write your first idea", { edit(Note(title = "")) }, Modifier.fillMaxWidth())
                }
            } else if (mode == "Map") {
                val scene = remember(notes) { MapScene.of(MapGraph.fromNotes(notes.map { NoteNode(it) }), theme = MapTheme.SPACE) }
                Map3DView(scene, Modifier.weight(1f).fillMaxWidth(), description = "3D map of ${notes.size} ideas. Edit all ideas from List view.",
                    onOpenNode = { index -> notes.getOrNull(index)?.let { edit(it) } })
                Text("Drag to turn · Pinch to zoom · Two fingers to move · Tap an idea to edit", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                WardButton("New idea", { edit(Note(title = "")) }, Modifier.fillMaxWidth())
            } else {
                LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    items(notes, key = { it.id }) { note ->
                        WardCard(Modifier.fillMaxWidth().clickable { edit(note) }) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Rounded.Lightbulb, null, tint = MaterialTheme.colorScheme.primary)
                                Spacer(Modifier.width(10.dp))
                                Text(note.title, Modifier.weight(1f), fontSize = 19.sp, fontWeight = FontWeight.SemiBold)
                                Icon(Icons.Rounded.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            if (note.body.isNotBlank()) Text(note.body, maxLines = 3, overflow = TextOverflow.Ellipsis, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            val details = listOfNotNull(if (note.links.isNotEmpty()) "${note.links.size} linked" else null, note.tags.takeIf { it.isNotEmpty() }?.joinToString(" · ")).joinToString(" · ")
                            if (details.isNotBlank()) Text(details, fontSize = 11.sp, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        }
    }
    error?.let { message -> AlertDialog(onDismissRequest = { error = null }, title = { Text("Could not save this idea") }, text = { Text(message) }, confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } }) }
}

@Composable private fun NoteEditor(note: Note, allNotes: List<Note>, onSave: (Note) -> Unit, onDelete: () -> Unit, onBack: () -> Unit) {
    var title by rememberSaveable(note.id) { mutableStateOf(note.title) }
    var body by rememberSaveable(note.id) { mutableStateOf(note.body) }
    var tags by rememberSaveable(note.id) { mutableStateOf(note.tags.joinToString(", ")) }
    var linkList by rememberSaveable(note.id) { mutableStateOf(ArrayList(note.links.distinct())) }
    val links = linkList.toSet()
    fun setLinks(value: Set<String>) { linkList = ArrayList(value) }
    var deleting by remember { mutableStateOf(false) }
    var leaving by remember { mutableStateOf(false) }
    val dirty = title != note.title || body != note.body || tags != note.tags.joinToString(", ") || links != note.links.toSet()
    fun back() { if (dirty) leaving = true else onBack() }
    fun save() { onSave(note.copy(title = title.trim(), body = body, tags = tags.split(',').map { it.trim() }.filter { it.isNotEmpty() }.distinct(), links = links.toList())) }
    BackHandler { back() }
    Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ScreenHeader(if (note.title.isBlank()) "New idea" else "Edit idea", "Saved on this device", ::back)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(), label = { Text("Title") }, singleLine = true, shape = RoundedCornerShape(20.dp))
            OutlinedTextField(body, { body = it }, Modifier.fillMaxWidth().heightIn(min = 180.dp), label = { Text("Your note") }, minLines = 6, shape = RoundedCornerShape(20.dp))
            OutlinedTextField(tags, { tags = it }, Modifier.fillMaxWidth(), label = { Text("Tags, separated by commas") }, shape = RoundedCornerShape(20.dp))
            SectionLabel("Connect to another idea")
            val others = allNotes.filter { it.id != note.id }
            if (others.isEmpty()) Text("Create another idea to make your first connection.", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            others.forEach { other ->
                Row(Modifier.fillMaxWidth().clickable { setLinks(if (other.id in links) links - other.id else links + other.id) }.padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(other.id in links, { checked -> setLinks(if (checked) links + other.id else links - other.id) })
                    Text(other.title, Modifier.weight(1f), fontSize = 15.sp)
                }
            }
            val incoming = allNotes.filter { it.id != note.id && note.id in it.links }
            if (incoming.isNotEmpty()) {
                SectionLabel("Linked from")
                Text(incoming.joinToString(" · ") { it.title }, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (allNotes.any { it.id == note.id }) TextButton(onClick = { deleting = true }) { Icon(Icons.Rounded.DeleteOutline, null); Spacer(Modifier.width(8.dp)); Text("Delete idea") }
        }
        WardButton("Save idea", ::save, Modifier.fillMaxWidth(), enabled = title.isNotBlank())
    }
    if (deleting) AlertDialog(onDismissRequest = { deleting = false }, title = { Text("Delete this idea?") }, text = { Text("${note.title}\nLinks to this idea will also be removed.") }, confirmButton = { TextButton(onClick = onDelete) { Text("Delete") } }, dismissButton = { TextButton(onClick = { deleting = false }) { Text("Cancel") } })
    if (leaving) AlertDialog(onDismissRequest = { leaving = false }, title = { Text("Keep your changes?") }, confirmButton = { TextButton(onClick = ::save, enabled = title.isNotBlank()) { Text("Save") } }, dismissButton = { TextButton(onClick = onBack) { Text("Discard") } })
}

private class NoteNode(note: Note) : NoteLike {
    override val id = note.id; override val title = note.title; override val links = note.links; override val tags = note.tags
}

/** The million-node scene is built once per process, off the main thread, and kept while memory allows. */
private object MillionScene {
    private var kept: java.lang.ref.SoftReference<MapScene>? = null
    @Synchronized fun get(): MapScene = kept?.get() ?: MapScene.of(SyntheticGraph.make(1_000_000)).also { kept = java.lang.ref.SoftReference(it) }
}

@Composable private fun MillionDemo(modifier: Modifier) {
    var scene by remember { mutableStateOf<MapScene?>(null) }
    LaunchedEffect(Unit) { scene = withContext(Dispatchers.Default) { MillionScene.get() } }
    val ready = scene
    if (ready == null) {
        Box(modifier.background(Color(0xFF0E1B2C), RoundedCornerShape(24.dp)), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                CircularProgressIndicator(color = Color(0xFF3B82F6))
                Text("Building 1,000,000 nodes and their links", color = Color(0xFFE1EBF9), fontSize = 14.sp)
            }
        }
    } else {
        Map3DView(ready, modifier, description = "3D performance map of 1,000,000 nodes", continuous = true, autoOrbit = true)
    }
}
