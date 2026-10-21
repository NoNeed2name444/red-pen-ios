package com.stethoscore.app.reading

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// ios/RedPen/Tests/ReadingTests.swift (fed0105), case for case: what a card's
// emphasis means (Highlight), how a textbook is split into pages and blocks
// (BookPages), and which figure goes on which page (BookFigures).
class ReadingTest {
    private fun run(text: String, bold: Boolean) = Highlight.Run(text, bold)

    // MARK: emphasis

    @Test fun emphasis() {
        assertEquals("text with no markers is one plain run", listOf(run("plain text", false)), Highlight.runs("plain text"))
        assertEquals("a marked term is emboldened and the rest is left alone",
            listOf(run("the ", false), run("key", true), run(" term", false)), Highlight.runs("the **key** term"))
        assertEquals("two marked terms both work",
            listOf(run("first", true), run(" and ", false), run("second", true)), Highlight.runs("**first** and **second**"))
        assertEquals("a card that is nothing but a marked term", listOf(run("leading", true)), Highlight.runs("**leading**"))
    }

    // MARK: the characters medical writing is actually full of

    @Test fun theCharactersMedicalWritingIsFullOf() {
        val underscores = "T_max_ and P_min_ rise"
        assertEquals("underscores are characters, not italics", underscores, Highlight.plain(underscores))
        val numbered = "1. Give oxygen"
        assertEquals("a line starting with a number is not a list", numbered, Highlight.plain(numbered))
        val bracketed = "Give adrenaline [1:1000] IM"
        assertEquals("square brackets are not a link", bracketed, Highlight.plain(bracketed))
        val backtick = "the `sniff` position"
        assertEquals("backticks are not code", backtick, Highlight.plain(backtick))
        val hash = "# of beats per minute"
        assertEquals("a hash is not a heading", hash, Highlight.plain(hash))
    }

    // MARK: markers that are not emphasis

    @Test fun markersThatAreNotEmphasis() {
        assertEquals("an unclosed pair stays as the asterisks somebody typed",
            listOf(run("2 ** 3 is not emphasis", false)), Highlight.runs("2 ** 3 is not emphasis"))
        assertEquals("and so does a lone pair", "**", Highlight.plain("**"))
        assertEquals("four asterisks emphasise nothing, so they stay", "****", Highlight.plain("****"))
        assertEquals("spaces inside the markers are kept, since they are part of what was typed",
            listOf(run("a ", false), run(" b ", true), run(" c", false)), Highlight.runs("a ** b ** c"))
    }

    // MARK: splitting a textbook

    @Test fun splittingATextbook() {
        val book = """
            Some words before any heading.

            # The kidney
            The nephron is the unit.

            ## Filtration
            Blood arrives at the glomerulus.
        """.trimIndent()
        val pages = BookPages.split(book)
        assertEquals("text before the first heading is a page of its own", 3, pages.size)
        assertEquals("and it is called Introduction", "Introduction", pages[0].title)
        assertEquals("a heading names its page", "The kidney", pages[1].title)
        assertEquals("at either level", "Filtration", pages[2].title)
        assertTrue("and carries the text under it", pages[1].markdown.contains("The nephron is the unit."))

        assertTrue("an empty textbook has no pages", BookPages.split("").isEmpty())
        assertTrue("and neither does one with only whitespace", BookPages.split("   \n\n  ").isEmpty())
        // the library's remembered count is the split's
        assertEquals(3, BookPages.pageCount(book))
    }

    // MARK: blocks
    //
    // A numbered list in a textbook is a sequence - the steps of a protocol, the
    // stages of a disease. Redrawing it as anonymous bullets throws that away.

    @Test fun blocks() {
        val blocks = BookPages.blocks("""
            ## Managing it
            1. Give oxygen
            2) Gain access
            - Then reassess
            * And again

            | Stage | Finding |
            | --- | --- |
            | I | Normal |
        """.trimIndent())
        val bullets = mutableListOf<Pair<String, String?>>()
        var headings = 0
        var rows = 0
        for (block in blocks) when (block) {
            is BookPages.Block.Bullet -> bullets += block.text to block.marker
            is BookPages.Block.Heading -> headings += 1
            is BookPages.Block.Row -> rows += 1
            else -> Unit
        }
        assertEquals("the heading is a heading", 1, headings)
        assertEquals("every list line is a bullet", 4, bullets.size)
        assertTrue("a numbered line keeps its number, however it was punctuated", bullets[0].second == "1." && bullets[1].second == "2)")
        assertTrue("an unnumbered one has no marker to keep", bullets[2].second == null && bullets[3].second == null)
        assertEquals("and the marker is not repeated in the text",
            listOf("Give oxygen", "Gain access", "Then reassess", "And again"), bullets.map { it.first })
        assertEquals("a table's rows are rows, and its separator line is not one of them", 2, rows)
    }

    // The textbook's visual aids
    @Test fun visualAids() {
        val rich = BookPages.blocks("""
            | Type | Feature |
            | --- | --- |
            | A | one |
            > **Exam tip:** Remember this
            ```flow
            Suspect it
            If positive → confirm
            ```
            ![The brachial plexus](image:2)
        """.trimIndent())
        var header = 0
        val callouts = mutableListOf<String>()
        val flows = mutableListOf<List<String>>()
        val pictures = mutableListOf<Int>()
        for (block in rich) when (block) {
            is BookPages.Block.Row -> if (block.header) header += 1
            is BookPages.Block.Callout -> callouts += block.kind
            is BookPages.Block.Flow -> flows += block.steps
            is BookPages.Block.Image -> pictures += block.index
            else -> Unit
        }
        assertEquals("a table's first row, above the |---| line, is its header", 1, header)
        assertEquals("a > **Exam tip:** line is an exam-tip callout", listOf("Exam tip"), callouts)
        assertEquals("a flow block is a flowchart of its steps", listOf(listOf("Suspect it", "If positive → confirm")), flows)
        assertEquals("a picture line points at the set's picture", listOf(2), pictures)
    }

    // one topic stays one page, and a page shows only the pictures it was given
    @Test fun tidyPage() {
        val tidy = BookPages.tidyPage("## Lupus\n## Clinical features\n- rash\n![made up](image:9)", fallbackTitle = "Part 1", figures = listOf(4))
        assertEquals("a second ## inside a page becomes a section, not a new page", 1, BookPages.split(tidy).size)
        assertTrue("a picture the page was not given is dropped; one it was given is added",
            !tidy.contains("image:9") && tidy.contains("image:4"))
    }

    // which figure goes on which page
    @Test fun figures() {
        val figs = listOf(
            BookFigure("x", 3, listOf("brachial", "plexus", "radial", "nerve")),
            BookFigure("y", 9, listOf("kidney", "nephron", "glomerulus")),
        )
        val placed = BookFigures.assign(figs, listOf("The kidney: nephron and glomerulus filtration", "Brachial plexus: radial nerve injury"))
        assertEquals("each diagram goes on the page about its topic", listOf(listOf(1), listOf(0)), placed)
        val (markdown, images) = BookFigures.compact("![a](image:5)\ntext\n![b](image:2)", listOf("0", "1", "2", "3", "4", "5"))
        assertTrue("a set keeps only the pictures its pages show, renumbered",
            images == listOf("5", "2") && markdown.contains("image:0") && markdown.contains("image:1"))
    }
}
