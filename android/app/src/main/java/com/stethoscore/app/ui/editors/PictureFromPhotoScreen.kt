package com.stethoscore.app.ui.editors

import android.net.Uri
import android.util.Base64
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.DocumentScanner
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AddBox
import androidx.compose.material.icons.rounded.RadioButtonChecked
import androidx.compose.material.icons.rounded.Rectangle
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.PhotoOcclusion
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.ward.StudyActionBar
import com.stethoscore.app.ui.ward.WardBanner
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardChipButton
import com.stethoscore.app.ui.ward.WardIconSquare
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSectionLabel
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextField
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTile
import com.stethoscore.app.ui.ward.WardToggle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Date

// A port of ios/RedPen/Features/Library/PictureFromPhotoView.swift
// (fed0105): Cards > Picture cards > From a photo or scan. Picture cards from
// anything: a photo of a textbook figure, a screenshot of a slide. The student
// moves, stretches, draws or deletes covers, then saves them as a deck.
//
// Photos come through the system photo picker, which needs no permission;
// Files through the system file picker. "Scan pages" is not offered
// (DocumentScanning). The labels are not read on Android yet (PhotoPages), so
// each picture says so and the covers are drawn by hand.

/** The most pictures read at once: each is a few seconds of reading. */
const val PHOTO_PAGE_LIMIT = 10

/** What the last save made, to say so and open it. */
private data class Saved(val set: StudySet, val cards: Int, val lecture: Boolean)

