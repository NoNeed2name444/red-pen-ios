package com.stethoscore.app.ui

import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.OsceChecklist
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.llm.FakeJobs
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.OwnerSpend
import com.stethoscore.app.network.BackendClient
import com.stethoscore.app.ui.book.BookReaderScreen
import com.stethoscore.app.ui.editors.LocalLLMService
import com.stethoscore.app.ui.learn.LearnRouter
import com.stethoscore.app.ui.learn.LearnRouterClosed
import com.stethoscore.app.ui.library.IncomingFiles
import com.stethoscore.app.ui.library.IncomingWords
import com.stethoscore.app.ui.library.LibraryNewSetScreen
import com.stethoscore.app.ui.library.ModeSwitch
import com.stethoscore.app.ui.osce.OsceReviewScreen
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

// T0115b3 A2: Turn into and a lecture shared into the app, tapped from the
// screen to the result with a stand-in worker (FakeServer: nothing goes on the
// network). Turn into from a library row's menu, from the Turn into… tile's
// page, and from the More menu of the quiz, card review, OSCE review and book
// (iOS TurnIntoPicker, ModeConversion, studyMoreMenu, rowMenu,
// TurnIntoListView): an instant turn makes and opens the new set, a written one
// opens New set on Make with the material in. A lecture opened from another
// app gets the Received sheet, whose Make questions from this lecture opens
// New set on Make with it read in (iOS ImportInboxSheet, NewSetPreset(lecture:)).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TurnIntoReachTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private val seen = CopyOnWriteArrayList<FakeServer.Request>()

    @Before fun fresh() { ModeSwitch.reset(); IncomingFiles.waiting.clear() }
    @After fun tidy() { ModeSwitch.reset(); IncomingFiles.waiting.clear() }

    /** The owner's build's service (Stethoscore Cloud chosen, a stand-in key) on the stand-in worker. */
    private fun owner(jobs: FakeJobs? = null): LLMService = LLMService(
        LLMService.MemoryPrefs().also { it.set(LLMService.CHOICE_KEY, "cloud") }, FakeServer.standInKey(), { null }, FakeServer.BASE,
        FakeServer { seen += it; jobs?.answer(it) ?: BackendClient.Reply(404, "{}") }, OwnerSpend(OwnerSpend.MemoryStore()))

    private fun store(name: String): StudyStore = StudyStore(folder.newFolder(name))

    private fun show(llm: LLMService, content: @Composable () -> Unit) {
        LearnRouter.close()
        compose.setContent { CompositionLocalProvider(LocalLLMService provides llm) { StethoscoreTheme { content() } } }
    }

    private fun app(store: StudyStore, llm: LLMService = owner()) {
        LearnRouter.close()
        compose.setContent { CompositionLocalProvider(LocalLLMService provides llm) { StethoscoreApp(store, forceDark = false) } }
    }

    private fun until(done: () -> Boolean) {
        compose.waitUntil(timeoutMillis = 20_000) {
            if (!done()) compose.mainClock.advanceTimeBy(500)
            done()
        }
    }

    private fun sent(path: String): FakeServer.Request {
        until { seen.any { it.method == "POST" && it.path == path } }
        return seen.first { it.method == "POST" && it.path == path }
    }

    /** The study screen as the app hosts it: what Turn into delivers is opened, or New set raised (StethoscoreApp's ModeSwitch). */
    @Composable private fun Routed(store: StudyStore, screen: @Composable () -> Unit) {
        val writing = ModeSwitch.writing
        val opening = ModeSwitch.opening
        when {
            writing != null -> LibraryNewSetScreen(store, writing.kind, {}, {}, preset = writing)
            opening != null -> androidx.compose.material3.Text("Opened ${opening.name}")
            else -> screen()
        }
    }

    /** More, Turn into…, then the tile for [kind], whose words are [note]. */
    private fun turn(kind: StudySetKind, note: String, more: String = "More") {
        // home's New set button and dock float over the list's foot, where a row scrolled to can stand
        compose.onNodeWithContentDescription(more).performSemanticsAction(SemanticsActions.OnClick)
        compose.onNodeWithTag("turnInto").performClick()
        compose.onNodeWithTag("turnIntoPicker").assertExists()
        compose.onNode(hasTestTag("turnInto-${kind.rawValue}") and hasContentDescription("${kind.label}. $note")).performScrollTo().performClick()
        compose.waitForIdle()
        assertTrue("the picker has gone", compose.onAllNodesWithTag("turnIntoPicker").fetchSemanticsNodes().isEmpty())
    }

    private fun questions(): String = JSONObject().put("questions", JSONArray().put(JSONObject().put("stem", "Which antibody is most specific for SLE?")
        .put("options", JSONArray(listOf("Anti-dsDNA", "ANA", "Anti-Ro", "Anti-La", "Anti-Jo-1"))).put("correctIndex", 0)
        .put("explanation", "Key point: anti-dsDNA is specific."))).toString()

    private val quiz = StudySet(name = "Nephrology", subject = "Renal", kind = StudySetKind.MCQ, questions = listOf(
        MCQQuestion(stem = "Anti-PLA2R antibodies are most specific for which condition?",
            options = listOf("Membranous nephropathy", "Lupus nephritis", "IgA nephropathy", "Anti-GBM disease"), correctIndex = 0,
            explanation = "Found in most primary membranous nephropathy."),
        MCQQuestion(stem = "Which nephropathy follows an upper respiratory infection by a day or two?",
            options = listOf("IgA nephropathy", "Post-streptococcal glomerulonephritis", "Minimal change disease", "Membranous nephropathy"),
            correctIndex = 0, explanation = "Synpharyngitic haematuria.")))

    private fun lupus(): StudySet = StudySet(name = "Lupus", subject = "Rheumatology", kind = StudySetKind.ANKI, cards = listOf(
        AnkiCard(front = "Which drug lowers mortality in SLE?", bullets = listOf("Hydroxychloroquine")),
        AnkiCard(front = "Which antibody is the entry criterion for SLE?", bullets = listOf("Antinuclear antibody")),
        AnkiCard(front = "Which antibody is most specific for SLE?", bullets = listOf("Anti-double-stranded DNA")),
        AnkiCard(front = "Which drug is used for lupus nephritis induction?", bullets = listOf("Mycophenolate mofetil")),
        AnkiCard(front = "Which test monitors disease activity in SLE?", bullets = listOf("Complement C3 and C4")),
        AnkiCard(front = "Which skin sign spares the nasolabial folds?", bullets = listOf("The malar rash"))))

    // the library: a row's menu and the Turn into… tile's page, through the app

    @Test fun aLibraryRowTurnsAQuizIntoCardsAndOpensThem() {
        val store = store("row").also { it.addSet(quiz) }
        app(store)
        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollToIndex)).performScrollToNode(hasContentDescription("More for Nephrology"))
        turn(StudySetKind.ANKI, "Instant · 2 cards", more = "More for Nephrology")
        // the deck is made beside the quiz and opened at once, its first card on screen
        val deck = store.library.single { it.kind == StudySetKind.ANKI }
        assertEquals("Nephrology – Cards", deck.name)
        assertEquals(listOf("Membranous nephropathy"), deck.cards.first().bullets)
        assertEquals("the quiz is left as it was", 2, store.library.single { it.id == quiz.id }.questions.size)
        until { compose.onAllNodesWithText(quiz.questions.first().stem, substring = true).fetchSemanticsNodes().isNotEmpty() }
        assertTrue(seen.isEmpty())
    }

    @Test fun theTurnIntoTilesPagePicksASetToTurn() {
        val store = store("tile").also { it.addSet(quiz) }
        app(store)
        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollToIndex)).performScrollToNode(hasText("Turn into…"))
        compose.onAllNodes(hasText("Turn into…") and hasClickAction()).onFirst().performSemanticsAction(SemanticsActions.OnClick)
        until { compose.onAllNodesWithText("PICK A SET TO TURN", ignoreCase = true).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("The set you pick stays as it is; the new one opens straight away.").assertExists()
        compose.onNodeWithTag("turnPick-mcq").performClick()
        compose.onNodeWithText("“Nephrology” stays as it is. The new set is added beside it, with the same subject and folder.").assertExists()
        // the quiz's own mode lies low and cannot be chosen
        compose.onNode(hasTestTag("turnInto-mcq") and hasContentDescription("MCQ. This set")).assertIsNotEnabled()
        compose.onNode(hasTestTag("turnInto-osce") and hasContentDescription("OSCE. Written by AI from this set")).assertExists()
        compose.onNodeWithTag("turnInto-anki").performScrollTo().performClick()
        until { store.library.any { it.kind == StudySetKind.ANKI } }
        until { compose.onAllNodesWithText(quiz.questions.first().stem, substring = true).fetchSemanticsNodes().isNotEmpty() }
    }

    // the study screens' More menu

    @Test fun theQuizTurnsIntoCards() {
        val store = store("quiz").also { it.addSet(quiz) }
        show(owner()) { Routed(store) { QuizScreen(quiz, store, onBack = {}) } }
        turn(StudySetKind.ANKI, "Instant · 2 cards")
        until { compose.onAllNodesWithText("Opened Nephrology – Cards").fetchSemanticsNodes().isNotEmpty() }
        assertEquals(2, store.library.single { it.kind == StudySetKind.ANKI }.cards.size)
    }

    @Test fun aQuizNotSavedYetOffersNoTurnInto() {
        val store = store("unsaved")
        show(owner()) { QuizScreen(quiz, store, onBack = {}, isUnsaved = true) }
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithTag("checkAccuracy").assertExists()
        assertTrue(compose.onAllNodesWithTag("turnInto").fetchSemanticsNodes().isEmpty())
    }

    @Test fun theCardReviewTurnsADeckIntoAQuiz() {
        val store = store("cards")
        val set = lupus().also { store.addSet(it) }
        show(owner()) { Routed(store) { AnkiReviewScreen(set, store, onBack = {}) } }
        // the deck's own answers are the wrong options: five of six cards make questions
        turn(StudySetKind.MCQ, "Instant · 5 questions")
        until { compose.onAllNodesWithText("Opened Lupus – MCQ").fetchSemanticsNodes().isNotEmpty() }
        val made = store.library.single { it.kind == StudySetKind.MCQ }
        assertEquals(5, made.questions.size)
        assertTrue(made.questions.all { q -> q.options.all { o -> set.cards.any { it.bullets.single() == o } } })
    }

    @Test fun theOsceReviewTurnsAStationIntoCards() {
        val store = store("osce")
        val set = StudySet(name = "Skills", subject = "Clinical skills", kind = StudySetKind.OSCE, osceChecklists = listOf(
            OsceChecklist(title = "Venepuncture", steps = listOf("Wash hands", "Confirm identity", "Apply tourniquet"))))
        store.addSet(set)
        show(owner()) { Routed(store) { OsceReviewScreen(set, store, onBack = {}) } }
        turn(StudySetKind.ANKI, "Instant · 3 cards")
        until { compose.onAllNodesWithText("Opened Skills – Cards").fetchSemanticsNodes().isNotEmpty() }
        assertEquals("Venepuncture: what is the first step?", store.library.single { it.kind == StudySetKind.ANKI }.cards.first().front)
    }

    @Test fun theBookIsWrittenIntoQuestions() {
        val store = store("book")
        val set = StudySet(name = "Thyroid", subject = "Endocrinology", kind = StudySetKind.BOOK,
            bookMarkdown = "# Thyroid\n\nHashimoto's thyroiditis is the commonest cause of hypothyroidism where iodine is sufficient.")
        store.addSet(set)
        show(owner(FakeJobs(listOf(questions())))) { Routed(store) { BookReaderScreen(set, store, onBack = {}) } }
        turn(StudySetKind.MCQ, "Written by AI from this set")
        // New set on Make, with the book as the material: nothing is added until it is made
        assertNull(ModeSwitch.opening)
        assertEquals(1, store.library.size)
        compose.onAllNodesWithText("Make 8 questions").onFirst().performScrollTo().performClick()
        val job = sent("/jobs").body!!
        assertEquals("questions", job.getString("extract"))
        assertTrue(job.getJSONArray("sources").getString(0).contains("Hashimoto's thyroiditis is the commonest cause"))
    }

    // a lecture shared into the app

    /** A Word file of [paragraphs], as OfficeText reads one. */
    private fun docx(name: String, paragraphs: List<String>): File {
        val file = File(folder.newFolder("files"), name)
        ZipOutputStream(file.outputStream()).use { zip ->
            zip.putNextEntry(ZipEntry("word/document.xml"))
            val body = paragraphs.joinToString("") { "<w:p><w:r><w:t>$it</w:t></w:r></w:p>" }
            zip.write("<w:document><w:body>$body</w:body></w:document>".toByteArray())
            zip.closeEntry()
        }
        return file
    }

    @Test fun aLectureSharedIntoTheAppOpensNewSetOnMake() {
        val store = store("shared")
        val file = docx("Renal lecture.docx", listOf("Nephrotic syndrome is proteinuria above 3.5 g a day with hypoalbuminaemia and oedema.",
            "Minimal change disease is the commonest cause in children."))
        IncomingFiles.waiting += Uri.fromFile(file)
        app(store, owner(FakeJobs(listOf(questions()))))
        until { compose.onAllNodesWithTag("importInboxSheet").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Received").assertExists()
        compose.onNodeWithText("Renal lecture.docx").assertExists()
        compose.onNodeWithText(IncomingWords.lectureLine(file.length())).assertExists()
        compose.onNodeWithText("Read it and make questions from it. Nothing is added until you make them.").assertExists()
        compose.onNodeWithText("Make questions from this lecture").performClick()
        until { compose.onAllNodesWithTag("importInboxSheet").fetchSemanticsNodes().isEmpty() }
        assertTrue("nothing is added until the questions are made", store.library.isEmpty())
        until { compose.onAllNodesWithText("Make 8 questions").fetchSemanticsNodes().isNotEmpty() }
        compose.onAllNodesWithText("Make 8 questions").onFirst().performScrollTo().performClick()
        val job = sent("/jobs").body!!
        assertTrue("the lecture is what it writes from", job.getJSONArray("sources").getString(0).contains("Minimal change disease is the commonest cause in children."))
    }

    @Test fun aLectureThatCannotBeReadSaysWhy() {
        val store = store("broken")
        val file = File(folder.newFolder("bad"), "Slides.pptx").also { it.writeText("not a zip") }
        IncomingFiles.waiting += Uri.fromFile(file)
        app(store)
        until { compose.onAllNodesWithTag("importInboxSheet").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Make questions from this lecture").performClick()
        until { compose.onAllNodesWithText("Couldn’t read this lecture: ", substring = true).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Not now").performClick()
        until { compose.onAllNodesWithTag("importInboxSheet").fetchSemanticsNodes().isEmpty() }
    }

    @Test fun theSizeIsWrittenAsIOSWritesIt() {
        assertEquals("Zero KB", IncomingWords.size(0))
        assertEquals("512 bytes", IncomingWords.size(512))
        assertEquals("245 KB", IncomingWords.size(245_300))
        assertEquals("1.2 MB", IncomingWords.size(1_234_567))
        assertEquals("Lecture · 3 MB", IncomingWords.lectureLine(3_000_000))
    }
}
