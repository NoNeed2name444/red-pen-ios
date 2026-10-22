package com.stethoscore.app.ui.library

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.ImportPreview
import com.stethoscore.app.data.ImportSource
import com.stethoscore.app.data.LibraryImport
import com.stethoscore.app.data.PlainTextImport
import com.stethoscore.app.data.SetImport
import com.stethoscore.app.data.StudyJson
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.modeIcon
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardIconSquare
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSectionLabel
import com.stethoscore.app.ui.ward.WardSegmented
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextField
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardInset
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.ward.wardRelief
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// iOS Features/Library/NewSetView.swift and NewSetDock.swift: making a set
// in three steps asked one at a time (what kind, where its material comes
// from, then a name and Save), only the step you are on shown, and one slab
// at the bottom with Back and the step's main button.
//
// The lecture path (MCQGenerateForm, LectureWriterSection, the OSCE and case
// writers) belongs to the library editors' batch; until it lands, every kind
// offers typing and a file, and Patient cases a file.

/**
 * New set, opening on [startKind] chosen and still on the first step.
 * [onSaved] is told after a set is saved or an import is in, and closes it.
 */
@Composable fun LibraryNewSetScreen(store: StudyStore, startKind: StudySetKind, onCancel: () -> Unit, onSaved: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var step by rememberSaveable { mutableStateOf(NewSetStep.KIND) }
    var kind by rememberSaveable { mutableStateOf(startKind) }
    var path by rememberSaveable { mutableStateOf(NewSetWords.paths(startKind).first()) }
    var name by rememberSaveable { mutableStateOf("") }
    var subject by rememberSaveable { mutableStateOf("General") }
    var bodyText by rememberSaveable { mutableStateOf("") }
    var showFormat by rememberSaveable { mutableStateOf(false) }
    var moreOptions by rememberSaveable { mutableStateOf(false) }
    var importSource by rememberSaveable { mutableStateOf(ImportSource.ANKI) }
    var importError by remember { mutableStateOf<String?>(null) }
    var readingFile by remember { mutableStateOf<String?>(null) }
    var importPreview by remember { mutableStateOf<ImportPreview?>(null) }
    var importNotice by remember { mutableStateOf<String?>(null) }
    var saveError by remember { mutableStateOf<String?>(null) }

    fun choose(option: StudySetKind) {
        if (option != kind) {
            // each mode's draft is in its own format, so a draft never carries over to another mode
            bodyText = ""
            if (path !in NewSetWords.paths(option)) path = NewSetWords.paths(option).first()
        }
        kind = option
        step = NewSetStep.MATERIAL
    }
    fun goBack() { NewSetStep.entries.firstOrNull { it.number == step.number - 1 }?.let { step = it } }
    BackHandler { if (step == NewSetStep.KIND) onCancel() else goBack() }

    val itemCount = remember(kind, bodyText) {
        when (kind) {
            StudySetKind.MCQ -> PlainTextImport.parseAnyMCQ(bodyText).size
            StudySetKind.ANKI -> PlainTextImport.parseAnyCards(bodyText).size
            StudySetKind.BOOK -> if (bodyText.isBlank()) 0 else LibraryImport.bookPageCount(bodyText)
            StudySetKind.OSCE -> PlainTextImport.parseOsce(bodyText).size
            StudySetKind.NARRATE -> PlainTextImport.parseNarrate(bodyText).size
            StudySetKind.CASES -> 0
        }
    }
    val canGoOn = path != NewSetPath.TYPE || bodyText.isNotBlank()
    val showsCreate = path != NewSetPath.IMPORT_FILE
    val canCreate = name.isNotBlank() && itemCount > 0
    val saveTitle = NewSetWords.saveTitle(kind)

    fun create() {
        if (!canCreate) return
        var set = StudySet(name = name, subject = subject.ifEmpty { "General" }, kind = kind)
        set = when (kind) {
            StudySetKind.MCQ -> set.copy(questions = PlainTextImport.parseAnyMCQ(bodyText))
            StudySetKind.ANKI -> set.copy(cards = PlainTextImport.parseAnyCards(bodyText))
            StudySetKind.BOOK -> set.copy(bookMarkdown = bodyText)
            StudySetKind.OSCE -> set.copy(osceChecklists = PlainTextImport.parseOsce(bodyText))
            StudySetKind.NARRATE -> set.copy(narrateSegments = PlainTextImport.parseNarrate(bodyText))
            StudySetKind.CASES -> return
        }
        runCatching { store.addSet(set) }.onSuccess { onSaved() }.onFailure { saveError = it.message ?: "Unable to save this set" }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        importError = null
        val kindNow = kind
        val subjectNow = subject
        readingFile = LibraryImport.stem(uri.lastPathSegment?.substringAfterLast('/') ?: "file")
        scope.launch {
            val picked = withContext(Dispatchers.IO) { runCatching { readPicked(context, uri) } }.getOrElse {
                readingFile = null
                importError = "Couldn't read that file: ${it.message ?: ""}"
                return@launch
            }
            readingFile = LibraryImport.stem(picked.name)
            val head = picked.data.copyOf(minOf(16, picked.data.size))
            if (ImportSource.of(picked.name, head) != ImportSource.APP_FILE) {
                // a deck or a table: read into a preview, and nothing is added until Import is tapped there
                val made = withContext(Dispatchers.Default) { runCatching { LibraryImport.preview(picked.name, picked.data, kindNow, subjectNow) } }
                readingFile = null
                made.onSuccess { importPreview = it }.onFailure { importError = it.message }
                return@launch
            }
            val received = withContext(Dispatchers.Default) {
                runCatching {
                    val sets = StudyJson.decodeSets(picked.data.toString(Charsets.UTF_8))
                    require(sets.size == 1) { "Choose a single Stethoscore set." }
                    // a new id, no folder this library lacks, no picture that only exists in the sender's account,
                    // and new ids for its cards, so a set shared back never shares a schedule with the original
                    val got = SetImport.received(sets.single().duplicate(), store.folders.map { it.id }.toSet()) { it.startsWith("blob:") }
                    store.addSet(got.set)
                    got
                }
            }
            readingFile = null
            received.onSuccess { got ->
                if (got.missingPictures > 0) importNotice = NewSetWords.missingPictures(got.missingPictures) else onSaved()
            }.onFailure { importError = "Couldn't read that file: ${it.message ?: ""}" }
        }
    }

    Column(Modifier.fillMaxSize()) {
        // Cancel, and the title in the middle (iOS's inline navigation title)
        Row(Modifier.fillMaxWidth().padding(horizontal = WardSpace.s.wardDp, vertical = WardSpace.xs.wardDp),
            verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.widthIn(min = 88.dp)) { WardTextButton("Cancel", onCancel, kind = WardButtonKind.quiet, fills = false) }
            Text("New set", style = WardType.headline.textStyle(), color = wardColor(WardToken.ink),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.weight(1f).semantics { heading() })
            Spacer(Modifier.widthIn(min = 88.dp).size(width = 88.dp, height = 1.dp))
        }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.xl.wardDp)) {
            StepHeader(step) { step = it }
            when (step) {
                NewSetStep.KIND -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    StudySetKind.entries.forEach { option -> ModeTile(option, kind == option) { choose(option) } }
                }
                NewSetStep.MATERIAL -> {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        NewSetWords.paths(kind).forEach { option -> PathTile(option, path == option) { path = option } }
                    }
                    if (path == NewSetPath.TYPE) DraftSection("Type or paste", kind, bodyText, { bodyText = it }, showFormat) { showFormat = !showFormat }
                    if (path == NewSetPath.IMPORT_FILE) LibraryFormSection {
                        WardSegmented(importSource, ImportSource.entries, { importSource = it; importError = null },
                            Modifier.fillMaxWidth().semantics { contentDescription = "From" }) { source, style, color ->
                            Text(source.title, style = style, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        val reading = readingFile
                        val error = importError
                        when {
                            reading != null -> Text("Reading “$reading”…", style = WardTextStyle.footnote.textStyle(),
                                color = wardColor(WardToken.ink), maxLines = 2)
                            error != null -> LibraryBanner(error, Icons.Rounded.Warning, WardTone.Danger)
                            else -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(sourceIcon(importSource), null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
                                Text(importSource.help, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
                            }
                        }
                    }
                }
                NewSetStep.MAKE -> {
                    Column(verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
                        WardSectionLabel("Name your set")
                        WardTextField(name, { name = it }, Modifier.fillMaxWidth().semantics { contentDescription = "Name" }, placeholder = "e.g. Cardiology week 3")
                    }
                    if (showsCreate) LibraryFormSection(footer = NewSetWords.readiness(kind, itemCount, name)) {
                        Row(Modifier.fillMaxWidth().heightIn(min = WardControlSize.target.wardDp).clickable(role = Role.Button) { moreOptions = !moreOptions },
                            verticalAlignment = Alignment.CenterVertically) {
                            Text("More options", style = WardTextStyle.body.textStyle(), color = wardColor(WardToken.ink), modifier = Modifier.weight(1f))
                            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.primaryInk),
                                modifier = Modifier.size(18.dp).rotate(if (moreOptions) 90f else 0f))
                        }
                        if (moreOptions) WardTextField(subject, { subject = it }, Modifier.fillMaxWidth().semantics { contentDescription = "Subject" },
                            placeholder = "Subject, e.g. Cardiology")
                        WardButtonBox(::create, Modifier.fillMaxWidth(), kind = WardButtonKind.primary, enabled = canCreate) {
                            Icon(Icons.Rounded.Check, null, Modifier.size(18.dp)); Text(saveTitle)
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
        if (step != NewSetStep.KIND) NewSetDock(
            hint = NewSetWords.dockHint(step, path, canGoOn),
            back = ::goBack,
        ) {
            when {
                step == NewSetStep.MATERIAL && path == NewSetPath.IMPORT_FILE ->
                    WardButtonBox({ picker.launch(importSource.mimeTypes) }, kind = WardButtonKind.primary, fills = false, enabled = readingFile == null) {
                        Icon(Icons.Rounded.Download, null, Modifier.size(18.dp)); Text("Choose a file")
                    }
                step == NewSetStep.MATERIAL ->
                    WardButtonBox({ step = NewSetStep.MAKE }, kind = WardButtonKind.primary, fills = false, enabled = canGoOn) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowForward, null, Modifier.size(18.dp)); Text("Next")
                    }
                showsCreate ->
                    WardButtonBox(::create, kind = WardButtonKind.primary, fills = false, enabled = canCreate) {
                        Icon(Icons.Rounded.Check, null, Modifier.size(18.dp))
                        Text(saveTitle, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
            }
        }
    }

    importPreview?.let { preview ->
        ImportPreviewSheet(preview, onDismiss = { importPreview = null }) {
            runCatching { LibraryImport.commit(preview, store) }
                .onSuccess { importPreview = null; onSaved() }
                .onFailure { importPreview = null; importError = it.message }
        }
    }
    importNotice?.let { notice -> LibraryAlert("Set imported", notice) { importNotice = null; onSaved() } }
    saveError?.let { message -> LibraryAlert("Couldn’t save", message) { saveError = null } }
}

/** "1 Choose, 2 Add, 3 Make" and the step's question; a step already done is a button back to it. */
@Composable private fun StepHeader(step: NewSetStep, goTo: (NewSetStep) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth().semantics { contentDescription = "Step ${step.number} of 3" }, verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NewSetStep.entries.forEach { one ->
                StepDot(one, step, if (one.number < step.number) ({ goTo(one) }) else null)
                if (one != NewSetStep.MAKE) {
                    if (one.number < step.number) Box(Modifier.weight(1f).height(2.dp).background(wardColor(WardToken.primaryInk), CircleShape))
                    else LibraryEtch(Modifier.weight(1f))
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            WardSmallCapsText("New admission")
            Text(step.question, style = WardTextStyle.title2.textStyle(WardWeight.bold), color = wardColor(WardToken.ink),
                modifier = Modifier.semantics { heading() })
        }
    }
}

/**
 * One step: a numbered dot, ticked once done, with its name beside it. A done
 * step is raised (it can be gone back to), the current one pressed in with
 * its number in the accent, one still to come pressed in, in grey (iOS NewSetStepDot).
 */
@Composable private fun StepDot(one: NewSetStep, current: NewSetStep, onClick: (() -> Unit)?) {
    val done = one.number < current.number
    val here = one == current
    val ink = wardColor(if (done || here) WardToken.primaryInk else WardToken.inkSecondary)
    val tap = if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick)
        .semantics { contentDescription = "Back to step ${one.number}, ${one.short}" } else Modifier
    Row(Modifier.heightIn(min = WardControlSize.target.wardDp).then(tap), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(28.dp).then(if (done) Modifier.wardRaised(14.0, WardLift.low) else Modifier.wardInset(CircleShape)),
            contentAlignment = Alignment.Center) {
            if (done) Icon(Icons.Rounded.Check, null, tint = ink, modifier = Modifier.size(14.dp))
            else Text("${one.number}", style = WardTextStyle.subheadline.textStyle(WardWeight.bold, mono = true), color = ink)
        }
        Text(one.short, style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(if (here) WardToken.ink else WardToken.inkSecondary),
            maxLines = 1)
    }
}

