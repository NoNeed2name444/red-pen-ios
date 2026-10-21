package com.stethoscore.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.LibraryBooks
import androidx.compose.material.icons.automirrored.rounded.ListAlt
import androidx.compose.material.icons.automirrored.rounded.ShowChart
import androidx.compose.material.icons.automirrored.rounded.TrendingDown
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.CalendarToday
import androidx.compose.material.icons.rounded.CheckCircleOutline
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.GpsFixed
import androidx.compose.material.icons.rounded.HighlightOff
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.WarningAmber
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.BedPlan
import com.stethoscore.app.data.CoverageEngine
import com.stethoscore.app.data.CoverageStatus
import com.stethoscore.app.data.ExamWeekPlanner
import com.stethoscore.app.data.RhythmReading
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.data.Syllabus
import com.stethoscore.app.data.WardWords
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.PassMark
import com.stethoscore.app.ui.coverage.CoverageScreen
import com.stethoscore.app.ui.home.ExamCountdown
import com.stethoscore.app.ui.home.HomeRound
import com.stethoscore.app.ui.mock.BigButton
import com.stethoscore.app.ui.mock.BigKind
import com.stethoscore.app.ui.mock.MockLibrary
import com.stethoscore.app.ui.mock.StudyActionBar
import com.stethoscore.app.ui.mock.StudyTitleBar
import com.stethoscore.app.ui.mock.readableColumn
import com.stethoscore.app.ui.sources.ReaderEmptyState
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.vitals.CalibrationChart
import com.stethoscore.app.ui.vitals.ConsultCard
import com.stethoscore.app.ui.vitals.CoverageGaps
import com.stethoscore.app.ui.vitals.DailyChart
import com.stethoscore.app.ui.vitals.FocusAction
import com.stethoscore.app.ui.vitals.FocusGlyph
import com.stethoscore.app.ui.vitals.FocusItem
import com.stethoscore.app.ui.vitals.InsightQuestionList
import com.stethoscore.app.ui.vitals.InsightQuiz
import com.stethoscore.app.ui.vitals.InsightQuizScreen
import com.stethoscore.app.ui.vitals.ProgressRing
import com.stethoscore.app.ui.vitals.ReadinessCard
import com.stethoscore.app.ui.vitals.ReasonDonut
import com.stethoscore.app.ui.vitals.RhythmMonitor
import com.stethoscore.app.ui.vitals.RuleSheetScreen
import com.stethoscore.app.ui.vitals.SparkPoint
import com.stethoscore.app.ui.vitals.Sparkline
import com.stethoscore.app.ui.vitals.StoreInsight
import com.stethoscore.app.ui.vitals.StudyHeatmap
import com.stethoscore.app.ui.vitals.Trend
import com.stethoscore.app.ui.vitals.VitalsNumbers
import com.stethoscore.app.ui.vitals.VitalsRings
import com.stethoscore.app.ui.vitals.VitalsSnapshot
import com.stethoscore.app.ui.vitals.WeeklyChart
import com.stethoscore.app.ui.vitals.WrongAnswer
import com.stethoscore.app.ui.vitals.percentText
import com.stethoscore.app.ui.vitals.reasonIcon
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardInset
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

// A port of upstream/ios/RedPen/Features/Analytics/AnalyticsView.swift:
// Vitals - how the studying is going, as a ward reads a patient, and what to
// study next. It opens on the countdown to the exam and where the readiness
// estimate stands, the study rhythm on a dark monitor, four rings
// (readiness, accuracy, syllabus, today) and the subjects that need a
// consult (ui/vitals/VitalsParts.kt). Then a short ranked list of next
// steps, each a tap that starts the right thing, and the evidence: the
// readiness estimate, trends week by week, the mistakes, each subject, and
// the study habit. The numbers are ui/vitals/VitalsNumbers.kt; nothing new
// is stored. Not here: the "By subject" link (StatsView, the Library batch).

