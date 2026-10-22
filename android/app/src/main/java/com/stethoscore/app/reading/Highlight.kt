package com.stethoscore.app.reading

// A port of ios/RedPen/Shared/Highlight.swift (fed0105): `**term**` emphasis,
// and nothing else. Cards are not Markdown: a full Markdown reader eats the
// underscores in "T_max_", turns "1." into a list and a bracket into a link.
// This reads the one thing the format promises and leaves every other
// character alone (ReadingTest).

object Highlight {

    data class Run(val text: String, val bold: Boolean)

    /**
     * The text split into plain and emboldened stretches. An unclosed `**`
     * is two asterisks somebody typed, and stays; "****" emphasises nothing.
     */
    fun runs(text: String): List<Run> {
        val out = mutableListOf<Run>()
        val plain = StringBuilder()
        var rest = text

        fun keepPlain() {
            if (plain.isNotEmpty()) { out += Run(plain.toString(), false); plain.clear() }
        }

        while (true) {
            val open = rest.indexOf("**")
            if (open < 0) break
            val after = rest.substring(open + 2)
            // the closing pair, if there is one; without it these are just asterisks
            val close = after.indexOf("**")
            if (close < 0) break
            val inner = after.substring(0, close)
            // "****" is not emphasis of nothing; it is four asterisks
            if (inner.isEmpty()) {
                plain.append(rest, 0, open + 2 + close + 2)
                rest = after.substring(close + 2)
                continue
            }
            plain.append(rest, 0, open)
            keepPlain()
            out += Run(inner, true)
            rest = after.substring(close + 2)
        }

        plain.append(rest)
        keepPlain()
        return out
    }

    /** The same text with the markers removed and nothing emphasised. */
    fun plain(text: String): String = runs(text).joinToString("") { it.text }
}
