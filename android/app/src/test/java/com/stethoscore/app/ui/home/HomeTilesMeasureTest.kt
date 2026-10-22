package com.stethoscore.app.ui.home

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.StethoscoreApp
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The screenshots run 39646961250 crashed on home with the example sets
// ("Asking for intrinsic measurements of SubcomposeLayout layouts is not
// supported"): the tiles' row asks its tiles' intrinsic height and the
// Vitals tile's ThatFits was a SubcomposeLayout. Home with the examples, its
// tiles and the dock (whose row and slots ask intrinsics too) must measure,
// and the textbook flow of ScreenshotTest.textbook must reach the reader.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w412dp-h915dp")
class HomeTilesMeasureTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    @Test fun homeWithTheExamplesMeasuresAndOpensTheTextbook() {
        val store = StudyStore(folder.newFolder("home")).also { it.loadExamples() }
        val set = store.library.first { it.kind == StudySetKind.BOOK }
        compose.setContent { StethoscoreApp(store, forceDark = false) }
        compose.waitForIdle()
        compose.onNodeWithText("YOUR STUDY WARD").assertExists()
        // the tiles' row, side by side (not the accessibility sizes' column)
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasContentDescription("Opens Progress", substring = true))
        compose.onNode(hasContentDescription("Opens Progress", substring = true)).assertExists()
        compose.onNode(hasContentDescription("Opens Ideas", substring = true)).assertExists()
        compose.onNode(hasText("Cards") and hasClickAction()).performClick()
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText(set.name))
        // home's list runs on behind New set and the dock (T0112): bring the
        // row to the list's top, clear of them, before tapping it
        val list = compose.onNode(hasScrollToNodeAction())
        val rise = compose.onNodeWithText(set.name).fetchSemanticsNode().boundsInRoot.top - list.fetchSemanticsNode().boundsInRoot.top
        list.performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, rise) }
        compose.waitForIdle()
        compose.onNodeWithText(set.name).performClick()
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Contents").assertExists()
    }
}
