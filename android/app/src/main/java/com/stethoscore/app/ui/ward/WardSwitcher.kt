package com.stethoscore.app.ui.ward

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.sources.ReaderDoneButton
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.wardColor

// The collapsible floating switcher (iOS Shared/Ward FloatingSwitcher, fed0105),
// shared by the lecture reader's bar (Document / Page) and Ideas' bottom
// container (List / Board / Space).

/** One choice on the switcher: its value, word, glyph and test tag (the accessibility identifier). */
data class SwitcherItem<T>(val value: T, val title: String, val icon: ImageVector, val identifier: String)

/**
 * A soft strip raised high off the base with the chosen view pressed into it
 * and a chevron to fold it away; folded, one raised disc showing what is
 * chosen, opened with a tap, switched with a hold. At the accessibility text
 * sizes it stays the disc and a tap lists every choice in a sheet.
 */
@Composable fun <T> FloatingSwitcher(
    items: List<SwitcherItem<T>>,
    selection: T,
    onSelect: (T) -> Unit,
    collapsed: Boolean,
    setCollapsed: (Boolean) -> Unit,
    toggleTag: String,
) {
    val large = wardAccessibilitySize()
    var listing by remember { mutableStateOf(false) }
    if (collapsed || large) SwitcherBubble(items, selection, onSelect, toggleTag) { if (large) listing = true else setCollapsed(false) }
    else SwitcherStrip(items, selection, onSelect, toggleTag) { setCollapsed(true) }
    if (listing) SwitcherListSheet(items, selection, { onSelect(it); listing = false }) { listing = false }
}

@Composable private fun <T> SwitcherStrip(items: List<SwitcherItem<T>>, selection: T, onSelect: (T) -> Unit, toggleTag: String, collapse: () -> Unit) {
    val tint = wardColor(WardToken.primaryInk)
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Row(Modifier.wardRaised(26.0, WardLift.high, fill = WardToken.raised).padding(5.dp), horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically) {
            items.forEach { item ->
                val chosen = item.value == selection
                val shape = RoundedCornerShape(21.dp)
                Column(Modifier.selectable(chosen, role = Role.Tab, interactionSource = remember { MutableInteractionSource() }, indication = null) { onSelect(item.value) }
                    .semantics { testTag = item.identifier }
                    // the well the chosen segment is pressed into, with its 2-point edge in its ink
                    .then(if (chosen) Modifier.wardInset(shape).wardChosenEdge(shape, true, tint) else Modifier)
                    .defaultMinSize(minWidth = 64.dp, minHeight = 48.dp).padding(horizontal = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)) {
                    val ink = if (chosen) tint else wardColor(WardToken.ink)
                    Icon(item.icon, null, tint = ink, modifier = Modifier.size(20.dp))
                    Text(item.title, style = WardTextStyle.caption2.textStyle(WardWeight.bold), color = ink, maxLines = 1)
                }
            }
            IconButton(onClick = collapse, Modifier.semantics { testTag = toggleTag }) {
                Icon(Icons.Rounded.KeyboardArrowDown, "Hide the switcher", tint = wardColor(WardToken.ink), modifier = Modifier.size(18.dp))
            }
        }
    }
}

/** The folded state: one disc raised off the base, showing what is chosen; held, it lists the choices. */
@OptIn(ExperimentalFoundationApi::class)
@Composable private fun <T> SwitcherBubble(items: List<SwitcherItem<T>>, selection: T, onSelect: (T) -> Unit, toggleTag: String, expand: () -> Unit) {
    val chosen = items.firstOrNull { it.value == selection } ?: items.first()
    var menu by remember { mutableStateOf(false) }
    Box {
        Box(Modifier.size(48.dp).combinedClickable(role = Role.Button, onLongClick = { menu = true }, onClick = expand)
            .semantics { contentDescription = "Show the switcher, now ${chosen.title}"; testTag = toggleTag }
            .wardRaised(24.0, WardLift.high, fill = WardToken.raised), contentAlignment = Alignment.Center) {
            Icon(chosen.icon, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(22.dp))
            // the small chevron at the top trailing corner, tucked 2 points in
            Box(Modifier.align(Alignment.TopEnd).offset(x = (-2).dp, y = 2.dp).wardRaised(8.0, WardLift.low).padding(3.dp)) {
                Icon(Icons.Rounded.KeyboardArrowUp, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(9.dp))
            }
        }
        DropdownMenu(menu, { menu = false }) {
            items.forEach { item ->
                DropdownMenuItem(text = { Text(item.title) }, leadingIcon = { Icon(item.icon, null) }, onClick = { menu = false; onSelect(item.value) })
            }
        }
    }
}

/** Every choice as a list, one to a row: the switcher at the accessibility text sizes. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun <T> SwitcherListSheet(items: List<SwitcherItem<T>>, selection: T, choose: (T) -> Unit, onDone: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDone, containerColor = wardColor(WardToken.background)) {
        ReaderNavBar("Show", trailing = { ReaderDoneButton(onClick = onDone) })
        items.forEach { item ->
            val chosen = item.value == selection
            Row(Modifier.fillMaxWidth().selectable(chosen, role = Role.Button) { choose(item.value) }.wardRowTile().heightIn(min = 56.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Icon(item.icon, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(26.dp))
                Text(item.title, Modifier.weight(1f), style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
                if (chosen) Icon(Icons.Rounded.Check, null, tint = wardColor(WardToken.primaryInk))
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}
