package com.stethoscore.app.ui.sources

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Article
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.ViewSidebar
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.*

// A port of ios/RedPen/Features/Sources/ReaderBar.swift (fed0105), with the
// FloatingSwitcher it holds (now shared, ui/ward/WardSwitcher.kt): the lecture reader's one bottom container, under
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
            if (!folded) FloatingSwitcher(modes, whole, onWhole, false, { setCollapsed(it) }, "readerSwitcherToggle")
            if (ReaderPaging.hasRow(folded, showsPages, whole)) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                if (showsPages) ReaderPagesButton(pageNoun, openPages)
                if (folded) FloatingSwitcher(modes, whole, onWhole, true, { setCollapsed(it) }, "readerSwitcherToggle")
                Spacer(Modifier.weight(1f))
                if (!whole) ReaderPager(page, onPage, pageCount, pageNoun)
            }
        }
    }
}

private val modes = listOf(
    SwitcherItem(true, "Document", Icons.Rounded.Description, "readerMode-document"),       // doc.text
    SwitcherItem(false, "Page", Icons.AutoMirrored.Rounded.Article, "readerMode-page"),      // doc.richtext
)

/** Every page, as a list: a 44-point disc on the floating plane, pressed in under the finger. */
@Composable private fun ReaderPagesButton(noun: String, action: () -> Unit) {
    WardTile(action, Modifier.minimumInteractiveComponentSize().size(44.dp).semantics { contentDescription = "All ${noun.lowercase()}s" }, cornerRadius = 22.0) {
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
    IconButton(onClick = action, enabled = enabled) {
        Icon(icon, label, tint = if (enabled) wardColor(WardToken.primaryInk) else wardDisabledInk(), modifier = Modifier.size(22.dp))
    }
}
