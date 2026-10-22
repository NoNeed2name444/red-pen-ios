package com.stethoscore.app.ui.sources

import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.reading.ContentSources
import com.stethoscore.app.reading.SourceSearch
import com.stethoscore.app.ui.book.BookReaderWords
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The words and arithmetic of the batch 9 screens, checked apart from the
// views: what the textbook's header says and where it opens, the reader
// bar's paging, the sources library's rows, the lecture reader's search
// heading and the credits' lines. Each is copied from the iOS view it
// names; iOS keeps these inside its views, so there is no iOS suite for them.
class ReaderWordsTest {
    private val lecture = SourceDoc(name = "Renal", kind = "pdf", addedAt = 10,
        pages = listOf(SourcePage(1, "Nephritic syndrome\nHaematuria and casts"), SourcePage(2, " "), SourcePage(3, "Nephrotic: haematuria is rare")))
    private val slides = SourceDoc(name = "Cardio", kind = "powerpoint", addedAt = 20, pages = listOf(SourcePage(1, "Murmurs")))

    @Test fun bookHeader() {
        assertEquals("Page 3 of 10", BookReaderWords.status(2, 10))
        assertEquals("One page", BookReaderWords.status(0, 1))
        assertNull(BookReaderWords.fraction(0, 1))
        assertEquals(0.5, BookReaderWords.fraction(1, 4)!!, 1e-9)
        assertEquals("1,234 words", BookReaderWords.detail(null, 1234))
        assertEquals(4, BookReaderWords.wordCount("  # Heart\n\nfour  beats "))
    }

    @Test fun bookOpensWhereItWasLeft() {
        assertEquals(0, BookReaderWords.opening(null, 5))
        assertEquals(3, BookReaderWords.opening(3, 5))
        // a place past the end of a book that got shorter starts it again
        assertEquals(0, BookReaderWords.opening(7, 5))
    }

    @Test fun calloutKinds() {
        assertEquals("danger", BookReaderWords.calloutKind("Red flag"))
        assertEquals("danger", BookReaderWords.calloutKind("WARNING"))
        assertEquals("exam", BookReaderWords.calloutKind("Exam tip"))
        assertEquals("mnemonic", BookReaderWords.calloutKind("Mnemonic"))
        assertEquals("note", BookReaderWords.calloutKind("Pearl"))
    }

    @Test fun readerBarPaging() {
        assertEquals("Slide 2 of 9", ReaderPaging.place("Slide", 2, 9))
        assertEquals(1, ReaderPaging.turn(1, -1, 9))
        assertEquals(9, ReaderPaging.turn(9, 1, 9))
        assertEquals(5, ReaderPaging.turn(4, 1, 9))
        assertEquals(1, ReaderPaging.turn(1, 1, 0))
        assertTrue(ReaderPaging.atStart(1)); assertFalse(ReaderPaging.atStart(2))
        assertTrue(ReaderPaging.atEnd(9, 9)); assertFalse(ReaderPaging.atEnd(8, 9))
        // the lower row: the bubble, the pages button, or the pager under one page
        assertFalse(ReaderPaging.hasRow(collapsed = false, showsPages = false, whole = true))
        assertTrue(ReaderPaging.hasRow(collapsed = true, showsPages = false, whole = true))
        assertTrue(ReaderPaging.hasRow(collapsed = false, showsPages = true, whole = true))
        assertTrue(ReaderPaging.hasRow(collapsed = false, showsPages = false, whole = false))
    }

    @Test fun libraryListsEachLectureOnceNewestFirst() {
        val a = StudySet(name = "Renal MCQs", kind = StudySetKind.MCQ, sources = listOf(lecture))
        val b = StudySet(name = "Renal cards", kind = StudySetKind.ANKI, sources = listOf(lecture, slides))
        val entries = SourcesLibrary.entries(listOf(a, b))
        assertEquals(listOf("Cardio", "Renal"), entries.map { it.source.name })
        assertEquals(listOf("Renal MCQs", "Renal cards"), entries[1].sets.map { it.name })
        assertEquals("PDF · 3 pages · 2 sets", SourcesLibrary.detail(entries[1]))
        assertEquals("Slides · 1 slide · 1 set", SourcesLibrary.detail(entries[0]))
        assertTrue(SourcesLibrary.entries(listOf(StudySet(name = "Typed", kind = StudySetKind.MCQ))).isEmpty())
    }

    @Test fun lectureReaderWords() {
        assertEquals("Search this pdf", SourceReaderWords.searchPrompt(lecture))
        assertEquals("Search this slides", SourceReaderWords.searchPrompt(slides))
        assertEquals("3 pages", SourceReaderWords.pagesTitle(lecture))
        assertEquals("Nephritic syndrome", SourceReaderWords.firstLine(lecture.pages[0], lecture))
        assertEquals("No text on this page", SourceReaderWords.firstLine(lecture.pages[1], lecture))
        val hits = SourceSearch.hits("haematuria", lecture.pages)
        assertEquals("2 mentions on 2 pages", SourceReaderWords.resultsHeading(hits, lecture))
        assertEquals("1 mention on 1 pages", SourceReaderWords.resultsHeading(SourceSearch.hits("casts", lecture.pages), lecture))
        assertEquals("1 card from this slide", PageCards.line(1, slides))
        assertEquals("3 cards from this page", PageCards.line(3, lecture))
    }

    @Test fun creditsWords() {
        assertEquals("Cited by 1 question", CreditsWords.cited(1, "question"))
        assertEquals("Cited by 4 cards", CreditsWords.cited(4, "card"))
        assertEquals("medlineplus.gov", CreditsWords.host(ContentSources.medlinePlus.home))
        assertEquals("not a link", CreditsWords.host("not a link"))
        assertTrue(CreditsWords.styleFooter(ContentSources.medqa, "USMLE Step 1").startsWith(
            "When questions are written for USMLE Step 1, the writer is shown a few real MedQA questions"))
    }
}
