package com.stethoscore.app.export

/**
 * The text of an Anki note's fields (iOS AnkiFields). Anki shows a field as
 * HTML, so everything a card says is escaped before it goes in - a cloze
 * sentence as much as a question.
 */
object AnkiFields {

    /** `**term**` -> <b>term</b>, everything else HTML-escaped. */
    fun bold(s: String): String {
        val out = StringBuilder()
        var rest = s
        var on = false
        while (true) {
            val at = rest.indexOf("**")
            if (at < 0) break
            out.append(esc(rest.substring(0, at))).append(if (on) "</b>" else "<b>")
            on = !on
            rest = rest.substring(at + 2)
        }
        out.append(esc(rest))
        if (on) out.append("</b>")
        return out.toString()
    }

    /** A cloze sentence as a field: escaped like any other, bold and all; the markers come through untouched. */
    fun cloze(s: String): String = bold(s)

    fun esc(s: String): String = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    fun plain(s: String): String = s.replace("**", "")

    /** Which cards a cloze note makes: one per distinct cN, counted from 0. */
    fun clozeOrdinals(text: String): List<Int> {
        val ords = Regex("""\{\{c(\d+)::""").findAll(text).mapNotNull { it.groupValues[1].toIntOrNull() }
            .map { it - 1 }.filter { it >= 0 }.toSortedSet().toList()
        return ords.ifEmpty { listOf(0) }
    }

    data class ClozeCard(val number: Int, val text: String)

    private val deletion = Regex("""\{\{c(\d+)::([\s\S]*?)(?:::([\s\S]*?))?\}\}""")

    /** An Anki cloze note as the cards Anki makes of it: one per cN, each hiding only its own deletions. */
    fun clozeCards(text: String): List<ClozeCard> {
        val matches = deletion.findAll(text).toList()
        val numbers = matches.mapNotNull { it.groupValues[1].toIntOrNull() }.filter { it > 0 }.toSortedSet().toList()
        if (numbers.size <= 1) return listOf(ClozeCard(numbers.firstOrNull() ?: 1, text))
        return numbers.map { number ->
            val out = StringBuilder()
            var at = 0
            for (m in matches) {
                out.append(text, at, m.range.first)
                val own = m.groupValues[1].toIntOrNull() == number
                out.append(if (own) m.value else m.groupValues[2])
                at = m.range.last + 1
            }
            out.append(text.substring(at))
            ClozeCard(number, out.toString())
        }
    }

    /** Whether a cloze sentence still has a deletion Anki can make a card from. */
    fun hasDeletion(text: String): Boolean = Regex("""\{\{c[1-9][0-9]*::[\s\S]+?\}\}""").containsMatchIn(text)

    /** What one cloze card becomes in the package: a cloze note, or a basic one when no deletion is left. */
    data class ClozeNote(val isCloze: Boolean, val fields: List<String>, val sort: String, val ordinals: List<Int>)

    fun clozeNote(text: String, why: String): ClozeNote {
        val reason = if (why.isEmpty()) "" else "<div class=\"why\"><b>Why / how</b>${esc(why)}</div>"
        if (!hasDeletion(text)) return ClozeNote(false, listOf(bold(text), reason), plain(text), listOf(0))
        return ClozeNote(true, listOf(cloze(text), if (why.isEmpty()) "" else bold(why)), plain(text), clozeOrdinals(text))
    }

    /** A field as Anki reads it for its duplicate check: the HTML gone and the entities undone. */
    fun stripped(field: String): String {
        val bare = field.replace(Regex("<[^>]+>"), "")
        if (!bare.contains("&")) return bare
        var out = bare
        for ((entity, character) in listOf("&lt;" to "<", "&gt;" to ">", "&quot;" to "\"", "&#39;" to "'", "&apos;" to "'", "&nbsp;" to " ")) {
            out = out.replace(entity, character)
        }
        // last, or an escaped entity would be decoded twice
        return out.replace("&amp;", "&")
    }
}
