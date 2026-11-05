package com.stethoscore.app.ui.library

import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.runtime.Composable
import com.stethoscore.app.data.StudyStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// Home's list keeps each library item by a stable key, and tells its kinds
// apart (contentType), so a scrolled-off set row is reused only as a set row.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LibraryItemsTest {
    @get:Rule val folder = TemporaryFolder()

    /** Writes down each item's key and content type instead of composing it. */
    private class Recorder : LazyListScope {
        val items = mutableListOf<Pair<Any?, Any?>>()
        override fun item(key: Any?, contentType: Any?, content: @Composable LazyItemScope.() -> Unit) { items += key to contentType }
        override fun items(count: Int, key: ((Int) -> Any)?, contentType: (Int) -> Any?, itemContent: @Composable LazyItemScope.(Int) -> Unit) {
            for (i in 0 until count) items += key?.invoke(i) to contentType(i)
        }
    }

    private val actions = LibraryActions(open = {}, quiz = {}, review = {}, newSet = {}, shelf = {}, stats = {}, due = {}, ideas = {},
        exportPdf = {}, shareJson = {}, change = { it() })

    private fun listed(store: StudyStore, category: StudyCategory, query: String = ""): List<Pair<Any?, Any?>> =
        Recorder().apply { libraryItems(store, 0, category, query, LibrarySearchState(), LibraryState(), actions) }.items

    @Test fun setRowsHeadingsAndTilesEachHaveTheirKind() {
        val store = StudyStore(folder.newFolder("examples")).also { it.loadExamples() }
        val shown = listed(store, StudyCategory.QUESTIONS)
        val keys = shown.map { it.first }
        assertEquals("every key is given and used once", keys.size, keys.filterNotNull().toSet().size)
        val sets = shownSets(store, StudyCategory.QUESTIONS, searching = false, search = LibrarySearchState())
        assertTrue("the examples list question sets", sets.isNotEmpty())
        for (set in sets) assertEquals(set.name, LibraryContent.row, shown.first { it.first == "set-" + set.id }.second)
        assertEquals(LibraryContent.heading, shown.first { it.first == "sets-heading" }.second)
        assertEquals(LibraryContent.tile, shown.first { it.first == "build-session" }.second)
    }

    @Test fun theEmptyAndSearchingItemsHaveTheirKind() {
        val empty = listed(StudyStore(folder.newFolder("empty")), StudyCategory.QUESTIONS)
        assertEquals(LibraryContent.empty, empty.first { it.first == "library-empty" }.second)
        val store = StudyStore(folder.newFolder("search")).also { it.loadExamples() }
        val searching = listed(store, StudyCategory.QUESTIONS, query = "zzzz nothing matches")
        assertEquals(LibraryContent.chips, searching.first { it.first == "search-scope" }.second)
        assertEquals(LibraryContent.empty, searching.first { it.first == "no-results" }.second)
    }
}