/** The pages this one pushes that are not quizzes. */
private sealed class VitalsRoute {
    object Due : VitalsRoute()
    object Coverage : VitalsRoute()
    object Rules : VitalsRoute()
    object Confident : VitalsRoute()
    data class Reason(val reason: com.stethoscore.app.quiz.MistakeReason) : VitalsRoute()
}

@Composable fun VitalsScreen(store: StudyStore, onBack: () -> Unit) {
    val context = LocalContext.current
    val track = remember { QuizPrefs.track(context) }
    var quiz by remember { mutableStateOf<InsightQuiz?>(null) }
    var route by remember { mutableStateOf<VitalsRoute?>(null) }
    // bumped on coming back from a pushed page, so the numbers are worked out again then rather than after every answer
    var revision by remember { mutableIntStateOf(0) }
    var gaps by remember { mutableStateOf<CoverageGaps?>(null) }
    var mistakeSubject by remember { mutableStateOf("") }

    // the same keyword check the Syllabus page runs, kept to its counts
    val edited = store.library.maxOfOrNull { it.updatedAt } ?: 0L
    LaunchedEffect(track, store.library.size, edited, revision) {
        val library = store.library
        val history = store.answerHistory
        val subtopics = withContext(Dispatchers.Default) { CoverageEngine.assess(library, history, Syllabus.areas(track)) }.flatMap { it.subtopics }
        val missing = subtopics.filter { it.status == CoverageStatus.notCovered }
        gaps = CoverageGaps(missing.size, subtopics.size, missing.firstOrNull()?.subtopic?.name,
            subtopics.count { it.status == CoverageStatus.covered }, subtopics.count { it.status == CoverageStatus.thin }, track)
    }

    fun back() { quiz = null; route = null; revision++ }
    quiz?.let { q ->
        BackHandler { back() }
        InsightQuizScreen(q, store, ::back)
        return
    }
    when (val r = route) {
        VitalsRoute.Due -> { BackHandler { back() }; DueTodayScreen(store, ::back); return }
        VitalsRoute.Coverage -> { CoverageScreen(store, ::back); return }
        VitalsRoute.Rules -> { RuleSheetScreen(store, ::back); return }
        VitalsRoute.Confident -> {
            InsightQuestionList("Confident but wrong", VitalsNumbers.confidentTip, StoreInsight.confidentMistakePicks(store), store, ::back); return
        }
        is VitalsRoute.Reason -> { InsightQuestionList(r.reason.title, VitalsNumbers.tip(r.reason), StoreInsight.picks(store, r.reason), store, ::back); return }
        null -> {}
    }
    BackHandler(onBack = onBack)

    val s = remember(revision, store.library, store.answerLog.size) { VitalsNumbers.snapshot(store, track) }
    val items = VitalsNumbers.focusItems(s, gaps)
    val spots = BedPlan.weakSpots(s.stats)
    val (target, fromExam) = remember(revision, store.library) { VitalsNumbers.dailyTarget(store) }

    fun startQuiz(set: StudySet, minReadSeconds: Int = 0, timed: Boolean = false) {
        if (set.questions.isEmpty()) return
        quiz = InsightQuiz(set, minReadSeconds, timed)
    }
    fun drill(subject: String) = startQuiz(HomeRound.drill(store, subject))
    fun fix(reason: com.stethoscore.app.quiz.MistakeReason) {
        when (reason) {
            com.stethoscore.app.quiz.MistakeReason.didntKnow -> startQuiz(StoreInsight.reasonQuiz(store, reason, "Practise these"))
            com.stethoscore.app.quiz.MistakeReason.misread -> startQuiz(StoreInsight.reasonQuiz(store, reason, "Slow reading drill"), minReadSeconds = 15)
            com.stethoscore.app.quiz.MistakeReason.outOfTime -> startQuiz(StoreInsight.timedDrill(store), timed = true)
            else -> route = VitalsRoute.Reason(reason)
        }
    }
    fun run(action: FocusAction) {
        when (action) {
            is FocusAction.Drill -> drill(action.subject)
            FocusAction.ConfidentQuiz -> startQuiz(StoreInsight.confidentMistakesQuiz(store))
            FocusAction.Due -> route = VitalsRoute.Due
            FocusAction.Coverage -> route = VitalsRoute.Coverage
            is FocusAction.Reason -> fix(action.reason)
        }
    }

    val scroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    val anchors = remember { mutableStateMapOf<String, Int>() }
    fun jump(anchor: String) { anchors[anchor]?.let { y -> scope.launch { scroll.animateScrollTo(y) } } }
    fun Modifier.anchor(name: String) = onGloballyPositioned { anchors[name] = it.positionInParent().y.toInt() }

    Column(Modifier.fillMaxSize()) {
        StudyTitleBar("Vitals", onBack)
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(scroll), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.readableColumn().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                VitalsLine(s, store)
                Box(Modifier.padding(horizontal = WardSpace.s.wardDp)) {
                    RhythmMonitor(RhythmReading.read(s.dayCounts, Instant.now(), ZoneId.systemDefault()), s.readiness?.center,
                        s.monthAccuracy, s.today, target, s.streak)
                }
                ReaderFormSection(footer = VitalsNumbers.ringsNote(fromExam)) {
                    Box(Modifier.padding(horizontal = WardSpace.s.wardDp, vertical = WardSpace.s.wardDp)) {
                        VitalsRings(s.readiness, s.monthAccuracy, s.lastMonthAnswered, VitalsNumbers.syllabusShare(gaps), VitalsNumbers.syllabusSpoken(gaps),
                            s.today, target, onReadiness = { jump("readiness") }, onAccuracy = { jump("subjects") },
                            onSyllabus = { route = VitalsRoute.Coverage }, onToday = { route = VitalsRoute.Due })
                    }
                }
                Box(Modifier.padding(horizontal = WardSpace.s.wardDp)) {
                    val judged = s.stats.any { it.answered >= BedPlan.consultAnswers }
                    val phase = ExamWeekPlanner.phase(store.examDate?.let { Instant.ofEpochMilli(it) }, Instant.now(), ZoneId.systemDefault())
                    ConsultCard(spots, BedPlan.consultNote(spots, phase, judged), ::drill)
                }
                if (s.includesExamples) ReaderFormSection {
                    Row(Modifier.fillMaxWidth().wardRowTile(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Info, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
                        Text("Includes example data", style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
                    }
                }
                FocusSection(items, s.sparks) { run(it) }
                Box(Modifier.anchor("readiness")) {
                    ReaderFormSection(header = "Readiness") {
                        Box(Modifier.fillMaxWidth().wardRowTile()) {
                            ReadinessCard(s.readiness, s.recentCount, s.includesExamples, track, ::drill)
                        }
                    }
                }
                TrendsSection(s, PassMark.typical(track) * 100)
                MistakesSection(s, store, mistakeSubject, { mistakeSubject = it },
                    onConfident = { route = VitalsRoute.Confident }, onRules = { route = VitalsRoute.Rules },
                    onOne = { pick -> startQuiz(MockLibrary.temporaryQuiz("One question", MockLibrary.subjectName(pick.set), listOf(pick))) })
                Box(Modifier.anchor("subjects")) { SubjectsSection(s, ::drill) }
                TimeSection(s)
            }
        }
        // one main button at a time: Treat weak spots now, in the consult card, while any subject needs one;
        // otherwise the best next step, under the thumb, once there is one
        val top = items.firstOrNull()
        if (spots.isEmpty() && top != null) StudyActionBar {
            BigButton("Start: " + top.title, focusIcon(top), BigKind.primary, { run(top.action) })
        }
    }
}

