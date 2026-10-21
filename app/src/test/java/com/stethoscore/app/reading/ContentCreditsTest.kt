package com.stethoscore.app.reading

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.exam.ExamCatalog
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// ios/RedPen/Tests/ContentCreditsTests.swift (fed0105), check for check: where
// a set's content came from, and whose licence it carries - the lectures it was
// made from and how many questions cite each, the exam's style bank, the public
// sources its checks read, and the app's own list.
class ContentCreditsTest {

    /** A question as iOS writes one, its checked evidence inside its differential. */
    private fun question(stem: String, source: String? = null, evidence: List<EvidenceRef> = emptyList()): MCQQuestion {
        val raw = JSONObject()
        if (evidence.isNotEmpty()) raw.put("differential", JSONObject().put("evidence", JSONArray(evidence.map {
            JSONObject().put("id", it.id).put("source", it.source).put("title", it.title).put("url", it.url)
        })))
        return MCQQuestion(stem = stem, options = listOf("a", "b", "c", "d"), correctIndex = 0, source = source, rawJson = raw.toString())
    }

    // MARK: citations, as Provenance writes them

    @Test fun citations() {
        assertEquals("a citation names its lecture", "Lupus", SetCredits.lectureName(Provenance.label("Lupus", 14)))
        assertEquals("a lecture whose name has a comma in it", "Renal, part 2", SetCredits.lectureName(Provenance.label("Renal, part 2", 3)))
        assertEquals("a citation with no lecture name names none", "", SetCredits.lectureName(Provenance.label("", 3)))
        assertTrue("cites matches the lecture and no other",
            SetCredits.cites("Lupus, p. 14", "Lupus") && !SetCredits.cites("Lupus, p. 14", "Lupus 2"))
    }

    // MARK: one set

    private val medline = EvidenceRef("m1", "MedlinePlus", "Lupus", "https://medlineplus.gov/lupus.html")
    private val pmc = EvidenceRef("p1", "Europe PMC", "Lupus nephritis (Kidney Int, 2024)", "https://doi.org/10.1/x")
    private val fda = EvidenceRef("f1", "openFDA label", "hydroxychloroquine (FDA label, effective 2025)",
        "https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=1")
    private val odd = EvidenceRef("x1", "Somewhere new", "A page", "https://example.org/a")

    @Test fun oneSet() {
        val lupus = SourceDoc(name = "Lupus", kind = "pdf", pages = listOf(SourcePage(1, "SLE"), SourcePage(2, "Malar rash", recognised = true)))
        val renal = SourceDoc(name = "Renal", kind = "powerpoint", pages = listOf(SourcePage(1, "Nephritis")))
        val set = StudySet(name = "SLE", kind = StudySetKind.MCQ, sources = listOf(lupus, renal),
            questions = listOf(
                question("q1", "Lupus, p. 1", listOf(medline, pmc)),
                question("q2", "Lupus, p. 2", listOf(medline)),          // the same MedlinePlus page again
                question("q3", "Renal, p. 1", listOf(fda, odd)),
                question("q4", "Cardio, p. 9"),                           // a lecture no longer kept
                question("q5"),                                           // typed in
            ),
            // a card cites a page too
            cards = listOf(AnkiCard(type = AnkiCardType.QA, source = "Renal, p. 1")))
        val credits = SetCredits.make(set, "USMLE Step 2 CK" to "medqa-step23")

        assertEquals("every lecture is listed, in the set's order", listOf("Lupus", "Renal"), credits.lectures.map { it.source.name })
        assertEquals("with how many questions and cards cite each", listOf(2, 2), credits.lectures.map { it.cited })
        assertEquals("a lecture's detail says its kind, its pages and how many were read from pictures",
            "PDF · 2 pages · 1 read from pictures", credits.lectures[0].detail)
        assertEquals("slides are counted as slides", "Slides · 1 slide", credits.lectures[1].detail)
        assertEquals("a cited lecture that is no longer kept is still named", listOf("Cardio"), credits.citedElsewhere)
        assertTrue("the exam's style bank is credited", credits.style?.id == "medqa" && credits.examName == "USMLE Step 2 CK")
        assertEquals("each public source is listed once, in the catalogue's order",
            listOf("medlineplus", "europepmc", "openfda"), credits.evidence.map { it.source.id })
        assertEquals("an evidence page cited twice is listed once", 1, credits.evidence.first().refs.size)
        assertEquals("evidence from a source with no known licence is kept apart, not dropped", listOf(odd), credits.otherEvidence)
        assertTrue("a set with all this is not empty", !credits.isEmpty)
    }

