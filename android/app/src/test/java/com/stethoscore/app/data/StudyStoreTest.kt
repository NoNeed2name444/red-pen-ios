package com.stethoscore.app.data

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class StudyStoreTest {
    @get:Rule val folder = TemporaryFolder()
    @Test fun freshStoreHasNoFabricatedProgress() {
        val store = StudyStore(folder.root)
        assertTrue(store.library.isEmpty()); assertTrue(store.answerHistory.isEmpty()); assertTrue(store.reviews.isEmpty())
        store.loadExamples()
        assertEquals(6, store.library.size); assertTrue(store.answerLog.isEmpty()); assertTrue(store.reviews.isEmpty())
        store.loadExamples(); assertEquals(6, store.library.size)
        assertEquals(2, store.library.first { it.kind == StudySetKind.CASES }.caseFiles.size)
        // the cases set says Example once, not "Example: Example patients"; the others keep the prefix
        assertEquals("Example patients", store.library.first { it.kind == StudySetKind.CASES }.name)
        assertTrue(store.library.all { it.name.startsWith("Example") && !it.name.startsWith("Example: Example") })
    }
    @Test fun importedDuplicatesReceiveIndependentItemIdentities() {
        val store = StudyStore(folder.root)
        val deck = StudySet(id = "deck", name = "Example", kind = StudySetKind.ANKI, cards = listOf(AnkiCard(id = "card", front = "Question", bullets = listOf("Answer"))))
        val json = StudyJson.encodeSet(deck).toString()
        store.importJson(json); store.importJson(json)
        val first = store.library[0]; val second = store.library[1]
        assertNotEquals(first.id, second.id); assertNotEquals(first.cards[0].id, second.cards[0].id)
        store.rateCard(first.cards[0], AnkiRating.EASY)
        assertEquals(0, store.dueCards(first).size); assertEquals(1, store.dueCards(second).size)
        val reopened = StudyStore(folder.root)
        assertEquals(1, reopened.reviews.size); assertEquals(0, reopened.dueCards(reopened.library[0]).size)
    }
    @Test fun unknownFieldsAndBothIOSDateFormatsRoundTrip() {
        val json = """{"kind":"mcq","name":"Future set","createdAt":0,"updatedAt":"2026-10-13T12:30:00Z","futureField":{"enabled":true},"questions":[{"stem":"Why?","options":["A","B"],"correctIndex":1,"futureScore":0.87,"differential":{"tiers":[1,2]}}]}"""
        val set = StudyJson.decodeSets(json).single()
        assertEquals(978307200000L, set.createdAt)
        assertEquals(1791894600000L, set.updatedAt)
        val roundtrip = StudyJson.encodeSet(set)
        assertTrue(roundtrip.getJSONObject("futureField").getBoolean("enabled"))
        assertEquals(0.87, roundtrip.getJSONArray("questions").getJSONObject(0).getDouble("futureScore"), 0.0)
        assertEquals(2, roundtrip.getJSONArray("questions").getJSONObject(0).getJSONObject("differential").getJSONArray("tiers").length())
    }
    @Test fun progressNotesAndAnswersSurviveRestart() {
        val store = StudyStore(folder.root)
        store.saveQuizProgress("set", QuizProgress(1, listOf(MCQAnswer(2, true)), listOf("q"), listOf(listOf(2, 0, 1))))
        store.recordAnswer("q", true); store.recordAnswer("q", false)
        store.saveReadingProgress("book", 3)
        store.saveOsceProgress("osce", OsceProgress(0, "Wash", 1, listOf(1)))
        store.saveCaseRun("set:case", """{"taken":["s1"],"finished":false}""")
        store.saveNote(Note(id = "n", title = "Review point", body = "Remember [[Physiology]]"))
        val restored = StudyStore(folder.root)
        assertEquals(listOf(true, false), restored.answerHistory["q"])
        assertEquals(listOf(2, 0, 1), restored.quizProgress["set"]?.optionOrders?.single())
        assertEquals(3, restored.readingProgress["book"]?.position)
        assertEquals(listOf(1), restored.osceProgress["osce"]?.missed)
        assertEquals("s1", JSONObject(restored.caseRuns.getValue("set:case")).getJSONArray("taken").getString(0))
        assertEquals("Remember [[Physiology]]", restored.notes.single().body)
    }
    @Test fun unreadableLibraryCannotBeOverwrittenByLaterActions() {
        val file = File(folder.root, "stethoscore.json")
        file.writeText("{unfinished")
        val store = StudyStore(folder.root)
        assertNotNull(store.loadError)
        assertThrows(IllegalStateException::class.java) { store.loadExamples() }
        assertEquals("{unfinished", file.readText())
    }
    @Test fun malformedImportDoesNotDestroyExistingLibrary() {
        val store = StudyStore(folder.root); store.loadExamples()
        assertThrows(Exception::class.java) { store.importJson("broken") }
        assertEquals(6, store.library.size)
        assertEquals(6, StudyStore(folder.root).library.size)
    }
    @Test fun futureModeSurvivesLibrarySave() {
        File(folder.root, "stethoscore.json").writeText("""{"library":[{"id":"future","kind":"new-mode","payload":[1,2,3]}]}""")
        val store = StudyStore(folder.root)
        store.saveNote(Note(title = "A note"))
        val stored = JSONObject(store.exportJson()).getJSONArray("library").getJSONObject(0)
        assertEquals("new-mode", stored.getString("kind")); assertEquals(3, stored.getJSONArray("payload").length())
    }
    @Test fun failedSaveLeavesMemoryMatchingDisk() {
        val store = StudyStore(folder.root)
        val deck = StudySet(id = "deck", name = "Kept", kind = StudySetKind.ANKI, cards = listOf(AnkiCard(id = "card", front = "Q", bullets = listOf("A"))))
        store.addSet(deck)
        // A directory where the temporary file goes makes every write fail, like a full disk.
        File(folder.root, "stethoscore.json.tmp").also { it.mkdir(); File(it, "keep").writeText("") }
        var reported: String? = null
        store.onSaveError = { reported = it }
        store.rateCard(deck.cards[0], AnkiRating.GOOD)
        assertNotNull(reported); assertTrue(store.reviews.isEmpty())
        assertThrows(IllegalStateException::class.java) { store.addSet(deck.copy(id = "other", name = "Lost")) }
        assertEquals(listOf("Kept"), store.library.map { it.name })
        assertEquals(listOf("Kept"), StudyStore(folder.root).library.map { it.name })
    }
    @Test fun unreadableLibraryIsNeverOverwritten() {
        File(folder.root, "stethoscore.json").writeText("{ truncated")
        val store = StudyStore(folder.root)
        assertNotNull(store.loadError)
        assertThrows(IllegalStateException::class.java) { store.loadExamples() }
        assertTrue(store.library.isEmpty())
        assertEquals("{ truncated", File(folder.root, "stethoscore.json").readText())
    }
    @Test fun fullBackupRestoresNotesReviewsAndProgress() {
        val source = StudyStore(folder.newFolder("source"))
        val deck = StudySet(id = "deck", name = "Deck", kind = StudySetKind.ANKI, cards = listOf(AnkiCard(id = "card", front = "Q", bullets = listOf("A"))))
        source.addSet(deck); source.rateCard(deck.cards[0], AnkiRating.EASY)
        source.saveNote(Note(id = "note", title = "Idea")); source.recordAnswer("q1", true); source.setExamDate(1_800_000_000_000L)
        val restored = StudyStore(folder.newFolder("restored"))
        assertEquals(1, restored.importJson(source.exportJson()))
        assertEquals(listOf("Idea"), restored.notes.map { it.title })
        assertNotNull(restored.reviews["card"]); assertEquals(listOf(true), restored.answerHistory["q1"])
        assertEquals(1_800_000_000_000L, restored.examDate)
        val reopened = StudyStore(folder.root.resolve("restored"))
        assertEquals(1, reopened.notes.size); assertEquals(1, reopened.reviews.size)
    }
}
