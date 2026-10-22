package com.stethoscore.app.ui.learn

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.Accessibility
import androidx.compose.material.icons.rounded.Air
import androidx.compose.material.icons.rounded.AirlineSeatFlat
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.MonitorHeart
import androidx.compose.material.icons.rounded.Opacity
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Psychology
import androidx.compose.material.icons.rounded.QuestionAnswer
import androidx.compose.material.icons.rounded.SportsGymnastics
import androidx.compose.material.icons.rounded.Timeline
import androidx.compose.material.icons.rounded.TripOrigin
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.data.SymptomBlocks
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.ward.WardIconSquare
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.wardColor

// A port of ios/RedPen/Features/Learn/SymptomBlocksView.swift: "Chest pain
// block", "Breathless block", "Groin lump block" - questions from every set
// that share a presenting complaint, mixed so neighbouring questions have
// different answers. After a block, the mix-ups: what was picked against
// what it was, read from the answers given during it.

@Composable internal fun SymptomBlocksScreen(store: StudyStore) {
    val version = LearnRouter.version
    /** The block last started, and when, for its mix-ups. */
    var last by remember { mutableStateOf<Pair<SymptomBlocks.Block, Long>?>(null) }
    val all = remember(version) { SymptomBlocks.blocks(LearnLibrary.symptomItems(store), includeThin = true) }
    val ready = all.filter(::isReady)
    val thin = all.filter { !isReady(it) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = WardSpace.m.wardDp),
        verticalArrangement = Arrangement.spacedBy(WardSpace.section.wardDp)) {
        ReaderFormSection {
            Box(Modifier.wardRowTile()) {
                Text("Questions from every set that start from the same complaint, mixed, so you learn to tell the lookalikes apart the way the exam asks.",
                    style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        }
        last?.let { (block, started) -> MixUps(store, block, started, version) }
        if (ready.isEmpty()) {
            ReaderFormSection {
                Box(Modifier.wardRowTile()) {
                    Text("No complaint has enough questions yet: a block needs ${SymptomBlocks.minimumQuestions} questions with at least ${SymptomBlocks.minimumCauses} different answers.",
                        style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
            }
        } else {
            ReaderFormSection("Blocks") {
                for (block in ready) BlockRow(block) {
                    last = block to System.currentTimeMillis()
                    LearnRouter.push(LearnPush.Quiz(LearnLibrary.symptomQuiz(store, block)))
                }
            }
        }
        if (thin.isNotEmpty()) ReaderFormSection("Not enough questions yet") {
            for (block in thin) ThinRow(block)
        }
    }
}

private fun isReady(block: SymptomBlocks.Block): Boolean =
    block.ids.size >= SymptomBlocks.minimumQuestions && block.causes >= SymptomBlocks.minimumCauses

/** A presentation's SF Symbol, as the nearest Material icon. */
internal fun presentationIcon(symbol: String): ImageVector = when (symbol) {
    "heart.text.square" -> Icons.Rounded.MonitorHeart
    "lungs" -> Icons.Rounded.Air
    "circle.dashed" -> Icons.Rounded.TripOrigin
    "stethoscope" -> Icons.Rounded.MedicalServices
    "brain.head.profile" -> Icons.Rounded.Psychology
    "figure.fall" -> Icons.Rounded.AirlineSeatFlat
    "drop.halffull" -> Icons.Rounded.Opacity
    "figure.walk" -> Icons.AutoMirrored.Rounded.DirectionsWalk
    "questionmark.bubble" -> Icons.Rounded.QuestionAnswer
    "waveform.path.ecg" -> Icons.Rounded.Timeline
    "drop.fill" -> Icons.Rounded.WaterDrop
    "figure.stand" -> Icons.Rounded.Accessibility
    "figure.flexibility" -> Icons.Rounded.SportsGymnastics
    "exclamationmark.circle" -> Icons.Rounded.ErrorOutline
    "eye.slash" -> Icons.Rounded.VisibilityOff
    else -> Icons.Rounded.MedicalServices
}

@Composable private fun BlockRow(block: SymptomBlocks.Block, start: () -> Unit) {
    val p = block.presentation
    val shown = minOf(20, block.ids.size)
    val lookalikes = p.lookalikes.take(4).joinToString(", ")
    Row(Modifier.clickable(onClickLabel = "Starts a mixed block of ${p.name.lowercase()} questions", onClick = start)
        .wardRowTile().heightIn(min = 56.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        WardIconSquare(presentationIcon(p.symbol), size = 36.0)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(p.blockTitle, style = WardTextStyle.body.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
            Text("$shown questions · ${block.causes} different answers", style = WardTextStyle.caption.textStyle(mono = true),
                color = wardColor(WardToken.inkSecondary))
            Text(lookalikes + "…", style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary),
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Icon(Icons.Rounded.PlayArrow, null, Modifier.size(14.dp), tint = wardColor(WardToken.primaryInk))
    }
}

@Composable private fun ThinRow(block: SymptomBlocks.Block) {
    val p = block.presentation
    val plural = if (block.ids.size == 1) "" else "s"
    Row(Modifier.wardRowTile().heightIn(min = 44.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        WardIconSquare(presentationIcon(p.symbol), tone = WardTone.Grey, size = 32.0)
        Text(p.name, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
        Text("${block.ids.size} question$plural", style = WardTextStyle.caption.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
    }
}

/** What was confused for what in the block just sat. */
@Composable private fun MixUps(store: StudyStore, block: SymptomBlocks.Block, since: Long, version: Int) {
    val events = remember(version, block, since) { LearnLibrary.answersSince(store, block.ids.toSet(), since) }
    if (events.isEmpty()) return
    val rows = remember(events) {
        SymptomBlocks.confusions(LearnLibrary.optionsById(LearnLibrary.picks(store, block.ids)), events)
    }
    val right = events.count { it.correct }
    ReaderFormSection("Mix-ups · ${block.presentation.blockTitle}",
        "What you picked, and what it was. The pairs that come up most are the ones to put side by side.") {
        Box(Modifier.wardRowTile()) {
            Text("$right of ${events.size} right", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold, mono = true),
                color = wardColor(WardToken.ink))
        }
        if (rows.isEmpty()) Box(Modifier.wardRowTile()) {
            Text("No mix-ups this time.", style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
        for (row in rows.take(6)) ConfusionRow(row)
    }
}

@Composable private fun ConfusionRow(row: SymptomBlocks.Confusion) {
    val times = if (row.count > 1) ", ${row.count} times" else ""
    val style = WardTextStyle.subheadline.textStyle()
    Row(Modifier.wardRowTile().clearAndSetSemantics { contentDescription = "Picked ${row.picked}, it was ${row.actual}$times" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(row.picked, style = style.copy(textDecoration = TextDecoration.LineThrough), color = wardColor(WardToken.inkSecondary))
        Icon(Icons.AutoMirrored.Rounded.ArrowForward, null, Modifier.size(12.dp), tint = wardColor(WardToken.inkSecondary))
        Text(row.actual, Modifier.weight(1f), style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
        if (row.count > 1) Text("×${row.count}", style = WardTextStyle.caption.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
    }
}
