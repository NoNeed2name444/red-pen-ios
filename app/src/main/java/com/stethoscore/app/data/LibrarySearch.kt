package com.stethoscore.app.data

import java.text.Normalizer

/**
 * Search that finds the item, not just the set it is in (iOS LibrarySearch).
 *
 * An index of every question, card, note and set, built whenever the library
 * changes, so a search lists the matching items themselves, each with the
 * phrase that matched marked, and a tap goes straight to it. Pure: no view and
 * no store, so it runs (and is tested) anywhere.
 *
 * Ranges are in the snippet's own characters (UTF-16 units here, Characters on
 * iOS; the same for the text a library holds).
 */
object LibrarySearch {

    /** What the search looks through: everything, or one kind of thing. */
    enum class Scope(val title: String) {
        ALL("All"), QUESTIONS("Questions"), CARDS("Cards"), NOTES("Notes"), LECTURES("Lectures");

        fun admits(kind: Kind): Boolean = when (this) {
            ALL -> true
            QUESTIONS -> kind == Kind.QUESTION
            CARDS -> kind == Kind.CARD
            NOTES -> kind == Kind.NOTE
            LECTURES -> kind == Kind.LECTURE
        }
    }

    enum class Kind(val rawValue: String, val label: String) {
        SET("set", "Set"), QUESTION("question", "Question"), CARD("card", "Card"),
        NOTE("note", "Note"), LECTURE("lecture", "Lecture")
    }

    /** A note as the index reads it; the caller copies out what is needed. */
    data class NoteText(val id: String, val title: String, val body: String, val tags: List<String> = emptyList())

    /** One searchable thing. `folded` holds the tags' words too. */
    data class Entry(
        val kind: Kind, val setId: String?, val itemId: String?, val title: String, val detail: String,
        val setName: String, val folded: String, val tags: List<String> = emptyList()
    )

    /** A lecture a set was made from, searched page by page with SourceSearch. */
    data class Lecture(val setId: String, val setName: String, val source: SourceDoc)

    data class Index(val entries: List<Entry> = emptyList(), val lectures: List<Lecture> = emptyList()) {
        val isEmpty: Boolean get() = entries.isEmpty() && lectures.isEmpty()
    }

    /** One result, with the text to show and where in it the match is. */
    data class Hit(
        val kind: Kind, val setId: String?, val itemId: String?, val page: Int?, val snippet: String,
        val range: IntRange, val setName: String, val sourceName: String = ""
    ) {
        val id: String get() {
            val item = itemId ?: setId ?: sourceName
            val at = page?.let { "p$it" } ?: ""
            return kind.rawValue + ":" + item + at + ":" + range.first
        }
    }

    data class Results(
        val query: String = "", val scope: Scope = Scope.ALL,
        /** Sets: the ones whose name or subject matched first, then those that only hold a matching item. */
        val sets: List<String> = emptyList(),
        /** Questions, cards, notes and lecture pages, capped. */
        val items: List<Hit> = emptyList(),
        /** True when there were more items than the cap. */
        val more: Boolean = false
    ) {
        val isEmpty: Boolean get() = sets.isEmpty() && items.isEmpty()
    }

    /** Items at most, the "first 50". */
    const val itemLimit = 50
    /** Text each side of a match in a snippet. */
    const val context = 48

    // building

    fun build(sets: List<StudySet>, notes: List<NoteText>): Index {
        val entries = mutableListOf<Entry>()
        val lectures = mutableListOf<Lecture>()
        for (set in sets) {
            appendEntries(set, entries)
            for (source in set.sources) if (source.pages.isNotEmpty()) lectures += Lecture(set.id, set.name, source)
        }
        for (note in notes) {
            val detail = note.body + "\n" + note.tags.joinToString(" ")
            entries += entry(Kind.NOTE, null, note.id, note.title, detail, "Ideas", note.tags)
        }
        return Index(entries, lectures)
    }

