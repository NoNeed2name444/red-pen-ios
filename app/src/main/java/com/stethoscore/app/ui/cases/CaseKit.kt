package com.stethoscore.app.ui.cases

import android.view.View
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.data.CaseChart
import com.stethoscore.app.data.CaseFile
import com.stethoscore.app.data.CaseRun
import com.stethoscore.app.data.CaseStep
import com.stethoscore.app.ui.SectionLabel
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.wardColor

// What the Cases screens add to the Ward look: port of iOS Features/Cases/CaseKit.swift.
// The Ward surfaces and controls (WardChip, WardSegmented, WardOptionRow, the
// raised and inset faces) are ported by their own batches; until they land
// here these are plain Compose drawn in the Ward palette's colours, so the
// screens can move onto the Ward controls without changing what they say.

/** The Ward tokens as the Cases screens use them. */
internal object CaseInk {
    val theatre: Color @Composable get() = wardColor(WardToken.primaryInk)
    val resus: Color @Composable get() = wardColor(WardToken.danger)
    val discharge: Color @Composable get() = wardColor(WardToken.success)
    val caution: Color @Composable get() = wardColor(WardToken.warning)
    val biro: Color @Composable get() = wardColor(WardToken.inkSecondary)
    val surface: Color @Composable get() = wardColor(WardToken.surface)
    val ward: Color @Composable get() = wardColor(WardToken.background)
    val hairline: Color @Composable get() = wardColor(WardToken.hairline)
    val ink: Color @Composable get() = wardColor(WardToken.ink)
    val well: Color @Composable get() = wardColor(WardToken.well)
}

internal val CaseCardShape = RoundedCornerShape(16.dp)

/** A card, full width (iOS caseCard over wardCard). */
@Composable
internal fun CaseCard(modifier: Modifier = Modifier, padding: Dp = 16.dp, spacing: Dp = 10.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().background(CaseInk.surface, CaseCardShape).border(1.dp, CaseInk.hairline, CaseCardShape).padding(padding),
        verticalArrangement = Arrangement.spacedBy(spacing), content = content,
    )
}

/** A small heading in the kit's small capitals, read as a heading. */
@Composable
internal fun CaseLabel(text: String, modifier: Modifier = Modifier) {
    Box(modifier.semantics { heading() }) { SectionLabel(text) }
}

/** The initials in a circle pressed into the card, for the patient. */
@Composable
internal fun CaseAvatar(initials: String, size: Dp = 44.dp) {
    Box(
        Modifier.size(size).background(CaseInk.well, CircleShape).border(1.dp, CaseInk.hairline, CircleShape).clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) { Text(initials, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = CaseInk.theatre) }
}

/**
 * The case's clock: minutes used of the budget, in a mono face, pressed in
 * like the kit's timer pill. Resus Red once past the budget, which the
 * student may go beyond (the debrief counts it).
 */
@Composable
internal fun CaseClockPill(used: Int, budget: Int) {
    val over = used > budget
    val spoken = when {
        used == 0 -> "Time allowed: $budget minutes"
        over -> "Clock: $used minutes used, ${used - budget} over the $budget allowed"
        else -> "Clock: $used of $budget minutes used"
    }
    val tint = if (over) CaseInk.resus else CaseInk.ink
    Row(
        Modifier.background(CaseInk.well, CircleShape).border(1.dp, CaseInk.hairline, CircleShape).padding(horizontal = 10.dp, vertical = 5.dp)
            .clearAndSetSemantics { contentDescription = spoken },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(if (over) Icons.Filled.Error else Icons.Filled.Schedule, null, tint = tint, modifier = Modifier.size(16.dp))
        Text(if (used == 0) "$budget min" else "$used / $budget min", fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, color = tint)
    }
}

internal enum class CaseTone { blue, grey, warning, green }

/** A small capsule of text in a tone (the kit's WardChip, drawn plainly). */
@Composable
internal fun CaseChip(text: String, tone: CaseTone) {
    val colour = when (tone) {
        CaseTone.blue -> CaseInk.theatre
        CaseTone.grey -> CaseInk.biro
        CaseTone.warning -> CaseInk.caution
        CaseTone.green -> CaseInk.discharge
    }
    Text(
        text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colour,
        modifier = Modifier.background(colour.copy(alpha = 0.12f), CircleShape).padding(horizontal = 9.dp, vertical = 3.dp),
    )
}

/** The state chip on a patient's card. */
@Composable
internal fun CaseStateChip(state: CaseRun.State) = when (state) {
    CaseRun.State.New -> CaseChip("New", CaseTone.blue)
    CaseRun.State.Seen -> CaseChip("Seen", CaseTone.warning)
    is CaseRun.State.Discharged -> CaseChip("Discharged · ${state.score}", CaseTone.green)
}

