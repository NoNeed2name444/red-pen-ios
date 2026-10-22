package com.stethoscore.app.ui

import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.quiz.PatientChart
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.wardDepth
import com.stethoscore.app.ui.ward.wardPressFace

// A port of ios/RedPen/Features/MCQ/ChartQuizViews.swift: the
// question screen's pieces - the option row, and the chart's chips, vitals
// grid and results table - plus the bar's buttons. What each shows is
// decided, and tested, in quiz/ChartQuiz.kt. The faces and controls are the
// Ward kit's (ui/ward): the option row stands on WardPressFace, a chip that
// is a button is WardChipButton, a label chip WardChip, a card WardCardFace.

/**
 * The bar's buttons (.bigPrimary, .bigCompanion, .bigSecondary), drawn by
 * WardButtonBox as on iOS: a capsule raised off the base, never a fill; the
 * primary stands a step higher and says its words in the section's ink, the
 * others in Chart Ink; a companion takes only the room its words need.
 */
internal enum class QuizButtonKind { primary, companion, secondary }

@Composable internal fun QuizBigButton(text: String?, icon: ImageVector?, kind: QuizButtonKind, onClick: () -> Unit, modifier: Modifier = Modifier,
                                       enabled: Boolean = true, label: String? = null) {
    WardButtonBox(onClick, modifier.then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier),
        kind = if (kind == QuizButtonKind.primary) WardButtonKind.primary else WardButtonKind.secondary,
        enabled = enabled, fills = kind != QuizButtonKind.companion) {
        if (icon != null) Icon(icon, null, Modifier.size(20.dp))
        if (text != null) Text(text, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * An answer option as a soft tile: a plain monospaced letter, then its text.
 * Chosen, the row is pressed into the base with letter and text in the
 * section's accent; once checked (the owner, 15 Oct: "the wrong should be
 * faded and what is right gets the color of the mode used"), the right one
 * is pressed in with its letter and check in the section's accent and its
 * ring in the section's ink, and a wrong pick lies flat on the faded face,
 * ringed, lettered, worded, struck and crossed in the faded ink, so it reads
 * as stepped back, never as lifted or as the right answer. Crossed out, it is
 * struck through and lies low, as do the options neither picked nor right
 * once checked: solid colours, never dimmed. For the quiz and the mock paper.
 */
@Composable fun WardOptionRow(letter: String, text: String, mark: ChartQuiz.Mark = ChartQuiz.Mark.idle, struck: Boolean = false, modifier: Modifier = Modifier) {
    val accent = wardColor(WardToken.primaryInk)
    val faded = wardColor(WardToken.fadedInk)
    val tone: Color? = when (mark) {
        ChartQuiz.Mark.chosen, ChartQuiz.Mark.right -> accent
        ChartQuiz.Mark.wrong -> faded
        ChartQuiz.Mark.idle, ChartQuiz.Mark.past -> null
    }
    val textInk = when (mark) {
        ChartQuiz.Mark.chosen -> accent
        ChartQuiz.Mark.wrong -> faded
        else -> wardColor(WardToken.ink)
    }
    val letterInk = tone ?: wardColor(WardToken.inkSecondary)
    val shape = RoundedCornerShape(16.dp)
    val wrong = mark == ChartQuiz.Mark.wrong
    // a wrong pick lies flat on the faded face, in the faded ink's ring, not
    // pressed in: its face is lighter than the cards at night, and a rim would lift it
    val face = Modifier.wardPressFace(shape,
        lift = if (wrong || ChartQuiz.liesLow(struck, mark)) WardLift.low else WardLift.mid,
        depth = wardDepth(mark == ChartQuiz.Mark.chosen || mark == ChartQuiz.Mark.right),
        fill = wardColor(if (wrong) WardToken.faded else WardToken.surface),
        flat = wrong, edge = if (wrong) faded else null)
    Row(modifier.fillMaxWidth().heightIn(min = 56.dp).then(face).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(letter, Modifier.clearAndSetSemantics {}, color = letterInk, style = WardTextStyle.callout.textStyle(WardWeight.semibold, mono = true))
        Text(text, Modifier.weight(1f), color = textInk, style = WardTextStyle.callout.textStyle(),
            textDecoration = if (struck || mark == ChartQuiz.Mark.wrong) TextDecoration.LineThrough else null)
        when (mark) {
            ChartQuiz.Mark.right -> Icon(Icons.Rounded.CheckCircle, null, tint = letterInk, modifier = Modifier.size(24.dp))
            ChartQuiz.Mark.wrong -> Icon(Icons.Rounded.Close, null, tint = letterInk, modifier = Modifier.size(16.dp))
            else -> {}
        }
    }
}

/** Who the patient is - "34 y", "Male", "3 wk" - in a row that wraps when large text leaves no room. */
@OptIn(ExperimentalLayoutApi::class)
@Composable fun ChartChipsRow(chips: List<String>) {
    FlowRow(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        chips.forEach { WardChip(it, tone = WardTone.Grey) }
    }
}

/** The vital signs as observations on a Ward White panel: monospaced values, one high or low in Resus Red with its arrow. */
@OptIn(ExperimentalLayoutApi::class)
@Composable fun ChartVitalsGrid(vitals: List<PatientChart.Vital>) {
    FlowRow(Modifier.fillMaxWidth().background(wardColor(WardToken.background), RoundedCornerShape(WardRadius.field.wardDp)).padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        vitals.forEach { v ->
            val danger = ChartQuiz.tone(v.flag) == ChartQuiz.Tone.danger
            val arrow = when (v.flag) { PatientChart.Flag.high -> " ↑"; PatientChart.Flag.low -> " ↓"; null -> "" }
            Column(Modifier.widthIn(min = 92.dp).clearAndSetSemantics { contentDescription = ChartQuiz.spoken(v) }) {
                WardSmallCapsText(v.label)
                Text(v.value + arrow, style = WardTextStyle.body.textStyle(WardWeight.semibold, mono = true),
                    color = if (danger) wardColor(WardToken.danger) else wardColor(WardToken.ink))
            }
        }
    }
}

/** The results as a monospaced table - name, value, unit, H or L - with a flagged value and its letter in Resus Red. Each row is read whole. */
@Composable fun ChartLabsTable(labs: List<PatientChart.Lab>) {
    Column(Modifier.fillMaxWidth().background(wardColor(WardToken.background), RoundedCornerShape(WardRadius.field.wardDp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        labs.forEach { lab ->
            val value = if (ChartQuiz.tone(lab.flag) == ChartQuiz.Tone.danger) wardColor(WardToken.danger) else wardColor(WardToken.ink)
            Row(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = ChartQuiz.spoken(lab) }, horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Bottom) {
                Text(lab.name, Modifier.weight(1f), style = WardTextStyle.subheadline.textStyle(mono = true), color = wardColor(WardToken.ink))
                Text(lab.value, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold, mono = true), color = value)
                Text(lab.unit, Modifier.widthIn(min = 64.dp), style = WardTextStyle.subheadline.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
                Text(lab.flag?.rawValue ?: "", Modifier.width(14.dp), style = WardTextStyle.subheadline.textStyle(WardWeight.bold, mono = true),
                    color = wardColor(WardToken.danger))
            }
        }
    }
}

/** A thin track filling in Pager Amber (ThinProgress). */
@Composable internal fun QuizStrip(fraction: Double, height: Dp = 4.dp) {
    Box(Modifier.fillMaxWidth().height(height).background(wardColor(WardToken.hairline), CircleShape)) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0.0, 1.0).toFloat()).fillMaxHeight().background(wardColor(WardToken.beam), CircleShape))
    }
}
