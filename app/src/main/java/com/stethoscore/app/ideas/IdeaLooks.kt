package com.stethoscore.app.ideas

import com.stethoscore.app.map.SpaceStyle
import kotlin.math.abs

// The map's themes and the Space's style choice: ports of GraphTheme.swift and
// GraphStyleChoice (GraphNodeStyles.swift), fed0105, with the style names of
// GraphNodeStyle (GraphSpaceOptics.swift). Pure Kotlin, tested in IdeaLooksTest.

/** The 3D Ideas map's themes (GraphTheme). */
enum class GraphTheme(val rawValue: String, val title: String) {
    SPACE("space", "Space"),
    NEURONS("neurons", "Neurons"),
    PERFORMANCE("performance", "Performance");

    /**
     * Whether it can be chosen. Neurons (GraphNeurons, its planner, cells and shaders) is not
     * ported to Android yet, so the Look menu does not offer it and a stored "neurons" reads
     * as the standard.
     */
    val isReady: Boolean get() = this != NEURONS

    val legendTitle: String get() = when (this) {
        SPACE -> "How your universe is built"
        NEURONS -> "How your network is built"
        PERFORMANCE -> "How the fast map is built"
    }

    /** What TalkBack calls the map. */
    val mapLabel: String get() = when (this) {
        SPACE -> "Space of ideas"
        NEURONS -> "Network of ideas"
        PERFORMANCE -> "Fast map of ideas"
    }

    val hint: String get() = when (this) {
        SPACE -> "Tap a body to preview it on a card; tap again, or Open, to read it. " +
            "Hold a body to move it, or hold it still for its options. Drag to turn, pinch to zoom."
        NEURONS -> "Tap a cell to preview it on a card; tap again, or Open, to read it. " +
            "Hold a cell to move it, or hold it still for its options. Drag to turn, pinch to zoom."
        PERFORMANCE -> "Tap a point to preview it on a card; tap again, or Open, to read it. " +
            "Hold a point for its options. Drag to turn, two fingers to slide, pinch to zoom."
    }

    val cardTitle: String get() = when (this) {
        SPACE -> "Your notes as a universe"
        NEURONS -> "Your notes as a nervous system"
        PERFORMANCE -> "Your notes, built for speed"
    }

    val cardText: String get() = when (this) {
        SPACE -> "Top-level folders are black holes, folders are stars, pages are gas giants " +
            "and ideas are rocky planets. Bigger holds more."
        NEURONS -> "Top-level folders are cells, folders are the parts inside them, " +
            "pages are vesicles and ideas granules. Links grow out of the cells as axons carrying impulses."
        PERFORMANCE -> "Every note is a point and every link a line, drawn so 100,000 fit at once. " +
            "Each top-level folder has its own colour; far away a folder’s notes merge into one glow."
    }

    val cardSteps: List<String> get() = when (this) {
        SPACE -> listOf("Tap + › New folder: a new galaxy round its black hole.",
            "Tap + › New page for a gas giant, New idea for a rocky planet.",
            "Type [[ and a note’s title in a note: a link joins them.")
        NEURONS -> listOf("Tap + › New folder: a new cell.",
            "Tap + › New page for a vesicle, New idea for a granule.",
            "Type [[ and a note’s title in a note: an axon joins them.")
        PERFORMANCE -> listOf("Tap + › New folder: a new cluster round its hub.",
            "Tap + › New page for a larger point, New idea for a smaller one.",
            "Type [[ and a note’s title in a note: a line joins them.")
    }

    companion object {
        const val KEY = "vignette.space.theme"
        val standard = SPACE
        const val HINTS_KEY = "vignette.space.themeHintsSeen"

        /** The themes the Look menu offers, in its order. */
        val offered: List<GraphTheme> get() = entries.filter { it.isReady }

        /** A stored value, or the standard for anything unknown or not ready. */
        fun stored(raw: String?): GraphTheme = entries.firstOrNull { it.rawValue == raw && it.isReady } ?: standard
    }
}

