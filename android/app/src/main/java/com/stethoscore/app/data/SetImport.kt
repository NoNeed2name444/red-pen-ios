package com.stethoscore.app.data

/**
 * A set that arrived as a file from somebody else's phone, made into one of
 * ours (iOS SetImport). Two things in a shared set only mean something on the
 * sender's phone: its folder, and pictures that had not finished downloading
 * there (a `blob:` reference into the sender's account).
 */
object SetImport {

    data class Received(
        val set: StudySet,
        /** Pictures the file referred to but did not carry; the cards that were nothing without them were left out. */
        val missingPictures: Int
    )

    /**
     * The set as it should join this library: a new id, its folder only if
     * this library has that folder, dated now, and no picture it cannot have.
     */
    fun received(incoming: StudySet, folders: Set<String>, now: Long = System.currentTimeMillis(), isMissing: (String) -> Boolean): Received {
        var set = incoming.copy(
            // never collide with a set already here
            id = newId(),
            folderId = incoming.folderId?.takeIf { it in folders },
            // new to this library, so it sorts as new and syncs as a change
            createdAt = now, updatedAt = now)
        val missing = set.images.count(isMissing)
        if (missing == 0) return Received(set, 0)

        // pictures are referred to by position, so dropping one renumbers every picture after it
        val moved = mutableMapOf<Int, Int>()
        val kept = mutableListOf<String>()
        set.images.forEachIndexed { index, image ->
            if (!isMissing(image)) { moved[index] = kept.size; kept += image }
        }
        val cards = set.cards.mapNotNull { card ->
            val old = card.imageIndex ?: return@mapNotNull card
            val now2 = moved[old]
            // an occlusion card IS its picture; any other card still reads
            if (now2 == null && card.type == AnkiCardType.OCCLUSION) null else card.copy(imageIndex = now2)
        }
        val questions = set.questions.map { q -> q.imageIndex?.let { q.copy(imageIndex = moved[it]) } ?: q }
        set = set.copy(images = kept, cards = cards, questions = questions,
            bookMarkdown = if (set.bookMarkdown.isEmpty()) set.bookMarkdown else renumbered(set.bookMarkdown, moved))
        return Received(set, missing)
    }

    /** A textbook's picture lines pointed at their new positions, and the lines whose picture is gone taken out. */
    fun renumbered(markdown: String, moved: Map<Int, Int>): String =
        markdown.split("\n").mapNotNull { line ->
            val (index, caption) = figure(line.trimSpaces()) ?: return@mapNotNull line
            val now = moved[index] ?: return@mapNotNull null
            "![$caption](image:$now)"
        }.joinToString("\n")

    /** A textbook's picture lines moved along by [offset], for a book joined after other pictures (iOS BookFigures.rebased). */
    fun rebased(markdown: String, offset: Int): String {
        if (offset == 0) return markdown
        return markdown.split("\n").joinToString("\n") { line ->
            val (index, caption) = figure(line.trimSpaces()) ?: return@joinToString line
            "![$caption](image:${index + offset})"
        }
    }

    /**
     * Two or more sets of one kind as a new set named [name] (iOS StudySet.combined):
     * every picture re-based into the joined pool, a book's `image:N` lines too,
     * every set's sources kept, and every item given a new id.
     */
    fun combined(members: List<StudySet>, name: String): StudySet? {
        val first = members.firstOrNull() ?: return null
        if (members.size < 2 || members.any { it.kind != first.kind }) return null
        var out = StudySet(name = name, subject = first.subject, kind = first.kind)
        for (m in members) {
            val base = out.images.size
            val sources = out.sources + m.sources.filter { doc -> out.sources.none { it.id == doc.id } }
            out = out.copy(images = out.images + m.images, sources = sources)
            out = when (m.kind) {
                StudySetKind.MCQ -> out.copy(questions = out.questions + m.questions.map { q -> q.copy(id = newId(), imageIndex = q.imageIndex?.let { it + base }) })
                StudySetKind.ANKI -> out.copy(cards = out.cards + m.cards.map { c -> c.copy(id = newId(), imageIndex = c.imageIndex?.let { it + base }) })
                StudySetKind.BOOK -> out.copy(bookMarkdown = out.bookMarkdown + (if (out.bookMarkdown.isEmpty()) "" else "\n\n") + rebased(m.bookMarkdown, base))
                StudySetKind.OSCE -> out.copy(osceChecklists = out.osceChecklists + m.osceChecklists.map { it.copy(id = newId()) })
                StudySetKind.NARRATE -> out.copy(narrateSegments = out.narrateSegments + m.narrateSegments.map { it.copy(id = newId()) })
                StudySetKind.CASES -> out.copy(caseFiles = out.caseFiles + m.caseFiles.map { it.copy(id = newId()) })
            }
        }
        return out
    }

    private val figureLine = Regex("""^!\[([^\]]*)\]\(image:(\d+)\)\s*$""")

    /** `![caption](image:3)`: the picture's index into StudySet.images and its caption (iOS BookFigures.parse). */
    fun figure(line: String): Pair<Int, String>? {
        val m = figureLine.find(line) ?: return null
        val index = m.groupValues[2].toIntOrNull() ?: return null
        return index to m.groupValues[1]
    }
}
