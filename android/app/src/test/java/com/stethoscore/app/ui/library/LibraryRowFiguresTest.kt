package com.stethoscore.app.ui.library

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiRating
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.ward.WardSection
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// A set row's two figures (the cards due, how far through the set) read every
// card of a deck. They were worked out while the row composed, on the main
// thread, for each visible row; now they come from Dispatchers.Default, as the
// search's index does, again when the revision or the set changes. The cards
// here report which thread reads them, and hold a reader that is not the main
// thread until the test lets it go, so the row's answer can be looked at while
// it is still being worked out.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LibraryRowFiguresTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val main: Thread = Looper.getMainLooper().thread

    /** A deck's cards that note the thread of each read of one, and hold any thread but the main one while [gate] is shut. */
    private inner class WatchedCards(private val cards: List<AnkiCard>) : AbstractList<AnkiCard>() {
        val readOn = CopyOnWriteArrayList<Thread>()
        @Volatile var gate: CountDownLatch? = null
        override val size: Int get() = cards.size
        override fun get(index: Int): AnkiCard {
            readOn += Thread.currentThread()
            val shut = gate
            if (shut != null && Thread.currentThread() !== main) shut.await(30, TimeUnit.SECONDS)
            return cards[index]
        }
        fun hold() { gate = CountDownLatch(1) }
        fun release() { gate?.countDown() }
    }

    private val watched = mutableListOf<WatchedCards>()
    @After fun letGo() { watched.forEach { it.release() } }

    private fun deck(name: String, cards: Int): Pair<StudySet, WatchedCards> {
        val list = WatchedCards(List(cards) { AnkiCard(id = "$name-$it", front = "front $it") }).also { watched += it }
        return StudySet(id = name, name = name, kind = StudySetKind.ANKI, cards = list) to list
    }

    private val actions = LibraryActions(open = {}, quiz = {}, review = {}, newSet = {}, shelf = {}, stats = {}, due = {}, ideas = {},
        exportPdf = {}, shareJson = {}, change = { it() })

    private fun store() = StudyStore(folder.newFolder())

    private fun show(set: () -> StudySet, store: StudyStore, revision: () -> Int) {
        compose.setContent {
            StethoscoreTheme(false, WardSection.cards) { LibraryRow(set(), store, revision(), LibraryState(), actions) }
        }
    }

    private fun exists(text: String) = compose.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty()

    private fun until(what: String, done: () -> Boolean) {
        compose.waitUntil(timeoutMillis = 20_000) { done() }
        assertTrue(what, done())
    }

    @Test fun theFiguresAreNotWorkedOutOnTheMainThread() {
        val (set, cards) = deck("heart", 3)
        show({ set }, store()) { 0 }
        until("the row shows its cards due") { exists("3 due") }
        assertTrue("the cards were read to work the figures out", cards.readOn.isNotEmpty())
        val onMain = cards.readOn.count { it === main }
        assertEquals("reads of the deck's cards on the main thread", 0, onMain)
    }

    @Test fun aRatingChangesTheFiguresAndTheRowUpdates() {
        val (set, cards) = deck("renal", 3)
        val store = store()
        val revision = mutableIntStateOf(0)
        show({ set }, store) { revision.intValue }
        until("three due, none begun") { exists("3 due") && exists("0%") }

        store.rateCard(cards[0], AnkiRating.EASY)
        compose.runOnIdle { revision.intValue++ }

        until("two due, a third begun") { exists("2 due") && exists("33%") }
        assertFalse("the old count is gone", exists("3 due"))
    }

    @Test fun aRowWithNoFiguresYetShowsNoneRatherThanAWrongOne() {
        val (set, cards) = deck("lung", 3)
        cards.hold()
        show({ set }, store()) { 0 }
        compose.waitForIdle()
        assertFalse("no cards due shown while they are counted", exists("3 due") || exists("0 due"))
        assertFalse("no progress shown while it is counted", exists("0%"))
        assertTrue("the row itself is there", exists("lung"))

        cards.release()
        until("the figures arrive") { exists("3 due") && exists("0%") }
    }

    @Test fun whileNewFiguresAreWorkedOutTheRowKeepsTheLastOnesForThatSet() {
        val (set, cards) = deck("gut", 3)
        val store = store()
        val revision = mutableIntStateOf(0)
        show({ set }, store) { revision.intValue }
        until("three due") { exists("3 due") }

        cards.hold()
        store.rateCard(cards[0], AnkiRating.EASY)
        compose.runOnIdle { revision.intValue++ }
        compose.waitForIdle()
        assertTrue("the last figure stays until the new one is ready", exists("3 due"))

        cards.release()
        until("the new figure replaces it") { exists("2 due") }
        assertFalse(exists("3 due"))
    }

    @Test fun figuresOfOneSetAreNeverShownOnAnother() {
        val (first, _) = deck("skin", 3)
        val (second, secondCards) = deck("bone", 5)
        val shown = mutableStateOf(first)
        show({ shown.value }, store()) { 0 }
        until("the first set's figure") { exists("3 due") }

        secondCards.hold()
        compose.runOnIdle { shown.value = second }
        compose.waitForIdle()
        assertTrue("the row now names the second set", exists("bone"))
        assertFalse("the first set's cards due are not shown on the second", exists("3 due"))
        assertFalse("nothing shown for the second until it is counted", exists("5 due"))

        secondCards.release()
        until("the second set's own figure") { exists("5 due") }
    }
}
