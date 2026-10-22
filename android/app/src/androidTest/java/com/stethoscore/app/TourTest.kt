package com.stethoscore.app

import android.net.Uri
import android.os.SystemClock
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.stethoscore.app.data.AnkiRating
import com.stethoscore.app.data.AnswerEvent
import com.stethoscore.app.data.CardReview
import com.stethoscore.app.data.CaseRun
import com.stethoscore.app.data.CaseRunStore
import com.stethoscore.app.data.LibraryImport
import com.stethoscore.app.data.MCQAnswer
import com.stethoscore.app.data.Note
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.data.WardRoundPlan
import com.stethoscore.app.exam.NewSetPreset
import com.stethoscore.app.exam.WardCalc
import com.stethoscore.app.exam.WardPocket
import com.stethoscore.app.exam.WardScores
import com.stethoscore.app.ideas.GraphTheme
import com.stethoscore.app.ideas.IdeaBook
import com.stethoscore.app.ideas.NoteFolder
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.MockFormat
import com.stethoscore.app.quiz.MockMark
import com.stethoscore.app.quiz.MockResult
import com.stethoscore.app.quiz.MockSittingSave
import com.stethoscore.app.quiz.PassMark
import com.stethoscore.app.ui.AnkiReviewScreen
import com.stethoscore.app.ui.ExamToolSheet
import com.stethoscore.app.ui.ExamToolSheets
import com.stethoscore.app.ui.NewSetScreen
import com.stethoscore.app.ui.QuizScreen
import com.stethoscore.app.ui.QuizSummaryScreen
import com.stethoscore.app.ui.book.BookReaderScreen
import com.stethoscore.app.ui.cases.CaseDebriefScreen
import com.stethoscore.app.ui.cases.CaseDecisionScreen
import com.stethoscore.app.ui.cases.CaseListScreen
import com.stethoscore.app.ui.cases.CaseWardScreen
import com.stethoscore.app.ui.coverage.CoverageScreen
import com.stethoscore.app.ui.editors.CardEditSheet
import com.stethoscore.app.ui.editors.CardsEditorScreen
import com.stethoscore.app.ui.editors.QuestionEditSheet
import com.stethoscore.app.ui.exam.ExamPickerScreen
import com.stethoscore.app.ui.exam.ExamSheet
import com.stethoscore.app.ui.exam.WardPocketScreen
import com.stethoscore.app.ui.exam.WardPocketTab
import com.stethoscore.app.ui.ideas.MoveSheet
import com.stethoscore.app.ui.learn.LearnRoute
import com.stethoscore.app.ui.learn.LearnRouter
import com.stethoscore.app.ui.learn.WardRoundClock
import com.stethoscore.app.ui.library.CategoryFeature
import com.stethoscore.app.ui.library.CustomSessionSheet
import com.stethoscore.app.ui.library.DeleteSetsDialog
import com.stethoscore.app.ui.library.FoundCardSheet
import com.stethoscore.app.ui.library.ImportPreviewSheet
import com.stethoscore.app.ui.library.IncomingFiles
import com.stethoscore.app.ui.library.KindShelfScreen
import com.stethoscore.app.ui.library.LibraryAlert
import com.stethoscore.app.ui.library.LibraryNewSetScreen
import com.stethoscore.app.ui.library.NewSetPath
import com.stethoscore.app.ui.library.NewSetStep
import com.stethoscore.app.ui.library.StudyCategory
import com.stethoscore.app.ui.mock.MockLibrary
import com.stethoscore.app.ui.mock.MockResultsScreen
import com.stethoscore.app.ui.mock.MockSitting
import com.stethoscore.app.ui.mock.MockSittingScreen
import com.stethoscore.app.ui.mock.QuestionPick
import com.stethoscore.app.ui.narrate.FixTarget
import com.stethoscore.app.ui.narrate.FixWordSheet
import com.stethoscore.app.ui.narrate.NarrateReviewScreen
import com.stethoscore.app.ui.osce.OsceReviewScreen
import com.stethoscore.app.ui.parseStudySet
import com.stethoscore.app.ui.sources.SetCreditsScreen
import com.stethoscore.app.ui.sources.SourcePreviewSheet
import com.stethoscore.app.ui.vitals.InsightQuestionList
import com.stethoscore.app.ui.vitals.InsightQuiz
import com.stethoscore.app.ui.vitals.InsightQuizScreen
import com.stethoscore.app.ui.vitals.RuleSheetScreen
import com.stethoscore.app.ui.vitals.StoreInsight
import com.stethoscore.app.ui.vitals.VitalsNumbers
import com.stethoscore.app.ui.vitals.insightQuiz
import com.stethoscore.app.ui.ward.WardSection
import org.junit.After
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.File
import java.time.ZonedDateTime

