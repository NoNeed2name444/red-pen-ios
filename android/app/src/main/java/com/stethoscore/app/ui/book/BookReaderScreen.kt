package com.stethoscore.app.ui.book

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.List
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.Psychology
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.*
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.reading.BookPage
import com.stethoscore.app.reading.BookPages
import com.stethoscore.app.ui.sources.*
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.AccuracyAsk
import com.stethoscore.app.ui.AccuracyWhySheet
import com.stethoscore.app.ui.CheckAccuracyMenuItem
import com.stethoscore.app.ui.StudyMoreButton
import com.stethoscore.app.ui.ward.*
import java.text.NumberFormat

// A port of ios/RedPen/Features/Book/BookReaderView.swift (fed0105): the
// textbook reader. The page's title and "Page X of Y" in the header, the page
// as native blocks on a reading card (headings, numbered and plain bullets,
// table rows with the header pressed in, callouts with their mark, flowcharts
// and the set's figures), and at the bottom Back, Contents and Next page, or
// Done on the last page. The place is kept per set (store.readingProgress).
//
// The More menu holds Check accuracy (iOS studyMoreMenu, T0115b2). Not here,
// for want of the feature on Android: Turn into, the page's accuracy badge, Guess first's five
// questions before a first reading, and Draw from memory under a figure.

/** The words iOS's header and bar say, kept apart from the view so they can be checked. */
object BookReaderWords {
    /** "Page 3 of 10", or "One page". */
    fun status(index: Int, count: Int): String = if (count > 1) "Page ${index + 1} of $count" else "One page"

    /** The page's title, or the book's length when there is no page. */
    fun detail(page: BookPage?, wordCount: Int): String =
        page?.title ?: "${NumberFormat.getIntegerInstance().format(wordCount)} words"

    fun fraction(index: Int, count: Int): Double? = if (count > 1) (index + 1).toDouble() / count else null

    fun wordCount(markdown: String): Int = markdown.split(Regex("\\s+")).count { it.isNotEmpty() }

    /** Where to open: the saved place when it is still a page of the book (Store.reading(for:count:)). */
    fun opening(saved: Int?, count: Int): Int = if (saved != null && saved < count) maxOf(0, saved) else 0

    /** A callout's mark, by its kind. */
    fun calloutKind(kind: String): String {
        val k = kind.lowercase()
        return when {
            k.contains("red flag") || k.contains("warning") -> "danger"
            k.contains("exam") -> "exam"
            k.contains("mnemonic") -> "mnemonic"
            else -> "note"
        }
    }
}

