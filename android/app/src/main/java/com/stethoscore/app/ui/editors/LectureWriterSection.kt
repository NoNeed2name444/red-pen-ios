package com.stethoscore.app.ui.editors

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.NoteAdd
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.CaseMaker
import com.stethoscore.app.data.CardStyle
import com.stethoscore.app.data.DiagramCards
import com.stethoscore.app.data.LectureForms
import com.stethoscore.app.data.ReadSource
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.exam.ExamChoice
import com.stethoscore.app.llm.BatchWriting
import com.stethoscore.app.llm.LectureWriter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import com.stethoscore.app.ui.ward.WardBanner
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.ward.WardTextField
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// A port of ios/RedPen/Features/Library/LectureWriterSection.swift
// (fed0105): writing Cards or a Textbook from a lecture, for New set. Step 2
// takes a lecture file, or notes pasted in, or both; step 3 the card type
// (Cards only), how many, the one big button and the rest behind More options.
//
// What it writes lands in the draft as lines to check (onBodyText), written by
// the writer route only (LLMService.backend(), Pro; LectureWriter), one run at
// a time through GenerationCenter. With no writer, Make says the cloud's own
// reason (CaseMaker.noWriter(llm.cloudBlocker)), as the question, case and
// station screens do, and nothing is written on the phone. What a run could
// not write is said, and offered again on its own (BatchWriting.Shortfall).
// Labelled diagrams are not looked for on Android (no text reader in this
// build), so Image occlusion finds none and says so.

