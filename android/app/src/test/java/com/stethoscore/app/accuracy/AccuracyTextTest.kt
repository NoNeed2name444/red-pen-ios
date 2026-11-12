package com.stethoscore.app.accuracy

import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.OsceChecklist
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.llm.AccuracyCheck
import com.stethoscore.app.llm.AccuracySendOutcome
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.quiz.DifferentialEntry
import com.stethoscore.app.quiz.DifferentialTiers
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

// What a checker is shown for an item and the lecture excerpt it is checked
// against: ios/RedPen/Tests/LLMTests.swift "what the checker is shown for a
// question" (107-120) and DifferentialTests.swift "what the checker is shown"
// (148-152), AccuracyText.swift's reference (the Word-lecture cases of
// LLMTests.swift 75-103 are in data/TextSlicingTest), and the checker call
// carrying the excerpt as AccuracyStore.build does.
class AccuracyTextTest {

    // LLMTests.swift:107-109
    @Test fun aSixthOptionIsFAndTheKeyNamesIt() {
        val six = AccuracyText.checkedQuestion("Which?", listOf("a", "b", "c", "d", "e", "f"), 5, "Because.")
        assertTrue(six.contains("\nF. f") && six.contains("Answer: F"))
        assertFalse("no two options share a letter", six.contains("E. f"))
    }

    // LLMTests.swift:110-111
    @Test fun fiveOptionsReadExactlyAsBefore() {
        assertEquals("Which?\nA. a\nB. b\nC. c\nD. d\nE. e\nAnswer: B\nExplanation: x",
            AccuracyText.checkedQuestion("Which?", listOf("a", "b", "c", "d", "e"), 1, "x"))
    }

    // LLMTests.swift:112-116
    @Test fun aKeyOfMinusOneOrPastTheLastOptionIsSaidToBeMissingNotReadOutOfRange() {
        assertTrue(AccuracyText.checkedQuestion("Which?", listOf("a", "b"), -1, "x").contains("Answer: none keyed"))
        assertTrue(AccuracyText.checkedQuestion("Which?", listOf("a"), 7, "x").contains("Answer: none keyed"))
    }

    @Test fun pastZTheOptionsNumberIsTheLetter() {
        assertEquals("A", AccuracyText.letter(0))
        assertEquals("Z", AccuracyText.letter(25))
        assertEquals("27", AccuracyText.letter(26))
    }

    // AccuracyText.swift:13-17: a question's text is its checked question and, when it has one, its differential
    private val hernia = DifferentialTiers(
        mostLikely = listOf(DifferentialEntry("Indirect inguinal hernia", listOf("Young man", "lump above the pubic tubercle"), listOf("below it"), "ultrasound")),
        expanded = listOf(DifferentialEntry("Hydrocele", listOf("transilluminates")), DifferentialEntry("Varicocele")),
        cantMiss = listOf(DifferentialEntry("Testicular torsion", test = "urgent scrotal ultrasound")),
    )

    private fun question(rawJson: String = "{}") = MCQQuestion(stem = "A man has a groin lump.", options = listOf("a", "b", "c", "d", "e"), correctIndex = 1,
        explanation = "Because.", rawJson = rawJson)

    @Test fun aQuestionWithNoDifferentialIsJustItsCheckedQuestion() {
        val q = question()
        assertEquals(AccuracyText.checkedQuestion(q.stem, q.options, q.correctIndex, q.explanation), AccuracyText.checkText(q))
        assertEquals("", AccuracyText.differentialBlock(null))
        assertEquals("", AccuracyText.differentialBlock(DifferentialTiers()))
    }

    // DifferentialTests.swift:148-152
    @Test fun theCheckerSeesEachTierOnItsOwnLine() {
        val text = AccuracyText.differentialText(hernia)
        assertTrue(text, text.startsWith("- Most likely: Indirect inguinal hernia (for: Young man, lump above the pubic tubercle; against: below it; test: ultrasound)"))
        assertTrue(text.contains("\n- Expanded: Hydrocele (for: transilluminates); Varicocele"))
        assertTrue(text.contains("\n- Can’t miss: Testicular torsion (test: urgent scrotal ultrasound)"))
        assertEquals(3, text.lines().size)
    }