@Composable fun BookReaderScreen(set: StudySet, store: StudyStore, onBack: () -> Unit, page: Int = 0) {
    val pages = remember(set.bookMarkdown) { BookPages.split(set.bookMarkdown) }
    val wordCount = remember(set.bookMarkdown) { BookReaderWords.wordCount(set.bookMarkdown) }
    var index by rememberSaveable(set.id) {
        val asked = page.coerceIn(0, maxOf(0, pages.size - 1))
        // the first opening goes back to where the reader left off
        mutableIntStateOf(if (asked == 0) BookReaderWords.opening(store.readingProgress[set.id]?.position, pages.size) else asked)
    }
    var showToc by rememberSaveable(set.id) { mutableStateOf(false) }
    fun go(to: Int) {
        if (to == index) return
        index = to
        store.saveReadingProgress(set.id, to)
    }
    val current = pages.getOrNull(index)
    var verifying by remember(set.id) { mutableStateOf<com.stethoscore.app.accuracy.AccuracyItem?>(null) }
    var turning by remember(set.id) { mutableStateOf<StudySet?>(null) }
    // What Check accuracy looks at: the page on screen (iOS BookReaderView's AccuracyAsk)
    val accuracyAsk = AccuracyAsk("Write a textbook page for medical students from the source.") {
        current?.let { it.title + "\n" + it.markdown }
    }
    verifying?.let { AccuracyWhySheet(it, checksWhenUnchecked = true) { verifying = null } }
    com.stethoscore.app.ui.library.TurnIntoPickerHost(turning, store) { turning = null }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val broad = isBroad(maxWidth)
        Column(Modifier.fillMaxSize().focusRequester(focus).focusable().onPreviewKeyEvent { e ->
            if (e.type != KeyEventType.KeyDown || pages.size <= 1 && e.key != Key.Enter) return@onPreviewKeyEvent false
            when (e.key) {
                Key.DirectionLeft -> { if (index > 0) go(index - 1); true }
                Key.DirectionRight -> { if (index < pages.size - 1) go(index + 1); true }
                Key.Enter, Key.NumPadEnter -> if (index >= pages.size - 1) { onBack(); true } else false
                else -> false
            }
        }) {
            // More: Check accuracy for the page on screen, and Turn into (iOS BookReaderView's studyMoreMenu)
            ReaderNavBar(set.subject.ifEmpty { "Textbook" }, leading = { ReaderBackButton(onBack) },
                trailing = { StudyMoreButton { close ->
                    CheckAccuracyMenuItem(accuracyAsk, set, close) { verifying = it }
                    com.stethoscore.app.ui.library.TurnIntoMenuItem(close) { turning = set }
                } })
            StudyProgressHeader(BookReaderWords.status(index, pages.size), BookReaderWords.detail(current, wordCount),
                BookReaderWords.fraction(index, pages.size))
            // the page, scrolling under the bar; keyed by the page, so a new page starts at its top
            key(index) {
                Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                    .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    SelectionContainer {
                        Column(Modifier.widthIn(max = 700.dp).fillMaxWidth().contentCard(),
                            verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
                            if (current != null) {
                                BookPages.blocks(current.markdown).forEach { block -> BookBlock(block, set) }
                            } else {
                                Text("This textbook is empty.", style = WardType.body.textStyle(), color = wardColor(WardToken.inkSecondary))
                            }
                        }
                    }
                }
            }
            StudyActionBar(folds = true) {
                BookFooter(pages.size, index, broad, onPrevious = { go(maxOf(0, index - 1)) }, onContents = { showToc = true },
                    onNext = { go(minOf(pages.size - 1, index + 1)) }, onDone = onBack)
            }
        }
    }
    if (showToc) ContentsSheet(pages, index, onPick = { go(it); showToc = false }, onClose = { showToc = false })
}

/**
 * Back and Contents on the left, small; Next page at the trailing end - and
 * on the last page, or a book of one page, Done. Back and Contents give way to
 * their symbols where their words have no room, so the main button keeps its
 * words whole; TalkBack still hears "Previous page" and "Contents".
 */
@Composable private fun BookFooter(count: Int, index: Int, broad: Boolean, onPrevious: () -> Unit, onContents: () -> Unit,
                                   onNext: () -> Unit, onDone: () -> Unit) {
    if (count <= 1) { DoneButton(onDone); return }
    val large = wardAccessibilitySize()
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        WardButtonBox(onPrevious, Modifier.semantics { contentDescription = "Previous page" }, kind = WardButtonKind.secondary,
            enabled = index > 0, fills = false) {
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, null, Modifier.size(22.dp))
            if (!large) Text("Back", maxLines = 1)
        }
        WardButtonBox(onContents, Modifier.semantics { contentDescription = "Contents" }, kind = WardButtonKind.secondary, fills = false) {
            Icon(Icons.AutoMirrored.Rounded.List, null, Modifier.size(22.dp))
            // words when there is room, the list symbol alone on a phone
            if (broad && !large) Text("Contents", maxLines = 1)
        }
        if (broad) Spacer(Modifier.weight(1f).widthIn(min = 16.dp))
        Box(if (broad) Modifier else Modifier.weight(1f)) {
            if (index >= count - 1) DoneButton(onDone)
            else WardButtonBox(onNext, kind = WardButtonKind.primary, fills = !broad) {
                Text("Next page", maxLines = 1)
                Icon(Icons.AutoMirrored.Rounded.ArrowForward, null, Modifier.size(20.dp))
            }
        }
    }
}

