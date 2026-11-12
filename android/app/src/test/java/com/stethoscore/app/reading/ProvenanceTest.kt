package com.stethoscore.app.reading

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.SourcePage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

// ios/RedPen/Tests/SlideTests.swift, "which page a card came off" (lines 66-107,
// Provenance), check for check; the rest of that file (slide reading, editing a
// question) is other batches'. The last four tests are not in the iOS file: they
// pin what Provenance.swift does that its tests leave open.
class ProvenanceTest {

    private val pages = listOf(
        SourcePage(1, "Introduction to connective tissue disease"),
        SourcePage(2, "Malar rash spares the nasolabial fold and is reversible"),
        SourcePage(3, "Lupus nephritis class IV is treated with cyclophosphamide"),
    )

    @Test fun aQuestionLandsOnThePageItCameFrom() {
        assertEquals("a question lands on the page it came from", 2, Provenance.page("Which rash spares the nasolabial fold?", pages))
    }

    @Test fun aDifferentFactLandsOnItsOwnPage() {
        assertEquals("a different fact lands on its own page", 3, Provenance.page("cyclophosphamide in class IV nephritis", pages))
    }

    @Test fun aQuestionMatchingNothingIsLeftUncited() {
        // a question that matches nothing drifted from the source, and saying nothing
        // is more honest than naming a page at random
        assertNull("a question matching nothing is left uncited", Provenance.page("Which cranial nerve supplies the stapedius?", pages))
    }

    @Test fun anEmptyQuestionIsNotAttributed() {
        assertNull("an empty question is not attributed", Provenance.page("", pages))
    }

    @Test fun aDocumentWithNoPagesAttributesNothing() {
        assertNull("a document with no pages attributes nothing", Provenance.page("malar rash", emptyList()))
    }

    private val question = MCQQuestion(stem = "A woman has a facial rash. Which is it?", options = listOf("Malar rash", "Discoid rash"), correctIndex = 0,
        explanation = "It spares the nasolabial fold.")

    @Test fun theCitationNamesTheFileAndThePage() {
        val cited = Provenance.attribute(listOf(question), pages, "Lupus")
        assertEquals("the citation names the file and the page", "Lupus, p. 2", cited.firstOrNull()?.source)
    }

    @Test fun aCardThatAlreadyKnowsItsPageKeepsIt() {
        val known = AnkiCard(type = AnkiCardType.QA, front = "malar rash", bullets = listOf("spares the nasolabial fold"), source = "Lupus, p. 14")
        val recited = Provenance.attribute(listOf(known), pages, "Lupus")
        // a figure card knows its page exactly; a guess must never overwrite that
        assertEquals("a card that already knows its page keeps it", "Lupus, p. 14", recited.firstOrNull()?.source)
    }

    @Test fun aCardWithNoSourceGetsOne() {
        val bare = AnkiCard(type = AnkiCardType.QA, front = "Which rash is reversible?", bullets = listOf("the malar rash"))
        assertEquals("a card with no source gets one", "Lupus, p. 2", Provenance.attribute(listOf(bare), pages, "Lupus").firstOrNull()?.source)
    }

    @Test fun aNamelessFileStillCitesThePage() {
        assertEquals("a nameless file still cites the page", "p. 3", Provenance.label("", 3))
        assertEquals("and a named one writes the name first", "Lupus, p. 14", Provenance.label("Lupus", 14))
    }

    // MARK: not in the iOS file

    @Test fun aQuestionMatchingNoPageKeepsWhatItHad() {
        val drifted = MCQQuestion(stem = "Which cranial nerve supplies the stapedius?", options = listOf("Facial", "Trigeminal"), correctIndex = 0, explanation = "")
        assertNull(Provenance.attribute(listOf(drifted), pages, "Lupus").single().source)
        val kept = drifted.copy(source = "Neuro, p. 4")
        assertEquals("Neuro, p. 4", Provenance.attribute(listOf(kept), pages, "Lupus").single().source)
    }

    @Test fun noPagesLeavesTheListAsItWas() {
        val questions = listOf(question)
        assertSame(questions, Provenance.attribute(questions, emptyList(), "Lupus"))
        val cards = listOf(AnkiCard(type = AnkiCardType.QA, front = "malar rash"))
        assertSame(cards, Provenance.attribute(cards, emptyList(), "Lupus"))
    }

    @Test fun aTieGoesToTheEarlierPage() {
        val twins = listOf(SourcePage(1, "Malar rash spares the nasolabial fold"), SourcePage(2, "Malar rash spares the nasolabial fold"))
        assertEquals(1, Provenance.page("malar rash spares the nasolabial fold", twins))
    }

    @Test fun aPageMustShareEnoughOfTheQuestionsWordsToBeNamed() {
        val rash = listOf(SourcePage(1, "Malar rash"))
        // the default floor is 0.3 of the question's own words: 1 of 3 (0.33) is named, 1 of 4 (0.25) is not
        assertEquals(1, Provenance.page("malar cranial stapedius", rash))
        assertNull(Provenance.page("malar cranial stapedius nerve", rash))
        // and the share is of the question's words: 2 of 3 is 0.667
        assertEquals(1, Provenance.page("malar rash cranial", rash, floor = 0.66))
        assertNull(Provenance.page("malar rash cranial", rash, floor = 0.67))
    }
}