@Composable fun PictureFromPhotoScreen(store: StudyStore, onBack: () -> Unit, onOpen: (StudySet) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var pages by remember { mutableStateOf(listOf<PhotoPage>()) }
    var current by remember { mutableIntStateOf(0) }
    var selected by remember { mutableStateOf<String?>(null) }
    var progress by remember { mutableStateOf<String?>(null) }
    var readJob by remember { mutableStateOf<Job?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    var name by remember { mutableStateOf("") }
    var subject by remember { mutableStateOf("") }
    /** The deck to add to; null makes a new one. */
    var destination by remember { mutableStateOf<String?>(null) }
    var keepAsLecture by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf<Saved?>(null) }
    DisposableEffect(Unit) { onDispose { readJob?.cancel() } }

    /** Each picture read in turn, off the main thread, shown as soon as it is ready; the pages already there stay. */
    fun read(inputs: List<Uri>, scanned: Boolean) {
        readJob?.cancel()
        problem = null
        val room = (PHOTO_PAGE_LIMIT - pages.size).coerceAtLeast(0)
        val taken = inputs.take(room)
        if (taken.isEmpty()) { problem = "Ten pictures at a time. Save these first."; return }
        val total = taken.size
        readJob = scope.launch {
            var failed = 0
            for ((index, input) in taken.withIndex()) {
                if (!isActive) break
                progress = if (total == 1) "Reading the labels…" else "Reading labels, ${index + 1} of $total…"
                val page = withContext(Dispatchers.Default) { PhotoPages.read(context, input, scanned) }
                if (!isActive) break
                if (page == null) { failed += 1; continue }
                pages = pages + page
                if (pages.size == 1) current = 0
            }
            progress = null
            if (scanned && pages.any { it.text.isNotEmpty() }) keepAsLecture = true
            if (failed > 0) {
                problem = "$failed picture${if (failed == 1) " was" else "s were"} not readable."
            } else if (pages.isNotEmpty() && pages.all { it.covers.isEmpty() }) {
                problem = "No labels were found. Drag across the picture to cover each label yourself."
            }
        }
    }
    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(PHOTO_PAGE_LIMIT)) { uris -> if (uris.isNotEmpty()) read(uris, scanned = false) }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> if (uris.isNotEmpty()) read(uris.take(PHOTO_PAGE_LIMIT), scanned = false) }

    fun coversNow(): List<PhotoOcclusion.Cover> = pages.getOrNull(current)?.covers ?: emptyList()
    fun setCovers(value: List<PhotoOcclusion.Cover>) {
        if (current !in pages.indices) return
        pages = pages.mapIndexed { i, p -> if (i == current) p.copy(covers = value) else p }
    }
    val anyScanned = pages.any { it.scanned }
    // the decks that already hold picture cards, to add these to
    val pictureDecks = store.library.filter { set -> set.kind == StudySetKind.ANKI && set.cards.any { it.type == AnkiCardType.OCCLUSION } }
    val cardTotal = pages.sumOf { PhotoOcclusion.answered(it.covers).size }

    fun save() {
        if (saving) return
        saving = true
        try {
            val typed = name.trim()
            val deckName = typed.ifEmpty { PhotoOcclusion.defaultName(Date(), anyScanned) }
            val existing = destination?.let { id -> store.library.firstOrNull { it.id == id } }
            var set = existing ?: StudySet(name = deckName, subject = subject.trim().ifEmpty { "General" }, kind = StudySetKind.ANKI)
            val label = existing?.name ?: deckName
            var made = 0
            pages.forEachIndexed { number, page ->
                val imageIndex = set.images.size
                val source = PhotoOcclusion.source(label, number + 1, pages.size)
                val cards = PhotoOcclusion.cards(page.covers, imageIndex, source = source)
                if (cards.isEmpty()) return@forEachIndexed
                set = set.copy(images = set.images + Base64.encodeToString(page.jpeg, Base64.NO_WRAP), cards = set.cards + cards)
                made += cards.size
            }
            if (made == 0) { problem = "Give at least one cover an answer first."; return }
            var lecture = false
            if (keepAsLecture) {
                val kept = pages.mapIndexed { i, p -> SourcePage(i + 1, p.text, recognised = true) }
                if (kept.any { it.text.isNotBlank() }) {
                    set = set.copy(sources = set.sources + SourceDoc(name = label, kind = "pdf", pages = kept))
                    lecture = true
                }
            }
            if (existing != null) store.updateSet(set) else store.addSet(set)
            val stored = store.library.firstOrNull { it.id == set.id } ?: set
            saved = Saved(stored, made, lecture)
            pages = emptyList()
            selected = null
            problem = null
        } catch (e: IllegalStateException) {
            problem = e.message ?: "Could not save your library."
        } finally { saving = false }
    }

    BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize()) {
        EditorTopBar("From a photo or scan", onCancel = onBack, cancelTitle = "Back")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp).widthIn(max = 760.dp).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            val done = saved
            when {
                done != null -> SavedPanel(done, onOpen = { onOpen(done.set) }) { saved = null; name = ""; keepAsLecture = false; current = 0 }
                pages.isEmpty() -> StartPanel(enabled = progress == null, onPhotos = {
                    photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }, onFiles = { files.launch(arrayOf("image/*")) })
                else -> {
                    val page = pages.getOrNull(current)
                    if (pages.size > 1) Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 6.dp, vertical = 2.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        pages.forEachIndexed { index, p ->
                            val count = PhotoOcclusion.answered(p.covers).size
                            WardChipButton("Page ${index + 1} · $count", { current = index; selected = null },
                                Modifier.semantics { contentDescription = "Page ${index + 1}, $count labels" }, on = index == current)
                        }
                    }
                    if (page != null) {
                        OcclusionCoverEditor(page.preview, page.aspect, page.covers, ::setCovers, selected, { selected = it },
                            Modifier.heightIn(max = 540.dp), tint = wardColor(WardToken.primary))
                        EditorNote("Drag a cover to move it, its corners to stretch it, or across the picture to draw a new one.", style = WardTextStyle.caption)
                        CoverTools(enabled = progress == null, onAdd = {
                            val made = PhotoOcclusion.Cover(box = PhotoOcclusion.added(aspect = page.aspect), answer = "")
                            setCovers(coversNow() + made); selected = made.id
                        }, onPlace = { placement ->
                            selected = null
                            setCovers(PhotoPages.replaced(page, placement))
                        }, onRemoveCovers = { setCovers(emptyList()); selected = null }, onRemovePage = {
                            if (current in pages.indices) {
                                pages = pages.filterIndexed { i, _ -> i != current }
                                current = current.coerceAtMost(pages.size - 1).coerceAtLeast(0)
                                selected = null
                            }
                        })
                        val chosen = coversNow().indexOfFirst { it.id == selected }
                        if (chosen >= 0) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Box(Modifier.weight(1f).semantics { contentDescription = "What this cover hides" }) {
                                WardTextField(coversNow()[chosen].answer, { text ->
                                    val all = coversNow()
                                    if (chosen in all.indices) setCovers(all.mapIndexed { i, c -> if (i == chosen) c.copy(answer = text) else c })
                                }, placeholder = "What this cover hides")
                            }
                            WardButtonBox({ val id = selected; setCovers(coversNow().filterNot { it.id == id }); selected = null },
                                Modifier.semantics { contentDescription = "Delete this cover" }, kind = WardButtonKind.compact) {
                                Icon(Icons.Rounded.Delete, null, tint = wardColor(WardToken.danger))
                            }
                        }
                        LabelList(coversNow(), selected) { selected = it }
                    }
                    DeckPanel(pictureDecks, destination, { destination = it }, name, { name = it }, subject, { subject = it },
                        PhotoOcclusion.defaultName(Date(), anyScanned), showLecture = pages.any { it.text.isNotEmpty() }, keepAsLecture) { keepAsLecture = it }
                }
            }
            progress?.let { words ->
                Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    EcgLoader()
                    Text(words, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
            }
            problem?.let { WardBanner(it, Icons.Rounded.Warning, WardTone.Warning) }
        }
        // the save slab only once there is something to save
        if (saved == null && pages.isNotEmpty()) StudyActionBar {
            WardButtonBox({ save() },
                kind = WardButtonKind.primary, enabled = cardTotal > 0 && !saving && progress == null) {
                Icon(Icons.Rounded.Check, null, Modifier.size(20.dp))
                Text(if (saving) "Saving…" else "Save $cardTotal picture card${if (cardTotal == 1) "" else "s"}")
            }
        }
    }
}

