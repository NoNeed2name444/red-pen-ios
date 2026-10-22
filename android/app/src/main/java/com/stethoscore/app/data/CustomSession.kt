package com.stethoscore.app.data

/**
 * A study session built to order - Anki's filtered deck (iOS CustomSession):
 * "the cards I got wrong this week, cardiology", "everything the accuracy
 * engine flagged", "what matches this search". Nothing is saved to the
 * library; the items keep their own ids, so every answer and rating lands on
 * the item it came from. Pure, like LibrarySearch.
 */
object CustomSession {

    /** Which kinds of item the session takes. */
    enum class Include(val title: String) { BOTH("Both"), QUESTIONS("Questions"), CARDS("Cards") }

    /** How the session is sat. */
    enum class Mode(val title: String) { QUIZ("Quiz"), REVIEW("Review") }

    data class Filter(
        /** Words that must be in the item, as the library search reads them. */
        var text: String = "",
        var include: Include = Include.BOTH,
        /** Missed within this many days: 7 is "failed this week". */
        var failedWithinDays: Int? = null,
        /** A tag or topic: the item's tags or its set's, the set's subject, exam or name, or a #tag in the text. */
        var tag: String = "",
        /** Only sets filed under this subject. */
        var subject: String? = null,
        /** Only cards that are due now. */
        var dueOnly: Boolean = false,
        /** Only items the accuracy engine flagged or asked to check. */
        var accuracyFlagged: Boolean = false,
        /** Only questions the student flagged. */
        var myFlags: Boolean = false,
        /** At most this many items, most recently missed first. */
        var limit: Int = 40
    ) {
        /** Whether anything narrows the library at all. */
        val narrows: Boolean get() {
            val words = text.trim().isNotEmpty()
            val tagged = tag.trim().isNotEmpty()
            val flags = accuracyFlagged || myFlags || dueOnly
            return words || tagged || flags || failedWithinDays != null || subject != null
        }
    }

    /** A card's standing in the schedule, as far as a filter cares (epoch ms). */
    data class CardState(val due: Long, val lapses: Int, val ratedAt: Long, val suspended: Boolean = false)

    /** What the store knows about the student's history, copied out. */
    data class Context(
        /** When each question was last answered wrong. */
        val lastMissed: MutableMap<String, Long> = mutableMapOf(),
        val cards: MutableMap<String, CardState> = mutableMapOf(),
        /** Items the accuracy engine graded Flagged or Check this. */
        var accuracyFlagged: Set<String> = emptySet(),
        /** Questions the student flagged. */
        var flagged: Set<String> = emptySet(),
        var now: Long = System.currentTimeMillis()
    )

    /** One item that passed, with the set it lives in. */
    data class Pick(val setId: String, val question: MCQQuestion? = null, val card: AnkiCard? = null, val missed: Long? = null)

    data class Plan(val questions: List<Pick> = emptyList(), val cards: List<Pick> = emptyList()) {
        val count: Int get() = questions.size + cards.size
        val isEmpty: Boolean get() = count == 0
    }

    data class Quiz(val set: StudySet, val skipped: Int)

    private const val DAY_MS = 86_400_000L

    /** The items that pass [filter], most recently missed first; each item once. */
    fun plan(sets: List<StudySet>, filter: Filter, context: Context): Plan {
        val words = LibrarySearch.fold(filter.text.trim())
        val wordList = words.split(" ").filter { it.isNotEmpty() }
        val typed = LibrarySearch.fold(filter.tag.trim())
        val tag = typed.removePrefix("#")
        val wanted = CardTags.normalized(filter.tag)?.let { listOf(it) } ?: emptyList()
        val since = filter.failedWithinDays?.let { context.now - it * DAY_MS }
        val questions = mutableListOf<Pick>()
        val cards = mutableListOf<Pick>()
        val seen = mutableSetOf<String>()
        for (set in sets) {
            if (filter.subject != null && subjectName(set) != filter.subject) continue
            val setTagged = tag.isEmpty() || setMatches(set, tag) || (wanted.isNotEmpty() && CardTags.matches(set.tags, wanted))
            if (filter.include != Include.CARDS && set.kind == StudySetKind.MCQ) {
                for (q in set.questions) {
                    if (q.id in seen) continue
                    val text = q.stem + "\n" + q.options.joinToString("\n") + "\n" + q.explanation
                    val tagged = setTagged || CardTags.matches(q.tags, wanted)
                    if (!passes(text, q.id, words, wordList, tag, tagged, filter, context)) continue
                    val missed = context.lastMissed[q.id]
                    if (since != null && (missed == null || missed < since)) continue
                    if (filter.dueOnly) continue
                    seen += q.id
                    questions += Pick(set.id, question = q, missed = missed)
                }
            }
            if (filter.include != Include.QUESTIONS && set.kind == StudySetKind.ANKI) {
                for (c in set.cards) {
                    if (c.id in seen) continue
                    val text = LibrarySearch.cardTitle(c) + "\n" + c.bullets.joinToString("\n") + "\n" + c.why
                    val tagged = setTagged || CardTags.matches(c.tags, wanted)
                    if (!passes(text, c.id, words, wordList, tag, tagged, filter, context)) continue
                    val state = context.cards[c.id]
                    if (state?.suspended == true) continue
                    if (filter.myFlags) continue
                    if (filter.dueOnly && (state == null || state.due > context.now)) continue
                    var missed: Long? = null
                    if (since != null) {
                        if (state == null || state.lapses <= 0 || state.ratedAt < since) continue
                        missed = state.ratedAt
                    }
                    seen += c.id
                    cards += Pick(set.id, card = c, missed = missed)
                }
            }
        }
        return trimmed(Plan(questions, cards), filter.limit)
    }

