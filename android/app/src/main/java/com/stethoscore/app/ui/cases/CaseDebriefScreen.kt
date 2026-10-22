package com.stethoscore.app.ui.cases

import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.quiz.ChartQuiz
import com.stethoscore.app.ui.WardOptionRow
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.*
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.ui.ScreenHeader
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** "Another patient like this", the debrief's writer half (iOS CaseDebriefView.another), kept apart so it is tested. */
internal object CaseAnother {
    /** The brief: the same diagnosis unlike this presentation, or the runner-up's. */
    fun brief(file: CaseFile, sameDiagnosis: Boolean): CaseWriting.Brief =
        if (sameDiagnosis) CaseWriting.Brief(diagnosis = file.diagnosis.name,
            unlike = "${file.patient.ageSex}, ${file.setting.rawValue}, \u201C${file.complaint}\u201D")
        else CaseWriting.Brief(diagnosis = file.runnerUp?.name)

    /** One new patient from the set's lecture (or, with none kept, what this case asserts). */
    suspend fun write(file: CaseFile, set: StudySet, sameDiagnosis: Boolean, writer: CaseMaker.Writer): List<CaseFile> {
        val pages = set.sources.flatMap { doc -> doc.pages.map { it.number to it.text } }
        val source = if (pages.isEmpty()) file.assertedText else CaseMaker.sourceText(pages)
        val lecture = set.sources.firstOrNull()?.name ?: file.source.lecture
        return CaseMaker.write(1, source, lecture, set.subject, brief(file, sameDiagnosis), writer).cases
    }

    const val ready = "A new patient is waiting in this set\u2019s list."
}

/**
 * The debrief, as a discharge summary: missed red flags first in Resus Red,
 * then the diagnosis (right or wrong) with what separates it from the
 * runner-up, the key findings found, the turning point against when the
 * ladder moved, the time and the low-yield steps, and three teaching points
 * with their source. The score is shown with its parts, never as a rank.
 * Port of iOS CaseDebriefView.
 *
 * Three things to do with it: cards from what was missed, a note in the
 * Ideas map, and another patient like this one, written by the writer chosen
 * the writer route (blocked, it says so, in CaseMaker's words).
 */
