package com.stethoscore.app.ideas

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.Note
import com.stethoscore.app.data.OsceText
import com.stethoscore.app.data.newId
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

// A port of the idea dump's logic (fed0105): NoteStore (Persistence/NoteStore.swift),
// IdeaEdges (Shared/Ideas/IdeaEdges.swift), and from Features/Notes/NotesShared.swift
// NoteKind, NoteTone, IdeasMode and NoteCards. Android keeps the notes and their folders
// in the library file (StudyStore's "notes" and "noteFolders"); IdeaBook works on a copy
// and hands every change to [onChange] to be saved.

/** What a note is for: a page to write at length, or an idea dumped in passing. */
enum class NoteKind(val rawValue: String, val label: String) {
    PAGE("page", "Page"),
    IDEA("idea", "Idea");

    companion object {
        /** An unknown kind from a newer version is read as an idea. */
        fun of(raw: String): NoteKind = entries.firstOrNull { it.rawValue == raw } ?: IDEA
    }
}

val Note.noteKind: NoteKind get() = NoteKind.of(kind)

/** A folder of notes. Folders nest: a folder with a parent sits inside it. */
data class NoteFolder(
    val id: String = newId(),
    val name: String,
    val parentId: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val rawJson: String = "{}",
)

/** Every connection in the dump, each once (IdeaEdges). */
object IdeaEdges {
    /**
     * [outgoing]: each note and what it links to. A link to itself or to a note that is gone is
     * left out; each pair is ordered by id, so a line always bows the same way.
     */
    fun pairs(outgoing: List<Pair<String, List<String>>>): List<Pair<String, String>> {
        val known = outgoing.map { it.first }.toSet()
        val seen = HashSet<String>()
        val edges = ArrayList<Pair<String, String>>()
        for ((id, targets) in outgoing) {
            for (other in targets) {
                if (other == id || other !in known) continue
                // iOS compares uppercase UUID strings; hex digits sort before letters either way
                val pair = if (id.uppercase() < other.uppercase()) id to other else other to id
                if (seen.add(pair.first + pair.second)) edges.add(pair)
            }
        }
        return edges
    }
}

/**
 * Every note and folder in the idea dump (iOS NoteStore), on a copy of the library's. Each
 * change calls [onChange] with the new notes and folders.
 */
