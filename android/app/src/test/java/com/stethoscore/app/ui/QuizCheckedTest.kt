package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.ui.ward.WardPaperFrame
import com.stethoscore.app.ui.ward.WardSection
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The tour's r043 (T0129): the examples' first question, its right answer picked and
// checked, shows Next question, in light and then dark in one composition, each mode
// with its own library, as TourTest.inEachMode shows them. On a phone the options and
// Check answer sit below the fold of the scrolling question (on the CI pixel_6 Check
// answer is under the How sure? bar), and a tap on a node out of view lands on whatever
// covers that spot, so each control is scrolled into view first, as a reader would
// (TourCapture.tapInView). Robolectric's default screen is short enough to show it.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class QuizCheckedTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private fun tapInView(matcher: SemanticsMatcher) {
        compose.onAllNodes(matcher).onFirst().performScrollTo().performClick()
        compose.waitForIdle()
    }

    @Test fun aCheckedAnswerShowsNextQuestionInLightAndDark() {
        val modes = listOf(false, true)
        val stores = modes.associateWith { StudyStore(folder.newFolder(if (it) "dark" else "light")).also { s -> s.loadExamples() } }
        val section = WardSection.fromKindRaw(StudySetKind.MCQ.rawValue)
        val dark = mutableStateOf<Boolean?>(null)
        compose.setContent {
            dark.value?.let { d ->
                key(d) {
                    val s = stores.getValue(d)
                    StethoscoreTheme(d, section) {
                        Box(Modifier.fillMaxSize()) {
                            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                                QuizScreen(s.library.first { it.kind == StudySetKind.MCQ }, s, {})
                            }
                            WardPaperFrame(Modifier.fillMaxSize())
                        }
                    }
                }
            }
        }
        for (d in modes) {
            val name = if (d) "dark" else "light"
            compose.runOnIdle { dark.value = d }
            compose.waitForIdle()
            val q = stores.getValue(d).library.first { it.kind == StudySetKind.MCQ }.questions.first()
            tapInView(hasClickAction() and hasContentDescription(": " + q.options[q.correctIndex], substring = true))
            val check = ChartQuiz.primaryTitle(false, true, false, false, false)
            assertTrue("$name: no $check after picking", compose.onAllNodes(hasText(check) and hasClickAction()).fetchSemanticsNodes().isNotEmpty())
            tapInView(hasText(check) and hasClickAction())
            val next = ChartQuiz.primaryTitle(true, true, false, false, false)
            assertTrue("$name: no $next after checking", compose.onAllNodes(hasText(next) and hasClickAction()).fetchSemanticsNodes().isNotEmpty())
        }
    }
}