@Composable fun LectureWriterSection(
    kind: StudySetKind,
    bodyText: String,
    onBodyText: (String) -> Unit,
    readSource: ReadSource?,
    onReadSource: (ReadSource?) -> Unit,
    suggestedName: String,
    onSuggestedName: (String) -> Unit,
    diagrams: DiagramCards,
    onDiagrams: (DiagramCards) -> Unit,
    subject: String,
    onSubject: (String) -> Unit,
    step: LectureStep,
    presetNotes: String = "",
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val llm = rememberLLMService()
    val backend = remember(step) { llm.backend() }
    // the run lives in GenerationCenter, for the process (as MCQGenerateForm's)
    val ownOwner = rememberGenerationOwner()
    val generationOwner = LocalGenerationOwner.current ?: ownOwner
    val running: GenerationCenter.Job? = GenerationCenter.job?.takeIf { GenerationCenter.runs(generationOwner) }
    val working = running != null
    var style by rememberSaveable { mutableStateOf(CardStyle.mixed) }
    var pastedNotes by rememberSaveable { mutableStateOf("") }
    var showMore by rememberSaveable { mutableStateOf(false) }
    var count by rememberSaveable { mutableIntStateOf(12) }
    var reading by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    var trouble by remember { mutableStateOf<String?>(null) }
    var missing by remember { mutableStateOf<MissingWrite?>(null) }
    val book = kind == StudySetKind.BOOK
    val noun = if (book) "page" else "card"
    // what is said under Make: the run's count while it runs, else its last word
    val said: String? = running?.let { "Writing ${it.done} of ${it.total}\u2026" } ?: GenerationCenter.note(generationOwner) ?: status

    LaunchedEffect(Unit) { if (pastedNotes.isEmpty() && presetNotes.isNotEmpty()) pastedNotes = presetNotes }

    val sourceText = listOf(readSource?.text ?: "", pastedNotes).filter { it.isNotEmpty() }.joinToString("\n\n")
    val hasSource = LectureForms.hasSource(sourceText)
    val canWrite = if (kind == StudySetKind.ANKI && style == CardStyle.image) diagrams.cards.isNotEmpty() else hasSource
    val actionTitle = LectureForms.writerActionTitle(book, style, count, diagrams.cards.size)

    // a finished run's draft, handed to whichever screen now holds this owner
    val made = GenerationCenter.result(generationOwner)
    val latestBody by rememberUpdatedState(bodyText)
    val latestOnBody by rememberUpdatedState(onBodyText)
    LaunchedEffect(made) {
        val written = made as? WrittenDraft ?: return@LaunchedEffect
        GenerationCenter.take(generationOwner)
        latestOnBody(written.into(latestBody))
        missing = written.missing
    }

    fun diagramsWanted(chosen: CardStyle): Boolean {
        val found = diagrams.cards.isNotEmpty()
        val alongside = chosen == CardStyle.image || bodyText.isNotEmpty()
        return chosen.usesDiagrams && found && alongside
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        trouble = null
        if (uri == null) return@rememberLauncherForActivityResult
        reading = true
        status = "Reading…"
        onDiagrams(DiagramCards())
        scope.launch {
            try {
                val file = withContext(Dispatchers.IO) { LectureFiles.read(context, uri) }
                val source = ReadSource(name = file.name, pages = file.pages, kind = LectureForms.writerFileKind(file.extension))
                onReadSource(source)
                if (suggestedName.trim().isEmpty()) onSuggestedName(file.name)
                count = LectureForms.writerCount(book, file.pages.size)
                status = null
                val joined = listOf(source.text, pastedNotes).filter { it.isNotEmpty() }.joinToString("\n\n")
                if (!LectureForms.hasSource(joined)) trouble = "There is not much text in that file to work from."
            } catch (e: Exception) {
                status = null
                trouble = e.message ?: "That file could not be read."
            }
            reading = false
        }
    }

    /** [retry]: what an earlier run left out, written on its own; null for the whole set (iOS write(retry:)). */
    fun write(retry: MissingWrite?) {
        val writer = backend ?: run { trouble = CaseMaker.noWriter(llm.cloudBlocker); return }
        val owner = generationOwner
        val text = sourceText
        val subj = subject
        val mode = kind
        val cardStyle = style
        val exam = ExamChoice.currentTrack(ExamChoice.defaults(context))
        // a second try writes only what the first left out
        val pages = retry?.pages ?: count
        val wanted = retry?.shortfall?.missing ?: count
        val parts = retry?.shortfall?.parts?.takeIf { it.isNotEmpty() }
        val already = if (retry == null) emptyList() else bodyText.split("\n")
        val asked = if (mode == StudySetKind.BOOK) pages else wanted
        if (retry == null) missing = null
        status = null
        var work: Job? = null
        val job = GenerationCenter.begin("Writing $wanted ${BatchWriting.plural(noun, wanted)}", wanted, owner) {
            work?.cancel()
            GenerationCenter.note(owner, "Cancelled.")
        } ?: run { trouble = GenerationCenter.busy; return }
        GenerationCenter.note(owner, null)
        work = GenerationCenter.launch(scope.coroutineContext) {
            try {
                val result = LectureWriter.draft(mode, text, asked, subj, writer, style = cardStyle, exam = exam,
                    already = already, parts = parts) { done, total -> GenerationCenter.update(job, done, total) }
                // a run cancelled or overtaken says nothing more
                if (!GenerationCenter.end(job)) return@launch
                GenerationCenter.note(owner, result.shortfall?.message(noun) ?: "Written \u2014 check them below.")
                GenerationCenter.deliver(owner, WrittenDraft(result, refill = mode == StudySetKind.BOOK && retry != null,
                    missing = result.shortfall?.let { MissingWrite(it, mode, text, writer.label, pages) }))
            } catch (e: CancellationException) {
                GenerationCenter.end(job)
                throw e
            } catch (e: Exception) {
                if (GenerationCenter.end(job)) GenerationCenter.note(owner, null)
                trouble = e.message ?: "The ${noun}s could not be written. Try again."
            }
        }
    }

    fun start() {
        trouble = null
        GenerationCenter.note(generationOwner, null)
        // image occlusion alone needs no model: the diagrams are the cards
        if (kind == StudySetKind.ANKI) {
            onDiagrams(diagrams.copy(included = style.usesDiagrams && diagrams.cards.isNotEmpty()))
            if (style == CardStyle.image) {
                val found = diagrams.cards.size
                status = if (found == 0) null else "$found image card${if (found == 1) "" else "s"} ready — save the set below."
                if (found == 0) trouble = "No labelled diagrams were found in this file."
                return
            }
        }
        // something else is being written: said here, and left running
        GenerationCenter.busy?.let { trouble = it; return }
        write(null)
    }

    /** Whether what the last run could not write can be written now: the same kind, lecture and writer, and a draft to add to. */
    fun canWriteMissing(left: MissingWrite): Boolean =
        left.kind == kind && left.source == sourceText && left.writer == backend?.label && bodyText.isNotBlank()

    fun writeMissing() {
        trouble = null
        GenerationCenter.busy?.let { trouble = it; return }
        val left = missing?.takeIf { canWriteMissing(it) } ?: return
        write(left)
    }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        if (step == LectureStep.material) {
            EditorSection("Add a file", footer = "PDF, Word or PowerPoint. It is read on this device.") {
                // second to the dock's Next
                WardButtonBox({ picker.launch(LectureFiles.types) }, Modifier.fillMaxWidth(), kind = WardButtonKind.secondary, enabled = !working && !reading) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (reading) EcgLoader()
                        Icon(Icons.AutoMirrored.Rounded.NoteAdd, null)
                        Text(LectureForms.writerPickTitle(reading, readSource != null))
                    }
                }
                readSource?.let { src ->
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.CheckCircle, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
                        EditorNote("${src.name} — ${src.pages.size} pages")
                    }
                }
                trouble?.let { WardBanner(it, Icons.Rounded.Warning, WardTone.Danger) }
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    EditorRowTitle("Or paste your notes")
                    EditorTextArea(pastedNotes, { pastedNotes = it }, minHeight = 120.dp, enabled = !working, label = "Or paste your notes")
                }
            }
        }
        if (step == LectureStep.make) {
            EditorSection(null) {
                if (kind == StudySetKind.ANKI) {
                    CardTypePicker(style, enabled = !working) { now ->
                        style = now
                        onDiagrams(diagrams.copy(included = diagramsWanted(now)))
                    }
                    if (style.usesDiagrams && readSource != null) EditorNote(LectureForms.diagramNote(diagrams.cards.size))
                }
                if (style.writesText || kind != StudySetKind.ANKI) {
                    CountField("How many ${noun}s", count, if (book) 1..1_000 else 1..10_000, { count = it }, enabled = !working)
                }
                // the same as its floating copy in the dock
                FloatingActionRegistration("writer", actionTitle, canWrite && !working && !reading, working, Icons.Rounded.EditNote) { start() }
                WardButtonBox({ start() }, Modifier.fillMaxWidth().floatingActionAnchor("writer"), kind = WardButtonKind.primary, enabled = canWrite && !working && !reading) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (reading || working) EcgLoader()
                        Text(when {
                            reading -> "Reading…"
                            working -> said ?: "Writing\u2026"
                            else -> actionTitle
                        })
                    }
                }
                said?.takeIf { !working }?.let { EditorNote(it) }
                // what the last run could not write, and only that, again
                missing?.takeIf { !working && canWriteMissing(it) }?.let { left ->
                    WardButtonBox(::writeMissing, kind = WardButtonKind.compact, fills = false, enabled = !reading) {
                        Text(left.shortfall.retryTitle(noun))
                    }
                }
                if (!hasSource && !(kind == StudySetKind.ANKI && style == CardStyle.image)) {
                    EditorNote("Go back and add a lecture first.")
                }
                trouble?.let { WardBanner(it, Icons.Rounded.Warning, WardTone.Danger) }
                MoreOptions("More options", showMore, { showMore = it }) {
                    WardTextField(subject, onSubject, Modifier.fillMaxWidth(), placeholder = "Subject, e.g. Cardiology", enabled = !working)
                    EditorNote(backend?.let { "Written by ${it.label}. The ${noun}s appear below to check before you save the set." }
                        ?: NoWriter.cards)
                }
            }
        }
    }
}

