package com.stethoscore.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.roundToInt

private fun studyDate(time: Long): LocalDate = Instant.ofEpochMilli(time).atZone(ZoneId.systemDefault()).minusHours(4).toLocalDate()

/** Metrics are calculated from saved answers/reviews; no synthetic readiness or pass forecast. */
@Composable fun VitalsScreen(store: StudyStore, onBack: () -> Unit) {
    val now = remember { System.currentTimeMillis() }
    val today = studyDate(now)
    val questions = store.library.flatMap { it.questions }.distinctBy { it.id }
    val questionIds = questions.map { it.id }.toSet()
    val cardIds = store.library.filter { it.kind == StudySetKind.ANKI }.flatMap { it.cards }.map { it.id }.toSet()
    val histories = store.answerHistory.filterKeys { it in questionIds }
    val attempts = histories.values.sumOf { it.size }
    val correct = histories.values.sumOf { answers -> answers.count { it } }
    val accuracy = if (attempts > 0) correct.toFloat() / attempts else null
    val answered = histories.count { it.value.isNotEmpty() }
    val coverage = if (questions.isNotEmpty()) answered.toFloat() / questions.size else 0f
    val days = store.answerLog.filter { it.questionId in questionIds }.groupingBy { studyDate(it.at) }.eachCount()
    val todayAnswers = days[today] ?: 0
    val reviewed = store.reviews.filterKeys { it in cardIds }.values
    val reviews = reviewed.sumOf { it.reviews }
    val due = store.dueCount(now)
    var streak = 0
    var day = if ((days[today] ?: 0) > 0) today else today.minusDays(1)
    while ((days[day] ?: 0) > 0) { streak++; day = day.minusDays(1) }
    val week = (6 downTo 0).map { today.minusDays(it.toLong()) }.map { it to (days[it] ?: 0) }
    val subjects = store.library.filter { it.kind == StudySetKind.MCQ }.groupBy { it.subject.ifBlank { "General" } }.map { (name, sets) ->
        val ids = sets.flatMap { it.questions }.map { it.id }.distinct()
        val answers = ids.flatMap { store.answerHistory[it].orEmpty() }
        Triple(name, answers.count { it }, answers.size)
    }.sortedWith(compareBy<Triple<String, Int, Int>> { if (it.third > 0) it.second.toDouble() / it.third else 2.0 }.thenBy { it.first })
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(20.dp, 12.dp, 20.dp, 24.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
        item { ScreenHeader("Vitals", "A picture of your practice", onBack) }
        store.examDate?.let { exam ->
            val date = Instant.ofEpochMilli(exam).atZone(ZoneId.systemDefault()).toLocalDate()
            val remaining = ChronoUnit.DAYS.between(LocalDate.now(), date)
            if (remaining >= 0) item { Text(if (remaining == 0L) "Your exam is today" else "Your exam in $remaining days", fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary) }
        }
        item {
            Column(Modifier.fillMaxWidth().background(Color(0xFF0E1B2C), RoundedCornerShape(24.dp)).padding(22.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                Text("QUESTION ACTIVITY · LAST 7 DAYS", color = Color(0xFFA3B1C3), fontSize = 10.sp, letterSpacing = 1.5.sp, fontWeight = FontWeight.Bold)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column { Text("$todayAnswers", fontSize = 38.sp, fontWeight = FontWeight.Bold, color = Color(0xFF4CC38A)); Text("answers today", color = Color(0xFFA3B1C3), fontSize = 12.sp) }
                    Column(horizontalAlignment = Alignment.End) { Text("$streak", fontSize = 38.sp, fontWeight = FontWeight.Bold, color = Color(0xFF7DB0F2)); Text("day question streak", color = Color(0xFFA3B1C3), fontSize = 12.sp) }
                }
                Row(Modifier.fillMaxWidth().height(65.dp), horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.Bottom) {
                    val highest = week.maxOf { it.second }.coerceAtLeast(1)
                    week.forEach { (date, count) ->
                        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Box(Modifier.fillMaxWidth().height((4 + count.toFloat() / highest * 40).dp).background(if (count > 0) Color(0xFF4CC38A) else Color(0xFF25364C), RoundedCornerShape(3.dp)))
                            Text(date.dayOfWeek.name.take(1), color = Color(0xFFA3B1C3), fontSize = 10.sp)
                        }
                    }
                }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                MetricRing("Accuracy", accuracy?.let { "${(it * 100).roundToInt()}%" } ?: "—", accuracy ?: 0f, "$correct of $attempts attempts", MaterialTheme.colorScheme.tertiary, Modifier.weight(1f))
                MetricRing("Questions seen", "${(coverage * 100).roundToInt()}%", coverage, "$answered of ${questions.size} questions", MaterialTheme.colorScheme.primary, Modifier.weight(1f))
            }
        }
        item {
            WardCard(Modifier.fillMaxWidth()) {
                SectionLabel("Spaced review")
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    StatNumber(due.toString(), "cards due")
                    StatNumber(reviews.toString(), "reviews saved")
                    StatNumber(cardIds.size.toString(), "cards in library")
                }
                if (due == 0 && cardIds.isNotEmpty()) Text("You're up to date. Your cards will return when they are due.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (subjects.isNotEmpty()) item {
            WardCard(Modifier.fillMaxWidth()) {
                SectionLabel("By subject")
                subjects.forEach { (name, right, total) ->
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(name, Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                            Text(if (total > 0) "${(right * 100f / total).roundToInt()}%" else "No answers", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
                        }
                        LinearProgressIndicator(progress = { if (total > 0) right.toFloat() / total else 0f }, modifier = Modifier.fillMaxWidth(), color = if (total > 0 && right.toFloat() / total < .6f) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.primary)
                        Text("$total recorded attempts", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        if (attempts == 0 && reviews == 0) item {
            WardCard(Modifier.fillMaxWidth()) {
                Text("Your progress begins with practice", fontWeight = FontWeight.Bold, fontSize = 21.sp)
                Text("Answer a question or review a card. Your saved activity will appear here.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item { Text("Accuracy includes repeat attempts. Questions seen counts unique questions in this library. The question streak and daily chart use a 4 a.m. study-day boundary.", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp) }
    }
}

@Composable private fun StatNumber(value: String, label: String) {
    Column { Text(value, fontSize = 27.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary); Text(label, fontSize = 10.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
}

@Composable private fun MetricRing(title: String, value: String, fraction: Float, detail: String, tint: Color, modifier: Modifier) {
    WardCard(modifier) {
        val track = MaterialTheme.colorScheme.outline.copy(alpha = .25f)
        Box(Modifier.size(86.dp).align(Alignment.CenterHorizontally), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val stroke = 6.dp.toPx()
                val inset = stroke / 2
                drawArc(track, -90f, 360f, false, Offset(inset, inset), Size(size.width - stroke, size.height - stroke), style = Stroke(stroke, cap = StrokeCap.Round))
                drawArc(tint, -90f, fraction.coerceIn(0f, 1f) * 360f, false, Offset(inset, inset), Size(size.width - stroke, size.height - stroke), style = Stroke(stroke, cap = StrokeCap.Round))
            }
            Text(value, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        }
        Text(title, fontWeight = FontWeight.Bold, fontSize = 14.sp)
        Text(detail, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
