package com.stethoscore.app.reading

// A port of ios/RedPen/Shared/BookFigures.swift (fed0105): which of a
// lecture's diagrams goes on which textbook page, and the `![caption](image:3)`
// lines that place a set's pictures on a page. Pure Kotlin (ReadingTest).

/** A diagram found in the lecture, ready to sit on the page about the same topic. */
data class BookFigure(
    /** JPEG, base64: the form StudySet.images keeps pictures in. */
    val imageBase64: String,
    /** The page or slide it was on, when the file says. */
    val page: Int?,
    /** The words labelled on it. */
    val labels: List<String>,
    /** The text of its page: what it is about. */
    val pageText: String = "",
) {
    val about: String get() = (labels + pageText).joinToString(" ")
}

object BookFigures {
    /** Most figures one page carries: a page of pictures is an atlas, not a textbook. */
    const val perPage = 3

    private val pictureLine = Regex("^!\\[([^\\]]*)\\]\\(image:(\\d+)\\)\\s*$")

    /**
     * Which figures belong to which slice of the lecture: each figure goes to
     * the slice it shares the most words with, and only if it shares enough.
     */
    fun assign(figures: List<BookFigure>, slices: List<String>, minimumOverlap: Int = 2): List<List<Int>> {
        val out = List(slices.size) { mutableListOf<Int>() }
        if (slices.isEmpty()) return out
        val sliceWords = slices.map(::words)
        data class Pick(val figure: Int, val slice: Int, val score: Int)
        val ranked = mutableListOf<Pick>()
        for ((f, figure) in figures.withIndex()) {
            val about = words(figure.about)
            if (about.isEmpty()) continue
            val scores = sliceWords.map { (it intersect about).size }
            val best = scores.indices.maxByOrNull { scores[it] } ?: continue
            if (scores[best] >= minimumOverlap) ranked += Pick(f, best, scores[best])
        }
        // the closest matches first, so a crowded page keeps its best figures
        for (pick in ranked.sortedByDescending { it.score }) {
            if (out[pick.slice].size < perPage) out[pick.slice] += pick.figure
        }
        return out.map { it.sorted() }
    }

    fun words(text: String): Set<String> =
        text.lowercase().split(Regex("[^\\p{L}\\p{M}\\p{N}]+")).filter { it.length > 3 }.toSet()

    /**
     * Keeps only the pictures a textbook actually shows, renumbering the
     * references to match.
     */
    fun compact(markdown: String, images: List<String>): Pair<String, List<String>> {
        val kept = mutableListOf<String>()
        val remap = mutableMapOf<Int, Int>()
        val lines = markdown.split("\n").map { line ->
            val parsed = parse(line.trimSpaces())
            if (parsed == null || parsed.first !in images.indices) return@map line
            val (index, caption) = parsed
            if (index !in remap) { remap[index] = kept.size; kept += images[index] }
            "![$caption](${reference(remap.getValue(index))})"
        }
        return lines.joinToString("\n") to kept
    }

    /** The reference a page uses for picture [index] of the set. */
    fun reference(index: Int): String = "image:$index"

    /** [markdown] with every picture reference moved on by [offset]. */
    fun rebased(markdown: String, offset: Int): String {
        if (offset == 0) return markdown
        return markdown.split("\n").joinToString("\n") { line ->
            val (index, caption) = parse(line.trimSpaces()) ?: return@joinToString line
            "![$caption](${reference(index + offset)})"
        }
    }

    /** `![caption](image:3)`: the picture's index and its caption, or null for any other line. */
    fun parse(line: String): Pair<Int, String>? {
        val m = pictureLine.find(line) ?: return null
        val index = m.groupValues[2].toIntOrNull() ?: return null
        return index to m.groupValues[1]
    }
}
