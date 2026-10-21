package com.stethoscore.app.ui.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.CheckCircleOutline
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.GpsFixed
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.TrackChanges
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.WbTwilight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.BedPlan
import com.stethoscore.app.data.ExamWeekPlanner
import com.stethoscore.app.data.RhythmReading
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.WardWords
import com.stethoscore.app.ui.LocalWardLook
import com.stethoscore.app.ui.modeIcon
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.wardRgb
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardIconSquare
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardPartLedger
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardRect
import com.stethoscore.app.ui.ward.WardRelief
import com.stethoscore.app.ui.ward.WardRing
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.capPop
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardAccessibilitySize
import com.stethoscore.app.ui.ward.wardDepth
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardInset
import com.stethoscore.app.ui.ward.wardPressFace
import com.stethoscore.app.ui.ward.wardSmallCapsStyle
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

// A port of upstream/ios/RedPen/Features/Library/WardHome.swift: the
// library's home in the Ward Round language. The page opens with the date,
// the app's name and a greeting, in place of a large title, and the
// countdown to the exam when there is a date. On Questions today's ward
// round follows: a card of beds (BedPlan), each a tap into what it holds,
// and one button that starts the first; then two tiles, Vitals and the
// brain map. The round also stands on Cards while cards are due. The page
// ends at a clean cut above the dock (HomeFit), which moves up past any row
// that would show a sliver over it (WardPartLedger). Nothing here is stored.

/** The squiggle beside the name (HomeHeader.squiggleSize) and its line (LaunchOpening.squiggleLine). */
private const val squiggleWidth = 34.0
private const val squiggleHeight = 18.0
private const val squiggleLine = 2.0

/** Home's small caps: WardSmallCaps one text step smaller (caption2 semibold). */
@Composable private fun homeSmallCapsStyle(): TextStyle =
    wardSmallCapsStyle().copy(fontSize = WardTextStyle.caption2.size.sp, lineHeight = WardTextStyle.caption2.line.sp)

@Composable fun HomeSmallCaps(text: String, modifier: Modifier = Modifier, color: Color = wardColor(WardToken.inkSecondary)) {
    Text(text.uppercase(Locale.getDefault()), modifier, style = homeSmallCapsStyle(), color = color)
}

// MARK: - The header

/**
 * The top of a category's page, in place of a large title: the date in
 * small caps, the app's name with a squiggle of ECG beside it, a greeting,
 * and the countdown to the exam when there is a date.
 */
@Composable fun HomeHeader(countdown: String?, modifier: Modifier = Modifier, name: String? = null) {
    val today = LocalDate.now()
    val greeting = WardWords.greeting(LocalTime.now().hour, name)
    Column(modifier.fillMaxWidth().padding(top = WardSpace.xs.wardDp), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
        // the weekday, the day and the month, in the reader's own order (iOS .dateTime.weekday(.wide).day().month(.wide))
        val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "EEEEdMMMM")
        HomeSmallCaps(today.format(DateTimeFormatter.ofPattern(pattern, Locale.getDefault())))
        Row(Modifier.semantics(mergeDescendants = true) { heading() }, verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            Text(HomeBrand.name, style = WardType.display.textStyle(), color = wardColor(WardToken.ink), maxLines = 1)
            EcgSquiggle(Modifier.size(squiggleWidth.wardDp, squiggleHeight.wardDp).clearAndSetSemantics {})
        }
        Text(greeting, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
        if (countdown != null) HomePill(countdown, Icons.Rounded.CalendarMonth, Modifier.padding(top = WardSpace.xs.wardDp))
    }
}

/** The app's name, as the header sets it in words (no logo picture on Android). */
object HomeBrand { const val name = "Stethoscore" }

