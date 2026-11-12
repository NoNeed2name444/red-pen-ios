package com.stethoscore.app.ui.library

import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.runtime.Composable
import com.stethoscore.app.data.LibrarySearch
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

    private fun listed(
        store: StudyStore, category: StudyCategory, query: String = "",
        search: LibrarySearchState = LibrarySearchState(), state: LibraryState = LibraryState(),
    ): List<Pair<Any?, Any?>> =
        Recorder().apply { libraryItems(store, 0, category, query, search, state, actions) }.items

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

    private fun hit(n: Int) = LibrarySearch.Hit(LibrarySearch.Kind.QUESTION, "set-$n", "q$n", null, "a snippet $n", 0..1, "Set $n")

    @Test fun theTileSectionsAndTheSearchHitsEachHaveTheirKind() {
        val store = StudyStore(folder.newFolder("tiles")).also { it.loadExamples() }
        val everywhere = StudyCategory.entries.flatMap { category ->
            listed(store, category) + listed(store, category, state = LibraryState().apply { morePractise = true })
        }
        val tiles = everywhere.filter { (it.first as String).let { key -> key.startsWith("tiles-") && !key.startsWith("tiles-heading") } }
        assertTrue("the categories list tiles", tiles.isNotEmpty())
        for ((key, kind) in tiles) assertEquals("$key", LibraryContent.tiles, kind)
        for ((key, kind) in everywhere.filter { (it.first as String).startsWith("tiles-heading") }) assertEquals("$key", LibraryContent.heading, kind)
        assertEquals(LibraryContent.toggle, everywhere.first { it.first == "more-practise" }.second)

        val found = LibrarySearchState(LibrarySearch.Results("set", LibrarySearch.Scope.ALL, listOf("set-1"), List(3) { hit(it) }, more = true))
        val searching = listed(store, StudyCategory.QUESTIONS, query = "set", search = found)
        assertEquals(LibraryContent.heading, searching.first { it.first == "hits-heading" }.second)
        for (n in 0 until 3) assertEquals(LibraryContent.hit, searching.first { it.first == "hit-" + hit(n).id }.second)
        assertEquals(LibraryContent.note, searching.first { it.first == "hits-more" }.second)
        assertEquals(LibraryContent.tile, searching.first { it.first == "hits-session" }.second)
        val none = listed(store, StudyCategory.QUESTIONS, query = "set", state = LibraryState().apply { scope = LibrarySearch.Scope.NOTES })
        assertEquals(LibraryContent.empty, none.first { it.first == "hits-none" }.second)
    }

    @Test fun noItemTheLibraryListsIsWithoutAKind() {
        val store = StudyStore(folder.newFolder("every")).also { it.loadExamples() }
        val found = LibrarySearchState(LibrarySearch.Results("set", LibrarySearch.Scope.ALL, emptyList(), List(2) { hit(it) }, more = true))
        val shown = StudyCategory.entries.flatMap { category ->
            listed(store, category) + listed(store, category, query = "set", search = found) +
                listed(store, category, state = LibraryState().apply { morePractise = true })
        } + listed(StudyStore(folder.newFolder("blank")), StudyCategory.CARDS)
        assertTrue("items were listed", shown.size > 20)
        for ((key, kind) in shown) assertTrue("$key has a kind", kind != null)
    }
}
