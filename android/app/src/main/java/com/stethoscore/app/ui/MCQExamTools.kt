package com.stethoscore.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.rounded.BorderColor
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.quiz.ExamCalculator
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.LabRanges
import com.stethoscore.app.quiz.LabUnits
import com.stethoscore.app.quiz.StemPieces
import com.stethoscore.app.ui.editors.EcgLoader
import com.stethoscore.app.ui.exam.WardUnitsPicker
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardChipButton
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.capPop
import com.stethoscore.app.ui.ward.wardDepth
import com.stethoscore.app.ui.ward.wardInset
import com.stethoscore.app.ui.ward.wardPressFace
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle

// A port of ios/RedPen/Features/MCQ/MCQExamTools.swift: the exam
// screen's tools, as the real test interfaces have them, for the question
// screen (and later the mock paper): the highlighter on the stem, the
// reference ranges sheet, the calculator and the attending's hint. Crossing
// out options lives with the option rows in MCQQuizScreen.kt. The logic is in
// quiz/ExamTools.kt.

/** Which of the tool sheets is open. */
enum class ExamToolSheet { labs, calculator }

/** The tools' items in the screen's More menu: the reference ranges, the calculator, and the highlighter switch. */
@Composable fun ExamToolMenuItems(track: ExamTrack, highlighting: Boolean, onSheet: (ExamToolSheet) -> Unit, onHighlight: () -> Unit) {
    val units = if (LabUnits.conventional(track)) "US units" else "SI units"
    MenuSection("Exam tools")
    DropdownMenuItem(text = { Text("Lab values ($units)") }, onClick = { onSheet(ExamToolSheet.labs) })
    DropdownMenuItem(text = { Text("Calculator") }, onClick = { onSheet(ExamToolSheet.calculator) })
    DropdownMenuItem(text = { Text(if (highlighting) "Stop highlighting" else "Highlight the stem") },
        leadingIcon = { Icon(Icons.Rounded.BorderColor, null) }, onClick = onHighlight)
}

/** A menu section's title, the one piece of text a menu reliably shows. */
@Composable internal fun MenuSection(title: String) {
    Text(title, Modifier.padding(horizontal = 16.dp, vertical = 8.dp).widthIn(max = 280.dp).semantics { heading() },
        style = WardType.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
}

/** The lab values and calculator sheets, opened from the More menu. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun ExamToolSheets(sheet: ExamToolSheet?, track: ExamTrack, onDismiss: () -> Unit) {
    if (sheet == null) return
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = wardColor(WardToken.raised)) {
        when (sheet) {
            ExamToolSheet.labs -> LabRangesSheet(track, onDismiss)
            ExamToolSheet.calculator -> CalculatorSheet(onDismiss)
        }
    }
}

@Composable private fun SheetTitle(title: String, onDone: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Spacer(Modifier.width(64.dp))
        Text(title, Modifier.weight(1f).semantics { heading() }, textAlign = TextAlign.Center, style = WardType.headline.textStyle())
        // iOS's .wardCompact Done
        WardButtonBox(onDone, Modifier.widthIn(min = 64.dp), kind = WardButtonKind.compact) { Text("Done", maxLines = 1) }
    }
}

// MARK: - the highlighter

/**
 * The stem, with the pieces the student marked drawn in highlighter amber.
 * While [highlighting] is on, each piece is its own button: a tap marks or
 * clears it.
 */
@Composable fun HighlightableStem(stem: String, plain: AnnotatedString, marked: Set<Int>, onMarked: (Set<Int>) -> Unit, highlighting: Boolean,
                                  style: TextStyle, prompt: Boolean = true) {
    val pieces = remember(stem) { StemPieces.split(stem) }
    val ink = wardColor(WardToken.beam).copy(alpha = 0.3f)
    if (highlighting) {
        val haptic = LocalHapticFeedback.current
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (prompt) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Rounded.BorderColor, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
                Text("Tap a phrase to highlight it", style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.inkSecondary))
            }
            pieces.forEachIndexed { index, piece ->
                val on = index in marked
                val fill = if (on) ink else wardColor(WardToken.inkSecondary).copy(alpha = 0.06f)
                Text(piece.trim(' ', '\t'), Modifier.fillMaxWidth().background(fill, RoundedCornerShape(8.dp))
                    .clickable(role = Role.Button, onClickLabel = if (on) "Removes the highlight" else "Highlights this phrase") {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onMarked(if (on) marked - index else marked + index)
                    }
                    .semantics { selected = on }
                    .padding(horizontal = 6.dp, vertical = 4.dp), style = style)
            }
        }
    } else if (marked.isEmpty()) {
        Text(plain, style = style)
    } else {
        Text(buildAnnotatedString {
            pieces.forEachIndexed { i, piece ->
                if (i in marked) { pushStyle(SpanStyle(background = ink)); append(piece); pop() } else append(piece)
            }
        }, style = style)
    }
}

// MARK: - the attending's hint

/** The hint, once asked for: the next step in the reasoning, never the answer. */
@Composable fun AttendingHintCard(text: String?) {
    WardCardFace(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Rounded.MedicalServices, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(18.dp))
            Text("Attending’s hint", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.primaryInk))
        }
        if (text != null) Text(text, style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
        else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            EcgLoader()
            Text("Thinking it through…", color = wardColor(WardToken.inkSecondary))
        }
    }
}

