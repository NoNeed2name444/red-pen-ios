package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.click
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.BedPlan
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.editors.CardsEditorScreen
import com.stethoscore.app.ui.editors.CountField
import com.stethoscore.app.ui.editors.MoreOptions
import com.stethoscore.app.ui.editors.QuestionEditSheet
import com.stethoscore.app.ui.editors.TagChipsField
import com.stethoscore.app.ui.home.HomePlanButton
import com.stethoscore.app.ui.home.HomeRoundCard
import com.stethoscore.app.ui.ward.WardControlSize
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// T0217: the controls iOS's default-size audit found too small to hit (app build run
// 42142451702, AUDIT-NIL): home's Open plan, the library's search field and the study
// screens' More. T0228 adds the editors' controls an independent check found short the same way.
// Here each control's own bounds are at least 48 dp wide and 48 dp tall, and its touch area (the
// bounds Compose reaches to the least target) is at least 48 dp tall. Open plan at the standard
// sizes is the one exception: its own height is trimmed to the words by design, so only its width
// and its touch height are asserted there. The touch area's width is not asserted anywhere. The
// last three tests are not about size: at 390 dp wide they assert that Open plan's own node does
// not cross the bed under it and that a tap 1 dp inside each opens that control.
// Native graphics, so the words are measured as the device measures them, not by Robolectric's
// legacy text.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AuditHitAreaTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    // The control's own bounds, not its touch bounds: Compose reaches any clickable's touch bounds
    // to 48 dp, so those pass even for an 18 dp control and would prove nothing.
    private fun SemanticsNodeInteraction.assertTarget(name: String, ownHeight: Boolean = true) {
        val own = getUnclippedBoundsInRoot()
        val least = WardControlSize.target.dp
        assertTrue("$name is $least wide: ${own.width}", own.width >= least)
        if (ownHeight) assertTrue("$name is $least tall: ${own.height}", own.height >= least)
        val touch = fetchSemanticsNode().touchBoundsInRoot
        val tall = with(compose.density) { touch.height.toDp() }
        assertTrue("$name's touch area is $least tall: $tall", tall >= least)
    }

    // At the standard sizes the row is trimmed to the words' height in its row by design, so its own
    // height is not the target (the node reads 42 dp under native graphics); Compose reaches the
    // touch to 48 dp round the words, and the control is its words wide (81 dp). No floor is added
    // there, so this test has nothing of the app's to catch: it records the width and the reach.
    @Test fun openPlanIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { HomePlanButton(onPlan = {}) } }
        compose.onNodeWithText("Open plan").assertTarget("Open plan", ownHeight = false)
    }

    // At the accessibility sizes the row keeps its whole target's height, the words and 12 dp a side:
    // 54 dp at 1.65 and 59 dp at 2.0 under native graphics, with no floor in the app. With the
    // padding removed they read 30 and 35 dp and these two fail; that is what they catch.
    private fun openPlanAt(scale: Float) {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, scale)) {
                StethoscoreTheme { HomePlanButton(onPlan = {}) }
            }
        }
        compose.onNodeWithText("Open plan").assertTarget("Open plan at font scale $scale")
    }

    @Test fun openPlanIsA48DpTallWhereTheAccessibilitySizesBegin() = openPlanAt(1.65f)

    @Test fun openPlanIsA48DpTallAtFontScale2() = openPlanAt(2f)

    @Test fun theSearchFieldIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { HomeSearchRow("", {}, onSources = {}, onSettings = {}) } }
        compose.onNode(hasSetTextAction()).assertTarget("the search field")
    }

    @Test fun studyMoreIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { StudyMoreButton { } } }
        compose.onNodeWithContentDescription("More").assertTarget("More")
    }

    // T0228: the editors' controls. Each one's click sat on a node inside Material's
    // minimum-size wrapper, so the node was 26 dp (the tag's plus), 44 dp (the minus and the
    // circle) or the words' height (the count field), and only the layout and Compose's reach
    // round the node made it 48. The click now sits outside the wrapper and the drawn part
    // inside it, as WardCircleButton does (T0217). These pass for a control whose own node
    // covers the target: the tag's cross, More options.
    private fun tagsField() = compose.setContent { StethoscoreTheme { TagChipsField(listOf("renal"), onChange = {}) } }

    @Test fun theAddTagPlusIsA48DpTarget() {
        tagsField()
        compose.onNodeWithContentDescription("Add tag").assertTarget("Add tag, nothing typed")
        compose.onNodeWithContentDescription("Add a tag").performTextInput("liver")
        compose.onNodeWithContentDescription("Add tag").assertTarget("Add tag, a tag typed")
    }

    @Test fun aTagsCrossIsA48DpTarget() {
        tagsField()
        compose.onNodeWithContentDescription("Remove tag renal").assertTarget("Remove tag")
    }

    @Test fun anEditorRowsMinusIsA48DpTarget() {
        val set = StudySet(name = "Lupus", subject = "Rheumatology", kind = StudySetKind.ANKI,
            cards = listOf(AnkiCard(front = "Rash across the cheeks?")))
        val store = StudyStore(folder.newFolder("rows")).also { it.addSet(set) }
        compose.setContent { StethoscoreTheme { CardsEditorScreen(set, store) { } } }
        compose.onNodeWithText("Edit").performClick()
        compose.onAllNodesWithContentDescription("Delete")[0].assertTarget("a row's Delete")
    }

    private fun questionSheet() = compose.setContent {
        val question = MCQQuestion(stem = "Which antibody is specific for lupus?", options = listOf("Anti-dsDNA", "ANA", "Anti-histone"), correctIndex = 0)
        StethoscoreTheme { QuestionEditSheet(question, emptyList(), onCancel = {}) { } }
    }

    @Test fun anOptionsCircleIsA48DpTarget() {
        questionSheet()
        compose.onAllNodesWithContentDescription("Mark correct")[0].assertTarget("Mark correct")
    }

    @Test fun anOptionsMinusIsA48DpTarget() {
        questionSheet()
        compose.onAllNodesWithContentDescription("Delete option")[0].assertTarget("Delete option")
    }

    @Test fun theCountFieldIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { CountField("How many questions", 10, 3..50, { }) } }
        compose.onNode(hasSetTextAction()).assertTarget("the count field")
    }

    @Test fun moreOptionsIsA48DpTarget() {
        compose.setContent { StethoscoreTheme { MoreOptions("More options", expanded = false, onToggle = { }) { } } }
        compose.onNodeWithText("More options").assertTarget("More options")
    }

    // T0228: Open plan and the bed under it, at 390 dp wide where the heading is one line (the
    // test window is 320 dp, where it wraps to two and the numbers differ). At the standard size
    // Open plan's own node ends flush with the bed's top, and Compose's touch reach, 3 dp further,
    // runs into the bed, where the bed's own bounds win; so no tap goes to the wrong control.
    // These pin that: the own node does not cross the bed, and a tap 1 dp inside each opens that
    // control (the bed at both font scales; Open plan only at the standard size, where its own node
    // reaches the bed's top: at the accessibility sizes the card's gap lies between them).
    private fun bed() = BedPlan.Bed(1, BedPlan.Kind.DueCards(3), "Cardiology", "Due cards", "3 cards due", BedPlan.Status.due, 5)

    private fun planAndBedAt(scale: Float) {
        var opened = 0
        var planned = 0
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, scale)) {
                StethoscoreTheme { Box(Modifier.requiredWidth(390.dp)) { HomeRoundCard(listOf(bed()), null, { opened++ }, onPlan = { planned++ }) } }
            }
        }
        val plan = compose.onNodeWithText("Open plan").getUnclippedBoundsInRoot()
        val row = compose.onNodeWithContentDescription(bed().spoken).getUnclippedBoundsInRoot()
        assertTrue("Open plan's own node ends at ${plan.bottom}, the bed starts at ${row.top} (font scale $scale)", plan.bottom <= row.top)
        val x = plan.left + 10.dp
        compose.onRoot().performTouchInput { click(Offset(x.toPx(), (row.top + 1.dp).toPx())) }
        assertEquals("a tap 1 dp inside the bed opens the bed (font scale $scale)", 1, opened)
        assertEquals("and not the plan (font scale $scale)", 0, planned)
        if (scale == 1f) {
            compose.onRoot().performTouchInput { click(Offset(x.toPx(), (row.top - 1.dp).toPx())) }
            assertEquals("a tap 1 dp inside Open plan opens the plan", 1, planned)
            assertEquals("and not the bed", 1, opened)
        }
    }

    @Test fun openPlanAndTheBedUnderItEachTakeTheirOwnTaps() = planAndBedAt(1f)

    @Test fun openPlanAndTheBedUnderItEachTakeTheirOwnTapsAtFontScale165() = planAndBedAt(1.65f)

    @Test fun openPlanAndTheBedUnderItEachTakeTheirOwnTapsAtFontScale2() = planAndBedAt(2f)
}