/** "Finals in 23 days · on track for a pass", when there is an exam date. */
@Composable private fun VitalsLine(s: VitalsSnapshot, store: StudyStore) {
    val standing = s.readiness?.let { WardWords.standing(it.low, it.high, it.passMark) }
    val line = WardWords.vitalsLine(ExamCountdown.text(store.examDate), standing) ?: return
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.CalendarToday, null, tint = wardColor(WardToken.beam), modifier = Modifier.size(16.dp))
        Text(line, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.inkSecondary))
    }
}

private fun focusIcon(item: FocusItem): ImageVector = when (item.glyph) {
    FocusGlyph.scope -> Icons.Rounded.GpsFixed
    FocusGlyph.warning -> Icons.Rounded.WarningAmber
    FocusGlyph.cards -> Icons.Rounded.Layers
    FocusGlyph.checklist -> Icons.Rounded.Checklist
    FocusGlyph.reason -> (item.action as? FocusAction.Reason)?.let { reasonIcon(it.reason) } ?: Icons.Rounded.GpsFixed
}

@Composable private fun FocusSection(items: List<FocusItem>, sparks: Map<String, List<SparkPoint>>, onRun: (FocusAction) -> Unit) {
    ReaderFormSection(header = "Focus next",
        footer = if (items.isEmpty()) null else "Ranked by how many marks each is likely worth: weak subjects by how often they are missed, then confident mistakes, cards waiting, syllabus gaps and your commonest reason for losing a mark.") {
        if (items.isEmpty()) Box(Modifier.fillMaxWidth().wardRowTile()) {
            ReaderEmptyState(Icons.Rounded.GpsFixed, "Nothing to focus on yet",
                "Make an MCQ set and answer a few questions. The most useful next steps will show here, best first.")
        } else items.forEachIndexed { index, item ->
            val spark = item.subject?.let { sparks[it] }.orEmpty()
            Row(Modifier.fillMaxWidth().wardRowTile().clickable(role = Role.Button) { onRun(item.action) }
                .semantics(mergeDescendants = true) {}.padding(vertical = WardSpace.xs.wardDp),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(22.dp).wardInset(CircleShape), contentAlignment = Alignment.Center) {
                    Text("${index + 1}", style = WardTextStyle.caption.textStyle(WardWeight.bold, mono = true), color = wardColor(WardToken.inkSecondary))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(focusIcon(item), null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(18.dp))
                        Text(item.title, style = WardTextStyle.body.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
                    }
                    Text(item.detail, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                    if (spark.size >= 2) Box(Modifier.padding(top = WardSpace.xs.wardDp)) { Sparkline(spark) }
                }
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
            }
        }
    }
}