/** One kind of set as a soft tile; the chosen one pressed in, its name in the accent. Tapping it moves on. */
@Composable private fun ModeTile(option: StudySetKind, chosen: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 72.dp).wardRelief(chosen, WardRadius.card, WardLift.mid)
        .clickable(role = Role.Button, onClick = onClick).semantics { selected = chosen }.padding(16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        WardIconSquare(modeIcon(option), tone = WardTone.Blue, size = 44.0, selected = chosen)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(NewSetWords.plainName(option), style = WardType.headline.textStyle(), color = wardColor(if (chosen) WardToken.primaryInk else WardToken.ink))
            Text(NewSetWords.blurb(option), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 2,
                overflow = TextOverflow.Ellipsis)
        }
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
    }
}

/** One way to add material; the chosen one pressed in, its name and tick in the accent. */
@Composable private fun PathTile(option: NewSetPath, chosen: Boolean, onClick: () -> Unit) {
    val icon = when (option) {
        NewSetPath.LECTURE -> Icons.Rounded.Description
        NewSetPath.TYPE -> Icons.Rounded.Keyboard
        NewSetPath.IMPORT_FILE -> Icons.Rounded.Download
    }
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).wardRelief(chosen, WardRadius.card, WardLift.mid)
        .clickable(role = Role.Button, onClick = onClick).semantics { selected = chosen }.padding(16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        WardIconSquare(icon, tone = WardTone.Blue, size = 40.0, selected = chosen)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(option.title, style = WardType.headline.textStyle(), color = wardColor(if (chosen) WardToken.primaryInk else WardToken.ink))
            Text(option.blurb, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
        Icon(if (chosen) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null,
            tint = wardColor(if (chosen) WardToken.primaryInk else WardToken.inkSecondary), modifier = Modifier.size(24.dp))
    }
}

