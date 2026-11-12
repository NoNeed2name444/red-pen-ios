package com.stethoscore.app.llm

import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.OcclusionBox
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySetKind
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T0237: a cloud recipe makes the set for every kind iOS finishes without its
 * screen (CloudRecipe in Shared/CloudJobCollector.swift), and what is kept with
 * the job reads back whole. Each kind goes through a job's record on disk, the
 * way a closed app finds it.
 */
class CloudRecipeTest {
    private val lecture = SourceDoc(
        id = "doc-1", name = "Lupus lecture", kind = "pdf", addedAt = 0,
        pages = listOf(SourcePage(1, "Lupus is an autoimmune disease.", true), SourcePage(2, "Anti-dsDNA is specific.")),
    )

    /** The recipe as a closed app finds it: in its job's record on disk, read back with the job's note. */
    private fun kept(recipe: CloudRecipe, extra: String? = null): Pair<CloudRecipe, String?> {
        val folder = kotlin.io.path.createTempDirectory("recipe-jobs").toFile()
        try {
            val jobs = CloudJobs.FileStore(folder)
            jobs.save(CloudJobs.Pending("job-1", "Writing ${recipe.count} ${recipe.kind.cloudNoun}", 1L, launch = null, recipe = recipe.json(), extra = extra))
            val read = jobs.all().single()
            return CloudRecipe.of(read.recipe)!! to read.extra
        } finally {
            folder.deleteRecursively()
        }
    }

    /** What was kept is what was sent: the same words, field for field. */
    private fun assertReadsBack(recipe: CloudRecipe): CloudRecipe {
        val (read, _) = kept(recipe)
        assertEquals(recipe.json(), read.json())
        assertEquals(recipe.kind, read.kind)
        assertEquals(recipe.name, read.name)
        assertEquals(recipe.subject, read.subject)
        assertEquals(recipe.count, read.count)
        assertEquals(recipe.exam, read.exam)
        assertEquals(recipe.figures, read.figures)
        assertEquals(recipe.diagramImages, read.diagramImages)
        assertEquals(recipe.diagramCards?.size, read.diagramCards?.size)
        assertEquals(recipe.source?.copy(addedAt = 0), read.source?.copy(addedAt = 0))
        return read
    }

    private fun question(stem: String) = JSONObject().put("stem", stem)
        .put("options", JSONArray(listOf("Atenolol tablets", "Amlodipine tablets", "Ramipril tablets", "Indapamide tablets")))
        .put("correctIndex", 2).put("explanation", "Key point: ACE inhibitors first.")

    private val questions = JSONObject().put("questions", JSONArray(listOf(question("First line for a 50-year-old?"), question("Which drug for diabetic kidney disease?")))).toString()

    private fun station(title: String) = JSONObject().put("title", title).put("steps", JSONArray(listOf(
        "Introduce yourself and confirm the patient's name", "Explain the examination and gain consent", "Wash your hands",
        "Inspect from the end of the bed", "Thank the patient")))

    private val stations = JSONObject().put("stations", JSONArray(listOf(station("Knee examination"), station("Hip examination")))).toString()

    private val cardLines = "What spares the nasolabial folds? | the **malar** rash | lupus\nWhich antibody is most specific? | **anti-dsDNA**\nThe malar rash spares the {{c1::nasolabial folds}}"

    private val oneCase = """{"complaint":"Pain in the knee","steps":[{"label":"Look at the knee","finding":"Red and swollen","group":"examine"}]}"""

    private val nothing = listOf("Not JSON at all.", "", "   ")

    // MARK: each kind, kept and read back

    @Test fun questionsReadBackAndMakeTheirSet() {
        val read = assertReadsBack(CloudRecipe(StudySetKind.MCQ, "Heart drugs", "Cardiology", 2, source = lecture, exam = "usmle1"))
        val set = read.set(listOf(questions), null)!!
        assertEquals("Heart drugs", set.name)
        assertEquals("Cardiology", set.subject)
        assertEquals(StudySetKind.MCQ, set.kind)
        assertEquals("usmle1", set.exam)
        assertEquals(2, set.questions.size)
        assertEquals(listOf("doc-1"), set.sources.map { it.id })
    }

    @Test fun stationsReadBackAndMakeTheirSet() {
        val read = assertReadsBack(CloudRecipe(StudySetKind.OSCE, "", "Orthopaedics", 2))
        val set = read.set(listOf(stations), null)!!
        assertEquals("Orthopaedics – OSCE stations", set.name)
        assertEquals(StudySetKind.OSCE, set.kind)
        assertEquals(listOf("Knee examination", "Hip examination"), set.osceChecklists.map { it.title })
        assertTrue(set.cards.isEmpty() && set.questions.isEmpty())
    }

