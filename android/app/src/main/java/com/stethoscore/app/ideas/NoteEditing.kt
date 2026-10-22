package com.stethoscore.app.ideas

import com.stethoscore.app.data.Note

// The note editor's rules (NoteEditorView, fed0105), apart from its view so they are
// tested: the `[[` completion, the links as typed, and Turn into cards' words.

object NoteEditing {
    const val NOTES_FOOTER = "Type [[ and a note’s title to link it, like [[Heart failure]]. Markdown works too: " +
        "# headings, - bullets, **bold**, *italic*; switch to Read to see it laid out. Lines written " +
        "“Question | Answer”, or bullet points, can be turned into cards."
    const val NOTHING_FOR_CARDS = "Nothing to make cards from yet. Write lines like “Question | Answer”, or bullet points under a title."
    const val MISSING = "No note by this name yet — tap to make it"
    const val READ_KEY = "notesReadAsMarkdown"

    /** Whatever has been typed after an unclosed `[[` at the end of the text. */
    fun openFragment(text: String): String? {
        val start = text.lastIndexOf("[[")
        if (start < 0) return null
        val after = text.substring(start + 2)
        if (']' in after || '\n' in after) return null
        return after
    }

    /** The notes a half-typed `[[` could mean: the eight most recent whose title fits. */
    fun suggestions(text: String, notes: List<Note>, current: String): List<Note> {
        val fragment = openFragment(text)?.lowercase() ?: return emptyList()
        return notes.filter { note ->
            note.id != current && note.title.isNotEmpty() && (fragment.isEmpty() || note.title.lowercase().contains(fragment))
        }.sortedByDescending { it.updatedAt }.take(8)
    }

    /** The text with the open `[[` completed as `[[name]]`. */
    fun complete(text: String, name: String): String {
        val start = text.lastIndexOf("[[")
        if (start < 0) return text
        return text.substring(0, start + 2) + name + "]]"
    }

    /** Hand-made links, then the `[[Title]]`s in the text as it is now, each once and known. */
    fun outgoing(book: IdeaBook, current: String, text: String): List<String> {
        val explicit = book.note(current)?.links ?: emptyList()
        val seen = hashSetOf(current)
        return (explicit + book.resolve(text)).filter { book.note(it) != null && seen.add(it) }
    }

    /** The notes linking here that are not already listed as linked from here. */
    fun backlinks(book: IdeaBook, current: String, text: String): List<String> {
        val shown = outgoing(book, current, text).toSet()
        return book.backlinks(current).filter { it !in shown }
    }

    /** `[[Title]]`s that name no note yet, each once. */
    fun unresolved(book: IdeaBook, text: String): List<String> {
        val index = book.titleIndex()
        val seen = HashSet<String>()
        return IdeaBook.wikiTitles(text).filter { index[it.lowercase()] == null && seen.add(it.lowercase()) }
    }

    /** What Turn into cards says once the set is made. */
    fun cardsMade(name: String, count: Int): String {
        val plural = if (count == 1) "" else "s"
        return "“$name” is in your Cards now, $count card$plural ready to review."
    }
}
