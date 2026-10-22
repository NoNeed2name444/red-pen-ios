package com.stethoscore.app.ui.ideas

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CenterFocusStrong
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.TouchApp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.Note
import com.stethoscore.app.ideas.BoardPoint
import com.stethoscore.app.ideas.GraphLineStyle
import com.stethoscore.app.ideas.IdeaBoardFit
import com.stethoscore.app.ideas.IdeaBook
import com.stethoscore.app.ideas.IdeaLinkShape
import com.stethoscore.app.ideas.NoteKind
import com.stethoscore.app.ideas.noteKind
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor
import kotlin.math.max

// A port of IdeaBoardView (Features/Notes, fed0105): every note a card on an open board,
// joined by its links. Drag the board to pan, pinch to zoom (0.3 to 2.5). Tap a card to
// open it; hold one, or tap Connect, to start a connection and tap another to join or part
// them. Drag a card to move it, saved where it lands. Double-tap anywhere to put an idea
// there. Board units are points, drawn here as dp.

private const val CARD_WIDTH = 150.0
private const val CARD_HEIGHT = 88.0

@Composable fun IdeaBoard(book: IdeaBook, settings: IdeasSettings, hidden: Dp, open: (String) -> Unit) {
    val density = LocalDensity.current
    var size by remember { mutableStateOf(IntSize.Zero) }
    var zoom by remember { mutableDoubleStateOf(1.0) }
    var panX by remember { mutableDoubleStateOf(0.0) }
    var panY by remember { mutableDoubleStateOf(0.0) }
    var moved by remember { mutableStateOf(false) }
    var connecting by remember { mutableStateOf(false) }
    var source by remember { mutableStateOf<String?>(null) }
    var dragging by remember { mutableStateOf<String?>(null) }
    var dragX by remember { mutableDoubleStateOf(0.0) }
    var dragY by remember { mutableDoubleStateOf(0.0) }
    var adding by remember { mutableStateOf<BoardPoint?>(null) }
    val notes = book.notes
    val edges = remember(notes) { book.allEdges() }
    val style = settings.lineStyle
    val hiddenDp = hidden.value.toDouble()

    val widthDp = size.width / density.density.toDouble()
    val heightDp = size.height / density.density.toDouble()
    val midY = (heightDp - hiddenDp) / 2

    fun position(note: Note): BoardPoint =
        if (note.id == dragging) BoardPoint(note.boardX + dragX, note.boardY + dragY) else BoardPoint(note.boardX, note.boardY)
    fun onScreen(p: BoardPoint) = BoardPoint(widthDp / 2 + panX + p.x * zoom, midY + panY + p.y * zoom)
    fun onBoard(x: Double, y: Double) = BoardPoint((x - widthDp / 2 - panX) / zoom, (y - midY - panY) / zoom)

    fun fitAll() {
        if (size == IntSize.Zero) return
        val camera = IdeaBoardFit.camera(notes.map { BoardPoint(it.boardX, it.boardY) }, IdeaBoardFit.Size(CARD_WIDTH, CARD_HEIGHT),
            IdeaBoardFit.Size(widthDp, heightDp), hiddenDp, IdeaBoardFit.Margins(16.0, 16.0, 16.0, 76.0))
        zoom = camera.zoom; panX = camera.panX; panY = camera.panY
    }
    // the first view frames every card, until the board is moved by hand
    LaunchedEffect(size, notes.size, hidden) { if (!moved) fitAll() }

    fun tapCard(id: String) {
        val from = source
        when {
            from == null && connecting -> source = id
            from == null -> open(id)
            from == id -> { source = null }
            else -> {
                if (book.isLinked(from, id)) book.unlink(from, id) else book.link(from, id)
                source = null
            }
        }
    }

    Box(Modifier.fillMaxSize().onSizeChanged { size = it }) {
        val ink = wardColor(WardToken.inkSecondary)
        val chosenInk = wardColor(WardToken.primaryInk)
        // the board itself: pan, pinch, double-tap
        Canvas(Modifier.fillMaxSize()
            .pointerInput(size, hidden) {
                detectTransformGestures { centroid, pan, gesture, _ ->
                    moved = true
                    val d = density.density.toDouble()
                    val next = (zoom * gesture).coerceIn(0.3, 2.5)
                    val cx = centroid.x / d; val cy = centroid.y / d
                    // keep the point under the fingers where it is
                    val bx = (cx - widthDp / 2 - panX) / zoom; val by = (cy - midY - panY) / zoom
                    zoom = next
                    panX = cx - widthDp / 2 - bx * zoom + pan.x / d
                    panY = cy - midY - by * zoom + pan.y / d
                }
            }
            .pointerInput(size, hidden) {
                detectTapGestures(onDoubleTap = { at ->
                    val d = density.density.toDouble()
                    adding = onBoard(at.x / d, at.y / d)
                }, onTap = { if (source != null && !connecting) source = null })
            }) {
            val d = density.density
            val byId = notes.associateBy { it.id }
            val keys = edges.map { (a, b) -> "$a|$b" }
            val lanes = IdeaLinkShape.lanes(keys)
            edges.forEachIndexed { k, (a, b) ->
                val na = byId[a] ?: return@forEachIndexed
                val nb = byId[b] ?: return@forEachIndexed
                val p = onScreen(position(na)); val q = onScreen(position(nb))
                val (lane, count) = lanes[k]
                val points = IdeaLinkShape.samples(style, p, q, lane, count, if (style == GraphLineStyle.STRAIGHT) 1 else 24)
                val path = Path()
                points.forEachIndexed { i, pt ->
                    val o = Offset((pt.x * d).toFloat(), (pt.y * d).toFloat())
                    if (i == 0) path.moveTo(o.x, o.y) else path.lineTo(o.x, o.y)
                }
                drawPath(path, ink, style = Stroke(width = max(1.0, 1.5 * zoom).toFloat() * d, cap = StrokeCap.Round))
            }
        }

        // the cards, each centred on its spot and scaled with the board
        Layout(content = {
            notes.forEach { note ->
                key(note.id) {
                    BoardCard(book, note, chosen = note.id == source, lifted = note.id == dragging, zoom = zoom, chosenInk = chosenInk,
                        modifier = Modifier.layoutId(note.id)
                            .pointerInput(note.id) {
                                detectTapGestures(onTap = { tapCard(note.id) }, onLongPress = { source = note.id })
                            }
                            .pointerInput(note.id) {
                                detectDragGestures(
                                    onDragStart = { dragging = note.id; dragX = 0.0; dragY = 0.0 },
                                    onDragEnd = {
                                        val id = dragging
                                        if (id != null) book.note(id)?.let { book.setPosition(id, it.boardX + dragX, it.boardY + dragY) }
                                        dragging = null; dragX = 0.0; dragY = 0.0
                                    },
                                    onDragCancel = { dragging = null; dragX = 0.0; dragY = 0.0 },
                                ) { change, amount ->
                                    change.consume()
                                    dragX += amount.x / density.density / zoom
                                    dragY += amount.y / density.density / zoom
                                }
                            }
                            .semantics {
                                role = Role.Button
                                selected = note.id == source
                                onClick(if (connecting || source != null) "Connect" else "Open") { tapCard(note.id); true }
                                onLongClick("Start a connection") { source = note.id; true }
                            })
                }
            }
        }, modifier = Modifier.fillMaxSize()) { measurables, constraints ->
            val loose = constraints.copy(minWidth = 0, minHeight = 0)
            val placeables = measurables.map { it to it.measure(loose) }
            layout(constraints.maxWidth, constraints.maxHeight) {
                placeables.forEach { (m, placeable) ->
                    val note = book.note(m.layoutId as? String) ?: return@forEach
                    val c = onScreen(position(note))
                    placeable.place((c.x * density.density - placeable.width / 2.0).toInt(), (c.y * density.density - placeable.height / 2.0).toInt())
                }
            }
        }

        if (notes.isEmpty()) {
            Column(Modifier.align(Alignment.Center).padding(bottom = hidden).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Rounded.TouchApp, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(40.dp))
                Text("Double-tap anywhere to put an idea there.", style = WardTextStyle.subheadline.textStyle(),
                    color = wardColor(WardToken.inkSecondary), textAlign = TextAlign.Center)
            }
        }

        if (connecting || source != null) {
            Row(Modifier.align(Alignment.TopCenter).padding(top = 12.dp).padding(horizontal = 16.dp)
                .wardRelief(RoundedCornerShape(50), WardLift.high, wardColor(WardToken.raised)).padding(start = 16.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(if (source == null) "Tap a card to start a connection." else "Tap another card to connect them, or to part them.",
                    Modifier.weight(1f, fill = false), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
                WardTextButton("Cancel", { source = null; connecting = false }, kind = WardButtonKind.quiet, fills = false)
            }
        }

        Box(Modifier.align(Alignment.BottomEnd).padding(bottom = hidden)) {
            IdeaToolCluster {
                IdeaBoardLookTool(settings)
                IdeaToolButton(Icons.Rounded.Link, if (connecting) "Stop connecting" else "Connect", active = connecting) {
                    connecting = !connecting; source = null
                }
                IdeaToolButton(Icons.Rounded.CenterFocusStrong, "Back to the middle") { fitAll() }
            }
        }
    }

    adding?.let { spot ->
        NameSheet("New idea", "The idea", "", "Add", { adding = null }) { name -> book.create(name.trim(), kind = NoteKind.IDEA, at = spot) }
    }
}

/** One card: its kind and folder in small type, the title, washed in its folder's colour. */
@Composable private fun BoardCard(book: IdeaBook, note: Note, chosen: Boolean, lifted: Boolean, zoom: Double,
                                  chosenInk: androidx.compose.ui.graphics.Color, modifier: Modifier) {
    val shape = RoundedCornerShape(WardRadius.card.wardDp)
    val tone = toneColor(note.folderId, book)
    val kind = note.noteKind
    val caption = book.folder(note.folderId)?.name ?: kind.label
    val scale = (zoom * if (lifted) 1.04 else 1.0).toFloat()
    Column(modifier.graphicsLayer { scaleX = scale; scaleY = scale }
        .width(CARD_WIDTH.dp)
        .wardRaised(WardRadius.card, if (lifted) WardLift.high else WardLift.low, fill = WardToken.raised)
        .clip(shape).background(tone.copy(alpha = 0.14f))
        .then(if (chosen) Modifier.border(2.dp, chosenInk, shape) else Modifier)
        .padding(10.dp)
        .semantics { contentDescription = "${note.title.ifEmpty { "Untitled" }}, $caption" },
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(kind.icon, null, tint = tone, modifier = Modifier.size(12.dp))
            Text(caption, style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(note.title.ifEmpty { "Untitled" }, style = WardTextStyle.subheadline.textStyle().copy(fontWeight = FontWeight.Medium),
            color = wardColor(WardToken.ink), maxLines = 4, overflow = TextOverflow.Ellipsis)
    }
}

