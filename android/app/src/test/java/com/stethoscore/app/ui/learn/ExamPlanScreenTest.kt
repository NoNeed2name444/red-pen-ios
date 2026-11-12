package com.stethoscore.app.ui.learn

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.core.app.ApplicationProvider
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.exam.WardCalc
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.StethoscoreApp
import com.stethoscore.app.ui.ward.WardSpace
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

// T0229: three things on the exam plan that no test covered.
//
// The header over the exam card. iOS's plan (Features/Learn/ExamPlanView.swift)
// puts the card in a Section whose header reads "Your exam"; Android's stood
// with none. The words are read from iOS's source here, so a change to them
// there fails this test until Android's follow. The order proved is the
// header's own: under the phase hero, over the card, nearer the card than the
// gap between two sections. (iOS lists the card after Today and the ward round
// tile; Android lists it second. That is not tested, and not changed here.)
//
// A date that was already set, changed in the plan's card: the card's pill and
// home's header must follow the new date, not the first one.
// HomeHeaderAfterPlanTest has only the first date set. (The plan's own phase
// hero does not follow either date while the plan is open: ExamPlanScreen reads
// it once per LearnRouter.version. That fix is outside T0229's scope; plan.md.)
//
// The Clinical reference opened from the plan is given the store, so its
// Practise this opens New set on Make with the question writer, as it does
// from the quiz (StudyReachTest.theWardPocketsPractiseThisOpensTheWriter).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w411dp-h4000dp")
class ExamPlanScreenTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()
    @get:Rule val learnClosed = LearnRouterClosed()

    private val zone: ZoneId = ZoneId.systemDefault()
    private val openPlan = SemanticsMatcher("Open plan") {
        it.config.getOrElseNullable(SemanticsActions.OnClick) { null }?.label == "Opens the exam plan and forecast"
    }
    private val isHeading = SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading)

    private fun prefs() = ApplicationProvider.getApplicationContext<Context>().getSharedPreferences("appearance", Context.MODE_PRIVATE)

    @Before fun noExam() { prefs().edit().clear().commit() }

    private fun chooseExam() { prefs().edit().putString(ExamTrack.storageKey, ExamTrack.plab.rawValue).commit() }

    private fun home() {
        val store = StudyStore(folder.newFolder("home")).also { it.loadExamples(); it.setExamDate(null) }
        compose.setContent { StethoscoreApp(store, forceDark = false) }
        compose.waitForIdle()
    }

    private fun openThePlan() {
        compose.onAllNodes(openPlan).onFirst().performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        assertEquals(LearnRoute.ExamPlan, LearnRouter.route)
    }

    /** The plan's own Done: the one button of that name outside a dialog. */
    private fun closeThePlan() {
        compose.onNode(hasText("Done") and !hasAnyAncestor(isDialog())).performClick()
        compose.waitForIdle()
        assertEquals(null, LearnRouter.route)
    }

    private fun openThePicker() {
        compose.onNodeWithTag("examDashboardChange").performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("examPickerSave").assertExists()
    }

    /**
     * The picker's Exam date row; in the date dialog [date] (none: the date it
     * opens on, ninety days from now), then the dialog's Done. The picker keeps
     * the date as soon as it is set. A day of the dialog's grid is a button
     * whose text is the whole date, "Saturday, February 20, 2027".
     */
    private fun setTheDate(date: LocalDate? = null) {
        compose.onNodeWithText("Exam date").performScrollTo().performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        if (date != null) {
            val spoken = date.format(DateTimeFormatter.ofPattern("MMMM d, yyyy", Locale.US))
            compose.onNode(hasText(spoken, substring = true) and hasClickAction() and hasAnyAncestor(isDialog())).performClick()
            compose.waitForIdle()
        }
        compose.onNode(hasText("Done") and hasAnyAncestor(isDialog())).performClick()
        compose.waitForIdle()
        compose.onAllNodesWithText("Clear the date").assertCountEquals(1)
    }

    private fun savePicker() { compose.onNodeWithTag("examPickerSave").performClick(); compose.waitForIdle() }

    /** What the picker opens on with no date set: ninety days from now, as ExamPickerScreen's defaultDate. */
    private fun ninetyDaysOn(): LocalDate = Instant.ofEpochMilli(System.currentTimeMillis() + 90L * 86_400_000L).atZone(zone).toLocalDate()

    private class Dates(val first: Int, val second: Int)

    /**
     * With the exam chosen and no date: the first date is set in the plan's card
     * (the picker's own), then the card's Change exam sets another day of that
     * month. Returns the days to each, counted here by calendar day.
     */
    private fun setThenChangeTheDate(afterFirst: (daysToFirst: Int) -> Unit = {}): Dates {
        val today = LocalDate.now(zone)
        val first = ninetyDaysOn()
        openThePicker()
        setTheDate()
        savePicker()
        afterFirst(ChronoUnit.DAYS.between(today, first).toInt())
        val second = first.withDayOfMonth(if (first.dayOfMonth != 20) 20 else 21)
        openThePicker()
        setTheDate(second)
        savePicker()
        val dates = Dates(ChronoUnit.DAYS.between(today, first).toInt(), ChronoUnit.DAYS.between(today, second).toInt())
        assertTrue("the two dates differ (${dates.first}, ${dates.second})", dates.first != dates.second)
        return dates
    }

    // the header over the card

    /** The header's words as iOS's plan writes them: the Text in the header of the Section that holds ExamDashboardCard. */
    private fun iosHeader(): String {
        var root: File? = File(System.getProperty("user.dir")).absoluteFile
        while (root != null && !File(root, "ios/RedPen").exists()) root = root.parentFile
        val source = File(root ?: File("/"), "ios/RedPen/Features/Learn/ExamPlanView.swift")
        assertTrue("iOS's ExamPlanView is found at ${source.path}", source.exists())
        val found = Regex("""ExamDashboardCard\(\)\s*\}\s*header:\s*\{\s*Text\("([^"]+)"\)""").find(source.readText())
        return requireNotNull(found) { "iOS's plan has no header on the exam card's Section" }.groupValues[1]
    }

    /** The header is the section's small-caps heading in iOS's words, under the hero and directly over the card. */
    private fun assertTheCardHasIosHeaderAboveIt() {
        val words = iosHeader()
        assertEquals("iOS's header", "Your exam", words)
        // WardSmallCapsText sets a section's header in capitals, as a Form's headers are on iOS
        val header = compose.onNode(hasText(words.uppercase(Locale.getDefault())) and isHeading)
        val h = header.getUnclippedBoundsInRoot()
        val hero = compose.onNodeWithTag("planPhase").getUnclippedBoundsInRoot()
        val card = compose.onNodeWithTag("examDashboard").getUnclippedBoundsInRoot()
        val gap = card.top.value - h.bottom.value
        println("T0229 A4: hero ends ${hero.bottom.value}, header ${h.top.value} to ${h.bottom.value}, card from ${card.top.value}, header to card $gap dp")
        assertTrue("the header is under the phase hero", hero.bottom.value <= h.top.value)
        assertTrue("the header is over the card", h.bottom.value <= card.top.value)
        assertTrue("the header is nearer the card ($gap dp) than a section break (${WardSpace.section} dp)", gap < WardSpace.section.toFloat())
    }

    @Test fun theCardHasTheHeaderIosGivesItWithAnExamChosen() {
        chooseExam()
        home()
        openThePlan()
        compose.onAllNodesWithText("YOUR EXAM").assertCountEquals(1)
        assertTheCardHasIosHeaderAboveIt()
    }

    @Test fun theCardHasTheHeaderIosGivesItWithNoExamChosen() {
        home()
        openThePlan()
        compose.onAllNodesWithText("Which exam are you preparing for?").assertCountEquals(1)
        compose.onAllNodesWithText("YOUR EXAM").assertCountEquals(1)
        assertTheCardHasIosHeaderAboveIt()
    }

    // a date that was already set, changed

    // the Clinical reference opened from the plan

    @Test fun theClinicalReferenceOpenedFromThePlanOffersNewSetOnMake() {
        chooseExam()
        home()
        openThePlan()
        compose.onNodeWithText("Clinical reference").performScrollTo().performClick()
        compose.waitForIdle()
        compose.onNodeWithText(WardCalc.anionGap.title).performScrollTo().performClick()
        compose.waitForIdle()
        compose.onNode(hasContentDescription("Practise this", substring = true)).performScrollTo().performClick()
        compose.waitForIdle()
        // New set on Make with the question writer (LibraryNewSetScreen); without the store it is the plain New set, which has a Set name field
        assertTrue("Make 8 questions is offered", compose.onAllNodesWithText("Make 8 questions").fetchSemanticsNodes().isNotEmpty())
        compose.onAllNodesWithText("Set name").assertCountEquals(0)
    }

    @Test fun aChangedDateIsHomesHeaderOnceThePlanCloses() {
        chooseExam()
        home()
        openThePlan()
        val days = setThenChangeTheDate()
        closeThePlan()
        compose.onAllNodesWithText("PLAB 1 in ${days.second} days", substring = true).assertCountEquals(1)
        compose.onAllNodesWithText("PLAB 1 in ${days.first} days", substring = true).assertCountEquals(0)
    }

    @Test fun aChangedDateIsTheCardsPillInThePlan() {
        chooseExam()
        home()
        openThePlan()
        val days = setThenChangeTheDate()
        compose.onAllNodesWithContentDescription("${days.second} days to go").assertCountEquals(1)
        compose.onAllNodesWithContentDescription("${days.first} days to go").assertCountEquals(0)
    }
}
