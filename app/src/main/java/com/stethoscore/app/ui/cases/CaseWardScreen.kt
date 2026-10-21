package com.stethoscore.app.ui.cases

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.FormatListBulleted
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MedicalServices
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.ScreenHeader

/**
 * One patient, from arrival to the decision, and then the debrief. Port of
 * iOS CaseWardView.
 *
 * Arrival: the clerking note (the history, already taken and written - the
 * patient is never questioned here), the triage strip (age, sex, where they
 * are seen), the arrival observations, the complaint in the patient's words
 * and the time allowed.
 * Work-up: Examine and Test, each action a chip with its minutes; taking one
 * spends them and adds its finding to the clinical note under the strip,
 * newest first. The differential ladder is open at any time - a sheet on a
 * phone, a side panel on a wide screen - and the run is kept after every
 * change, so leaving and coming back carries on where it was.
 */
@Composable
fun CaseWardScreen(file: CaseFile, setID: String, store: StudyStore, onBack: () -> Unit) {
    val runs = remember(store) { CaseRunStore(store) }
    val view = LocalView.current
    val saved = remember(file.id) { runs.run(file) }
    var run by remember(file.id) { mutableStateOf(saved ?: CaseRun(caseID = file.id)) }
    var arriving by rememberSaveable(file.id) { mutableStateOf(saved == null || saved.taken.isEmpty()) }
    var group by rememberSaveable(file.id) { mutableStateOf(CaseStep.Group.examine) }
    var showingLadder by rememberSaveable(file.id) { mutableStateOf(false) }
    var deciding by rememberSaveable(file.id) { mutableStateOf(false) }

    fun change(edit: (CaseRun) -> Boolean) {
        val next = run.copy()
        if (!edit(next)) return
        run = next
        runs.save(next)
    }

    val title = file.patient.ageSex.ifEmpty { "Patient" }

    if (run.isFinished) {
        CaseDebriefScreen(file, setID, run, store, title, onBack, again = {
            runs.reset(file)
            run = CaseRun(caseID = file.id)
            arriving = true
            group = CaseStep.Group.examine
        })
        return
    }
    if (deciding) {
        BackHandler { deciding = false }
        CaseDecisionScreen(file, leading = run.ladder.firstOrNull() ?: "", onBack = { deciding = false }) { decision ->
            deciding = false
            change { it.decide(decision, file); true }
        }
        return
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth >= 840.dp
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.weight(1f)) {
                Column(
                    Modifier.weight(1f).fillMaxHeight().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    ScreenHeader(title, "", onBack)
                    Triage(file, run, arriving)
                    if (arriving) {
                        ClerkingCard(file)
                        CaseCard {
                            CaseLabel("Your shift")
                            Text("You have ${file.budgetMinutes} minutes. Every examination and test costs time. Keep a ranked differential as you go, then decide the diagnosis and the next step.",
                                fontSize = 15.sp, color = CaseInk.ink)
                        }
                    } else {
                        ClerkingFolded(file)
                        Actions(file, run, group, onGroup = { group = it }) { step ->
                            change { it.take(step.id, file) }
                            // the finding, read out, since it lands below the chips
                            view.announce(step.finding)
                        }
                        ClinicalNote(file, run)
                    }
                }
                if (wide && !arriving) {
                    VerticalDivider(color = CaseInk.hairline)
                    CaseLadderPanel(file, run, Modifier.width(340.dp).fillMaxHeight()) { edit -> change { edit(it); true } }
                }
            }
            // the bar at the bottom, under the thumb
            HorizontalDivider(color = CaseInk.hairline)
            Row(Modifier.fillMaxWidth().background(CaseInk.ward).padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (arriving) {
                    CaseButton("See the patient", { arriving = false }, Modifier.weight(1f), primary = true, icon = Icons.Filled.MedicalServices)
                } else {
                    if (!wide) {
                        CaseButton(if (run.ladder.isEmpty()) "Differential" else "Differential (${run.ladder.size})", { showingLadder = true },
                            Modifier.weight(1f).semantics { stateDescription = "Your ranked working diagnoses" }, icon = Icons.AutoMirrored.Filled.FormatListBulleted)
                    }
                    CaseButton("Decide", { deciding = true }, Modifier.weight(1f).semantics { stateDescription = "Confirm the diagnosis and choose the next step" },
                        primary = true, icon = Icons.Filled.Verified)
                }
            }
        }
        if (showingLadder && !wide) LadderSheet(file, run, onDone = { showingLadder = false }) { edit -> change { edit(it); true } }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LadderSheet(file: CaseFile, run: CaseRun, onDone: () -> Unit, edit: ((CaseRun) -> Unit) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDone, sheetState = rememberModalBottomSheetState(), containerColor = CaseInk.ward) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Differential", Modifier.weight(1f), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            TextButton(onDone) { Text("Done", fontWeight = FontWeight.SemiBold) }
        }
        CaseLadderPanel(file, run, Modifier.fillMaxWidth(), edit)
    }
}

