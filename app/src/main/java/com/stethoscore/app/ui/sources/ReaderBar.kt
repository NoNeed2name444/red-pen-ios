package com.stethoscore.app.ui.sources

import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Article
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.ViewSidebar
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.*

// A port of ios/RedPen/Features/Sources/ReaderBar.swift (fed0105), with the
// FloatingSwitcher it holds: the lecture reader's one bottom container, under
// the thumb. The floating Document / Page switcher, which folds into a small
// disc and opens again with a tap (held, it switches without opening); the
// page list as a soft disc at the leading end (not on a wide screen, where the
// list is beside the reader); and in Page view the pager at the trailing end.
// The arrow keys turn the pages too. With the switcher open it has its own row
// above the other two; folded, all three share one row.

/** The pager's sums: "Page 3 of 12", and the page one turn away, kept inside the document. */
object ReaderPaging {
    fun place(noun: String, page: Int, count: Int): String = "$noun $page of $count"
    fun turn(page: Int, by: Int, count: Int): Int = minOf(maxOf(1, page + by), maxOf(1, count))
    fun atStart(page: Int): Boolean = page <= 1
    fun atEnd(page: Int, count: Int): Boolean = page >= count
    /** Whether the bar's lower row has anything in it. */
    fun hasRow(collapsed: Boolean, showsPages: Boolean, whole: Boolean): Boolean = collapsed || showsPages || !whole
}

private const val collapsedKey = "vignette.reader.switcherCollapsed"

@Composable fun ReaderBar(
    whole: Boolean, onWhole: (Boolean) -> Unit,
    page: Int, onPage: (Int) -> Unit,
    pageCount: Int,
    /** "Page" or "Slide". */
    pageNoun: String,
    showsPages: Boolean,
    openPages: () -> Unit,
) {
    val context = LocalContext.current
    val prefs = remember { runCatching { context.getSharedPreferences("reader", Context.MODE_PRIVATE) }.getOrNull() }
    var collapsed by remember { mutableStateOf(runCatching { prefs?.getBoolean(collapsedKey, false) }.getOrNull() ?: false) }
    fun setCollapsed(now: Boolean) { collapsed = now; runCatching { prefs?.edit()?.putBoolean(collapsedKey, now)?.apply() } }
    val large = wardAccessibilitySize()
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
        Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            val folded = collapsed || large
            if (!folded) FloatingSwitcher(whole, onWhole, false, { setCollapsed(it) })
            if (ReaderPaging.hasRow(folded, showsPages, whole)) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                if (showsPages) ReaderPagesButton(pageNoun, openPages)
                if (folded) FloatingSwitcher(whole, onWhole, true, { setCollapsed(it) })
                Spacer(Modifier.weight(1f))
                if (!whole) ReaderPager(page, onPage, pageCount, pageNoun)
            }
        }
    }
}

private data class SwitcherItem(val whole: Boolean, val title: String, val icon: ImageVector, val identifier: String)

private val modes = listOf(
    SwitcherItem(true, "Document", Icons.Rounded.Description, "readerMode-document"),       // doc.text
    SwitcherItem(false, "Page", Icons.AutoMirrored.Rounded.Article, "readerMode-page"),      // doc.richtext
)

/**
 * The collapsible floating switcher (FloatingSwitcher): a soft strip raised
 * high off the base with the chosen view pressed into it and a chevron to fold
 * it away; folded, one raised disc showing what is chosen, opened with a tap,
 * switched with a hold. At the accessibility text sizes it stays the disc and
 * a tap lists every choice in a sheet.
 */
@Composable private fun FloatingSwitcher(whole: Boolean, onWhole: (Boolean) -> Unit, collapsed: Boolean, setCollapsed: (Boolean) -> Unit) {
    val large = wardAccessibilitySize()
    var listing by remember { mutableStateOf(false) }
    if (collapsed || large) SwitcherBubble(whole, onWhole) { if (large) listing = true else setCollapsed(false) }
    else SwitcherStrip(whole, onWhole) { setCollapsed(true) }
    if (listing) SwitcherListSheet(whole, { onWhole(it); listing = false }) { listing = false }
}

