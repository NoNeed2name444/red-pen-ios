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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.CardStyle
import com.stethoscore.app.data.DiagramCards
import com.stethoscore.app.data.LectureForms
import com.stethoscore.app.data.ReadSource
import com.stethoscore.app.data.StudySetKind
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
// On iOS what it writes lands in the editor as draft lines to check. Android
// has no writer yet, so Make says "No model is ready to write with." the way
// iOS does when none is chosen, and the line under More options says why.
// Labelled diagrams are not looked for on Android (no text reader in this
// build), so Image occlusion finds none and says so.

@Composable fun LectureWriterSection(
    kind: StudySetKind,
    bodyText: String,
    @Suppress("UNUSED_PARAMETER") onBodyText: (String) -> Unit,
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
    var style by rememberSaveable { mutableStateOf(CardStyle.mixed) }
    var pastedNotes by rememberSaveable { mutableStateOf("") }
    var showMore by rememberSaveable { mutableStateOf(false) }
    var count by rememberSaveable { mutableIntStateOf(12) }
    val working = false
    var reading by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    var trouble by remember { mutableStateOf<String?>(null) }
    val book = kind == StudySetKind.BOOK
    val noun = if (book) "page" else "card"

    LaunchedEffect(Unit) { if (pastedNotes.isEmpty() && presetNotes.isNotEmpty()) pastedNotes = presetNotes }

    val sourceText = listOf(readSource?.text ?: "", pastedNotes).filter { it.isNotEmpty() }.joinToString("\n\n")
    val hasSource = LectureForms.hasSource(sourceText)
    val canWrite = if (kind == StudySetKind.ANKI && style == CardStyle.image) diagrams.cards.isNotEmpty() else hasSource
    val actionTitle = LectureForms.writerActionTitle(book, style, count, diagrams.cards.size)

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

    fun start() {
        trouble = null
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
        // no writer on this phone (iOS llm.writerOrApple() == nil)
        trouble = "No model is ready to write with."
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
                trouble?.let { EditorBanner(it, Icons.Rounded.Warning, WardTone.Danger) }
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
                WardButtonBox({ start() }, Modifier.fillMaxWidth(), kind = WardButtonKind.primary, enabled = canWrite && !working && !reading) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (reading) EcgLoader()
                        Text(if (reading) "Reading…" else actionTitle)
                    }
                }
                status?.let { EditorNote(it) }
                if (!hasSource && !(kind == StudySetKind.ANKI && style == CardStyle.image)) {
                    EditorNote("Nothing to write from yet — go Back and add a lecture.")
                }
                trouble?.let { EditorBanner(it, Icons.Rounded.Warning, WardTone.Danger) }
                MoreOptions("More options", showMore, { showMore = it }) {
                    WardTextField(subject, onSubject, Modifier.fillMaxWidth(), placeholder = "Subject, e.g. Cardiology", enabled = !working)
                    EditorNote(NoWriter.cards)
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
            Text(style.title, style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk))
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
