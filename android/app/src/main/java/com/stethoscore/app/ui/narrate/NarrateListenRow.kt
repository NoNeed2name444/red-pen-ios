package com.stethoscore.app.ui.narrate

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.List
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.audio.AudioChapter
import com.stethoscore.app.audio.LectureAudio
import com.stethoscore.app.audio.SleepChoice
import com.stethoscore.app.ui.sources.ReaderDoneButton
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor

/**
 * The small row above the lecture's transport
 * (ios/RedPen/Features/Narrate/NarrateListenRow.swift, fed0105): which
 * section it is in, the way to the one before or after, and the sleep
 * timer. Small compact buttons rather than more big ones; with fewer than two
 * sections only the sleep timer shows.
 */
@Composable internal fun NarrateListenRow(sections: List<AudioChapter>, current: Int?, sleep: SleepTimer,
                                          onPrevious: () -> Unit, onNext: () -> Unit, onPick: (Int) -> Unit) {
    var listing by remember { mutableStateOf(false) }
    val place = if (current == null) "Sections" else "${current + 1} of ${sections.size}"
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (sections.size >= 2) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            WardButtonBox(onPrevious, Modifier.semantics { contentDescription = "Previous section" }, kind = WardButtonKind.compact, fills = false) {
                Icon(Icons.Rounded.SkipPrevious, null, Modifier.size(18.dp))
            }
            WardButtonBox({ listing = true }, Modifier.semantics { contentDescription = "Sections, $place" }, kind = WardButtonKind.compact, fills = false) {
                Icon(Icons.AutoMirrored.Rounded.List, null, Modifier.size(18.dp))
                Text(place, maxLines = 1, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold, mono = current != null))
            }
            WardButtonBox(onNext, Modifier.semantics { contentDescription = "Next section" }, kind = WardButtonKind.compact,
                enabled = current?.let { it + 1 < sections.size } ?: true, fills = false) {
                Icon(Icons.Rounded.SkipNext, null, Modifier.size(18.dp))
            }
        }
        Spacer(Modifier.weight(1f))
        SleepTimerMenu(sleep, sectioned = sections.size >= 2)
    }
    if (listing) SectionListSheet(sections, current, onPick = { onPick(it); listing = false }, onClose = { listing = false })
}

/** The sleep timer's chip: a moon, and the time left while it runs. */
@Composable internal fun SleepTimerMenu(sleep: SleepTimer, sectioned: Boolean) {
    var open by remember { mutableStateOf(false) }
    val countdown = sleep.countdown
    val shown = countdown?.label ?: "Sleep"
    val running = countdown != null
    Box {
        WardButtonBox({ open = true }, Modifier.semantics { contentDescription = if (running) "Sleep timer, $shown left" else "Sleep timer" },
            kind = WardButtonKind.compact, fills = false) {
            Icon(if (running) Icons.Rounded.Bedtime else Icons.Outlined.Bedtime, null, Modifier.size(18.dp))
            Text(shown, maxLines = 1, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold, mono = running))
        }
        DropdownMenu(open, { open = false }, containerColor = wardColor(WardToken.raised)) {
            // items rather than a picker, so choosing the same time again starts it over
            SleepChoice.all.forEach { option ->
                val chosen = countdown?.choice == option
                val name = if (option == SleepChoice.EndOfSection && !sectioned) "End of the lecture" else option.name
                DropdownMenuItem(text = { Text(name) },
                    leadingIcon = { if (chosen) Icon(Icons.Rounded.Check, null) else Spacer(Modifier.size(24.dp)) },
                    onClick = { open = false; sleep.start(option) })
            }
            if (running) DropdownMenuItem(text = { Text("Turn off") }, leadingIcon = { Icon(Icons.Rounded.Close, null) },
                onClick = { open = false; sleep.cancel() })
        }
    }
}

/** Every section, to jump straight to one: a recording's show when they start, and the one playing is marked. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun SectionListSheet(sections: List<AudioChapter>, current: Int?, onPick: (Int) -> Unit, onClose: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onClose, sheetState = rememberModalBottomSheetState(), containerColor = wardColor(WardToken.background)) {
        ReaderNavBar("Sections", trailing = { ReaderDoneButton(onClick = onClose) })
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = WardSpace.s.wardDp).padding(bottom = 24.dp)) {
            sections.forEachIndexed { i, section ->
                val playing = i == current
                val start = section.start
                val whenText = if (start != null) LectureAudio.clock(start) else ""
                Row(Modifier.fillMaxWidth().semantics { selected = playing }.clickable(role = Role.Button) { onPick(i) }
                    .wardRowTile().heightIn(min = 44.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${i + 1}", Modifier.widthIn(min = 24.dp), style = WardTextStyle.subheadline.textStyle(mono = true),
                        color = wardColor(WardToken.inkSecondary), textAlign = TextAlign.End)
                    Text(section.title, Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis,
                        style = WardTextStyle.body.textStyle(if (playing) WardWeight.semibold else WardWeight.regular), color = wardColor(WardToken.ink))
                    if (whenText.isNotEmpty()) Text(whenText, style = WardTextStyle.subheadline.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
                    if (playing) Icon(Icons.AutoMirrored.Rounded.VolumeUp, "Playing", tint = wardColor(WardToken.primary))
                }
            }
        }
    }
}
