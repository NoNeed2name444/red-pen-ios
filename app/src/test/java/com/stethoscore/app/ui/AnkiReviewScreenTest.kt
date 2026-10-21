package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.stethoscore.app.data.*
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The card review flow as iOS's AnkiReviewView and DueTodayView run it (dcb4745): the
// header's words, Reveal, the four ratings with their meanings, Undo, and the finishes.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AnkiReviewScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private fun deck(store: StudyStore): StudySet {
        val set = StudySet(name = "Lupus", subject = "Rheumatology", kind = StudySetKind.ANKI, cards = listOf(
            AnkiCard(front = "Rash across the cheeks?", bullets = listOf("**Malar** rash")),
            AnkiCard(type = AnkiCardType.CLOZE, clozeText = "Anti-{{c1::dsDNA}} is specific", why = "High specificity for SLE"),
        ))
        store.addSet(set)
        return set
    }

    @Test fun aDeckIsReviewedRatedUndoneAndFinished() {
        val store = StudyStore(folder.newFolder("deck"))
        val set = deck(store)
        compose.setContent { StethoscoreTheme { AnkiReviewScreen(set, store, onBack = {}) } }
        compose.onNodeWithText("Rheumatology").assertExists()
        compose.onNodeWithText("2 cards left").assertExists()
        compose.onNodeWithText("0 done").assertExists()
        compose.onNodeWithText("QUESTION").assertExists()
        compose.onNodeWithText("Reveal").performClick()
        compose.onNodeWithText("How well did you remember it?").assertExists()
        compose.onNodeWithText("I got it").assertExists()
        compose.onNodeWithContentDescription("Easy").performClick()
        compose.onNodeWithText("1 card left").assertExists()
        compose.onNodeWithText("1 done").assertExists()
        compose.onNodeWithText("FILL IN THE GAP").assertExists()
        compose.onNodeWithContentDescription("Anti-blank is specific").assertExists()
        compose.onNodeWithContentDescription("Undo last rating").performClick()
        compose.onNodeWithText("2 cards left").assertExists()
        compose.onNodeWithText("QUESTION").assertExists()
        assertEquals("the undone card is never rated again", 0, store.reviews.getValue(set.cards[0].id).reviews)
        repeat(2) {
            compose.onNodeWithText("Reveal").performClick()
            compose.onNodeWithContentDescription("Easy").performClick()
        }
        compose.onNodeWithText("Done for now").assertExists()
        compose.onNodeWithText("You went through 2 cards. Next card back in 4 d.").assertExists()
        compose.onNodeWithText("Done").assertExists()
    }

    @Test fun nothingDueOffersToStudyAhead() {
        val store = StudyStore(folder.newFolder("ahead"))
        val set = deck(store)
        set.cards.forEach { store.rateCard(it, AnkiRating.EASY) }
        compose.setContent { StethoscoreTheme { AnkiReviewScreen(set, store, onBack = {}) } }
        compose.onNodeWithText("Nothing to review").assertExists()
        compose.onNodeWithText("Study it anyway").performClick()
        compose.onNodeWithText("0 done · studying ahead").assertExists()
        compose.onNodeWithText("2 cards left").assertExists()
    }

    @Test fun dueTodayGathersEveryDeck() {
        val store = StudyStore(folder.newFolder("due"))
        deck(store)
        compose.setContent { StethoscoreTheme { DueTodayScreen(store, onBack = {}) } }
        compose.onNodeWithText("Due today").assertExists()
        compose.onNodeWithText("2 cards due").assertExists()
        compose.onNodeWithText("LUPUS").assertExists()
        repeat(2) {
            compose.onNodeWithText("Reveal").performClick()
            compose.onNodeWithContentDescription("Good").performClick()
        }
        // Good on a new card is the ten-minute step: back in this sitting
        compose.onNodeWithText("2 cards due").assertExists()
        compose.onNodeWithText("2 done").assertExists()
    }

    @Test fun anEmptyDueTodaySaysSo() {
        val store = StudyStore(folder.newFolder("empty"))
        compose.setContent { StethoscoreTheme { DueTodayScreen(store, onBack = {}) } }
        compose.onNodeWithText("Nothing due today").assertExists()
        compose.onNodeWithText("Come back when a card is ready, or open a deck and study ahead.").assertExists()
    }
}