    private fun appendEntries(set: StudySet, entries: MutableList<Entry>) {
        val about = set.subject + "\n" + (set.exam ?: "")
        entries += entry(Kind.SET, set.id, null, set.name, about, set.name, set.tags)
        for (q in set.questions) {
            val detail = q.options.joinToString("\n") + "\n" + q.explanation
            entries += entry(Kind.QUESTION, set.id, q.id, q.stem, detail, set.name, CardTags.combined(q.tags, set.tags))
        }
        for (c in set.cards) {
            val detail = c.bullets.joinToString("\n") + "\n" + c.why
            entries += entry(Kind.CARD, set.id, c.id, cardTitle(c), detail, set.name, CardTags.combined(c.tags, set.tags))
        }
    }

    private fun entry(kind: Kind, set: String?, item: String?, title: String, detail: String, setName: String, tags: List<String> = emptyList()): Entry {
        // "#AK_Step1::Cardio" searchable as its words: AK, Step1, Cardio
        val tagWords = tags.joinToString(" ") { tagText(it) }
        val both = title + "\n" + detail + "\n" + tagWords
        return Entry(kind, set, item, title, detail, setName, fold(both), tags)
    }

    /** A tag as words: "#AK_Step1::Cardio" reads "AK Step1 Cardio". */
    fun tagText(tag: String): String = tag.replace("::", " ").replace("_", " ").replace("#", "")

    /** A card as it reads on its front: a cloze with its gaps filled in. */
    fun cardTitle(card: AnkiCard): String = if (card.type == AnkiCardType.CLOZE) clozeBare(card.clozeText) else card.displayFront

    /** "{{c1::Warfarin::drug}} needs INR" -> "Warfarin needs INR". */
    fun clozeBare(text: String): String {
        val out = StringBuilder()
        var rest = text
        while (true) {
            val open = rest.indexOf("{{")
            if (open < 0) break
            out.append(rest, 0, open)
            val after = rest.substring(open + 2)
            val close = after.indexOf("}}")
            if (close < 0) {
                out.append(rest.substring(open))
                return out.toString()
            }
            val inside = after.substring(0, close)
            val parts = inside.split("::")
            out.append(if (parts.size >= 2) parts[1] else inside)
            rest = after.substring(close + 2)
        }
        out.append(rest)
        return out.toString()
    }

    // text

    /** Lower-cased and without accents: "Édème" and "edeme" alike. */
    fun fold(text: String): String = TextFold.fold(text)

    /** The words of a text, folded, two letters or more. */
    fun tokens(text: String): List<String> =
        fold(text).split(Regex("[^\\p{L}\\p{N}]+")).filter { it.length >= 2 }

    /** The first place `needle` appears in `text`, ignoring case and accents, as start until end. */
    fun find(needle: String, text: String): IntRange? {
        if (needle.isEmpty()) return null
        return TextFold.find(needle, text, 0)
    }

    /** Text around a match, on one line, and where the match is inside it. */
    fun snippet(text: String, match: IntRange, context: Int = LibrarySearch.context): Pair<String, IntRange> {
        val start = match.first
        val end = match.last + 1
        val before = maxOf(0, start - context)
        val after = minOf(text.length, end + context)
        val lead = flatten(text.substring(before, start))
        val body = flatten(text.substring(start, end))
        val tail = flatten(text.substring(end, after))
        val front = if (before > 0) "…" else ""
        val back = if (after < text.length) "…" else ""
        val head = front + lead.trimStart(' ')
        val line = head + body + tail.trimEnd(' ') + back
        return line to (head.length until head.length + body.length)
    }

    private fun flatten(text: String) = text.replace("\n", " ")

    // searching

