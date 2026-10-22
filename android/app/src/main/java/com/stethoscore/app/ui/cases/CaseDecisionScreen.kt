package com.stethoscore.app.ui.cases

import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.ui.WardOptionRow
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Description
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.data.CaseFile
import com.stethoscore.app.data.CaseNames
import com.stethoscore.app.data.CaseRun
import com.stethoscore.app.data.candidates
import com.stethoscore.app.data.resolve
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp

/**
 * The decision: the leading diagnosis confirmed (the top of the ladder, or
 * another picked here), the next step as a single best answer, and an
 * optional one-line reason. Discharging closes the case and opens the
 * debrief. Port of iOS CaseDecisionView (a sheet there, a screen here).
 */
@Composable
internal fun CaseDecisionScreen(file: CaseFile, leading: String, onBack: () -> Unit, decide: (CaseRun.Decision) -> Unit) {
    var diagnosis by rememberSaveable(file.id) { mutableStateOf(leading) }
    var choosing by rememberSaveable(file.id) { mutableStateOf(leading.isEmpty()) }
    var typed by rememberSaveable(file.id) { mutableStateOf("") }
    var option by rememberSaveable(file.id) { mutableStateOf<Int?>(null) }
    var reason by rememberSaveable(file.id) { mutableStateOf("") }
    val ready = diagnosis.isNotBlank() && option != null

    fun useTyped() {
        val name = typed.trim()
        if (name.isEmpty()) return
        diagnosis = file.resolve(name) ?: name
        typed = ""
        choosing = false
    }

    fun discharge() {
        val chosen = option ?: return
        if (!ready) return
        decide(CaseRun.Decision(diagnosis = diagnosis, nextStep = chosen, reason = reason.trim()))
    }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onBack) { Text("Back") }
            Text("Decision", Modifier.weight(1f), style = WardType.headline.textStyle(), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Spacer(Modifier.width(64.dp))
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp).widthIn(max = 760.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            CaseCard {
                CaseLabel("Leading diagnosis")
                if (diagnosis.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(diagnosis, Modifier.weight(1f), style = WardType.title.textStyle())
                        TextButton({ choosing = !choosing }, Modifier.heightIn(min = 44.dp)) { Text(if (choosing) "Keep" else "Change") }
                    }
                }
                if (choosing) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(typed, { typed = it }, Modifier.weight(1f), placeholder = { Text("Type a diagnosis") }, singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { useTyped() }))
                        TextButton(::useTyped, enabled = typed.isNotBlank()) { Text("Use", fontWeight = FontWeight.SemiBold) }
                    }
                    for (name in file.candidates) {
                        val picked = CaseNames.same(name, diagnosis)
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = WardControlSize.target.wardDp).clickable(role = Role.Button) { diagnosis = name; choosing = false }
                                .semantics { selected = picked },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(name, Modifier.weight(1f), style = WardType.body.textStyle())
                            if (picked) Icon(Icons.Filled.Check, null, tint = CaseInk.theatre)
                        }
                    }
                }
            }
            CaseCard {
                CaseLabel("Next step")
                Text("What is the single best next step?", style = WardType.headline.textStyle())
                file.nextStep.options.forEachIndexed { index, text ->
                    WardOptionRow(AccuracyItem.letter(index), text, if (option == index) ChartQuiz.Mark.chosen else ChartQuiz.Mark.idle, modifier =
                        Modifier.clickable(role = Role.RadioButton) { option = index }.semantics(mergeDescendants = true) {
                            contentDescription = "Option ${AccuracyItem.letter(index)}: $text"
                            selected = option == index
                        })
                }
            }
            CaseCard {
                CaseLabel("Your reason (optional)")
                OutlinedTextField(reason, { reason = it }, Modifier.fillMaxWidth().heightIn(min = 44.dp), placeholder = { Text("One line: why this patient, why now") }, singleLine = true)
            }
        }
        HorizontalDivider(color = CaseInk.hairline)
        Box(Modifier.fillMaxWidth().background(CaseInk.ward).padding(horizontal = 16.dp, vertical = 10.dp)) {
            CaseButton("Discharge and debrief", ::discharge,
                Modifier.fillMaxWidth().semantics {
                    stateDescription = if (ready) "Closes the case and shows what mattered" else "Confirm a diagnosis and choose a next step first"
                },
                primary = true, enabled = ready, icon = Icons.Filled.Description)
        }
    }
}
