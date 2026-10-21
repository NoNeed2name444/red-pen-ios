package com.stethoscore.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

// The logic under the library's editors. Its first test is a port of the
// "how many questions the source can support" part of
// upstream/ios/RedPen/Tests/CoverageTests.swift (fed0105), case for case; the
// rest of CoverageTests (repeats across a long set) is the question writer's
// and comes with it. The others hold the editors' iOS words, counts and rules,
// which iOS keeps in its views, and Android's own reading of Office files.
class LibraryEditorsTest {

    @Test fun howManyQuestionsTheSourceCanSupport() {
        assertEquals("a longer lecture earns more questions", 100, MCQCoverage.suggestedCount(32_000))
        assertEquals("a scrap of text still gets a set", 5, MCQCoverage.suggestedCount(200))
        assertEquals("nothing pasted does not crash", 5, MCQCoverage.suggestedCount(0))
        assertEquals("a textbook does not get a thousand questions", 200, MCQCoverage.suggestedCount(5_000_000))
    }

    @Test fun aClozeNeedsAHole() {
        assertTrue("a sentence with its braces edited away has nothing to recall", CardQuality.clozeHoles("Anti-dsDNA is specific").isEmpty())
        val holes = CardQuality.clozeHoles("{{c1::Anti-dsDNA}} is {{c2::specific::how?}}")
        assertEquals(listOf(1, 2), holes.map { it.number })
        assertEquals(listOf("Anti-dsDNA", "specific"), holes.map { it.text })
    }

    @Test fun cardStyles() {
        assertEquals(listOf("Mixed (all types)", "Question & answer", "Cloze deletion", "Image occlusion"), CardStyle.entries.map { it.title })
        assertTrue(CardStyle.mixed.usesDiagrams && CardStyle.image.usesDiagrams && !CardStyle.qa.usesDiagrams && !CardStyle.cloze.usesDiagrams)
        assertTrue(!CardStyle.image.writesText && CardStyle.mixed.writesText)
    }

    @Test fun lectureWords() {
        assertEquals("word", LectureForms.kind("DOCX"))
        assertEquals("powerpoint", LectureForms.kind("ppt"))
        assertEquals("text", LectureForms.kind("txt"))
        assertEquals("word", LectureForms.writerFileKind("docx"))
        assertEquals("a forty-slide lecture proposes twenty cards", 20, LectureForms.writerCount(book = false, pages = 40))
        assertEquals("never fewer than eight cards", 8, LectureForms.writerCount(book = false, pages = 1))
        assertEquals("nor more than eighty", 80, LectureForms.writerCount(book = false, pages = 400))
        assertEquals("a textbook takes a page in three", 13, LectureForms.writerCount(book = true, pages = 40))
        assertEquals("at most thirty pages", 30, LectureForms.writerCount(book = true, pages = 400))
        assertEquals("Read 12 pages, 2 by OCR. 40 questions suits this much material.", LectureForms.pdfSummary(12, 2, 0, 0, 40))
        assertEquals("Read 1 page, 1 labelled diagram. 5 questions suits this much material.", LectureForms.pdfSummary(1, 0, 1, 3, 5))
        assertEquals("Make 1 card", LectureForms.writerActionTitle(book = false, style = CardStyle.mixed, count = 1, diagrams = 0))
        assertEquals("Make 12 pages", LectureForms.writerActionTitle(book = true, style = CardStyle.image, count = 12, diagrams = 0))
        assertEquals("Add 3 image cards", LectureForms.writerActionTitle(book = false, style = CardStyle.image, count = 12, diagrams = 3))
        assertEquals("No labelled diagrams were found in this file.", LectureForms.diagramNote(0))
        assertEquals("1 picture card from the file's diagrams.", LectureForms.diagramNote(1))
        assertTrue("two hundred characters is not enough to write from", !LectureForms.hasSource("x".repeat(200)) && LectureForms.hasSource("x".repeat(201)))
    }

    private fun zip(vararg entries: Pair<String, String>): ByteArrayInputStream {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { z -> entries.forEach { (name, body) -> z.putNextEntry(ZipEntry(name)); z.write(body.toByteArray()); z.closeEntry() } }
        return ByteArrayInputStream(out.toByteArray())
    }

    @Test fun officeFilesAreReadOnTheDevice() {
        val docx = zip("word/document.xml" to """<w:document><w:body><w:p><w:r><w:t>Heart &amp; lungs</w:t></w:r></w:p><w:p/><w:p w:rsid="1"><w:r><w:t xml:space="preserve">Aortic </w:t></w:r><w:r><w:t>valve</w:t></w:r></w:p></w:body></w:document>""")
        val word = OfficeText.read(docx, "docx")
        assertEquals(1, word.size)
        assertEquals("Heart & lungs\nAortic valve", word[0].text)
        val pptx = zip("ppt/slides/slide10.xml" to "<p:sld><a:p><a:r><a:t>Ten</a:t></a:r></a:p></p:sld>",
            "ppt/slides/slide2.xml" to "<p:sld><a:p><a:r><a:t>Two</a:t></a:r></a:p><a:p><a:r><a:t>more</a:t></a:r></a:p></p:sld>")
        val slides = OfficeText.read(pptx, "pptx")
        assertEquals("slides in their own order, one page each", listOf("Two\nmore", "Ten"), slides.map { it.text })
        assertEquals(listOf(1, 2), slides.map { it.number })
    }
}
