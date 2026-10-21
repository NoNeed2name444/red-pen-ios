package com.stethoscore.app.ui.cases

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.CaseChecks
import com.stethoscore.app.data.CaseFile
import com.stethoscore.app.data.CaseRun
import com.stethoscore.app.data.CaseRunStore
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.ScreenHeader

/**
 * A Cases set: one card per patient - initials, age and sex, where they are
 * seen and what they came with - and where each stands: New, Seen (a run in
 * progress) or Discharged with the last score. Port of iOS CaseListView.
 *
 * A case the verification layer has held (a red flag in its medicine) is
 * never shown; the list says how many are waiting on the checkers. Android
 * has no AccuracyHolds store yet, so only a case marked held is held here.
 */
@Composable
fun CaseListScreen(set: StudySet, store: StudyStore, onBack: () -> Unit) {
    var openID by rememberSaveable(set.id) { mutableStateOf<String?>(null) }
    // the set as the library has it now: another patient may have joined it
    var version by remember { mutableIntStateOf(0) }
    val current = remember(version, openID) { store.library.firstOrNull { it.id == set.id } ?: set }
    val runs = remember(store) { CaseRunStore(store) }
    val flagged: Set<String> = emptySet()
    val shown = current.caseFiles.filter { !CaseChecks.isHeld(it, flagged) }
    val heldCount = current.caseFiles.size - shown.size

    val open = shown.firstOrNull { it.id == openID }
    if (open != null) {
        BackHandler { openID = null }
        CaseWardScreen(open, current.id, store, onBack = { openID = null; version++ })
        return
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp)
            .widthIn(max = 760.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ScreenHeader(current.name, "", onBack)
        CaseLabel(if (current.caseFiles.size == 1) "1 patient" else "${current.caseFiles.size} patients", Modifier.padding(horizontal = 4.dp))
        if (shown.isEmpty()) {
            CaseCard {
                Text(
                    if (heldCount > 0) "Every patient here is waiting on the accuracy checkers." else "No patients in this set yet.",
                    fontSize = 15.sp, color = CaseInk.biro,
                )
            }
        }
        for (file in shown) {
            CasePatientCard(file, runs.state(file)) { openID = file.id }
        }
        if (heldCount > 0) {
            val plural = if (heldCount == 1) " is" else "s are"
            Row(Modifier.padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.PanTool, null, tint = CaseInk.biro, modifier = Modifier.size(14.dp))
                Text("$heldCount patient$plural held while the checkers look at a possible error.", fontSize = 13.sp, color = CaseInk.biro)
            }
        }
    }
}

/** One patient on the list. */
@Composable
internal fun CasePatientCard(file: CaseFile, state: CaseRun.State, open: () -> Unit) {
    // the complaint in a few words: its first clause
    val cut = file.complaint.split(',', '.', ';').first()
    val shortComplaint = "“" + cut.trim(' ', '\t') + "”"
    val status = when (state) {
        CaseRun.State.New -> "New"
        CaseRun.State.Seen -> "Seen, in progress"
        is CaseRun.State.Discharged -> "Discharged, score ${state.score} out of 100"
    }
    val spoken = "${file.patient.spoken}, ${file.setting.label}. $shortComplaint. $status"
    CaseCard(
        Modifier.clickable(onClick = open).clearAndSetSemantics {
            contentDescription = spoken
            role = Role.Button
            onClick(label = "Opens the patient") { open(); true }
        },
        padding = 14.dp,
    ) {
        Row(Modifier.heightIn(min = 44.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            CaseAvatar(file.patient.initials)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(file.patient.ageSex, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text("· " + file.setting.label, fontSize = 15.sp, color = CaseInk.biro)
                }
                Text(shortComplaint, fontSize = 15.sp, color = CaseInk.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                CaseStateChip(state)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = CaseInk.biro)
        }
    }
}