/** The squiggle of ECG beside the name (EcgSquiggle), in ECG Red. */
@Composable fun EcgSquiggle(modifier: Modifier = Modifier) {
    val ink = wardColor(WardToken.ecg)
    Canvas(modifier) {
        val points = listOf(0.0 to 0.0, 0.30 to 0.0, 0.36 to -0.12, 0.42 to 0.0, 0.48 to 0.10, 0.54 to -0.50,
            0.60 to 0.30, 0.66 to 0.0, 0.78 to -0.14, 0.88 to 0.0, 1.0 to 0.0)
        val mid = size.height / 2
        val path = Path()
        points.forEachIndexed { i, (x, y) ->
            val px = (x * size.width).toFloat()
            val py = mid + (y * size.height).toFloat()
            if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }
        drawPath(path, ink, style = Stroke(squiggleLine.wardDp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** Home's countdown pill (WardPill one text step smaller: footnote bold). */
@Composable private fun HomePill(text: String, icon: ImageVector?, modifier: Modifier = Modifier) {
    Row(
        modifier.wardInset(CircleShape)
            .padding(horizontal = WardSpace.m.wardDp, vertical = WardSpace.s.wardDp)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) Icon(icon, null, tint = wardColor(WardToken.beam), modifier = Modifier.size(13.dp))
        Text(text, style = WardTextStyle.footnote.textStyle(WardWeight.bold), color = wardColor(WardToken.warning))
    }
}

/** Home's chip (WardChip one text step smaller: caption2 semibold). */
@Composable private fun HomeChip(text: String, tone: WardTone, modifier: Modifier = Modifier) {
    Row(
        modifier.wardInset(CircleShape)
            .padding(horizontal = WardSpace.s.wardDp, vertical = WardSpace.xs.wardDp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, style = WardTextStyle.caption2.textStyle(WardWeight.semibold), color = tone.ink())
    }
}

// MARK: - The parts that can meet the cut

/**
 * Home's book of parts (iOS WardPartBook): each row and part reports where
 * it lies, and at rest its top is booked, so the page's cut moves up past
 * any that would show a sliver over it (HomeFit.settledCut).
 */
class HomePartBook {
    val ledger = WardPartLedger<String>()
    /** The booked tops last published, in root dp: the page's cut reads them. */
    var tops by mutableStateOf(emptyList<Double>())
        private set
    /** At rest: the list at its top and not moving. */
    var atRest = true
        private set

    fun set(key: String, name: String, rect: WardRect, reach: Double, scale: Double) {
        if (ledger.set(key, name, rect, reach, scale, atRest)) tops = ledger.told
    }

    fun drop(key: String) {
        if (ledger.drop(key, atRest)) tops = ledger.told
    }

    /** A new page (another category, a search): the book empties; the cut is kept. */
    fun clear() {
        if (ledger.clear()) tops = ledger.told
    }

    /** The list started or stopped moving; once at rest, every live sighting is booked afresh. */
    fun settle(rest: Boolean) {
        atRest = rest
        if (rest && ledger.rebook()) tops = ledger.told
    }
}

/** Reports this part to home's book (wardPart): its name, and how far its face stands out above its frame. */
fun Modifier.homePart(book: HomePartBook?, key: String, name: String, reach: Double = 0.0): Modifier =
    if (book == null) this else composed {
        val density = LocalDensity.current.density
        DisposableEffect(book, key) { onDispose { book.drop(key) } }
        onGloballyPositioned { c ->
            val b = c.boundsInRoot()
            book.set(key, name, WardRect((b.left / density).toDouble(), (b.top / density).toDouble(),
                (b.width / density).toDouble(), (b.height / density).toDouble()), reach, density.toDouble())
        }
    }

/**
 * Home's page, cut `HomeFit.cutRoom` above the bar under it (the dock):
 * the list inside is as tall as `HomeFit.shown`, so nothing shows past the
 * cut, and no row shows a sliver over it. [atRest]: the list at its top and
 * not moving.
 */
@Composable fun HomeCutPage(book: HomePartBook, atRest: Boolean, modifier: Modifier = Modifier,
                            content: @Composable (Modifier) -> Unit) {
    val density = LocalDensity.current.density
    var page by remember { mutableStateOf<Pair<Double, Double>?>(null) }
    LaunchedEffect(atRest) { book.settle(atRest) }
    Box(modifier.onGloballyPositioned { c ->
        val b = c.boundsInRoot()
        val next = (b.top / density).toDouble() to (b.height / density).toDouble()
        if (next != page) page = next
    }) {
        val p = page
        val tops = book.tops
        val shown = p?.let { (top, height) -> HomeFit.shown(top + height, top, height, tops, density.toDouble()) }
        SideEffect { book.ledger.cut = p?.let { (top, height) -> HomeFit.cut(top + height, top, tops)?.plus(top) } }
        content(if (shown == null) Modifier.fillMaxSize() else Modifier.fillMaxWidth().height(shown.wardDp))
    }
}

/** Whether this window is short (HomeFit.isShort): a phone under 770 points tall. */
@Composable fun homeShortWindow(): Boolean {
    val config = LocalConfiguration.current
    return HomeFit.isShort(config.screenHeightDp.toDouble(), broad = config.smallestScreenWidthDp >= 600)
}

// MARK: - Today's ward round

/** What home's round and tiles show, read once per change of the library. */
data class HomeRoundModel(
    val beds: List<BedPlan.Bed>,
    /** The exam-week line, while new material is held back. */
    val note: String?,
    val streak: Int,
    val rhythm: RhythmReading.Reading,
    val ideas: Int,
    val links: Int,
    /** The readiness estimate the Vitals tile's ring shows (StoreInsight.readiness), null until there is one. */
    val readiness: com.stethoscore.app.data.ReadinessEstimate? = null,
)

/**
 * Today's ward round, and on Questions the two tiles under it (iOS
 * homeRoundSections), as rows of home's list.
 */
fun LazyListScope.homeRoundItems(model: HomeRoundModel, tiles: Boolean, book: HomePartBook?,
                                 onOpen: (BedPlan.Bed) -> Unit, onVitals: () -> Unit, onIdeas: () -> Unit,
                                 onPlan: () -> Unit = {}) {
    item(key = "home-round") { HomeRoundCard(model.beds, model.note, onOpen, book, onPlan = onPlan) }
    if (tiles) item(key = "home-tiles") {
        HomeTiles(model.streak, model.rhythm, model.ideas, model.links, onVitals, onIdeas, book, model.readiness)
    }
}

/**
 * The round's card: its heading with how many patients and how long, a row
 * per bed, and the button that starts bed 1.
 */
@Composable fun HomeRoundCard(beds: List<BedPlan.Bed>, note: String?, onOpen: (BedPlan.Bed) -> Unit,
                              book: HomePartBook? = null, modifier: Modifier = Modifier, onPlan: () -> Unit = {}) {
    WardCardFace(modifier.fillMaxWidth().homePart(book, "card", "the round card"), lift = WardLift.low,
        spacing = WardSpace.m.wardDp) {
        val spoken = BedPlan.spokenSummary(beds)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            HomeSmallCaps("Today’s ward round · " + BedPlan.summary(beds),
                Modifier.weight(1f).semantics { heading(); contentDescription = spoken })
            HomePlanButton(onPlan)
        }
        if (beds.isEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.CheckCircleOutline, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
                Text("All done for now — nothing is waiting.", style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        } else {
            Column {
                beds.forEachIndexed { i, bed ->
                    HomeBedRow(bed, { onOpen(bed) }, book)
                    if (i < beds.lastIndex) HomeEtch(Modifier.padding(start = 52.dp))
                }
            }
            if (note != null) Row(horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.NightsStay, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp))
                Text(note, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            WardButtonBox({ onOpen(beds.first()) }, Modifier.homePart(book, "start", "Start ward round"), kind = WardButtonKind.primary) {
                Icon(Icons.Rounded.Bolt, null, Modifier.size(18.dp))
                Text("Start ward round", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold))
            }
        }
    }
}

/**
 * The round's way into the exam plan (HomeRoundCard.planButton): a 44-point
 * target that takes only the words' height in the heading's row.
 */
@Composable private fun HomePlanButton(onPlan: () -> Unit) {
    Row(Modifier.layout { measurable, constraints ->
            // the words' height in the row, the target 12 above and below it
            val placeable = measurable.measure(constraints)
            val trim = 24.dp.roundToPx()
            layout(placeable.width, maxOf(0, placeable.height - trim)) { placeable.place(0, -trim / 2) }
        }.clickable(role = Role.Button, onClickLabel = "Opens the exam plan and forecast", onClick = onPlan)
        .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(Icons.AutoMirrored.Rounded.TrendingUp, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(16.dp))
        Text("Plan", style = WardTextStyle.footnote.textStyle(WardWeight.semibold), color = wardColor(WardToken.primaryInk))
    }
}

/** A bed's glyph (HomeRoundCard.symbol): the mission's, or its mode's. */
fun homeBedIcon(bed: BedPlan.Bed): ImageVector = when (val kind = bed.kind) {
    is BedPlan.Kind.Priority -> missionIcon(kind.mission)
    is BedPlan.Kind.DueCards -> modeIcon(StudySetKind.ANKI)
    is BedPlan.Kind.Weakest -> Icons.Rounded.TrackChanges
    is BedPlan.Kind.Fresh -> modeIcon(when (kind.set.mode) {
        BedPlan.Mode.questions -> StudySetKind.MCQ
        BedPlan.Mode.cards -> StudySetKind.ANKI
        BedPlan.Mode.textbook -> StudySetKind.BOOK
    })
    is BedPlan.Kind.OsceStation -> modeIcon(StudySetKind.OSCE)
}

/** ExamWeekPlanner.Mission.symbol, as the nearest Material Symbols. */
fun missionIcon(mission: ExamWeekPlanner.Mission): ImageVector = when (mission) {
    ExamWeekPlanner.Mission.ExamKit -> Icons.Rounded.Checklist
    is ExamWeekPlanner.Mission.MorningCheck -> Icons.Rounded.WbTwilight
    is ExamWeekPlanner.Mission.DueCards -> Icons.Rounded.PlayArrow
    ExamWeekPlanner.Mission.Mock -> Icons.Rounded.Timer
    is ExamWeekPlanner.Mission.ConfidentErrors -> Icons.Rounded.Warning
    is ExamWeekPlanner.Mission.Mistakes -> Icons.AutoMirrored.Rounded.Undo
    is ExamWeekPlanner.Mission.LockIn -> Icons.Rounded.Lock
    is ExamWeekPlanner.Mission.Flagged -> Icons.Rounded.Flag
    is ExamWeekPlanner.Mission.Weakest -> Icons.Rounded.GpsFixed
    ExamWeekPlanner.Mission.NewQuestions -> Icons.Rounded.AutoAwesome
    ExamWeekPlanner.Mission.Nothing -> Icons.Rounded.CheckCircle
}

/**
 * The chip's words and tone (HomeRoundCard.chip): Caution Amber, Resus Red,
 * and the section's accent, which is what New takes.
 */
fun homeBedChip(bed: BedPlan.Bed): Pair<String, WardTone>? {
    val status = bed.status ?: return null
    val tone = when (status) {
        BedPlan.Status.due, BedPlan.Status.timed, BedPlan.Status.today -> WardTone.Warning
        BedPlan.Status.new -> WardTone.Blue
        BedPlan.Status.weak -> WardTone.Danger
    }
    return status.rawValue to tone
}

/**
 * Home's bed row (WardRow one text step smaller): the glyph in a soft
 * square, the bed's small-caps line, title and detail, its chip and a
 * chevron; stacked at the accessibility sizes. Pressed, it dims a little
 * and sinks (pressableRow).
 */
@Composable private fun HomeBedRow(bed: BedPlan.Bed, onClick: () -> Unit, book: HomePartBook?) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val chip = homeBedChip(bed)
    val stacked = wardAccessibilitySize()
    val words: @Composable () -> Unit = {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            HomeSmallCaps(bed.overline)
            Text(bed.title, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
            Text(bed.detail, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
    val chipView: @Composable () -> Unit = {
        if (chip != null) HomeChip(chip.first, chip.second, Modifier.homePart(book, "chip-${bed.id}", "bed ${bed.number}'s ${chip.first} chip"))
    }
    val chevron: @Composable () -> Unit = {
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
    }
    Box(Modifier.fillMaxWidth()
        .homePart(book, "bed-${bed.id}", "bed ${bed.number}")
        .capPop(pressed)
        // brightness -0.04 while held: a veil of black at that strength
        .drawWithContent { drawContent(); if (pressed) drawRect(Color.Black.copy(alpha = 0.04f)) }
        .clickable(source, indication = null, role = Role.Button, onClickLabel = "Opens this bed", onClick = onClick)
        .clearAndSetSemantics { contentDescription = bed.spoken }
        .padding(vertical = WardSpace.s.wardDp)) {
        if (stacked) Column(verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                WardIconSquare(homeBedIcon(bed))
                Spacer(Modifier.weight(1f))
                chevron()
            }
            words()
            chipView()
        } else Row(horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp), verticalAlignment = Alignment.CenterVertically) {
            WardIconSquare(homeBedIcon(bed))
            Box(Modifier.weight(1f)) { words() }
            chipView()
            chevron()
        }
    }
}

/**
 * A line etched into the card between rows (WardEtch): the relief's shade
 * over its highlight, one point each, at the low lift.
 */
@Composable private fun HomeEtch(modifier: Modifier = Modifier) {
    val spec = WardRelief.raised(WardLift.low, LocalWardLook.current.dark)
    val shade = wardRgb(spec.shade.hex).copy(alpha = spec.shade.alpha.toFloat())
    val highlight = wardRgb(spec.highlight.hex).copy(alpha = spec.highlight.alpha.toFloat())
    Canvas(modifier.fillMaxWidth().height(2.dp)) {
        val w = 1.dp.toPx()
        drawLine(shade, Offset(0f, w / 2), Offset(size.width, w / 2), w)
        drawLine(highlight, Offset(0f, w * 1.5f), Offset(size.width, w * 1.5f), w)
    }
}

// MARK: - Vitals and the brain map

/**
 * The two tiles under the round, side by side (one above the other at the
 * accessibility sizes): Vitals opens the Vitals screen, the brain map Ideas.
 */
@Composable fun HomeTiles(streak: Int, rhythm: RhythmReading.Reading, ideas: Int, links: Int,
                          onVitals: () -> Unit, onIdeas: () -> Unit, book: HomePartBook? = null,
                          readiness: com.stethoscore.app.data.ReadinessEstimate? = null) {
    val brainLine = if (ideas <= 0) "Your ideas, joined up on a map" else {
        var line = BedPlan.counted(ideas, "idea")
        if (links > 0) line += " · " + BedPlan.counted(links, "link")
        line
    }
    val vitalsSpoken = listOf("Vitals", if (readiness != null) "Readiness ${Math.round(readiness.center * 100)} percent" else "Readiness not estimated yet",
        streakText(streak), rhythm.spoken).joinToString(". ")
    val reach = WardRelief.rimOffset(WardLift.low) + WardRelief.rimBlur(WardLift.low)
    val vitals: @Composable (Modifier) -> Unit = { m ->
        HomeTile(onVitals, "$vitalsSpoken. Opens Vitals", m) { VitalsTileFace(readiness, streak, rhythm) }
    }
    val brain: @Composable (Modifier) -> Unit = { m ->
        HomeTile(onIdeas, "Brain map. $brainLine. Opens Ideas: the idea dump, its board and the 3D map", m) { BrainMapTileFace(brainLine) }
    }
    val tiles = Modifier.homePart(book, "tiles", "the tiles", reach)
    if (wardAccessibilitySize()) Column(tiles, verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
        vitals(Modifier.fillMaxWidth())
        brain(Modifier.fillMaxWidth())
    } else Row(tiles.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
        vitals(Modifier.weight(1f).fillMaxHeight())
        brain(Modifier.weight(1f).fillMaxHeight())
    }
}

/** "12-day streak", or "No streak yet". */
fun streakText(streak: Int): String = if (streak > 0) "$streak-day streak" else "No streak yet"

/**
 * A tile on the home (PopTileStyle at the low lift, homeTile): a soft tile
 * raised low off the base, pressed in under the finger, filling its share
 * of the row.
 */
@Composable private fun HomeTile(onClick: () -> Unit, spoken: String, modifier: Modifier, content: @Composable () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val shape = RoundedCornerShape(WardRadius.card.wardDp)
    Box(modifier
        .capPop(pressed)
        .wardPressFace(shape, WardLift.low, wardDepth(pressed), control = false)
        .clickable(source, indication = null, role = Role.Button, onClick = onClick)
        .clearAndSetSemantics { contentDescription = spoken }
        .padding(WardSpace.l.wardDp)) { content() }
}

/** The Vitals tile: the readiness ring, the streak with a heart, and the last two weeks as a rhythm strip. */
@Composable private fun VitalsTileFace(readiness: com.stethoscore.app.data.ReadinessEstimate?, streak: Int, rhythm: RhythmReading.Reading) {
    Column(verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        HomeSmallCaps("Vitals")
        // the figures beside the ring only where they fit whole; otherwise under it
        ThatFits(
            { Row(horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp), verticalAlignment = Alignment.CenterVertically) { ReadinessRing(readiness); Figures(streak) } },
            { Column(verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) { ReadinessRing(readiness); Figures(streak) } },
        )
        RhythmTrace(rhythm.beats, Modifier.fillMaxWidth().height(18.dp))
    }
}

/** The readiness estimate's middle (StoreInsight.readiness) as a ring; a dash before there is one. */
@Composable private fun ReadinessRing(readiness: com.stethoscore.app.data.ReadinessEstimate?) {
    WardRing(readiness?.center ?: 0.0, Modifier.size(56.dp), tone = WardTone.Blue, lineWidth = 6.0,
        centre = if (readiness == null) "–" else null, spoken = if (readiness == null) "not estimated yet" else null)
}

@Composable private fun Figures(streak: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
        Text("Readiness", style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
        Row(horizontalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Favorite, null, tint = wardColor(WardToken.ecg), modifier = Modifier.size(12.dp))
            Text(streakText(streak), style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
        }
    }
}

/** The brain map tile: a small node graph and the count of ideas. */
@Composable private fun BrainMapTileFace(line: String) {
    Column(verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        HomeSmallCaps("Brain map")
        NodeGlyph(Modifier.size(72.dp, 48.dp))
        Text(line, style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
    }
}

/**
 * The first of two layouts that fits the width whole (ViewThatFits): the
 * first is measured at its own width, and the second is used when that is
 * wider than the room.
 */
@Composable private fun ThatFits(first: @Composable () -> Unit, second: @Composable () -> Unit) {
    SubcomposeLayout { constraints ->
        val wide = subcompose("first", first).map { it.measure(Constraints(maxHeight = constraints.maxHeight)) }
        val fits = wide.maxOfOrNull { it.width }?.let { it <= constraints.maxWidth } ?: true
        val placeables = if (fits) subcompose("fits", first).map { it.measure(constraints.copy(minWidth = 0)) }
        else subcompose("under", second).map { it.measure(constraints.copy(minWidth = 0)) }
        val w = placeables.maxOfOrNull { it.width } ?: 0
        val h = placeables.maxOfOrNull { it.height } ?: 0
        layout(w, h) { placeables.forEach { it.place(0, 0) } }
    }
}

/**
 * A rhythm strip: a beat for each day studied and a flat line for each day
 * off (RhythmReading.beats), oldest on the left, in ECG Red.
 */
@Composable fun RhythmTrace(beats: List<Boolean>, modifier: Modifier = Modifier) {
    val ink = wardColor(WardToken.ecg)
    Canvas(modifier) {
        val complex = listOf(0.30 to 0.0, 0.36 to -0.12, 0.42 to 0.0, 0.48 to 0.10, 0.54 to -0.50,
            0.60 to 0.30, 0.66 to 0.0, 0.78 to -0.14, 0.88 to 0.0)
        val count = maxOf(beats.size, 1)
        val step = size.width / count
        val mid = size.height / 2
        val path = Path().apply { moveTo(0f, mid) }
        beats.forEachIndexed { index, beat ->
            val start = index * step
            if (beat) for ((x, y) in complex) path.lineTo(start + x.toFloat() * step, mid + y.toFloat() * size.height)
            path.lineTo(start + step, mid)
        }
        drawPath(path, ink, style = Stroke(1.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** A small node graph: five ideas and the links between them, in the accent. */
@Composable fun NodeGlyph(modifier: Modifier = Modifier) {
    val ink = wardColor(WardToken.primaryInk)
    Canvas(modifier) {
        val nodes = listOf(0.46 to 0.52, 0.10 to 0.20, 0.14 to 0.84, 0.86 to 0.16, 0.90 to 0.80)
        val links = listOf(0 to 1, 0 to 2, 0 to 3, 0 to 4, 3 to 4, 1 to 2)
        val points = nodes.map { Offset((it.first * size.width).toFloat(), (it.second * size.height).toFloat()) }
        for ((a, b) in links) drawLine(ink.copy(alpha = 0.45f), points[a], points[b], 1.5.dp.toPx())
        points.forEachIndexed { i, p -> drawCircle(ink, (if (i == 0) 6 else 4).dp.toPx(), p) }
    }
}
