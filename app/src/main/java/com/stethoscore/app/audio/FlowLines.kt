package com.stethoscore.app.audio

// Words wrapped the way a paragraph wraps them, worked out once for both of a
// flow layout's passes (ios/RedPen/Shared/FlowLines.swift, fed0105; the
// transcript's word flow, NarrateWordFlow). Both passes break the lines here,
// against the width offered; and a point of give keeps the lines when a parent
// offers the layout back its own width, rounded down.
object FlowLines {
    /** A word may run this far past the width and still fit: more than a pixel's rounding on any screen, less than anyone can see. */
    const val give: Double = 1.0

    /**
     * Which line each item goes on (0, 1, ...), for items this wide, laid
     * [spacing] apart in lines [width] wide; an infinite width is one line.
     * An item wider than a line has a line of its own.
     */
    fun lines(widths: List<Double>, spacing: Double, width: Double): List<Int> {
        val out = ArrayList<Int>(widths.size)
        var x = 0.0
        var line = 0
        for (w in widths) {
            if (x > 0 && x + w > width + give) {
                line += 1
                x = 0.0
            }
            out.add(line)
            x += w + spacing
        }
        return out
    }

    /** Each line's width, for items on [lines] (as [FlowLines.lines] gives them). */
    fun lineWidths(widths: List<Double>, spacing: Double, lines: List<Int>): List<Double> {
        val out = ArrayList<Double>()
        for ((w, line) in widths.zip(lines)) {
            if (line < out.size) out[line] += spacing + w else out.add(w)
        }
        return out
    }
}
