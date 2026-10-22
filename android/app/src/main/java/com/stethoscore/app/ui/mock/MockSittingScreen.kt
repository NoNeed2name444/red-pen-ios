package com.stethoscore.app.ui.mock

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.Coffee
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.HelpOutline
import androidx.compose.material.icons.rounded.HorizontalRule
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SportsScore
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.draw.clip
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.quiz.MockMark
import com.stethoscore.app.quiz.MockPacing
import com.stethoscore.app.quiz.MockRecord
import com.stethoscore.app.quiz.MockRecords
import com.stethoscore.app.quiz.MockResult
import com.stethoscore.app.quiz.MockSittingSave
import com.stethoscore.app.quiz.MockSittingStore
import com.stethoscore.app.quiz.OptionOrder
import com.stethoscore.app.quiz.PassMark
import com.stethoscore.app.ui.ExamToolMenuItems
import com.stethoscore.app.ui.ExamToolSheet
import com.stethoscore.app.ui.ExamToolSheets
import com.stethoscore.app.ui.HighlightableStem
import com.stethoscore.app.ui.WardOptionRow
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardEmptyState
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTimerPill
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardRelief
import kotlinx.coroutines.delay
import kotlin.math.abs

// Port of ios/RedPen/Features/Mock/MockSittingView.swift.
//
// A mock paper being sat: a strict clock per section, nothing said about
// right or wrong, flags and a grid to jump between questions, and the exam
// tools in More. When the last section closes, the results.

private fun letter(slot: Int): String = ('A' + minOf(slot, 25)).toString()