    @Test fun anEmptyTierIsLeftOutAndAnEntryWithNoDetailIsItsNameAlone() {
        val d = DifferentialTiers(mostLikely = listOf(DifferentialEntry("Gout")), cantMiss = listOf(DifferentialEntry("Septic arthritis", against = listOf("afebrile"))))
        assertEquals("- Most likely: Gout\n- Can’t miss: Septic arthritis (against: afebrile)", AccuracyText.differentialText(d))
    }

    @Test fun theDifferentialBlockIsHeadedAndSitsAfterTheExplanation() {
        val raw = """{"differential":{"mostLikely":[{"name":"Indirect inguinal hernia","supporting":["Young man"],"against":[],"test":"ultrasound"}]}}"""
        val q = question(raw)
        assertEquals(AccuracyText.checkedQuestion(q.stem, q.options, q.correctIndex, q.explanation) +
            "\nDifferential:\n- Most likely: Indirect inguinal hernia (for: Young man; test: ultrasound)", AccuracyText.checkText(q))
        assertTrue(AccuracyText.differentialBlock(hernia).startsWith("\nDifferential:\n- Most likely:"))
    }

    // the same wording as the server's jobs.js differentialText, tier title for tier title
    @Test fun theTierTitlesAreTheServers() {
        val server = serverFile("server/jobs.js")
        val titles = Regex("""\['([^']+)', \[""").findAll(server.substring(server.indexOf("const TIERS ="))).map { it.groupValues[1] }.take(3).toList()
        assertEquals(listOf("Most likely", "Expanded", "Can\\u2019t miss"), titles)
        val text = AccuracyText.differentialText(DifferentialTiers(listOf(DifferentialEntry("a")), listOf(DifferentialEntry("b")), listOf(DifferentialEntry("c"))))
        assertEquals(listOf("- Most likely: a", "- Expanded: b", "- Can’t miss: c"), text.lines())
    }

    // AccuracyText.swift:25-27
    @Test fun aStationIsItsTitleAndItsSteps() {
        assertEquals("Chest examination\n- Wash hands\n- Introduce yourself", AccuracyText.checkText(OsceChecklist(title = "Chest examination", steps = listOf("Wash hands", "Introduce yourself"))))
        // as on iOS (AccuracyText.swift:26): the title, a line break, then the steps - none, here
        assertEquals("Empty\n", AccuracyText.checkText(OsceChecklist(title = "Empty", steps = emptyList())))
    }

    @Test fun theNoSourceNoteIsIOSsWordForWord() {
        assertEquals("No source document was provided. Judge the output against standard, current medical teaching for students; treat any claim that contradicts it as a fabricated claim.", AccuracyText.noSourceNote)
    }

    // MARK: the lecture excerpt (AccuracyText.reference)

    // a Word lecture is one page, one line per paragraph, bigger than the budget (LLMTests.swift:80-90)
    private val wordPage = ((1..300).map { "Line $it about renal physiology and tubular transport." } +
        "Furosemide blocks the NKCC2 cotransporter in the thick ascending limb." +
        (1..300).map { "Line $it about cardiac output and preload." }).joinToString("\n")

    private val lecture = SourceDoc(name = "Diuretics", pages = listOf(SourcePage(1, wordPage)))

    private fun set(vararg sources: SourceDoc, questions: List<MCQQuestion> = emptyList()) =
        StudySet(name = "Diuretics", kind = StudySetKind.MCQ, questions = questions, sources = sources.toList())

    @Test fun aOnePageWordLectureOverTheBudgetIsStillUsedAtTheMatchingLineWithItsPageNamed() {
        assertTrue(wordPage.length > 8_000)
        val reference = AccuracyText.reference("Which cotransporter does furosemide block?", set(lecture), 8_000)
        assertNotNull(reference)
        assertTrue(reference!!.contains("NKCC2"))
        assertTrue(reference.length <= 8_000)
        assertTrue(reference.startsWith("Diuretics, 1:"))
    }

    @Test fun aSetWithNoSourceHasNoReference() {
        assertNull(AccuracyText.reference("furosemide", set(), 1_400))
    }

