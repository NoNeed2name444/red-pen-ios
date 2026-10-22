package com.stethoscore.app.ui.ideas

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.rounded.AddCircleOutline
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Style
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.Note
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.ideas.IdeaBook
import com.stethoscore.app.ideas.NoteCards
import com.stethoscore.app.ideas.NoteEditing
import com.stethoscore.app.ideas.NoteKind
import com.stethoscore.app.ideas.NoteMarkdown
import com.stethoscore.app.ideas.noteKind
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.delay

// A port of NoteEditorView (Features/Notes, fed0105): one note, its title, its kind and
// folder, its text (written, or read laid out as Markdown), what it links to and what links
// to it. Typing `[[` offers the notes it could mean. Changes save half a second after the
// last key and on leaving. Android shows it in place of the list rather than as a sheet, and
// following a link opens that note here, Back returning along the trail.

@Composable fun NoteEditor(model: IdeasModel, settings: IdeasSettings, noteId: String, onClose: () -> Unit) {
    var trail by rememberSaveable { mutableStateOf(listOf<String>()) }
    var currentId by rememberSaveable { mutableStateOf(noteId) }
    val book = model.book
    val note = book.note(currentId)
    if (note == null) { LaunchedEffect(currentId) { if (trail.isEmpty()) onClose() else { currentId = trail.last(); trail = trail.dropLast(1) } }; return }

    key(currentId) {
        NoteEditorPage(model, settings, note, backTitle = trail.lastOrNull()?.let { book.note(it)?.title?.ifEmpty { "Untitled" } },
            go = { id -> if (id != currentId) { trail = trail + currentId; currentId = id } },
            back = { if (trail.isEmpty()) onClose() else { currentId = trail.last(); trail = trail.dropLast(1) } },
            done = onClose)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable private fun NoteEditorPage(
    model: IdeasModel, settings: IdeasSettings, note: Note, backTitle: String?,
    go: (String) -> Unit, back: () -> Unit, done: () -> Unit,
) {
    val id = note.id
    var title by rememberSaveable(id) { mutableStateOf(note.title) }
    var body by rememberSaveable(id) { mutableStateOf(note.body) }
    var menu by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf(false) }
    var cardsMessage by remember { mutableStateOf<String?>(null) }
    val book = model.book
    val reading = settings.reading

    fun save() {
        val now = model.book.note(id) ?: return
        model.book.update(now.copy(title = title, body = body))
    }
    // half a second after the last key, and whenever the page goes
    LaunchedEffect(title, body) { delay(500); save() }
    DisposableEffect(id) { onDispose { save() } }
    fun leave(then: () -> Unit) { save(); then() }
    fun openTitle(name: String) {
        save()
        val found = model.book.resolve("[[$name]]").firstOrNull()
        go(found ?: model.book.create(name, kind = NoteKind.PAGE, folderId = note.folderId).id)
    }
    BackHandler { leave(back) }

    Column(Modifier.fillMaxSize()) {
        ReaderNavBar("",
            leading = {
                if (backTitle != null) {
                    Row(Modifier.clickable(role = Role.Button) { leave(back) }.padding(horizontal = 8.dp, vertical = 12.dp).widthIn(max = 160.dp)
                        .semantics { contentDescription = "Back to $backTitle" },
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(20.dp))
                        Text(backTitle, style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            },
            trailing = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Rounded.MoreHoriz, "More", tint = wardColor(WardToken.primaryInk)) }
                        DropdownMenu(menu, { menu = false }) {
                            DropdownMenuItem({ Text("Delete note", color = wardColor(WardToken.danger)) }, { menu = false; deleting = true },
                                leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = wardColor(WardToken.danger)) })
                        }
                    }
                    WardTextButton("Done", { leave(done) }, kind = WardButtonKind.compact, fills = false)
                }
            })

        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // the title, large, on the page
            BasicTextField(title, { title = it }, Modifier.fillMaxWidth().semantics { contentDescription = "Title" },
                textStyle = WardTextStyle.title2.textStyle(WardWeight.bold).copy(color = wardColor(WardToken.ink)),
                cursorBrush = SolidColor(wardColor(WardToken.primaryInk)),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                decorationBox = { inner ->
                    Box { if (title.isEmpty()) Text("Title", style = WardTextStyle.title2.textStyle(WardWeight.bold), color = wardDisabledInk()); inner() }
                })
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                KindChip(note) { kind -> save(); model.book.note(id)?.let { model.book.update(it.copy(kind = kind.rawValue)) } }
                FolderChip(book, note) { folder -> save(); model.book.move(id, folder) }
            }

            Section("Notes")
            if (reading) MarkdownReader(body, Modifier.fillMaxWidth().wardRowTile(), openTitle = ::openTitle)
            else {
                BasicTextField(body, { body = it }, Modifier.fillMaxWidth().heightIn(min = 200.dp).semantics { contentDescription = "Notes" },
                    textStyle = WardType.body.textStyle().copy(color = wardColor(WardToken.ink)),
                    cursorBrush = SolidColor(wardColor(WardToken.primaryInk)),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    decorationBox = { inner -> Box(Modifier.fillMaxWidth().wardField()) { inner() } })
                val suggestions = NoteEditing.suggestions(body, book.notes, id)
                if (suggestions.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    suggestions.forEach { s ->
                        WardTextButton(s.title, { body = NoteEditing.complete(body, s.title) }, kind = WardButtonKind.compact, fills = false)
                    }
                }
            }
            Text(NoteEditing.NOTES_FOOTER, style = WardType.caption.textStyle(), color = wardColor(WardToken.inkSecondary))

            Section("Linked notes")
            val outgoing = NoteEditing.outgoing(book, id, body)
            val missing = NoteEditing.unresolved(book, body)
            val byHand = book.note(id)?.links?.toSet() ?: emptySet()
            outgoing.forEach { other ->
                book.note(other)?.let { LinkRow(book, it, if (other in byHand) "Linked by hand" else "Named in the text") { save(); go(other) } }
            }
            missing.forEach { name ->
                Row(Modifier.fillMaxWidth().clickable(role = Role.Button) { openTitle(name) }.wardRowTile(),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Rounded.AddCircleOutline, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.width(24.dp))
                    Column(Modifier.weight(1f)) {
                        Text(name, style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                        Text(NoteEditing.MISSING, style = WardType.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                    }
                }
            }
            if (outgoing.isEmpty() && missing.isEmpty()) {
                Row(Modifier.fillMaxWidth().clickable(role = Role.Button) { picking = true }.wardRowTile(),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Rounded.Link, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.width(24.dp))
                    Text("Link to…", style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk))
                }
            }

            val incoming = NoteEditing.backlinks(book, id, body)
            if (incoming.isNotEmpty()) {
                Section("Linked here from")
                incoming.forEach { other ->
                    book.note(other)?.let { from -> LinkRow(book, from, if (id in from.links) "Linked by hand" else "Names this note") { save(); go(other) } }
                }
            }
            Spacer(Modifier.height(24.dp))
        }

        // the bottom bar: Write / Read, Link to…, Turn into cards
        FlowRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).imePadding(),
            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            WardSegmented(reading, listOf(false, true), { save(); settings.setReading(it) }, Modifier.semantics { contentDescription = "Write or read" }) { r, text, ink ->
                Text(if (r) "Read" else "Write", style = text, color = ink)
            }
            WardTile({ save(); picking = true }, Modifier.minimumInteractiveComponentSize().size(44.dp).semantics { contentDescription = "Link to…" }, cornerRadius = 22.0) {
                Icon(Icons.Rounded.Link, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(20.dp))
            }
            WardTile({
                save()
                val now = model.book.note(id) ?: return@WardTile
                val cards = NoteCards.cards(now)
                cardsMessage = if (cards.isEmpty()) NoteEditing.NOTHING_FOR_CARDS else {
                    val name = now.title.trim().ifEmpty { "Untitled" }
                    if (model.addSet(StudySet(name = name, subject = "Ideas", kind = StudySetKind.ANKI, cards = cards))) NoteEditing.cardsMade(name, cards.size) else null
                }
            }, Modifier.minimumInteractiveComponentSize().size(44.dp).semantics { contentDescription = "Turn into cards" }, cornerRadius = 22.0) {
                Icon(Icons.Rounded.Style, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(20.dp))
            }
        }
    }

    if (picking) LinkPicker(book, id) { picking = false }
    if (deleting) AlertDialog(onDismissRequest = { deleting = false }, title = { Text("Delete this note?") },
        text = { Text("Links to it from other notes are removed too.") },
        confirmButton = { TextButton(onClick = { deleting = false; model.book.delete(id); back() }) { Text("Delete", color = wardColor(WardToken.danger)) } },
        dismissButton = { TextButton(onClick = { deleting = false }) { Text("Cancel") } })
    cardsMessage?.let { message ->
        AlertDialog(onDismissRequest = { cardsMessage = null }, title = { Text("Turn into cards") }, text = { Text(message) },
            confirmButton = { TextButton(onClick = { cardsMessage = null }) { Text("OK") } })
    }
}