/** The box the material is typed into, with what each line needs folded above it. */
@Composable private fun DraftSection(title: String, kind: StudySetKind, text: String, onText: (String) -> Unit, showFormat: Boolean, toggleFormat: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        WardSectionLabel(title)
        LibraryFormSection {
            Row(Modifier.fillMaxWidth().heightIn(min = WardControlSize.target.wardDp).clickable(role = Role.Button, onClick = toggleFormat),
                verticalAlignment = Alignment.CenterVertically) {
                Text("How to lay it out", style = WardTextStyle.body.textStyle(), color = wardColor(WardToken.ink), modifier = Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.primaryInk),
                    modifier = Modifier.size(18.dp).rotate(if (showFormat) 90f else 0f))
            }
            if (showFormat) Text(NewSetWords.formatHelp(kind), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
            WardTextField(text, onText, Modifier.fillMaxWidth().heightIn(min = 180.dp).semantics { contentDescription = title }, singleLine = false)
        }
    }
}

/**
 * New set's one bottom container (iOS NewSetDock): a soft slab raised high
 * off the base, Back at the leading end and the step's main button at the
 * trailing end, with why that button cannot be tapped yet above them.
 */
@Composable private fun NewSetDock(hint: String?, back: () -> Unit, primary: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 8.dp), contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 600.dp).fillMaxWidth().wardRaised(WardRadius.bar, WardLift.high).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (hint != null) Text(hint, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                WardButtonBox(back, kind = WardButtonKind.secondary, fills = false) {
                    Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, Modifier.size(18.dp)); Text("Back")
                }
                Spacer(Modifier.weight(1f).widthIn(min = 12.dp))
                primary()
            }
        }
    }
}