/** The kit's primary and secondary buttons, as full-height capsules. */
@Composable
internal fun CaseButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, primary: Boolean = false, enabled: Boolean = true,
                        icon: androidx.compose.ui.graphics.vector.ImageVector? = null) {
    val content: @Composable RowScope.() -> Unit = {
        if (icon != null) { Icon(icon, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
    }
    if (primary) {
        Button(onClick, modifier.heightIn(min = 50.dp), enabled = enabled, shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = wardColor(WardToken.primary), contentColor = wardColor(WardToken.onPrimary)), content = content)
    } else {
        OutlinedButton(onClick, modifier.heightIn(min = 50.dp), enabled = enabled, shape = CircleShape,
            border = BorderStroke(1.dp, CaseInk.hairline), colors = ButtonDefaults.outlinedButtonColors(contentColor = CaseInk.theatre), content = content)
    }
}

/** Two or more choices side by side, one chosen (the kit's WardSegmented). */
@Composable
internal fun <T> CaseSegmented(selection: T, options: List<T>, label: (T) -> String, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().background(CaseInk.well, CircleShape).padding(3.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        for (option in options) {
            val chosen = option == selection
            Box(
                Modifier.weight(1f).heightIn(min = 44.dp)
                    .background(if (chosen) CaseInk.surface else Color.Transparent, CircleShape)
                    .clickable(role = Role.Tab) { onSelect(option) }
                    .semantics { selected = chosen },
                contentAlignment = Alignment.Center,
            ) { Text(label(option), fontWeight = if (chosen) FontWeight.SemiBold else FontWeight.Normal, color = if (chosen) CaseInk.ink else CaseInk.biro) }
        }
    }
}

internal enum class CaseMark { idle, chosen, right, wrong }

/** A lettered option (the kit's WardOptionRow). */
@Composable
internal fun CaseOptionRow(index: Int, text: String, mark: CaseMark, modifier: Modifier = Modifier) {
    val edge = when (mark) {
        CaseMark.idle -> CaseInk.hairline
        CaseMark.chosen -> CaseInk.theatre
        CaseMark.right -> CaseInk.discharge
        CaseMark.wrong -> CaseInk.resus
    }
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier.fillMaxWidth().heightIn(min = 44.dp).background(CaseInk.surface, shape).border(if (mark == CaseMark.idle) 1.dp else 2.dp, edge, shape).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(AccuracyItem.letter(index), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, color = if (mark == CaseMark.idle) CaseInk.biro else edge)
        Text(text, Modifier.weight(1f), fontSize = 15.sp)
        when (mark) {
            CaseMark.right -> Icon(Icons.Filled.CheckCircle, null, tint = CaseInk.discharge)
            CaseMark.wrong -> Icon(Icons.Filled.Cancel, null, tint = CaseInk.resus)
            CaseMark.chosen -> Icon(Icons.Filled.CheckCircle, null, tint = CaseInk.theatre)
            CaseMark.idle -> {}
        }
    }
}

/** The arrival observations in the chart's vitals grid, flagged H or L. */
@Composable
internal fun CaseVitalsGrid(obs: List<CaseFile.Obs>) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (o in obs) {
            val unit = when (o.sign) { CaseFile.Obs.Sign.temp -> " °C"; CaseFile.Obs.Sign.spo2 -> "%"; else -> "" }
            val flag = CaseChart.flag(o)
            val tint = if (flag != null) CaseInk.resus else CaseInk.ink
            Column(
                Modifier.widthIn(min = 86.dp).background(CaseInk.well, RoundedCornerShape(10.dp)).padding(horizontal = 10.dp, vertical = 6.dp)
                    .clearAndSetSemantics { contentDescription = "${o.sign.spoken} ${o.shown}${unit}" + (flag?.let { ", ${it.spoken}" } ?: "") },
            ) {
                Text(o.sign.label, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = CaseInk.biro)
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(o.shown + unit, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, color = tint)
                    if (flag != null) Text(flag.rawValue, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 12.sp, color = CaseInk.resus)
                }
            }
        }
    }
}

/** Test values in the chart's results table, flagged H or L. */
@Composable
internal fun CaseResultsTable(results: List<CaseStep.LabResult>) {
    Column(Modifier.fillMaxWidth().background(CaseInk.well, RoundedCornerShape(10.dp)).padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (r in results) {
            val flag = CaseChart.flag(r)
            Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { }, verticalAlignment = Alignment.CenterVertically) {
                Text(r.name, Modifier.weight(1f), fontSize = 14.sp)
                Text(CaseFile.Obs.number(r.value), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                    color = if (flag != null) CaseInk.resus else CaseInk.ink)
                Text(flag?.rawValue ?: "", Modifier.width(18.dp).padding(start = 4.dp), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 12.sp, color = CaseInk.resus)
                Text(r.unit, Modifier.widthIn(min = 64.dp).padding(start = 6.dp), fontSize = 12.sp, color = CaseInk.biro)
            }
        }
    }
}

/** A line read out by a screen reader (iOS's announcement). */
internal fun View.announce(text: String) {
    if (text.isNotEmpty()) announceForAccessibility(text)
}
