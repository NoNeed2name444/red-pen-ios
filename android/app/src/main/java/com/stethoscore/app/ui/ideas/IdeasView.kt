package com.stethoscore.app.ui.ideas

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Hub
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.Note
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ideas.IdeaBook
import com.stethoscore.app.ideas.IdeasMode
import com.stethoscore.app.ideas.NoteFolder
import com.stethoscore.app.ideas.NoteKind
import com.stethoscore.app.ideas.noteKind
import com.stethoscore.app.ui.LocalWardDark
import com.stethoscore.app.ui.LocalWardLook
import com.stethoscore.app.ui.sources.ReaderBackButton
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.delay

// A port of IdeasView and IdeasBottomBar (Features/Notes, fed0105): the idea dump,
// one place to throw every thought as it comes, then sort it into folders and join
// it up later. Everything tapped sits at the bottom, under the thumb, in one
// container: the floating List / Board / Space switcher, which folds into a disc,
// and under it the capture field, always there. Return saves the idea and leaves
// the field ready for the next one. Standalone (Android has no Library place for
// it yet): its own title on a plate, Back, and the search field under them.

/** The naming sheet, for a new folder or a renamed one. */
private sealed class FolderPrompt {
    data class New(val parent: String?) : FolderPrompt()
    data class Rename(val folder: NoteFolder) : FolderPrompt()
}

@Composable fun IdeasView(store: StudyStore, onBack: () -> Unit) {
    val context = LocalContext.current
    val model = remember(store) { IdeasModel(store) }
    val settings = remember(context) { IdeasSettings(context) }
    val book = model.book
    var query by rememberSaveable { mutableStateOf("") }
    var draft by rememberSaveable { mutableStateOf("") }
    var folderId by rememberSaveable { mutableStateOf<String?>(null) }
    var opening by rememberSaveable { mutableStateOf<String?>(null) }
    var naming by remember { mutableStateOf<FolderPrompt?>(null) }
    var moving by remember { mutableStateOf<Note?>(null) }
    val capture = remember { FocusRequester() }
    var capturing by remember { mutableStateOf(false) }
    // capturing, held a moment after the caret leaves, so the switcher does not flash open
    var typing by remember { mutableStateOf(false) }
    LaunchedEffect(capturing) { if (capturing) typing = true else { delay(200); typing = false } }
    var barHeight by remember { mutableIntStateOf(0) }
    val density = LocalDensity.current

    // the folder being browsed was deleted: back to the top
    LaunchedEffect(book.folders) { if (folderId != null && book.folder(folderId) == null) folderId = null }

    val openId = opening
    if (openId != null && book.note(openId) != null) {
        NoteEditor(model, settings, openId) { opening = null }
        return
    }

    val mode = settings.mode
    val overMap = mode == IdeasMode.SPACE && query.isBlank()

    fun captureIdea() {
        val text = draft.trim()
        if (text.isEmpty()) return
        book.create(text, kind = NoteKind.IDEA, folderId = if (mode == IdeasMode.LIST) folderId else null)
        draft = ""
        runCatching { capture.requestFocus() }
    }
    fun newPage() {
        val note = book.create("Untitled page", kind = NoteKind.PAGE, folderId = if (mode == IdeasMode.LIST) folderId else null)
        opening = note.id
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            Night(overMap) {
                ReaderNavBar("", leading = { ReaderBackButton(onBack) })
            }
            Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                SearchField(query) { query = it }
            }
            val bottomRoom = with(density) { barHeight.toDp() } + 8.dp
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when {
                    query.isNotBlank() -> SearchResults(book, query, bottomRoom, { opening = it }, { moving = it })
                    mode == IdeasMode.LIST -> ListContent(book, folderId, { folderId = it }, bottomRoom, typing,
                        open = { opening = it }, move = { moving = it }, name = { naming = it }, startTyping = { runCatching { capture.requestFocus() } })
                    mode == IdeasMode.BOARD -> IdeaBoard(book, settings, hidden = bottomRoom, open = { opening = it })
                    else -> IdeasSpace(book, settings, covered = naming != null, hidden = bottomRoom, open = { opening = it },
                        openFolder = { id -> folderId = id; settings.setMode(IdeasMode.LIST) })
                }
            }
        }
        // the title plate over the nav bar's middle
        Night(overMap) {
            Box(Modifier.fillMaxWidth().height(52.dp), contentAlignment = Alignment.Center) {
                Text("Ideas", Modifier.wardInset(CircleShape).padding(horizontal = 18.dp, vertical = 9.dp).semantics { heading() },
                    style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
            }
        }
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().onSizeChanged { barHeight = it.height }) {
            Night(overMap) {
                IdeasBottomBar(settings, draft, { draft = it }, capture, { capturing = it }, typing,
                    capture = ::captureIdea, newPage = ::newPage, newFolder = { naming = FolderPrompt.New(folderId) })
            }
        }
    }

    when (val prompt = naming) {
        is FolderPrompt.New -> NameSheet("New folder", "Folder name", "", "Create", { naming = null }) { book.createFolder(it, prompt.parent) }
        is FolderPrompt.Rename -> NameSheet("Rename folder", "Folder name", prompt.folder.name, "Rename", { naming = null }) { book.renameFolder(prompt.folder.id, it) }
        null -> {}
    }
    moving?.let { note -> MoveSheet(book, { moving = null }) { book.move(note.id, it) } }
    model.error?.let { message ->
        AlertDialog(onDismissRequest = { model.error = null }, title = { Text("Could not save this idea") }, text = { Text(message) },
            confirmButton = { TextButton(onClick = { model.error = null }) { Text("OK") } })
    }
}

