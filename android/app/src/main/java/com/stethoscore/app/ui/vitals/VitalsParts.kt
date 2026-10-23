package com.stethoscore.app.ui.vitals

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.BedPlan
import com.stethoscore.app.data.Readiness
import com.stethoscore.app.data.ReadinessEstimate
import com.stethoscore.app.data.RhythmReading
import com.stethoscore.app.quiz.MistakeReason
import com.stethoscore.app.ui.home.RhythmTrace
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardMonitorCard
import com.stethoscore.app.ui.ward.WardRing
import com.stethoscore.app.ui.ward.WardSmallCaps
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardAccessibilitySize
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.wardColor

// A port of ios/RedPen/Features/Analytics/VitalsParts.swift: the top
// of the Vitals screen - the study rhythm on a dark monitor, four rings, and
// the subjects that need a consult with the one button that treats them.
// VitalsScreen puts them above Focus next, readiness, trends, mistakes,
// subjects and time; the numbers are its own.

/**
 * The monitor, laid out like a bedside monitor (the owner, 22 Oct: "make it
 * like the monitor"): a status strip along the top - "Study rhythm · Sinus ·
 * Regular" on the left, the streak with its heart on the right - then the
 * screen, the last two weeks as a green trace (a beat for each day studied)
 * filling the channel on the left, and the parameter column on the right,
 * each readout its label over its big number in the parameter's colour,
 * parted by thin rules: readiness, accuracy, and questions today against the
 * day's target. A dark panel in both modes. At the accessibility text sizes
 * the column moves under the trace.
 */
@Composable fun RhythmMonitor(reading: RhythmReading.Reading, readiness: Double?, accuracy: Double?, today: Int, target: Int, streak: Int) {
    val spoken = remember(reading, readiness, accuracy, today, target, streak) {
        val parts = mutableListOf(reading.spoken)
        if (readiness != null) parts.add("Readiness ${percentOf(readiness)} percent")
        if (accuracy != null) parts.add("Accuracy ${percentOf(accuracy)} percent over 30 days")
        parts.add("$today of $target studied today")
        if (streak > 0) parts.add("$streak-day streak")
        parts.joinToString(". ")
    }
    // a List row: the bezel as low as the tiles round it. The panel is dark in both modes
    // (WardMonitorCard's held well), so everything on it takes the held (night) colours.
    WardMonitorCard(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = spoken }, lift = WardLift.low,
        spacing = WardSpace.m.wardDp) { MonitorPanel(reading, readiness, accuracy, today, target, streak) }
}

/** What the monitor's panel holds, top to bottom: the status strip, the screen, and the line saying what the trace means. */
@Composable internal fun MonitorPanel(reading: RhythmReading.Reading, readiness: Double?, accuracy: Double?, today: Int, target: Int, streak: Int) {
    // the status strip: what the trace is on the left, the beat on the right
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) { WardSmallCapsText("Study rhythm · " + reading.words, color = wardColor(WardSmallCaps.colour, held = true)) }
        MonitorStreak(streak)
    }
    MonitorScreen(reading, readiness, accuracy, today, target)
    Text(reading.line, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary, held = true))
}

/**
 * The monitor's screen: the trace's channel on the left, a thin rule, and the
 * parameter column on the right; at the accessibility text sizes the column
 * goes under the trace.
 */
@Composable internal fun MonitorScreen(reading: RhythmReading.Reading, readiness: Double?, accuracy: Double?, today: Int, target: Int) {
    if (wardAccessibilitySize()) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
            MonitorTrace(reading, Modifier.fillMaxWidth().height(MonitorChannel.channel.dp))
            MonitorReadouts(readiness, accuracy, today, target, Modifier.fillMaxWidth())
        }
    } else {
        // the trace and its rule as tall as the column beside them, at every text size
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp), verticalAlignment = Alignment.Top) {
            MonitorTrace(reading, Modifier.weight(1f).fillMaxHeight())
            Box(Modifier.width(1.dp).fillMaxHeight().background(wardColor(WardToken.hairline, held = true)))
            MonitorReadouts(readiness, accuracy, today, target, Modifier.width(MonitorChannel.column.dp))
        }
    }
}

/** The monitor's sizes in points and dp, as RhythmMonitor.channel and .column on iOS. */
object MonitorChannel {
    /** The trace's height when the column is under it (the largest text sizes); beside the column it is the column's height. */
    const val channel: Int = 112
    /** The parameter column's width. */
    const val column: Int = 112
}

/** "68%", or a dash with nothing to show (RhythmMonitor.percent). */
fun monitorPercent(value: Double?): String = if (value == null) "–" else percentText(value)

/** The trace in its channel: RhythmTrace in Discharge Green, its ECG Red stroke recoloured where it is drawn. */
@Composable private fun MonitorTrace(reading: RhythmReading.Reading, modifier: Modifier) {
    val green = wardColor(WardToken.success, held = true)
    RhythmTrace(reading.beats, modifier.testTag("rhythmTrace")
        .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
        .drawWithContent { drawContent(); drawRect(green, blendMode = BlendMode.SrcIn) })
}

/** The parameter column: each readout a label over its number, parted by thin rules. */
@Composable private fun MonitorReadouts(readiness: Double?, accuracy: Double?, today: Int, target: Int, modifier: Modifier) {
    val rule = wardColor(WardToken.hairline, held = true)
    Column(modifier.testTag("monitorReadouts"), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
        MonitorReading("RDY", monitorPercent(readiness), wardColor(WardToken.beam, held = true))
        Box(Modifier.fillMaxWidth().height(1.dp).background(rule))
        MonitorReading("ACC", monitorPercent(accuracy), wardColor(WardToken.success, held = true))
        Box(Modifier.fillMaxWidth().height(1.dp).background(rule))
        MonitorReading("Q/D", "$today/$target", wardColor(WardToken.onPrimary, held = true))
    }
}