@Composable
fun MockSittingScreen(sitting: MockSitting, store: StudyStore, resumed: MockSittingSave?, onDone: () -> Unit) {
    key(sitting.id) { SittingBody(sitting, store, resumed, onDone) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SittingBody(sitting: MockSitting, store: StudyStore, resumed: MockSittingSave?, onDone: () -> Unit) {
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val broad = LocalConfiguration.current.screenWidthDp >= 600
    val file = remember { MockLibrary.sittingFile(context.filesDir) }

    // A new sitting, or one put back as it was left: the same questions,
    // option orders, answers, marks and the time that was left on the clock.
    val orders = remember {
        val made = HashMap(resumed?.orders ?: emptyMap())
        for (pick in sitting.picks.flatten()) if (made[pick.question.id] == null) {
            made[pick.question.id] = OptionOrder.make(pick.question.options.size, shuffle = true)
        }
        made.toMap()
    }
    var section by remember { mutableIntStateOf(resumed?.let { minOf(maxOf(0, it.section), maxOf(0, sitting.specs.size - 1)) } ?: 0) }
    var current by remember { mutableIntStateOf(maxOf(0, resumed?.current ?: 0)) }
    /** The option chosen for each question, as its own index (not the slot). */
    var selected by remember { mutableStateOf(resumed?.selected ?: emptyMap()) }
    var flagged by remember { mutableStateOf(resumed?.flagged ?: emptySet()) }
    var struck by remember { mutableStateOf(resumed?.struck ?: emptyMap()) }
    var highlights by remember { mutableStateOf(resumed?.highlights ?: emptyMap()) }
    var highlighting by remember { mutableStateOf(false) }
    var toolSheet by remember { mutableStateOf<ExamToolSheet?>(null) }
    var menuOpen by remember { mutableStateOf(false) }
    var sectionEndsAt by remember {
        mutableStateOf(resumed?.secondsLeft?.let { System.currentTimeMillis() + (maxOf(1.0, it) * 1000).toLong() })
    }
    /** Seconds each question has been on screen. */
    var spent by remember { mutableStateOf(resumed?.spent ?: emptyMap()) }
    var shownAt by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val startedAt = remember { resumed?.startedAt ?: System.currentTimeMillis() }
    /** Between two sections: the next one's clock waits for the student. */
    var onBreak by remember { mutableStateOf(resumed?.onBreak ?: false) }
    var showGrid by remember { mutableStateOf(false) }
    var confirmEnd by remember { mutableStateOf(false) }
    var confirmQuit by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<MockResult?>(null) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }

    val picks = sitting.picks.getOrElse(section) { emptyList() }
    val spec = sitting.specs[minOf(section, sitting.specs.size - 1)]
    val pick = picks.getOrNull(minOf(current, maxOf(0, picks.size - 1)))
    val isLastSection = section >= sitting.specs.size - 1

    /** The sitting as it stands, for MockSittingStore. */
    fun snapshot() = MockSittingSave(
        title = sitting.title, specs = sitting.specs, questionIds = sitting.picks.map { s -> s.map { it.question.id } },
        wanted = sitting.wanted, track = sitting.track.rawValue, passMark = sitting.passMark,
        section = section, current = current, selected = selected, orders = orders, flagged = flagged, struck = struck,
        highlights = highlights, secondsLeft = sectionEndsAt?.let { maxOf(0.0, (it - System.currentTimeMillis()) / 1000.0) },
        onBreak = onBreak, spent = spent, startedAt = startedAt)

    /** Kept after every change while the paper is open; never once it is marked. */
    fun persist() { if (result == null) MockSittingStore.save(snapshot(), file) }

    /** Adds the time on the question just left to its total. */
    fun noteTime() {
        val q = picks.getOrNull(current)?.question ?: return
        val t = System.currentTimeMillis()
        spent = spent + (q.id to (spent[q.id] ?: 0.0) + (t - shownAt) / 1000.0)
        shownAt = t
    }

    fun go(index: Int) {
        if (index !in picks.indices) return
        noteTime()
        current = index
    }

    fun startSection() {
        current = 0
        shownAt = System.currentTimeMillis()
        sectionEndsAt = System.currentTimeMillis() + spec.minutes * 60_000L
    }

    fun minutesUsed(): Int = Math.round((System.currentTimeMillis() - startedAt) / 60_000.0).toInt()

    /** Marks every question, records the answers given in the library's history, and keeps the sitting. */
    fun finish() {
        if (sectionEndsAt != null) noteTime()
        sectionEndsAt = null
        val marks = ArrayList<MockMark>()
        for (p in sitting.picks.flatten()) {
            val q = p.question
            val chosen = selected[q.id]
            val right = chosen == q.correctIndex
            marks.add(MockMark(q.id, MockLibrary.subjectName(p.set), chosen, right, q.id in flagged, spent[q.id] ?: 0.0))
            // an answer left blank says nothing about what the student knows
            if (chosen != null) store.recordAnswer(q.id, right, picked = chosen, saving = false)
        }
        store.save()
        val passMark = sitting.passMark ?: PassMark.typical(sitting.track)
        val made = MockResult(marks, passMark, sitting.penalty)
        MockRecords.record(MockRecord(title = sitting.title, track = sitting.track.rawValue, correct = made.correct, total = made.total,
            wanted = sitting.wanted, passMark = passMark, minutesUsed = minutesUsed(),
            score = if (made.penalty > 0) made.fraction else null), MockLibrary.recordsFile(context.filesDir))
        // marked and kept in the history: nothing left to resume
        MockSittingStore.clear(file)
        haptic.performHapticFeedback(HapticFeedbackType.Confirm)
        onBreak = false
        result = made
    }

    fun closeSection() {
        noteTime()
        sectionEndsAt = null
        showGrid = false
        if (isLastSection) finish() else {
            section += 1
            current = 0
            onBreak = true
        }
    }

    // a resumed sitting already has its clock, or is between sections
    LaunchedEffect(Unit) { if (sectionEndsAt == null && result == null && !onBreak) startSection() }
    // on disk after every answer, flag, move and section
    LaunchedEffect(section, current, selected, flagged, struck, highlights, onBreak, sectionEndsAt) { persist() }
    // and as the app leaves the screen: Android may end it in the background at any time
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val latestLeave by rememberUpdatedState({ if (sectionEndsAt != null) noteTime(); persist() })
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) latestLeave() }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    // the section closes when its time is up, answered or not
    val latestClose by rememberUpdatedState(::closeSection)
    LaunchedEffect(sectionEndsAt) {
        val ends = sectionEndsAt ?: return@LaunchedEffect
        while (true) {
            now = System.currentTimeMillis()
            if (now >= ends) break
            delay(minOf(1_000L, ends - now))
        }
        if (sectionEndsAt == ends) {
            haptic.performHapticFeedback(HapticFeedbackType.Reject)
            latestClose()
        }
    }

    val shownResult = result
    if (shownResult != null) {
        MockResultsScreen(shownResult, sitting, selected, remember { minutesUsed() }, store, onDone)
        return
    }

    BackHandler { confirmQuit = true }
    Column(Modifier.fillMaxSize()) {
        StudyTitleBar(sitting.title, null, leading = {
            WardButtonBox({ confirmQuit = true }, kind = WardButtonKind.compact) { Text("End") }
        }) {
            if (!onBreak) Box {
                WardCircleButton(Icons.Rounded.MoreHoriz, "More", { menuOpen = true })
                DropdownMenu(menuOpen, { menuOpen = false }, containerColor = wardColor(WardToken.raised)) {
                    ExamToolMenuItems(sitting.track, highlighting, onSheet = { menuOpen = false; toolSheet = it },
                        onHighlight = { menuOpen = false; highlighting = !highlighting })
                }
            }
        }
        when {
            onBreak -> {
                // the break between sections
                val next = spec
                Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                    ContentCard(Modifier.readableColumn().padding(16.dp)) {
                        FinishHero("Section closed", "${next.questions} questions in ${mockHours(next.minutes)}. Its clock starts when you do.") {
                            FinishSymbol(Icons.Rounded.Coffee)
                        }
                    }
                }
                StudyActionBar {
                    BigButton("Start ${next.title}", Icons.Rounded.PlayArrow, BigKind.primary, { onBreak = false; startSection() }, Modifier.fillMaxWidth())
                }
            }
            pick == null -> Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                WardEmptyState(Icons.Rounded.HelpOutline, "No questions", tone = WardTone.Grey)
            }
            else -> {
                val q = pick.question
                val order = OptionOrder.valid(orders[q.id], q.options.size)
                // the header: where in the section, how many answered, and the pace
                val answered = picks.count { selected[it.question.id] != null }
                val parts = ArrayList<String>()
                if (sitting.specs.size > 1) parts.add("${spec.title} of ${sitting.specs.size}")
                parts.add("$answered answered")
                val ends = sectionEndsAt
                if (ends != null) {
                    val elapsed = spec.minutes * 60.0 - (ends - now) / 1000.0
                    val target = MockPacing.target(elapsed, picks.size, spec.minutes)
                    if (target > 0) parts.add("aim: Q$target by now")
                }
                StudyProgressHeader("Question ${current + 1} of ${picks.size}", parts.joinToString(" · "),
                    current.toDouble() / maxOf(1, picks.size)) {
                    if (ends != null) {
                        // Resus Red for the last five minutes
                        val left = maxOf(0, Math.ceil((ends - now) / 1000.0).toInt())
                        WardTimerPill(left, Modifier.clearAndSetSemantics { contentDescription = "${left / 60} minutes left in this section" },
                            warnBelow = 301)
                    }
                }
                Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                    key(q.id) {
                        Column(Modifier.readableColumn().padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 24.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            QuestionCard(pick, q.id in flagged, onFlag = {
                                haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
                                flagged = if (q.id in flagged) flagged - q.id else flagged + q.id
                            }, marked = highlights[q.id] ?: emptySet(), onMarked = { highlights = highlights + (q.id to it) }, highlighting = highlighting)
                            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                q.options.indices.forEach { slot ->
                                    val orig = OptionOrder.original(slot, order)
                                    val text = orig?.let { q.options.getOrNull(it) } ?: ""
                                    val chosen = orig != null && selected[q.id] == orig
                                    val out = orig != null && orig in (struck[q.id] ?: emptySet())
                                    SittingOption(slot, text, chosen, out, onPick = {
                                        if (!out && orig != null) {
                                            haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
                                            selected = selected + (q.id to orig)
                                        }
                                    }, onStrike = {
                                        if (orig != null) {
                                            val set = struck[q.id] ?: emptySet()
                                            val on = orig in set
                                            struck = struck + (q.id to if (on) set - orig else set + orig)
                                            if (!on && selected[q.id] == orig) selected = selected - q.id
                                        }
                                    })
                                }
                            }
                        }
                    }
                }
                // the bar
                val last = current >= picks.size - 1
                StudyActionBar {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        BigButton("Back", Icons.Rounded.ChevronLeft, BigKind.companion, { go(current - 1) }, enabled = current > 0,
                            label = "Previous question")
                        BigButton("Review", Icons.Rounded.GridView, BigKind.companion, { showGrid = true })
                        BroadGap(broad)
                        BigButton(if (last) (if (isLastSection) "Finish paper" else "End ${spec.title}") else "Next",
                            if (last) Icons.Rounded.SportsScore else Icons.AutoMirrored.Rounded.ArrowForward, BigKind.primary,
                            { if (last) confirmEnd = true else go(current + 1) }, Modifier.weight(1f))
                    }
                }
            }
        }
    }

    if (showGrid) ModalBottomSheet(onDismissRequest = { showGrid = false }, containerColor = wardColor(WardToken.raised)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(spec.title, Modifier.weight(1f).semantics { heading() }, style = WardTextStyle.headline.textStyle(WardWeight.semibold),
                color = wardColor(WardToken.ink))
            WardButtonBox({ showGrid = false }, kind = WardButtonKind.compact) { Text("Done") }
        }
        LazyVerticalGrid(GridCells.Adaptive(52.dp), Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(picks.indices.toList()) { i ->
                val id = picks[i].question.id
                GridCell(i, selected[id] != null, id in flagged, i == current) { go(i); showGrid = false }
            }
        }
    }
    if (confirmEnd) {
        val open = picks.count { selected[it.question.id] == null }
        val marked = picks.count { it.question.id in flagged }
        val closing = if (isLastSection) "" else " A closed section can’t be reopened."
        ConfirmSheet(if (isLastSection) "Finish the paper?" else "Close ${spec.title}?", "$open unanswered, $marked flagged.$closing",
            listOf(ConfirmChoice(if (isLastSection) "Finish paper" else "Close ${spec.title}", true) { closeSection() }),
            "Keep going") { confirmEnd = false }
    }
    if (confirmQuit) ConfirmSheet("End the paper now?", "Unanswered questions count as wrong.", listOf(
        ConfirmChoice("End and see results", true) { finish() },
        ConfirmChoice("Leave without results", true) { MockSittingStore.clear(file); result = null; onDone() },
    ), "Cancel") { confirmQuit = false }
    ExamToolSheets(toolSheet, sitting.track) { toolSheet = null }
}

