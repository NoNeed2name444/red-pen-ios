package com.stethoscore.app.ui.mock

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.MockResult
import com.stethoscore.app.quiz.MockSubjectScore
import com.stethoscore.app.ui.QuizScreen
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.StudyActionBar
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardProgressBar
import com.stethoscore.app.ui.ward.WardSectionLabel
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.textStyle

// Port of ios/RedPen/Features/Mock/MockResultsView.swift.
//
// The end of a mock: the score against the exam's rough pass mark, marks by
// subject (weakest first), the pace, and every question with its answer -
// the feedback the paper held back. Not ported: the review prompt iOS asks
// for after a mock that went reasonably.

@Composable
fun MockResultsScreen(result: MockResult, sitting: MockSitting, selected: Map<String, Int>, minutesUsed: Int, store: StudyStore,
                      onDone: () -> Unit) {
    var practising by remember { mutableStateOf<StudySet?>(null) }
    var showAll by remember { mutableStateOf(false) }
    val broad = com.stethoscore.app.ui.ward.currentWindowShape().widthClass != com.stethoscore.app.ui.ward.WardWidthClass.compact

    val shownSet = practising
    if (shownSet != null) {
        BackHandler { practising = null }
        QuizScreen(shownSet, store, onBack = { practising = null }, keepsProgress = false)
        return
    }

    val percent = Math.round(result.fraction * 100).toInt()
    val mark = Math.round(result.passMark * 100).toInt()
    val side = if (result.passed) "Above" else "Below"
    val verdict = "$side the rough pass mark of about $mark%. Pass marks move from sitting to sitting, so read it as a guide."
    /** Every question sat, in paper order, with where it came from. */
    val allPicks = sitting.picks.flatten()
    val missed = allPicks.filter { selected[it.question.id] != it.question.correctIndex }

    BackHandler(onBack = onDone)
    Column(Modifier.fillMaxSize()) {
        StudyTitleBar(sitting.title, null)
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.readableColumn().padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)) {
                ContentCard {
                    FinishHero("${result.correct} of ${result.total} right", verdict) { ScoreRing(result.fraction, "$percent%", "score") }
                }
                if (result.total < sitting.wanted) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Rounded.Info, null, Modifier.size(18.dp), tint = wardColor(WardToken.inkSecondary))
                    Text("A shortened paper: ${result.total} of the real ${sitting.wanted} questions.",
                        style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
                // the facts
                ContentCard(spacing = 8.dp) {
                    val pace = Math.round(result.secondsPerQuestion).toInt()
                    FactRow("Unanswered", "${result.unanswered}", Icons.Rounded.RadioButtonUnchecked)
                    FactRow("Flagged", "${result.marks.count { it.flagged }}", Icons.Rounded.Flag)
                    FactRow("Time used", mockHours(maxOf(1, minutesUsed)), Icons.Rounded.Timer)
                    FactRow("Average per question", "$pace s", Icons.Rounded.Speed)
                }
                // by subject
                ContentCard {
                    WardSectionLabel("By subject, weakest first")
                    result.bySubject.forEach { SubjectRow(it) }
                }
                // every answer, explained
                val shown = if (showAll) allPicks else missed
                ContentCard {
                    WardSectionLabel(if (showAll) "Every question" else "The ones you missed") {
                        WardTextButton(if (showAll) "Missed only" else "Show all", { showAll = !showAll }, kind = WardButtonKind.quiet, fills = false)
                    }
                    if (shown.isEmpty()) Text("Nothing missed. Well done.", style = WardType.body.textStyle(), color = wardColor(WardToken.inkSecondary))
                    shown.forEach { ReviewRow(it, selected[it.question.id]) }
                }
            }
        }
        // it folds away (iOS MockResultsView studyBar(folds: true))
        StudyActionBar(folds = true) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (missed.isNotEmpty()) {
                    BigButton("Practise missed", Icons.Rounded.Replay, BigKind.companion, {
                        practising = MockLibrary.temporaryQuiz("Mock mistakes", "Mock mistakes", missed)
                    })
                    BroadGap(broad)
                }
                BigButton("Done", Icons.Rounded.Check, BigKind.primary, onDone, Modifier.weight(1f))
            }
        }
    }
}

@Composable private fun FactRow(title: String, value: String, icon: ImageVector) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, Modifier.size(20.dp), tint = wardColor(WardToken.primaryInk))
        Text(title, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
        Text(value, style = WardType.obs.textStyle(), color = wardColor(WardToken.inkSecondary))
    }
}

@Composable private fun SubjectRow(row: MockSubjectScore) {
    val share = Math.round(row.fraction * 100).toInt()
    Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(row.subject, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
            Text("${row.correct} of ${row.total} · $share%", style = WardTextStyle.subheadline.textStyle(mono = true),
                color = wardColor(WardToken.inkSecondary))
        }
        androidx.compose.foundation.layout.Box(Modifier.clearAndSetSemantics {}) { WardProgressBar(row.fraction, row.subject) }
    }
}

/** One question, folded: right or wrong and its stem; open, the answer, the student's, and why. */
@Composable private fun ReviewRow(pick: QuestionPick, chosen: Int?) {
    val q = pick.question
    val right = chosen == q.correctIndex
    val answer = q.options.getOrElse(q.correctIndex) { "" }
    val yours = chosen?.let { q.options.getOrNull(it) } ?: "No answer"
    var open by remember(q.id) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = WardControlSize.target.wardDp).clickable(role = Role.Button) { open = !open }
            .semantics(mergeDescendants = true) { stateDescription = if (open) "Expanded" else "Collapsed" },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(if (right) Icons.Rounded.CheckCircle else Icons.Rounded.Cancel, if (right) "Right" else "Wrong", Modifier.size(18.dp),
                tint = if (right) wardColor(WardToken.success) else wardColor(WardToken.danger))
            Text(q.stem, Modifier.weight(1f), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink),
                maxLines = 2, overflow = TextOverflow.Ellipsis)
            Icon(Icons.Rounded.ChevronRight, null, Modifier.rotate(if (open) 90f else 0f), tint = wardColor(WardToken.primaryInk))
        }
        if (open) Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(q.stem, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Rounded.CheckCircle, null, Modifier.size(18.dp), tint = wardColor(WardToken.success))
                Text("Answer: $answer", style = WardType.body.textStyle(), color = wardColor(WardToken.success))
            }
            if (!right) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Rounded.Cancel, null, Modifier.size(18.dp), tint = wardColor(WardToken.danger))
                Text("You: $yours", style = WardType.body.textStyle(), color = wardColor(WardToken.danger))
            }
            Text(q.explanation, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}