@Composable private fun TrendsSection(s: VitalsSnapshot, passMark: Double) {
    ReaderFormSection(header = "Trends") {
        if (s.weeks.isEmpty()) Box(Modifier.fillMaxWidth().wardRowTile()) {
            ReaderEmptyState(Icons.AutoMirrored.Rounded.ShowChart, "No trends yet",
                "Answer questions on a few different days and your weekly accuracy and daily practice will show here.")
        } else {
            ChartBlock("Accuracy by week", "The last 8 weeks. The dashed line is the typical pass mark.") { WeeklyChart(s.weeks, passMark) }
            ChartBlock("Studied per day", "The last 30 days: questions answered and cards reviewed.") { DailyChart(s.days) }
        }
    }
}

/** A chart in its row: the title, the chart, and what it shows. */
@Composable private fun ChartBlock(title: String, caption: String, chart: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().wardRowTile().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
        chart()
        Text(caption, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
    }
}

@Composable private fun MistakesSection(
    s: VitalsSnapshot, store: StudyStore, subject: String, onSubject: (String) -> Unit,
    onConfident: () -> Unit, onRules: () -> Unit, onOne: (com.stethoscore.app.ui.mock.QuestionPick) -> Unit,
) {
    val subjects = s.wrong.map { MockLibrary.subjectName(it.pick.set) }.toSortedSet().toList()
    val shown = if (subject.isEmpty()) s.wrong else s.wrong.filter { MockLibrary.subjectName(it.pick.set) == subject }
    ReaderFormSection(header = "Mistakes",
        footer = if (s.wrong.isEmpty()) null else "Your latest wrong answer to each question, newest first. Tap one to try it again; the list icon opens its line on the rule sheet.") {
        if (s.wrong.isEmpty() && s.shares.isEmpty() && s.calibration.isEmpty()) Box(Modifier.fillMaxWidth().wardRowTile()) {
            ReaderEmptyState(Icons.Rounded.Verified, "No mistakes yet", "Questions you get wrong, and the reasons you give for them, will show here.", WardTone.Green)
        } else {
            if (s.shares.isNotEmpty()) ChartBlock("Why you lose marks",
                "The last ${StoreInsight.reasonWindowDays} days, from the reason picked after each wrong answer. Your commonest one has its fix under Focus next.") { ReasonDonut(s.shares) }
            if (s.calibration.isNotEmpty()) ChartBlock("Right by confidence",
                "Bars are how often each was right; the dashed line is roughly where it should be. “Sure” well under the line means facts learned wrongly.") { CalibrationChart(s.calibration) }
            if (s.confidentWrong > 0) Row(Modifier.fillMaxWidth().wardRowTile().clickable(role = Role.Button, onClick = onConfident)
                .semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.WarningAmber, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(18.dp))
                Text("Confident but wrong", Modifier.weight(1f), style = WardTextStyle.body.textStyle(), color = wardColor(WardToken.ink))
                Text("${s.confidentWrong}", style = WardTextStyle.subheadline.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
            }
            if (subjects.size > 1) SubjectPicker(subject, subjects, onSubject)
            for (answer in shown) WrongRow(answer, store.ruleSheet.containsKey(answer.pick.question.id), onRules) { onOne(answer.pick) }
        }
    }
}