class IdeaBook(
    notes: List<Note>,
    folders: List<NoteFolder>,
    private val now: () -> Long = System::currentTimeMillis,
    private val onChange: (List<Note>, List<NoteFolder>) -> Unit = { _, _ -> },
) {
    var notes: List<Note> = notes
        private set(value) { field = value; edgeCache = null }
    var folders: List<NoteFolder> = folders
        private set
    private var edgeCache: List<Pair<String, String>>? = null

    private fun changed() = onChange(notes, folders)

    // ---- finding notes ----

    fun note(id: String?): Note? = id?.let { i -> notes.firstOrNull { it.id == i } }

    /** Notes whose title, body or tags contain every word of the query, newest first. */
    fun search(query: String): List<Note> {
        val words = query.lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }
        val newest = notes.sortedByDescending { it.updatedAt }
        if (words.isEmpty()) return newest
        return newest.filter { note ->
            val haystack = (listOf(note.title, note.body) + note.tags).joinToString(" ").lowercase()
            words.all { haystack.contains(it) }
        }
    }

    /** The notes directly in a folder (null: the ones in no folder), newest first. */
    fun contents(folderId: String?): List<Note> = notes.filter { it.folderId == folderId }.sortedByDescending { it.updatedAt }

    // ---- making and changing notes ----

    /** Makes a note; without a board position it goes on a golden-angle spiral out from the centre. */
    fun create(title: String, body: String = "", kind: NoteKind = NoteKind.IDEA, folderId: String? = null,
               at: BoardPoint? = null): Note {
        val spot = at ?: nextBoardSpot()
        val time = now()
        val note = Note(title = title.trim(), body = body, folderId = folderId, kind = kind.rawValue,
            boardX = spot.x, boardY = spot.y, createdAt = time, updatedAt = time)
        notes = notes + note
        changed()
        return note
    }

    /** Replaces the stored note; the time is stamped only when something really differs. */
    fun update(note: Note) {
        val index = notes.indexOfFirst { it.id == note.id }
        if (index < 0) return
        val kept = note.copy(updatedAt = notes[index].updatedAt)
        if (kept == notes[index]) return
        notes = notes.toMutableList().also { it[index] = kept.copy(updatedAt = now()) }
        changed()
    }

    /** Deletes a note and every hand-made link to it; `[[Title]]`s are left as written. */
    fun delete(id: String) {
        notes = notes.filterNot { it.id == id }.map { if (id in it.links) it.copy(links = it.links.filterNot { l -> l == id }) else it }
        changed()
    }

    fun move(id: String, folderId: String?) {
        val index = notes.indexOfFirst { it.id == id }
        if (index < 0 || notes[index].folderId == folderId) return
        notes = notes.toMutableList().also { it[index] = it[index].copy(folderId = folderId, updatedAt = now()) }
        changed()
    }

    /** Where a card was dropped on the board; not an edit, so its time is left alone. */
    fun setPosition(id: String, x: Double, y: Double) {
        val index = notes.indexOfFirst { it.id == id }
        if (index < 0) return
        notes = notes.toMutableList().also { it[index] = it[index].copy(boardX = x, boardY = y) }
        changed()
    }

    // ---- links ----

    /** Joins two notes by hand; the link is kept on the first only (read both ways). */
    fun link(a: String, b: String) {
        val index = notes.indexOfFirst { it.id == a }
        if (a == b || index < 0 || isLinked(a, b)) return
        notes = notes.toMutableList().also { it[index] = it[index].copy(links = it[index].links + b) }
        changed()
    }

    /** Removes a hand-made link between two notes, whichever of them holds it. */
    fun unlink(a: String, b: String) {
        var didChange = false
        notes = notes.map { n ->
            when {
                n.id == a && b in n.links -> { didChange = true; n.copy(links = n.links.filterNot { it == b }) }
                n.id == b && a in n.links -> { didChange = true; n.copy(links = n.links.filterNot { it == a }) }
                else -> n
            }
        }
        if (didChange) changed()
    }

    fun isLinked(a: String, b: String): Boolean = (note(a)?.links?.contains(b) ?: false) || (note(b)?.links?.contains(a) ?: false)

    /** Every note's id by its lowercased title; where two share a title the older one wins. */
    fun titleIndex(): Map<String, String> {
        val index = LinkedHashMap<String, String>()
        for (note in notes.sortedBy { it.createdAt }) {
            val key = note.title.trim().lowercase()
            if (key.isNotEmpty() && key !in index) index[key] = note.id
        }
        return index
    }

    /** The notes that `[[Title]]`s in this text name, in the order written, each once. */
    fun resolve(text: String, index: Map<String, String>? = null): List<String> {
        val idx = index ?: titleIndex()
        val seen = HashSet<String>()
        return wikiTitles(text).mapNotNull { title -> idx[title.lowercase()]?.takeIf { seen.add(it) } }
    }

    /** The notes one note points to: its hand-made links, then its `[[Title]]`s. */
    fun outgoing(id: String, index: Map<String, String>? = null): List<String> {
        val note = note(id) ?: return emptyList()
        val known = notes.map { it.id }.toSet()
        val seen = hashSetOf(id)
        return (note.links + resolve(note.body, index)).filter { it in known && seen.add(it) }
    }

    /** The notes that point to this one, by hand or by `[[Title]]`. */
    fun backlinks(id: String): List<String> {
        val index = titleIndex()
        return notes.filter { other -> other.id != id && (id in other.links || id in resolve(other.body, index)) }.map { it.id }
    }

    /** Everything a note is connected to. */
    fun connections(id: String): Set<String> = (outgoing(id).toSet() + backlinks(id)) - id

    /** Every connection in the dump, each once, whichever way it was made. */
    fun allEdges(): List<Pair<String, String>> {
        edgeCache?.let { return it }
        val index = titleIndex()
        return IdeaEdges.pairs(notes.map { it.id to (it.links + resolve(it.body, index)) }).also { edgeCache = it }
    }

    // ---- folders ----

    fun createFolder(name: String, parentId: String? = null): NoteFolder {
        val folder = NoteFolder(name = name.trim(), parentId = parentId, createdAt = now())
        folders = folders + folder
        changed()
        return folder
    }

    fun renameFolder(id: String, name: String) {
        val trimmed = name.trim()
        val index = folders.indexOfFirst { it.id == id }
        if (trimmed.isEmpty() || index < 0) return
        folders = folders.toMutableList().also { it[index] = it[index].copy(name = trimmed) }
        changed()
    }

    /** Deletes a folder but nothing in it: its notes and folders move up into its parent. */
    fun deleteFolder(id: String) {
        val folder = folders.firstOrNull { it.id == id } ?: return
        notes = notes.map { if (it.folderId == id) it.copy(folderId = folder.parentId) else it }
        folders = folders.filterNot { it.id == id }.map { if (it.parentId == id) it.copy(parentId = folder.parentId) else it }
        changed()
    }

    fun folder(id: String?): NoteFolder? = id?.let { i -> folders.firstOrNull { it.id == i } }

    /** The folders directly inside one (null: the top level), by name. */
    fun subfolders(parentId: String?): List<NoteFolder> = folders.filter { it.parentId == parentId }.sortedWith(compareBy(NaturalOrder) { it.name })

    /** A folder and the folders it sits in, outermost first; a loop in the parents stops it. */
    fun path(id: String?): List<NoteFolder> {
        val path = ArrayList<NoteFolder>()
        val seen = HashSet<String>()
        var current = folder(id)
        while (current != null && seen.add(current.id)) {
            path.add(0, current)
            current = folder(current.parentId)
        }
        return path
    }

    /** The top-level folder a note's folder sits in: what its colour comes from. */
    fun rootFolder(id: String?): String? = path(id).firstOrNull()?.id

    /** Every folder with its depth, in outline order, for "Move to". */
    fun folderOutline(): List<Pair<NoteFolder, Int>> {
        val result = ArrayList<Pair<NoteFolder, Int>>()
        val seen = HashSet<String>()
        fun walk(parent: String?, depth: Int) {
            for (folder in subfolders(parent)) if (seen.add(folder.id)) {
                result.add(folder to depth)
                walk(folder.id, depth + 1)
            }
        }
        walk(null, 0)
        return result
    }

    /** The number of notes in a folder and everything inside it. */
    fun count(folderId: String): Int {
        val ids = hashSetOf(folderId)
        var grew = true
        while (grew) {
            val before = ids.size
            ids += folders.filter { f -> f.parentId != null && f.parentId in ids }.map { it.id }
            grew = ids.size > before
        }
        return notes.count { n -> n.folderId != null && n.folderId in ids }
    }

    /** The next spot on the board: a golden-angle spiral out from the centre, one step per note. */
    private fun nextBoardSpot(): BoardPoint {
        val n = notes.size.toDouble()
        val angle = n * 2.399963
        val radius = 90 * sqrt(n)
        return BoardPoint(radius * cos(angle), radius * sin(angle))
    }

    companion object {
        /** The titles written as `[[Title]]` in a body, trimmed; `[[Title|shown]]` links to Title. */
        fun wikiTitles(text: String): List<String> {
            val titles = ArrayList<String>()
            for (piece in text.split("[[").drop(1)) {
                val close = piece.indexOf("]]")
                if (close < 0) continue
                val inner = piece.substring(0, close)
                if ('\n' in inner) continue
                val title = inner.split("|", limit = 2).first().trim { it == ' ' || it == '\t' }
                if (title.isNotEmpty()) titles.add(title)
            }
            return titles
        }

        /** A name indented by depth with em spaces, for "Move to" and the folder chip. */
        fun indented(name: String, depth: Int): String = " ".repeat(depth) + name
    }
}