@Composable private fun MonitorStreak(streak: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.Favorite, null, tint = wardColor(WardToken.ecg, held = true), modifier = Modifier.size(14.dp))
        Text(if (streak > 0) "$streak day streak" else "No streak yet", style = WardTextStyle.footnote.textStyle(WardWeight.semibold),
            color = wardColor(WardToken.ink, held = true))
    }
}

/** One parameter on the monitor: its label at the top left and its number large at the right, both in its colour. */
@Composable private fun MonitorReading(label: String, value: String, tint: androidx.compose.ui.graphics.Color) {
    Column(Modifier.fillMaxWidth()) {
        Text(label, style = WardTextStyle.caption2.textStyle(WardWeight.semibold), color = tint)
        Text(value, Modifier.fillMaxWidth(), style = WardType.obsLarge.textStyle(), color = tint, maxLines = 1,
            textAlign = TextAlign.End)
    }
}

/**
 * The four rings: Readiness (Pager Amber), Accuracy over 30 days (Discharge
 * Green), Syllabus covered (ECG Red) and Today against the day's target
 * (the section's accent). Each is a button into what is behind it. Four
 * across; two by two at the largest text sizes.
 */
@Composable fun VitalsRings(
    readiness: ReadinessEstimate?, accuracy: Double?, answered: Int, syllabus: Double?, syllabusSpoken: String,
    today: Int, target: Int, onReadiness: () -> Unit, onAccuracy: () -> Unit, onSyllabus: () -> Unit, onToday: () -> Unit,
) {
    val readinessSpoken = if (readiness != null)
        "estimated ${percentOf(readiness.center)} percent, pass mark about ${percentOf(readiness.passMark)} percent"
    else "answer at least ${Readiness.minimumAnswers} questions for an estimate"
    val accuracySpoken = if (accuracy != null) "${percentOf(accuracy)} percent of $answered answers right, last 30 days" else "no answers yet"
    val share = if (target > 0) today.toDouble() / target else 0.0
    val rings: List<Triple<String, () -> Unit, @Composable (Modifier) -> Unit>> = listOf(
        Triple("Shows the readiness estimate", onReadiness) { m ->
            WardRing(readiness?.center ?: 0.0, m, WardTone.Amber, "Readiness", centre = if (readiness == null) "–" else null, spoken = readinessSpoken)
        },
        Triple("Shows accuracy subject by subject", onAccuracy) { m ->
            WardRing(accuracy ?: 0.0, m, WardTone.Green, "Accuracy", centre = if (accuracy == null) "–" else null, spoken = accuracySpoken)
        },
        Triple("Opens the syllabus check", onSyllabus) { m ->
            WardRing(syllabus ?: 0.0, m, WardTone.Red, "Syllabus", centre = if (syllabus == null) "…" else null, spoken = syllabusSpoken)
        },
        Triple("Opens the cards due today", onToday) { m ->
            WardRing(share, m, WardTone.Blue, "Today", centre = "$today", spoken = "$today of $target studied today")
        },
    )
    val count = if (wardAccessibilitySize()) 2 else 4
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
        for (row in rings.chunked(count)) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            for ((hint, action, ring) in row) Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                val source = remember { MutableInteractionSource() }
                ring(Modifier.widthIn(max = 120.dp).fillMaxWidth().aspectRatio(1f)
                    .clickable(source, indication = null, role = Role.Button, onClickLabel = hint, onClick = action))
            }
        }
    }
}

/**
 * "Weak topics": the weakest subjects as chips with their percentage,
 * each a drill of that subject; a line saying what today's revision does
 * about them (BedPlan.consultNote); and "Practise weak topics", the drill
 * of the weakest - the same drill as the Weakest topic bed on home.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable fun ConsultCard(spots: List<BedPlan.Topic>, note: String, onDrill: (String) -> Unit) {
    // a List row: as low as the tiles round it, the button proud of it
    WardCardFace(Modifier.fillMaxWidth(), lift = WardLift.low, spacing = WardSpace.m.wardDp) {
        WardSmallCapsText("Weak topics", Modifier.semantics { heading() })
        if (spots.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            for (spot in spots) {
                val source = remember(spot.name) { MutableInteractionSource() }
                Box(Modifier.defaultMinSize(minHeight = WardControlSize.target.wardDp)
                    .clickable(source, indication = null, role = Role.Button, onClickLabel = "Opens a drill of ${spot.name}") { onDrill(spot.name) }
                    .clearAndSetSemantics { contentDescription = "${spot.name}, ${spot.percent} percent" },
                    contentAlignment = Alignment.Center) {
                    WardChip("${spot.name} ${spot.percent}%", tone = WardTone.Danger)
                }
            }
        }
        Text(note, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
        spots.firstOrNull()?.let { first ->
            WardButtonBox({ onDrill(first.name) }, Modifier.fillMaxWidth(), WardButtonKind.primary) {
                Icon(Icons.Rounded.MedicalServices, null, Modifier.size(20.dp))
                Text("Practise weak topics")
            }
        }
    }
}

/** The glyph each reason for a lost mark carries (iOS MistakeReason.symbol). */
fun reasonIcon(reason: MistakeReason): ImageVector = when (reason) {
    MistakeReason.didntKnow -> Icons.AutoMirrored.Rounded.MenuBook
    MistakeReason.misread -> Icons.Rounded.Visibility
    MistakeReason.changedAnswer -> Icons.AutoMirrored.Rounded.Undo
    MistakeReason.outOfTime -> Icons.Rounded.Timer
    MistakeReason.lookalikes -> Icons.Rounded.ContentCopy
}
