package com.stethoscore.app.ui.sources

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DocumentScanner
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.reading.Citation
import com.stethoscore.app.reading.isBlank
import com.stethoscore.app.reading.page
import com.stethoscore.app.reading.sourceKind
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.*
import kotlinx.coroutines.flow.distinctUntilChanged

// Ports of ios/RedPen/Features/Sources/SourceDocumentView.swift and
// SourcePageReader.swift (fed0105): the two ways the reader shows a lecture.
// The whole document is one continuous column of its pages (iOS's
// TextPagesView, what it shows when the device has no file; Android keeps
// none, so there are no PDF pages, Word or PowerPoint conversions or Quick
// Look here). One page shows its text and how many cards came off it.

/** Which page a column scrolled to reports, or null while it stays near the current one. */
internal fun reportedPage(visible: Int, current: Int): Int? = if (kotlin.math.abs(visible - current) > 1) visible else null

/** The extracted text of each page, as cards down one column (TextPagesView). */
@Composable fun TextPagesView(source: SourceDoc, page: Int, onPage: (Int) -> Unit) {
    val state = rememberLazyListState(initialFirstVisibleItemIndex = maxOf(0, source.pages.indexOfFirst { it.number == page }))
    // the last page this column itself reported from scrolling, so a page picked
    // in the list moves the column and the column's own reports do not jerk it back
    var reported by remember { mutableIntStateOf(page) }
    LaunchedEffect(page) {
        if (page != reported) {
            val at = source.pages.indexOfFirst { it.number == page }
            if (at >= 0) state.scrollToItem(at)
            reported = page
        }
    }
    val current by rememberUpdatedState(page)
    LaunchedEffect(state, source) {
        snapshotFlow { state.firstVisibleItemIndex }.distinctUntilChanged().collect { at ->
            val number = source.pages.getOrNull(at)?.number ?: return@collect
            reportedPage(number, current)?.let { reported = it; onPage(it) }
        }
    }
    LazyColumn(Modifier.fillMaxSize(), state = state, contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        items(source.pages, key = { it.number }) { p -> PageCard(source, p) }
    }
}

@Composable private fun PageCard(source: SourceDoc, p: SourcePage) {
    val noun = source.sourceKind.pageNoun
    Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().wardRaised(WardRadius.card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        WardSmallCapsText("$noun ${p.number}")
        if (p.isBlank) {
            BlankLine("No text on this ${noun.lowercase()}")
        } else {
            SelectionContainer { Text(p.text, Modifier.fillMaxWidth(), style = WardType.body.textStyle(), color = wardColor(WardToken.ink)) }
        }
    }
}

@Composable private fun BlankLine(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.Image, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
        Text(text, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
    }
}

/** "3 cards from this slide": how many of the set's items cite this page, or null for none. */
object PageCards {
    fun citing(source: SourceDoc, page: Int, set: StudySet?): List<String> {
        if (set == null) return emptyList()
        val labels = set.cards.mapNotNull { it.source } + set.questions.mapNotNull { it.source }
        return Citation.citing(source, page, labels, set.sources)
    }

    fun line(found: Int, source: SourceDoc): String =
        "$found ${if (found == 1) "card" else "cards"} from this ${source.sourceKind.pageNoun.lowercase()}"
}

/**
 * One page, and what came off it (SourcePageReader): the page's text laid out
 * to be read, a warning when text recognition read it, and under it how many
 * cards cite this page.
 */
@Composable fun SourcePageReader(source: SourceDoc, page: Int, set: StudySet?) {
    val current = source.page(page)
    val mine = remember(source, page, set) { PageCards.citing(source, page, set) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        if (current != null) {
            if (current.isBlank) {
                BlankLine("No text on this ${source.sourceKind.pageNoun.lowercase()}")
            } else {
                if (current.recognised) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.DocumentScanner, null, tint = wardColor(WardToken.warning), modifier = Modifier.size(14.dp))
                    Text("Read by text recognition — worth checking against the original", style = WardTextStyle.caption.textStyle(),
                        color = wardColor(WardToken.warning))
                }
                SelectionContainer { Text(current.text, Modifier.fillMaxWidth(), style = WardType.body.textStyle(), color = wardColor(WardToken.ink)) }
            }
        }
        if (mine.isNotEmpty()) {
            ReaderEtch()
            WardSectionLabel(PageCards.line(mine.size, source))
        }
    }
}
