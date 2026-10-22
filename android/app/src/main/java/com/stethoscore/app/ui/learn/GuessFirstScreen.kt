package com.stethoscore.app.ui.learn

import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.Pretest
import com.stethoscore.app.data.StudyRhythm
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.quiz.SpokenText
import com.stethoscore.app.ui.mock.BigButton
import com.stethoscore.app.ui.mock.BigKind
import com.stethoscore.app.ui.mock.ContentCard
import com.stethoscore.app.ui.ward.StudyActionBar
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardRelief
import com.stethoscore.app.ui.wardColor

// A port of ios/RedPen/Features/Learn/GuessFirstView.swift: five quick
// questions the first time a textbook or narrate set is opened, before any
// reading. Skippable, and wrong guesses are the point - trying first and
// then seeing the answer makes the reading stick better. The questions come
// from the set's own text (Pretest). Nothing is recorded in the answer
// history: these are guesses, not a measure of anything. Not ported: a
// deck's pretest from its own cards (QuizFromCards), as decks are not
// offered one (GuessFirst.offers).

@Composable internal fun GuessFirstScreen(set: StudySet) {
    val questions = remember(set.id) { GuessFirst.questions(set) }
    var started by remember { mutableStateOf(false) }
    var index by remember { mutableIntStateOf(0) }
    var picked by remember { mutableStateOf<Int?>(null) }
    var right by remember { mutableIntStateOf(0) }
    LaunchedEffect(set.id) { LearnMarks.markPretestSeen(set.id) }
    val dismiss: () -> Unit = { LearnRouter.close() }
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), contentAlignment = Alignment.TopCenter) {
            Column(Modifier.widthIn(max = 640.dp).fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                when {
                    questions.isEmpty() -> Text("Nothing to ask from this one yet.", style = WardType.body.textStyle(),
                        color = wardColor(WardToken.inkSecondary))
                    !started -> Intro(questions.size, set.name)
                    index < questions.size -> Question(questions[index], index, questions.size, picked) { i ->
                        if (picked == null) {
                            picked = i
                            if (i == questions[index].correctIndex) right++
                        }
                    }
                    else -> Finish(right, questions.size)
                }
            }
        }
        StudyActionBar {
            when {
                questions.isEmpty() || index >= questions.size -> BigButton("Start reading", null, BigKind.primary, dismiss)
                !started -> Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    BigButton("Skip", null, BigKind.companion, dismiss)
                    BigButton("Guess", null, BigKind.primary, { started = true }, Modifier.weight(1f))
                }
                else -> Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    BigButton("Skip", null, BigKind.companion, dismiss)
                    BigButton(if (index + 1 < questions.size) "Next" else "Done", null, BigKind.primary, {
                        picked = null
                        index++
                    }, Modifier.weight(1f), enabled = picked != null)
                }
            }
        }
    }
}

@Composable private fun Intro(count: Int, name: String) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Take a guess", style = WardTextStyle.largeTitle.textStyle(WardWeight.bold), color = wardColor(WardToken.ink))
        Text("$count quick questions on $name, before you read it. It’s fine to be wrong.",
            style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
        Text(Pretest.why, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
    }
}

@Composable private fun Question(q: MCQQuestion, index: Int, count: Int, picked: Int?, pick: (Int) -> Unit) {
    val view = LocalView.current
    // "Correct." or "Incorrect. The answer is B: ..." for TalkBack, as the marks appear
    LaunchedEffect(q, picked) {
        val chosen = picked ?: return@LaunchedEffect
        val slot = q.correctIndex
        val known = slot in q.options.indices
        @Suppress("DEPRECATION")
        view.announceForAccessibility(SpokenText.answerResult(chosen == slot, if (known) StudyRhythm.letter(slot) else "",
            if (known) q.options[slot] else ""))
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("${index + 1} of $count", style = WardTextStyle.caption.textStyle(WardWeight.semibold, mono = true),
            color = wardColor(WardToken.inkSecondary))
        Text(q.stem, style = WardTextStyle.title3.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
        q.options.forEachIndexed { i, text -> OptionButton(q, i, text, picked) { pick(i) } }
        if (picked != null) ContentCard {
            Text(q.explanation, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}

@Composable private fun OptionButton(q: MCQQuestion, i: Int, text: String, picked: Int?, onPick: () -> Unit) {
    val answered = picked != null
    val isRight = i == q.correctIndex
    val isPicked = picked == i
    val wrongTint = if (isPicked) wardColor(WardToken.danger) else wardColor(WardToken.inkSecondary)
    val tint = if (!answered) wardColor(WardToken.inkSecondary) else if (isRight) wardColor(WardToken.success) else wrongTint
    // once answered, the right one and the pick are pressed into the base, their marks in green and red
    val marked = answered && (isRight || isPicked)
    // a wrong answer is faded grey
    val words = if (answered && !isRight) wardColor(WardToken.inkSecondary) else wardColor(WardToken.ink)
    val letter = StudyRhythm.letter(i)
    Row(Modifier.fillMaxWidth()
        .clickable(enabled = !answered, role = Role.Button, onClick = onPick)
        .semantics {
            contentDescription = "$letter: $text"
            stateDescription = SpokenText.optionState(answered, isRight, isPicked)
            selected = isPicked
        }
        .wardRelief(pressed = marked, radius = WardRadius.button, lift = WardLift.mid)
        .heightIn(min = 48.dp)
        .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        when {
            !answered -> LetterMark(letter.lowercase(), tint)
            isRight -> Icon(Icons.Rounded.CheckCircle, null, Modifier.size(24.dp), tint = tint)
            isPicked -> Icon(Icons.Rounded.Cancel, null, Modifier.size(24.dp), tint = tint)
            else -> Icon(Icons.Rounded.RadioButtonUnchecked, null, Modifier.size(24.dp), tint = tint)
        }
        Text(text, Modifier.weight(1f), style = WardType.body.textStyle(), color = words)
    }
}

/** A letter in a ring (SF Symbols' "a.circle"). */
@Composable private fun LetterMark(letter: String, tint: Color) {
    Box(Modifier.size(24.dp).padding(2.dp).border(1.5.dp, tint, CircleShape), contentAlignment = Alignment.Center) {
        Text(letter, style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = tint)
    }
}

@Composable private fun Finish(right: Int, count: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("$right of $count", style = WardTextStyle.largeTitle.textStyle(WardWeight.bold, mono = true), color = wardColor(WardToken.ink))
        Text("Whatever the score, you now know what to look out for. Watch for these as you read.",
            style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
    }
}