/** The small Hint button beside Flag: a Ward chip, 44 points tall, lit in Caution Amber once used. */
@Composable fun HintChip(used: Boolean, labelled: Boolean = true, action: () -> Unit) {
    WardChipButton(if (labelled) (if (used) "Hint shown" else "Hint") else null, action,
        Modifier.semantics { contentDescription = if (used) "Hint shown" else "Show a hint" },
        on = used, tone = WardTone.Warning, enabled = !used, icon = if (used) Icons.Rounded.Lightbulb else Icons.Outlined.Lightbulb,
        role = Role.Button)
}

// MARK: - reference ranges

@Composable fun LabRangesSheet(track: ExamTrack, onDone: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var conventional by remember { mutableStateOf(LabUnits.conventional(track)) }
    val found = remember(query) { LabRanges.search(query) }
    Column(Modifier.fillMaxWidth().fillMaxHeight(0.9f)) {
        SheetTitle("Lab values", onDone)
        LazyColumn(Modifier.fillMaxWidth(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item {
                // the units switch sits on the base itself, not on a tile
                WardUnitsPicker(conventional) { conventional = it }
            }
            item {
                OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(), placeholder = { Text("Search lab values") },
                    leadingIcon = { Icon(Icons.Rounded.Search, null) }, singleLine = true, shape = CircleShape)
            }
            item { Text(LabRanges.caveat, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary)) }
            LabRanges.groups.forEach { group ->
                val rows = found.filter { it.group == group }
                if (rows.isNotEmpty()) {
                    item(key = group) { WardSmallCapsText(group, Modifier.padding(top = 12.dp).semantics { heading() }) }
                    items(rows, key = { it.id }) { row ->
                        Row(Modifier.fillMaxWidth().wardRaised(12.0).padding(12.dp).semantics(mergeDescendants = true) {},
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(row.name, Modifier.weight(1f), color = wardColor(WardToken.ink))
                            // the body face with even figures, as iOS's monospacedDigit
                            Text(row.value(conventional), Modifier.weight(1f), textAlign = TextAlign.End,
                                style = WardType.body.textStyle().copy(fontFeatureSettings = "tnum"), color = wardColor(WardToken.inkSecondary))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - calculator

private enum class KeyRole { digit, function, op, equals, blank }

@Composable fun CalculatorSheet(onDone: () -> Unit) {
    val calc = remember { ExamCalculator() }
    // the calculator keeps its own state; this tells Compose it changed
    var shown by remember { mutableStateOf(calc.display to calc.pendingOp) }
    val haptic = LocalHapticFeedback.current
    fun press(action: ExamCalculator.() -> Unit) { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); calc.action(); shown = calc.display to calc.pendingOp }
    @Composable fun RowScope.key(title: String, role: KeyRole, chosen: Boolean = false, action: ExamCalculator.() -> Unit) {
        if (role == KeyRole.blank) { Spacer(Modifier.weight(1f).heightIn(min = 56.dp)); return }
        val ink = when (role) {
            KeyRole.equals, KeyRole.op -> wardColor(WardToken.primaryInk)
            KeyRole.function -> wardColor(WardToken.inkSecondary)
            else -> wardColor(WardToken.ink)
        }
        val shape = RoundedCornerShape(14.dp)
        // iOS's PopPressStyle: raised at mid, pressed in while held or while chosen (a pending operation)
        val source = remember { MutableInteractionSource() }
        val held by source.collectIsPressedAsState()
        Text(title, Modifier.weight(1f).heightIn(min = 56.dp).capPop(held).wardPressFace(shape, WardLift.mid, wardDepth(held || chosen))
            .clickable(source, indication = null, role = Role.Button) { press(action) }.semantics { selected = chosen }.wrapContentHeight(Alignment.CenterVertically),
            textAlign = TextAlign.Center, style = WardType.obsLarge.textStyle(), color = ink)
    }
    @Composable fun RowScope.opKey(op: ExamCalculator.Op) = key(op.rawValue, KeyRole.op, chosen = shown.second == op) { op(op) }
    Column(Modifier.fillMaxWidth()) {
        SheetTitle("Calculator", onDone)
        Column(Modifier.widthIn(max = 420.dp).align(Alignment.CenterHorizontally).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(shown.first, Modifier.fillMaxWidth().wardInset(RoundedCornerShape(20.dp), WardLift.mid).padding(horizontal = 16.dp, vertical = 12.dp)
                .semantics { contentDescription = "Display, ${shown.first}" }, textAlign = TextAlign.End, fontFamily = FontFamily.Monospace,
                fontSize = 40.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Clip, color = wardColor(WardToken.ink))
            val gap = Arrangement.spacedBy(10.dp)
            Row(horizontalArrangement = gap) { key("C", KeyRole.function) { clear() }; key("±", KeyRole.function) { negate() }; key("%", KeyRole.function) { percent() }; opKey(ExamCalculator.Op.divide) }
            for ((digits, op) in listOf(listOf(7, 8, 9) to ExamCalculator.Op.multiply, listOf(4, 5, 6) to ExamCalculator.Op.subtract, listOf(1, 2, 3) to ExamCalculator.Op.add)) {
                Row(horizontalArrangement = gap) { digits.forEach { d -> key(d.toString(), KeyRole.digit) { digit(d) } }; opKey(op) }
            }
            Row(horizontalArrangement = gap) { key("0", KeyRole.digit) { digit(0) }; key(".", KeyRole.digit) { dot() }; key("", KeyRole.blank) {}; key("=", KeyRole.equals) { equals() } }
            Spacer(Modifier.height(16.dp))
        }
    }
}