/** The iOS names of the six styles (GraphNodeStyle's raw values), for the stored choice. */
val SpaceStyle.rawValue: String get() = when (this) {
    SpaceStyle.BLACK_HOLE -> "blackHole"
    SpaceStyle.ROCKY -> "rocky"
    SpaceStyle.GAS_GIANT -> "gasGiant"
    SpaceStyle.COMET -> "comet"
    SpaceStyle.PULSAR -> "pulsar"
    SpaceStyle.SUN -> "sun"
}

fun spaceStyle(raw: String?): SpaceStyle? = SpaceStyle.entries.firstOrNull { it.rawValue == raw }

/**
 * Which look the notes take in Space (GraphStyleChoice): the Universe ([AUTO]) or one style for
 * every note, and optionally a style per top-level folder.
 */
object GraphStyleChoice {
    const val KEY = "vignette.space.nodeStyle"
    const val FOLDERS_KEY = "vignette.space.nodeStyleFolders"
    const val AUTO = "auto"
    const val STANDARD = AUTO

    /** "id=style;id=style" to a map; anything unreadable is skipped. */
    fun folders(raw: String): Map<String, SpaceStyle> {
        val found = LinkedHashMap<String, SpaceStyle>()
        for (part in raw.split(";")) {
            val pieces = part.split("=")
            if (pieces.size != 2 || !isId(pieces[0])) continue
            val style = spaceStyle(pieces[1]) ?: continue
            found[pieces[0]] = style
        }
        return found
    }

    fun encode(map: Map<String, SpaceStyle>): String =
        map.keys.sortedBy { it.uppercase() }.joinToString(";") { "$it=${map.getValue(it).rawValue}" }

    /**
     * Every note's style for the single looks. A main that is not a style falls back to pages
     * as gas giants and ideas as rocky planets; a folder look wins for that folder's notes.
     */
    fun resolve(book: IdeaBook, main: String, folderRaw: String): Map<String, SpaceStyle> {
        val single = spaceStyle(main)
        val result = LinkedHashMap<String, SpaceStyle>()
        for (note in book.notes) result[note.id] = single ?: if (note.noteKind == NoteKind.PAGE) SpaceStyle.GAS_GIANT else SpaceStyle.ROCKY
        result.putAll(overrides(book, folderRaw))
        return result
    }

    /** Each note's folder look, from its top-level folder. */
    fun overrides(book: IdeaBook, folderRaw: String): Map<String, SpaceStyle> {
        val byFolder = folders(folderRaw)
        if (byFolder.isEmpty()) return emptyMap()
        val result = LinkedHashMap<String, SpaceStyle>()
        for (note in book.notes) {
            val root = book.rootFolder(note.folderId) ?: continue
            result[note.id] = byFolder[root] ?: continue
        }
        return result
    }

    /** Folder palettes, so two folders of planets are not twins: 0, 1 or 2 from the folder's id. */
    fun palette(folder: String?): Int {
        if (folder == null) return 0
        var total = 0L
        for (c in folder.uppercase()) total = total * 31 + c.code
        return (abs(total) % 3).toInt()
    }

    /**
     * Android's map: every node's style code, in [ids]' order. The single looks as [resolve]
     * gives them; the Universe (not ported: GraphUniverse plans galaxies from the folders) is
     * Android's stand-in, a note's style by its links ([SpaceStyle.forLinks]), with the folder
     * looks over it.
     */
    fun codes(book: IdeaBook, ids: List<String>, linkCounts: IntArray, main: String, folderRaw: String): ByteArray {
        val chosen: Map<String, SpaceStyle> = if (spaceStyle(main) != null) resolve(book, main, folderRaw) else overrides(book, folderRaw)
        return ByteArray(ids.size) { i -> (chosen[ids[i]] ?: SpaceStyle.forLinks(linkCounts.getOrElse(i) { 0 })).code.toByte() }
    }

    /** A UUID, as iOS's UUID(uuidString:) reads one: 36 characters, hex in five groups. */
    private fun isId(s: String) = Regex("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}").matches(s)
}
