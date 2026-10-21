package com.stethoscore.app.ui

import com.stethoscore.app.ui.ward.wardRaised
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.quiz.PatientChart
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRelief
import com.stethoscore.app.ui.ward.WardToken

// A port of upstream/ios/RedPen/Features/MCQ/ChartQuizViews.swift: the
// question screen's pieces - the option row, and the chart's chips, vitals
// grid and results table - plus the few Ward controls the question screens
// need. What each shows is decided, and tested, in quiz/ChartQuiz.kt.
//
// The Ward surfaces and controls (WardPressFace, WardChipButtonStyle,
// .bigPrimary and the rest) are being ported in batches 2 and 3; until they
// land these are plain Compose in the Ward palette's colours: a raised face is
// Theme.kt's relief on the surface, a pressed one the well with the section's
// edge, a flat one its fill and ring alone.

/** How a Ward face sits: raised off the base, pressed into it, or flat on it. */
internal enum class QuizFace { raised, pressed, flat }

/** A face in the Ward colours, in plain Compose (WardPressFace's stand-in). */
@Composable internal fun Modifier.quizFace(face: QuizFace, shape: Shape, radius: Float, fill: Color? = null, edge: Color? = null, lift: WardLift = WardLift.mid): Modifier {
    val dark = LocalWardDark.current
    val ring = edge ?: wardInk().copy(alpha = WardRelief.edgeAlpha(dark).toFloat() * 0.6f)
    return when (face) {
        QuizFace.raised -> this.wardRaised(radius.toDouble(), lift = lift).background(fill ?: wardColor(WardToken.surface), shape)
        QuizFace.pressed -> this.background(fill ?: wardColor(WardToken.well), shape).border(1.5.dp, ring, shape)
        QuizFace.flat -> this.background(fill ?: wardColor(WardToken.surface), shape).border(1.dp, ring, shape)
    }
}

/** The tone of a small Ward chip (WardChip). */
internal enum class QuizTone { grey, blue, warning }