/**
 * The Android app tour (T0126c): a still of every screen in the tour inventory that
 * Android has and a still can show, light and dark, as r<row>-<name>-<light|dark>.png.
 * tools/tour_screens_android.txt lists each row, its test and its shots, in the
 * inventory's order; capture-screenshots.sh runs this class only with `tour`.
 *
 * Content is the app's own: DemoData (loadExamples), InsightExamples and what the
 * examples hold. Nodes are found by routes, test tags, the app's own constants and
 * DemoData's text, never by the exam screens' wording.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class TourTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule val learnClosed = LearnRouterClosed()
    private val tour = TourCapture(compose)

    @Before fun clean() = tour.reset()
    @After fun tidy() = tour.reset()

    // MARK: the examples, by kind

    private fun StudyStore.first(kind: StudySetKind): StudySet =
        checkNotNull(library.firstOrNull { it.kind == kind }) { "Tour: the examples have no ${kind.rawValue} set" }

    private fun section(kind: StudySetKind) = WardSection.fromKindRaw(kind.rawValue)
    private val questions get() = section(StudySetKind.MCQ)
    private val cards get() = section(StudySetKind.ANKI)

    private fun tab(category: StudyCategory) =
        hasText(category.title) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)

    /** Shoots the app on [screen], each mode, after [ready] says it is there. */
    private fun appRoute(row: Int, name: String, screen: String, store: () -> StudyStore = tour::store, ready: () -> Unit = {}) {
        val stores = Mode.entries.associateWith { store() }
        tour.inEachMode(content = { m -> tour.App(stores.getValue(m), screen, m) }) { m -> ready(); tour.shot(row, name, m) }
    }

    /** Opens a learning sheet over home, each mode. */
    private fun learn(row: Int, name: String, modes: List<Mode> = Mode.entries, store: () -> StudyStore = tour::store, route: (StudyStore) -> LearnRoute) {
        val stores = Mode.entries.associateWith { store() }
        tour.inEachMode(modes, before = { m -> tour.ui { LearnRouter.open(route(stores.getValue(m))) } },
            content = { m -> tour.App(stores.getValue(m), "home", m) }) { m ->
            tour.waitFor("the learning sheet ($name)") { LearnRouter.route != null }
            tour.shot(row, name, m)
        }
    }

    /** InsightExamples' history, with two questions just got wrong while sure, so the confident mistakes are never empty. */
    private fun insightStore() = tour.historyStore(insightHistory = true) { library, now ->
        val respiratory = library.first { it.subject == "Respiratory" && it.kind == StudySetKind.MCQ }.questions
        respiratory.take(2).mapIndexed { i, q -> AnswerEvent(q.id, false, now + 1 + i, "sure", isExample = true) }
    }

    /** Yesterday's misses (the examples' nephrology questions) and today's (three respiratory ones): the evening and morning re-reads. */
    private fun rhythmStore() = tour.historyStore(insightHistory = false) { library, now ->
        val yesterday = ZonedDateTime.now().minusDays(1).withHour(12).withMinute(0).toInstant().toEpochMilli()
        val nephrology = library.first { it.kind == StudySetKind.MCQ }.questions
        val respiratory = library.first { it.subject == "Respiratory" && it.kind == StudySetKind.MCQ }.questions
        nephrology.map { AnswerEvent(it.id, false, yesterday, "maybe", isExample = true) } +
            respiratory.take(3).mapIndexed { i, q -> AnswerEvent(q.id, false, now - 1_000L * (i + 1), "sure", isExample = true) }
    }

    // MARK: launch and gates

    @Test fun r008_examOnboarding() {
        val store = tour.store()
        tour.inEachMode(content = { m -> tour.Page(m, WardSection.outside) { ExamPickerScreen(store, {}, isOnboarding = true) } }) { m ->
            tour.waitFor("the exam onboarding's skip", hasTestTag("examOnboardingSkip"))
            tour.shot(8, "exam-onboarding", m)
        }
    }

    // MARK: home and library

    @Test fun r013_home() = appRoute(13, "library", "home") { tour.waitFor("home's Settings button", hasContentDescription("Settings")) }

    @Test fun r014_dockPlaces() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> tour.App(stores.getValue(m), "home", m) }) { m ->
            for ((category, name) in listOf(StudyCategory.CARDS to "home-cards", StudyCategory.CASES to "home-cases",
                StudyCategory.OSCE to "home-osce", StudyCategory.AUDIO to "home-audio")) {
                tour.tap("the ${category.title} dock tab", tab(category))
                tour.shot(14, name, m)
            }
        }
    }

    @Test fun r015_emptyLibrary() = appRoute(15, "library-empty", "home", tour::bareStore)

    @Test fun r016_libraryUnreadable() = appRoute(16, "library-unreadable", "home", tour::unreadableStore)

    @Test fun r017_emptyCategory() {
        val stores = Mode.entries.associateWith {
            tour.store().also { s -> s.library.filter { it.kind == StudySetKind.CASES }.forEach { s.deleteSet(it.id) } }
        }
        tour.inEachMode(content = { m -> tour.App(stores.getValue(m), "home", m) }) { m ->
            tour.tap("the Cases dock tab", tab(StudyCategory.CASES))
            tour.shot(17, "category-empty", m)
        }
    }

    @Test fun r018_searchNoResults() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> tour.App(stores.getValue(m), "home", m) }) { m ->
            val search = hasSetTextAction() and hasContentDescription("Search")
            tour.waitFor("home's search field", search)
            compose.onAllNodes(search).onFirst().performTextInput("zzqx")
            tour.waitFor("the no-results line", hasText("zzqx", substring = true) and hasText("No results", substring = true))
            tour.shot(18, "search-empty", m)
        }
    }

    /** Home with [sheet] over it, each mode. */
    private fun overHome(row: Int, name: String, sheet: @androidx.compose.runtime.Composable (StudyStore) -> Unit) {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m ->
            tour.App(stores.getValue(m), "home", m)
            tour.Over(m, questions) { sheet(stores.getValue(m)) }
        }) { m -> tour.shot(row, name, m) }
    }

    @Test fun r019_foundCard() = overHome(19, "found-card") { s -> val deck = s.first(StudySetKind.ANKI); FoundCardSheet(deck, deck.cards.first(), {}, {}) }

    @Test fun r020_customSession() = overHome(20, "custom-session") { s -> CustomSessionSheet(s, "", {}) { _, _ -> } }

    @Test fun r021_selectingSets() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> tour.App(stores.getValue(m), "home", m) }) { m ->
            val set = stores.getValue(m).first(StudySetKind.MCQ)
            val select = hasText("Select") and hasClickAction()
            tour.scrollTo("the sets' Select button", select)
            tour.tap("the sets' Select button", select)
            tour.tap("the example question set's row", hasText(set.name, substring = true) and hasClickAction())
            tour.shot(21, "library-select", m)
        }
    }

    @Test fun r022_nameSheet() = overHome(22, "name-sheet") { s ->
        val set = s.first(StudySetKind.MCQ)
        com.stethoscore.app.ui.library.NameSheet("Rename set", "Set name", set.name, "Rename", {}) {}
    }

    @Test fun r023_deleteSets() = overHome(23, "library-delete") { DeleteSetsDialog(2, {}, {}) }

    @Test fun r024_nothingHereYet() = overHome(24, "nothing-yet") { LibraryAlert("Nothing here yet", CategoryFeature.MISTAKES.emptyText) {} }

    @Test fun r025_wardRound() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> tour.App(stores.getValue(m), "home", m) }) { m ->
            tour.ui { if (WardRoundClock.round == null) WardRoundClock.start(WardRoundPlan(25, 5)); WardRoundClock.expanded = false }
            tour.waitFor("the running ward round") { WardRoundClock.round != null }
            tour.shot(25, "ward-round", m)
            tour.ui { WardRoundClock.expanded = true }
            tour.shot(25, "ward-round-panel", m)
        }
    }

    @Test fun r027_shelf() = appRoute(27, "shelf", "shelf")

    @Test fun r028_shelfEmpty() {
        val store = tour.store()
        tour.inEachMode(content = { m -> tour.Page(m, cards) { KindShelfScreen(CategoryFeature.PICTURES, store, 0, {}, {}, {}) } }) { m ->
            tour.shot(28, "shelf-empty", m)
        }
    }

    // MARK: new set, import, editors

    @Test fun r029_newSetKind() = appRoute(29, "new", "newset")

    /** New set opened on its second step with typing chosen, as a category's Paste or import opens it. */
    private fun newSet(row: Int, name: String, steps: (Mode) -> Unit) {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m ->
            tour.Page(m, questions) { LibraryNewSetScreen(stores.getValue(m), StudySetKind.MCQ, {}, {}, NewSetStep.MATERIAL) }
        }) { m -> steps(m); tour.shot(row, name, m) }
    }

    @Test fun r030_newSetMaterial() = newSet(30, "new-material") { tour.waitFor("the Type or paste field", hasSetTextAction() and hasContentDescription(NewSetPath.TYPE.title)) }

    @Test fun r031_newSetMake() = newSet(31, "new-make") {
        val draft = hasSetTextAction() and hasContentDescription(NewSetPath.TYPE.title)
        tour.waitFor("the Type or paste field", draft)
        // the examples' own questions, in the format New set's help gives
        val typed = tour.store().first(StudySetKind.MCQ).questions.joinToString("\n") { q ->
            "${q.stem} | ${q.options.joinToString("; ")} | ${'A' + q.correctIndex} | ${q.explanation}"
        }
        compose.onAllNodes(draft).onFirst().performTextInput(typed)
        tour.tap("New set's Next button", hasText("Next") and hasClickAction())
        tour.waitFor("the Name field of step 3", hasSetTextAction() and hasContentDescription("Name"))
    }

    @Test fun r032_newSetPreset() {
        val preset = NewSetPreset.wardPocket(WardCalc.anionGap.title, WardPocket.practiceNotes(WardCalc.anionGap))
        tour.inEachMode(content = { m -> tour.Page(m, WardSection.outside) { NewSetScreen({}, {}, preset) } }) { m -> tour.shot(32, "new-preset", m) }
    }

    @Test fun r033_aiWriter() = newSet(33, "new-writer") {
        tour.tap("the From a lecture file path", hasText(NewSetPath.LECTURE.title, substring = true) and hasClickAction())
        val notes = hasSetTextAction() and hasContentDescription("Or paste your notes")
        tour.waitFor("the writer's notes field", notes)
        compose.onAllNodes(notes).onFirst().performTextInput(tour.store().first(StudySetKind.BOOK).bookPages.first())
        tour.tap("New set's Next button", hasText("Next") and hasClickAction())
        tour.waitFor("step 3's Name field", hasSetTextAction() and hasContentDescription("Name"))
    }

    /** The examples' cards as a two-column table, the way Quizlet or a spreadsheet exports them. */
    private fun cardTable(store: StudyStore): ByteArray = store.first(StudySetKind.ANKI).cards.filter { it.bullets.isNotEmpty() }
        .joinToString("\n") { "${it.displayFront}\t${it.bullets.joinToString("; ")}" }.toByteArray()

    @Test fun r035_importPreview() = overHome(35, "import-preview") { s ->
        ImportPreviewSheet(LibraryImport.previewDetecting("cardiology.tsv", cardTable(s), "Cardiology"), {}, {})
    }

    @Test fun r036_incomingFile() {
        val stores = Mode.entries.associateWith { tour.store() }
        val file = File(tour.context.cacheDir, "cardiology.tsv").also { it.writeBytes(cardTable(stores.getValue(Mode.LIGHT))) }
        tour.inEachMode(before = { tour.ui { IncomingFiles.waiting.clear(); IncomingFiles.waiting.add(Uri.fromFile(file)) } },
            content = { m -> tour.App(stores.getValue(m), "home", m) }) { m ->
            tour.waitFor("the import preview of a file from another app", hasText("Nothing is added", substring = true))
            tour.shot(36, "import-inbox", m)
        }
    }

    @Test fun r037_pictureFromPhoto() = appRoute(37, "picture-from-photo", "photo")

    @Test fun r038_editCards() {
        val store = tour.store()
        tour.inEachMode(content = { m -> tour.Page(m, cards) { CardsEditorScreen(store.first(StudySetKind.ANKI), store) {} } }) { m -> tour.shot(38, "cards-editor", m) }
    }

    @Test fun r039_editCard() {
        val store = tour.store()
        val deck = store.first(StudySetKind.ANKI)
        tour.inEachMode(content = { m ->
            tour.Page(m, cards) { CardsEditorScreen(deck, store) {} }
            tour.Over(m, cards) { CardEditSheet(deck.cards.first(), emptyList(), {}, {}) }
        }) { m -> tour.shot(39, "card-edit", m) }
    }

    @Test fun r039_editQuestion() {
        val store = tour.store()
        val set = store.first(StudySetKind.MCQ)
        tour.inEachMode(content = { m ->
            tour.Page(m, questions) { CardsEditorScreen(set, store) {} }
            tour.Over(m, questions) { QuestionEditSheet(set.questions.first(), emptyList(), {}, {}) }
        }) { m -> tour.shot(39, "question-edit", m) }
    }

    // MARK: questions, mock, plan

    @Test fun r042_quiz() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> val s = stores.getValue(m); tour.Page(m, questions) { QuizScreen(s.first(StudySetKind.MCQ), s, {}) } }) { m ->
            tour.shot(42, "quiz", m)
        }
    }

    @Test fun r043_quizChecked() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> val s = stores.getValue(m); tour.Page(m, questions) { QuizScreen(s.first(StudySetKind.MCQ), s, {}) } }) { m ->
            val q = stores.getValue(m).first(StudySetKind.MCQ).questions.first()
            tour.tap("the right answer's option", hasClickAction() and hasContentDescription(": " + q.options[q.correctIndex], substring = true))
            tour.tap("the quiz's check button", hasText(ChartQuiz.primaryTitle(false, true, false, false, false)) and hasClickAction())
            tour.waitFor("the checked answer's next button", hasText(ChartQuiz.primaryTitle(true, true, false, false, false)))
            tour.shot(43, "quiz-checked", m)
        }
    }

    @Test fun r044_timedPractice() {
        val stores = Mode.entries.associateWith { insightStore() }
        tour.inEachMode(content = { m ->
            val s = stores.getValue(m)
            val quiz = checkNotNull(CategoryFeature.TIMED.quiz(s)) { "Tour: the timed tile made no quiz" }
            tour.Page(m, questions) { QuizScreen(quiz.set, s, {}, keepsProgress = false, startsTimed = true) }
        }) { m -> tour.shot(44, "quiz-timed", m) }
    }

    @Test fun r046_quizResults() {
        val store = tour.store()
        val set = store.first(StudySetKind.MCQ)
        // two right, one wrong
        val answers = set.questions.mapIndexed { i, q -> MCQAnswer(if (i == 1) (q.correctIndex + 1) % q.options.size else q.correctIndex, true) }
        tour.inEachMode(content = { m -> tour.Page(m, questions) { QuizSummaryScreen(set, store, answers, {}, {}, {}) } }) { m -> tour.shot(46, "summary", m) }
    }

    /** The quiz with [sheet] over it, as its tools open it. */
    private fun overQuiz(row: Int, name: String, sheet: @androidx.compose.runtime.Composable () -> Unit) {
        val store = tour.store()
        tour.inEachMode(content = { m ->
            tour.Page(m, questions) { QuizScreen(store.first(StudySetKind.MCQ), store, {}) }
            tour.Over(m, questions) { sheet() }
        }) { m -> tour.shot(row, name, m) }
    }

    @Test fun r047_labValues() = overQuiz(47, "lab-values") { ExamToolSheets(ExamToolSheet.labs, ExamTrack.general) {} }

    @Test fun r048_calculator() = overQuiz(48, "calculator") { ExamToolSheets(ExamToolSheet.calculator, ExamTrack.general) {} }

    @Test fun r049_wardPocket() = overQuiz(49, "ward-pocket") { ExamSheet({}) { WardPocketScreen(ExamTrack.general, {}, {}) } }

    @Test fun r050_wardCalculator() {
        tour.inEachMode(content = { m -> tour.Page(m, questions) { WardPocketScreen(ExamTrack.general, {}, {}) } }) { m ->
            tour.tap("the anion gap calculator", hasText(WardCalc.anionGap.title, substring = true) and hasClickAction())
            tour.shot(50, "ward-calc", m)
        }
    }

    @Test fun r050_wardScore() {
        val score = WardScores.all.first()
        tour.inEachMode(content = { m -> tour.Page(m, questions) { WardPocketScreen(ExamTrack.general, {}, {}, start = WardPocketTab.scores) } }) { m ->
            tour.tap("the ${score.name} score", hasText(score.name, substring = true) and hasClickAction())
            tour.shot(50, "ward-score", m)
        }
    }

    @Test fun r053_mockPaper() = appRoute(53, "mock-paper", "mock", ::insightStore)

    @Test fun r054_mockTooFew() = appRoute(54, "mock-too-few", "mock")

    /** A two-part USMLE-style sitting over the examples' and InsightExamples' 19 questions. */
    private fun sitting(store: StudyStore): MockSitting {
        val picks = MockLibrary.mcqPicks(store.library)
        check(picks.size >= 19) { "Tour: the seeded library has ${picks.size} questions, not 19" }
        val paper = MockFormat.papers(ExamTrack.usmle).first()
        val parts = listOf(picks.take(10), picks.drop(10).take(9))
        val specs = paper.sections.take(2).mapIndexed { i, spec -> spec.copy(questions = parts[i].size, minutes = 15) }
        return MockSitting(paper.title, specs, parts, 19, ExamTrack.usmle, PassMark.typical(ExamTrack.usmle))
    }

    private fun wrong(pick: QuestionPick) = (pick.question.correctIndex + 1) % pick.question.options.size

    @Test fun r055_mockSitting() {
        val stores = Mode.entries.associateWith { insightStore() }
        tour.inEachMode(content = { m -> val s = stores.getValue(m); tour.Page(m, questions) { MockSittingScreen(sitting(s), s, null) {} } }) { m ->
            tour.shot(55, "mock-sitting", m)
        }
    }

    @Test fun r055_mockBreak() {
        val stores = Mode.entries.associateWith { insightStore() }
        tour.inEachMode(content = { m ->
            val s = stores.getValue(m)
            val sitting = sitting(s)
            // the first part handed in, the break before the second
            val saved = MockSittingSave(sitting.title, sitting.specs, sitting.picks.map { part -> part.map { it.question.id } }, sitting.wanted,
                sitting.track.rawValue, sitting.passMark, section = 1, current = 0,
                selected = sitting.picks.first().associate { it.question.id to it.question.correctIndex },
                orders = emptyMap(), flagged = emptySet(), struck = emptyMap(), highlights = emptyMap(), secondsLeft = null, onBreak = true,
                spent = emptyMap(), startedAt = System.currentTimeMillis() - 14 * 60_000L)
            tour.Page(m, questions) { MockSittingScreen(sitting, s, saved) {} }
        }) { m -> tour.shot(55, "mock-break", m) }
    }

    @Test fun r056_mockResults() {
        val store = insightStore()
        val sitting = sitting(store)
        val picks = sitting.picks.flatten()
        val selected = picks.mapIndexed { i, p -> p.question.id to (if (i % 3 == 2) wrong(p) else p.question.correctIndex) }.toMap()
        val marks = picks.mapIndexed { i, p -> MockMark(p.question.id, MockLibrary.subjectName(p.set), selected[p.question.id], i % 3 != 2, seconds = 50.0) }
        val result = MockResult(marks, sitting.passMark ?: PassMark.typical(sitting.track))
        tour.inEachMode(content = { m -> tour.Page(m, questions) { MockResultsScreen(result, sitting, selected, 26, store) {} } }) { m ->
            tour.shot(56, "mock-results", m)
        }
    }

    @Test fun r057_symptomBlocks() = learn(57, "symptom-blocks") { LearnRoute.SymptomBlocks }

    @Test fun r058_examPlan() = learn(58, "exam-plan", store = {
        tour.store().also { it.setExamDate(System.currentTimeMillis() + 45L * 86_400_000L) }
    }) { LearnRoute.ExamPlan }

    @Test fun r059_examKit() = learn(59, "exam-kit") { LearnRoute.ExamKit }

    /** Bedtime is always night (LearnSheet), so it is shot once. */
    @Test fun r060_bedtime() = learn(60, "bedtime", listOf(Mode.DARK), ::rhythmStore) { LearnRoute.Bedtime }

    @Test fun r061_morningCheck() = learn(61, "morning-check", store = ::rhythmStore) { LearnRoute.MorningCheck }

    @Test fun r062_question() = learn(62, "learn-question") { s -> LearnRoute.Question(s.first(StudySetKind.MCQ).questions.first().id) }

    @Test fun r062_questionGone() = learn(62, "learn-question-gone") { LearnRoute.Question("a-question-since-deleted") }

    @Test fun r063_examPicker() = appRoute(63, "exam-picker", "exam")

    @Test fun r064_examCard() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> tour.App(stores.getValue(m), "home", m) }) { m ->
            tour.scrollTo("home's exam card", hasTestTag("examDashboard"))
            tour.shot(64, "exam-card", m)
        }
    }

    // MARK: cards, textbook

    @Test fun r065_cardReview() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> val s = stores.getValue(m); tour.Page(m, cards) { AnkiReviewScreen(s.first(StudySetKind.ANKI), s, {}) } }) { m -> tour.shot(65, "anki", m) }
    }

    @Test fun r066_cardRevealed() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> val s = stores.getValue(m); tour.Page(m, cards) { AnkiReviewScreen(s.first(StudySetKind.ANKI), s, {}, startRevealed = true) } }) { m ->
            tour.shot(66, "anki-revealed", m)
        }
    }

    @Test fun r067_deckEmpty() {
        val store = tour.store()
        val empty = store.first(StudySetKind.ANKI).copy(cards = emptyList())
        tour.inEachMode(content = { m -> tour.Page(m, cards) { AnkiReviewScreen(empty, store, {}) } }) { m -> tour.shot(67, "anki-empty", m) }
    }

    @Test fun r067_deckDone() {
        // every card but the first already learned, and the first rated Easy here
        val stores = Mode.entries.associateWith { tour.store().also { s -> s.first(StudySetKind.ANKI).cards.drop(1).forEach { s.rateCard(it, AnkiRating.EASY) } } }
        tour.inEachMode(content = { m -> val s = stores.getValue(m); tour.Page(m, cards) { AnkiReviewScreen(s.first(StudySetKind.ANKI), s, {}, startRevealed = true) } }) { m ->
            tour.tap("the Easy rating", hasText(CardReview.title(AnkiRating.EASY), substring = true) and hasClickAction())
            tour.shot(67, "anki-done", m)
        }
    }

    @Test fun r067_deckNotDue() {
        val store = tour.store().also { s -> s.first(StudySetKind.ANKI).cards.forEach { s.rateCard(it, AnkiRating.EASY) } }
        tour.inEachMode(content = { m -> tour.Page(m, cards) { AnkiReviewScreen(store.first(StudySetKind.ANKI), store, {}) } }) { m -> tour.shot(67, "anki-not-due", m) }
    }

    @Test fun r069_dueCards() = appRoute(69, "due-today", "due")

    @Test fun r070_nothingDue() = appRoute(70, "due-none", "due", {
        tour.store().also { s -> s.library.filter { it.kind == StudySetKind.ANKI }.forEach { s.deleteSet(it.id) } }
    })

    @Test fun r071_textbook() {
        val store = tour.store()
        tour.inEachMode(content = { m -> tour.Page(m, section(StudySetKind.BOOK)) { BookReaderScreen(store.first(StudySetKind.BOOK), store, {}) } }) { m ->
            tour.waitFor("the textbook's Contents button", hasContentDescription("Contents"))
            tour.shot(71, "book", m)
        }
    }

    @Test fun r072_contents() {
        val store = tour.store()
        tour.inEachMode(content = { m -> tour.Page(m, section(StudySetKind.BOOK)) { BookReaderScreen(store.first(StudySetKind.BOOK), store, {}) } }) { m ->
            tour.tap("the textbook's Contents button", hasContentDescription("Contents") and hasClickAction())
            tour.shot(72, "book-contents", m)
        }
    }

    @Test fun r073_guessFirst() = learn(73, "guess-first") { s -> LearnRoute.Pretest(s.first(StudySetKind.BOOK).id) }

    /** The examples' textbook carrying its own pages as its lecture, as a set made from a lecture file does. */
    private fun withLecture(book: StudySet): StudySet =
        book.copy(sources = listOf(SourceDoc(name = book.name, pages = book.bookPages.mapIndexed { i, page -> SourcePage(i + 1, page) })))

    @Test fun r074_lecturePreview() {
        val store = tour.store()
        val book = withLecture(store.first(StudySetKind.BOOK)).also(store::updateSet)
        tour.inEachMode(content = { m ->
            tour.Page(m, section(StudySetKind.BOOK)) { BookReaderScreen(book, store, {}) }
            tour.Over(m, section(StudySetKind.BOOK)) { SourcePreviewSheet(book.sources.first(), book, 1) {} }
        }) { m -> tour.shot(74, "lecture-preview", m) }
    }

    // MARK: OSCE, cases

    private fun osce(row: Int, name: String, screen: @androidx.compose.runtime.Composable (StudySet, StudyStore) -> Unit) {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> val s = stores.getValue(m); tour.Page(m, section(StudySetKind.OSCE)) { screen(s.first(StudySetKind.OSCE), s) } }) { m ->
            tour.shot(row, name, m)
        }
    }

    @Test fun r082_osceStation() = osce(82, "osce") { set, s -> OsceReviewScreen(set, s, {}) }

    @Test fun r083_osceRevealed() = osce(83, "osce-revealed") { set, s -> OsceReviewScreen(set, s, {}, startRevealed = true) }

    @Test fun r084_osceComplete() = osce(84, "osce-complete") { set, s -> OsceReviewScreen(set, s, {}, startComplete = true, startMissed = listOf(1)) }

    private val caseSection get() = section(StudySetKind.CASES)

    @Test fun r088_caseList() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m -> val s = stores.getValue(m); tour.Page(m, caseSection) { CaseListScreen(s.first(StudySetKind.CASES), s, {}) } }) { m -> tour.shot(88, "cases", m) }
    }

    @Test fun r089_caseWard() {
        val stores = Mode.entries.associateWith { tour.store() }
        tour.inEachMode(content = { m ->
            val s = stores.getValue(m); val set = s.first(StudySetKind.CASES)
            tour.Page(m, caseSection) { CaseWardScreen(set.caseFiles.first(), set.id, s) {} }
        }) { m -> tour.shot(89, "case-ward", m) }
    }

    @Test fun r090_differential() {
        // the patient seen and one step taken, so the ward's Differential button shows
        val stores = Mode.entries.associateWith {
            tour.store().also { s -> val file = s.first(StudySetKind.CASES).caseFiles.first()
                CaseRunStore(s).save(CaseRun(caseID = file.id).also { run -> run.take(file.steps.first().id, file) }) }
        }
        tour.inEachMode(content = { m ->
            val s = stores.getValue(m); val set = s.first(StudySetKind.CASES)
            tour.Page(m, caseSection) { CaseWardScreen(set.caseFiles.first(), set.id, s) {} }
        }) { m ->
            tour.tap("the case's Differential button", SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Your ranked working diagnoses"))
            tour.shot(90, "case-differential", m)
        }
    }

    @Test fun r091_decision() {
        val store = tour.store()
        val file = store.first(StudySetKind.CASES).caseFiles.first()
        tour.inEachMode(content = { m -> tour.Page(m, caseSection) { CaseDecisionScreen(file, file.differentials.first().name, {}) {} } }) { m ->
            tour.shot(91, "case-decision", m)
        }
    }

    @Test fun r092_debrief() {
        val store = tour.store()
        val set = store.first(StudySetKind.CASES)
        val file = set.caseFiles.first()
        // a run that led with another diagnosis, came round to the right one, and chose the right next step
        val names = file.differentials.map { it.name }
        val run = CaseRun(caseID = file.id).also { run ->
            run.setLadder(names.filter { it != file.diagnosis.name }.take(2))
            file.steps.take(2).forEach { run.take(it.id, file) }
            run.setLadder(listOf(file.diagnosis.name) + names.filter { it != file.diagnosis.name }.take(2))
            file.steps.drop(2).take(2).forEach { run.take(it.id, file) }
            run.decide(CaseRun.Decision(file.diagnosis.name, file.nextStep.key), file)
        }
        tour.inEachMode(content = { m ->
            tour.Page(m, caseSection) { CaseDebriefScreen(file, set.id, run, store, file.patient.ageSex.ifEmpty { "Patient" }, {}, {}) }
        }) { m -> tour.shot(92, "case-debrief", m) }
    }

    // MARK: audio

    private val audio get() = section(StudySetKind.NARRATE)

    @Test fun r093_narratedLecture() {
        val store = tour.store()
        tour.inEachMode(content = { m -> tour.Page(m, audio) { NarrateReviewScreen(store.first(StudySetKind.NARRATE), store, {}) } }) { m -> tour.shot(93, "narrate", m) }
    }

    @Test fun r095_fixWord() {
        val store = tour.store()
        val lecture = store.first(StudySetKind.NARRATE)
        val words = lecture.narrateSegments[1].text.split(" ")
        val target = FixTarget(1, 5, words[5].trim(',', '.', ':', ';'))
        tour.inEachMode(content = { m ->
            tour.Page(m, audio) { NarrateReviewScreen(lecture, store, {}) }
            tour.Over(m, audio) { FixWordSheet(target, {}, {}) }
        }) { m -> tour.shot(95, "narrate-fixing", m) }
    }

    @Test fun r096_sections() {
        // the examples' textbook pasted in as a lecture: its headings make the sections
        val store = tour.store()
        val book = store.first(StudySetKind.BOOK)
        val lecture = parseStudySet(book.name, book.subject, StudySetKind.NARRATE, book.bookMarkdown).also(store::addSet)
        tour.inEachMode(content = { m -> tour.Page(m, audio) { NarrateReviewScreen(lecture, store, {}) } }) { m ->
            tour.tap("the lecture's Sections button", hasContentDescription("Sections, ", substring = true) and hasClickAction())
            tour.shot(96, "narrate-sections", m)
        }
    }

    @Test fun r097_nothingToRead() {
        val store = tour.store()
        val empty = store.first(StudySetKind.NARRATE).copy(narrateSegments = emptyList())
        tour.inEachMode(content = { m -> tour.Page(m, audio) { NarrateReviewScreen(empty, store, {}) } }) { m -> tour.shot(97, "narrate-empty", m) }
    }

    // MARK: ideas

    /** ScreenshotTest's four linked ideas, two of them in a folder when [folder]. */
    private fun ideasStore(folder: Boolean = false): StudyStore = tour.store().also { s ->
        val cardiology = NoteFolder(name = "Cardiology")
        val inFolder = if (folder) cardiology.id else null
        val heart = Note(title = "Heart failure", tags = listOf("cardio"), folderId = inFolder)
        val bnp = Note(title = "BNP", body = "Rises with ventricular stretch.", links = listOf(heart.id), tags = listOf("labs"))
        val edema = Note(title = "Pulmonary oedema", links = listOf(heart.id, bnp.id), tags = listOf("cardio"), folderId = inFolder)
        val diuretics = Note(title = "Loop diuretics", links = listOf(edema.id), tags = listOf("drugs"))
        s.replaceIdeas(listOf(heart, bnp, edema, diuretics), if (folder) listOf(cardiology) else emptyList())
    }

    /** Ideas' remembered view ("ideas" preferences), as ScreenshotTest sets it. */
    private fun ideasPrefs(block: android.content.SharedPreferences.Editor.() -> Unit) =
        tour.context.getSharedPreferences("ideas", android.content.Context.MODE_PRIVATE).edit().clear().apply(block).commit()

    private fun space() = ideasPrefs { putString("vignette.ideas.mode", "space") }

    private val spaceMap = hasContentDescription("Space of ideas: 4 notes", substring = true)

    /** Waits for the map's node, then lets its first frames draw. The tour shoots the map whether or not the GL surface has drawn yet. */
    private fun mapShown(what: String, matcher: SemanticsMatcher, timeoutMs: Long = 30_000) {
        tour.waitFor(what, matcher, timeoutMs)
        SystemClock.sleep(3_000)
    }

    private fun ideas(row: Int, name: String, store: () -> StudyStore = { ideasStore() }, steps: (Mode) -> Unit) {
        val stores = Mode.entries.associateWith { store() }
        tour.inEachMode(content = { m -> tour.App(stores.getValue(m), "ideas", m) }) { m -> steps(m); tour.shot(row, name, m) }
    }

    @Test fun r100_ideasList() = ideas(100, "ideas") { tour.waitFor("the idea Loop diuretics", hasText("Loop diuretics", substring = true)) }

    @Test fun r101_ideasEmpty() = ideas(101, "home-ideas", tour::store) {}

    @Test fun r101_ideasEmptyMap() { space(); ideas(101, "ideas-map-empty", tour::store) {} }

    @Test fun r102_board() {
        ideasPrefs { putString("vignette.ideas.mode", "board") }
        ideas(102, "ideas-board") { tour.waitFor("the idea Loop diuretics on the board", hasText("Loop diuretics", substring = true)) }
    }

    @Test fun r103_brainMap() { space(); ideas(103, "ideas-map") { mapShown("the Space map of 4 notes", spaceMap) } }

    @Test fun r104_millionDemo() {
        ideasPrefs { putString("vignette.ideas.mode", "space"); putString("vignette.space.theme", "performance"); putInt("vignette.space.perfDemo", 1_000_000) }
        ideas(104, "ideas-million", tour::store) {
            // building a million nodes and their octree takes a few seconds on a CI emulator
            tour.waitFor("the million-note demo's node count", hasText("1,000,000 nodes", substring = true), 120_000)
            SystemClock.sleep(6_000)
        }
    }

    @Test fun r105_legend() {
        space()
        ideas(105, "ideas-legend", { ideasStore(folder = true) }) {
            mapShown("the Space map of 4 notes", spaceMap)
            tour.tap("the map's Look tool", hasContentDescription("Look") and hasClickAction())
            tour.tap("the Look menu's legend", hasText(GraphTheme.SPACE.legendTitle) and hasClickAction())
        }
    }

    @Test fun r105_folderLooks() {
        space()
        ideas(105, "ideas-folder-looks", { ideasStore(folder = true) }) {
            mapShown("the Space map of 4 notes", spaceMap)
            tour.tap("the map's Look tool", hasContentDescription("Look") and hasClickAction())
            tour.tap("the Look menu's Folder looks", hasText("Folder looks") and hasClickAction())
        }
    }

    @Test fun r106_noteEditorAndLinkPicker() {
        val stores = Mode.entries.associateWith { ideasStore() }
        tour.inEachMode(content = { m -> tour.App(stores.getValue(m), "ideas", m) }) { m ->
            tour.tap("the idea Loop diuretics", hasText("Loop diuretics", substring = true) and hasClickAction())
            val link = hasContentDescription("Link to…") and hasClickAction()
            tour.waitFor("the note editor's Link to… button", link)
            tour.shot(106, "note-editor", m)
            tour.tap("the note editor's Link to… button", link)
            tour.shot(107, "link-picker", m)
        }
    }

    @Test fun r108_ideaName() {
        val stores = Mode.entries.associateWith { ideasStore(folder = true) }
        tour.inEachMode(content = { m ->
            tour.App(stores.getValue(m), "ideas", m)
            tour.Over(m, WardSection.ideas) { com.stethoscore.app.ui.ideas.NameSheet("New folder", "Folder name", "", "Create", {}) {} }
        }) { m -> tour.shot(108, "idea-name", m) }
    }

    @Test fun r108_ideaMove() {
        val stores = Mode.entries.associateWith { ideasStore(folder = true) }
        tour.inEachMode(content = { m ->
            val s = stores.getValue(m)
            tour.App(s, "ideas", m)
            tour.Over(m, WardSection.ideas) { MoveSheet(IdeaBook(s.notes, s.noteFolders), {}) {} }
        }) { m -> tour.shot(108, "idea-move", m) }
    }

    // MARK: vitals

    @Test fun r109_vitals() = appRoute(109, "vitals", "vitals", ::insightStore)

    @Test fun r110_vitalsEmpty() = appRoute(110, "vitals-empty", "vitals")

    @Test fun r111_insightQuestions() {
        val store = insightStore()
        val picks = StoreInsight.confidentMistakePicks(store)
        check(picks.isNotEmpty()) { "Tour: the seeded history has no confident mistakes" }
        tour.inEachMode(content = { m -> tour.Page(m, questions) { InsightQuestionList("Confident but wrong", VitalsNumbers.confidentTip, picks, store) {} } }) { m ->
            tour.shot(111, "insight-questions", m)
        }
    }

    @Test fun r112_insightQuiz() {
        val stores = Mode.entries.associateWith { insightStore() }
        tour.inEachMode(content = { m ->
            val s = stores.getValue(m)
            val quiz = InsightQuiz(insightQuiz("Cardiology", MockLibrary.mcqPicks(s.library) { it.set.subject == "Cardiology" }))
            tour.Page(m, questions) { InsightQuizScreen(quiz, s) {} }
        }) { m -> tour.shot(112, "insight-quiz", m) }
    }

    @Test fun r113_ruleSheet() {
        val store = insightStore()
        check(store.ruleSheet.isNotEmpty()) { "Tour: the seeded history has no rules" }
        tour.inEachMode(content = { m -> tour.Page(m, questions) { RuleSheetScreen(store) {} } }) { m -> tour.shot(113, "rules", m) }
    }

    @Test fun r114_syllabusCheck() {
        val store = insightStore()
        tour.inEachMode(content = { m -> tour.Page(m, questions) { CoverageScreen(store, {}) } }) { m -> tour.shot(114, "coverage", m) }
    }

    @Test fun r115_bySubject() = appRoute(115, "stats", "stats", ::insightStore)

    // MARK: settings, sources

    @Test fun r116_settings() = appRoute(116, "settings", "settings")

    @Test fun r117_aiModels() = appRoute(117, "ai-models", "models")

    @Test fun r120_lecturesEmpty() = appRoute(120, "lectures-empty", "sources")

    @Test fun r120_lectures() = appRoute(120, "lectures", "sources", {
        tour.store().also { s -> s.updateSet(withLecture(s.first(StudySetKind.BOOK))) }
    }) { tour.waitFor("a lecture's row", hasTestTag("source-row")) }

    @Test fun r121_setCredits() {
        val store = tour.store()
        tour.inEachMode(content = { m -> tour.Page(m, questions) { SetCreditsScreen(store.first(StudySetKind.MCQ), {}, {}) } }) { m -> tour.shot(121, "set-credits", m) }
    }

    @Test fun r122_licences() = appRoute(122, "licences", "licences")
}
