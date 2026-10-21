package com.stethoscore.app.ui.learn

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.HelpOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.QuizScreen
import com.stethoscore.app.ui.StethoscoreTheme
import com.stethoscore.app.ui.mock.MockPaperScreen
import com.stethoscore.app.ui.sources.ReaderDoneButton
import com.stethoscore.app.ui.sources.ReaderEmptyState
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.ward.WardSection
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.wardColor

// A port of ios/RedPen/Shared/Learn/LearnRouter.swift and
// Features/Learn/LearnRoutes.swift: one learning screen at a time, over the
// app in a sheet of its own with a Done button - from home's round, its
// Plan button or a set opened for the first time. A quiz or the mock paper
// started from one of them is pushed inside the sheet.

/** What the learning sheet can show. */
internal sealed class LearnRoute {
    data object ExamPlan : LearnRoute()
    data object ExamKit : LearnRoute()
    data object Bedtime : LearnRoute()
    data object MorningCheck : LearnRoute()
    data object SymptomBlocks : LearnRoute()
    data object MockPaper : LearnRoute()
    data class Question(val id: String) : LearnRoute()
    data class Quiz(val set: StudySet, val timed: Boolean = false) : LearnRoute()
    data class Pretest(val id: String) : LearnRoute()
}

/** A screen pushed inside the sheet (navigationDestination). */
internal sealed class LearnPush {
    data class Quiz(val set: StudySet) : LearnPush()
    data object Mock : LearnPush()
    data object RuleSheet : LearnPush()
}

/** Opens the learning screens (LearnRouter.shared). */
internal object LearnRouter {
    var route by mutableStateOf<LearnRoute?>(null)
        private set
    var pushed by mutableStateOf<LearnPush?>(null)
        private set
    /** Bumped whenever a pushed screen or the sheet closes, so what is shown is read again. */
    var version by mutableIntStateOf(0)
        private set

    fun open(next: LearnRoute) {
        pushed = null
        route = next
        version++
    }

    fun push(next: LearnPush?) {
        if (next != null) pushed = next
    }

    fun pop() {
        pushed = null
        version++
    }

    fun close() {
        pushed = null
        route = null
        version++
    }

    /** The section the sheet's screen wears, when one is open (null: the app's own). */
    fun section(store: StudyStore): WardSection? {
        val open = route ?: return null
        if (pushed != null) return mcq
        return when (open) {
            is LearnRoute.Quiz, is LearnRoute.Question, LearnRoute.MockPaper -> mcq
            is LearnRoute.Pretest -> store.library.firstOrNull { it.id == open.id }?.let { WardSection.fromKindRaw(it.kind.rawValue) }
            else -> WardSection.outside
        }
    }

    private val mcq: WardSection get() = WardSection.fromKindRaw(StudySetKind.MCQ.rawValue)
}

/**
 * The open learning screen, over everything, in its own navigation stack
 * with a Done button (LearnSheet). [onOpenSet] opens a set a quiz's results
 * just made; [section] is the look the sheet wears.
 */
@Composable internal fun LearnSheet(store: StudyStore, dark: Boolean, section: WardSection,
                                    onPreset: (com.stethoscore.app.exam.NewSetPreset) -> Unit = {}, onOpenSet: (StudySet) -> Unit) {
    val route = LearnRouter.route ?: return
    // the bedtime re-read is drawn dark whatever the phone's setting
    StethoscoreTheme(dark = dark || route == LearnRoute.Bedtime, section = section) {
        Box(Modifier.fillMaxSize().background(wardColor(WardToken.background))) {
            BackHandler { LearnRouter.close() }
            Screen(route, store, onPreset, onOpenSet)
            when (val pushed = LearnRouter.pushed) {
                is LearnPush.Quiz -> Box(Modifier.fillMaxSize().background(wardColor(WardToken.background))) {
                    BackHandler { LearnRouter.pop() }
                    QuizScreen(pushed.set, store, { LearnRouter.pop() }, onOpen = { LearnRouter.close(); onOpenSet(it) }, keepsProgress = false)
                }
                LearnPush.Mock -> Box(Modifier.fillMaxSize().background(wardColor(WardToken.background))) {
                    BackHandler { LearnRouter.pop() }
                    MockPaperScreen(store) { LearnRouter.pop() }
                }
                LearnPush.RuleSheet -> Box(Modifier.fillMaxSize().background(wardColor(WardToken.background))) {
                    BackHandler { LearnRouter.pop() }
                    com.stethoscore.app.ui.vitals.RuleSheetScreen(store) { LearnRouter.pop() }
                }
                null -> Unit
            }
        }
    }
}

@Composable private fun Screen(route: LearnRoute, store: StudyStore, onPreset: (com.stethoscore.app.exam.NewSetPreset) -> Unit, onOpenSet: (StudySet) -> Unit) {
    val done: () -> Unit = { LearnRouter.close() }
    when (route) {
        LearnRoute.ExamPlan -> Framed("Exam plan") { ExamPlanScreen(store, onPreset) }
        LearnRoute.ExamKit -> Framed("Exam-day kit") { ExamDayKitScreen() }
        LearnRoute.Bedtime -> Framed("") { BedtimeReviewScreen(store) }
        LearnRoute.MorningCheck -> Framed("") { MorningCheckScreen(store) }
        LearnRoute.SymptomBlocks -> Framed("Symptom blocks") { SymptomBlocksScreen(store) }
        // screens with a bar of their own: its back is the sheet's Done
        LearnRoute.MockPaper -> MockPaperScreen(store, done)
        is LearnRoute.Quiz -> QuizScreen(route.set, store, done, onOpen = { done(); onOpenSet(it) }, keepsProgress = false, startsTimed = route.timed)
        is LearnRoute.Question -> {
            val set = LearnLibrary.singleQuestionQuiz(store, route.id)
            if (set != null) QuizScreen(set, store, done, onOpen = { done(); onOpenSet(it) }, keepsProgress = false)
            else Framed("") {
                ReaderEmptyState(Icons.AutoMirrored.Rounded.HelpOutline, "That question has gone",
                    "It may have been deleted, or edited on another device.", modifier = Modifier.fillMaxSize())
            }
        }
        is LearnRoute.Pretest -> {
            val set = store.library.firstOrNull { it.id == route.id }
            Framed("Guess first") {
                if (set != null) GuessFirstScreen(set)
                else ReaderEmptyState(Icons.AutoMirrored.Rounded.HelpOutline, "That set has gone", modifier = Modifier.fillMaxSize())
            }
        }
    }
}

/** The sheet's bar: the title inline and Done at the leading end, the screen under it. */
@Composable private fun Framed(title: String, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        ReaderNavBar(title, leading = { ReaderDoneButton { LearnRouter.close() } })
        Box(Modifier.fillMaxWidth().weight(1f)) { content() }
    }
}

/** A row whose screen is not on Android yet says so, in the app's own alert. */
@Composable internal fun NotYetNotice(message: String?, onDismiss: () -> Unit) {
    if (message == null) return
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Library") }, text = { Text(message) },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } })
}
