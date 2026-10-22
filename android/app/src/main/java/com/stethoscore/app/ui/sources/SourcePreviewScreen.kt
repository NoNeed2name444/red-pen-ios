package com.stethoscore.app.ui.sources

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DocumentScanner
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.reading.SourceSearch
import com.stethoscore.app.reading.heading
import com.stethoscore.app.reading.isBlank
import com.stethoscore.app.reading.pageCount
import com.stethoscore.app.reading.sourceKind
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.*

// A port of ios/RedPen/Features/Sources/SourcePreviewView.swift (fed0105):
// reading the lecture a set was made from. A list of pages down one side on a
// wide screen, the lecture filling the rest - the whole document, or one page
// with the cards made from it - a search that lists where its matches are, and
// the reader bar under the thumb. Android keeps no lecture files (iOS keeps the
// original on the device it was imported on, SourceFiles), so it reads the
// extracted text, page by page: iOS's view on a device without the file.
//
// Not here: Save to Ideas over a selected passage (Android has no IdeaSaver).

/** A request to open a lecture at a particular page (SourceOpening). */
data class SourceOpening(val source: SourceDoc, val page: Int) {
    val id: String get() = "${source.id}-$page"
}

/** The words the reader says, kept apart so they can be checked. */
object SourceReaderWords {
    fun searchPrompt(source: SourceDoc): String = "Search this ${source.sourceKind.label.lowercase()}"

    /** The page sheet's title: "12 pages". */
    fun pagesTitle(source: SourceDoc): String = "${source.pageCount} ${source.sourceKind.pageNoun.lowercase()}s"

    /** "5 mentions on 3 pages". */
    fun resultsHeading(hits: List<SourceSearch.Hit>, source: SourceDoc): String {
        val found = hits.size
        val mentions = if (found == 1) "mention" else "mentions"
        return "$found $mentions on ${SourceSearch.pagesMatched(hits)} ${source.sourceKind.pageNoun.lowercase()}s"
    }

    /** A page list's line: the page's first line, or what a blank page is. */
    fun firstLine(page: SourcePage, source: SourceDoc): String =
        if (!page.isBlank) page.heading else "No text on this ${source.sourceKind.pageNoun.lowercase()}"
}

/** The reader in a sheet, as iOS presents it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun SourcePreviewSheet(source: SourceDoc, set: StudySet?, openAt: Int, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = wardColor(WardToken.background), dragHandle = null) {
        SourcePreview(source, set, openAt, onDismiss, Modifier.fillMaxSize())
    }
}

/** Reading the lecture a set was made from (SourcePreviewView). */
@Composable fun SourcePreview(source: SourceDoc, set: StudySet?, openAt: Int, onDone: () -> Unit, modifier: Modifier = Modifier) {
    var page by rememberSaveable(source.id) { mutableIntStateOf(openAt) }
    var term by rememberSaveable(source.id) { mutableStateOf("") }
    var showingPages by rememberSaveable(source.id) { mutableStateOf(false) }
    /** The whole document, or one page with the cards made from it. */
    var whole by rememberSaveable(source.id) { mutableStateOf(true) }
    // Android shows no lecture in Quick Look, so picking a page always moves what is shown
    val documentFollowsPage = true
    val hits = remember(term, source) { SourceSearch.hits(term, source.pages) }

    BoxWithConstraints(modifier.fillMaxSize()) {
        val wide = isBroad(maxWidth)
        val pageAware = !whole || documentFollowsPage
        val sidebar = wide && pageAware
        Column(Modifier.fillMaxSize()) {
            ReaderNavBar(source.name, leading = { ReaderDoneButton(onClick = onDone) })
            // search stays at the top, out of the thumb's way
            WardTextField(term, { term = it }, Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp),
                placeholder = SourceReaderWords.searchPrompt(source))
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (term.isNotEmpty()) {
                    SourceResultsList(hits, source) { found -> page = found; term = "" }
                } else {
                    // the page list stays beside the reader in both views
                    Row(Modifier.fillMaxSize()) {
                        if (sidebar) {
                            SourcePageList(source, page, { page = it }, Modifier.width(240.dp).fillMaxHeight())
                            ReaderEtch(vertical = true)
                        }
                        Box(Modifier.weight(1f).fillMaxHeight()) {
                            if (whole) TextPagesView(source, page) { page = it }
                            else SourcePageReader(source, page, set)
                        }
                    }
                }
            }
            // Document / Page, the page list and the pager, under the thumb; out of the way while results show
            if (term.isEmpty()) ReaderBar(whole, { whole = it }, page, { page = it }, source.pageCount,
                source.sourceKind.pageNoun, showsPages = !wide && pageAware, openPages = { showingPages = true })
        }
    }
    if (showingPages) PageSheet(source, page, onPick = { page = it; showingPages = false }) { showingPages = false }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun PageSheet(source: SourceDoc, page: Int, onPick: (Int) -> Unit, onDone: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDone, sheetState = rememberModalBottomSheetState(), containerColor = wardColor(WardToken.background)) {
        ReaderNavBar(SourceReaderWords.pagesTitle(source), trailing = { ReaderDoneButton(onClick = onDone) })
        SourcePageList(source, page, onPick, Modifier.fillMaxWidth().heightIn(max = 560.dp))
    }
}

