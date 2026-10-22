package com.stethoscore.app.data

import java.nio.charset.Charset
import java.text.NumberFormat

/**
 * Where a file to import comes from (iOS ImportSource): the New set sheet's
 * three choices, with the words under each.
 */
enum class ImportSource(val rawValue: String) {
    ANKI("anki"), TABLE("table"), APP_FILE("appFile");

    val title: String get() = when (this) {
        ANKI -> "Anki deck"
        TABLE -> "Quizlet / CSV"
        APP_FILE -> "Stethoscore file"
    }

    val help: String get() = when (this) {
        ANKI -> "An .apkg deck or .colpkg collection from Anki, AnkiDroid or AnkiMobile — AnKing too. Subdecks become sets, tags and pictures come with the cards, and so does where each card was in Anki’s schedule. You’ll see what’s inside before anything is added."
        TABLE -> "A table with a card on each row: Quizlet’s export (term, tab, definition), a CSV from Google Sheets, Excel or Brainscape, or Anki’s “Notes in Plain Text”. Columns named Front, Back, Tags — or Question, A, B, C, D, Answer for questions — are recognised."
        APP_FILE -> "A .json set exported from Stethoscore, or from an earlier version of it. It goes straight into your library."
    }

    /** The document types the file picker offers. */
    val mimeTypes: Array<String> get() = when (this) {
        ANKI -> arrayOf("application/zip", "application/octet-stream", "*/*")
        TABLE -> arrayOf("text/csv", "text/comma-separated-values", "text/tab-separated-values", "text/plain", "text/*")
        APP_FILE -> arrayOf("application/json", "text/plain")
    }

    companion object {
        /** What a file is, by its name and, failing that, its first bytes. */
        fun of(name: String, head: ByteArray): ImportSource {
            val ext = name.substringAfterLast('.', "").lowercase()
            if (ext in setOf("apkg", "colpkg", "anki2", "anki21", "zip")) return ANKI
            if (ext == "json") return APP_FILE
            if (ext in setOf("csv", "tsv", "txt", "tab", "text")) return TABLE
            if (head.size >= 2 && head[0] == 0x50.toByte() && head[1] == 0x4B.toByte()) return ANKI
            if (head.copyOf(minOf(15, head.size)).toString(Charsets.US_ASCII) == "SQLite format 3") return ANKI
            if (head.firstOrNull() == '{'.code.toByte()) return APP_FILE
            return TABLE
        }
    }
}

/** One of the import preview's figures: "1,204 cards". [icon] names the glyph. */
data class ImportFact(val value: String, val label: String, val icon: String)

/** What a file holds, shown before anything is added (iOS ImportPreview). */
data class ImportPreview(
    val title: String,
    val source: ImportSource,
    val sets: List<StudySet>,
    /** Each set's folder by name, or null; matched to a folder here or made. */
    val folderNames: List<String?>,
    val facts: List<ImportFact> = emptyList(),
    val notes: List<String> = emptyList(),
    val id: String = newId(),
) {
    val itemCount: Int get() = sets.sumOf { it.itemCount }
}

/**
 * Reading a file into a preview and adding it (iOS LibraryImport): a table
 * of cards or questions; a deck from Anki is not read on Android yet.
 */
object LibraryImport {

    class Failure(message: String) : Exception(message) {
        companion object {
            val nothingReadable = Failure("Nothing in that file could be read as cards or questions. Each row needs a front and a back — or a question, its options and the answer.")
            val unreadableText = Failure("That file isn’t text this app can read.")
            val ankiNotYet = Failure("Anki decks can’t be opened on Android yet. Export the deck from Anki as “Notes in Plain Text” and import that instead.")
        }
    }

    /** A preview of [data], named [fileName], as [kind] (questions or cards). */
    fun preview(fileName: String, data: ByteArray, kind: StudySetKind, subject: String): ImportPreview =
        when (ImportSource.of(fileName, data.copyOf(minOf(16, data.size)))) {
            ImportSource.ANKI -> throw Failure.ankiNotYet
            ImportSource.TABLE, ImportSource.APP_FILE -> table(stem(fileName), decodeText(data) ?: throw Failure.unreadableText, kind, subject)
        }

