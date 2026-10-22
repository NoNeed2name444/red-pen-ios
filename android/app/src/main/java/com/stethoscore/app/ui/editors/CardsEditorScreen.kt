package com.stethoscore.app.ui.editors

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.RemoveCircle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.AnkiCard
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.CardQuality
import com.stethoscore.app.data.CardTags
import com.stethoscore.app.data.MCQEdit
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.ward.StudyActionBar
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.wardColor

// A port of ios/RedPen/Features/Library/CardsEditorView.swift and
// CardEditSheets.swift (fed0105): editing what is in a set, one item at a
// time. A row is deleted by swiping it, by holding it (Delete in its menu) or
// with Edit at the top. Nothing is kept until Save changes, which appears at
// the bottom once there is something to save; Cancel leaves the set as it
// was. Deleting a card forgets its place in the schedule, at Save and only
// for the cards deleted here.

/** CardsEditorView: "Edit cards" for a Cards set, "Edit questions" for a question set. */
@Composable fun CardsEditorScreen(set: StudySet, store: StudyStore, onClose: () -> Unit) {
    var working by remember(set.id) { mutableStateOf(set) }
    var editingCard by remember { mutableStateOf<AnkiCard?>(null) }
    var editingQuestion by remember { mutableStateOf<MCQQuestion?>(null) }
    var changed by remember { mutableStateOf(false) }
    var editMode by remember { mutableStateOf(false) }
    // the library's tags, most used first, worked out once when the editor opens
    val knownTags = remember { CardTags.counts(store.library) }
    val title = if (working.kind == StudySetKind.ANKI) "Edit cards" else "Edit questions"

    fun deleteCard(id: String) { working = working.copy(cards = working.cards.filterNot { it.id == id }); changed = true }
    fun deleteQuestion(id: String) { working = working.copy(questions = working.questions.filterNot { it.id == id }); changed = true }
    // edits are held until Save, so backing out of a sheet changes nothing
    fun save() {
        val kept = working.cards.map { it.id }.toSet()
        store.forgetReviews(set.cards.map { it.id }.filter { it !in kept })
        store.updateSet(working)
        onClose()
    }

    editingCard?.let { card ->
        CardEditSheet(card, knownTags, onCancel = { editingCard = null }) { edited ->
            working = working.copy(cards = working.cards.map { if (it.id == edited.id) edited else it }); changed = true; editingCard = null
        }
        return
    }
    editingQuestion?.let { question ->
        QuestionEditSheet(question, knownTags, onCancel = { editingQuestion = null }) { edited ->
            working = working.copy(questions = working.questions.map { if (it.id == edited.id) edited else it }); changed = true; editingQuestion = null
        }
        return
    }
    BackHandler(onBack = onClose)
    Column(Modifier.fillMaxSize()) {
        EditorTopBar(title, onCancel = onClose) {
            WardTextButton(if (editMode) "Done" else "Edit", { editMode = !editMode }, kind = WardButtonKind.compact, fills = false)
        }
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(WardSpace.gutter.wardDp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
            // the whole set's tags: they cover every card in it
            item("tags") {
                EditorSection("Set tags", rows = false) {
                    TagChipsField(working.tags.ifEmpty { null }, { working = working.copy(tags = it ?: emptyList()); changed = true }, knownTags)
                }
            }
            if (working.kind == StudySetKind.ANKI) items(working.cards, key = { it.id }) { card ->
                EditorRow(editMode, onOpen = { editingCard = card }, onDelete = { deleteCard(card.id) }) { CardRow(card) }
            } else items(working.questions, key = { it.id }) { question ->
                EditorRow(editMode, onOpen = { editingQuestion = question }, onDelete = { deleteQuestion(question.id) }) { QuestionRow(question) }
            }
        }
        // the one main button, once there is something to save
        if (changed) StudyActionBar {
            WardButtonBox({ save() }, kind = WardButtonKind.primary) {
                Icon(Icons.Rounded.Check, null, Modifier.size(20.dp))
                Text("Save changes")
            }
        }
    }
}