/**
 * The list of pages: number, first line, and whether the words were
 * recognised rather than read. The open page is pressed into the base.
 */
@Composable fun SourcePageList(source: SourceDoc, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val state = rememberLazyListState()
    LaunchedEffect(selected) {
        val at = source.pages.indexOfFirst { it.number == selected }
        if (at >= 0) state.animateScrollToItem(maxOf(0, at - 2))
    }
    LazyColumn(modifier, state = state, contentPadding = PaddingValues(vertical = 4.dp)) {
        items(source.pages, key = { it.number }) { p ->
            val chosen = p.number == selected
            Row(Modifier.fillMaxWidth().clickable(role = Role.Button) { onSelect(p.number) }.semantics { this.selected = chosen }
                .then(if (chosen) Modifier.wardRowTile(inset = true) else Modifier.padding(WardSpace.s.wardDp).padding(horizontal = 12.dp, vertical = 8.dp)),
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("${p.number}", Modifier.widthIn(min = 22.dp), style = WardTextStyle.caption.textStyle(mono = true),
                    color = if (chosen) wardColor(WardToken.primaryInk) else wardColor(WardToken.inkSecondary),
                    textAlign = androidx.compose.ui.text.style.TextAlign.End)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(SourceReaderWords.firstLine(p, source), style = WardTextStyle.subheadline.textStyle(),
                        color = if (p.isBlank) wardColor(WardToken.inkSecondary) else wardColor(WardToken.ink),
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (p.recognised) Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.DocumentScanner, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(12.dp))
                        Text("Recognised", style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
                    }
                }
            }
        }
    }
}

/** Search results, as somewhere to go rather than a jump: every match with the words around it. */
@Composable fun SourceResultsList(hits: List<SourceSearch.Hit>, source: SourceDoc, open: (Int) -> Unit) {
    if (hits.isEmpty()) {
        WardEmptyState(Icons.Rounded.Search, "Not in this ${source.sourceKind.label.lowercase()}",
            "No ${source.sourceKind.pageNoun.lowercase()} mentions it.")
        return
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)) {
        item { WardSectionLabel(SourceReaderWords.resultsHeading(hits, source), Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) }
        items(hits, key = { it.id }) { hit ->
            Column(Modifier.fillMaxWidth().clickable(role = Role.Button) { open(hit.page) }.wardRowTile(),
                verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("${source.sourceKind.pageNoun} ${hit.page}", style = WardTextStyle.caption.textStyle(WardWeight.semibold),
                    color = wardColor(WardToken.primaryInk))
                Text(marked(hit, wardColor(WardToken.primaryInk)), style = WardTextStyle.subheadline.textStyle(),
                    color = wardColor(WardToken.ink), maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** The snippet with the match emphasised, by the range the search already worked out. */
internal fun marked(hit: SourceSearch.Hit, tint: androidx.compose.ui.graphics.Color): AnnotatedString {
    if (hit.start < 0 || hit.end > hit.snippet.length) return AnnotatedString(hit.snippet)
    return buildAnnotatedString {
        append(hit.snippet.substring(0, hit.start))
        withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = tint)) { append(hit.snippet.substring(hit.start, hit.end)) }
        append(hit.snippet.substring(hit.end))
    }
}