@Composable private fun SwitcherStrip(whole: Boolean, onWhole: (Boolean) -> Unit, collapse: () -> Unit) {
    val tint = wardColor(WardToken.primaryInk)
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Row(Modifier.wardRaised(26.0, WardLift.high, fill = WardToken.raised).padding(5.dp), horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically) {
            modes.forEach { item ->
                val chosen = item.whole == whole
                val shape = RoundedCornerShape(21.dp)
                Column(Modifier.selectable(chosen, role = Role.Tab, interactionSource = remember { MutableInteractionSource() }, indication = null) { onWhole(item.whole) }
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
            IconButton(onClick = collapse, Modifier.size(44.dp).semantics { testTag = "readerSwitcherToggle" }) {
                Icon(Icons.Rounded.KeyboardArrowDown, "Hide the switcher", tint = wardColor(WardToken.ink), modifier = Modifier.size(18.dp))
            }
        }
    }
}

/** The folded state: one disc raised off the base, showing what is chosen; held, it lists the choices. */
@OptIn(ExperimentalFoundationApi::class)
@Composable private fun SwitcherBubble(whole: Boolean, onWhole: (Boolean) -> Unit, expand: () -> Unit) {
    val chosen = modes.first { it.whole == whole }
    var menu by remember { mutableStateOf(false) }
    Box {
        Box(Modifier.size(48.dp).combinedClickable(role = Role.Button, onLongClick = { menu = true }, onClick = expand)
            .semantics { contentDescription = "Show the switcher, now ${chosen.title}"; testTag = "readerSwitcherToggle" }
            .wardRaised(24.0, WardLift.high, fill = WardToken.raised), contentAlignment = Alignment.Center) {
            Icon(chosen.icon, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(22.dp))
            // the small chevron at the top trailing corner, tucked 2 points in
            Box(Modifier.align(Alignment.TopEnd).offset(x = (-2).dp, y = 2.dp).wardRaised(8.0, WardLift.low).padding(3.dp)) {
                Icon(Icons.Rounded.KeyboardArrowUp, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(9.dp))
            }
        }
        DropdownMenu(menu, { menu = false }) {
            modes.forEach { item ->
                DropdownMenuItem(text = { Text(item.title) }, leadingIcon = { Icon(item.icon, null) }, onClick = { menu = false; onWhole(item.whole) })
            }
        }
    }
}

/** Every choice as a list, one to a row: the switcher at the accessibility text sizes. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun SwitcherListSheet(whole: Boolean, choose: (Boolean) -> Unit, onDone: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDone, containerColor = wardColor(WardToken.background)) {
        ReaderNavBar("Show", trailing = { ReaderDoneButton(onClick = onDone) })
        modes.forEach { item ->
            val chosen = item.whole == whole
            Row(Modifier.fillMaxWidth().selectable(chosen, role = Role.Button) { choose(item.whole) }.wardRowTile().heightIn(min = 56.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Icon(item.icon, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(26.dp))
                Text(item.title, Modifier.weight(1f), style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
                if (chosen) Icon(Icons.Rounded.Check, null, tint = wardColor(WardToken.primaryInk))
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

/** Every page, as a list: a 44-point disc on the floating plane, pressed in under the finger. */
@Composable private fun ReaderPagesButton(noun: String, action: () -> Unit) {
    WardTile(action, Modifier.size(44.dp).semantics { contentDescription = "All ${noun.lowercase()}s" }, cornerRadius = 22.0) {
        Icon(Icons.Rounded.ViewSidebar, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(20.dp))
    }
}

/** "‹ Page 3 of 12 ›": a soft capsule on the floating plane. */
@Composable private fun ReaderPager(page: Int, onPage: (Int) -> Unit, count: Int, noun: String) {
    Row(Modifier.wardRaised(22.0, WardLift.high, fill = WardToken.raised).padding(horizontal = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        PagerArrow(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, "Previous ${noun.lowercase()}", !ReaderPaging.atStart(page)) { onPage(ReaderPaging.turn(page, -1, count)) }
        Text(ReaderPaging.place(noun, page, count), Modifier.widthIn(min = 88.dp),
            style = WardTextStyle.footnote.textStyle(WardWeight.semibold, mono = true), color = wardColor(WardToken.ink),
            maxLines = 1, textAlign = TextAlign.Center)
        PagerArrow(Icons.AutoMirrored.Rounded.KeyboardArrowRight, "Next ${noun.lowercase()}", !ReaderPaging.atEnd(page, count)) { onPage(ReaderPaging.turn(page, 1, count)) }
    }
}

@Composable private fun PagerArrow(icon: ImageVector, label: String, enabled: Boolean, action: () -> Unit) {
    IconButton(onClick = action, enabled = enabled, modifier = Modifier.size(44.dp)) {
        Icon(icon, label, tint = if (enabled) wardColor(WardToken.primaryInk) else wardDisabledInk(), modifier = Modifier.size(22.dp))
    }
}
