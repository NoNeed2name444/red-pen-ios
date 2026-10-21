package com.stethoscore.app.reading

import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import java.text.Normalizer

// A port of ios/RedPen/Shared/SourceSearch.swift (fed0105): finding a word in
// a lecture, and reading a card's citation ("Immunology, p. 12") back apart so
// it can open the lecture at that page. Pure Kotlin (SourceTest).
//
// iOS counts a snippet's characters as Swift Characters; here they are the
// String's UTF-16 units, which are the same for text in the Basic
// Multilingual Plane (every lecture the tests and the samples hold).

/** Case and accent folding, with where each folded character came from. */
private class Folded(text: String) {
    val folded: String
    /** For each folded character, the index of the original character it came from. */
    val from: IntArray

    init {
        val out = StringBuilder()
        val map = ArrayList<Int>(text.length)
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            val width = Character.charCount(cp)
            val piece = fold(String(Character.toChars(cp)))
            for (c in piece) { out.append(c); map += i }
            i += width
        }
        folded = out.toString()
        from = map.toIntArray()
    }

    companion object {
        private val marks = Regex("\\p{Mn}+")
        fun fold(text: String): String =
            marks.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase()
    }
}

object SourceSearch {

    /** One place a search term appears, with enough text around it to read. */
    data class Hit(
        val page: Int,
        /** Where the match starts within [snippet], so the view can mark it without searching again. */
        val start: Int,
        /** Where it ends (exclusive). */
        val end: Int,
        val snippet: String,
    ) {
        val range: IntRange get() = start until end
        val id: String get() = "$page-$start-${snippet.length}"
    }

    /**
     * Every appearance of [term], in reading order. Case and accent
     * insensitive: nobody hunting for "oedema" wants to be told there is no
     * such word when the slide says "Oedema".
     */
    fun hits(term: String, pages: List<SourcePage>, context: Int = 40, limit: Int = 200): List<Hit> {
        val needle = term.trim()
        if (needle.length < 2) return emptyList()
        val wanted = Folded.fold(needle)
        if (wanted.isEmpty()) return emptyList()

        val found = mutableListOf<Hit>()
        for (page in pages) {
            val text = page.text
            val folded = Folded(text)
            var searchFrom = 0
            while (found.size < limit) {
                val at = folded.folded.indexOf(wanted, searchFrom)
                if (at < 0) break
                val lastFolded = at + wanted.length - 1
                val matchStart = folded.from[at]
                // past the original character the match's last folded character came from
                val lastOriginal = folded.from[lastFolded]
                val matchEnd = lastOriginal + Character.charCount(text.codePointAt(lastOriginal))
                val (snippet, offset) = window(text, matchStart, matchEnd, context)
                found += Hit(page.number, offset, offset + (matchEnd - matchStart), snippet)
                // past the END of this match, never one character on from its
                // start: "aa" in "aaaa" would otherwise match for ever
                searchFrom = lastFolded + 1
                if (matchEnd == text.length) break
            }
            if (found.size >= limit) break
        }
        return found
    }

    /**
     * A readable amount of text either side of a match, and where the match
     * sits inside it (returned, not recomputed: the snippet may hold the term
     * twice).
     */
    private fun window(text: String, matchStart: Int, matchEnd: Int, context: Int): Pair<String, Int> {
        val before = maxOf(0, matchStart - context)
        val after = minOf(text.length, matchEnd + context)
        var snippet = text.substring(before, after).replace("\n", " ")
        var offset = matchStart - before

        // leading and trailing ellipses are part of the snippet, so anything
        // trimmed from the front moves the offset with it
        val trimmedFront = snippet.length - snippet.trimStart(' ').length
        snippet = snippet.trimStart(' ')
        offset -= trimmedFront
        snippet = snippet.trimEnd(' ')

        if (before > 0) { snippet = "…$snippet"; offset += 1 }
        if (after < text.length) snippet += "…"
        return snippet to maxOf(0, offset)
    }

    /** How many pages a term appears on. */
    fun pagesMatched(hits: List<Hit>): Int = hits.map { it.page }.toSet().size

    /** Two names the same but for case and accents. */
    internal fun sameName(a: String, b: String): Boolean = Folded.fold(a) == Folded.fold(b)
}

/**
 * A card's citation, read back apart. The app writes "Immunology, p. 12"
 * (Provenance.label); reading one back turns it into somewhere to go.
 * Forgiving: "p12", "page 12", "pp. 12-14" all name a page.
 */
object Citation {

    data class Reference(val name: String, val page: Int)

    private val marker = Regex("(?:^|[,\\s(])p{1,2}\\.?\\s*(\\d+)|(?:^|[,\\s(])pages?\\s*(\\d+)", RegexOption.IGNORE_CASE)

    /**
     * The document a citation is pointing at, and the page in it: by name,
     * except when there is only one source, which it can only mean.
     */
    fun resolve(label: String?, sources: List<SourceDoc>): Pair<SourceDoc, Int>? {
        val reference = read(label) ?: return null
        if (sources.isEmpty()) return null
        val named = sources.firstOrNull { SourceSearch.sameName(it.name, reference.name) }
        val source = named ?: (if (sources.size == 1) sources[0] else null) ?: return null
        // a citation to a page the document does not have is not somewhere to go
        if (source.page(reference.page) == null) return null
        return source to reference.page
    }

    /** The citations that point at this page of this source. */
    fun citing(source: SourceDoc, page: Int, labels: List<String>, sources: List<SourceDoc>): List<String> =
        labels.filter { label ->
            val hit = resolve(label, sources) ?: return@filter false
            hit.first.id == source.id && hit.second == page
        }

    fun read(label: String?): Reference? {
        if (label.isNullOrEmpty()) return null
        val match = marker.find(label) ?: return null
        var page: Int? = null
        for (group in 1..2) {
            val value = match.groups[group]?.value ?: continue
            page = value.toIntOrNull()
            break
        }
        if (page == null || page <= 0) return null
        // whatever came before the page marker is the document's name, minus the comma
        val name = label.substring(0, match.range.first).trim { it in " ,(-–—" }
        return Reference(name, page)
    }
}