@Composable private fun DoneButton(onDone: () -> Unit) {
    WardButtonBox(onDone, kind = WardButtonKind.primary) {
        Text("Done", maxLines = 1)
        Icon(Icons.Rounded.Check, null, Modifier.size(20.dp))
    }
}

/** The list of pages, in a sheet: number, title, and a tick where you are. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun ContentsSheet(pages: List<BookPage>, index: Int, onPick: (Int) -> Unit, onClose: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onClose, sheetState = rememberModalBottomSheetState(), containerColor = wardColor(WardToken.background)) {
        ReaderNavBar("Contents", trailing = { WardTextButton("Close", onClose, kind = WardButtonKind.quiet, fills = false) })
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = WardSpace.s.wardDp).padding(bottom = 24.dp)) {
            pages.forEach { p ->
                Row(Modifier.fillMaxWidth().clickable(role = Role.Button) { onPick(p.id) }.wardRowTile().heightIn(min = 44.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("${p.id + 1}.", style = WardTextStyle.body.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
                    Text(p.title, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                    if (p.id == index) Icon(Icons.Rounded.Check, "You are here", tint = wardColor(WardToken.primaryInk))
                }
            }
        }
    }
}

/** A heading's size by its level: # the largest, ### and below a headline. */
internal fun headingStyle(level: Int): TextStyle = when (level) {
    1 -> WardTextStyle.title2.textStyle(WardWeight.bold)
    2 -> WardTextStyle.title3.textStyle(WardWeight.semibold)
    else -> WardType.headline.textStyle()
}

/** A table cell's font: the header row bold, the first column a touch heavier than the rest. */
internal fun cellStyle(header: Boolean, first: Boolean): TextStyle = when {
    header -> WardTextStyle.subheadline.textStyle(WardWeight.bold)
    first -> WardTextStyle.subheadline.textStyle(WardWeight.semibold)
    else -> WardTextStyle.subheadline.textStyle()
}

@Composable private fun calloutIcon(kind: String): ImageVector = when (BookReaderWords.calloutKind(kind)) {
    "danger" -> Icons.Rounded.Warning           // exclamationmark.triangle.fill
    "exam" -> Icons.Rounded.School              // graduationcap.fill
    "mnemonic" -> Icons.Rounded.Psychology      // brain.head.profile
    else -> Icons.Rounded.Lightbulb             // lightbulb.fill
}

@Composable private fun calloutColor(kind: String): Color = wardColor(when (BookReaderWords.calloutKind(kind)) {
    "danger" -> WardToken.danger
    "exam" -> WardToken.primaryInk
    "mnemonic" -> WardToken.ecg
    else -> WardToken.warning
})

@Composable private fun BookBlock(block: BookPages.Block, set: StudySet) {
    val ink = wardColor(WardToken.ink)
    when (block) {
        is BookPages.Block.Heading -> Text(inlineMarkdown(block.text), Modifier.padding(top = WardSpace.s.wardDp),
            style = headingStyle(block.level), color = ink)
        is BookPages.Block.Bullet -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(block.marker ?: "•", style = WardTextStyle.body.textStyle(mono = block.marker != null), color = wardColor(WardToken.inkSecondary))
            Text(inlineMarkdown(block.text), style = WardType.body.textStyle(), color = ink)
        }
        is BookPages.Block.Row -> Row(
            Modifier.fillMaxWidth()
                // the header row pressed into the page, the others flat on it
                .then(if (block.header) Modifier.wardInset(RoundedCornerShape(8.dp)) else Modifier)
                .padding(8.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            block.cells.forEachIndexed { i, cell ->
                Text(inlineMarkdown(cell), Modifier.weight(1f), style = cellStyle(block.header, i == 0), color = ink)
            }
        }
        is BookPages.Block.Paragraph -> Text(inlineMarkdown(block.text),
            style = WardType.body.textStyle().copy(lineHeight = (WardTextStyle.body.line + 3).sp), color = ink)
        is BookPages.Block.Callout -> {
            val tint = calloutColor(block.kind)
            Row(Modifier.fillMaxWidth().wardInset(RoundedCornerShape(12.dp))
                .drawWithContent {
                    drawContent()
                    // the kind's mark down the leading edge
                    val inset = WardSpace.s.wardDp.toPx()
                    drawRect(tint, Offset(0f, inset), Size(3.dp.toPx(), size.height - 2 * inset))
                }
                .padding(12.dp), horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
                Icon(calloutIcon(block.kind), null, tint = tint, modifier = Modifier.size(20.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
                    Text(block.kind, style = WardTextStyle.subheadline.textStyle(WardWeight.bold), color = tint)
                    Text(inlineMarkdown(block.text), style = WardType.body.textStyle(), color = ink)
                }
            }
        }
        is BookPages.Block.Flow -> FlowchartView(block.steps)
        is BookPages.Block.Image -> {
            val stored = set.images.getOrNull(block.index)
            val picture = remember(stored) { stored?.let(::decodePicture) }
            if (picture != null) Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
                Image(picture, block.caption.ifEmpty { "Figure" },
                    Modifier.fillMaxWidth().wardRaised(10.0, WardLift.low).clip(RoundedCornerShape(10.dp)),
                    contentScale = ContentScale.FillWidth)
                if (block.caption.isNotEmpty()) Text(inlineMarkdown(block.caption), style = WardTextStyle.subheadline.textStyle(),
                    color = wardColor(WardToken.inkSecondary))
            }
        }
    }
}

