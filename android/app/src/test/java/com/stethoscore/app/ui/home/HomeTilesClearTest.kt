package com.stethoscore.app.ui.home

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.learn.LearnRouterClosed
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// T0211 A3: on the review's phone (run 42028140747, 411 x 914 dp) New set sat
// over the Brain map tile mid-sentence at the default text size. The tiles
// get the round card's room for the bar now: at rest the round gives up a bed
// (Plan has the whole day) and the tiles end barRoom above New set. Robolectric
// sets text shorter than the phone did (the tiles cleared 914 dp here even
// before), so the window is 790 dp tall, still not a short one: there the tiles
// ran 563-698 under New set from 654 before, and 490-625 once a bed came off.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w411dp-h790dp-xxhdpi")
class HomeTilesClearTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private val newSet = "New set. Make questions or cards from a lecture"

    @Test fun theTilesEndAboveNewSetAtTheDefaultSize() {
        val store = StudyStore(folder.newFolder("home")).also { it.loadExamples() }
        compose.setContent { StethoscoreApp(store, forceDark = false) }
        compose.waitForIdle()
        val brain = compose.onAllNodes(hasContentDescription("Brain map.", substring = true)).onFirst().getUnclippedBoundsInRoot()
        val vitals = compose.onAllNodes(hasContentDescription("Opens Progress", substring = true)).onFirst().getUnclippedBoundsInRoot()
        val bar = compose.onNodeWithContentDescription(newSet).getUnclippedBoundsInRoot()
        println("T0211 A3: brain map ${brain.top}..${brain.bottom}, vitals ${vitals.top}..${vitals.bottom}, New set from ${bar.top}")
        val line = bar.top.value - HomeFit.barRoom.toFloat()
        assertTrue("the Brain map tile (${brain.top}..${brain.bottom}) ends above New set's line ($line)", brain.bottom.value <= line)
        assertTrue("the Vitals tile (${vitals.top}..${vitals.bottom}) ends above New set's line ($line)", vitals.bottom.value <= line)
    }
}
