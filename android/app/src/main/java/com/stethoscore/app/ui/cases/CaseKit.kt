package com.stethoscore.app.ui.cases

import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.CaseChart
import com.stethoscore.app.data.CaseFile
import com.stethoscore.app.data.CaseRun
import com.stethoscore.app.data.CaseStep
import com.stethoscore.app.ui.SectionLabel
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardSegmented
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.wardInset
import com.stethoscore.app.ui.wardColor

// What the Cases screens add to the Ward kit: port of iOS Features/Cases/CaseKit.swift.
// The card is WardCardFace, the avatar and the clock are pressed in (wardInset),
// a chip is WardChip, the choices WardSegmented and the buttons WardButtonBox,
// under the Cases screens' own names so the screens keep what they say.

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

/** A card, full width (iOS caseCard over wardCard): raised off the base. */
@Composable
internal fun CaseCard(modifier: Modifier = Modifier, padding: Dp = 16.dp, spacing: Dp = 10.dp, content: @Composable ColumnScope.() -> Unit) {
    WardCardFace(modifier.fillMaxWidth(), padding = padding, spacing = spacing, content = content)
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
        Modifier.size(size).wardInset(CircleShape).clearAndSetSemantics { },
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
        // pressed in, like the kit's timer pill: read, not touched
        Modifier.wardInset(CircleShape).padding(horizontal = 10.dp, vertical = 5.dp)
            .clearAndSetSemantics { contentDescription = spoken },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(if (over) Icons.Filled.Error else Icons.Filled.Schedule, null, tint = tint, modifier = Modifier.size(16.dp))
        Text(if (used == 0) "$budget min" else "$used / $budget min", fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, color = tint)
    }
}

internal enum class CaseTone { blue, grey, warning, green }

/** A small capsule of text in a tone: the kit's WardChip. */
@Composable
internal fun CaseChip(text: String, tone: CaseTone) {
    WardChip(text, tone = when (tone) {
        CaseTone.blue -> WardTone.Blue
        CaseTone.grey -> WardTone.Grey
        CaseTone.warning -> WardTone.Warning
        CaseTone.green -> WardTone.Green
    })
}

/** The state chip on a patient's card (WardChip). */
@Composable
internal fun CaseStateChip(state: CaseRun.State) = when (state) {
    CaseRun.State.New -> WardChip("New", tone = WardTone.Blue)
    CaseRun.State.Seen -> WardChip("Seen", tone = WardTone.Warning)
    is CaseRun.State.Discharged -> WardChip("Discharged · ${state.score}", tone = WardTone.Green)
}

/**
 * The kit's buttons as on iOS: .bigPrimary and .wardSecondary, both
 * WardButtonBox, raised capsules whose kind shows in their words (the
 * section's ink, Chart Ink), never a fill or an outline.
 */
@Composable
internal fun CaseButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, primary: Boolean = false, enabled: Boolean = true,
                        icon: androidx.compose.ui.graphics.vector.ImageVector? = null) {
    WardButtonBox(onClick, modifier, kind = if (primary) WardButtonKind.primary else WardButtonKind.secondary, enabled = enabled) {
        if (icon != null) Icon(icon, null, Modifier.size(18.dp))
        Text(text)
    }
}

/** Two or more choices side by side, one chosen: the kit's WardSegmented. */
@Composable
internal fun <T> CaseSegmented(selection: T, options: List<T>, label: (T) -> String, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    WardSegmented(selection, options, onSelect, modifier.fillMaxWidth()) { option, style, color ->
        Text(label(option), style = style, color = color, maxLines = 1)
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