    @Test fun barerSets() {
        val bare = SetCredits.make(StudySet(name = "Typed", kind = StudySetKind.ANKI), null)
        assertTrue("a typed-in set with no exam has nothing recorded", bare.isEmpty)
        assertNull("an exam with no openly licensed bank credits none",
            SetCredits.make(StudySet(name = "x", kind = StudySetKind.MCQ), "PLAB 1" to "none").style)
        assertTrue("MedMCQA's exams credit MedMCQA",
            ContentSources.styleBank("medmcqa")?.id == "medmcqa" && ContentSources.styleBank("medqa-step1")?.id == "medqa")
        // the exams the credits know, as iOS's catalogue names them
        fun style(id: String?) = ExamCatalog.exam(id)?.let { it.name to it.exemplars.rawValue }
        assertEquals(21, ExamCatalog.all.size)
        assertEquals("USMLE Step 2 CK" to "medqa-step23", style("step2ck"))
        assertEquals("NEET-PG" to "medmcqa", style("neetpg"))
        assertNull(style(null))
    }

    // MARK: the app's own list

    @Test fun theAppsOwnList() {
        assertTrue("every source names a licence with a link, a credit line and a home page",
            ContentSources.all.all { source ->
                source.licences.isNotEmpty() && source.licences.all { it.url.startsWith("https://") } &&
                    source.attribution.isNotEmpty() && source.home.startsWith("https://")
            })
        assertEquals("ids are unique", ContentSources.all.size, ContentSources.all.map { it.id }.toSet().size)
        assertTrue("CC BY content says what was changed",
            ContentSources.all.filter { ContentSources.ccBy4 in it.licences }.all { (it.changes ?: "").length > 20 })
        assertTrue("MedlinePlus is credited the way it asks",
            ContentSources.medlinePlus.attribution.startsWith("Courtesy of MedlinePlus from the National Library of Medicine"))
    }

    /** The repository's root: the folder holding upstream/ios/RedPen. */
    private fun root(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "upstream/ios/RedPen").exists()) dir = dir.parentFile
        return requireNotNull(dir) { "the repository root, with upstream/ios/RedPen" }
    }

    // the bundled exemplars carry their own licence lines: each bank they name
    // is on the list, with the same licence (iOS bundles them; Android reads
    // iOS's ExamExemplarData from upstream/)
    @Test fun theBundledExemplarsMatchTheirCredits() {
        val data = File(root(), "upstream/ios/RedPen/Shared/Exam/ExamExemplarData.swift").readText()
        val json = data.substring(data.indexOf("{\"version\""))
        val licences = Regex("\"licences\":(\\[[^\\]]*\\])").find(json)?.groupValues?.get(1)
        assertTrue("the bundled exemplars can be read", licences != null)
        val lines = JSONArray(licences).let { a -> (0 until a.length()).map { a.getString(it) } }
        assertEquals("the bundled exemplars name two banks", 2, lines.size)
        val medqaLine = lines.firstOrNull { it.startsWith("MedQA") } ?: ""
        val medmcqaLine = lines.firstOrNull { it.startsWith("MedMCQA") } ?: ""
        assertTrue("MedQA's line matches its credit",
            medqaLine.contains("MIT") && medqaLine.contains("CC-BY-4.0") &&
                ContentSources.medqa.licences == listOf(ContentSources.mit, ContentSources.ccBy4))
        assertTrue("MedMCQA's line matches its credit",
            medmcqaLine.contains("Apache-2.0") && ContentSources.medmcqa.licences == listOf(ContentSources.apache2))
    }

    // the Earth's imagery is credited in Settings with the line its maps'
    // SOURCES.md gives, word for word (Android's copy of it, in assets/earth)
    @Test fun theEarthImageryIsCredited() {
        val sources = File(root(), "app/src/main/assets/earth/SOURCES.md").readText()
        val flat = sources.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        assertTrue("the Earth imagery's credit is its SOURCES.md's, word for word",
            flat.contains("\"" + ContentSources.nasaEarthCredit + "\"") &&
                ContentSources.nasaEarth.attribution.startsWith(ContentSources.nasaEarthCredit))
        assertTrue("the Earth imagery is in Settings' list", ContentSources.nasaEarth in ContentSources.all)
    }
}
