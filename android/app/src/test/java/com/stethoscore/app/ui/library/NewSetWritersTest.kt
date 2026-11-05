package com.stethoscore.app.ui.library

import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.filterToOne
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isEnabled
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.core.app.ActivityOptionsCompat
import com.stethoscore.app.data.CaseMaker
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.llm.FakeServer
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.editors.LocalLLMService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

// T0194: New set's From a lecture file reaches the cards and textbook writer
// (LectureWriterSection) and the station writer (OsceGenerateSection), as iOS
// NewSetView.material does (NewSetView.swift:625-634), with the draft in
// Check and edit above Save. The service is the public build's: no Pro, so
// each writer says the cloud's own reason and nothing is sent.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NewSetWritersTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    /** The public build: no owner key, so no Pro and no writer. */
    private val noPro = LLMService("", { null }, FakeServer.BASE, FakeServer { error("nothing is sent without a writer") })

    /** The system's file picker, answering at once with [uri]. */
    private class Picker(private val uri: Uri) : ActivityResultRegistry() {
        var launched = 0
        override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>, input: I, options: ActivityOptionsCompat?) {
            launched += 1
            dispatchResult(requestCode, uri)
        }
    }

    private fun open(store: StudyStore, startKind: StudySetKind = StudySetKind.MCQ, startStep: NewSetStep = NewSetStep.KIND,
                     picker: ActivityResultRegistry? = null, onSaved: () -> Unit = {}) {
        compose.setContent {
            CompositionLocalProvider(LocalLLMService provides noPro) {
                StethoscoreTheme {
                    if (picker == null) LibraryNewSetScreen(store, startKind, {}, onSaved, startStep = startStep)
                    else CompositionLocalProvider(LocalActivityResultRegistryOwner provides object : ActivityResultRegistryOwner {
                        override val activityResultRegistry: ActivityResultRegistry = picker
                    }) { LibraryNewSetScreen(store, startKind, {}, onSaved, startStep = startStep) }
                }
            }
        }
    }

    private fun until(done: () -> Boolean) {
        compose.waitUntil(timeoutMillis = 20_000) {
            if (!done()) compose.mainClock.advanceTimeBy(500)
            done()
        }
    }

    /** Taps a kind on step 1 and checks the lecture path is offered first and chosen, with the other two after it. */
    private fun chooseKindOnTheLecturePath(kind: StudySetKind) {
        compose.onNodeWithText(NewSetWords.plainName(kind)).performScrollTo().performClick()
        compose.onNodeWithText("Add your lecture").assertExists()
        compose.onNodeWithText(NewSetPath.LECTURE.title).assertIsSelected()
        compose.onNodeWithText(NewSetPath.TYPE.blurb).assertExists()
        compose.onNodeWithText(NewSetPath.IMPORT_FILE.title).assertExists()
    }

    private val noWriter: String get() = CaseMaker.noWriter(noPro.cloudBlocker)

    @Test fun thePathsPerKindFollowIos() {
        val all = listOf(NewSetPath.LECTURE, NewSetPath.TYPE, NewSetPath.IMPORT_FILE)
        // iOS paths(for:): every kind but Narrate and Cases offers all three, the lecture first
        for (kind in listOf(StudySetKind.MCQ, StudySetKind.ANKI, StudySetKind.BOOK, StudySetKind.OSCE)) assertEquals(kind.name, all, NewSetWords.paths(kind))
        assertEquals(listOf(NewSetPath.LECTURE, NewSetPath.IMPORT_FILE), NewSetWords.paths(StudySetKind.CASES))
        assertEquals(listOf(NewSetPath.TYPE, NewSetPath.IMPORT_FILE), NewSetWords.paths(StudySetKind.NARRATE))
        // + New set opens on the lecture; a category's Paste or import still on typing
        for (kind in listOf(StudySetKind.ANKI, StudySetKind.BOOK, StudySetKind.OSCE)) {
            assertEquals(NewSetPath.LECTURE, NewSetWords.startPath(kind, NewSetStep.KIND))
            assertEquals(NewSetPath.TYPE, NewSetWords.startPath(kind, NewSetStep.MATERIAL))
        }
        // a lecture section holds the subject itself, for every kind but Narrate (iOS usesWriter)
        assertTrue(NewSetWords.usesWriter(NewSetPath.LECTURE, StudySetKind.OSCE))
        assertFalse(NewSetWords.usesWriter(NewSetPath.TYPE, StudySetKind.ANKI))
        assertFalse(NewSetWords.usesWriter(NewSetPath.LECTURE, StudySetKind.NARRATE))
    }

    @Test fun theDockFloatsTheWriterUntilThereIsADraft() {
        val make = NewSetStep.MAKE
        val lecture = NewSetPath.LECTURE
        // iOS floatingID: the writer while there is nothing to save, then Save
        assertEquals("writer", NewSetWords.floatingID(make, lecture, StudySetKind.ANKI, showsCreate = true, hasDraft = false))
        assertEquals("writer", NewSetWords.floatingID(make, lecture, StudySetKind.BOOK, showsCreate = true, hasDraft = false))
        assertEquals("osce", NewSetWords.floatingID(make, lecture, StudySetKind.OSCE, showsCreate = true, hasDraft = false))
        assertEquals("create", NewSetWords.floatingID(make, lecture, StudySetKind.ANKI, showsCreate = true, hasDraft = true))
        assertEquals("create", NewSetWords.floatingID(make, lecture, StudySetKind.OSCE, showsCreate = true, hasDraft = true))
        // questions and patients keep their own writer's button, with nothing for Save to do
        assertEquals("mcq", NewSetWords.floatingID(make, lecture, StudySetKind.MCQ, showsCreate = false, hasDraft = false))
        assertEquals("cases", NewSetWords.floatingID(make, lecture, StudySetKind.CASES, showsCreate = false, hasDraft = false))
        // typing has no writer: Save; an import nothing; and nothing floats before step 3
        assertEquals("create", NewSetWords.floatingID(make, NewSetPath.TYPE, StudySetKind.ANKI, showsCreate = true, hasDraft = false))
        assertNull(NewSetWords.floatingID(make, NewSetPath.IMPORT_FILE, StudySetKind.ANKI, showsCreate = false, hasDraft = false))
        assertNull(NewSetWords.floatingID(NewSetStep.MATERIAL, lecture, StudySetKind.ANKI, showsCreate = true, hasDraft = true))
    }

    @Test fun cardsFromALectureReachTheirWriter() {
        open(StudyStore(folder.newFolder("cards")))
        chooseKindOnTheLecturePath(StudySetKind.ANKI)
        // step 2 is the writer's: a file, or notes pasted in
        compose.onNodeWithText("Choose a lecture file").assertExists()
        compose.onNode(hasSetTextAction() and hasContentDescription("Or paste your notes")).performScrollTo()
            .performTextInput("The malar rash of lupus spares the nasolabial folds. ".repeat(6))
        compose.onNodeWithText("Next").performClick()
        // step 3: the writer's card type, count and Make
        compose.onNodeWithText("Card type").assertExists()
        compose.onNodeWithText("How many cards").assertExists()
        compose.onAllNodesWithText("Make 12 cards").onFirst().performScrollTo().performClick()
        // no writer: the cloud's own reason, and nothing written on the phone
        compose.onNodeWithText(noWriter).assertExists()
        // the subject is the writer's More options; Save keeps none of its own
        assertEquals(1, compose.onAllNodesWithText("More options").fetchSemanticsNodes().size)
    }

    @Test fun aTextbookFromALectureReachesItsWriter() {
        open(StudyStore(folder.newFolder("book")))
        chooseKindOnTheLecturePath(StudySetKind.BOOK)
        compose.onNodeWithText("Choose a lecture file").assertExists()
        compose.onNode(hasSetTextAction() and hasContentDescription("Or paste your notes")).performScrollTo()
            .performTextInput("Heart failure presents with breathlessness, orthopnoea and ankle swelling. ".repeat(6))
        compose.onNodeWithText("Next").performClick()
        compose.onNodeWithText("How many pages").assertExists()
        compose.onNodeWithText("Card type").assertDoesNotExist()
        compose.onAllNodesWithText("Make 12 pages").onFirst().performScrollTo().performClick()
        compose.onNodeWithText(noWriter).assertExists()
        assertEquals(1, compose.onAllNodesWithText("More options").fetchSemanticsNodes().size)
    }

    /** A Word file of [paragraphs], as the station reader reads one. */
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

    @Test fun stationsFromALectureReachTheirWriter() {
        val lecture = docx("Knee examination.docx", listOf(
            "Introduce yourself, confirm the patient's name and date of birth, and explain the examination.",
            "Gain consent, wash your hands and expose both knees with the patient lying flat.",
            "Inspect from the end of the bed for swelling, scars, wasting of the quadriceps and deformity.",
            "Feel for warmth, an effusion with the patellar tap, and tenderness along the joint line.",
        ))
        val picker = Picker(Uri.fromFile(lecture))
        open(StudyStore(folder.newFolder("osce")), picker = picker)
        chooseKindOnTheLecturePath(StudySetKind.OSCE)
        // step 2 is only the file; the count and Make wait for step 3 (iOS step == .material)
        compose.onNodeWithText("How many stations").assertDoesNotExist()
        compose.onNodeWithText("Choose a skills lecture or mark sheet").performScrollTo().performClick()
        assertEquals(1, picker.launched)
        until { compose.onAllNodes(hasText("Choose a different file") and isEnabled()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Next").performClick()
        compose.onNodeWithText("Choose a different file").assertDoesNotExist()
        compose.onNodeWithText("How many stations").assertExists()
        compose.onAllNodesWithText("Make 3 stations").onFirst().performScrollTo().performClick()
        compose.onNodeWithText(noWriter).assertExists()
        assertEquals(1, compose.onAllNodesWithText("More options").fetchSemanticsNodes().size)
    }

    @Test fun stationsSayWhatIsMissingWithNoFile() {
        open(StudyStore(folder.newFolder("osce-empty")))
        chooseKindOnTheLecturePath(StudySetKind.OSCE)
        // the station section keeps its file to itself, so Next is open and step 3 says what is missing
        compose.onNodeWithText("Next").performClick()
        compose.onNodeWithText("Nothing to write from yet — go Back and add a file.").assertExists()
    }

    @Test fun aDraftOnTheLecturePathIsCheckedThenSaved() {
        val store = StudyStore(folder.newFolder("draft"))
        var saved = false
        // a draft already in (as a writer's lands, through onBodyText) is carried to the lecture path
        open(store, StudySetKind.ANKI, NewSetStep.MATERIAL, onSaved = { saved = true })
        compose.onNode(hasSetTextAction() and hasContentDescription("Type or paste")).performTextInput("Malar rash spares? | the nasolabial folds")
        compose.onAllNodesWithText(NewSetPath.LECTURE.title).filterToOne(isSelectable()).performScrollTo().performClick()
        compose.onAllNodesWithText(NewSetPath.LECTURE.title).filterToOne(isSelectable()).assertIsSelected()
        compose.onNodeWithText("Next").performClick()
        // step 3: the writer, then the draft to check and edit, then Save
        compose.onNode(hasSetTextAction() and hasContentDescription("Check and edit")).performScrollTo().assertExists()
        compose.onNode(hasSetTextAction() and hasContentDescription("Name")).performTextInput("Lupus")
        compose.onNodeWithText("1 card ready.").assertExists()
        compose.onAllNodesWithText(NewSetWords.saveTitle(StudySetKind.ANKI)).onFirst().performScrollTo().performClick()
        assertTrue(saved)
        val made = store.library.single { it.name == "Lupus" }
        assertEquals(StudySetKind.ANKI, made.kind)
        assertEquals(1, made.cards.size)
    }
}