@Composable private fun StartPanel(enabled: Boolean, onPhotos: () -> Unit, onFiles: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("A labelled diagram from a photo, a screenshot or a scanned page. Drag across each label to cover it; move or add covers before saving.",
            style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SourceTile("Photos", "A photo or screenshot", Icons.Rounded.PhotoLibrary, enabled, Modifier.weight(1f), onPhotos)
            if (DocumentScanning.isAvailable) SourceTile("Scan pages", "With the camera", Icons.Rounded.DocumentScanner, enabled, Modifier.weight(1f)) {}
            SourceTile("Files", "A picture saved in Files", Icons.Rounded.Folder, enabled, Modifier.weight(1f), onFiles)
        }
    }
}

/** A soft tile raised off the base, pressed in under the finger (PopTileStyle). */
@Composable private fun SourceTile(title: String, detail: String, icon: ImageVector, enabled: Boolean, modifier: Modifier, action: () -> Unit) {
    WardTile(action, modifier, enabled = enabled, cornerRadius = WardRadius.card) {
        Column(Modifier.fillMaxWidth().defaultMinSize(minHeight = 100.dp).padding(14.dp).semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            WardIconSquare(icon, tone = WardTone.Blue, size = 36.0)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
                Text(detail, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        }
    }
}

@Composable private fun CoverTools(enabled: Boolean, onAdd: () -> Unit, onPlace: (PhotoPages.Placement) -> Unit, onRemoveCovers: () -> Unit, onRemovePage: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        WardButtonBox(onAdd, kind = WardButtonKind.compact) {
            Icon(Icons.Rounded.AddBox, null, Modifier.size(18.dp))
            Text("Add a cover")
        }
        Box(Modifier.weight(1f))
        Box {
            WardButtonBox({ menu = true }, kind = WardButtonKind.compact, enabled = enabled) {
                Icon(Icons.Rounded.MoreHoriz, null, Modifier.size(18.dp))
                Text("More")
            }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text("Labels anywhere on the picture") }, { menu = false; onPlace(PhotoPages.Placement.wholePicture) })
                DropdownMenuItem({ Text("Labels on the diagram only") }, { menu = false; onPlace(PhotoPages.Placement.diagramOnly) })
                HorizontalDivider()
                DropdownMenuItem({ Text("Remove every cover", color = wardColor(WardToken.danger)) }, { menu = false; onRemoveCovers() })
                DropdownMenuItem({ Text("Remove this picture", color = wardColor(WardToken.danger)) }, { menu = false; onRemovePage() })
            }
        }
    }
}

