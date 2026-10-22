package com.stethoscore.app.ui.ideas

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.rounded.CenterFocusStrong
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ideas.GraphStyleChoice
import com.stethoscore.app.ideas.GraphTheme
import com.stethoscore.app.ideas.IdeaBook
import com.stethoscore.app.ideas.rawValue
import com.stethoscore.app.ideas.spaceStyle
import com.stethoscore.app.map.MapGraph
import com.stethoscore.app.map.NoteLike
import com.stethoscore.app.map.SpaceStyle
import com.stethoscore.app.map.SyntheticGraph
import com.stethoscore.app.ui.map.Map3DView
import com.stethoscore.app.ui.map.MapScene
import com.stethoscore.app.ui.map.MapTheme
import com.stethoscore.app.ui.sources.ReaderDoneButton
import com.stethoscore.app.ui.sources.ReaderEmptyState
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.NumberFormat
import java.util.Locale

// Ideas' Space (IdeasView's .space, fed0105): every note a point in space joined to the notes
// it links to, on the existing GL map, in the theme the Look menu chose. Space draws the six
// bodies (GraphNodeStyle); Performance is the plain fast map with its readout, and offers the
// seeded demo maps. The tools sit at the bottom-trailing corner over the bottom bar: Look and
// Recentre. Android's map has no force simulation, so bodies do not drift and cannot be held
// and moved; a tap opens the note.

/** A note as the map reads it: its links from the book's edges, its group its top-level folder. */
private class NoteNode(override val id: String, override val title: String, override val links: List<String>, override val tags: List<String>) : NoteLike

/** The demo maps are built once per size, off the main thread, and kept while memory allows. */
private object DemoScenes {
    private val kept = HashMap<Int, java.lang.ref.SoftReference<MapScene>>()
    @Synchronized fun get(size: Int): MapScene =
        kept[size]?.get() ?: MapScene.of(SyntheticGraph.make(size)).also { kept[size] = java.lang.ref.SoftReference(it) }
}

private fun grouped(n: Int): String = NumberFormat.getIntegerInstance(Locale.UK).format(n)

/** Each map's words: "Demo: 100,000 notes" and so on. */
fun perfDemoTitle(size: Int): String = "Demo: ${grouped(size)} notes"

@Composable fun IdeasSpace(
    book: IdeaBook, settings: IdeasSettings, covered: Boolean, hidden: Dp,
    open: (String) -> Unit, openFolder: (String) -> Unit,
) {
    val theme = GraphTheme.stored(settings.theme)
    val demo = if (theme == GraphTheme.PERFORMANCE) settings.perfDemo.takeIf { it in IdeasSettings.perfDemoSizes } else null
    var recenter by remember { mutableIntStateOf(0) }
    var legend by remember { mutableStateOf(false) }
    var folderLooks by remember { mutableStateOf(false) }

    Box(Modifier.fillMaxSize()) {
        when {
            demo != null -> DemoMap(demo, recenter)
            book.notes.isEmpty() -> Box(Modifier.fillMaxSize().background(wardColor(WardToken.background)).padding(bottom = hidden), contentAlignment = Alignment.Center) {
                ReaderEmptyState(Icons.Outlined.Lightbulb, "Dump your first idea",
                    "Every note appears here as a point in space, joined to the notes it links to. Type one in the bar below.")
            }
            else -> NotesMap(book, settings, theme, recenter, open)
        }
        if (!covered) Box(Modifier.align(Alignment.BottomEnd).padding(bottom = hidden)) {
            IdeaToolCluster {
                SpaceLookTool(book, settings, theme, showLegend = { legend = true }, showFolderLooks = { folderLooks = true }, openFolder = openFolder)
                IdeaToolButton(Icons.Rounded.CenterFocusStrong, "Recentre") { recenter++ }
            }
        }
    }
    if (legend) LegendSheet(theme) { legend = false }
    if (folderLooks) FolderLooksSheet(book, settings) { folderLooks = false }
}

