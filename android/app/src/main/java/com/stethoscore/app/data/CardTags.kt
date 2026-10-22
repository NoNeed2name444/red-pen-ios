package com.stethoscore.app.data

// A port of ios/RedPen/Shared/CardTags.swift (fed0105): tags on cards,
// questions and sets. Tags follow Anki's rules: no spaces inside a tag, `::`
// nests one under another, case is ignored when matching, and asking for a
// parent finds everything filed under it. iOS's optional list is a nullable
// list here; a model stores null as an empty list. Pure Kotlin (CardTagsTest:
// DataIOTests' tags cases).

object CardTags {

    /** The longest one tag may be. */
    const val maxLength = 120
    /** The most tags one card, question or set keeps. */
    const val maxPerItem = 20

    /** A tag and how many items in the library carry it. */
    data class Count(val tag: String, val count: Int)

    private fun words(text: String): List<String> {
        val out = mutableListOf<String>()
        val word = StringBuilder()
        for (ch in text) {
            if (ch.isWhitespace()) { if (word.isNotEmpty()) { out += word.toString(); word.clear() } } else word.append(ch)
        }
        if (word.isNotEmpty()) out += word.toString()
        return out
    }

    /** A tag as it is stored: trimmed, inner spaces joined with "_", no empty `::` levels. Null when nothing is left. */
    fun normalized(raw: String): String? {
        val joined = words(raw).joinToString("_")
        val levels = joined.split("::").filter { it.isNotEmpty() }
        val tag = levels.joinToString("::").take(maxLength)
        return tag.ifEmpty { null }
    }

    /** Tags typed in one go - "cardio, pharm renal" - as a list. */
    fun parse(typed: String): List<String> {
        val pieces = typed.split(',', ';', '\n')
        val out = mutableListOf<String>()
        val commaList = typed.contains(",") || typed.contains(";")
        for (piece in pieces) {
            // a comma list keeps its spaces as part of each tag; a plain list of words is one tag per word
            val parts = if (commaList) listOf(piece) else piece.split(' ').filter { it.isNotEmpty() }
            for (part in parts) {
                val tag = normalized(part) ?: continue
                if (contains(out, tag)) continue
                out += tag
            }
        }
        return out.take(maxPerItem)
    }

    /** A list with one more tag, or the same list when it is already there. */
    fun adding(raw: String, to: List<String>?): List<String>? {
        val list = (to ?: emptyList()).toMutableList()
        for (tag in parse(raw)) if (!contains(list, tag) && list.size < maxPerItem) list += tag
        return list.ifEmpty { null }
    }

    /** A list without one tag. Null once none are left, so an untagged item stores nothing. */
    fun removing(tag: String, from: List<String>?): List<String>? {
        val list = (from ?: emptyList()).filter { !it.equals(tag, ignoreCase = true) }
        return list.ifEmpty { null }
    }

    fun contains(list: List<String>, tag: String): Boolean = list.any { it.equals(tag, ignoreCase = true) }

    /** The last level, for a chip: "#AK_Step1::Cardio" shows as "Cardio". */
    fun label(tag: String): String = tag.split("::").lastOrNull { it.isNotEmpty() } ?: tag

    // MARK: - search

    /** Search text split into words and wanted tags: `tag:pharm` and `#pharm` are tags. */
    fun query(text: String): Pair<String, List<String>> {
        val words = mutableListOf<String>()
        val tags = mutableListOf<String>()
        for (word in text.split(' ').filter { it.isNotEmpty() }) {
            val lower = word.lowercase()
            if (lower.startsWith("tag:") && word.length > 4) {
                normalized(word.drop(4))?.let { tags += it }
            } else if (word.startsWith("#") && word.length > 1) {
                normalized(word.drop(1))?.let { tags += it }
            } else words += word
        }
        return words.joinToString(" ") to tags
    }

    /** Whether one tag is the wanted one or filed under it, whole levels only, ignoring case and a leading "#". */
    fun tag(tag: String, isUnder: String): Boolean {
        val have = levels(tag)
        val want = levels(isUnder)
        if (want.isEmpty() || want.size > have.size) return false
        for (start in 0..(have.size - want.size)) if (have.subList(start, start + want.size) == want) return true
        return false
    }

    private fun levels(tag: String): List<String> = tag.split("::").map(::bare).filter { it.isNotEmpty() }

    private fun bare(tag: String): String = tag.lowercase().trimStart('#')

    /** Whether an item with [tags] has every wanted tag. */
    fun matches(tags: List<String>?, wanted: List<String>): Boolean {
        if (wanted.isEmpty()) return true
        val have = tags ?: emptyList()
        return wanted.all { want -> have.any { tag(it, want) } }
    }

    /** The part of a set that carries the wanted tags; null when nothing in it does. */
    fun tagged(set: StudySet, with: List<String>): StudySet? {
        if (with.isEmpty()) return set
        if (matches(set.tags, with)) return set
        val out = set.copy(
            cards = set.cards.filter { matches(combined(it.tags, set.tags), with) },
            questions = set.questions.filter { matches(combined(it.tags, set.tags), with) },
        )
        if (out.cards.isEmpty() && out.questions.isEmpty()) return null
        return out
    }

    /** An item's tags with its set's added, since a set's tag covers every card in it. */
    fun combined(own: List<String>?, set: List<String>?): List<String> = (own ?: emptyList()) + (set ?: emptyList())

    // MARK: - counting

    /** Every tag in the library with how many items carry it, most used first. */
    fun counts(sets: List<StudySet>): List<Count> {
        val tally = LinkedHashMap<String, Count>()
        fun add(tags: List<String>) {
            for (tag in tags) {
                val key = tag.lowercase()
                val now = tally[key]
                tally[key] = Count(now?.tag ?: tag, (now?.count ?: 0) + 1)
            }
        }
        for (set in sets) {
            add(set.tags)
            set.cards.forEach { add(it.tags) }
            set.questions.forEach { add(it.tags) }
        }
        return tally.values.sortedWith { a, b -> if (a.count == b.count) a.tag.compareTo(b.tag) else b.count.compareTo(a.count) }
    }

    /** Known tags that start with what is typed, or contain it, most used first, never one already chosen. */
    fun suggestions(typed: String, known: List<Count>, excluding: List<String>?, limit: Int = 8): List<String> {
        val needle = typed.trim { it == ' ' || it == '\t' }.lowercase()
        val taken = excluding ?: emptyList()
        val open = known.filter { !contains(taken, it.tag) }
        if (needle.isEmpty()) return open.take(limit).map { it.tag }
        val starts = open.filter { bare(it.tag).startsWith(needle) || label(it.tag).lowercase().startsWith(needle) }
        val startTags = starts.map { it.tag }
        val inside = open.filter { it.tag.lowercase().contains(needle) && it.tag !in startTags }
        return (starts + inside).take(limit).map { it.tag }
    }
}