/** Every cover's answer as a row, for a quick read-through and for TalkBack, where dragging boxes is not the way in. */
@Composable private fun LabelList(covers: List<PhotoOcclusion.Cover>, selected: String?, onSelect: (String) -> Unit) {
    if (covers.isEmpty()) return
    var open by remember { mutableStateOf(false) }
    val asked = PhotoOcclusion.answered(covers).size
    val blank = covers.size - asked
    val summary = "$asked card${if (asked == 1) "" else "s"} on this picture${if (blank > 0) ", $blank without an answer" else ""}"
    Column(Modifier.fillMaxWidth().wardRaised().padding(horizontal = 14.dp)) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable(role = Role.Button) { open = !open }, verticalAlignment = Alignment.CenterVertically) {
            Text(summary, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink), modifier = Modifier.weight(1f))
            Icon(if (open) Icons.Rounded.KeyboardArrowDown else Icons.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.primaryInk))
        }
        if (open) Column(Modifier.padding(top = 6.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            covers.forEach { cover ->
                val answer = PhotoOcclusion.tidied(cover.answer)
                val chosen = cover.id == selected
                Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable(role = Role.Button) { onSelect(cover.id) },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(if (chosen) Icons.Rounded.RadioButtonChecked else Icons.Rounded.Rectangle, null,
                        tint = if (chosen) wardColor(WardToken.primaryInk) else wardColor(WardToken.beam), modifier = Modifier.size(18.dp))
                    Text(answer.ifEmpty { "No answer yet" }, style = WardType.body.textStyle(),
                        color = if (answer.isEmpty()) wardColor(WardToken.inkSecondary) else wardColor(WardToken.ink))
                }
            }
        }
    }
}

@Composable private fun DeckPanel(
    decks: List<StudySet>, destination: String?, onDestination: (String?) -> Unit,
    name: String, onName: (String) -> Unit, subject: String, onSubject: (String) -> Unit, defaultName: String,
    showLecture: Boolean, keepAsLecture: Boolean, onKeep: (Boolean) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        WardSectionLabel("Save to")
        if (decks.isNotEmpty()) Box {
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable(role = Role.Button) { menu = true }
                .semantics { contentDescription = "Deck" }, verticalAlignment = Alignment.CenterVertically) {
                Text("Deck", style = WardType.body.textStyle(), color = wardColor(WardToken.ink), modifier = Modifier.weight(1f))
                Text(decks.firstOrNull { it.id == destination }?.name ?: "A new deck", style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk))
                Icon(Icons.Rounded.KeyboardArrowDown, null, tint = wardColor(WardToken.primaryInk))
            }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text("A new deck") }, { menu = false; onDestination(null) })
                decks.forEach { deck -> DropdownMenuItem({ Text(deck.name) }, { menu = false; onDestination(deck.id) }) }
            }
        }
        if (destination == null) {
            Box(Modifier.semantics { contentDescription = "Deck name" }) { WardTextField(name, onName, placeholder = defaultName) }
            Box(Modifier.semantics { contentDescription = "Subject" }) { WardTextField(subject, onSubject, placeholder = "Subject, like Anatomy") }
        }
        if (showLecture) Column {
            WardToggle(keepAsLecture, onKeep, label = "Also keep the pages as a lecture")
            EditorNote("Listed under Sources, with the words read from each page.", style = WardTextStyle.caption)
        }
    }
}

@Composable private fun SavedPanel(result: Saved, onOpen: () -> Unit, onMore: () -> Unit) {
    val lecture = if (result.lecture) " The pages are under Sources too." else ""
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        WardCardFace(Modifier.fillMaxWidth()) {
            Row(horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
                Icon(Icons.Rounded.CheckCircle, null, tint = wardColor(WardToken.success))
                Text("Saved ${result.cards} picture card${if (result.cards == 1) "" else "s"} to “${result.set.name}”.$lecture",
                    style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
            }
        }
        WardButtonBox(onOpen, kind = WardButtonKind.primary) {
            Icon(Icons.Rounded.PlayArrow, null, Modifier.size(20.dp))
            Text("Open the deck")
        }
        WardButtonBox(onMore, kind = WardButtonKind.secondary) {
            Icon(Icons.Rounded.Add, null, Modifier.size(20.dp))
            Text("Make more")
        }
    }
}

/**
 * Picture cards: "From a photo or scan", a soft tile raised above the decks
 * (iOS PhotoCardsTile in CategoryShelves.swift), for the Cards page.
 */
@Composable fun PhotoCardsTile(onClick: () -> Unit, modifier: Modifier = Modifier) {
    WardTile(onClick, modifier.fillMaxWidth(), cornerRadius = WardRadius.card) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 72.dp).padding(14.dp).semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
            WardIconSquare(Icons.Rounded.DocumentScanner, tone = WardTone.Blue, size = 40.0)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("From a photo or scan", style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
                Text("Labels read and covered for you, then adjust", style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            Icon(Icons.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary))
        }
    }
}