/** The user's notes on the map, rebuilt off the main thread when they or the look change. */
@Composable private fun NotesMap(book: IdeaBook, settings: IdeasSettings, theme: GraphTheme, recenter: Int, open: (String) -> Unit) {
    val notes = book.notes
    val edges = remember(notes) { book.allEdges() }
    val main = settings.nodeStyle
    val folderRaw = settings.folderStyles
    val scene by produceState<MapScene?>(null, notes, theme, main, folderRaw) {
        value = withContext(Dispatchers.Default) {
            val out = HashMap<String, MutableList<String>>()
            for ((a, b) in edges) out.getOrPut(a) { ArrayList() }.add(b)
            val performance = theme == GraphTheme.PERFORMANCE
            val nodes = notes.map { note ->
                NoteNode(note.id, note.title.ifEmpty { "Untitled" }, out[note.id] ?: emptyList(),
                    if (performance) listOfNotNull(book.rootFolder(note.folderId)) else emptyList())
            }
            val graph = MapGraph.fromNotes(nodes)
            if (performance) MapScene.of(graph, theme = MapTheme.PLAIN)
            else {
                val degree = IntArray(graph.nodeCount)
                for (k in graph.edges.indices) degree[graph.edges[k]]++
                MapScene.of(graph, theme = MapTheme.SPACE, styles = GraphStyleChoice.codes(book, graph.ids, degree, main, folderRaw))
            }
        }
    }
    val ready = scene
    if (ready == null) { Building(null); return }
    val description = "${theme.mapLabel}: ${notes.size} ${if (notes.size == 1) "note" else "notes"}, ${edges.size} ${if (edges.size == 1) "link" else "links"}. " +
        "Tap a note to open it. Drag to turn, pinch to zoom."
    Map3DView(ready, Modifier.fillMaxSize(), description = description,
        onOpenNode = { index -> ready.ids.getOrNull(index)?.let(open) },
        showReadout = theme == GraphTheme.PERFORMANCE, showControls = false, recenter = recenter, corner = 0.dp)
}

/** A seeded demo map (GraphPerfDemo): synthetic notes, not the user's, turning by itself. */
@Composable private fun DemoMap(size: Int, recenter: Int) {
    val scene by produceState<MapScene?>(null, size) { value = withContext(Dispatchers.Default) { DemoScenes.get(size) } }
    val ready = scene
    if (ready == null) { Building(size); return }
    Map3DView(ready, Modifier.fillMaxSize(), description = "${GraphTheme.PERFORMANCE.mapLabel}: demo of ${grouped(size)} synthetic notes, not your notes",
        continuous = true, autoOrbit = true, showControls = false, recenter = recenter, corner = 0.dp)
}

