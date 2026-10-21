package com.stethoscore.app.ui.learn

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.WbTwilight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.mock.BigButton
import com.stethoscore.app.ui.mock.BigKind
import com.stethoscore.app.ui.mock.QuestionPick
import com.stethoscore.app.ui.mock.StudyActionBar
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.wardColor

// A port of ios/RedPen/Features/Learn/BedtimeReviewView.swift.
//
// Bedtime lock-in: a calm re-read of today's misses, each as the answer and
// one line to remember. Not a test - nothing to tap, nothing scored. Dim and
// large, and the whole sheet is drawn dark whatever the phone's setting
// (LearnSheet holds it dark). Tomorrow morning's check asks the same items.
// The line is the explanation's first sentence: Android has no rule sheet yet.

@Composable internal fun BedtimeReviewScreen(store: StudyStore) {
    val picks = remember(LearnRouter.version) { LearnLibrary.bedtimePicks(store) }
    Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 640.dp).fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Today’s misses", style = WardTextStyle.largeTitle.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
                Text(subtitle(picks.size), style = WardTextStyle.title3.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            for (pick in picks) BedtimeItem(pick)
            Text("That’s all. Good night — tomorrow morning, two minutes on these.",
                style = WardTextStyle.title3.textStyle(), color = wardColor(WardToken.inkSecondary))
            WardTextButton("Good night", { LearnRouter.close() }, kind = WardButtonKind.secondary)
        }
    }
}

private fun subtitle(count: Int): String {
    if (count == 0) return "Nothing missed today. Sleep well."
    val plural = if (count == 1) "" else "es"
    return "$count miss$plural, with the answer. Just read them."
}

@Composable private fun BedtimeItem(pick: QuestionPick) {
    val q = pick.question
    val answer = if (q.correctIndex in q.options.indices) q.options[q.correctIndex] else ""
    val line = firstSentence(q.explanation)
    Column(Modifier.padding(vertical = 4.dp).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(q.stem, style = WardType.body.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 4, overflow = TextOverflow.Ellipsis)
        Text(answer, style = WardTextStyle.title2.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
        if (line.isNotEmpty()) Text(line, style = WardTextStyle.title3.textStyle(), color = wardColor(WardToken.ink).copy(alpha = 0.85f))
    }
}

/** The morning check: yesterday's misses, re-asked, before anything new. Two minutes - at most ten questions. */
@Composable internal fun MorningCheckScreen(store: StudyStore) {
    val count = remember(LearnRouter.version) { minOf(10, LearnLibrary.morningPicks(store).size) }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically)) {
            Icon(Icons.Rounded.WbTwilight, null, Modifier.size(52.dp), tint = wardColor(WardToken.beam))
            Text("Morning check", style = WardTextStyle.largeTitle.textStyle(WardWeight.bold), color = wardColor(WardToken.ink))
            Text(morningNote(count), Modifier.widthIn(max = 480.dp), style = WardType.body.textStyle(),
                color = wardColor(WardToken.inkSecondary), textAlign = TextAlign.Center)
        }
        StudyActionBar {
            if (count > 0) BigButton("Start", Icons.Rounded.PlayArrow, BigKind.primary, {
                LearnMarks.markMorningDone()
                LearnRouter.push(LearnPush.Quiz(LearnLibrary.morningCheckQuiz(store)))
            })
            else BigButton("Done", null, BigKind.secondary, { LearnRouter.close() })
        }
    }
}

private fun morningNote(count: Int): String {
    if (count == 0) return "Nothing from yesterday to re-ask. On with the day."
    val plural = if (count == 1) "" else "s"
    return "$count question$plural you missed yesterday. About two minutes, before anything new — asking again after a night’s sleep is what fixes them."
}
