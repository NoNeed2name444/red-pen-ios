package com.stethoscore.app.ui

import androidx.compose.animation.core.animateIntAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.MCQAnswer
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.quiz.QuizSummary
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardToken
import kotlin.math.roundToInt

// A port of ios/RedPen/Features/MCQ/MCQSummaryView.swift: the
// results. "N of M right" over a score ring, the verdict, Try again, every
// question with a tick or a cross, and one main button: Save to library for
// a set not yet saved, then Practise mistakes, then Done. The sums are in
// quiz/QuizSummary.kt (QuizSummaryTest). Not here yet: Add rules and the
// rule sheet (Insight, batch 15) and Save to Ideas.

@Composable
fun QuizSummaryScreen(
    set: StudySet, store: StudyStore,
    /** The answers to the set's own questions, as indices into each question's own options. */
    answers: List<MCQAnswer>,
    onDone: () -> Unit, onRetake: (() -> Unit)?, onOpen: (StudySet) -> Unit,
    isUnsaved: Boolean = false, saved: Boolean = false, onSave: () -> Unit = {},
) {
    val haptic = LocalHapticFeedback.current
    var mistakesSaved by remember { mutableStateOf(false) }
    val questions = set.questions
    val correctCount = QuizSummary.correctCount(questions, answers)
    val total = questions.size
    val fraction = QuizSummary.fraction(correctCount, total)
    val mistakes = remember(answers) { QuizSummary.mistakes(questions, answers) }
    val next = QuizSummary.next(isUnsaved, saved, mistakes.isNotEmpty(), mistakesSaved)

    fun saveMistakes(): StudySet? {
        val name = QuizSummary.mistakesName(set.name)
        val existing = store.library.firstOrNull { it.kind == StudySetKind.MCQ && it.name == name }
        val made = if (existing != null) QuizSummary.addMistakes(existing, mistakes, set).copy(updatedAt = System.currentTimeMillis())
        else QuizSummary.addMistakes(StudySet(name = name, subject = set.subject, kind = StudySetKind.MCQ, folderId = set.folderId), mistakes, set)
        return runCatching { if (existing != null) store.updateSet(made) else store.addSet(made) }.map {
            haptic.performHapticFeedback(HapticFeedbackType.Confirm)
            mistakesSaved = true
            made
        }.getOrNull()
    }

    Column(Modifier.fillMaxSize()) {
        Text("Results", Modifier.fillMaxWidth().padding(vertical = 12.dp).semantics { heading() }, textAlign = TextAlign.Center,
            fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = wardColor(WardToken.ink))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            WardCardFace(Modifier.fillMaxWidth()) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    ScoreRing(fraction)
                    Text("$correctCount of $total right", Modifier.semantics { heading() }, fontSize = 28.sp, fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center, color = wardColor(WardToken.ink))
                    Text(QuizSummary.verdict(fraction), fontSize = 17.sp, textAlign = TextAlign.Center, color = wardColor(WardToken.inkSecondary))
                }
            }

            if (isUnsaved && saved) Done("Saved to library")
            if (mistakesSaved) Done("In your library as “Mistakes”")
            if (onRetake != null) QuizBigButton("Try again", Icons.Rounded.Refresh, QuizButtonKind.secondary, onClick = onRetake,
                modifier = Modifier.fillMaxWidth(), label = "Try this set again")

            WardCardFace(Modifier.fillMaxWidth()) {
                WardSmallCapsText("Your answers", Modifier.semantics { heading() })
                questions.indices.forEach { i ->
                    val q = questions[i]
                    val correct = QuizSummary.isRight(questions, answers, i)
                    Row(Modifier.fillMaxWidth().padding(vertical = 12.dp).semantics(mergeDescendants = true) {},
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(if (correct) Icons.Rounded.CheckCircle else Icons.Rounded.Cancel, if (correct) "Right" else "Wrong",
                            tint = if (correct) wardColor(WardToken.success) else wardColor(WardToken.danger), modifier = Modifier.size(24.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(q.stem, fontSize = 17.sp, color = wardColor(WardToken.ink))
                            val key = q.options.getOrNull(q.correctIndex)
                            if (!correct && key != null) Text("Answer: $key", fontSize = 15.sp, fontWeight = FontWeight.Medium,
                                color = wardColor(WardToken.success))
                        }
                    }
                    if (i < questions.lastIndex) HorizontalDivider(color = wardColor(WardToken.hairline))
                }
            }
        }

        // the bar: the one main button, and Done beside it whenever that is not Done already
        Row(Modifier.fillMaxWidth().background(wardColor(WardToken.raised)).padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (next != QuizSummary.Next.done) QuizBigButton("Done", null, QuizButtonKind.companion, onClick = onDone)
            when (next) {
                QuizSummary.Next.save -> QuizBigButton("Save to library", Icons.Rounded.Download, QuizButtonKind.primary, onClick = onSave,
                    modifier = Modifier.weight(1f))
                QuizSummary.Next.practise -> QuizBigButton("Practise mistakes (${mistakes.size})", Icons.Rounded.Replay, QuizButtonKind.primary,
                    onClick = { saveMistakes()?.let(onOpen) }, modifier = Modifier.weight(1f))
                QuizSummary.Next.done -> QuizBigButton("Done", null, QuizButtonKind.primary, onClick = onDone, modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable private fun Done(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(Icons.Rounded.Check, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
        Text(text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = wardColor(WardToken.inkSecondary))
    }
}

/** The score as a ring filling to the fraction, the percentage counting up as it fills, "correct" under it. */
@Composable private fun ScoreRing(fraction: Double) {
    var started by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { started = true }
    val target = (fraction * 100).roundToInt()
    val shown by animateIntAsState(if (started) target else 0, tween(900), label = "score")
    val track = wardColor(WardToken.hairline)
    val fill = wardColor(WardToken.primaryInk)
    Box(Modifier.size(140.dp).clearAndSetSemantics { contentDescription = "$target% correct" }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize().padding(8.dp)) {
            val stroke = Stroke(width = 12.dp.toPx(), cap = StrokeCap.Round)
            drawArc(track, 0f, 360f, false, style = stroke)
            drawArc(fill, -90f, 360f * shown / 100f, false, style = stroke)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("$shown%", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = wardColor(WardToken.ink))
            Text("correct", fontSize = 13.sp, color = wardColor(WardToken.inkSecondary))
        }
    }
}
