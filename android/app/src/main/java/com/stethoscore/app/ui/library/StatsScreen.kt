package com.stethoscore.app.ui.library

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.ViewList
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ChangeCircle
import androidx.compose.material.icons.rounded.CompareArrows
import androidx.compose.material.icons.rounded.GpsFixed
import androidx.compose.material.icons.rounded.Inbox
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.outlined.Lightbulb
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.LibraryStats
import com.stethoscore.app.data.QuestionPick
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.data.SubjectStats
import com.stethoscore.app.quiz.MistakeReason
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp

// iOS Features/Library/StatsView.swift and its InsightQuestionList
// (Features/Insight/InsightViews.swift): By subject. The streak, MCQ
// accuracy subject by subject with "Drill weakest" under the thumb, and the
// parts about how marks are lost: confidence, and the reasons given for
// wrong answers with one thing to do about each. Every quiz it starts is put
// together on the spot and not saved to the library.

/** A list of questions with a tip, opened from the lost-marks sections. */
private data class QuestionList(val title: String, val tip: String?, val picks: List<QuestionPick>)

@Composable fun StatsScreen(store: StudyStore, revision: Int, onBack: () -> Unit, onQuiz: (LibraryQuiz) -> Unit) {
    var list by remember { mutableStateOf<QuestionList?>(null) }
    list?.let { shown ->
        BackHandler { list = null }
        InsightQuestionList(shown, { list = null }, onQuiz)
        return
    }
    val context = LocalContext.current
    val stats = remember(revision) { LibraryStats.subjectStats(store) }
    val tried = stats.filter { it.answered > 0 }
    val (streak, today) = remember(revision) { LibraryStats.streakAndToday(store) }
    val rows = remember(revision) { LibraryStats.calibration(store) }
    val confidentWrong = remember(revision) { LibraryStats.confidentMistakePicks(store) }
    val shares = remember(revision) { LibraryStats.reasonShares(store) }
    val seconds = remember { com.stethoscore.app.ui.QuizPrefs.track(context).secondsPerQuestion }

    fun startQuiz(set: StudySet, minReadSeconds: Int = 0, timed: Boolean = false) {
        if (set.questions.isNotEmpty()) onQuiz(LibraryQuiz(set, minReadSeconds, timed))
    }
    fun drillSubject(subject: String) = startQuiz(LibraryStats.drill(store, subject))

    Column(Modifier.fillMaxSize()) {
        LibraryPageTop("By subject", onBack)
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(20.dp, 8.dp, 20.dp, 24.dp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.xl.wardDp)) {
            item {
                LibraryFormSection(footer = tried.firstOrNull()?.let { StatsWords.drillNote(it.subject) }) {
                    Overview(tried, streak, today)
                }
            }
            item {
                LibraryFormSection("Confidence",
                    footer = if (rows.isNotEmpty()) "“Sure” should be right nearly every time. Confident mistakes come first in every drill." else null) {
                    if (rows.isEmpty()) Empty("Pick Sure, Maybe or Guess before checking an answer, and how often each is right will show here.")
                    rows.forEach { row ->
                        Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            TitleAndFigure(row.confidence.title, "${StatsWords.percent(row.accuracy)} right", wardColor(WardToken.primaryInk))
                            LibraryGroove(row.accuracy, wardColor(WardToken.primaryInk), Modifier.clearAndSetSemantics {})
                            Text(StatsWords.counted(row.answered, "answer"), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                        }
                    }
                    if (confidentWrong.isNotEmpty()) {
                        LinkRow(Icons.Rounded.Warning, "Confident but wrong", "${confidentWrong.size}") {
                            list = QuestionList("Confident but wrong",
                                "These felt certain and were not: usually a fact learned wrongly rather than one not learned. Read the explanation, then quiz them again.",
                                confidentWrong)
                        }
                        ActionLine(Icons.Rounded.GpsFixed, "Confident mistakes quiz") { startQuiz(LibraryStats.confidentMistakesQuiz(store)) }
                    }
                }
            }
            item {
                LibraryFormSection("Why you lose marks",
                    footer = if (shares.isNotEmpty()) "The last ${LibraryStats.reasonWindowDays} days, from the reason you picked after each wrong answer." else null) {
                    if (shares.isEmpty()) Empty("After a wrong answer, tap why you think you lost the mark. The reasons you give show here with something to do about each.")
                    shares.forEach { share ->
                        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(reasonIcon(share.reason), null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(18.dp))
                                Box(Modifier.weight(1f)) {
                                    TitleAndFigure(share.reason.title, StatsWords.percent(share.share), wardColor(WardToken.primaryInk))
                                }
                            }
                            LibraryGroove(share.share, wardColor(WardToken.primaryInk), Modifier.clearAndSetSemantics {})
                            val questions = StatsWords.counted(share.count, "question")
                            when (share.reason) {
                                MistakeReason.didntKnow -> ActionLine(Icons.AutoMirrored.Rounded.ArrowForward, "Practise these · $questions") {
                                    startQuiz(LibraryStats.reasonQuiz(store, MistakeReason.didntKnow, "Practise these"))
                                }
                                MistakeReason.misread -> ActionLine(Icons.AutoMirrored.Rounded.ArrowForward, "Slow reading drill · key words marked, 15 s a question") {
                                    startQuiz(LibraryStats.reasonQuiz(store, MistakeReason.misread, "Slow reading drill"), minReadSeconds = 15)
                                }
                                MistakeReason.changedAnswer -> ActionLine(null, "A tip, and the $questions") {
                                    list = QuestionList("Changed a right answer",
                                        "Change an answer only when you find a clue in the stem you missed the first time, not because a second option starts to look good. Your first answer was right here.",
                                        LibraryStats.picks(store, MistakeReason.changedAnswer))
                                }
                                MistakeReason.outOfTime -> ActionLine(Icons.AutoMirrored.Rounded.ArrowForward, "Timed drill · 10 questions at $seconds s each") {
                                    startQuiz(LibraryStats.timedDrill(store), timed = true)
                                }
                                MistakeReason.lookalikes -> ActionLine(null, "See the $questions") {
                                    list = QuestionList("Mixed up lookalikes",
                                        "For each, name the one feature that tells the right answer from the option you chose.",
                                        LibraryStats.picks(store, MistakeReason.lookalikes))
                                }
                            }
                        }
                    }
                }
            }
            if (stats.isEmpty()) item {
                LibraryFormSection { Empty("Make an MCQ set and answer a few questions, and how you are doing in each subject will show here.") }
            } else item {
                LibraryFormSection("By subject",
                    footer = "Every answer you have checked counts, so a question answered twice counts twice. Weakest first. Tap a subject to drill it.") {
                    stats.forEach { subject -> SubjectRow(subject) { drillSubject(subject.subject) } }
                }
            }
        }
        tried.firstOrNull()?.let { weakest ->
            LibraryStudyBar {
                WardButtonBox({ drillSubject(weakest.subject) }, Modifier.fillMaxWidth().semantics { contentDescription = "Drill weakest: ${weakest.subject}. ${StatsWords.drillNote(weakest.subject)}" },
                    kind = WardButtonKind.primary) {
                    Icon(Icons.Rounded.GpsFixed, null, Modifier.size(18.dp))
                    Text("Drill weakest: ${weakest.subject}", maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

/** The streak, today, and everything answered so far. */
@Composable private fun Overview(tried: List<SubjectStats>, streak: Int, today: Int) {
    val answered = tried.sumOf { it.answered }
    val correct = tried.sumOf { it.correct }
    val share = if (answered == 0) 0.0 else correct.toDouble() / answered
    val right = if (answered == 0) "–" else StatsWords.percent(share)
    val streakWord = if (streak == 1) "day streak" else "days streak"
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Figure("$streak", streakWord, Icons.Rounded.LocalFireDepartment, wardColor(WardToken.beam), Modifier.weight(1f))
        Figure("$today", "today", Icons.Rounded.CheckCircle, wardColor(WardToken.primaryInk), Modifier.weight(1f))
        Figure(right, "of $answered right", Icons.Rounded.GpsFixed, wardColor(WardToken.success), Modifier.weight(1f))
    }
}

@Composable private fun Figure(value: String, caption: String, icon: ImageVector, color: Color, modifier: Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Icon(icon, null, tint = color, modifier = Modifier.size(14.dp))
        Text(value, style = WardTextStyle.title2.textStyle(WardWeight.bold, mono = true), color = wardColor(WardToken.ink))
        Text(caption, style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable private fun TitleAndFigure(title: String, figure: String, color: Color) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = WardTextStyle.body.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink), maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Spacer(Modifier.size(8.dp))
        Text(figure, style = WardTextStyle.body.textStyle(WardWeight.semibold, mono = true), color = color)
    }
}

@Composable private fun Empty(text: String) {
    Text(text, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
}

/** A row that opens a page: a glyph, a name, a count and a chevron (iOS NavigationLink). */
@Composable private fun LinkRow(icon: ImageVector, title: String, count: String?, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(role = Role.Button, onClick = onClick), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(icon, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(20.dp))
        Text(title, style = WardTextStyle.body.textStyle(), color = wardColor(WardToken.ink), modifier = Modifier.weight(1f))
        if (count != null) Text(count, style = WardTextStyle.subheadline.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
    }
}

/** A line in the tint that does one thing (iOS borderless Label button). */
@Composable private fun ActionLine(icon: ImageVector?, text: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(role = Role.Button, onClick = onClick), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (icon != null) Icon(icon, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(18.dp))
        Text(text, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.primaryInk), modifier = Modifier.weight(1f))
    }
}

/** A subject's row: a tap drills it. Green from three in four, amber from half, red below; grey when not tried. */
@Composable private fun SubjectRow(s: SubjectStats, onClick: () -> Unit) {
    val color = when {
        s.answered == 0 -> wardColor(WardToken.inkSecondary)
        s.accuracy >= 0.75 -> wardColor(WardToken.success)
        s.accuracy >= 0.5 -> wardColor(WardToken.warning)
        else -> wardColor(WardToken.danger)
    }
    val percent = if (s.answered == 0) "Not tried" else StatsWords.percent(s.accuracy)
    val line = "${s.answered} answered · ${StatsWords.counted(s.questions, "question")}"
    Column(Modifier.fillMaxWidth().clickable(role = Role.Button, onClickLabel = "Drills up to 20 questions in this subject", onClick = onClick)
        .semantics(mergeDescendants = true) {}.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        TitleAndFigure(s.subject, percent, color)
        LibraryGroove(if (s.answered == 0) 0.0 else s.accuracy, color, Modifier.clearAndSetSemantics {})
        Text(line, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
    }
}

private fun reasonIcon(reason: MistakeReason): ImageVector = when (reason) {
    MistakeReason.didntKnow -> Icons.Outlined.Lightbulb
    MistakeReason.misread -> Icons.Rounded.Visibility
    MistakeReason.changedAnswer -> Icons.Rounded.ChangeCircle
    MistakeReason.outOfTime -> Icons.Rounded.Timer
    MistakeReason.lookalikes -> Icons.Rounded.CompareArrows
}

/** The most questions Quiz these asks: the same cap as the confident mistakes quiz (iOS InsightQuestionList.quizLimit). */
private const val QUIZ_LIMIT = 20

/** These questions as a quiz of their own, shuffled and capped (iOS InsightQuestionList.makeQuiz). */
private fun makeQuiz(name: String, picks: List<QuestionPick>): StudySet {
    val chosen = picks.shuffled().take(QUIZ_LIMIT)
    val subjects = chosen.map { LibraryStats.subjectName(it.set) }.toSet()
    val subject = if (subjects.size == 1) subjects.first() else "Mixed"
    return LibraryStats.temporaryQuiz(name, subject, chosen)
}

/** A list of questions with a tip, each opening to its answer, and Quiz these (iOS InsightQuestionList). */
@Composable private fun InsightQuestionList(list: QuestionList, onBack: () -> Unit, onQuiz: (LibraryQuiz) -> Unit) {
    Column(Modifier.fillMaxSize()) {
        LibraryPageTop(list.title, onBack)
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(20.dp, 8.dp, 20.dp, 24.dp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.xl.wardDp)) {
            list.tip?.let { tip -> item {
                LibraryFormSection {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Outlined.Lightbulb, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(18.dp))
                        Text(tip, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
                    }
                }
            } }
            if (list.picks.isEmpty()) item {
                LibraryFormSection { LibraryEmptyState(Icons.Rounded.Inbox, "Nothing here at the moment.") }
            } else item {
                val count = list.picks.size
                LibraryFormSection(footer = "$count question${if (count == 1) "" else "s"}. Tap one to see its answer.") {
                    list.picks.forEach { pick -> InsightQuestionRow(pick) }
                }
            }
        }
        if (list.picks.isNotEmpty()) LibraryStudyBar {
            val hint = if (list.picks.size > QUIZ_LIMIT) "A quiz of $QUIZ_LIMIT of these questions, in a new order, not saved to your library"
                else "A quiz of these questions, in a new order, not saved to your library"
            WardButtonBox({ onQuiz(LibraryQuiz(makeQuiz(list.title, list.picks))) },
                Modifier.fillMaxWidth().semantics { contentDescription = "Quiz these. $hint" }, kind = WardButtonKind.primary) {
                Icon(Icons.AutoMirrored.Rounded.ViewList, null, Modifier.size(18.dp)); Text("Quiz these")
            }
        }
    }
}

/** One question, folded: the stem and its subject, opening on a tap to the right answer and why. */
@Composable private fun InsightQuestionRow(pick: QuestionPick) {
    var open by remember(pick.question.id) { mutableStateOf(false) }
    val q = pick.question
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClickLabel = if (open) "Hide answer" else "Show answer") { open = !open },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(q.stem, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink), maxLines = 3, overflow = TextOverflow.Ellipsis)
                Text(LibraryStats.subjectName(pick.set), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.primaryInk),
                modifier = Modifier.size(18.dp).then(if (open) Modifier.rotate(90f) else Modifier))
        }
        if (open) Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (q.correctIndex in q.options.indices) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Rounded.CheckCircle, null, tint = wardColor(WardToken.success), modifier = Modifier.size(16.dp))
                Text(q.options[q.correctIndex], style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.success))
            }
            if (q.explanation.isNotEmpty()) Text(q.explanation, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}