/** The map is always night, so the chrome over it is too. */
@Composable fun Night(on: Boolean, content: @Composable () -> Unit) {
    if (!on) { content(); return }
    val look = LocalWardLook.current.copy(dark = true)
    CompositionLocalProvider(LocalWardLook provides look, LocalWardDark provides true, LocalWardGlide provides null, content = content)
}

/** "Search ideas", in a well under the title. */
@Composable private fun SearchField(query: String, onQuery: (String) -> Unit) {
    BasicTextField(query, onQuery, Modifier.fillMaxWidth().semantics { contentDescription = "Search ideas" }, singleLine = true,
        textStyle = WardType.body.textStyle().copy(color = wardColor(WardToken.ink)), cursorBrush = SolidColor(wardColor(WardToken.primaryInk)),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        decorationBox = { inner ->
            Row(Modifier.fillMaxWidth().wardField(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Rounded.Search, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
                Box(Modifier.weight(1f)) {
                    if (query.isEmpty()) Text("Search ideas", style = WardType.body.textStyle(), color = wardDisabledInk())
                    inner()
                }
            }
        })
}

@Composable private fun SearchResults(book: IdeaBook, query: String, bottom: androidx.compose.ui.unit.Dp, open: (String) -> Unit, move: (Note) -> Unit) {
    val found = book.search(query)
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 8.dp, end = 8.dp, top = 8.dp, bottom = bottom)) {
        if (found.isEmpty()) item {
            Text("Nothing matches “$query”.", Modifier.fillMaxWidth().wardRowTile(), style = WardType.body.textStyle(), color = wardColor(WardToken.inkSecondary))
        } else {
            sectionHeader("${found.size} found")
            items(found, key = { it.id }) { note -> NoteRow(book, note, open, move) }
        }
    }
}

private fun LazyListScope.sectionHeader(text: String) = item {
    WardSmallCapsText(text, Modifier.padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 2.dp).semantics { heading() })
}

@Composable private fun ListContent(
    book: IdeaBook, folderId: String?, setFolder: (String?) -> Unit, bottom: androidx.compose.ui.unit.Dp, typing: Boolean,
    open: (String) -> Unit, move: (Note) -> Unit, name: (FolderPrompt) -> Unit, startTyping: () -> Unit,
) {
    val subfolders = book.subfolders(folderId)
    val here = book.contents(folderId)
    val current = book.folder(folderId)
    val heading = current?.name ?: if (subfolders.isEmpty()) "Ideas" else "Loose ideas"
    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 8.dp, end = 8.dp, top = 4.dp, bottom = bottom)) {
            if (current != null) {
                item {
                    Text(book.path(current.id).joinToString(" / ") { it.name }, Modifier.padding(horizontal = 20.dp).padding(top = 12.dp),
                        style = WardType.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
                item {
                    val parentName = book.folder(current.parentId)?.name ?: "All ideas"
                    Row(Modifier.fillMaxWidth().combinedClickable(role = Role.Button) { setFolder(current.parentId) }.wardRowTile(),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, null, tint = wardColor(WardToken.primaryInk))
                        Text(parentName, Modifier.padding(vertical = 4.dp), style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk))
                    }
                }
            }
            if (subfolders.isNotEmpty()) {
                sectionHeader("Folders")
                items(subfolders, key = { "f-" + it.id }) { folder -> FolderRow(book, folder, { setFolder(folder.id) }, name) }
            }
            sectionHeader(heading)
            if (here.isEmpty()) item {
                Text(if (current != null) "Nothing in this folder yet. Ideas dumped while it is open land here."
                    else "Type anything below and press return. Sort it later.",
                    Modifier.fillMaxWidth().wardRowTile(), style = WardType.caption.textStyle().copy(fontSize = WardTextStyle.footnote.textStyle().fontSize),
                    color = wardColor(WardToken.inkSecondary))
            } else items(here, key = { it.id }) { note -> NoteRow(book, note, open, move) }
        }
        if (book.notes.isEmpty() && book.folders.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(bottom = bottom), contentAlignment = Alignment.Center) {
                WardEmptyState(Icons.Outlined.Lightbulb, "Dump your first idea",
                    "Anything worth remembering: a mnemonic, a question to look up, a link between two topics. Join them up later on the board or in the space.") {
                    // gone once typing, when Send is the one main button
                    if (!typing) WardTextButton("Start typing", startTyping, kind = WardButtonKind.primary)
                }
            }
        }
    }
}