/** The Subject picker (iOS's menu Picker in a list row): "All subjects" or one of them. */
@Composable private fun SubjectPicker(subject: String, subjects: List<String>, onSubject: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth().wardRowTile().clickable(role = Role.Button) { open = true }.semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Subject", Modifier.weight(1f), style = WardTextStyle.body.textStyle(), color = wardColor(WardToken.ink))
            Text(subject.ifEmpty { "All subjects" }, style = WardTextStyle.body.textStyle(), color = wardColor(WardToken.inkSecondary),
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            Icon(Icons.Rounded.KeyboardArrowDown, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
        }
        DropdownMenu(open, { open = false }, containerColor = wardColor(WardToken.raised)) {
            DropdownMenuItem({ Text("All subjects", color = wardColor(WardToken.ink)) }, { open = false; onSubject("") })
            for (name in subjects) DropdownMenuItem({ Text(name, color = wardColor(WardToken.ink)) }, { open = false; onSubject(name) })
        }
    }
}

/** "Renal · 3 Oct 2026 · Misread the question". */
internal fun wrongLine(answer: WrongAnswer, zone: ZoneId = ZoneId.systemDefault()): String {
    val subject = MockLibrary.subjectName(answer.pick.set)
    val day = Instant.ofEpochMilli(answer.date).atZone(zone).toLocalDate().format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))
    var line = "$subject · $day"
    if (answer.reason != null) line += " · " + answer.reason.title
    return line
}

@Composable private fun WrongRow(answer: WrongAnswer, hasRule: Boolean, onRules: () -> Unit, onOpen: () -> Unit) {
    val q = answer.pick.question
    val right = q.options.getOrNull(q.correctIndex).orEmpty()
    // what was chosen instead, when it was recorded and is still one of the question's options
    val chosen = answer.picked?.takeIf { it != q.correctIndex }?.let { q.options.getOrNull(it) }?.let { "You chose $it" }.orEmpty()
    Row(Modifier.fillMaxWidth().wardRowTile().padding(vertical = WardSpace.xs.wardDp), horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp),
        verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f).clickable(role = Role.Button, onClickLabel = "Opens this question on its own", onClick = onOpen)
            .semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(q.stem, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink), maxLines = 3, overflow = TextOverflow.Ellipsis)
            if (chosen.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.HighlightOff, null, tint = wardColor(WardToken.danger), modifier = Modifier.size(14.dp))
                Text(chosen, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.danger))
            }
            if (right.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.CheckCircleOutline, null, tint = wardColor(WardToken.success), modifier = Modifier.size(14.dp))
                Text(right, style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.success))
            }
            Text(wrongLine(answer), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
        if (hasRule) WardCircleButton(Icons.AutoMirrored.Rounded.ListAlt, "Rule sheet", onRules)
    }
}

