package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import com.stethoscore.app.data.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// T0226, Android parity for iOS T0225: the card pages (one deck's review, Due today) start at their
// top again after every rating and every undo, also when the same card comes straight back after
// Again (its id does not change, so the card alone cannot be what resets the page).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)  // real text widths, so a long front still fills more than the screen
class AnkiReviewScrollTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val deckScreen: @Composable (StudyStore, StudySet) -> Unit = { store, set -> AnkiReviewScreen(set, store, onBack = {}) }
    private val dueScreen: @Composable (StudyStore, StudySet) -> Unit = { store, _ -> DueTodayScreen(store, onBack = {}) }

    // cards long enough, asked and answered, that the page scrolls on the test's small screen
    private fun open(
        name: String, cards: Int, screen: @Composable (StudyStore, StudySet) -> Unit,
        host: (@Composable () -> Unit) -> Unit = { compose.setContent(it) },
    ) {
        val store = StudyStore(folder.newFolder(name))
        val set = StudySet(name = "Lupus", subject = "Rheumatology", kind = StudySetKind.ANKI, cards = List(cards) { n ->
            AnkiCard(front = "Card ${n + 1}. " + "What is the long question? ".repeat(60), bullets = List(30) { "Answer line $it of the long answer" })
        })
        store.addSet(set)
        host { StethoscoreTheme { screen(store, set) } }
    }

    private val pageScroll = SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange)

    private fun scrolled(): Int = compose.onNode(pageScroll).fetchSemanticsNode()
        .config[SemanticsProperties.VerticalScrollAxisRange].value().toInt()

    private fun scrollDown() {
        compose.onNode(pageScroll).performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, 300f) }
        compose.waitForIdle()
        assertTrue("the page was scrolled down first: ${scrolled()}", scrolled() > 0)
    }

    private fun revealScrollAndRate(word: String) {
        compose.onNodeWithText("Reveal").performClick()
        scrollDown()
        compose.onNodeWithContentDescription("$word, back in", substring = true).performClick()
        compose.waitForIdle()
    }

    private fun sameCardAfterAgain(screen: @Composable (StudyStore, StudySet) -> Unit) {
        open("again", cards = 1, screen)
        revealScrollAndRate("Again")
        compose.onNodeWithText("Card 1.", substring = true).assertExists()
        compose.onNodeWithText("1 done").assertExists()
        assertEquals("the same card is back, at its top", 0, scrolled())
    }

    private fun nextCardAfterRating(screen: @Composable (StudyStore, StudySet) -> Unit) {
        open("next", cards = 2, screen)
        revealScrollAndRate("Easy")
        compose.onNodeWithText("Card 2.", substring = true).assertExists()
        assertEquals("the next card opens at its top", 0, scrolled())
    }

    private fun cardAfterUndo(screen: @Composable (StudyStore, StudySet) -> Unit) {
        open("undo", cards = 2, screen)
        compose.onNodeWithText("Reveal").performClick()
        compose.onNodeWithContentDescription("Easy, back in", substring = true).performClick()
        compose.onNodeWithText("Card 2.", substring = true).assertExists()
        scrollDown()
        compose.onNodeWithContentDescription("Undo last rating").performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Card 1.", substring = true).assertExists()
        assertEquals("the undone card opens at its top", 0, scrolled())
    }

    // Bury and Suspend (the More menu) change the card without a rating, so the counter alone is not the key
    private fun nextCardAfterMenu(item: String, screen: @Composable (StudyStore, StudySet) -> Unit) {
        open("menu", cards = 2, screen)
        scrollDown()
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText(item).performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Card 2.", substring = true).assertExists()
        assertEquals("the next card opens at its top", 0, scrolled())
    }

    // a turn (rotation or fold) keeps the page where it was: same card, same rating count
    private fun keepsItsPlaceThroughATurn(screen: @Composable (StudyStore, StudySet) -> Unit) {
        val restoration = StateRestorationTester(compose)
        open("turn", cards = 2, screen, host = { restoration.setContent(it) })
        scrollDown()
        restoration.emulateSavedInstanceStateRestore()
        compose.waitForIdle()
        compose.onNodeWithText("Card 1.", substring = true).assertExists()
        assertTrue("the page keeps its place through a turn: ${scrolled()}", scrolled() > 0)
    }

    @Test fun aDeckAtTheTopWhenTheSameCardComesBackAfterAgain() = sameCardAfterAgain(deckScreen)
    @Test fun aDeckAtTheTopOnTheNextCard() = nextCardAfterRating(deckScreen)
    @Test fun aDeckAtTheTopAfterUndo() = cardAfterUndo(deckScreen)
    @Test fun dueTodayAtTheTopWhenTheSameCardComesBackAfterAgain() = sameCardAfterAgain(dueScreen)
    @Test fun dueTodayAtTheTopOnTheNextCard() = nextCardAfterRating(dueScreen)
    @Test fun dueTodayAtTheTopAfterUndo() = cardAfterUndo(dueScreen)

    @Test fun aDeckAtTheTopAfterBury() = nextCardAfterMenu("Bury until tomorrow", deckScreen)
    @Test fun aDeckAtTheTopAfterSuspend() = nextCardAfterMenu("Suspend this card", deckScreen)
    @Test fun dueTodayAtTheTopAfterBury() = nextCardAfterMenu("Bury until tomorrow", dueScreen)
    @Test fun dueTodayAtTheTopAfterSuspend() = nextCardAfterMenu("Suspend this card", dueScreen)
    @Test fun aDeckKeepsItsPlaceThroughATurn() = keepsItsPlaceThroughATurn(deckScreen)
    @Test fun dueTodayKeepsItsPlaceThroughATurn() = keepsItsPlaceThroughATurn(dueScreen)
}
