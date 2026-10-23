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
import androidx.compose.material.icons.automirrored.rounded.FormatListBulleted
import androidx.compose.material.icons.rounded.AddCircleOutline
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.Verified
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
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.ScreenHeader
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDisabledInk
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.wardWellFill
import com.stethoscore.app.ui.wardColor

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
        val wide = com.stethoscore.app.ui.ward.WindowShape.isExpanded(maxWidth.value.toDouble())
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.weight(1f)) {
                Column(
                    Modifier.weight(1f).fillMaxHeight().verticalScroll(rememberScrollState()).padding(horizontal = WardSpace.l.wardDp).padding(bottom = WardSpace.l.wardDp),
                    verticalArrangement = Arrangement.spacedBy(WardSpace.l.wardDp),
                ) {
                    ScreenHeader(title, "", onBack)
                    Triage(file, run, arriving)
                    if (arriving) {
                        ClerkingCard(file)
                        CaseCard {
                            CaseLabel("Your shift")
                            Text("You have ${file.budgetMinutes} minutes. Every examination and test costs time. Keep a ranked differential as you go, then decide the diagnosis and the next step.",
                                style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
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
                    VerticalDivider(color = wardColor(WardToken.hairline))
                    CaseLadderPanel(file, run, Modifier.width(340.dp).fillMaxHeight()) { edit -> change { edit(it); true } }
                }
            }
            // the bar at the bottom, under the thumb
            HorizontalDivider(color = wardColor(WardToken.hairline))
            Row(Modifier.fillMaxWidth().background(wardColor(WardToken.background)).padding(horizontal = WardSpace.l.wardDp, vertical = WardSpace.m.wardDp), horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
                if (arriving) {
                    CaseButton("See the patient", { arriving = false }, Modifier.weight(1f), primary = true, icon = Icons.Rounded.MedicalServices)
                } else {
                    if (!wide) {
                        CaseButton(if (run.ladder.isEmpty()) "Differential" else "Differential (${run.ladder.size})", { showingLadder = true },
                            Modifier.weight(1f).semantics { stateDescription = "Your ranked working diagnoses" }, icon = Icons.AutoMirrored.Rounded.FormatListBulleted)
                    }
                    CaseButton("Decide", { deciding = true }, Modifier.weight(1f).semantics { stateDescription = "Confirm the diagnosis and choose the next step" },
                        primary = true, icon = Icons.Rounded.Verified)
                }
            }
        }
        if (showingLadder && !wide) LadderSheet(file, run, onDone = { showingLadder = false }) { edit -> change { edit(it); true } }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LadderSheet(file: CaseFile, run: CaseRun, onDone: () -> Unit, edit: ((CaseRun) -> Unit) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDone, sheetState = rememberModalBottomSheetState(), containerColor = wardColor(WardToken.background)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = WardSpace.l.wardDp), verticalAlignment = Alignment.CenterVertically) {
            Text("Differential", Modifier.weight(1f), style = WardType.headline.textStyle())
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
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
            CaseAvatar(file.patient.initials)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
                FlowRow(
                    Modifier.clearAndSetSemantics { contentDescription = "${file.patient.spoken}, seen in ${file.setting.label}" },
                    horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp),
                ) {
                    if (file.patient.age > 0) CaseChip("${file.patient.age} y", CaseTone.grey)
                    if (file.patient.sexLetter.isNotEmpty()) CaseChip(if (file.patient.isFemale) "Female" else "Male", CaseTone.grey)
                    CaseChip(file.setting.label, CaseTone.blue)
                }
                if (file.patient.about.isNotEmpty()) Text(file.patient.about, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            CaseClockPill(run.minutesUsed, file.budgetMinutes)
        }
        if (file.arrival.isNotEmpty()) {
            CaseLabel("On arrival")
            CaseVitalsGrid(file.arrival)
        }
        Text("“" + file.complaint + "”", style = (if (arriving) WardTextStyle.title3 else WardTextStyle.body).textStyle(), fontStyle = FontStyle.Italic,
            modifier = Modifier.clearAndSetSemantics { contentDescription = "The patient says: " + file.complaint })
    }
}

@Composable
private fun ClerkingParts(file: CaseFile) {
    Column(verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        for (part in file.clerking.parts) {
            Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
                Text(part.label, style = WardTextStyle.footnote.textStyle(WardWeight.semibold), color = wardColor(WardToken.inkSecondary))
                Text(part.text, style = WardTextStyle.subheadline.textStyle())
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
            Modifier.fillMaxWidth().heightIn(min = WardControlSize.target.wardDp).clickable(role = Role.Button) { open = !open }
                .semantics { stateDescription = if (open) "Expanded" else "Collapsed" },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CaseLabel("Clerking note", Modifier.weight(1f))
            Icon(if (open) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown, null, tint = wardColor(WardToken.primaryInk))
        }
        if (open) Box(Modifier.padding(top = WardSpace.s.wardDp)) { ClerkingParts(file) }
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
            FlowRow(horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
                for (step in file.steps(group)) ActionChip(step, run.hasTaken(step.id), Modifier.width(width)) { take(step) }
            }
        }
    }
}