@Composable private fun Section(text: String) {
    WardSmallCapsText(text, Modifier.padding(top = 8.dp).semantics { heading() })
}

@Composable private fun LinkRow(book: IdeaBook, note: Note, caption: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick).wardRowTile(),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(note.noteKind.icon, null, tint = toneColor(note.folderId, book), modifier = Modifier.width(24.dp))
        Column(Modifier.weight(1f)) {
            Text(note.title.ifEmpty { "Untitled" }, style = WardType.body.textStyle(), color = wardColor(WardToken.ink), maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(caption, style = WardType.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}

/** Page or Idea, as a chip with a menu. */
@Composable private fun KindChip(note: Note, onKind: (NoteKind) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val kind = note.noteKind
    Box {
        Chip(kind.icon, kind.label, "Kind") { open = true }
        DropdownMenu(open, { open = false }) {
            NoteKind.entries.forEach { k ->
                DropdownMenuItem({ Text(k.label) }, { open = false; onKind(k) }, leadingIcon = { Icon(k.icon, null) },
                    trailingIcon = if (k == kind) ({ Icon(Icons.Rounded.Check, "Chosen") }) else null)
            }
        }
    }
}

/** The note's folder: No folder, or every folder indented by depth. */
@Composable private fun FolderChip(book: IdeaBook, note: Note, onFolder: (String?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Chip(Icons.Outlined.Folder, book.folder(note.folderId)?.name ?: "No folder", "Folder") { open = true }
        DropdownMenu(open, { open = false }) {
            DropdownMenuItem({ Text("No folder") }, { open = false; onFolder(null) },
                trailingIcon = if (note.folderId == null) ({ Icon(Icons.Rounded.Check, "Chosen") }) else null)
            book.folderOutline().forEach { (folder, depth) ->
                DropdownMenuItem({ Text(IdeaBook.indented(folder.name, depth)) }, { open = false; onFolder(folder.id) },
                    trailingIcon = if (note.folderId == folder.id) ({ Icon(Icons.Rounded.Check, "Chosen") }) else null)
            }
        }
    }
}

@Composable private fun Chip(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, label: String, onClick: () -> Unit) {
    Row(Modifier.clickable(role = Role.Button, onClick = onClick).wardInset(CircleShape).padding(horizontal = 12.dp, vertical = 7.dp)
        .semantics { contentDescription = "$label: $text" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(16.dp))
        Text(text, style = WardType.chip.textStyle(), color = wardColor(WardToken.primaryInk), maxLines = 1)
    }
}

/** The note laid out (NoteMarkdownView): headings, bullets, quotes, code, rules; `[[links]]` open notes. */
@Composable private fun MarkdownReader(text: String, modifier: Modifier, openTitle: (String) -> Unit) {
    val blocks = NoteMarkdown.blocks(text)
    val ink = wardColor(WardToken.ink)
    val soft = wardColor(WardToken.inkSecondary)
    val link = wardColor(WardToken.primaryInk)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (blocks.isEmpty()) Text(NoteMarkdown.EMPTY, style = WardType.body.textStyle(), color = soft)
        blocks.forEach { block ->
            when (block) {
                is NoteMarkdown.Block.Heading -> Text(inline(block.text, link, openTitle), Modifier.semantics { heading() },
                    style = when (block.level) { 1 -> WardTextStyle.title2; 2 -> WardTextStyle.title3; else -> WardTextStyle.headline }.textStyle(WardWeight.bold), color = ink)
                is NoteMarkdown.Block.Bullet -> Row(Modifier.padding(start = (block.depth * 16).dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(if (block.marker.firstOrNull()?.isDigit() == true) block.marker else "•", style = WardType.body.textStyle(), color = soft)
                    Text(inline(block.text, link, openTitle), style = WardType.body.textStyle(), color = ink)
                }
                is NoteMarkdown.Block.Quote -> Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.width(3.dp).fillMaxHeight().wardInset(CircleShape))
                    Text(inline(block.text, link, openTitle), style = WardType.body.textStyle().copy(fontStyle = FontStyle.Italic), color = soft)
                }
                is NoteMarkdown.Block.Code -> Text(block.text, Modifier.fillMaxWidth().wardField(), style = WardTextStyle.callout.textStyle(mono = true), color = ink)
                NoteMarkdown.Block.Rule -> HorizontalDivider(color = soft.copy(alpha = 0.4f))
                is NoteMarkdown.Block.Paragraph -> Text(inline(block.text, link, openTitle), style = WardType.body.textStyle(), color = ink)
            }
        }
    }
}