@Composable
internal fun CaseDebriefScreen(file: CaseFile, setID: String, run: CaseRun, store: StudyStore, title: String, onBack: () -> Unit, again: () -> Unit) {
    val debrief = remember(file, run) { CaseDebrief(file, run) }
    val view = LocalView.current
    var cardsNote by rememberSaveable(file.id, run.finished) { mutableStateOf<String?>(null) }
    var ideaNote by rememberSaveable(file.id, run.finished) { mutableStateOf<String?>(null) }
    var anotherNote by rememberSaveable(file.id, run.finished) { mutableStateOf<String?>(null) }
    var writing by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
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

    /** A new patient, the same diagnosis or the runner-up's, into this set's list. */
    fun another(sameDiagnosis: Boolean) {
        anotherNote = null
        val current = set ?: return
        if (writing != null) return
        val llm = LLMService.from(context)
        val writer = CaseMaker.writer(llm.backend()) ?: run {
            anotherNote = CaseMaker.noWriter(llm.cloudBlocker)
            return
        }
        anotherNote = "Writing another patient\u2026"
        writing = scope.launch {
            try {
                val made = CaseAnother.write(file, current, sameDiagnosis, writer)
                store.library.firstOrNull { it.id == setID }?.let { latest -> store.updateSet(latest.copy(caseFiles = latest.caseFiles + made)) }
                anotherNote = CaseAnother.ready
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                anotherNote = e.message ?: "The patient could not be written."
            } finally {
                writing = null
            }
            view.announce(anotherNote ?: "")
        }
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
                Text("Discharge summary", Modifier.semantics { heading() }, style = WardTextStyle.title2.textStyle(WardWeight.bold))
                Text("${file.patient.ageSex} · ${file.setting.label} · “${file.complaint}”", style = WardTextStyle.subheadline.textStyle(), color = CaseInk.biro, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }

        val score = debrief.score
        CaseCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CaseLabel("Score", Modifier.weight(1f))
                Text("${score.total} / 100", style = WardTextStyle.title2.textStyle(WardWeight.bold, mono = true))
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
                    Text("Capped at 60: a must-not-miss red flag was missed.", style = WardTextStyle.footnote.textStyle(WardWeight.semibold), color = CaseInk.resus)
                }
            }
        }

        if (debrief.missedRedFlags.isNotEmpty()) {
            CaseCard(Modifier.border(2.dp, CaseInk.resus, CaseCardShape)) {
                CaseLabel("Missed red flags")
                for (step in debrief.missedRedFlags) {
                    Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text((if (step.mustNotMiss) "Must not miss · " else "") + step.label, style = WardTextStyle.subheadline.textStyle(WardWeight.bold), color = CaseInk.resus)
                        Text(step.finding, color = CaseInk.resus)
                        if (step.note.isNotEmpty()) Text(step.note, style = WardTextStyle.footnote.textStyle(), color = CaseInk.resus)
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
                Text(file.diagnosis.name, style = WardType.title.textStyle())
            }
            if (!debrief.diagnosisRight) Text("You said: ${debrief.chosenDiagnosis}", style = WardTextStyle.subheadline.textStyle(), color = CaseInk.biro)
            val other = file.runnerUp
            if (other != null && debrief.separating.isNotEmpty()) {
                Text("What tells it from ${other.name}:", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold))
                for (item in debrief.separating) FindingRow(item)
            }
            HorizontalDivider(color = CaseInk.hairline)
            CaseLabel("Next step")
            val chosen = debrief.chosenNextStep
            if (chosen != null && !debrief.nextStepRight) {
                WardOptionRow(AccuracyItem.letter(run.decision?.nextStep ?: 0), chosen, ChartQuiz.Mark.wrong, modifier = Modifier.clearAndSetSemantics { contentDescription = "Your choice: $chosen, wrong" })
            }
            WardOptionRow(AccuracyItem.letter(file.nextStep.key), debrief.rightNextStep, ChartQuiz.Mark.right, modifier = Modifier.clearAndSetSemantics { contentDescription = "Right next step: ${debrief.rightNextStep}" })
            if (file.nextStep.why.isNotEmpty()) Text(file.nextStep.why, style = WardTextStyle.subheadline.textStyle())
            val reason = run.decision?.reason.orEmpty()
            if (reason.isNotEmpty()) Text("Your reason: $reason", style = WardTextStyle.footnote.textStyle(), color = CaseInk.biro)
        }

        CaseCard {
            Row(Modifier.semantics(mergeDescendants = true) { }, verticalAlignment = Alignment.CenterVertically) {
                CaseLabel("Key findings", Modifier.weight(1f))
                Text("${debrief.keyFound} of ${debrief.keyFindings.size} found", style = WardTextStyle.subheadline.textStyle(mono = true))
            }
            for (item in debrief.keyFindings) FindingRow(item)
        }

        CaseCard(spacing = 8.dp) {
            CaseLabel("Turning point")
            Text(debrief.turningSaid, style = WardTextStyle.subheadline.textStyle())
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
                            Text("${taken.at} min", Modifier.widthIn(min = 48.dp), style = WardTextStyle.caption.textStyle(mono = true), color = CaseInk.biro)
                            Text(label ?: "", Modifier.weight(1f), style = WardType.caption.textStyle())
                            Text(lead, style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = if (right) CaseInk.discharge else CaseInk.ink)
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
                Text("No low-yield steps.", style = WardTextStyle.subheadline.textStyle(), color = CaseInk.biro)
            } else {
                Text("Low-yield here:", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold))
                for (step in debrief.lowYield) {
                    Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("${step.label} · ${step.minutes} min", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold))
                        if (step.note.isNotEmpty()) Text(step.note, style = WardTextStyle.subheadline.textStyle())
                    }
                }
            }
        }

        CaseCard(spacing = 8.dp) {
            CaseLabel("Teaching")
            file.teaching.forEachIndexed { index, point ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("${index + 1}.", Modifier.clearAndSetSemantics { }, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold, mono = true), color = CaseInk.theatre)
                    Text(point, style = WardTextStyle.subheadline.textStyle())
                }
            }
            val cited = file.source.cited
            if (cited.isNotEmpty()) Text("Source: $cited", style = WardTextStyle.footnote.textStyle(), color = CaseInk.biro)
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
            CaseButton("Same diagnosis, a new presentation", { another(true) },
                Modifier.fillMaxWidth().semantics { stateDescription = "Writes another patient with ${file.diagnosis.name}, presented differently, into this set" },
                enabled = writing == null, icon = Icons.Filled.PersonAdd)
            file.runnerUp?.let { other ->
                CaseButton("The runner-up: ${other.name}", { another(false) },
                    Modifier.fillMaxWidth().semantics { stateDescription = "Writes a patient whose diagnosis is ${other.name} into this set" },
                    enabled = writing == null, icon = Icons.Filled.Group)
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
            Text(item.step.label, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold))
            Text(item.step.finding, style = WardTextStyle.subheadline.textStyle())
        }
    }
}

@Composable
private fun NoteLine(text: String) = Text(text, style = WardTextStyle.footnote.textStyle(), color = CaseInk.biro)