    /** As [preview], the kind read from the file: questions if it has question columns, cards otherwise. */
    fun previewDetecting(fileName: String, data: ByteArray, subject: String): ImportPreview {
        val text = decodeText(data)
        val kind = if (text != null && PlainTextImport.holdsQuestions(text)) StudySetKind.MCQ else StudySetKind.ANKI
        return preview(fileName, data, kind, subject)
    }

    fun stem(fileName: String): String = fileName.substringAfterLast('/').let { if ('.' in it) it.substringBeforeLast('.') else it }

    /** A table's rows as one set of cards, or of questions when asked for and the columns are there. */
    fun table(name: String, text: String, kind: StudySetKind, subject: String): ImportPreview {
        var set = StudySet(name = name.ifEmpty { "Imported" }, subject = subject.ifEmpty { "General" },
            kind = if (kind == StudySetKind.MCQ) StudySetKind.MCQ else StudySetKind.ANKI)
        if (kind == StudySetKind.MCQ) set = set.copy(questions = PlainTextImport.parseAnyMCQ(text))
        if (set.questions.isEmpty()) set = set.copy(kind = StudySetKind.ANKI, cards = PlainTextImport.parseAnyCards(text))
        if (set.itemCount <= 0) throw Failure.nothingReadable
        val facts = mutableListOf<ImportFact>()
        val notes = mutableListOf<String>()
        val noun = if (set.kind == StudySetKind.MCQ) "questions" else "cards"
        facts += ImportFact(number(set.itemCount), noun, if (set.kind == StudySetKind.MCQ) "questions" else "cards")
        val tagged = set.cards.count { it.tags.isNotEmpty() } + set.questions.count { it.tags.isNotEmpty() }
        if (tagged > 0) facts += ImportFact(number(tagged), "tagged", "tag")
        val rows = PlainTextImport.table(text)?.rows?.size ?: set.itemCount
        if (rows > set.itemCount) notes += "${number(rows - set.itemCount)} rows had no front or no back and were skipped."
        if (kind == StudySetKind.MCQ && set.kind == StudySetKind.ANKI) notes += "No question and answer columns were found, so these came in as flashcards."
        return ImportPreview(set.name, ImportSource.TABLE, listOf(set), listOf(null), facts, notes)
    }

    /** UTF-16 with its mark, UTF-8, and failing that Windows-1252. */
    fun decodeText(data: ByteArray): String? {
        if (data.size >= 2 && ((data[0] == 0xFF.toByte() && data[1] == 0xFE.toByte()) || (data[0] == 0xFE.toByte() && data[1] == 0xFF.toByte())))
            return String(data, Charsets.UTF_16)
        val decoder = Charsets.UTF_8.newDecoder()
        val utf8 = runCatching { decoder.decode(java.nio.ByteBuffer.wrap(data)).toString() }.getOrNull()
        if (utf8 != null) return utf8.removePrefix("﻿")
        return runCatching { String(data, Charset.forName("windows-1252")) }.getOrElse { String(data, Charsets.ISO_8859_1) }
    }

    fun number(value: Int): String = NumberFormat.getIntegerInstance().format(value)

    /**
     * Adds what the preview holds: each set into its folder by name, a
     * folder here of that name (any case) if there is one, a new one if not;
     * a set with no folder goes into [folder]. Returns the sets added.
     */
    fun commit(preview: ImportPreview, store: StudyStore, folder: String? = null): Int {
        val ids = mutableMapOf<String, String>()
        val made = mutableListOf<StudyFolder>()
        for (name in preview.folderNames.filterNotNull()) {
            if (name in ids) continue
            val here = store.folders.firstOrNull { it.name.equals(name, ignoreCase = true) }
            if (here != null) ids[name] = here.id else StudyFolder(name = name).also { made += it; ids[name] = it.id }
        }
        val sets = preview.sets.mapIndexed { index, set ->
            val name = preview.folderNames.getOrNull(index)
            set.copy(folderId = name?.let { ids[it] } ?: folder)
        }
        store.addSets(sets, made)
        return sets.size
    }

    /** A textbook's pages as iOS BookPages.split counts them: a page per # or ## heading, empty ones dropped. */
    fun bookPageCount(markdown: String): Int {
        var pages = 0
        val body = StringBuilder()
        fun flush() { if (body.toString().isNotBlank()) pages++; body.setLength(0) }
        for (line in markdown.split("\n")) {
            if (Regex("^#{1,2}\\s+").containsMatchIn(line)) flush()
            body.append(line).append('\n')
        }
        flush()
        return pages
    }
}