    /**
     * Every match for [query] within [scope]: a phrase first, then every word
     * anywhere; `#cardio` or `tag:cardio` asks for a tag (CardTags.query).
     */
    fun search(query: String, index: Index, scope: Scope, limit: Int = itemLimit): Results {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return Results(trimmed, scope)
        val asked = CardTags.query(trimmed)
        val wanted = asked.second
        val phrase = asked.first.trim()
        val needle = fold(phrase)
        val words = needle.split(" ").filter { it.isNotEmpty() }

        val named = mutableListOf<String>()
        val holding = mutableListOf<String>()
        val seenSets = mutableSetOf<String>()
        val strong = mutableListOf<Hit>()
        val weak = mutableListOf<Hit>()
        var total = 0
        // one letter matches almost everything; sets only until there are two
        val itemsToo = phrase.length >= 2 || wanted.isNotEmpty()

        for (entry in index.entries) {
            if (!CardTags.matches(entry.tags, wanted)) continue
            if (!(phrase.isEmpty() || matches(entry.folded, needle, words))) continue
            if (entry.kind == Kind.SET) {
                val id = entry.setId
                if (id != null && seenSets.add(id)) named += id
                continue
            }
            if (!itemsToo) continue
            entry.setId?.let { if (it !in seenSets) holding += it }
            if (!scope.admits(entry.kind)) continue
            total += 1
            if (strong.size + weak.size >= limit) continue
            val (hit, inTitle) = makeHit(entry, phrase, words)
            if (inTitle) strong += hit else weak += hit
        }
        val ordered = named.toMutableList()
        val added = named.toMutableSet()
        for (id in holding) if (added.add(id)) ordered += id

        var items = strong + weak
        // lecture pages carry no tags: only a plain search reaches them
        if (itemsToo && wanted.isEmpty() && (scope == Scope.ALL || scope == Scope.LECTURES)) {
            val room = maxOf(0, limit - items.size)
            val pages = lectureHits(phrase, index.lectures, room + 1)
            total += pages.size
            items = items + pages.take(room)
        }
        val capped = items.take(limit)
        return Results(trimmed, scope, if (scope == Scope.ALL) ordered else emptyList(), capped, total > capped.size)
    }

    fun matches(folded: String, needle: String, words: List<String>): Boolean {
        if (folded.contains(needle)) return true
        if (words.size <= 1) return false
        return words.all { folded.contains(it) }
    }

    private fun makeHit(entry: Entry, phrase: String, words: List<String>): Pair<Hit, Boolean> {
        val first = words.firstOrNull() ?: phrase
        val lookFor = if (phrase.isEmpty()) emptyList() else listOf(phrase, first)
        for (needle in lookFor) {
            find(needle, entry.title)?.let { return hit(entry, entry.title, it) to true }
            find(needle, entry.detail)?.let { return hit(entry, entry.detail, it) to false }
        }
        // matched only across the join of title and detail: show the title
        val plain = Hit(entry.kind, entry.setId, entry.itemId, null, entry.title.take(context * 2), 0 until 0, entry.setName)
        return plain to true
    }

    private fun hit(entry: Entry, text: String, match: IntRange): Hit {
        val (line, range) = snippet(text, match)
        return Hit(entry.kind, entry.setId, entry.itemId, null, line, range, entry.setName)
    }

    /** One hit per lecture page, in reading order, through SourceSearch. */
    fun lectureHits(phrase: String, lectures: List<Lecture>, limit: Int): List<Hit> {
        val out = mutableListOf<Hit>()
        for (lecture in lectures) {
            if (out.size >= limit) break
            val found = SourceSearch.hits(phrase, lecture.source.pages, context, 200)
            val pages = mutableSetOf<Int>()
            for (h in found) {
                if (!pages.add(h.page)) continue
                out += Hit(Kind.LECTURE, lecture.setId, lecture.source.id, h.page, h.snippet, h.range, lecture.setName, lecture.source.name)
                if (out.size >= limit) break
            }
        }
        return out
    }

    // opening

    /** A copy of [set] that opens on question [id] and carries on, wrapping round. Null when it is not there. */
    fun opening(set: StudySet, id: String): StudySet? {
        val at = set.questions.indexOfFirst { it.id == id }
        if (at < 0) return null
        return set.copy(questions = set.questions.drop(at) + set.questions.take(at))
    }
}

/** Case- and accent-insensitive comparison, as Swift's [.caseInsensitive, .diacriticInsensitive]. */
internal object TextFold {
    private val marks = Regex("\\p{Mn}+")

    fun fold(text: String): String = marks.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase()

    /** The first match of [needle] in [text] at or after [from], in [text]'s own indices. */
    fun find(needle: String, text: String, from: Int): IntRange? = Folded(text).find(needle, from)

    /** A text folded once, with each folded character's place in the original, for repeated finds. */
    class Folded(val text: String) {
        private val folded: String
        private val origin: IntArray