    @Test fun stationsAreCutToTheCountAskedAndRepeatsDropped() {
        val repeated = JSONObject().put("stations", JSONArray(listOf(station("Knee examination"), station("KNEE EXAMINATION"), station("Hip examination")))).toString()
        val set = CloudRecipe(StudySetKind.OSCE, "", "", 1).set(listOf(repeated), null)!!
        assertEquals(listOf("Knee examination"), set.osceChecklists.map { it.title })
        assertEquals("General", set.subject)
        assertEquals("Generated – OSCE stations", set.name)
    }

    @Test fun cardsReadBackAndMakeTheirSet() {
        val read = assertReadsBack(CloudRecipe(StudySetKind.ANKI, "Lupus cards", "Rheumatology", 10, source = lecture))
        val set = read.set(listOf(cardLines), null)!!
        assertEquals("Lupus cards", set.name)
        assertEquals(StudySetKind.ANKI, set.kind)
        assertEquals(listOf(AnkiCardType.QA, AnkiCardType.QA, AnkiCardType.CLOZE), set.cards.map { it.type })
        assertEquals("What spares the nasolabial folds?", set.cards.first().front)
        assertTrue(set.images.isEmpty())
    }

    @Test fun theImageOcclusionCardsRideAlongWithTheWrittenOnes() {
        val diagram = AnkiCard(
            id = "diagram-1", type = AnkiCardType.OCCLUSION, front = "Label the aorta", imageIndex = 0,
            occlusion = OcclusionBox(0.1, 0.2, 0.3, 0.4), siblings = listOf(OcclusionBox(0.5, 0.5, 0.1, 0.1)),
        )
        val recipe = CloudRecipe(StudySetKind.ANKI, "Heart cards", "Cardiology", 3, diagramCards = listOf(diagram), diagramImages = listOf("picture-one"))
        val read = assertReadsBack(recipe)
        val back = read.diagramCards!!.single()
        assertEquals("diagram-1", back.id)
        assertEquals(AnkiCardType.OCCLUSION, back.type)
        assertEquals(0, back.imageIndex)
        assertEquals(0.3, back.occlusion!!.w, 0.0)
        assertEquals(1, back.siblings.size)
        val set = read.set(listOf(cardLines), null)!!
        // the written cards first, then the diagram's, on the pictures they were cut from
        assertEquals(4, set.cards.size)
        assertEquals("diagram-1", set.cards.last().id)
        assertEquals(listOf("picture-one"), set.images)
    }

    @Test fun diagramCardsNeedTheirPicturesAndSomethingToCarry() {
        val diagram = AnkiCard(id = "diagram-1", type = AnkiCardType.OCCLUSION, imageIndex = 0, occlusion = OcclusionBox(0.1, 0.1, 0.2, 0.2))
        // cards with no pictures, and pictures with no cards: neither is carried
        val noPictures = CloudRecipe(StudySetKind.ANKI, "", "", 3, diagramCards = listOf(diagram)).set(listOf(cardLines), null)!!
        assertEquals(3, noPictures.cards.size)
        assertTrue(noPictures.images.isEmpty())
        val noCards = CloudRecipe(StudySetKind.ANKI, "", "", 3, diagramCards = emptyList(), diagramImages = listOf("picture-one")).set(listOf(cardLines), null)!!
        assertEquals(3, noCards.cards.size)
        assertTrue(noCards.images.isEmpty())
    }

    @Test fun aTextbookReadsBackWithItsFiguresAndPlacement() {
        val figures = listOf("figure-zero", "figure-one", "figure-two")
        val read = assertReadsBack(CloudRecipe(StudySetKind.BOOK, "Lupus textbook", "Rheumatology", 2, source = lecture, figures = figures))
        assertEquals(figures, read.figures)
        val replies = listOf(
            "## Lupus\n\n### Definition\n\nAn autoimmune disease.\n\n![The malar rash](image:1)",
            "## Gout\n\n### Definition\n\nUrate crystals.",
        )
        // the job's note: page one was given figure 1, page two none
        val (_, extra) = kept(read, "[[1],[]]")
        assertEquals("[[1],[]]", extra)
        val set = read.set(replies, extra)!!
        assertEquals("Lupus textbook", set.name)
        assertEquals(StudySetKind.BOOK, set.kind)
        assertTrue(set.bookMarkdown.startsWith("## Lupus"))
        assertTrue(set.bookMarkdown.contains("## Gout"))
        // only the picture the pages show is kept, and numbered from the start of the set's own
        assertEquals(listOf("figure-one"), set.images)
        assertTrue(set.bookMarkdown.contains("![The malar rash](image:0)"))
        assertTrue(!set.bookMarkdown.contains("image:1"))
    }