/** Who the patient is, their observations, what they say and the clock. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Triage(file: CaseFile, run: CaseRun, arriving: Boolean) {
    CaseCard(spacing = 12.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            CaseAvatar(file.patient.initials)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                FlowRow(
                    Modifier.clearAndSetSemantics { contentDescription = "${file.patient.spoken}, seen in ${file.setting.label}" },
                    horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    if (file.patient.age > 0) CaseChip("${file.patient.age} y", CaseTone.grey)
                    if (file.patient.sexLetter.isNotEmpty()) CaseChip(if (file.patient.isFemale) "Female" else "Male", CaseTone.grey)
                    CaseChip(file.setting.label, CaseTone.blue)
                }
                if (file.patient.about.isNotEmpty()) Text(file.patient.about, fontSize = 13.sp, color = CaseInk.biro)
            }
            CaseClockPill(run.minutesUsed, file.budgetMinutes)
        }
        if (file.arrival.isNotEmpty()) {
            CaseLabel("On arrival")
            CaseVitalsGrid(file.arrival)
        }
        Text("“" + file.complaint + "”", fontSize = if (arriving) 20.sp else 17.sp, fontStyle = FontStyle.Italic,
            modifier = Modifier.clearAndSetSemantics { contentDescription = "The patient says: " + file.complaint })
    }
}

@Composable
private fun ClerkingParts(file: CaseFile) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (part in file.clerking.parts) {
            Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(part.label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = CaseInk.biro)
                Text(part.text, fontSize = 15.sp)
            }
        }
    }
}

/** The history as it was written on admission. */
@Composable
private fun ClerkingCard(file: CaseFile) {
    CaseCard {
        CaseLabel("Clerking note")
        ClerkingParts(file)
    }
}

/** The same note during the work-up, folded away until wanted. */
@Composable
private fun ClerkingFolded(file: CaseFile) {
    var open by rememberSaveable(file.id) { mutableStateOf(false) }
    CaseCard(padding = 12.dp) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(role = Role.Button) { open = !open }
                .semantics { stateDescription = if (open) "Expanded" else "Collapsed" },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CaseLabel("Clerking note", Modifier.weight(1f))
            Icon(if (open) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, null, tint = CaseInk.theatre)
        }
        if (open) Box(Modifier.padding(top = 8.dp)) { ClerkingParts(file) }
    }
}

// MARK: the work-up

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Actions(file: CaseFile, run: CaseRun, group: CaseStep.Group, onGroup: (CaseStep.Group) -> Unit, take: (CaseStep) -> Unit) {
    CaseCard(spacing = 12.dp) {
        CaseSegmented(group, CaseStep.Group.entries.toList(), { it.label }, onGroup, Modifier.semantics { contentDescription = "Action" })
        BoxWithConstraints {
            val columns = maxOf(1, (maxWidth / 158.dp).toInt())
            val width = (maxWidth - 8.dp * (columns - 1)) / columns
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for (step in file.steps(group)) ActionChip(step, run.hasTaken(step.id), Modifier.width(width)) { take(step) }
            }
        }
    }
}

@Composable
private fun ActionChip(step: CaseStep, done: Boolean, modifier: Modifier, take: () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    val minutes = "${step.label}, ${step.minutes} minute${if (step.minutes == 1) "" else "s"}"
    Row(
        modifier.heightIn(min = 44.dp)
            // raised to be tapped; once taken, pressed into the card
            .background(if (done) CaseInk.well else CaseInk.surface, shape)
            .border(1.dp, CaseInk.hairline, shape)
            .clickable(enabled = !done, role = Role.Button, onClick = take)
            .padding(10.dp)
            .clearAndSetSemantics {
                contentDescription = minutes
                role = Role.Button
                if (done) { stateDescription = "Done"; disabled() } else onClick(label = "Spends the minutes and adds the finding to the note") { take(); true }
            },
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top,
    ) {
        Icon(if (done) Icons.Filled.CheckCircle else Icons.Filled.AddCircleOutline, null, tint = if (done) CaseInk.discharge else CaseInk.theatre, modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(step.label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (done) CaseInk.biro else CaseInk.ink)
            Text("${step.minutes} min", fontSize = 12.sp, fontFamily = FontFamily.Monospace, color = CaseInk.biro)
        }
    }
}