/** The question: "Pick the one best answer", its flag, the stem (highlightable) and its picture. */
@Composable private fun QuestionCard(pick: QuestionPick, on: Boolean, onFlag: () -> Unit, marked: Set<Int>, onMarked: (Set<Int>) -> Unit,
                                     highlighting: Boolean) {
    val q = pick.question
    ContentCard {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            WardSmallCapsText("Pick the one best answer", Modifier.weight(1f))
            ChipBox(on, onFlag, Modifier.semantics { contentDescription = if (on) "Remove flag" else "Flag for review" }, tone = WardTone.Warning) {
                Icon(if (on) Icons.Rounded.Flag else Icons.Outlined.Flag, null, Modifier.size(16.dp), tint = chipInk(on, WardTone.Warning))
                Text(if (on) "Flagged" else "Flag", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = chipInk(on, WardTone.Warning))
            }
        }
        HighlightableStem(q.stem, AnnotatedString(q.stem), marked, onMarked, highlighting,
            WardTextStyle.title3.textStyle(WardWeight.semibold).copy(color = wardColor(WardToken.ink), lineHeight = 28.sp))
        val image = remember(q.id) {
            val raw = q.imageIndex?.let { pick.set.images.getOrNull(it) } ?: return@remember null
            val body = if (raw.startsWith("data:") && raw.contains(',')) raw.substringAfter(',') else raw
            runCatching { Base64.decode(body, Base64.DEFAULT).let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }.getOrNull()
        }
        if (image != null) Image(image, null, Modifier.fillMaxWidth().heightIn(max = 220.dp).clip(RoundedCornerShape(12.dp)),
            contentScale = ContentScale.Fit)
    }
}

