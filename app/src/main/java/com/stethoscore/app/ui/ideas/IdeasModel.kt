package com.stethoscore.app.ui.ideas

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.NoteAdd
import androidx.compose.material.icons.automirrored.rounded.List
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.rounded.Adjust
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Contrast
import androidx.compose.material.icons.rounded.Dashboard
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Sensors
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.ViewInAr
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ideas.GraphLineStyle
import com.stethoscore.app.ideas.GraphStyleChoice
import com.stethoscore.app.ideas.GraphTheme
import com.stethoscore.app.ideas.IdeaBook
import com.stethoscore.app.ideas.IdeasMode
import com.stethoscore.app.ideas.NoteEditing
import com.stethoscore.app.ideas.NoteKind
import com.stethoscore.app.ideas.NoteTone
import com.stethoscore.app.map.SpaceStyle

/**
 * The idea dump as the screens hold it: the notes and folders (IdeaBook, on the library's
 * copy), saved to the library after every change. Reading [book] subscribes to its changes.
 * A save that fails puts the screen back to what is on disk and says why in [error].
 */
class IdeasModel(private val store: StudyStore) {
    private var revision by mutableIntStateOf(0)
    var error by mutableStateOf<String?>(null)
    private var held: IdeaBook = make()

    private fun make() = IdeaBook(store.notes, store.noteFolders, onChange = ::persist)

    private fun persist(notes: List<com.stethoscore.app.data.Note>, folders: List<com.stethoscore.app.ideas.NoteFolder>) {
        runCatching { store.replaceIdeas(notes, folders) }.onFailure {
            error = it.message ?: "Could not save your library."
            held = make()
        }
        revision++
    }

    val book: IdeaBook get() { revision; return held }

    /** Adds the cards made from a note to the library (Turn into cards). */
    fun addSet(set: com.stethoscore.app.data.StudySet): Boolean =
        runCatching { store.addSet(set) }.onFailure { error = it.message ?: "Could not save your library." }.isSuccess
}

/**
 * Ideas' remembered choices, kept as iOS keeps them in UserDefaults (the same keys), in this
 * device's preferences: the mode, the folded switcher, Lines, Read as Markdown, and the map's
 * theme, look, folder looks and demo.
 */
class IdeasSettings(context: Context) {
    private val prefs: SharedPreferences? = runCatching { context.getSharedPreferences(FILE, Context.MODE_PRIVATE) }.getOrNull()
    private fun str(key: String, fallback: String) = runCatching { prefs?.getString(key, fallback) }.getOrNull() ?: fallback
    private fun bool(key: String) = runCatching { prefs?.getBoolean(key, false) }.getOrNull() ?: false
    private fun put(block: SharedPreferences.Editor.() -> Unit) { runCatching { prefs?.edit()?.apply(block)?.apply() } }

    private var heldMode by mutableStateOf(IdeasMode.of(str(IdeasMode.KEY, IdeasMode.LIST.rawValue)))
    val mode: IdeasMode get() = heldMode
    fun setMode(value: IdeasMode) { heldMode = value; put { putString(IdeasMode.KEY, value.rawValue) } }

    private var heldSwitcherCollapsed by mutableStateOf(bool(SWITCHER_KEY))
    val switcherCollapsed: Boolean get() = heldSwitcherCollapsed
    fun setSwitcherCollapsed(value: Boolean) { heldSwitcherCollapsed = value; put { putBoolean(SWITCHER_KEY, value) } }

    private var heldStraightLines by mutableStateOf(bool(GraphLineStyle.KEY))
    val straightLines: Boolean get() = heldStraightLines
    fun setStraightLines(value: Boolean) { heldStraightLines = value; put { putBoolean(GraphLineStyle.KEY, value) } }
    val lineStyle: GraphLineStyle get() = GraphLineStyle.inForce(straightLines)

    private var heldReading by mutableStateOf(bool(NoteEditing.READ_KEY))
    val reading: Boolean get() = heldReading
    fun setReading(value: Boolean) { heldReading = value; put { putBoolean(NoteEditing.READ_KEY, value) } }

    private var heldTheme by mutableStateOf(str(GraphTheme.KEY, GraphTheme.standard.rawValue))
    val theme: String get() = heldTheme
    fun setTheme(value: String) { heldTheme = value; put { putString(GraphTheme.KEY, value) } }

    private var heldNodeStyle by mutableStateOf(str(GraphStyleChoice.KEY, GraphStyleChoice.STANDARD))
    val nodeStyle: String get() = heldNodeStyle
    fun setNodeStyle(value: String) { heldNodeStyle = value; put { putString(GraphStyleChoice.KEY, value) } }

    private var heldFolderStyles by mutableStateOf(str(GraphStyleChoice.FOLDERS_KEY, ""))
    val folderStyles: String get() = heldFolderStyles
    fun setFolderStyles(value: String) { heldFolderStyles = value; put { putString(GraphStyleChoice.FOLDERS_KEY, value) } }

    private var heldPerfDemo by mutableIntStateOf(runCatching { prefs?.getInt(PERF_DEMO_KEY, 0) }.getOrNull() ?: 0)
    val perfDemo: Int get() = heldPerfDemo
    fun setPerfDemo(value: Int) { heldPerfDemo = value; put { putInt(PERF_DEMO_KEY, value) } }

    companion object {
        const val FILE = "ideas"
        const val SWITCHER_KEY = "vignette.ideas.switcherCollapsed"
        const val PERF_DEMO_KEY = "vignette.space.perfDemo"
        /** The demo maps the readout offers (iOS GraphPerfDemo), and Android's own million. */
        val perfDemoSizes = listOf(100_000, 300_000, 1_000_000)
    }
}

val IdeasMode.icon: ImageVector get() = when (this) {
    IdeasMode.LIST -> Icons.AutoMirrored.Rounded.List          // list.bullet
    IdeasMode.BOARD -> Icons.Rounded.Dashboard                 // rectangle.3.group
    IdeasMode.SPACE -> Icons.Rounded.ViewInAr                  // cube.transparent
}

val NoteKind.icon: ImageVector get() = when (this) {
    NoteKind.PAGE -> Icons.Outlined.Description                // doc.text
    NoteKind.IDEA -> Icons.Outlined.Lightbulb                  // lightbulb
}

val GraphTheme.icon: ImageVector get() = when (this) {
    GraphTheme.SPACE -> Icons.Rounded.AutoAwesome              // sparkles
    GraphTheme.NEURONS -> Icons.Rounded.Public
    GraphTheme.PERFORMANCE -> Icons.Rounded.Speed              // speedometer
}

val SpaceStyle.icon: ImageVector get() = when (this) {
    SpaceStyle.BLACK_HOLE -> Icons.Rounded.Adjust              // circle.circle.fill
    SpaceStyle.SUN -> Icons.Rounded.WbSunny                    // sun.max.fill
    SpaceStyle.ROCKY -> Icons.Rounded.Public                   // globe.europe.africa.fill
    SpaceStyle.GAS_GIANT -> Icons.Rounded.Contrast             // circle.lefthalf.filled
    SpaceStyle.PULSAR -> Icons.Rounded.Sensors                 // dot.radiowaves.left.and.right
    SpaceStyle.COMET -> Icons.Rounded.AutoAwesome              // sparkle
}

/** New page's glyph (doc.badge.plus). */
val newPageIcon: ImageVector get() = Icons.AutoMirrored.Outlined.NoteAdd

/** A folder's colour, as NoteTone gives it. */
fun toneColor(folderId: String?, book: IdeaBook): Color = NoteTone.rgb(folderId, book).let { Color(it[0], it[1], it[2]) }