@Composable private fun SubjectsSection(s: VitalsSnapshot, onDrill: (String) -> Unit) {
    ReaderFormSection(header = "Subjects",
        footer = if (s.stats.isEmpty()) null else "Weakest first; tap one to drill it. The arrow compares the last two weeks with before, when both have a few answers.") {
        if (s.stats.isEmpty()) Box(Modifier.fillMaxWidth().wardRowTile()) {
            ReaderEmptyState(Icons.AutoMirrored.Rounded.LibraryBooks, "No subjects yet", "Make an MCQ set and each subject you study will show here with its accuracy.")
        } else for (subject in s.stats) {
            val trend = s.trends[subject.name]
            Row(Modifier.fillMaxWidth().wardRowTile()
                .clickable(role = Role.Button, onClickLabel = "Opens a drill of ${subject.name}") { onDrill(subject.name) }
                .defaultMinSize(minHeight = 44.dp).padding(vertical = WardSpace.xs.wardDp).semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
                    Text(subject.name, style = WardTextStyle.body.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("${subject.answered} answered", style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
                if (trend != null) Icon(when (trend) {
                    Trend.up -> Icons.AutoMirrored.Rounded.TrendingUp
                    Trend.down -> Icons.AutoMirrored.Rounded.TrendingDown
                    Trend.flat -> Icons.AutoMirrored.Rounded.ArrowForward
                }, trend.label, tint = when (trend) {
                    Trend.up -> wardColor(WardToken.success)
                    Trend.down -> wardColor(WardToken.danger)
                    Trend.flat -> wardColor(WardToken.inkSecondary)
                }, modifier = Modifier.size(14.dp))
                ProgressRing(if (subject.answered == 0) 0.0 else subject.accuracy, size = 22.0, lineWidth = 3.5)
                Text(if (subject.answered == 0) "–" else percentText(subject.accuracy), Modifier.widthIn(min = 40.dp),
                    style = WardTextStyle.body.textStyle(WardWeight.semibold, mono = true), color = wardColor(WardToken.ink), textAlign = TextAlign.End)
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
            }
        }
    }
}

@Composable private fun TimeSection(s: VitalsSnapshot) {
    val average = VitalsNumbers.dailyAverage(s.days)
    ReaderFormSection(header = "Time",
        footer = "The average is over the days in the last 30 you studied at all. The calendar is the last 12 weeks, a column a week, today outlined; a moon marks a rest day that kept your streak.") {
        Column(Modifier.fillMaxWidth().wardRowTile(), verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                Figure("${s.streak}", if (s.streak == 1) "day streak" else "days streak", Icons.Rounded.LocalFireDepartment, wardColor(WardToken.beam))
                Figure("${s.studiedThisMonth}", "days this month", Icons.Rounded.CalendarMonth, wardColor(WardToken.primaryInk))
                Figure(average?.toString() ?: "–", "a day studied", Icons.Rounded.BarChart, wardColor(WardToken.success))
            }
            Box(Modifier.padding(vertical = WardSpace.s.wardDp)) { StudyHeatmap(s.dayCounts, s.restDays) }
        }
    }
}

@Composable private fun androidx.compose.foundation.layout.RowScope.Figure(value: String, caption: String, icon: ImageVector, colour: androidx.compose.ui.graphics.Color) {
    Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
        Icon(icon, null, tint = colour, modifier = Modifier.size(14.dp))
        Text(value, style = WardTextStyle.title2.textStyle(WardWeight.bold, mono = true), color = wardColor(WardToken.ink))
        Text(caption, style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