/** Picker("Card type") in a Form: the title, the choice on the right, the menu under it. */
@Composable private fun CardTypePicker(style: CardStyle, enabled: Boolean, onChange: (CardStyle) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = WardControlSize.target.wardDp)
            .clickable(enabled = enabled, role = Role.DropdownList, onClickLabel = "Choose the card type") { open = true },
            verticalAlignment = Alignment.CenterVertically) {
            Text("Card type", style = WardType.body.textStyle(), color = wardColor(WardToken.ink), modifier = Modifier.weight(1f))
            Text(style.title, style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
            Icon(Icons.Rounded.UnfoldMore, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(18.dp))
        }
        DropdownMenu(open, { open = false }) {
            CardStyle.entries.forEach { option ->
                DropdownMenuItem({ Text(option.title, style = WardTextStyle.body.textStyle(if (option == style) WardWeight.semibold else WardWeight.regular)) },
                    { open = false; onChange(option) },
                    trailingIcon = if (option == style) ({ Icon(Icons.Rounded.CheckCircle, null, tint = wardColor(WardToken.primaryInk)) }) else null)
            }
        }
    }
}

/** What a finished run hands back to the screen: the draft, and what it could not write. */
internal class WrittenDraft(val draft: LectureWriter.Draft, val refill: Boolean, val missing: MissingWrite?) {
    /** The new draft: each page written again in its own gap, else the lines added after what is there. */
    fun into(body: String): String {
        if (refill) return draft.pages.keys.sorted().fold(body) { text, part -> BatchWriting.fill(text, part, draft.pages.getValue(part)) }
        val existing = body.trim()
        return if (existing.isEmpty()) draft.text else existing + "\n" + draft.text
    }
}

/** What a run left out, kept with what it was written from, to write only that again (iOS MissingWrite). */
internal data class MissingWrite(
    val shortfall: BatchWriting.Shortfall,
    val kind: StudySetKind,
    val source: String,
    val writer: String,
    /** The pages the lecture was cut into, for a textbook's second try. */
    val pages: Int,
)
