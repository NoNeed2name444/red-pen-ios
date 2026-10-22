package com.stethoscore.app.ui.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ViewList
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Style
import androidx.compose.material.icons.rounded.TableChart
import androidx.compose.material.icons.rounded.Tag
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.CustomSession
import com.stethoscore.app.data.ImportFact
import com.stethoscore.app.data.ImportPreview
import com.stethoscore.app.data.ImportSource
import com.stethoscore.app.data.LibrarySearch
import com.stethoscore.app.data.QuizFromCards
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardIconSquare
import com.stethoscore.app.ui.ward.WardSegmented
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextField
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToggle
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardField
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.random.Random

// The library's sheets, each a port of its iOS view: NameSheet
// (LibraryChrome.swift), the delete question and the export alert
// (LibrarySheets.swift), FoundCardSheet (LibrarySearchResults.swift),
// CustomSessionSheet and ImportPreviewSheet.

/**
 * A sheet with iOS's inline bar: a quiet Cancel at the leading end, the
 * title in the middle, and the confirming button at the trailing end.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun LibrarySheet(title: String, onDismiss: () -> Unit, leading: String? = "Cancel", trailing: (@Composable () -> Unit)? = null,
                             full: Boolean = false, bottom: (@Composable ColumnScope.() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = full)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = wardColor(WardToken.raised)) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = WardSpace.l.wardDp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                    if (leading != null) WardTextButton(leading, onDismiss, kind = WardButtonKind.quiet, fills = false)
                }
                Text(title, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink), maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.semantics { heading() })
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) { trailing?.invoke() }
            }
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(WardSpace.l.wardDp), content = content)
            if (bottom != null) Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = WardSpace.m.wardDp),
                verticalArrangement = Arrangement.spacedBy(10.dp), content = bottom)
        }
    }
}

/** A name to give: a set, a folder, a combined set (iOS NameSheet). */
@Composable fun NameSheet(title: String, prompt: String, initial: String, confirm: String, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var name by remember { mutableStateOf(initial) }
    val focus = remember { FocusRequester() }
    fun submit() { val trimmed = name.trim(); if (trimmed.isNotEmpty()) { onConfirm(trimmed); onDismiss() } }
    LibrarySheet(title, onDismiss, trailing = {
        WardTextButton(confirm, ::submit, kind = WardButtonKind.compact, enabled = name.trim().isNotEmpty(), fills = false)
    }) {
        WardTextField(name, { name = it }, Modifier.fillMaxWidth().heightIn(min = 44.dp).focusRequester(focus), placeholder = prompt)
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}

/** "Delete 1 set?" or "Delete 3 sets?", asked before every delete (iOS LibrarySheets). */
@Composable fun DeleteSetsDialog(count: Int, onDelete: () -> Unit, onDismiss: () -> Unit) {
    val plural = if (count == 1) "" else "s"
    AlertDialog(onDismissRequest = onDismiss, containerColor = wardColor(WardToken.raised),
        title = { Text("Delete $count set$plural?", color = wardColor(WardToken.ink)) },
        text = { Text("This can’t be undone.", color = wardColor(WardToken.inkSecondary)) },
        confirmButton = { WardTextButton("Delete", { onDismiss(); onDelete() }, kind = WardButtonKind.destructive, fills = false) },
        dismissButton = { WardTextButton("Cancel", onDismiss, kind = WardButtonKind.quiet, fills = false) })
}

/** An alert with one OK (iOS .alert with a message). */
@Composable fun LibraryAlert(title: String, message: String, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, containerColor = wardColor(WardToken.raised),
        title = { Text(title, color = wardColor(WardToken.ink)) },
        text = { Text(message, color = wardColor(WardToken.inkSecondary)) },
        confirmButton = { WardTextButton("OK", onDismiss, kind = WardButtonKind.compact, fills = false) })
}