/** A folder: its icon in its colour, its name, how many notes are in it, a chevron; held, its menu. */
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable private fun FolderRow(book: IdeaBook, folder: NoteFolder, open: () -> Unit, name: (FolderPrompt) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    SwipeRow(onDelete = { book.deleteFolder(folder.id) }) {
        Box {
            Row(Modifier.fillMaxWidth().combinedClickable(role = Role.Button, onLongClick = { menu = true }, onClick = open).wardRowTile(),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Outlined.Folder, null, tint = toneColor(folder.id, book), modifier = Modifier.width(24.dp))
                Text(folder.name, Modifier.weight(1f).padding(vertical = 4.dp), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                Text("${book.count(folder.id)}", style = WardTextStyle.caption.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
            }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text("Rename") }, { menu = false; name(FolderPrompt.Rename(folder)) }, leadingIcon = { Icon(Icons.Rounded.Edit, null) })
                DropdownMenuItem({ Text("New folder inside") }, { menu = false; name(FolderPrompt.New(folder.id)) }, leadingIcon = { Icon(Icons.Outlined.CreateNewFolder, null) })
                DropdownMenuItem({ Text("Delete folder", color = wardColor(WardToken.danger)) }, { menu = false; book.deleteFolder(folder.id) },
                    leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = wardColor(WardToken.danger)) })
            }
        }
    }
}

/** A note: its kind's icon in its folder's colour, the title, the first line, how many it is linked to. */
@OptIn(ExperimentalFoundationApi::class)
@Composable fun NoteRow(book: IdeaBook, note: Note, open: (String) -> Unit, move: (Note) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val links = book.connections(note.id).size
    val preview = note.body.split("\n").firstOrNull { it.isNotEmpty() } ?: ""
    SwipeRow(onDelete = { book.delete(note.id) }, onMove = { move(note) }) {
        Box {
            Row(Modifier.fillMaxWidth().combinedClickable(role = Role.Button, onLongClick = { menu = true }) { open(note.id) }.wardRowTile(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(note.noteKind.icon, null, tint = toneColor(note.folderId, book), modifier = Modifier.width(24.dp).padding(top = 2.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(note.title.ifEmpty { "Untitled" }, style = WardType.body.textStyle(), color = wardColor(WardToken.ink), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (preview.isNotEmpty()) Text(preview, style = WardType.caption.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (links > 0) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Rounded.Hub, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(11.dp))
                        Text("$links linked", style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
                    }
                }
            }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text("Move to") }, { menu = false; move(note) }, leadingIcon = { Icon(Icons.Outlined.Folder, null) })
                DropdownMenuItem({ Text("Delete", color = wardColor(WardToken.danger)) }, { menu = false; book.delete(note.id) },
                    leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = wardColor(WardToken.danger)) })
            }
        }
    }
}