/** One row of the list: tapped to edit, swiped or held to delete, with a minus in Edit. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable private fun EditorRow(editMode: Boolean, onOpen: () -> Unit, onDelete: () -> Unit, content: @Composable () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val swipe = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) { onDelete(); true } else false
    })
    SwipeToDismissBox(swipe, enableDismissFromStartToEnd = false, backgroundContent = {
        Row(Modifier.fillMaxSize().padding(horizontal = WardSpace.l.wardDp), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Delete, null, tint = wardColor(WardToken.danger))
        }
    }) {
        Box {
            Row(Modifier.fillMaxWidth().wardRaised(lift = com.stethoscore.app.ui.ward.WardLift.low)
                .combinedClickable(role = Role.Button, onClick = onOpen, onLongClick = { menu = true })
                .padding(horizontal = WardSpace.m.wardDp, vertical = WardSpace.s.wardDp + 2.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
                if (editMode) Icon(Icons.Rounded.RemoveCircle, "Delete", tint = wardColor(WardToken.danger),
                    modifier = Modifier.minimumInteractiveComponentSize().size(44.dp).combinedClickable(role = Role.Button, onClick = onDelete).padding(10.dp))
                Box(Modifier.weight(1f)) { content() }
            }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text("Delete", color = wardColor(WardToken.danger)) }, { menu = false; onDelete() },
                    leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = wardColor(WardToken.danger)) })
            }
        }
    }
}

@Composable private fun CardRow(card: AnkiCard) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.padding(vertical = 2.dp)) {
        Text(if (card.type == AnkiCardType.CLOZE) card.clozeText else card.displayFront, style = WardTextStyle.subheadline.textStyle(),
            color = wardColor(WardToken.ink), maxLines = 2, overflow = TextOverflow.Ellipsis)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(card.type.rawValue, style = WardTextStyle.caption2.textStyle(WardWeight.semibold), color = wardColor(WardToken.primaryInk))
            card.source?.takeIf { it.isNotEmpty() }?.let { Text(it, style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1) }
            TagLine(card.tags)
        }
    }
}

@Composable private fun QuestionRow(question: MCQQuestion) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.padding(vertical = 2.dp)) {
        Text(question.stem, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink), maxLines = 2, overflow = TextOverflow.Ellipsis)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            question.options.getOrNull(question.correctIndex)?.let { answer ->
                Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "Answer: $answer" }, verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Icon(Icons.Rounded.Check, null, tint = wardColor(WardToken.success), modifier = Modifier.size(12.dp))
                    Text(answer, style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.success), maxLines = 1)
                }
            }
            question.source?.takeIf { it.isNotEmpty() }?.let { Text(it, style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1) }
            TagLine(question.tags)
        }
    }
}

/** Swift's `.whitespaces`: spaces and tabs, not line breaks. */
private fun String.trimSpaces() = trim { it == ' ' || it == '\t' }

/**
 * CardEditSheet: editing one card. Only the fields of the card's own type
 * are shown; a cloze with nothing hidden cannot be saved.
 */
@Composable fun CardEditSheet(card: AnkiCard, knownTags: List<CardTags.Count>, onCancel: () -> Unit, onSave: (AnkiCard) -> Unit) {
    var working by remember(card.id) { mutableStateOf(card) }
    var bullets by remember(card.id) { mutableStateOf(card.bullets.joinToString("\n")) }
    // a cloze sentence whose braces were edited away would study as a card with nothing to recall
    val clozeHasNoDeletion = working.type == AnkiCardType.CLOZE && CardQuality.clozeHoles(working.clozeText).isEmpty()
    fun commit() = onSave(working.copy(bullets = bullets.split("\n").map { it.trimSpaces() }.filter { it.isNotEmpty() }))
    BackHandler(onBack = onCancel)
    Column(Modifier.fillMaxSize()) {
        EditorTopBar("Edit card", onCancel = onCancel) {
            WardTextButton("Done", ::commit, kind = WardButtonKind.compact, enabled = !clozeHasNoDeletion, fills = false)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(WardSpace.gutter.wardDp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.l.wardDp)) {
            when (working.type) {
                AnkiCardType.CLOZE -> EditorSection("Sentence",
                    footer = if (clozeHasNoDeletion) "Nothing is hidden yet — wrap the tested words in {{c1::...}}." else "Wrap the tested words in {{c1::...}}.") {
                    EditorTextArea(working.clozeText, { working = working.copy(clozeText = it) }, minHeight = 90.dp, label = "Sentence")
                }
                AnkiCardType.QA -> {
                    EditorSection("Question") { EditorTextArea(working.front, { working = working.copy(front = it) }, minHeight = 70.dp, label = "Question") }
                    EditorSection("Answer", footer = "One bullet per line.") { EditorTextArea(bullets, { bullets = it }, minHeight = 90.dp, label = "Answer") }
                }
                AnkiCardType.OCCLUSION -> {
                    EditorSection("Question") {
                        EditorTextArea(working.front, { working = working.copy(front = it) }, minHeight = 44.dp, placeholder = "What is labelled here?", singleLine = true, label = "Question")
                    }
                    EditorSection("Answer", footer = "The label this card's mask covers. The mask itself is set where the card was made.") {
                        EditorTextArea(bullets, { bullets = it }, minHeight = 60.dp, label = "Answer")
                    }
                }
            }
            EditorSection("Why / how") { EditorTextArea(working.why, { working = working.copy(why = it) }, minHeight = 70.dp, label = "Why / how") }
            EditorSection("Tags", footer = "For finding it again: search for #tag. Tags go with the card to Anki.", rows = false) {
                TagChipsField(working.tags.ifEmpty { null }, { working = working.copy(tags = it ?: emptyList()) }, knownTags)
            }
            working.source?.takeIf { it.isNotEmpty() }?.let { source ->
                EditorSection("From") { EditorNote(source) }
            }
        }
    }
}