/** A card found by the search, its answer behind Show answer (iOS FoundCardSheet). */
@Composable fun FoundCardSheet(set: StudySet, card: AnkiCard, onDismiss: () -> Unit, openDeck: (StudySet) -> Unit) {
    var revealed by remember { mutableStateOf(false) }
    val front = if (card.type == AnkiCardType.CLOZE) QuizFromCards.stem(card) else card.displayFront
    val answers = if (card.type == AnkiCardType.CLOZE) listOf(LibrarySearch.clozeBare(card.clozeText)) else card.bullets
    LibrarySheet("Card", onDismiss, leading = null, trailing = {
        WardTextButton("Done", onDismiss, kind = WardButtonKind.compact, fills = false)
    }) {
        WardCardFace(Modifier.fillMaxWidth(), spacing = 12.dp) {
            Text(front, style = WardTextStyle.title3.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
            if (revealed) {
                LibraryEtch()
                answers.forEach { Text(it, style = WardType.body.textStyle(), color = wardColor(WardToken.ink)) }
                if (card.why.isNotEmpty()) Text(card.why, style = WardTextStyle.callout.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        }
        if (!revealed) WardTextButton("Show answer", { revealed = true }, kind = WardButtonKind.secondary)
        WardTextButton("Open “${set.name}”", { onDismiss(); openDeck(set) }, kind = WardButtonKind.primary)
    }
}

/**
 * Build a session (iOS CustomSessionSheet): what to take, what to keep to,
 * and a count kept up to date as the filters change.
 */
@Composable fun CustomSessionSheet(store: StudyStore, text: String, onDismiss: () -> Unit, onStart: (StudySet, CustomSession.Mode) -> Unit) {
    var filter by remember { mutableStateOf(CustomSession.Filter(text = text)) }
    var plan by remember { mutableStateOf(CustomSession.Plan()) }
    var counting by remember { mutableStateOf(false) }
    var starting by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf<String?>(null) }
    var subjectMenu by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val subjects = remember(store.library) { CustomSession.subjects(store.library) }
    LaunchedEffect(filter) {
        counting = true
        delay(150)
        val sets = store.library
        val chosen = filter
        val context = sessionContext(store)
        plan = withContext(Dispatchers.Default) { CustomSession.plan(sets, chosen, context) }
        counting = false
    }
    fun start(mode: CustomSession.Mode) {
        if (plan.isEmpty || starting) return
        starting = true
        val sets = store.library
        val chosen = plan
        val name = CustomSession.title(filter)
        scope.launch {
            val made = withContext(Dispatchers.Default) {
                if (mode == CustomSession.Mode.REVIEW) CustomSession.deck(chosen, sets, name)
                else CustomSession.quiz(chosen, sets, name, Random.nextLong(1, Long.MAX_VALUE).toULong()).set
            }
            starting = false
            val empty = if (mode == CustomSession.Mode.REVIEW) made.cards.isEmpty() else made.questions.isEmpty()
            if (empty) {
                note = "None of these cards has a single answer to ask for, so none could become a question. Review them as cards instead."
                return@launch
            }
            onStart(made, mode)
            onDismiss()
        }
    }
    LibrarySheet("Build a session", onDismiss, full = true, bottom = {
        Text(sessionSummary(filter, plan, counting), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary),
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        val ready = !plan.isEmpty && !starting && filter.narrows
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (plan.cards.isNotEmpty()) WardTextButton("Review cards", { start(CustomSession.Mode.REVIEW) }, Modifier.weight(1f),
                kind = WardButtonKind.secondary, enabled = ready)
            WardTextButton("Start quiz", { start(CustomSession.Mode.QUIZ) }, Modifier.weight(1f), kind = WardButtonKind.primary, enabled = ready)
        }
    }) {
        WardSegmented(filter.include, CustomSession.Include.entries, { filter = filter.copy(include = it) }, Modifier.fillMaxWidth()) { include, style, color ->
            Text(include.title, style = style, color = color)
        }
        LibraryHeading("Only")
        WardCardFace(Modifier.fillMaxWidth()) {
            WardToggle(filter.failedWithinDays != null, { filter = filter.copy(failedWithinDays = if (it) 7 else null) }, label = "Missed this week")
            WardToggle(filter.dueOnly, { filter = filter.copy(dueOnly = it) }, label = "Due now")
            WardToggle(filter.myFlags, { filter = filter.copy(myFlags = it) }, label = "My flagged questions")
            WardToggle(filter.accuracyFlagged, { filter = filter.copy(accuracyFlagged = it) }, label = "Flagged for accuracy")
        }
        Text("Due counts cards; flags count questions. Missed means answered wrong, or a card rated Again.",
            style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
        LibraryHeading("Narrow it")
        WardCardFace(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Subject", style = WardType.body.textStyle(), color = wardColor(WardToken.ink), modifier = Modifier.weight(1f))
                Box {
                    WardTextButton(filter.subject ?: "Any", { subjectMenu = true }, kind = WardButtonKind.quiet, fills = false)
                    DropdownMenu(subjectMenu, { subjectMenu = false }, containerColor = wardColor(WardToken.raised)) {
                        DropdownMenuItem({ Text("Any") }, { filter = filter.copy(subject = null); subjectMenu = false })
                        subjects.forEach { s -> DropdownMenuItem({ Text(s) }, { filter = filter.copy(subject = s); subjectMenu = false }) }
                    }
                }
            }
            WardTextField(filter.tag, { filter = filter.copy(tag = it) }, Modifier.fillMaxWidth(), placeholder = "Tag or topic, e.g. cardio")
            WardTextField(filter.text, { filter = filter.copy(text = it) }, Modifier.fillMaxWidth(), placeholder = "Words in the item")
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
                Text("At most ${filter.limit}", style = WardType.body.textStyle(), color = wardColor(WardToken.ink), modifier = Modifier.weight(1f))
                WardCircleButton(Icons.Rounded.Remove, "Fewer", { filter = filter.copy(limit = (filter.limit - 10).coerceAtLeast(10)) }, enabled = filter.limit > 10)
                WardCircleButton(Icons.Rounded.Add, "More", { filter = filter.copy(limit = (filter.limit + 10).coerceAtMost(200)) }, enabled = filter.limit < 200)
            }
        }
        note?.let { LibraryBanner(it, Icons.Rounded.Warning, WardTone.Warning) }
    }
}