/** A small label chip: "optional", "Best answer", "34 y" (WardChip). */
@Composable internal fun QuizTag(text: String, tone: QuizTone) {
    val ink = when (tone) {
        QuizTone.grey -> wardColor(WardToken.inkSecondary)
        QuizTone.blue -> wardColor(WardToken.primaryInk)
        QuizTone.warning -> wardColor(WardToken.warning)
    }
    Text(text, Modifier.background(ink.copy(alpha = 0.12f), CircleShape).padding(horizontal = 8.dp, vertical = 3.dp),
        color = ink, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
}

/**
 * A chip that is a button (WardChipButtonStyle): 44 points tall, quiet, so it
 * never looks like the main button; chosen, it is pressed in and in the
 * section's colour (or Caution Amber for Flag and Hint).
 */
@Composable internal fun QuizChip(text: String?, icon: ImageVector?, on: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier,
                                  warning: Boolean = false, enabled: Boolean = true, label: String? = null) {
    val ink = when {
        !enabled && !on -> wardColor(WardToken.inkSecondary)
        on -> if (warning) wardColor(WardToken.warning) else wardColor(WardToken.primaryInk)
        else -> wardColor(WardToken.ink)
    }
    val shape = CircleShape
    Row(modifier.heightIn(min = 44.dp)
        .quizFace(if (on) QuizFace.pressed else QuizFace.raised, shape, 22f, lift = WardLift.low)
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
        .semantics { selected = on; if (label != null) contentDescription = label }
        .padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (icon != null) Icon(icon, null, tint = ink, modifier = Modifier.size(18.dp))
        if (text != null) Text(text, color = ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/** The bar's buttons (.bigPrimary, .bigCompanion, .bigSecondary): the main one filled in the section's colour. */
internal enum class QuizButtonKind { primary, companion, secondary }

@Composable internal fun QuizBigButton(text: String?, icon: ImageVector?, kind: QuizButtonKind, onClick: () -> Unit, modifier: Modifier = Modifier,
                                       enabled: Boolean = true, label: String? = null) {
    val shape = RoundedCornerShape(16.dp)
    val primary = kind == QuizButtonKind.primary
    // a disabled Ward button goes Biro Grey
    val ink = when {
        !enabled -> wardColor(WardToken.inkSecondary)
        primary -> wardColor(WardToken.onPrimary)
        else -> wardColor(WardToken.primaryInk)
    }
    val face = when {
        primary && enabled -> Modifier.wardRaised(16.0).background(wardColor(WardToken.primary), shape)
        primary -> Modifier.quizFace(QuizFace.pressed, shape, 16f)
        else -> Modifier.quizFace(QuizFace.raised, shape, 16f, lift = WardLift.low)
    }
    Row(modifier.heightIn(min = 52.dp).then(face).clickable(enabled = enabled, role = Role.Button, onClick = onClick)
        .semantics { if (label != null) contentDescription = label }
        .padding(horizontal = 18.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
        if (icon != null) Icon(icon, null, tint = ink, modifier = Modifier.size(20.dp))
        if (text != null) Text(text, color = ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** A card on the base (.contentCard). */
@Composable internal fun QuizCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().quizFace(QuizFace.raised, RoundedCornerShape(20.dp), 20f).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
}

/** Small caps over a part of a card (wardSmallCaps), read as a heading. */
@Composable internal fun QuizSmallCaps(text: String) {
    Text(text.uppercase(), Modifier.semantics { heading() }, fontSize = 12.sp, letterSpacing = 1.2.sp, fontWeight = FontWeight.Bold,
        color = wardColor(WardToken.inkSecondary))
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
    val face = when {
        mark == ChartQuiz.Mark.wrong -> Modifier.quizFace(QuizFace.flat, shape, 16f, fill = wardColor(WardToken.faded), edge = faded)
        mark == ChartQuiz.Mark.chosen -> Modifier.quizFace(QuizFace.pressed, shape, 16f)
        mark == ChartQuiz.Mark.right -> Modifier.quizFace(QuizFace.pressed, shape, 16f, edge = wardInk())
        else -> Modifier.quizFace(QuizFace.raised, shape, 16f, lift = if (ChartQuiz.liesLow(struck, mark)) WardLift.low else WardLift.mid)
    }
    Row(modifier.fillMaxWidth().heightIn(min = 56.dp).then(face).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(letter, Modifier.clearAndSetSemantics {}, color = letterInk, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
        Text(text, Modifier.weight(1f), color = textInk, fontSize = 16.sp,
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
        chips.forEach { QuizTag(it, QuizTone.grey) }
    }
}

/** The vital signs as observations on a Ward White panel: monospaced values, one high or low in Resus Red with its arrow. */
@OptIn(ExperimentalLayoutApi::class)
@Composable fun ChartVitalsGrid(vitals: List<PatientChart.Vital>) {
    FlowRow(Modifier.fillMaxWidth().background(wardColor(WardToken.background), RoundedCornerShape(12.dp)).padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        vitals.forEach { v ->
            val danger = ChartQuiz.tone(v.flag) == ChartQuiz.Tone.danger
            val arrow = when (v.flag) { PatientChart.Flag.high -> " ↑"; PatientChart.Flag.low -> " ↓"; null -> "" }
            Column(Modifier.widthIn(min = 92.dp).clearAndSetSemantics { contentDescription = ChartQuiz.spoken(v) }) {
                Text(v.label.uppercase(), fontSize = 11.sp, letterSpacing = 1.sp, fontWeight = FontWeight.Bold, color = wardColor(WardToken.inkSecondary))
                Text(v.value + arrow, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, fontSize = 17.sp,
                    color = if (danger) wardColor(WardToken.danger) else wardColor(WardToken.ink))
            }
        }
    }
}

/** The results as a monospaced table - name, value, unit, H or L - with a flagged value and its letter in Resus Red. Each row is read whole. */
@Composable fun ChartLabsTable(labs: List<PatientChart.Lab>) {
    Column(Modifier.fillMaxWidth().background(wardColor(WardToken.background), RoundedCornerShape(12.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        labs.forEach { lab ->
            val value = if (ChartQuiz.tone(lab.flag) == ChartQuiz.Tone.danger) wardColor(WardToken.danger) else wardColor(WardToken.ink)
            Row(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = ChartQuiz.spoken(lab) }, horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Bottom) {
                Text(lab.name, Modifier.weight(1f), fontFamily = FontFamily.Monospace, fontSize = 15.sp, color = wardColor(WardToken.ink))
                Text(lab.value, fontFamily = FontFamily.Monospace, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = value)
                Text(lab.unit, Modifier.widthIn(min = 64.dp), fontFamily = FontFamily.Monospace, fontSize = 15.sp, color = wardColor(WardToken.inkSecondary))
                Text(lab.flag?.rawValue ?: "", Modifier.width(14.dp), fontFamily = FontFamily.Monospace, fontSize = 15.sp, fontWeight = FontWeight.Bold,
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
