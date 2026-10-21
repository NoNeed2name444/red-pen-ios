package com.stethoscore.app.ui.cases

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.ScreenHeader

/**
 * The debrief, as a discharge summary: missed red flags first in Resus Red,
 * then the diagnosis (right or wrong) with what separates it from the
 * runner-up, the key findings found, the turning point against when the
 * ladder moved, the time and the low-yield steps, and three teaching points
 * with their source. The score is shown with its parts, never as a rank.
 * Port of iOS CaseDebriefView.
 *
 * Three things to do with it: cards from what was missed, a note in the
 * Ideas map, and another patient like this one (which needs a case writer,
 * not on Android yet: it says so, in CaseMaker's words).
 */
@Composable
internal fun CaseDebriefScreen(file: CaseFile, setID: String, run: CaseRun, store: StudyStore, title: String, onBack: () -> Unit, again: () -> Unit) {
    val debrief = remember(file, run) { CaseDebrief(file, run) }
    val view = LocalView.current
    var cardsNote by rememberSaveable(file.id, run.finished) { mutableStateOf<String?>(null) }
    var ideaNote by rememberSaveable(file.id, run.finished) { mutableStateOf<String?>(null) }
    var anotherNote by rememberSaveable(file.id, run.finished) { mutableStateOf<String?>(null) }
    val set = store.library.firstOrNull { it.id == setID }

    /** One basic card per missed key finding or red flag, into a deck of their own so they come up in review with the rest. */
    fun makeCards() {
        val made = debrief.cards
        if (made.isEmpty()) return
        val deckName = "Missed in cases"
        val deck = store.library.firstOrNull { it.kind == StudySetKind.ANKI && it.name == deckName }
        cardsNote = if (deck != null) {
            val fronts = deck.cards.map { it.front }.toSet()
            val fresh = made.filter { it.front !in fronts }
            store.updateSet(deck.copy(cards = deck.cards + fresh))
            if (fresh.isEmpty()) "Those cards are in “$deckName” already."
            else "${fresh.size} card${if (fresh.size == 1) "" else "s"} added to “$deckName”."
        } else {
            store.addSet(StudySet(name = deckName, subject = set?.subject ?: "General", kind = StudySetKind.ANKI, cards = made))
            "${made.size} card${if (made.size == 1) "" else "s"} in a new deck, “$deckName”."
        }
        view.announce(cardsNote ?: "")
    }

    fun addIdea() {
        val title = debrief.ideaTitle
        val body = debrief.ideaText
        ideaNote = if (store.notes.any { it.title == title && it.body == body }) "Already in Ideas" else {
            store.saveNote(Note(title = title, body = body, tags = listOf(set?.subject ?: file.specialty).filter { it.isNotBlank() }))
            "Saved to Ideas"
        }
        view.announce(ideaNote ?: "")
    }

    /** A new patient, the same diagnosis or the runner-up's: needs a writer, which Android does not have yet. */
    fun another() {
        anotherNote = null
        if (CaseMaker.writer() == null) anotherNote = CaseMaker.noWriter()
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp).widthIn(max = 760.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        ScreenHeader(title, "", onBack)
        // the summary
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            CaseAvatar(file.patient.initials)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Discharge summary", Modifier.semantics { heading() }, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text("${file.patient.ageSex} · ${file.setting.label} · “${file.complaint}”", fontSize = 15.sp, color = CaseInk.biro, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }

        val score = debrief.score
        CaseCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CaseLabel("Score", Modifier.weight(1f))
                Text("${score.total} / 100", fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 22.sp)
            }
            for (part in score.parts) {
                Row(Modifier.clearAndSetSemantics { contentDescription = "${part.label}: ${part.points} of ${part.of}" }) {
                    Text(part.label, Modifier.weight(1f))
                    Text("${part.points} / ${part.of}", fontFamily = FontFamily.Monospace, color = if (part.points == part.of) CaseInk.discharge else CaseInk.ink)
                }
            }
            if (score.capped) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Warning, null, tint = CaseInk.resus, modifier = Modifier.size(16.dp))
                    Text("Capped at 60: a must-not-miss red flag was missed.", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = CaseInk.resus)
                }
            }
        }

        if (debrief.missedRedFlags.isNotEmpty()) {
            CaseCard(Modifier.border(2.dp, CaseInk.resus, CaseCardShape)) {
                CaseLabel("Missed red flags")
                for (step in debrief.missedRedFlags) {
                    Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text((if (step.mustNotMiss) "Must not miss · " else "") + step.label, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = CaseInk.resus)
                        Text(step.finding, color = CaseInk.resus)
                        if (step.note.isNotEmpty()) Text(step.note, fontSize = 13.sp, color = CaseInk.resus)
                    }
                }
            }
        }

        CaseCard {
            CaseLabel("Diagnosis")
            Row(
                Modifier.clearAndSetSemantics {
                    contentDescription = "Diagnosis: ${file.diagnosis.name}. " + if (debrief.diagnosisRight) "You were right." else "You said ${debrief.chosenDiagnosis}."
                },
                horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(if (debrief.diagnosisRight) Icons.Filled.CheckCircle else Icons.Filled.Cancel, null, tint = if (debrief.diagnosisRight) CaseInk.discharge else CaseInk.resus)
                Text(file.diagnosis.name, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
            }
            if (!debrief.diagnosisRight) Text("You said: ${debrief.chosenDiagnosis}", fontSize = 15.sp, color = CaseInk.biro)
            val other = file.runnerUp
            if (other != null && debrief.separating.isNotEmpty()) {
                Text("What tells it from ${other.name}:", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                for (item in debrief.separating) FindingRow(item)
            }
            HorizontalDivider(color = CaseInk.hairline)
            CaseLabel("Next step")
            val chosen = debrief.chosenNextStep
            if (chosen != null && !debrief.nextStepRight) {
                CaseOptionRow(run.decision?.nextStep ?: 0, chosen, CaseMark.wrong, Modifier.clearAndSetSemantics { contentDescription = "Your choice: $chosen, wrong" })
            }
            CaseOptionRow(file.nextStep.key, debrief.rightNextStep, CaseMark.right, Modifier.clearAndSetSemantics { contentDescription = "Right next step: ${debrief.rightNextStep}" })
            if (file.nextStep.why.isNotEmpty()) Text(file.nextStep.why, fontSize = 15.sp)
            val reason = run.decision?.reason.orEmpty()
            if (reason.isNotEmpty()) Text("Your reason: $reason", fontSize = 13.sp, color = CaseInk.biro)
        }

        CaseCard {
            Row(Modifier.semantics(mergeDescendants = true) { }, verticalAlignment = Alignment.CenterVertically) {
                CaseLabel("Key findings", Modifier.weight(1f))
                Text("${debrief.keyFound} of ${debrief.keyFindings.size} found", fontFamily = FontFamily.Monospace, fontSize = 15.sp)
            }
            for (item in debrief.keyFindings) FindingRow(item)
        }

        CaseCard(spacing = 8.dp) {
            CaseLabel("Turning point")
            Text(debrief.turningSaid, fontSize = 15.sp)
            if (run.ladders.isNotEmpty()) {
                // the lead of the ladder after each step, in order
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    run.taken.forEachIndexed { index, taken ->
                        val lead = run.ladders.getOrNull(index)?.firstOrNull() ?: "—"
                        val right = file.isDiagnosis(lead)
                        val label = file.step(taken.stepID)?.label
                        Row(
                            Modifier.clearAndSetSemantics { contentDescription = "After ${label ?: "a step"}, your leading diagnosis was $lead" },
                            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text("${taken.at} min", Modifier.widthIn(min = 48.dp), fontFamily = FontFamily.Monospace, fontSize = 12.sp, color = CaseInk.biro)
                            Text(label ?: "", Modifier.weight(1f), fontSize = 12.sp)
                            Text(lead, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = if (right) CaseInk.discharge else CaseInk.ink)
                        }
                    }
                }
            }
        }

        CaseCard(spacing = 8.dp) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CaseLabel("Time", Modifier.weight(1f))
                CaseClockPill(debrief.minutesUsed, file.budgetMinutes)
            }
            if (debrief.lowYield.isEmpty()) {
                Text("No low-yield steps.", fontSize = 15.sp, color = CaseInk.biro)
            } else {
                Text("Low-yield here:", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                for (step in debrief.lowYield) {
                    Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("${step.label} · ${step.minutes} min", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        if (step.note.isNotEmpty()) Text(step.note, fontSize = 15.sp)
                    }
                }
            }
        }

        CaseCard(spacing = 8.dp) {
            CaseLabel("Teaching")
            file.teaching.forEachIndexed { index, point ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("${index + 1}.", Modifier.clearAndSetSemantics { }, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = CaseInk.theatre)
                    Text(point, fontSize = 15.sp)
                }
            }
            val cited = file.source.cited
            if (cited.isNotEmpty()) Text("Source: $cited", fontSize = 13.sp, color = CaseInk.biro)
        }

        // what to do with it
        CaseCard {
            CaseButton("Make cards from what I missed", ::makeCards,
                Modifier.fillMaxWidth().semantics {
                    stateDescription = if (debrief.missed.isEmpty()) "Nothing was missed" else "One card for each missed key finding or red flag, into your review"
                },
                enabled = debrief.missed.isNotEmpty(), icon = Icons.Filled.LibraryAdd)
            cardsNote?.let { NoteLine(it) }
            CaseButton("Add to the Ideas map", ::addIdea, Modifier.fillMaxWidth(), icon = Icons.Filled.Lightbulb)
            ideaNote?.let { NoteLine(it) }

            CaseLabel("Another patient like this")
            CaseButton("Same diagnosis, a new presentation", ::another,
                Modifier.fillMaxWidth().semantics { stateDescription = "Writes another patient with ${file.diagnosis.name}, presented differently, into this set" },
                icon = Icons.Filled.PersonAdd)
            file.runnerUp?.let { other ->
                CaseButton("The runner-up: ${other.name}", ::another,
                    Modifier.fillMaxWidth().semantics { stateDescription = "Writes a patient whose diagnosis is ${other.name} into this set" },
                    icon = Icons.Filled.Group)
            }
            anotherNote?.let { NoteLine(it) }

            TextButton(again, Modifier.fillMaxWidth().heightIn(min = 44.dp)) {
                Icon(Icons.Filled.Replay, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("See this patient again", Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun FindingRow(item: CaseDebrief.Item) {
    Row(
        Modifier.clearAndSetSemantics { contentDescription = "${item.step.label}: ${item.step.finding}. " + if (item.found) "Found." else "Not found." },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(if (item.found) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null,
            tint = if (item.found) CaseInk.discharge else CaseInk.biro, modifier = Modifier.size(18.dp).padding(top = 2.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(item.step.label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text(item.step.finding, fontSize = 15.sp)
        }
    }
}

@Composable
private fun NoteLine(text: String) = Text(text, fontSize = 13.sp, color = CaseInk.biro)