        init {
            val out = StringBuilder()
            val at = ArrayList<Int>()
            var i = 0
            while (i < text.length) {
                val step = Character.charCount(text.codePointAt(i))
                val piece = fold(text.substring(i, i + step))
                out.append(piece)
                repeat(piece.length) { at += i }
                i += step
            }
            folded = out.toString()
            origin = at.toIntArray()
        }

        fun find(needle: String, from: Int = 0): IntRange? {
            val want = fold(needle)
            if (want.isEmpty()) return null
            var startAt = 0
            while (startAt < origin.size && origin[startAt] < from) startAt++
            val hit = folded.indexOf(want, startAt)
            if (hit < 0) return null
            val start = origin[hit]
            val lastOrigin = origin[hit + want.length - 1]
            var end = lastOrigin + Character.charCount(text.codePointAt(lastOrigin))
            // carry on over marks the fold dropped, as a Character would hold them
            while (end < text.length) {
                val step = Character.charCount(text.codePointAt(end))
                if (fold(text.substring(end, end + step)).isNotEmpty()) break
                end += step
            }
            return start until end
        }
    }
}

/**
 * Tags on cards, questions and sets (iOS CardTags), on Anki's rules: no spaces
 * inside a tag, `::` nests, case is ignored, and a parent tag finds what is
 * filed under it.
 */
object CardTags {
    /** The longest one tag may be. */
    const val maxLength = 120
    /** The most tags one card, question or set keeps. */
    const val maxPerItem = 20

    /** A tag as it is stored: trimmed, inner spaces joined with "_", no empty `::` levels. */
    fun normalized(raw: String): String? {
        val joined = raw.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString("_")
        val tag = joined.split("::").filter { it.isNotEmpty() }.joinToString("::").take(maxLength)
        return tag.ifEmpty { null }
    }

    /** Tags typed in one go - "cardio, pharm renal" - as a list. */
    fun parse(typed: String): List<String> {
        val out = mutableListOf<String>()
        val listed = typed.contains(",") || typed.contains(";")
        for (piece in typed.split(',', ';', '\n')) {
            val parts = if (listed) listOf(piece) else piece.split(" ").filter { it.isNotEmpty() }
            for (part in parts) {
                val tag = normalized(part) ?: continue
                if (contains(out, tag)) continue
                out += tag
            }
        }
        return out.take(maxPerItem)
    }

    /** A list with one more tag, or the same list when it is already there. */
    fun adding(raw: String, tags: List<String>): List<String> {
        val list = tags.toMutableList()
        for (tag in parse(raw)) if (!contains(list, tag) && list.size < maxPerItem) list += tag
        return list
    }

    /** A list without one tag. */
    fun removing(tag: String, tags: List<String>): List<String> = tags.filterNot { it.equals(tag, ignoreCase = true) }

    fun contains(list: List<String>, tag: String): Boolean = list.any { it.equals(tag, ignoreCase = true) }

    /** The last level, for a chip: "#AK_Step1::Cardio" shows as "Cardio". */
    fun label(tag: String): String = tag.split("::").lastOrNull { it.isNotEmpty() } ?: tag

    /** Search text split into words and wanted tags: `tag:pharm` and `#pharm` are tags. */
    fun query(text: String): Pair<String, List<String>> {
        val words = mutableListOf<String>()
        val tags = mutableListOf<String>()
        for (word in text.split(" ").filter { it.isNotEmpty() }) {
            if (word.lowercase().startsWith("tag:") && word.length > 4) {
                normalized(word.drop(4))?.let { tags += it }
            } else if (word.startsWith("#") && word.length > 1) {
                normalized(word.drop(1))?.let { tags += it }
            } else {
                words += word
            }
        }
        return words.joinToString(" ") to tags
    }

    /** Whether one tag is the wanted one or filed under it, whole levels only, case and "#" aside. */
    fun isUnder(tag: String, wanted: String): Boolean {
        val have = levels(tag)
        val want = levels(wanted)
        if (want.isEmpty() || want.size > have.size) return false
        for (start in 0..(have.size - want.size)) if (have.subList(start, start + want.size) == want) return true
        return false
    }

    private fun levels(tag: String): List<String> = tag.split("::").map { bare(it) }.filter { it.isNotEmpty() }

    private fun bare(tag: String): String = tag.lowercase().trimStart('#')