/** A row's swipes: trailing to Delete, leading to Move… (when there is one). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun SwipeRow(onDelete: () -> Unit, onMove: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        when (value) {
            SwipeToDismissBoxValue.EndToStart -> { onDelete(); true }
            SwipeToDismissBoxValue.StartToEnd -> { onMove?.invoke(); false }
            else -> false
        }
    })
    SwipeToDismissBox(state, enableDismissFromStartToEnd = onMove != null, backgroundContent = {
        val toDelete = state.dismissDirection == SwipeToDismissBoxValue.EndToStart
        Row(Modifier.fillMaxSize().padding(horizontal = 24.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = if (toDelete) Arrangement.End else Arrangement.Start) {
            if (toDelete) Text("Delete", style = WardType.buttonSmall.textStyle(), color = wardColor(WardToken.danger))
            else if (onMove != null) Text("Move…", style = WardType.buttonSmall.textStyle(), color = wardColor(WardToken.primaryInk))
        }
    }) { content() }
}

/**
 * Ideas' one bottom container (IdeasBottomBar): the switcher with its fold, then the capture
 * row - the folded switcher when folded, the "Dump an idea…" field, and Send while there is
 * text or else Add. While typing, the switcher folds into the capture row by itself.
 */
@Composable private fun IdeasBottomBar(
    settings: IdeasSettings, draft: String, onDraft: (String) -> Unit, focus: FocusRequester, onFocus: (Boolean) -> Unit, typing: Boolean,
    capture: () -> Unit, newPage: () -> Unit, newFolder: () -> Unit,
) {
    val focusManager = LocalFocusManager.current
    val showCollapsed = settings.switcherCollapsed || typing
    val hasText = draft.isNotBlank()
    val items = IdeasMode.entries.map { SwitcherItem(it, it.title, it.icon, it.identifier) }
    // folded while typing whatever was stored; opening it while typing puts the keyboard away
    val setCollapsed: (Boolean) -> Unit = { now -> if (!now) focusManager.clearFocus(); settings.setSwitcherCollapsed(now) }
    @Composable fun switcher() = FloatingSwitcher(items, settings.mode, settings::setMode, showCollapsed, setCollapsed, "ideasSwitcherToggle")
    // it floats over the page: no glow round it, only the edges (iOS bottomBar.wardUnlit())
    WardUnlit { Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
        Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp).imePadding(),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (!showCollapsed) switcher()
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                if (showCollapsed) switcher()
                // "Dump an idea…": a soft capsule pressed into the base
                Row(Modifier.weight(1f).heightIn(min = 48.dp).wardInset(CircleShape, control = true).padding(horizontal = 14.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Outlined.Lightbulb, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(20.dp))
                    BasicTextField(draft, onDraft, Modifier.weight(1f).focusRequester(focus).onFocusChanged { onFocus(it.isFocused) }
                        .semantics { testTag = "idea-capture"; contentDescription = "Dump an idea…" },
                        singleLine = true, textStyle = WardType.body.textStyle().copy(color = wardColor(WardToken.ink)),
                        cursorBrush = SolidColor(wardColor(WardToken.primaryInk)),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { capture() }),
                        decorationBox = { inner ->
                            Box(contentAlignment = Alignment.CenterStart) {
                                if (draft.isEmpty()) Text("Dump an idea…", style = WardType.body.textStyle(), color = wardDisabledInk())
                                inner()
                            }
                        })
                }
                if (hasText) {
                    // Send: a disc as high as the switcher, its bold arrow in the accent
                    WardTile(capture, Modifier.size(48.dp).semantics { contentDescription = "Save idea" }, cornerRadius = 24.0) {
                        Icon(Icons.Rounded.ArrowUpward, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(22.dp))
                    }
                } else AddMenu(newIdea = { runCatching { focus.requestFocus() } }, newPage = newPage, newFolder = newFolder)
            }
        }
    } }
}

/** With nothing typed: New idea, New page or New folder, from a disc raised as high as the switcher. */
@Composable private fun AddMenu(newIdea: () -> Unit, newPage: () -> Unit, newFolder: () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        WardTile({ open = true }, Modifier.size(48.dp).semantics { contentDescription = "Add" }, cornerRadius = 24.0) {
            Icon(Icons.Rounded.Add, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(22.dp))
        }
        DropdownMenu(open, { open = false }) {
            DropdownMenuItem({ Text("New idea") }, { open = false; newIdea() }, leadingIcon = { Icon(Icons.Outlined.Lightbulb, null) })
            DropdownMenuItem({ Text("New page") }, { open = false; newPage() }, leadingIcon = { Icon(newPageIcon, null) })
            DropdownMenuItem({ Text("New folder") }, { open = false; newFolder() }, leadingIcon = { Icon(Icons.Outlined.CreateNewFolder, null) })
        }
    }
}