@Composable private fun Building(size: Int?) {
    Box(Modifier.fillMaxSize().background(wardColor(WardToken.background)), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            CircularProgressIndicator(color = wardColor(WardToken.primaryInk))
            Text(if (size == null) "Laying out your notes" else "Building ${grouped(size)} notes and their links",
                style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}

/**
 * Space's Look menu (GraphLookMenu): the theme, then the theme's own choices - for Space the
 * Universe or one style for every note, and folder looks; for Performance the demo maps -
 * then Lines and the theme's legend.
 */
@Composable private fun SpaceLookTool(
    book: IdeaBook, settings: IdeasSettings, theme: GraphTheme,
    showLegend: () -> Unit, showFolderLooks: () -> Unit, openFolder: (String) -> Unit,
) {
    var showing by remember { mutableStateOf(false) }
    Box {
        IdeaToolButton(Icons.Rounded.Palette, "Look", value = theme.title) { showing = true }
        DropdownMenu(showing, { showing = false }, containerColor = wardColor(WardToken.background)) {
            MenuHeader("Theme")
            GraphTheme.offered.forEach { t ->
                Choice(t.title, t.icon, t == theme) { settings.setTheme(t.rawValue); showing = false }
            }
            HorizontalDivider()
            if (theme == GraphTheme.SPACE) {
                MenuHeader("Bodies")
                Choice("Universe", Icons.Rounded.Public, spaceStyle(settings.nodeStyle) == null) { settings.setNodeStyle(GraphStyleChoice.AUTO); showing = false }
                SpaceStyle.menuOrder.forEach { s ->
                    Choice(s.label, s.icon, settings.nodeStyle == s.rawValue) { settings.setNodeStyle(s.rawValue); showing = false }
                }
                if (book.subfolders(null).isNotEmpty()) Choice("Folder looks", Icons.Outlined.Folder, false) { showing = false; showFolderLooks() }
            } else if (theme == GraphTheme.PERFORMANCE) {
                MenuHeader("Map")
                Choice("Your notes", Icons.Outlined.Lightbulb, settings.perfDemo !in IdeasSettings.perfDemoSizes) { settings.setPerfDemo(0); showing = false }
                IdeasSettings.perfDemoSizes.forEach { n ->
                    Choice(perfDemoTitle(n), Icons.Rounded.Public, settings.perfDemo == n) { settings.setPerfDemo(n); showing = false }
                }
            }
            HorizontalDivider()
            MenuHeader("Lines")
            IdeaLinesPicker(settings, Modifier.width(220.dp).padding(horizontal = 12.dp, vertical = 4.dp))
            HorizontalDivider()
            Choice(theme.legendTitle, Icons.Outlined.Info, false) { showing = false; showLegend() }
        }
    }
}

@Composable private fun MenuHeader(text: String) {
    WardSmallCapsText(text, Modifier.padding(horizontal = 16.dp, vertical = 6.dp).semantics { heading() })
}

@Composable private fun Choice(title: String, icon: ImageVector, chosen: Boolean, onClick: () -> Unit) {
    DropdownMenuItem({ Text(title, color = wardColor(WardToken.ink)) }, onClick,
        leadingIcon = { Icon(icon, null, tint = wardColor(WardToken.inkSecondary)) },
        trailingIcon = if (chosen) ({ Icon(Icons.Rounded.Check, "Chosen", tint = wardColor(WardToken.primaryInk)) }) else null)
}

/** The theme's legend (GraphThemeCard): what the map is made of, and how to grow it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun LegendSheet(theme: GraphTheme, onDone: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDone, containerColor = wardColor(WardToken.background)) {
        ReaderNavBar(theme.legendTitle, trailing = { ReaderDoneButton(onClick = onDone) })
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(theme.cardTitle, Modifier.semantics { heading() }, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
            Text(theme.cardText, style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
            theme.cardSteps.forEachIndexed { i, step ->
                Text("${i + 1}. $step", style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            Text(theme.hint, style = WardType.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
            Spacer(Modifier.height(24.dp))
        }
    }
}

/** Folder looks: each top-level folder's notes as one style, or "Same as all". */
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun FolderLooksSheet(book: IdeaBook, settings: IdeasSettings, onDone: () -> Unit) {
    val looks = GraphStyleChoice.folders(settings.folderStyles)
    fun set(folder: String, style: SpaceStyle?) {
        val next = HashMap(looks)
        if (style == null) next.remove(folder) else next[folder] = style
        settings.setFolderStyles(GraphStyleChoice.encode(next))
    }
    ModalBottomSheet(onDismissRequest = onDone, containerColor = wardColor(WardToken.background)) {
        ReaderNavBar("Folder looks", trailing = { ReaderDoneButton(onClick = onDone) })
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 12.dp)) {
            book.subfolders(null).forEach { folder ->
                var menu by remember(folder.id) { mutableStateOf(false) }
                val chosen = looks[folder.id]
                Box {
                    DropdownMenuItem({ Text(folder.name, color = wardColor(WardToken.ink)) }, { menu = true },
                        leadingIcon = { Icon(Icons.Outlined.Folder, null, tint = toneColor(folder.id, book)) },
                        trailingIcon = { Text(chosen?.label ?: "Same as all", style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.primaryInk)) })
                    DropdownMenu(menu, { menu = false }, containerColor = wardColor(WardToken.background)) {
                        Choice("Same as all", Icons.Rounded.Public, chosen == null) { set(folder.id, null); menu = false }
                        SpaceStyle.menuOrder.forEach { s -> Choice(s.label, s.icon, chosen == s) { set(folder.id, s); menu = false } }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}