    /** Whether an item with [tags] has every wanted tag. */
    fun matches(tags: List<String>, wanted: List<String>): Boolean {
        if (wanted.isEmpty()) return true
        return wanted.all { want -> tags.any { isUnder(it, want) } }
    }

    /** The part of a set that carries the wanted tags; null when nothing in it does. */
    fun tagged(set: StudySet, wanted: List<String>): StudySet? {
        if (wanted.isEmpty() || matches(set.tags, wanted)) return set
        val out = set.copy(
            cards = set.cards.filter { matches(combined(it.tags, set.tags), wanted) },
            questions = set.questions.filter { matches(combined(it.tags, set.tags), wanted) })
        return if (out.cards.isEmpty() && out.questions.isEmpty()) null else out
    }

    /** An item's tags with its set's added, since a set's tag covers every card in it. */
    fun combined(own: List<String>, set: List<String>): List<String> = own + set

    /** Every tag in the library with how many items carry it, most used first. */
    fun counts(sets: List<StudySet>): List<Pair<String, Int>> {
        val tally = LinkedHashMap<String, Pair<String, Int>>()
        fun add(tags: List<String>) {
            for (tag in tags) {
                val key = tag.lowercase()
                val now = tally[key]
                tally[key] = (now?.first ?: tag) to ((now?.second ?: 0) + 1)
            }
        }
        for (set in sets) {
            add(set.tags)
            set.cards.forEach { add(it.tags) }
            set.questions.forEach { add(it.tags) }
        }
        return tally.values.sortedWith { a, b -> if (a.second == b.second) a.first.compareTo(b.first) else b.second - a.second }
    }

    /** Known tags that start with, or contain, what is typed; never one already chosen. */
    fun suggestions(typed: String, known: List<Pair<String, Int>>, chosen: List<String>, limit: Int = 8): List<String> {
        val needle = typed.trim().lowercase()
        val open = known.filter { !contains(chosen, it.first) }
        if (needle.isEmpty()) return open.take(limit).map { it.first }
        val starts = open.filter { bare(it.first).startsWith(needle) || label(it.first).lowercase().startsWith(needle) }
        val startTags = starts.map { it.first }
        val inside = open.filter { it.first.lowercase().contains(needle) && it.first !in startTags }
        return (starts + inside).take(limit).map { it.first }
    }
}

/** Finding a word in a lecture (iOS SourceSearch). */
object SourceSearch {
    /** One place a search term appears; `range` is where it sits in `snippet`. */
    data class Hit(val page: Int, val range: IntRange, val snippet: String) {
        val id: String get() = "$page-${range.first}-${snippet.length}"
    }

    /** Every appearance of [term], in reading order, case and accents aside. */
    fun hits(term: String, pages: List<SourcePage>, context: Int = 40, limit: Int = 200): List<Hit> {
        val needle = term.trim()
        if (needle.length < 2) return emptyList()
        val found = mutableListOf<Hit>()
        for (page in pages) {
            val text = page.text
            val folded = TextFold.Folded(text)
            var from = 0
            while (found.size < limit) {
                val match = folded.find(needle, from) ?: break
                val (snippet, offset) = window(text, match, context)
                val length = match.last + 1 - match.first
                found += Hit(page.number, offset until offset + length, snippet)
                // past the END of this match, so "aa" in "aaaa" never overlaps
                from = match.last + 1
                if (from >= text.length) break
            }
            if (found.size >= limit) break
        }
        return found
    }

    private fun window(text: String, match: IntRange, context: Int): Pair<String, Int> {
        val before = maxOf(0, match.first - context)
        val after = minOf(text.length, match.last + 1 + context)
        var snippet = text.substring(before, after).replace("\n", " ")
        var offset = match.first - before
        val trimmed = snippet.trimStart(' ')
        offset -= snippet.length - trimmed.length
        snippet = trimmed.trimEnd(' ')
        if (before > 0) { snippet = "…" + snippet; offset += 1 }
        if (after < text.length) snippet += "…"
        return snippet to maxOf(0, offset)
    }

    /** How many pages a term appears on. */
    fun pagesMatched(hits: List<Hit>): Int = hits.map { it.page }.toSet().size
}