@Composable
private fun ActionChip(step: CaseStep, done: Boolean, modifier: Modifier, take: () -> Unit) {
    val shape = RoundedCornerShape(WardRadius.field.wardDp)
    val minutes = "${step.label}, ${step.minutes} minute${if (step.minutes == 1) "" else "s"}"
    Row(
        modifier.minimumInteractiveComponentSize().heightIn(min = 44.dp)
            // raised to be tapped; once taken, pressed into the card
            .background(if (done) wardWellFill() else wardColor(WardToken.surface), shape)
            .border(1.dp, wardColor(WardToken.hairline), shape)
            .clickable(enabled = !done, role = Role.Button, onClick = take)
            .padding(WardSpace.m.wardDp)
            .clearAndSetSemantics {
                contentDescription = minutes
                role = Role.Button
                if (done) { stateDescription = "Done"; disabled() } else onClick(label = "Spends the minutes and adds the finding to the note") { take(); true }
            },
        horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalAlignment = Alignment.Top,
    ) {
        Icon(if (done) Icons.Rounded.CheckCircle else Icons.Rounded.AddCircleOutline, null, tint = if (done) wardColor(WardToken.success) else wardColor(WardToken.primaryInk), modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
            Text(step.label, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = if (done) wardColor(WardToken.inkSecondary) else wardColor(WardToken.ink))
            Text("${step.minutes} min", style = WardTextStyle.caption.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
        }
    }
}

/** What has been found, newest first. */
@Composable
private fun ClinicalNote(file: CaseFile, run: CaseRun) {
    CaseCard(spacing = 12.dp) {
        CaseLabel("Clinical note")
        if (run.taken.isEmpty()) Text("Findings appear here as you ask, examine and test.", style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        for (taken in run.taken.reversed()) {
            val step = file.step(taken.stepID) ?: continue
            Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(step.group.label + " · " + step.label, Modifier.weight(1f), style = WardTextStyle.footnote.textStyle(WardWeight.semibold), color = wardColor(WardToken.inkSecondary))
                    Spacer(Modifier.width(WardSpace.s.wardDp))
                    Text("${taken.at} min", style = WardTextStyle.caption.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
                }
                Text(step.finding, style = WardType.body.textStyle())
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
    Column(modifier.background(wardColor(WardToken.background)).verticalScroll(rememberScrollState()).padding(WardSpace.l.wardDp), verticalArrangement = Arrangement.spacedBy(WardSpace.l.wardDp)) {
        CaseLabel("Your ladder")
        if (run.ladder.isEmpty()) Text("Up to three working diagnoses, the most likely first. Change them whenever you like.", style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        run.ladder.forEachIndexed { index, name ->
            val leading = index == 0
            CaseCard(padding = 8.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
                    Box(Modifier.size(32.dp).background(wardWellFill(), CircleShape).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
                        Text("${index + 1}", fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, color = if (leading) wardColor(WardToken.primaryInk) else wardColor(WardToken.inkSecondary))
                    }
                    Text(name, Modifier.weight(1f).clearAndSetSemantics {
                        contentDescription = "Rung ${index + 1} of ${run.ladder.size}: $name" + if (leading) ", leading" else ""
                    }, style = WardTextStyle.body.textStyle(if (leading) WardWeight.semibold else WardWeight.regular))
                    RungButton(Icons.Rounded.KeyboardArrowUp, "Move up", index > 0) { edit { it.move(name, up = true) } }
                    RungButton(Icons.Rounded.KeyboardArrowDown, "Move down", index < run.ladder.size - 1) { edit { it.move(name, up = false) } }
                    RungButton(Icons.Rounded.Close, "Remove", true) { edit { it.remove(name) } }
                }
            }
        }
        CaseLabel("Add a diagnosis")
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            OutlinedTextField(typed, { typed = it }, Modifier.weight(1f), placeholder = { Text("Type a diagnosis") }, singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { addTyped() }))
            TextButton(::addTyped, enabled = typed.isNotBlank(), colors = ButtonDefaults.textButtonColors(disabledContentColor = wardDisabledInk())) { Text("Add", fontWeight = FontWeight.SemiBold) }
        }
        if (run.ladder.size >= CaseRun.RUNGS) Text("The ladder is full: a new diagnosis takes the bottom rung.", style = WardType.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            for (name in pickable) {
                val shape = RoundedCornerShape(WardRadius.field.wardDp)
                Box(
                    Modifier.minimumInteractiveComponentSize().widthIn(min = 140.dp).heightIn(min = 44.dp).background(wardColor(WardToken.surface), shape).border(1.dp, wardColor(WardToken.hairline), shape)
                        .clickable(role = Role.Button, onClickLabel = "Adds it to your ladder") { add(name) }.padding(horizontal = WardSpace.m.wardDp),
                    contentAlignment = Alignment.CenterStart,
                ) { Text(name, style = WardTextStyle.subheadline.textStyle()) }
            }
        }
    }
}

@Composable
private fun RungButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean, action: () -> Unit) {
    IconButton(action, enabled = enabled) {
        Icon(icon, label, tint = if (enabled) wardColor(WardToken.primaryInk) else wardDisabledInk())
    }
}
