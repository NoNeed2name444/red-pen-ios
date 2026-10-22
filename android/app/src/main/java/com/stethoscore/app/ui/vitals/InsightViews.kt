package com.stethoscore.app.ui.vitals

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.ListAlt
import androidx.compose.material.icons.rounded.CheckCircleOutline
import androidx.compose.material.icons.rounded.GpsFixed
import androidx.compose.material.icons.rounded.Inbox
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.ui.draw.rotate
import com.stethoscore.app.data.Readiness
import com.stethoscore.app.data.ReadinessEstimate
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.QuizScreen
import com.stethoscore.app.ui.mock.BigButton
import com.stethoscore.app.ui.mock.BigKind
import com.stethoscore.app.ui.mock.MockLibrary
import com.stethoscore.app.ui.mock.QuestionPick
import com.stethoscore.app.ui.mock.StudyTitleBar
import com.stethoscore.app.ui.mock.readableColumn
import com.stethoscore.app.ui.sources.ReaderEtch
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.ward.StudyActionBar
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardEmptyState
import com.stethoscore.app.ui.ward.WardSectionLabel
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTypeSpec
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardInset
import com.stethoscore.app.ui.wardColor
import java.util.Locale

// A port of ios/RedPen/Features/Insight/InsightViews.swift: the
// readiness card, its range bar, and the list of questions with their
// answers that changed answers, lookalikes and confident mistakes open.

/** A quiz opened from the Vitals screen, with the way it is to be sat: normally, as a slow reading drill, or against the clock. */
data class InsightQuiz(
    val set: StudySet,
    /** Seconds before each answer can be checked; 0 for none. */
    val minReadSeconds: Int = 0,
    /** Starts in timed exam mode. */
    val timed: Boolean = false,
)

/** An InsightQuiz sat on the spot, never kept in the library. */
@Composable internal fun InsightQuizScreen(quiz: InsightQuiz, store: StudyStore, onBack: () -> Unit) {
    QuizScreen(quiz.set, store, onBack, keepsProgress = false, minReadSeconds = quiz.minReadSeconds, startsTimed = quiz.timed)
}

/** The readiness card: the estimated score as a range, against a typical pass mark, and the subjects that would move it most. */
@Composable fun ReadinessCard(estimate: ReadinessEstimate?, answered: Int, includesExamples: Boolean, track: ExamTrack,
                              onDrill: (String) -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Speed, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(18.dp))
                Text("Readiness estimate", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
            }
            Spacer(Modifier.width(8.dp))
            if (includesExamples) WardChip("Example data", tone = WardTone.Grey)
        }
        if (estimate != null) Filled(estimate, track, onDrill) else Empty(answered)
    }
}

@Composable private fun Empty(answered: Int) {
    val needed = Readiness.minimumAnswers
    val done = minOf(answered, needed)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Answer at least $needed questions and an estimated score will show here.",
            style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        EcgStrip(done.toDouble() / needed)
        Text("$done of $needed", style = WardTextStyle.caption.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
    }
}

/** "Likely above the pass mark", "Below the pass mark for now" or "Around the pass mark". */
fun readinessVerdict(e: ReadinessEstimate): String = when {
    e.low >= e.passMark -> "Likely above the pass mark"
    e.high < e.passMark -> "Below the pass mark for now"
    else -> "Around the pass mark"
}

/** What the estimate rests on and what was taken off, in plain words. */
fun readinessBasis(e: ReadinessEstimate): String {
    val parts = mutableListOf("An estimate, not a prediction: your last ${e.answers} answers, the latest counting most.")
    if (e.coveragePenalty >= 0.005) {
        val n = e.thinSubjects.size
        parts.add("${percentOf(e.coveragePenalty)} off for $n subject${if (n == 1) "" else "s"} with under ${Readiness.thinSubjectAnswers} answers.")
    }
    if (e.reviewPenalty >= 0.005) {
        parts.add("${percentOf(e.reviewPenalty)} off for ${e.dueCards} card${if (e.dueCards == 1) "" else "s"} waiting for review.")
    }
    return parts.joinToString(" ")
}

/** "18% of your questions · 52% right", or "· not tried yet". */
fun leverLine(lever: ReadinessEstimate.Lever): String {
    val share = "${percentText(lever.share)} of your questions"
    val accuracy = lever.accuracy ?: return "$share · not tried yet"
    return "$share · ${percentText(accuracy)} right"
}

/** "Typical pass mark for PLAB: 60% · approximate"; general revision names no exam. */
fun passLine(e: ReadinessEstimate, track: ExamTrack): String {
    val exam = if (track == ExamTrack.general) "" else " for " + track.rawValue.uppercase(Locale.ROOT)
    return "Typical pass mark$exam: ${percentText(e.passMark)} · approximate"
}