/**
 * A pathway as boxes joined by arrows: one box per step, a branch ("If X →
 * do Y") drawn with its condition above its action.
 */
@Composable internal fun FlowchartView(steps: List<String>) {
    Column(Modifier.fillMaxWidth().padding(vertical = WardSpace.s.wardDp).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        steps.forEachIndexed { i, step ->
            if (i > 0) Icon(Icons.Rounded.ArrowDownward, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
            FlowBox(step)
        }
    }
}

/** A step's condition and action: split at "→" (or "->"). */
internal fun flowPieces(step: String): List<String> {
    val parts = step.split("→").map { it.trim() }
    return if (parts.size > 1) parts else step.split("->").map { it.trim() }
}

@Composable private fun FlowBox(step: String) {
    val pieces = flowPieces(step)
    Column(Modifier.widthIn(max = 420.dp).fillMaxWidth().wardInset(RoundedCornerShape(12.dp))
        .padding(horizontal = WardSpace.l.wardDp, vertical = WardSpace.m.wardDp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
        if (pieces.size > 1) {
            Text(pieces[0], style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.inkSecondary), textAlign = TextAlign.Center)
            Text(pieces.drop(1).joinToString(" → "), style = WardTextStyle.subheadline.textStyle(WardWeight.semibold),
                color = wardColor(WardToken.ink), textAlign = TextAlign.Center)
        } else {
            Text(step, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink), textAlign = TextAlign.Center)
        }
    }
}

/**
 * Inline Markdown as SwiftUI reads it in a textbook (inlineOnlyPreservingWhitespace):
 * **bold**, *italic* or _italic_, and `code`; any other character as typed.
 */
internal fun inlineMarkdown(text: String): AnnotatedString = buildAnnotatedString {
    var i = 0
    fun closing(marker: String, from: Int): Int {
        val end = text.indexOf(marker, from)
        return if (end > from) end else -1
    }
    while (i < text.length) {
        val c = text[i]
        if (text.startsWith("**", i) || text.startsWith("__", i)) {
            val marker = text.substring(i, i + 2)
            val end = closing(marker, i + 2)
            if (end > 0) { withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(inlineMarkdown(text.substring(i + 2, end))) }; i = end + 2; continue }
        } else if (c == '*' || c == '_') {
            val end = closing(c.toString(), i + 1)
            val wordStart = c == '*' || i == 0 || !text[i - 1].isLetterOrDigit()
            if (end > 0 && wordStart && !text[i + 1].isWhitespace()) {
                withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(inlineMarkdown(text.substring(i + 1, end))) }; i = end + 1; continue
            }
        } else if (c == '`') {
            val end = closing("`", i + 1)
            if (end > 0) { withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append(text.substring(i + 1, end)) }; i = end + 1; continue }
        }
        append(c)
        i++
    }
}
