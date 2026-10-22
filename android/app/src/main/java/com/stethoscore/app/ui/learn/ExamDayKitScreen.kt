package com.stethoscore.app.ui.learn

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.AltRoute
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.HourglassEmpty
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.ExamWeekPlanner
import com.stethoscore.app.data.LearnDefaults
import com.stethoscore.app.data.StudyStreak
import com.stethoscore.app.quiz.MockMarking
import com.stethoscore.app.ui.QuizPrefs
import com.stethoscore.app.ui.editors.EditorTextArea
import com.stethoscore.app.ui.sources.ReaderEtch
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.wardColor
import java.time.Instant
import java.time.ZoneId

// A port of ios/RedPen/Features/Learn/ExamDayKitView.swift: the
// exam-morning kit - pacing checkpoints for the student's paper, how to
// handle a hard question, what the evidence says about changing an answer,
// a checklist, and an optional two-minute worry box that is never kept.
// Nothing to learn on this screen, on purpose. The paper is the exam
// track's (QuizPrefs.track); Android has no chosen exam (ExamChoice) yet.

private val checklist = listOf(
    "Photo ID and your exam confirmation",
    "Directions and travel time, with a margin",
    "Water and something to eat at the break",
    "Anything your test centre allows (earplugs, glasses)",
    "Phone off and away before you go in",
)

private const val ticksKey = "learn.kit.ticks"
private const val ticksDayKey = "learn.kit.day"

@Composable internal fun ExamDayKitScreen() {
    val context = LocalContext.current
    val track = remember { QuizPrefs.track(context) }
    val paper = ExamWeekPlanner.paper(track)
    val defaults = LearnDefaults.shared
    var ticks by remember { mutableStateOf(readTicks(defaults)) }
    // the worry box: never saved or sent, and gone when the screen closes
    var worries by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        // ticks are for today only
        val today = StudyStreak.key(Instant.now(), ZoneId.systemDefault())
        if (defaults.string(ticksDayKey) != today) {
            defaults.set(ticksKey, "")
            defaults.set(ticksDayKey, today)
            ticks = emptySet()
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = WardSpace.m.wardDp),
        verticalArrangement = Arrangement.spacedBy(WardSpace.section.wardDp)) {
        ReaderFormSection("Pacing · ${paper.name}", paceNote(paper, track.secondsPerQuestion)) {
            Box(Modifier.wardRowTile()) { PacingTable(paper) }
        }
        ReaderFormSection("A question you can’t crack") {
            Tip(Icons.Rounded.Flag, "Flag it, pick your best answer now, and move on. Come back at the end with fresh eyes.")
            Tip(Icons.Rounded.AltRoute, "Rule out what you can. Two options left is a far better guess than five.")
            Tip(Icons.Rounded.HourglassEmpty, MockMarking.guessAdvice("Your exam", null, 5))
        }
        ReaderFormSection("Changing answers") {
            Tip(Icons.AutoMirrored.Rounded.Undo, "Changing an answer helps more often than it hurts in studies of medical exams — when you have a reason, such as a detail you misread. Without a reason, leave it.")
        }
        ReaderFormSection("Checklist") {
            checklist.forEachIndexed { index, text ->
                val done = index in ticks
                Row(Modifier.toggleable(done, role = Role.Checkbox) {
                    val next = if (done) ticks - index else ticks + index
                    ticks = next
                    defaults.set(ticksKey, next.sorted().joinToString(","))
                    defaults.set(ticksDayKey, StudyStreak.key(Instant.now(), ZoneId.systemDefault()))
                }.wardRowTile().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(if (done) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null, Modifier.size(24.dp),
                        tint = if (done) wardColor(WardToken.success) else wardColor(WardToken.inkSecondary))
                    Text(text, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                }
            }
        }
        ReaderFormSection("Optional: two minutes of worries",
            "Some students find that writing their worries down just before an exam frees their head for the paper; the evidence is mixed, so skip it if it isn’t for you. Nothing here is saved or sent, and it is gone when you close this screen.") {
            Box(Modifier.wardRowTile()) { EditorTextArea(worries, { worries = it }, minHeight = 120.dp, label = "Worry box") }
            if (worries.isNotEmpty()) Row(Modifier.clickable(role = Role.Button) { worries = "" }.wardRowTile().heightIn(min = 44.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Rounded.Delete, null, Modifier.size(20.dp), tint = wardColor(WardToken.primaryInk))
                Text("Clear it", style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk))
            }
        }
    }
}

private fun readTicks(defaults: LearnDefaults): Set<Int> =
    defaults.string(ticksKey).orEmpty().split(',').mapNotNull { it.toIntOrNull() }.toSet()

private fun paceNote(paper: ExamWeekPlanner.Paper, seconds: Int): String {
    if (paper.published) {
        val time = ExamWeekPlanner.clock(paper.minutes)
        return "${paper.questions} questions in $time. Glance at the clock at each checkpoint; ahead or a little behind is fine."
    }
    return "About a question every $seconds seconds. Check your own paper’s question count and time on your confirmation."
}

@Composable private fun Tip(icon: ImageVector, text: String) {
    Row(Modifier.wardRowTile().padding(vertical = 2.dp).semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, Modifier.size(24.dp), tint = wardColor(WardToken.primaryInk))
        Text(text, Modifier.weight(1f), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
    }
}

/** "By 1:00 be at Q60". */
@Composable private fun PacingTable(paper: ExamWeekPlanner.Paper) {
    val points = ExamWeekPlanner.checkpoints(paper)
    Column(Modifier.fillMaxWidth()) {
        points.forEachIndexed { i, point ->
            Row(Modifier.fillMaxWidth().heightIn(min = 36.dp).semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically) {
                Text("By " + ExamWeekPlanner.clock(point.minute), Modifier.weight(1f), style = WardType.obs.textStyle(),
                    color = wardColor(WardToken.ink))
                Text("Q${point.question}", style = WardTextStyle.body.textStyle(WardWeight.semibold, mono = true), color = wardColor(WardToken.ink))
            }
            if (i < points.lastIndex) ReaderEtch()
        }
    }
}