private fun inline(line: String, link: androidx.compose.ui.graphics.Color, openTitle: (String) -> Unit): AnnotatedString = buildAnnotatedString {
    for (span in NoteMarkdown.inline(line)) {
        val style = SpanStyle(
            fontWeight = if (span.bold) FontWeight.Bold else null,
            fontStyle = if (span.italic) FontStyle.Italic else null,
            fontFamily = if (span.code) FontFamily.Monospace else null,
            textDecoration = if (span.strike) TextDecoration.LineThrough else null,
        )
        val links = TextLinkStyles(SpanStyle(color = link, textDecoration = TextDecoration.Underline))
        when {
            span.noteLink != null -> withLink(LinkAnnotation.Clickable(span.noteLink, links) { openTitle(span.noteLink) }) { withStyle(style) { append(span.text) } }
            span.url != null -> withLink(LinkAnnotation.Url(span.url, links)) { withStyle(style) { append(span.text) } }
            else -> withStyle(style) { append(span.text) }
        }
    }
}

/** Link to… (NoteLinkPicker): every other note, found by title; a tick joins or parts. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun LinkPicker(book: IdeaBook, id: String, onDone: () -> Unit) {
    var query by remember { mutableStateOf("") }
    val others = book.notes.filter { it.id != id }.sortedByDescending { it.updatedAt }
    val shown = if (query.isBlank()) others else others.filter { it.title.contains(query.trim(), ignoreCase = true) }
    ModalBottomSheet(onDismissRequest = onDone, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = wardColor(WardToken.background)) {
        ReaderNavBar("Link to…", trailing = { WardTextButton("Done", onDone, kind = WardButtonKind.compact, fills = false) })
        BasicTextField(query, { query = it }, Modifier.fillMaxWidth().padding(horizontal = 16.dp).semantics { contentDescription = "Find a note" },
            singleLine = true, textStyle = WardType.body.textStyle().copy(color = wardColor(WardToken.ink)),
            cursorBrush = SolidColor(wardColor(WardToken.primaryInk)),
            decorationBox = { inner ->
                Box(Modifier.fillMaxWidth().wardField()) { if (query.isEmpty()) Text("Find a note", style = WardType.body.textStyle(), color = wardDisabledInk()); inner() }
            })
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp), contentPadding = PaddingValues(8.dp)) {
            if (shown.isEmpty()) item {
                Text(if (others.isEmpty()) "There are no other notes yet." else "Nothing matches.", Modifier.fillMaxWidth().wardRowTile(),
                    style = WardType.body.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            items(shown, key = { it.id }) { other ->
                val linked = book.isLinked(id, other.id)
                Row(Modifier.fillMaxWidth().clickable(role = Role.Checkbox) { if (linked) book.unlink(id, other.id) else book.link(id, other.id) }.wardRowTile()
                    .semantics { contentDescription = other.title.ifEmpty { "Untitled" } + if (linked) ", linked" else "" },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(other.noteKind.icon, null, tint = toneColor(other.folderId, book), modifier = Modifier.width(24.dp))
                    Text(other.title.ifEmpty { "Untitled" }, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink),
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (linked) Icon(Icons.Rounded.Check, null, tint = wardColor(WardToken.primaryInk))
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}