/**
 * Finder's order (localizedStandardCompare, near enough): case-insensitive, runs of digits by
 * their value, so "Week 2" comes before "Week 10".
 */
object NaturalOrder : Comparator<String> {
    override fun compare(a: String, b: String): Int {
        var i = 0; var j = 0
        while (i < a.length && j < b.length) {
            val ca = a[i]; val cb = b[j]
            if (ca.isDigit() && cb.isDigit()) {
                var ei = i; while (ei < a.length && a[ei].isDigit()) ei++
                var ej = j; while (ej < b.length && b[ej].isDigit()) ej++
                val na = a.substring(i, ei).trimStart('0'); val nb = b.substring(j, ej).trimStart('0')
                if (na.length != nb.length) return na.length - nb.length
                val c = na.compareTo(nb)
                if (c != 0) return c
                i = ei; j = ej
            } else {
                val c = ca.lowercaseChar().compareTo(cb.lowercaseChar())
                if (c != 0) return c
                i++; j++
            }
        }
        return (a.length - i) - (b.length - j)
    }
}

/**
 * The quiet colour each top-level folder is known by (NoteTone): seven muted tones by the
 * folder's place among the top-level folders; loose notes plain grey. Colours as 0...1 sRGB.
 */
object NoteTone {
    val palette: List<FloatArray> = listOf(
        floatArrayOf(0.36f, 0.62f, 0.60f), // sea green
        floatArrayOf(0.45f, 0.47f, 0.75f), // slate blue
        floatArrayOf(0.78f, 0.58f, 0.40f), // sand
        floatArrayOf(0.62f, 0.46f, 0.66f), // heather
        floatArrayOf(0.47f, 0.63f, 0.42f), // sage
        floatArrayOf(0.76f, 0.47f, 0.47f), // clay
        floatArrayOf(0.40f, 0.58f, 0.76f), // sky
    )

