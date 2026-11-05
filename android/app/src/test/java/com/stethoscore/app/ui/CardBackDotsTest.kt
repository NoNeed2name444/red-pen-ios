package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import com.stethoscore.app.data.AnkiCard
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// A question card's back draws a dot beside each line of its answer, and TalkBack reads
// the line alone: the dot is drawn, not read, so it has no node of its own. On iOS the
// default-size audit flagged each such dot on the revealed card as an element of its own,
// 9 by 23 points, "Hit area is too small" (probe run 42024778055, T0203).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w360dp-h800dp")
class CardBackDotsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun theBackReadsItsLinesAndNotTheirDots() {
        val card = AnkiCard(front = "Four drug classes with mortality benefit in HFrEF?", bullets = listOf(
            "ACEi / ARB / ARNI", "Beta-blockers (bisoprolol, carvedilol, metoprolol succinate)",
            "MRA (spironolactone, eplerenone)", "SGLT2 inhibitors",
        ))
        compose.setContent { StethoscoreTheme { AnkiCardFace(card, images = emptyList(), revealed = true) } }
        // no dot, merged or not
        assertEquals("a dot in the merged tree", 0, compose.onAllNodesWithText("•").fetchSemanticsNodes().size)
        assertEquals("a dot of its own", 0, compose.onAllNodesWithText("•", useUnmergedTree = true).fetchSemanticsNodes().size)
        // and every line still there, read as it is
        for (line in card.bullets) compose.onNodeWithText(line).assertExists()
    }
}