/**
 * QuestionEditSheet: editing one question. The correct answer is picked
 * rather than typed, so it cannot point at an option that no longer exists
 * (MCQEdit keeps the key with its option).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable fun QuestionEditSheet(question: MCQQuestion, knownTags: List<CardTags.Count>, onCancel: () -> Unit, onSave: (MCQQuestion) -> Unit) {
    var working by remember(question.id) { mutableStateOf(question) }
    val saved = MCQEdit.tidied(working)
    fun removeOption(index: Int) { if (index in working.options.indices) working = MCQEdit.removing(setOf(index), working) }
    BackHandler(onBack = onCancel)
    Column(Modifier.fillMaxSize()) {
        EditorTopBar("Edit question", onCancel = onCancel) {
            // two options with words, one of them marked correct
            WardTextButton("Done", { saved?.let(onSave) }, kind = WardButtonKind.compact, enabled = saved != null, fills = false)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(WardSpace.gutter.wardDp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.l.wardDp)) {
            EditorSection("Stem") { EditorTextArea(working.stem, { working = working.copy(stem = it) }, minHeight = 90.dp, label = "Stem") }
            EditorSection("Options", footer = if (MCQEdit.hasKey(working)) "Tap the circle beside the right answer."
                else "No answer is marked correct — tap the circle beside the right one.") {
                working.options.indices.forEach { index -> OptionRow(working, index, { working = working.copy(correctIndex = index) }, { removeOption(index) }) { text ->
                    if (index in working.options.indices) working = working.copy(options = working.options.toMutableList().also { it[index] = text })
                } }
                WardButtonBox({ working = working.copy(options = working.options + "") }, kind = WardButtonKind.secondary) {
                    Icon(Icons.Rounded.Add, null, Modifier.size(20.dp))
                    Text("Add an option")
                }
            }
            EditorSection("Explanation") { EditorTextArea(working.explanation, { working = working.copy(explanation = it) }, minHeight = 90.dp, label = "Explanation") }
            EditorSection("Tags", rows = false) {
                TagChipsField(working.tags.ifEmpty { null }, { working = working.copy(tags = it ?: emptyList()) }, knownTags)
            }
            working.source?.takeIf { it.isNotEmpty() }?.let { source -> EditorSection("From") { EditorNote(source) } }
        }
    }
}

/** One option: the circle that marks it correct (held: Mark correct, Delete), its words, and a minus that removes it. */
@OptIn(ExperimentalFoundationApi::class)
@Composable private fun OptionRow(question: MCQQuestion, index: Int, onMark: () -> Unit, onRemove: () -> Unit, onText: (String) -> Unit) {
    val correct = question.correctIndex == index
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box {
            Icon(if (correct) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null,
                tint = if (correct) wardColor(WardToken.success) else wardColor(WardToken.inkSecondary),
                modifier = Modifier.minimumInteractiveComponentSize().size(44.dp).combinedClickable(role = Role.Button, onClick = onMark, onLongClick = { menu = true })
                    .semantics { contentDescription = "Mark correct"; selected = correct }.padding(10.dp))
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text("Mark correct") }, { menu = false; onMark() }, leadingIcon = { Icon(Icons.Rounded.CheckCircle, null) })
                DropdownMenuItem({ Text("Delete", color = wardColor(WardToken.danger)) }, { menu = false; onRemove() },
                    leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = wardColor(WardToken.danger)) })
            }
        }
        // the words read back from the list each time, so a row just deleted reads as empty instead of past the end
        Box(Modifier.weight(1f)) {
            EditorTextArea(question.options.getOrElse(index) { "" }, onText, minHeight = 44.dp, placeholder = "Option", label = "Option ${index + 1}")
        }
        Icon(Icons.Rounded.RemoveCircle, "Delete option", tint = wardColor(WardToken.danger),
            modifier = Modifier.minimumInteractiveComponentSize().size(44.dp).combinedClickable(role = Role.Button, onClick = onRemove).padding(10.dp))
    }
}