/**
 * One option as a Ward row (WardOptionRow): in the section's accent once
 * chosen, and nothing about right or wrong until the end. A long press
 * offers Cross out option or Restore option, and a sideways swipe of 70
 * points does the same (iOS strikeOutGestures).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable private fun SittingOption(slot: Int, text: String, chosen: Boolean, struck: Boolean, onPick: () -> Unit, onStrike: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val title = if (struck) "Restore option" else "Cross out option"
    val swipe = with(LocalDensity.current) { 70.dp.toPx() }
    Box {
        WardOptionRow(letter(slot), text, if (chosen) ChartQuiz.Mark.chosen else ChartQuiz.Mark.idle, struck, Modifier
            .combinedClickable(interactionSource = remember { MutableInteractionSource() }, indication = null,
                onLongClick = { menu = true }, onClick = onPick)
            .pointerInput(Unit) {
                var dx = 0f
                detectHorizontalDragGestures(onDragStart = { dx = 0f }, onDragEnd = { if (abs(dx) > swipe) onStrike() }) { _, amount -> dx += amount }
            }
            .semantics(mergeDescendants = true) {
                contentDescription = "Answer ${letter(slot)}: $text" + (if (struck) ", crossed out" else "")
                selected = chosen
                customActions = listOf(CustomAccessibilityAction(title) { onStrike(); true })
            })
        DropdownMenu(menu, { menu = false }, containerColor = wardColor(WardToken.raised)) {
            DropdownMenuItem(text = { Text(title) }, leadingIcon = { Icon(if (struck) Icons.AutoMirrored.Rounded.Undo else Icons.Rounded.HorizontalRule, null) },
                onClick = { menu = false; onStrike() })
        }
    }
}

/** A question in the grid: raised to be tapped; answered, pressed in, its number blue; flagged, an amber flag. */
@Composable private fun GridCell(i: Int, answered: Boolean, marked: Boolean, here: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(WardRadius.field.wardDp)
    val state = (if (answered) "answered" else "unanswered") + (if (marked) ", flagged" else "")
    Box(Modifier.clearAndSetSemantics { contentDescription = "Question ${i + 1}, $state" }
        .clickable(onClick = onClick), contentAlignment = Alignment.TopEnd) {
        Text("${i + 1}", Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp)
            .wardRelief(pressed = answered, radius = WardRadius.field, lift = WardLift.low)
            .border(2.dp, if (here) wardColor(WardToken.ink) else Color.Transparent, shape)
            .padding(vertical = 13.dp),
            style = WardTextStyle.body.textStyle(WardWeight.semibold, mono = true),
            color = if (answered) wardColor(WardToken.primaryInk) else wardColor(WardToken.ink), textAlign = TextAlign.Center)
        if (marked) Icon(Icons.Rounded.Flag, null, Modifier.padding(4.dp).size(11.dp), tint = wardColor(WardToken.warning))
    }
}