/** What the store knows, copied out for CustomSession.plan (iOS CustomSessionSheet.makeContext). */
fun sessionContext(store: StudyStore, now: Long = System.currentTimeMillis()): CustomSession.Context {
    val context = CustomSession.Context(now = now)
    for (event in store.answerLog) if (!event.correct) {
        val known = context.lastMissed[event.questionId] ?: Long.MIN_VALUE
        if (event.at > known) context.lastMissed[event.questionId] = event.at
    }
    for ((id, record) in store.reviews) context.cards[id] = CustomSession.CardState(record.due, record.lapses, record.ratedAt, record.suspended)
    context.flagged = store.flagged
    return context
}

/** The count over the start buttons (iOS CustomSessionSheet.summary). */
fun sessionSummary(filter: CustomSession.Filter, plan: CustomSession.Plan, counting: Boolean): String {
    if (!filter.narrows) return "Choose at least one filter"
    if (counting && plan.isEmpty) return "Counting…"
    if (plan.isEmpty) return "Nothing matches yet"
    val q = plan.questions.size
    val c = plan.cards.size
    val qs = if (q == 1) "1 question" else "$q questions"
    val cs = if (c == 1) "1 card" else "$c cards"
    if (q == 0) return cs
    if (c == 0) return qs
    return "$qs · $cs"
}

/**
 * What a file holds, before anything is added (iOS ImportPreviewSheet): its
 * figures, its sets, anything left out, and Import.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable fun ImportPreviewSheet(preview: ImportPreview, onDismiss: () -> Unit, onImport: () -> Unit) {
    var importing by remember { mutableStateOf(false) }
    val listed = 12
    val kind = preview.sets.firstOrNull()?.kind ?: StudySetKind.ANKI
    LibrarySheet("Import", { if (!importing) onDismiss() }, full = true) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
            WardIconSquare(sourceIcon(preview.source), size = 48.0)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(preview.title, style = WardTextStyle.title3.textStyle(WardWeight.bold), color = wardColor(WardToken.ink), maxLines = 2,
                    overflow = TextOverflow.Ellipsis)
                Text("Nothing is added until you tap Import.", style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            preview.facts.forEach { FactTile(it) }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            LibraryHeading(if (preview.sets.size == 1) "Your new set" else "Your new sets")
            WardCardFace(Modifier.fillMaxWidth(), padding = 0.dp, spacing = 0.dp) {
                preview.sets.take(listed).forEachIndexed { index, set ->
                    if (index > 0) LibraryEtch(Modifier.padding(start = 14.dp))
                    ImportSetRow(set, preview.folderNames.getOrNull(index))
                }
                if (preview.sets.size > listed) {
                    LibraryEtch(Modifier.padding(start = 14.dp))
                    Text("and ${preview.sets.size - listed} more", style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary),
                        modifier = Modifier.padding(14.dp))
                }
            }
        }
        if (preview.notes.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            preview.notes.forEach { line ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Rounded.Info, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
                    Text(line, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
            }
        }
        val count = preview.itemCount
        val noun = if (kind == StudySetKind.MCQ) (if (count == 1) "question" else "questions") else (if (count == 1) "card" else "cards")
        val number = com.stethoscore.app.data.LibraryImport.number(count)
        WardTextButton(if (importing) "Adding…" else "Import $number $noun", {
            if (!importing) { importing = true; onImport() }
        }, kind = WardButtonKind.primary, enabled = !importing)
    }
}

@Composable private fun FactTile(fact: ImportFact) {
    WardCardFace(Modifier.widthIn(min = 120.dp), padding = 14.dp, spacing = 4.dp) {
        Icon(factIcon(fact.icon), null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(16.dp))
        Text(fact.value, style = WardTextStyle.title3.textStyle(WardWeight.bold, mono = true), color = wardColor(WardToken.ink), maxLines = 1)
        Text(fact.label, style = WardType.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
    }
}

@Composable private fun ImportSetRow(set: StudySet, folder: String?) {
    val count = set.itemCount
    val noun = if (count == 1) set.itemNoun else set.itemNoun + "s"
    Row(Modifier.fillMaxWidth().padding(14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(set.name, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink), maxLines = 2,
                overflow = TextOverflow.Ellipsis)
            if (folder != null) Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Folder, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
                Text(folder, style = WardType.caption.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1)
            }
        }
        Spacer(Modifier.width(8.dp))
        Text("${com.stethoscore.app.data.LibraryImport.number(count)} $noun", style = WardTextStyle.caption.textStyle(WardWeight.semibold, mono = true),
            color = wardColor(WardToken.inkSecondary))
    }
}

fun sourceIcon(source: ImportSource) = when (source) {
    ImportSource.ANKI -> Icons.Rounded.Style
    ImportSource.TABLE -> Icons.Rounded.TableChart
    ImportSource.APP_FILE -> Icons.Rounded.Download
}

private fun factIcon(name: String) = when (name) {
    "questions" -> Icons.AutoMirrored.Rounded.ViewList
    "tag" -> Icons.Rounded.Tag
    else -> Icons.Rounded.Style
}
