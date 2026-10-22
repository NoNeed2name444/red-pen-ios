package com.stethoscore.app.ui.ideas

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ideas.GraphLineStyle
import com.stethoscore.app.ideas.IdeaBook
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor

// The canvas tools (IdeaTools.swift, fed0105): the Board's (Back to the middle,
// Connect, Look) and the Space's, a vertical cluster of 44-point circles at the
// bottom-trailing corner, each raised off the base on the floating plane, pressed
// in while held or while the tool is on, its glyph the section's accent then and
// Biro Grey at rest. Also the naming sheet (NameSheet) and "Move to".

/** A vertical cluster of tool circles, 16 apart, each with its own relief. */
@Composable fun IdeaToolCluster(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
}

/** A tool's glyph ink: the accent while on, Biro Grey at rest. */
@Composable fun ideaToolInk(active: Boolean) = wardColor(if (active) WardToken.primaryInk else WardToken.inkSecondary)

/** One round tool: [active] presses it in and turns its glyph the accent. */
@Composable fun IdeaToolButton(icon: ImageVector, label: String, active: Boolean = false, modifier: Modifier = Modifier,
                               value: String? = null, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val held by source.collectIsPressedAsState()
    Box(modifier.minimumInteractiveComponentSize().size(44.dp).capPop(held)
        .wardRelief(pressed = active || held, radius = 22.0, lift = WardLift.high, fill = WardToken.raised, control = false)
        .clickable(source, indication = null, role = Role.Button, onClick = onClick)
        .semantics { contentDescription = label; selected = active; if (value != null) stateDescription = value },
        contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = ideaToolInk(active), modifier = Modifier.size(20.dp))
    }
}

/**
 * "Lines: Curved / Straight" (IdeaLinesPicker): two segments, the same stored choice as the
 * 3D map's Look menu.
 */
@Composable fun IdeaLinesPicker(settings: IdeasSettings, modifier: Modifier = Modifier) {
    WardSegmented(settings.lineStyle, GraphLineStyle.entries, { settings.setStraightLines(it.isStraight) },
        modifier.semantics { contentDescription = "Lines" }) { style, text, ink ->
        Text(style.title, style = text, color = ink, modifier = Modifier.semantics { testTag = "lookLines-" + style.rawValue })
    }
}

/** The board's Look tool: a small popover beside the tools with Lines in it. */
@Composable fun IdeaBoardLookTool(settings: IdeasSettings) {
    var showing by remember { mutableStateOf(false) }
    val straight = settings.lineStyle.isStraight
    Box {
        IdeaToolButton(Icons.Rounded.Palette, "Look", active = straight, value = if (straight) "Straight lines" else "Curved lines") { showing = true }
        DropdownMenu(showing, { showing = false }, containerColor = wardColor(WardToken.background)) {
            IdeaLinesPicker(settings, Modifier.width(200.dp).padding(12.dp))
        }
    }
}

/** A sheet asking for one name (NameSheet): Cancel, the field, and the confirming word. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun NameSheet(title: String, prompt: String, initial: String, confirm: String, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var name by remember { mutableStateOf(initial) }
    val focus = remember { FocusRequester() }
    val blank = name.isBlank()
    fun submit() { if (!blank) { onConfirm(name); onDismiss() } }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = wardColor(WardToken.background)) {
        ReaderNavBar(title,
            leading = { WardTextButton("Cancel", onDismiss, kind = WardButtonKind.quiet, fills = false) },
            trailing = { WardTextButton(confirm, ::submit, kind = WardButtonKind.compact, fills = false, enabled = !blank) })
        Box(Modifier.padding(20.dp)) {
            androidx.compose.foundation.text.BasicTextField(name, { name = it },
                Modifier.fillMaxWidth().focusRequester(focus).semantics { contentDescription = prompt },
                singleLine = true, textStyle = WardType.body.textStyle().copy(color = wardColor(WardToken.ink)),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(wardColor(WardToken.primaryInk)),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { submit() }),
                decorationBox = { inner ->
                    Box(Modifier.fillMaxWidth().wardField(), contentAlignment = Alignment.CenterStart) {
                        if (name.isEmpty()) Text(prompt, style = WardType.body.textStyle(), color = wardDisabledInk())
                        inner()
                    }
                })
        }
        Spacer(Modifier.height(120.dp))
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}

/** "Move to": No folder, then every folder indented by depth (IdeasView.moveChoices). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun MoveSheet(book: IdeaBook, onDismiss: () -> Unit, onMove: (String?) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = wardColor(WardToken.background)) {
        ReaderNavBar("Move to", trailing = { WardTextButton("Cancel", onDismiss, kind = WardButtonKind.quiet, fills = false) })
        val choices: List<Pair<String?, String>> = listOf<Pair<String?, String>>(null to "No folder") +
            book.folderOutline().map { (folder, depth) -> folder.id to IdeaBook.indented(folder.name, depth) }
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 480.dp)) {
            items(choices) { (id, name) ->
                Box(Modifier.fillMaxWidth().clickable(role = Role.Button) { onMove(id); onDismiss() }.wardRowTile()) {
                    Text(name, Modifier.padding(vertical = 6.dp), style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk),
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}