    @Test fun aTextbookPlacesAFigureItsPageDidNotUse() {
        val set = CloudRecipe(StudySetKind.BOOK, "", "", 1, figures = listOf("figure-zero", "figure-one"))
            .set(listOf("## Heart\n\n### Definition\n\nA pump."), "[[1]]")!!
        assertTrue(set.bookMarkdown.contains("### Figures from the lecture"))
        assertEquals(listOf("figure-one"), set.images)
    }

    @Test fun aTextbookWithoutItsNoteIsStillWrittenWithoutPictures() {
        val recipe = CloudRecipe(StudySetKind.BOOK, "", "", 1, figures = listOf("figure-zero"))
        for (extra in listOf(null, "not json", "{}", "[1,2]")) {
            val set = recipe.set(listOf("## Heart\n\n### Definition\n\nA pump."), extra)
            assertNotNull(extra, set)
            assertTrue(extra, set!!.images.isEmpty())
            assertTrue(extra, set.bookMarkdown.startsWith("## Heart"))
        }
        assertNull(CloudRecipe(StudySetKind.BOOK, "", "", 1).set(emptyList(), "[[]]"))
    }

    @Test fun aLectureThatIsNarratedIsNotWrittenInTheCloud() {
        val read = assertReadsBack(CloudRecipe(StudySetKind.NARRATE, "Spoken lecture", "Cardiology", 1, source = lecture))
        assertNull(read.set(listOf("en|Hello"), null))
    }

    @Test fun casesReadBackAndMakeTheirSetFromTheLecture() {
        val read = assertReadsBack(CloudRecipe(StudySetKind.CASES, "Knee cases", "Orthopaedics", 2, source = lecture))
        val set = read.set(listOf(oneCase), null)!!
        assertEquals("Knee cases", set.name)
        assertEquals(StudySetKind.CASES, set.kind)
        assertEquals(1, set.caseFiles.size)
        assertEquals("Lupus lecture", set.caseFiles.single().source.lecture)
        assertEquals(listOf("doc-1"), set.sources.map { it.id })
    }

    // MARK: replies that make no set

    @Test fun repliesThatMakeNothingMakeNoSetForEveryKind() {
        assertNull(CloudRecipe(StudySetKind.MCQ, "", "", 2).set(nothing, null))
        assertNull(CloudRecipe(StudySetKind.OSCE, "", "", 2).set(nothing, null))
        assertNull(CloudRecipe(StudySetKind.ANKI, "", "", 2).set(nothing, null))
        assertNull(CloudRecipe(StudySetKind.CASES, "", "", 2).set(nothing, null))
        assertNull(CloudRecipe(StudySetKind.NARRATE, "", "", 2).set(listOf(cardLines), null))
        // a set with pictures of its own but nothing written is still nothing
        val diagram = AnkiCard(id = "diagram-1", type = AnkiCardType.OCCLUSION, imageIndex = 0, occlusion = OcclusionBox(0.1, 0.1, 0.2, 0.2))
        assertNull(CloudRecipe(StudySetKind.ANKI, "", "", 2, diagramCards = listOf(diagram), diagramImages = listOf("p")).set(nothing, null))
    }

    // MARK: the stored form

    @Test fun aRecipeKeptBeforeFiguresExistedStillReads() {
        val old = """{"kind":"mcq","name":"","subject":"Cardiology","count":2,"source":null,"exam":"usmle1"}"""
        val read = CloudRecipe.of(old)!!
        assertEquals(CloudRecipe(StudySetKind.MCQ, "", "Cardiology", 2, exam = "usmle1"), read)
        assertNull(read.figures)
        assertNull(read.diagramCards)
        assertNull(read.diagramImages)
    }

    @Test fun everyKindIsKnownByItsStoredName() {
        for (kind in StudySetKind.values()) {
            val read = CloudRecipe.of(CloudRecipe(kind, "n", "s", 1).json())
            assertEquals(kind, read?.kind)
        }
    }

    @Test fun aRecipeThatCannotBeReadIsNone() {
        assertNull(CloudRecipe.of(null))
        assertNull(CloudRecipe.of("not json"))
        assertNull(CloudRecipe.of("""{"kind":"podcast","name":"","subject":"","count":1}"""))
        assertNull(CloudRecipe.of("""{"name":"","subject":"","count":1}"""))
    }

    @Test fun theNounsAKindIsCalledByAreIosWords() {
        assertEquals(
            listOf("questions", "OSCE stations", "cards", "textbook", "lecture", "cases"),
            listOf(StudySetKind.MCQ, StudySetKind.OSCE, StudySetKind.ANKI, StudySetKind.BOOK, StudySetKind.NARRATE, StudySetKind.CASES).map { it.cloudNoun },
        )
    }
}
