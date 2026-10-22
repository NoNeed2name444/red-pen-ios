package com.stethoscore.app.reading

import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// ios/RedPen/Tests/SourceTests.swift (fed0105), case for case: searching a
// lecture, and reading a card's citation back apart.
class SourceTest {
    private fun page(number: Int, text: String, ocr: Boolean = false) = SourcePage(number, text, ocr)

    // MARK: a page knows how to describe itself

    @Test fun aPageDescribesItself() {
        val blank = page(1, "   \n\n  ")
        assertTrue("a page with nothing but whitespace is blank", blank.isBlank)
        assertEquals("and offers no heading", "", blank.heading)

        val titled = page(2, "\n\n  Glomerular disease  \nThe nephritic syndrome")
        assertEquals("a heading is the first line with anything on it, trimmed", "Glomerular disease", titled.heading)
    }

    // MARK: searching

    private val pages = listOf(
        page(1, "The nephrotic syndrome\nOedema, proteinuria, low albumin"),
        page(2, "Oedema is pitting oedema in most cases"),
        page(3, "Nothing relevant here at all"),
    )

    @Test fun searching() {
        val found = SourceSearch.hits("oedema", pages)
        assertEquals("every appearance is found, on every page", 3, found.size)
        assertEquals("across two pages", 2, SourceSearch.pagesMatched(found))
        assertEquals("in reading order", listOf(1, 2, 2), found.map { it.page })

        assertEquals("case does not matter", 3, SourceSearch.hits("OEDEMA", pages).size)
        assertTrue("and neither do accents", SourceSearch.hits("oedema", listOf(page(1, "Œdema and oedema"))).size >= 1)

        assertTrue("a single character is not a search, so it finds nothing rather than everything",
            SourceSearch.hits("z", pages).isEmpty())
        assertTrue("nor is whitespace", SourceSearch.hits("  ", pages).isEmpty())
    }

    // MARK: the snippet marks the right occurrence
    //
    // The second "oedema" on page 2 must be marked at ITS position, not at the
    // first one's - searching the snippet again is exactly how that goes wrong.

    @Test fun theSnippetMarksTheRightOccurrence() {
        val onPageTwo = SourceSearch.hits("oedema", pages).filter { it.page == 2 }
        assertEquals("both appearances on one page are separate hits", 2, onPageTwo.size)
        for (hit in onPageTwo) {
            assertTrue("the marked range lies inside its own snippet", hit.start >= 0 && hit.end <= hit.snippet.length)
            val marked = hit.snippet.substring(hit.start, hit.end).lowercase()
            assertEquals("and marks the word itself, not something near it", "oedema", marked)
        }
        // the two are marked at different places
        assertTrue(onPageTwo[0].start != onPageTwo[1].start)
    }

    // MARK: a match at the very start, and at the very end

    @Test fun aMatchAtTheVeryStart() {
        val only = SourceSearch.hits("Oedema", listOf(page(1, "Oedema")))
        assertTrue("a match at the start of a page is marked from the start", only.size == 1 && only[0].start == 0)
        assertTrue("and has nothing elided before it", !only[0].snippet.startsWith("…"))
    }

    // MARK: overlapping matches cannot loop
    //
    // Advancing by one character instead of past the match makes "aa" in "aaaa"
    // match for ever. The limit would hide it; the count is what catches it.

    @Test fun overlappingMatchesCannotLoop() {
        val repeated = SourceSearch.hits("aa", listOf(page(1, "aaaa")))
        assertEquals("overlapping matches advance past the match, not into it", 2, repeated.size)
    }

    // MARK: citations

    @Test fun citations() {
        assertEquals("the app's own citation format is read back", Citation.Reference("Immunology", 12), Citation.read("Immunology, p. 12"))
        assertEquals("a citation with no document name still names a page", Citation.Reference("", 7), Citation.read("p. 7"))
        assertEquals("so does one that spells out 'page'", 3, Citation.read("Renal block, page 3")?.page)
        assertEquals("a range opens at its first page", 14, Citation.read("Notes, pp. 14-16")?.page)
        assertEquals("a number in the document's own name is not mistaken for the page", "Lecture 2", Citation.read("Lecture 2, p. 5")?.name)
        assertEquals("and the page is still the page", 5, Citation.read("Lecture 2, p. 5")?.page)

        assertNull("no citation is not a citation", Citation.read(null))
        assertNull("nor is an empty one", Citation.read(""))
        assertNull("nor a document name with no page", Citation.read("Immunology"))
        assertNull("and page zero is not a page", Citation.read("p. 0"))
    }

    // MARK: which cards came off a page, when a set has two lectures

    @Test fun whichCardsCameOffAPage() {
        val renal = SourceDoc(name = "Renal", pages = (1..6).map { page(it, "renal $it") })
        val cardio = SourceDoc(name = "Cardio", pages = (1..6).map { page(it, "cardio $it") })
        val cited = listOf("Renal, p. 4", "Cardio, p. 4", "Cardio, p. 4", "Renal, p. 2")
        assertEquals("page 4 of one lecture is not page 4 of the other",
            listOf("Renal, p. 4"), Citation.citing(renal, 4, cited, listOf(renal, cardio)))
        assertEquals("each lecture counts its own", 2, Citation.citing(cardio, 4, cited, listOf(renal, cardio)).size)
        assertEquals("a set with one lecture still counts unnamed citations",
            listOf("p. 2"), Citation.citing(renal, 2, listOf("p. 2"), listOf(renal)))
    }
}