    @Test fun noSharedWordNoReference() {
        assertNull(AccuracyText.reference("zzzz qqqq", set(SourceDoc(name = "L", pages = listOf(SourcePage(1, "Asthma.")))), 1_000))
    }

    @Test fun theBestPageComesFirstAcrossDocumentsAndPagesAreNamedByDocumentAndNumber() {
        val a = SourceDoc(name = "Resp", pages = listOf(SourcePage(1, "Asthma: salbutamol relieves bronchospasm.")))
        val b = SourceDoc(name = "Cardio", pages = listOf(SourcePage(7, "Heart failure: furosemide for congestion.")))
        val reference = AccuracyText.reference("furosemide in heart failure", set(a, b), 1_000)
        assertTrue(reference, reference!!.startsWith("Cardio, 7:\n"))
    }

    // MARK: the checker call carries the excerpt as iOS does (AccuracyStore.build, AccuracyItem.sourceLimit)

    private val furosemide = MCQQuestion(stem = "Which cotransporter does furosemide block?", options = listOf("NKCC2", "NCC", "ENaC", "Aquaporin", "Na/K-ATPase"),
        correctIndex = 0, explanation = "Furosemide blocks the NKCC2 cotransporter in the thick ascending limb.")

    @Test fun everyItemOfASetComesWithItsLectureExcerptWithinTheLimit() {
        val s = set(lecture, questions = listOf(furosemide))
        val items = AccuracyCheck.items(s)
        assertEquals(1, items.size)
        assertTrue(items[0].source.startsWith("Diuretics, 1:"))
        assertTrue(items[0].source.contains("NKCC2"))
        assertTrue(items[0].source.length <= AccuracyItem.sourceLimit)
        assertEquals(1_400, AccuracyItem.sourceLimit)
        // the item is the one the set's own order gives, with the source the only difference
        assertEquals(AccuracyItem.mcq(furosemide).copy(source = items[0].source), items[0])
    }

    @Test fun aSetWithNoSourceGivesItemsWithNoExcerpt() {
        val items = AccuracyCheck.items(set(questions = listOf(furosemide)))
        assertEquals("", items.single().source)
    }

    @Test fun anItemOutsideItsSetGetsTheExcerptAndOneThatHasOneKeepsIt() {
        val s = set(lecture)
        val bare = AccuracyItem.mcq(furosemide)
        val withSource = AccuracyCheck.withExcerpt(bare, s)
        assertTrue(withSource.source.contains("NKCC2") && withSource.source.length <= 1_400)
        assertEquals(bare.copy(source = withSource.source), withSource)
        val held = bare.copy(source = "the student's own source")
        assertSame(held, AccuracyCheck.withExcerpt(held, s))
        assertSame(bare, AccuracyCheck.withExcerpt(bare, set()))
    }

    @Test fun theCheckerCallSendsTheLectureExcerptAsTheItemsSource() = runBlocking {
        val server = FakeServer { FakeServer.ok(JSONObject("""{"items":[]}""")) }
        val item = AccuracyCheck.items(set(lecture, questions = listOf(furosemide))).single()
        val sent = AccuracyCheck.send(server.client(FakeServer.standInKey()), listOf(item))
        assertEquals(AccuracySendOutcome.Done, sent.outcome)
        val request = server.requests.single()
        assertEquals("/accuracy/check", request.path)
        val body = request.body!!.getJSONArray("items").getJSONObject(0)
        assertEquals(item.source, body.getString("source"))
        assertTrue(body.getString("source").contains("NKCC2"))
        assertTrue(body.getString("source").length <= 1_400)
        assertEquals("mcq", body.getString("kind"))
        assertEquals("Which cotransporter does furosemide block?", body.getString("stem"))
        assertEquals(0, body.getInt("key"))
    }

    private fun serverFile(relative: String): String {
        var dir: java.io.File? = java.io.File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !java.io.File(dir, relative).exists()) dir = dir.parentFile
        assertNotNull("$relative is found from the test's working directory", dir)
        return java.io.File(dir, relative).readText(Charsets.UTF_8)
    }
}
