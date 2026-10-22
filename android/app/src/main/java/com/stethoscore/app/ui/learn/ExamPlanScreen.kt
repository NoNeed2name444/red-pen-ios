package com.stethoscore.app.ui.learn

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ListAlt
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.MedicalInformation
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.ExamWeekPlanner
import com.stethoscore.app.data.RetentionForecast
import com.stethoscore.app.data.SecuredRule
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.ward.WardProgressBar
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.WardRowItem
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

// A port of ios/RedPen/Features/Learn/ExamPlanView.swift: where the run-up
// stands, today's goal and a focus session, what the student would remember
// on the day, the next two weeks of reviews, how much is locked in per
// subject, and what this phase asks for. Opened from Today's revision's
// "Open plan". Everything on it is an estimate from the app's own schedule
// and answer history, and it says so. The chosen exam's card (Your exam,
// ExamDashboardCard), the rule sheet and the ward pocket open the exam and
// Vitals batches' screens.

@Composable internal fun ExamPlanScreen(store: StudyStore, onPreset: (com.stethoscore.app.exam.NewSetPreset) -> Unit = {}) {
    val version = LearnRouter.version
    var notice by remember { mutableStateOf<String?>(null) }
    var pocketOpen by remember { mutableStateOf(false) }
    val context = androidx.compose.ui.platform.LocalContext.current
    val read = remember(version) {
        val now = System.currentTimeMillis()
        val phase = ExamWeekPlanner.phase(store.examDate?.let { Instant.ofEpochMilli(it) }, Instant.ofEpochMilli(now), ZoneId.systemDefault())
        val standings = LearnLibrary.securedStandings(store)
        PlanReading(
            phase = phase,
            forecast = LearnLibrary.examForecast(store, now),
            rings = SecuredRule.rings(LearnLibrary.questionSubjects(store), standings),
            due = RetentionForecast.dueByDay(LearnLibrary.deckCardIds(store), store.reviews, now, 14, ZoneId.systemDefault()),
            today = TodayLog.read(store),
            confident = LearnLibrary.confidentMistakePicks(store).size,
            missed = LearnLibrary.lastWrongPicks(store).size,
            lockIn = LearnLibrary.lockInPicks(store, standings, now).size,
        )
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = WardSpace.m.wardDp),
        verticalArrangement = Arrangement.spacedBy(WardSpace.section.wardDp)) {
        ReaderFormSection { Box(Modifier.wardRowTile()) { PhaseHero(read.phase) } }
        // Your exam: the chosen exam's blueprint, readiness and what to study next
        Box(Modifier.padding(horizontal = 16.dp)) { com.stethoscore.app.ui.exam.ExamDashboardCard(store, version, onPreset) }
        // the streak, the goal ring and a ward round
        ReaderFormSection("Today", "One missed day a week is a free rest day and keeps your streak. Minutes in a focus session count for the streak too. Set the daily goal in Settings → Study.") {
            Box(Modifier.wardRowTile()) { TodayGoalRow(read.today) }
        }
        // the tile is its own card, so no row behind it
        Box(Modifier.padding(horizontal = 8.dp)) { WardRoundTile() }
        ReaderFormSection("Remembering on the day",
            "An estimate from your cards’ review intervals on a standard forgetting curve, not a measurement. No interval is allowed to run past your exam date: cards come back a day or two before it.") {
            Box(Modifier.wardRowTile()) { ForecastCard(read.forecast, read.phase) }
        }
        ReaderFormSection("Due in the next two weeks") {
            Box(Modifier.wardRowTile()) { DueBars(read.due, read.phase.days) }
        }
        ReaderFormSection("Locked in",
            "A question is locked in once you have got it right on three separate days. Getting something right in three spaced sessions keeps far more of it than three times in one sitting. A wrong answer starts its count again.") {
            SecuredRingsView(read.rings)
        }
        ReaderFormSection("What this phase is for") {
            Box(Modifier.wardRowTile()) {
                Text(read.phase.advice, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            if (read.phase.holdsNewMaterial) {
                if (read.confident > 0) PlanRow("Confident errors (${read.confident})", Icons.Rounded.Warning) {
                    LearnRouter.push(LearnPush.Quiz(LearnLibrary.confidentMistakesQuiz(store)))
                }
                if (read.missed > 0) PlanRow("Your mistakes (${read.missed})", Icons.AutoMirrored.Rounded.Undo) {
                    LearnRouter.push(LearnPush.Quiz(LearnLibrary.mistakesQuiz(store)))
                }
                PlanRow("Rule sheet", Icons.AutoMirrored.Rounded.ListAlt) { LearnRouter.push(LearnPush.RuleSheet) }
            }
            if (read.lockIn > 0) {
                val plural = if (read.lockIn == 1) "" else "s"
                PlanRow("Lock in ${read.lockIn} question$plural", Icons.Rounded.Lock) {
                    LearnRouter.push(LearnPush.Quiz(LearnLibrary.lockInQuiz(store)))
                }
            }
            // the real mock paper; it counts as sat only once a sitting is finished
            if (read.phase.isMockWindow) PlanRow("Sit a mock paper", Icons.Rounded.Timer) { LearnRouter.push(LearnPush.Mock) }
            PlanRow("Symptom blocks", Icons.Rounded.MedicalServices) { LearnRouter.open(LearnRoute.SymptomBlocks) }
            PlanRow("Exam-day kit", Icons.Rounded.Checklist) { LearnRouter.open(LearnRoute.ExamKit) }
        }
        ReaderFormSection(footer = "Lab values, clinical calculators and scores, each with how it is worked out. For learning only.") {
            PlanRow("Clinical reference", Icons.Rounded.MedicalInformation) { pocketOpen = true }
        }
    }
    NotYetNotice(notice) { notice = null }
    if (pocketOpen) com.stethoscore.app.ui.exam.ExamSheet({ pocketOpen = false }) {
        com.stethoscore.app.ui.exam.WardPocketScreen(com.stethoscore.app.ui.QuizPrefs.track(context), { pocketOpen = false },
            { made -> runCatching { store.addSet(made) } })
    }
}

private class PlanReading(
    val phase: ExamWeekPlanner.Phase,
    val forecast: RetentionForecast.Forecast,
    val rings: List<SecuredRule.Ring>,
    val due: List<Int>,
    val today: TodayLog,
    val confident: Int,
    val missed: Int,
    val lockIn: Int,
)

@Composable private fun PlanRow(title: String, icon: ImageVector, action: () -> Unit) {
    Box(Modifier.clickable(onClick = action).wardRowTile().heightIn(min = 44.dp), contentAlignment = Alignment.CenterStart) {
        WardRowItem(icon, title)
    }
}

/** The phase, large: "T-9 · Mock week". */
@Composable private fun PhaseHero(phase: ExamWeekPlanner.Phase) {
    val big = phase.days?.let { if (it == 0) "Today" else "T-$it" } ?: "—"
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(big, color = wardColor(WardToken.ink), fontSize = 40.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(phase.headline, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
            if (phase == ExamWeekPlanner.Phase.NoDate) Text("Set it in Settings → Your exam.",
                style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}

/** "If your exam were today you'd remember ~71%; do 140 reviews over the next 10 days to reach 90%." */
@Composable private fun ForecastCard(forecast: RetentionForecast.Forecast, phase: ExamWeekPlanner.Phase) {
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (forecast.studied == 0) {
            Text("Review some cards and a forecast of what you would remember on the day will show here.",
                style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
            return@Column
        }
        val today = RetentionForecast.percent(forecast.today)
        Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("~$today", color = wardColor(WardToken.ink), fontSize = 36.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
            Text("if your exam were today", Modifier.padding(bottom = 6.dp), style = WardTextStyle.subheadline.textStyle(),
                color = wardColor(WardToken.inkSecondary))
        }
        WardProgressBar(forecast.today, "Remembered if your exam were today")
        if (phase.days != null && phase != ExamWeekPlanner.Phase.ExamDay) {
            val onDay = RetentionForecast.percent(forecast.onExamDay)
            Text("On exam day with no more reviews: ~$onDay.", style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
            Text(planSentence(forecast), style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
        }
        if (forecast.unseen > 0) {
            val plural = if (forecast.unseen == 1) "" else "s"
            Text("${forecast.unseen} card$plural not yet studied are not in these figures.",
                style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}

private fun planSentence(forecast: RetentionForecast.Forecast): String {
    if (forecast.reviewsNeeded == 0) return "On course for 90% on the day."
    val plural = if (forecast.days == 1) "" else "s"
    val perDay = "about ${forecast.perDay} a day"
    return "Do ${forecast.reviewsNeeded} reviews over the next ${forecast.days} day$plural ($perDay) to reach 90%."
}

private fun spokenCount(n: Int, noun: String): String = if (n == 1) "1 $noun" else "$n ${noun}s"

/** Fourteen small bars: cards falling due each day, today first. The exam's day is red and carries a flag. */
@Composable private fun DueBars(counts: List<Int>, examDay: Int?) {
    val top = maxOf(1, counts.maxOrNull() ?: 1)
    val total = counts.sum()
    val spoken = run {
        val whole = spokenCount(total, "card") + " due over the next two weeks, ${counts.firstOrNull() ?: 0} today"
        if (examDay == null || examDay >= counts.size) whole
        else whole + ". " + (if (examDay == 0) "The exam is today." else "The exam is in ${spokenCount(examDay, "day")}.")
    }
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().height(72.dp).clearAndSetSemantics { contentDescription = spoken },
            horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.Bottom) {
            counts.forEachIndexed { day, count ->
                val isExam = examDay == day
                val fill = if (isExam) wardColor(WardToken.ecg) else wardColor(WardToken.primaryInk)
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.Bottom)) {
                    if (isExam) Icon(Icons.Rounded.Flag, null, Modifier.size(11.dp), tint = fill)
                    val height = maxOf(3f, 56f * count / top)
                    Box(Modifier.fillMaxWidth().height(height.dp).background(fill.copy(alpha = if (count == 0) 0.25f else 1f), CircleShape))
                }
            }
        }
        Row(Modifier.fillMaxWidth()) {
            Text("Today", style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
            Spacer(Modifier.weight(1f))
            Text("+13 days", style = WardTextStyle.caption2.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
        }
    }
}

/** One ring per subject: locked in, with the questions on their way lighter. */
@Composable internal fun SecuredRingsView(rings: List<SecuredRule.Ring>) {
    if (rings.isEmpty()) {
        Box(Modifier.wardRowTile()) {
            Text("Answer some questions and each subject gets a ring here.", style = WardTextStyle.subheadline.textStyle(),
                color = wardColor(WardToken.inkSecondary))
        }
        return
    }
    val secured = rings.sumOf { it.secured }
    val total = rings.sumOf { it.total }
    Box(Modifier.wardRowTile()) {
        Text("$secured of $total questions locked in", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold),
            color = wardColor(WardToken.ink))
    }
    Box(Modifier.wardRowTile()) {
        BoxWithConstraints(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
            // as many 92-wide columns as fit, 12 apart (an adaptive grid)
            val columns = maxOf(1, ((maxWidth.value + 12) / (92 + 12)).toInt())
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                for (line in rings.chunked(columns)) Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    for (ring in line) Box(Modifier.weight(1f), contentAlignment = Alignment.TopCenter) { SubjectRing(ring) }
                    repeat(columns - line.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable private fun SubjectRing(ring: SecuredRule.Ring) {
    val total = maxOf(1, ring.total).toDouble()
    val secured = ring.secured / total
    val building = (ring.secured + ring.building) / total
    val tint = wardColor(WardToken.primaryInk)
    val track = wardColor(WardToken.hairline)
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    Column(Modifier.clearAndSetSemantics {
        contentDescription = "${ring.subject}: ${ring.secured} of ${ring.total} locked in, ${ring.building} on their way"
    }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(60.dp), contentAlignment = Alignment.Center) {
            // both arcs clockwise from the top, anticlockwise right to left
            Canvas(Modifier.fillMaxSize().scale(if (rtl) -1f else 1f, 1f)) {
                val w = 7.dp.toPx()
                val tl = Offset(w / 2, w / 2)
                val sz = Size(size.width - w, size.height - w)
                drawArc(track, 0f, 360f, false, tl, sz, style = Stroke(w))
                drawArc(tint.copy(alpha = 0.3f), -90f, 360f * building.toFloat(), false, tl, sz, style = Stroke(w, cap = StrokeCap.Round))
                drawArc(tint, -90f, 360f * secured.toFloat(), false, tl, sz, style = Stroke(w, cap = StrokeCap.Round))
            }
            Text(RetentionForecast.percent(secured), style = WardTextStyle.caption.textStyle(WardWeight.bold, mono = true),
                color = wardColor(WardToken.ink))
        }
        Text(ring.subject, Modifier.widthIn(max = 120.dp), style = WardTextStyle.caption.textStyle(), maxLines = 3,
            textAlign = TextAlign.Center, color = wardColor(WardToken.ink))
        Text("${ring.secured}/${ring.total}", style = WardTextStyle.caption2.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
    }
}