    private fun passes(text: String, id: String, words: String, wordList: List<String>, tag: String,
                       setTagged: Boolean, filter: Filter, context: Context): Boolean {
        if (filter.accuracyFlagged && id !in context.accuracyFlagged) return false
        if (filter.myFlags && id !in context.flagged) return false
        val folded = if (words.isEmpty() && setTagged) null else LibrarySearch.fold(text)
        if (words.isNotEmpty() && folded != null && !LibrarySearch.matches(folded, words, wordList)) return false
        if (!setTagged && folded != null && !folded.contains("#$tag")) return false
        return true
    }

    /** The set's subject, name or exam holds the tag; a leading "#" is optional. */
    fun setMatches(set: StudySet, tag: String): Boolean {
        val bare = tag.removePrefix("#")
        if (bare.isEmpty()) return true
        return LibrarySearch.fold(set.subject + "\n" + set.name + "\n" + (set.exam ?: "")).contains(bare)
    }

    /** A set's subject as the Progress screen groups it: blank is "General". */
    fun subjectName(set: StudySet): String = set.subject.trim().ifEmpty { "General" }

    /** The subjects that hold questions or cards, for the sheet's picker. */
    fun subjects(sets: List<StudySet>): List<String> =
        sets.filter { it.kind == StudySetKind.MCQ || it.kind == StudySetKind.ANKI }
            .map { subjectName(it) }.toSet().sortedWith(String.CASE_INSENSITIVE_ORDER)

    /** Most recently missed first, then as found; the cap shared in proportion. */
    fun trimmed(plan: Plan, limit: Int): Plan {
        val cap = maxOf(1, limit)
        val out = Plan(ordered(plan.questions), ordered(plan.cards))
        if (out.count <= cap) return out
        val share = out.questions.size.toDouble() / out.count
        var keepQ = Math.round(cap * share).toInt()
        keepQ = minOf(out.questions.size, maxOf(if (out.questions.isEmpty()) 0 else 1, keepQ))
        val keepC = minOf(out.cards.size, cap - keepQ)
        return Plan(out.questions.take(keepQ), out.cards.take(keepC))
    }

    private fun ordered(picks: List<Pick>): List<Pick> = picks.sortedByDescending { it.missed ?: Long.MIN_VALUE }

    /** The session as a quiz: questions as they are, cards turned into questions from their decks. */
    fun quiz(plan: Plan, sets: List<StudySet>, name: String, seed: ULong = 0uL): Quiz {
        val byId = sets.reversed().associateBy { it.id }
        val images = mutableListOf<String>()
        val bases = mutableMapOf<String, Int>()
        val questions = mutableListOf<MCQQuestion>()
        for (pick in plan.questions) {
            val q = pick.question ?: continue
            questions += q.copy(imageIndex = remap(q.imageIndex, byId[pick.setId], images, bases))
        }
        val cards = plan.cards.mapNotNull { it.card }
        var skipped = 0
        if (cards.isNotEmpty()) {
            val deckIds = plan.cards.map { it.setId }.toSet()
            val pool = sets.filter { it.id in deckIds }.flatMap { it.cards }
            val built = QuizFromCards.build(cards, pool, seed = seed)
            questions += built.questions
            skipped = built.skipped.size
        }
        return Quiz(StudySet(name = name, subject = "Custom", kind = StudySetKind.MCQ, questions = questions, images = images), skipped)
    }

    /** The session as a deck to review: the cards themselves, ids kept. */
    fun deck(plan: Plan, sets: List<StudySet>, name: String): StudySet {
        val byId = sets.reversed().associateBy { it.id }
        val images = mutableListOf<String>()
        val bases = mutableMapOf<String, Int>()
        val cards = plan.cards.mapNotNull { pick ->
            pick.card?.let { it.copy(imageIndex = remap(it.imageIndex, byId[pick.setId], images, bases)) }
        }
        return StudySet(name = name, subject = "Custom", kind = StudySetKind.ANKI, cards = cards, images = images)
    }

    /** An item's picture index in the session: the source set's pictures are copied in once. */
    fun remap(index: Int?, set: StudySet?, images: MutableList<String>, bases: MutableMap<String, Int>): Int? {
        if (index == null || set == null || index !in set.images.indices) return null
        bases[set.id]?.let { return it + index }
        val base = images.size
        images += set.images
        bases[set.id] = base
        return base + index
    }

    /** "Missed this week · Cardiology · #tag · “words”". */
    fun title(filter: Filter): String {
        val parts = mutableListOf<String>()
        if (filter.failedWithinDays == 7) parts += "Missed this week"
        else filter.failedWithinDays?.let { parts += "Missed in $it days" }
        if (filter.accuracyFlagged) parts += "Flagged for accuracy"
        if (filter.myFlags) parts += "My flags"
        if (filter.dueOnly) parts += "Due"
        filter.subject?.let { parts += it }
        val tag = filter.tag.trim()
        if (tag.isNotEmpty()) parts += if (tag.startsWith("#")) tag else "#$tag"
        val words = filter.text.trim()
        if (words.isNotEmpty()) parts += "“$words”"
        return if (parts.isEmpty()) "Custom session" else parts.joinToString(" · ")
    }
}