/** What has been found, newest first. */
@Composable
private fun ClinicalNote(file: CaseFile, run: CaseRun) {
    CaseCard(spacing = 12.dp) {
        CaseLabel("Clinical note")
        if (run.taken.isEmpty()) Text("Findings appear here as you ask, examine and test.", fontSize = 15.sp, color = CaseInk.biro)
        for (taken in run.taken.reversed()) {
            val step = file.step(taken.stepID) ?: continue
            Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(step.group.label + " · " + step.label, Modifier.weight(1f), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = CaseInk.biro)
                    Spacer(Modifier.width(8.dp))
                    Text("${taken.at} min", fontSize = 12.sp, fontFamily = FontFamily.Monospace, color = CaseInk.biro)
                }
                Text(step.finding, fontSize = 17.sp)
                if (step.results.isNotEmpty()) CaseResultsTable(step.results)
            }
        }
    }
}

/**
 * The differential ladder: up to three working diagnoses, the leading one
 * first, picked from the case's list or typed. Nothing here asks the student
 * to keep it up to date; the run copies it after every step.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun CaseLadderPanel(file: CaseFile, run: CaseRun, modifier: Modifier = Modifier, edit: ((CaseRun) -> Unit) -> Unit) {
    var typed by rememberSaveable(file.id) { mutableStateOf("") }
    fun add(name: String) = edit { it.add(name, file) }
    fun addTyped() {
        val name = typed.trim()
        if (name.isEmpty()) return
        add(name)
        typed = ""
    }
    // the case's list, less what is on the ladder already
    val pickable = file.candidates.filter { name -> run.ladder.none { CaseNames.same(it, name) } }
    Column(modifier.background(CaseInk.ward).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        CaseLabel("Your ladder")
        if (run.ladder.isEmpty()) Text("Up to three working diagnoses, the most likely first. Change them whenever you like.", fontSize = 15.sp, color = CaseInk.biro)
        run.ladder.forEachIndexed { index, name ->
            val leading = index == 0
            CaseCard(padding = 8.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(32.dp).background(CaseInk.well, CircleShape).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
                        Text("${index + 1}", fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, color = if (leading) CaseInk.theatre else CaseInk.biro)
                    }
                    Text(name, Modifier.weight(1f).clearAndSetSemantics {
                        contentDescription = "Rung ${index + 1} of ${run.ladder.size}: $name" + if (leading) ", leading" else ""
                    }, fontWeight = if (leading) FontWeight.SemiBold else FontWeight.Normal, fontSize = 17.sp)
                    RungButton(Icons.Filled.KeyboardArrowUp, "Move up", index > 0) { edit { it.move(name, up = true) } }
                    RungButton(Icons.Filled.KeyboardArrowDown, "Move down", index < run.ladder.size - 1) { edit { it.move(name, up = false) } }
                    RungButton(Icons.Filled.Close, "Remove", true) { edit { it.remove(name) } }
                }
            }
        }
        CaseLabel("Add a diagnosis")
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(typed, { typed = it }, Modifier.weight(1f), placeholder = { Text("Type a diagnosis") }, singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { addTyped() }))
            TextButton(::addTyped, enabled = typed.isNotBlank()) { Text("Add", fontWeight = FontWeight.SemiBold) }
        }
        if (run.ladder.size >= CaseRun.RUNGS) Text("The ladder is full: a new diagnosis takes the bottom rung.", fontSize = 12.sp, color = CaseInk.biro)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (name in pickable) {
                val shape = RoundedCornerShape(12.dp)
                Box(
                    Modifier.widthIn(min = 140.dp).heightIn(min = 44.dp).background(CaseInk.surface, shape).border(1.dp, CaseInk.hairline, shape)
                        .clickable(role = Role.Button, onClickLabel = "Adds it to your ladder") { add(name) }.padding(horizontal = 12.dp),
                    contentAlignment = Alignment.CenterStart,
                ) { Text(name, fontSize = 15.sp) }
            }
        }
    }
}

@Composable
private fun RungButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean, action: () -> Unit) {
    IconButton(action, Modifier.size(44.dp), enabled = enabled) {
        Icon(icon, label, tint = if (enabled) CaseInk.theatre else CaseInk.ink.copy(alpha = 0.38f))
    }
}
