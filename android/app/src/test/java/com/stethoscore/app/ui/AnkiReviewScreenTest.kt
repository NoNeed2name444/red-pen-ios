package com.stethoscore.app.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color
import com.stethoscore.app.ui.ward.WardToken
import kotlin.math.ceil
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.stethoscore.app.data.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

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
        // the meaning is no caption on the button (the owner, 22 Oct): TalkBack's click label
        compose.onNodeWithText("I got it").assertDoesNotExist()
        compose.onNodeWithContentDescription("Easy, back in", substring = true).performClick()
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
            compose.onNodeWithContentDescription("Easy, back in", substring = true).performClick()
        }
        compose.onNodeWithText("Done for now").assertExists()
        compose.onNodeWithText("You went through 2 cards. Next card back in 4 d.").assertExists()
        compose.onNodeWithText("Done").assertExists()
    }

    // the owner, 23 Oct (D6): Again, Hard, Good, Easy side by side in one row, each its word and
    // when the card comes back, at least 48 dp tall; what each means is TalkBack's, in one label.
    @Test fun theRatingsStandInOneRowOfWords() {
        val store = StudyStore(folder.newFolder("row"))
        val set = deck(store)
        compose.setContent { StethoscoreTheme { AnkiReviewScreen(set, store, onBack = {}) } }
        compose.onNodeWithText("Reveal").performClick()
        // a new card: 1 min, 5 min, 10 min, 4 d, the same faces iOS shows (ScheduleTests)
        val spoken = listOf("Again, back in 1 minute. I forgot it.", "Hard, back in 5 minutes. I just about got it.",
            "Good, back in 10 minutes. I got it.", "Easy, back in 4 days. Too easy.")
        val buttons = spoken.map { compose.onNodeWithContentDescription(it).getUnclippedBoundsInRoot() }
        val tops = buttons.map { it.top }.toSet()
        assertEquals("all four share one row", 1, tops.size)
        for (i in 1 until buttons.size) assertTrue("left to right, Again to Easy", buttons[i].left >= buttons[i - 1].right)
        buttons.forEach { assertTrue("48 dp tall: ${it.height}", it.height >= 48.dp) }
        compose.onAllNodesWithTag("ratingRow").assertCountEquals(1)
        for (caption in listOf("I forgot it", "I just about got it", "I got it", "Too easy", "back")) compose.onNodeWithText(caption).assertDoesNotExist()
        assertEquals(listOf(AnkiRating.entries.toList()), CardReview.ratingRows(large = false))
        assertEquals(AnkiRating.entries.map { listOf(it) }, CardReview.ratingRows(large = true))
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
            compose.onNodeWithContentDescription("Good, back in", substring = true).performClick()
        }
        // Good on a new card is the ten-minute step: back in this sitting
        compose.onNodeWithText("2 cards due").assertExists()
        compose.onNodeWithText("2 done").assertExists()
    }

    @Test fun anEmptyDueTodaySaysSo() {
        val store = StudyStore(folder.newFolder("empty"))
        compose.setContent { StethoscoreTheme { DueTodayScreen(store, onBack = {}) } }
        compose.onNodeWithText("Nothing due today").assertExists()
        compose.onNodeWithText("Open a deck to study ahead.").assertExists()
        // the header says it once, with no "0 done" and no empty detail line beside it
        val said = compose.onNodeWithText("No cards due").fetchSemanticsNode().config[SemanticsProperties.Text].map { it.text }
        assertEquals(listOf("No cards due"), said)
        compose.onNodeWithText("0 done").assertDoesNotExist()
    }

    // A rating's tone is its button's ring, drawn by the shared press face (iOS WardPressFace
    // edge): at a control edge's strength, and at full strength when the system asks for more
    // contrast, as iOS's ring is under Increase Contrast.
    @Test @GraphicsMode(GraphicsMode.Mode.NATIVE) @Config(qualifiers = "xhdpi")
    fun theRingFollowsHighContrast() {
        val high = mutableStateOf(false)
        var tone = Color.Unspecified
        var surface = Color.Unspecified
        val labels = AnkiRating.entries.associateWith { "in 4 d" }
        compose.setContent {
            StethoscoreTheme {
                tone = wardColor(WardToken.danger)
                surface = wardColor(WardToken.surface)
                CompositionLocalProvider(LocalRatingHighContrast provides high.value) { AnkiRatingBar(labels, onRate = {}) }
            }
        }
        val standard = ringPixel("Again")
        assertNotEquals("standard: the ring shows on the face", hex(surface), hex(standard))
        assertNotEquals("standard: the ring is at a control edge's strength, not full", hex(tone), hex(standard))
        high.value = true
        compose.waitForIdle()
        assertEquals("more contrast: the ring is the tone at full strength", hex(tone), hex(ringPixel("Again")))
    }

    // More contrast is Android's High contrast text (and, from API 34, Color contrast above Standard).
    @Test fun highContrastTextAsksForMoreContrast() {
        val context = compose.activity
        assertFalse("by default the rings are at a control edge's strength", ratingHighContrast(context))
        Settings.Secure.putInt(context.contentResolver, "high_text_contrast_enabled", 1)
        assertTrue("High contrast text draws them at full strength", ratingHighContrast(context))
    }

    /** The window drawn in software, read just inside the left edge of [word]'s button, halfway down. */
    private fun ringPixel(word: String): Color {
        val bounds = compose.onNodeWithContentDescription("$word, back in", substring = true).fetchSemanticsNode().boundsInWindow
        val root = compose.activity.window.decorView.rootView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        compose.runOnIdle { root.draw(Canvas(bitmap)) }
        // the ring is 1 dp (2 px here) inside the edge: this pixel lies wholly in it
        return Color(bitmap.getPixel(ceil(bounds.left).toInt(), bounds.center.y.toInt()))
    }

    private fun hex(c: Color): String = "%06X".format(
        ((c.red * 255 + 0.5f).toInt() shl 16) or ((c.green * 255 + 0.5f).toInt() shl 8) or (c.blue * 255 + 0.5f).toInt())
}