    /** UIKit's systemGray (light), what Color.gray reads as on iOS: 142, 142, 147. */
    val grey = floatArrayOf(142f / 255, 142f / 255, 147f / 255)

    /** The palette index for a note in [folderId], or null for a loose note (grey). */
    fun index(folderId: String?, book: IdeaBook): Int? {
        val root = book.rootFolder(folderId) ?: return null
        val index = book.subfolders(null).indexOfFirst { it.id == root }
        if (index < 0) return null
        return index % palette.size
    }

    fun rgb(folderId: String?, book: IdeaBook): FloatArray = index(folderId, book)?.let { palette[it] } ?: grey

    /** The palette's colour at [index], wrapping. */
    fun at(index: Int): FloatArray = palette[((index % palette.size) + palette.size) % palette.size]
}

/** Which way the notes are being looked at. */
enum class IdeasMode(val rawValue: String, val title: String, val identifier: String) {
    LIST("list", "List", "ideasMode-list"),
    BOARD("board", "Board", "ideasMode-board"),
    SPACE("space", "Space", "ideasMode-space");

    companion object {
        const val KEY = "vignette.ideas.mode"
        fun of(raw: String?): IdeasMode = entries.firstOrNull { it.rawValue == raw } ?: LIST
    }
}

/**
 * Turning a note into flashcards (NoteCards): its "Question | Answer" lines become cards as a
 * pasted Cards set does; with none, its bullet points become the answers to cards asked by the
 * note's title, four bullets a card.
 */
object NoteCards {
    fun cards(note: Note): List<AnkiCard> {
        val lines = note.body.split(Regex("\r\n|\r|\n| | |\u0085"))
        val paired = lines.filter { "|" in it }.joinToString("\n")
        val cards = OsceText.parseAnkiQA(paired)
        if (cards.isNotEmpty()) return cards

        val bullets = lines.mapNotNull { raw ->
            val line = raw.trim { it == ' ' || it == '\t' }
            for (marker in listOf("- ", "* ", "• ")) if (line.startsWith(marker)) {
                val text = line.removePrefix(marker).trim { it == ' ' || it == '\t' }
                return@mapNotNull text.ifEmpty { null }
            }
            null
        }
        val question = note.title.trim { it == ' ' || it == '\t' }
        if (bullets.isEmpty() || question.isEmpty()) return emptyList()
        return (bullets.indices step 4).map { start ->
            val chunk = bullets.subList(start, minOf(start + 4, bullets.size))
            val front = if (bullets.size > 4) "$question (${start / 4 + 1})" else question
            AnkiCard(type = com.stethoscore.app.data.AnkiCardType.QA, front = front, bullets = chunk)
        }
    }
}