@Composable private fun Filled(e: ReadinessEstimate, track: ExamTrack, onDrill: (String) -> Unit) {
    Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(percentText(e.center), style = WardTypeSpec(WardTextStyle.largeTitle, WardWeight.bold, mono = true).textStyle().copy(fontSize = 40.sp),
            color = wardColor(WardToken.ink))
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text("likely ${percentText(e.low)}–${percentText(e.high)}", style = WardTextStyle.subheadline.textStyle(WardWeight.medium, mono = true),
                color = wardColor(WardToken.ink))
            Text(readinessVerdict(e), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
    RangeBar(e.low, e.center, e.high, e.passMark)
    Text(passLine(e, track), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
    Text(readinessBasis(e), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
    if (e.levers.isNotEmpty()) {
        ReaderEtch()
        WardSectionLabel("What would move it most")
        for (lever in e.levers) {
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
                .clickable(role = Role.Button, onClickLabel = "Opens a drill of ${lever.subject}") { onDrill(lever.subject) }
                .semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.GpsFixed, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(18.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(lever.subject, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
                    Text(leverLine(lever), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
            }
        }
    }
}

/** Where RangeBar's pieces go, in points: the range's width and start, the middle dot's start and the pass mark's tick. */
data class RangeBarLayout(val rangeWidth: Double, val rangeX: Double, val centerX: Double, val markX: Double) {
    companion object {
        fun of(width: Double, low: Double, center: Double, high: Double, mark: Double): RangeBarLayout {
            val w = width
            return RangeBarLayout(
                rangeWidth = maxOf(8.0, (high - low) * w),
                rangeX = minOf(maxOf(0.0, low * w), maxOf(0.0, w - 8)),
                centerX = minOf(maxOf(0.0, center * w - 6), w - 12),
                markX = minOf(maxOf(0.0, mark * w - 1), w - 2),
            )
        }
    }
}

/** 0-100% as a groove pressed into the card, with the estimate's range shaded, its middle marked, and a tick at the pass mark. */
@Composable private fun RangeBar(low: Double, center: Double, high: Double, mark: Double) {
    val accent = wardColor(WardToken.primaryInk)
    val ink = wardColor(WardToken.ink)
    BoxWithConstraints(Modifier.fillMaxWidth().height(18.dp).clearAndSetSemantics {}) {
        val layout = RangeBarLayout.of(maxWidth.value.toDouble(), low, center, high, mark)
        Box(Modifier.fillMaxWidth().height(8.dp).align(Alignment.CenterStart).wardInset(CircleShape))
        Canvas(Modifier.fillMaxSize()) {
            val mid = size.height / 2
            val p = density
            drawRoundRect(accent.copy(alpha = 0.35f), Offset((layout.rangeX * p).toFloat(), mid - 4 * p),
                Size((layout.rangeWidth * p).toFloat(), 8 * p), CornerRadius(4 * p))
            drawCircle(accent, 6 * p, Offset(((layout.centerX + 6) * p).toFloat(), mid))
            drawRect(ink, Offset((layout.markX * p).toFloat(), 0f), Size(2 * p, 18 * p))
        }
    }
}

/** The most questions Quiz these asks - the same cap as the confident mistakes quiz. */
const val insightQuizLimit = 20

/** These questions as a quiz of their own: one subject's name when they all share it, "Mixed" otherwise. Shuffled and capped. */
fun insightQuiz(name: String, picks: List<QuestionPick>): StudySet {
    val chosen = picks.shuffled().take(insightQuizLimit)
    val subjects = chosen.map { MockLibrary.subjectName(it.set) }.toSet()
    val subject = if (subjects.size == 1) subjects.first() else "Mixed"
    return MockLibrary.temporaryQuiz(name, subject, chosen)
}

/**
 * A list of questions with their answers, for the reasons that call for
 * reading rather than a quiz: changed answers and lookalikes, and the
 * confident mistakes. Once they are read, Quiz these - in the slab at the
 * bottom, under the thumb - asks the same questions again.
 */
@Composable fun InsightQuestionList(title: String, tip: String?, picks: List<QuestionPick>, store: StudyStore, onBack: () -> Unit) {
    var quiz by remember { mutableStateOf<StudySet?>(null) }
    quiz?.let { set ->
        BackHandler { quiz = null }
        QuizScreen(set, store, { quiz = null }, keepsProgress = false)
        return
    }
    BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize()) {
        StudyTitleBar(title, onBack)
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.readableColumn().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                if (tip != null) ReaderFormSection {
                    Row(Modifier.fillMaxWidth().wardRowTile(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Rounded.Lightbulb, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(18.dp))
                        Text(tip, Modifier.weight(1f), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
                    }
                }
                if (picks.isEmpty()) ReaderFormSection {
                    Box(Modifier.fillMaxWidth().wardRowTile()) { WardEmptyState(Icons.Rounded.Inbox, "Nothing here at the moment.") }
                } else ReaderFormSection(footer = "${picks.size} question${if (picks.size == 1) "" else "s"}. Tap one to see its answer.") {
                    for (pick in picks) InsightQuestionRow(pick)
                }
            }
        }
        if (picks.isNotEmpty()) StudyActionBar {
            BigButton("Quiz these", Icons.AutoMirrored.Rounded.ListAlt, BigKind.primary, { quiz = insightQuiz(title, picks) })
        }
    }
}

/** One question, folded: the stem and its subject, opening on a tap to the right answer and why. */
@Composable private fun InsightQuestionRow(pick: QuestionPick) {
    val q = pick.question
    var open by rememberSaveable(q.id) { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().wardRowTile(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClickLabel = if (open) "Hide the answer" else "Show the answer") { open = !open },
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(q.stem, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink), maxLines = 3, overflow = TextOverflow.Ellipsis)
                Text(MockLibrary.subjectName(pick.set), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.primaryInk),
                modifier = Modifier.size(16.dp).rotate(if (open) 90f else 0f))
        }
        if (open) Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            q.options.getOrNull(q.correctIndex)?.let { answer ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.CheckCircleOutline, null, tint = wardColor(WardToken.success), modifier = Modifier.size(16.dp))
                    Text(answer, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.success))
                }
            }
            if (q.explanation.isNotEmpty()) Text(q.explanation, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}
