package com.stethoscore.app.ui.learn

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.DailyGoal
import com.stethoscore.app.data.GoalProgress
import com.stethoscore.app.data.LearnDefaults
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.data.StudyStreak
import com.stethoscore.app.data.WardRound
import com.stethoscore.app.data.WardRoundPlan
import com.stethoscore.app.ui.home.HomeRound
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardRing
import com.stethoscore.app.ui.ward.WardSegmented
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.ward.wardRelief
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import kotlin.math.roundToInt

// A port of ios/RedPen/Features/Learn/WardRoundView.swift and
// WardRoundOverlay.swift: the tile that starts a ward round (on the exam
// plan), the chip that floats over the app while it runs and the panel it
// opens into, and the goal ring beside the streak.
//
// The time left is a WardRing that redraws once a second, and only while a
// clock is actually running: a paused round, a finished break and a finished
// round are still pictures.

internal object WardRoundStyle {
    /** The section's accent while focusing, green on a break, grey while paused. */
    fun tone(round: WardRound): WardTone {
        if (round.phase == WardRound.Phase.Rest || round.phase == WardRound.Phase.Ready) return WardTone.Green
        return if (round.isPaused) WardTone.Grey else WardTone.Blue
    }
}

/**
 * Now, once a second while the round's clock runs, on the second the clock
 * text changes (WardRoundTicker); otherwise the moment it was drawn.
 */
@Composable internal fun rememberRoundNow(round: WardRound): Long {
    var now by remember(round) { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(round) {
        now = System.currentTimeMillis()
        if (!round.ticks) return@LaunchedEffect
        while (true) {
            // counted from the phase's end, so each tick lands as the clock text turns over
            val rest = Math.floorMod(round.phaseEnds - System.currentTimeMillis(), 1000L)
            delay(if (rest == 0L) 1000L else rest)
            now = System.currentTimeMillis()
        }
    }
    return now
}

/** The time left as a small ring with no numeral, for the tile and the chip. */
@Composable internal fun WardRoundMiniRing(round: WardRound, now: Long, width: Double = 3.0, size: Double = 22.0) {
    Box(Modifier.size(size.wardDp).clearAndSetSemantics {}) {
        WardRing(round.leftFraction(now), Modifier.fillMaxSize(), tone = WardRoundStyle.tone(round), lineWidth = width, centre = "")
    }
}

// MARK: the tile

/**
 * "Start a ward round": the choice of 25 or 50 minutes and a 5- or 10-minute
 * break, and the start. While one runs, its ring and a way in.
 */
@Composable internal fun WardRoundTile(modifier: Modifier = Modifier) {
    val round = WardRoundClock.round
    // raised as low as the tiles round it, the button proud of it
    WardCardFace(modifier.fillMaxWidth(), lift = WardLift.low, padding = 14.dp, spacing = 12.dp) {
        if (round != null) Running(round) else Setup()
    }
}

@Composable private fun Setup() {
    val defaults = LearnDefaults.shared
    var focus by remember { mutableStateOf(defaults.int(WardRoundClock.focusKey) ?: 25) }
    var rest by remember { mutableStateOf(defaults.int(WardRoundClock.breakKey) ?: 5) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Rounded.MedicalServices, null, Modifier.size(20.dp), tint = wardColor(WardToken.primaryInk))
        Text("Start a ward round", style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
    }
    Text("Four rounds of focus with a break between. Everything you study while the clock runs counts on the round, and its minutes count for your streak.",
        style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
    WardSegmented(focus, WardRoundPlan.focusChoices, { focus = it; defaults.setInt(WardRoundClock.focusKey, it) },
        Modifier.fillMaxWidth().semantics { contentDescription = "Focus" }) { minutes, style, color ->
        Text("$minutes min", style = style, color = color, maxLines = 1)
    }
    WardSegmented(rest, WardRoundPlan.breakChoices, { rest = it; defaults.setInt(WardRoundClock.breakKey, it) },
        Modifier.fillMaxWidth().semantics { contentDescription = "Break" }) { minutes, style, color ->
        Text("$minutes min break", style = style, color = color, maxLines = 1)
    }
    WardButtonBox({ WardRoundClock.start(WardRoundPlan(focus, rest)) }, kind = WardButtonKind.primary) {
        Icon(Icons.Rounded.PlayArrow, null, Modifier.size(20.dp))
        Text("Start round 1")
    }
}

@Composable private fun Running(round: WardRound) {
    val now = rememberRoundNow(round)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            WardRoundMiniRing(round, now, width = 4.0, size = 40.0)
            Text(round.caption(now), style = WardTextStyle.subheadline.textStyle(WardWeight.semibold, mono = true),
                color = wardColor(WardToken.ink), maxLines = 2)
        }
        Spacer(Modifier.size(8.dp))
        WardTextButton("Open", { WardRoundClock.expanded = true }, kind = WardButtonKind.compact, fills = false)
    }
}

// MARK: the chip

/**
 * The small chip over the app while a round runs: the ring and the time, or
 * for a few seconds what just ended. Tap to open the round; the overlay drags it.
 */
@Composable internal fun WardRoundChip(round: WardRound, notice: String?, open: () -> Unit, modifier: Modifier = Modifier) {
    val now = rememberRoundNow(round)
    val view = LocalView.current
    LaunchedEffect(notice) {
        if (notice != null) view.performHapticFeedback(
            if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.CONTEXT_CLICK)
    }
    val style = WardTextStyle.subheadline.textStyle(WardWeight.semibold, mono = true).copy(color = wardColor(WardToken.ink))
    // floating over every screen, so raised high off the base
    Row(modifier.minimumInteractiveComponentSize()
        .wardRelief(RoundedCornerShape(50), WardLift.high)
        .clickable(remember { MutableInteractionSource() }, indication = null, onClick = open)
        .clearAndSetSemantics {
            contentDescription = "Ward round: " + round.caption(now)
            role = Role.Button
            onClick("Open the ward round. Drag to move it to another corner.") { open(); true }
        }
        .heightIn(min = 44.dp).widthIn(max = 300.dp)
        .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        WardRoundMiniRing(round, now)
        BasicText(notice ?: chipWords(round, now), style = style, maxLines = 1,
            autoSize = TextAutoSize.StepBased(minFontSize = 12.sp, maxFontSize = style.fontSize, stepSize = 0.5.sp))
    }
}

private fun chipWords(round: WardRound, now: Long): String {
    val time = WardRound.clock(round.remaining(now))
    return when (round.phase) {
        WardRound.Phase.Focus -> if (round.isPaused) "Paused · $time" else time
        WardRound.Phase.Rest -> "Break · $time"
        WardRound.Phase.Ready -> "Round ${round.round + 1} ready"
        WardRound.Phase.Done -> "Done"
    }
}

// MARK: the panel

/** The round, open over the app: the ring, the count, and what to do next. */
@Composable internal fun WardRoundPanel(round: WardRound, notice: String?, close: () -> Unit, modifier: Modifier = Modifier) {
    val now = rememberRoundNow(round)
    Column(modifier.fillMaxWidth().wardRaised(WardRadius.card, WardLift.mid)
        // a tap on the panel itself is not a tap on the dimming behind
        .clickable(remember { MutableInteractionSource() }, indication = null) {}
        .padding(WardSpace.gutter.wardDp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Rounded.MedicalServices, null, Modifier.size(20.dp), tint = wardColor(WardToken.primaryInk))
                Text("Ward round", style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
            }
            Box(Modifier.size(WardControlSize.target.wardDp).clickable(onClickLabel = null, role = Role.Button, onClick = close)
                .semantics { contentDescription = "Fold the ward round away" }, contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.KeyboardArrowDown, null, Modifier.size(20.dp), tint = wardColor(WardToken.inkSecondary))
            }
        }
        Face(round, now)
        if (notice != null) Text(notice, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold),
            color = wardColor(WardToken.ink), textAlign = TextAlign.Center)
        Controls(round, close)
    }
}

@Composable private fun Face(round: WardRound, now: Long) {
    val time = WardRound.clock(round.remaining(now))
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.clearAndSetSemantics { contentDescription = round.caption(now) },
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            WardRing(round.leftFraction(now), Modifier.size(180.dp), tone = WardRoundStyle.tone(round), label = phaseWord(round),
                lineWidth = 6.0, centre = if (round.isTimed) time else "–")
            WardSmallCapsText(round.roundWords)
        }
        // "38 cards · 31 min focused"
        Text(WardRound.cardWords(round.items) + " · ${round.focusMinutes} min focused",
            style = WardTextStyle.subheadline.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
    }
}

private fun phaseWord(round: WardRound): String = when (round.phase) {
    WardRound.Phase.Focus -> if (round.isPaused) "Paused" else "Focus"
    WardRound.Phase.Rest -> "Break"
    WardRound.Phase.Ready -> "Ready"
    WardRound.Phase.Done -> "Done"
}

@Composable private fun Controls(round: WardRound, close: () -> Unit) {
    when (round.phase) {
        WardRound.Phase.Focus -> {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (round.isPaused) Wide("Resume", Icons.Rounded.PlayArrow, Modifier.weight(1f)) { WardRoundClock.resume() }
                else Wide("Pause", Icons.Rounded.Pause, Modifier.weight(1f)) { WardRoundClock.pause() }
                Wide("End round", Icons.Rounded.SkipNext, Modifier.weight(1f)) { WardRoundClock.skip() }
            }
            StopButton(close)
        }
        WardRound.Phase.Rest -> {
            Text("Look away from the screen for a while.", style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
            Wide("Start round ${round.round + 1} now", Icons.Rounded.PlayArrow, Modifier.fillMaxWidth()) { WardRoundClock.startNext() }
            StopButton(close)
        }
        WardRound.Phase.Ready -> {
            Prominent("Start round ${round.round + 1}", Icons.Rounded.PlayArrow) { WardRoundClock.startNext() }
            StopButton(close)
        }
        WardRound.Phase.Done -> Prominent("Close", Icons.Rounded.Check) {
            close()
            WardRoundClock.close()
        }
    }
}

@Composable private fun StopButton(close: () -> Unit) {
    Box(Modifier.heightIn(min = WardControlSize.target.wardDp).clickable(role = Role.Button) {
        close()
        WardRoundClock.stop()
    }.padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
        Text("Stop the ward round", style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.danger))
    }
}

@Composable private fun Wide(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier, action: () -> Unit) {
    WardButtonBox(action, modifier, kind = WardButtonKind.secondary) {
        Icon(icon, null, Modifier.size(20.dp))
        Text(title, maxLines = 1)
    }
}

@Composable private fun Prominent(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, action: () -> Unit) {
    WardButtonBox(action, Modifier.fillMaxWidth(), kind = WardButtonKind.primary) {
        Icon(icon, null, Modifier.size(20.dp))
        Text(title, maxLines = 1)
    }
}

// MARK: over the whole app

/** The four places the chip can sit. */
internal enum class WardRoundCorner(val raw: String) {
    topLeading("topLeading"), topTrailing("topTrailing"), bottomLeading("bottomLeading"), bottomTrailing("bottomTrailing");

    val isBottom: Boolean get() = this == bottomLeading || this == bottomTrailing
    val isLeading: Boolean get() = this == topLeading || this == bottomLeading

    companion object {
        const val key = "wardRound.corner"
        fun from(raw: String?): WardRoundCorner = entries.firstOrNull { it.raw == raw } ?: bottomLeading

        /** [x] (from the leading edge) and [y] as fractions of the window. */
        fun nearest(x: Double, y: Double): WardRoundCorner {
            val leading = x < 0.5
            if (y < 0.5) return if (leading) topLeading else topTrailing
            return if (leading) bottomLeading else bottomTrailing
        }
    }
}

/**
 * While a ward round runs, a small chip floats at the bottom of the screen
 * over every page, and stays there wherever the student goes. Tapping it
 * opens the round in a card over everything; dragging it moves it to another
 * corner, out of a screen's way. Only the chip (or the open panel) takes
 * touches; everything else falls through to the app beneath.
 */
@Composable internal fun WardRoundFloat() {
    val round = WardRoundClock.round ?: return
    val notice = WardRoundClock.notice
    if (WardRoundClock.expanded) {
        BackHandler { WardRoundClock.expanded = false }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f))
            .clickable(remember { MutableInteractionSource() }, indication = null) { WardRoundClock.expanded = false }
            .clearAndSetSemantics {})
        Box(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp), contentAlignment = Alignment.BottomCenter) {
            WardRoundPanel(round, notice, { WardRoundClock.expanded = false }, Modifier.widthIn(max = 440.dp))
        }
    } else {
        ChipInCorner(round, notice)
    }
}

@Composable private fun ChipInCorner(round: WardRound, notice: String?) {
    var corner by remember { mutableStateOf(WardRoundCorner.from(LearnDefaults.shared.string(WardRoundCorner.key))) }
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding(), contentAlignment = AbsoluteAlignment.TopLeft) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        var chip by remember { mutableStateOf(IntSize.Zero) }
        var dragging by remember { mutableStateOf(false) }
        var placed by remember { mutableStateOf(false) }
        val position = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
        fun target(c: WardRoundCorner): Offset = with(density) {
            val side = 16.dp.toPx()
            val left = if (c.isLeading != rtl) side else w - side - chip.width
            val top = if (c.isBottom) h - 84.dp.toPx() - chip.height else 52.dp.toPx()
            Offset(left, top)
        }
        LaunchedEffect(corner, chip, w, h) {
            if (chip == IntSize.Zero || dragging) return@LaunchedEffect
            if (!placed) { position.snapTo(target(corner)); placed = true }
            else position.animateTo(target(corner), spring(dampingRatio = 0.85f, stiffness = 600f))
        }
        WardRoundChip(round, notice, { WardRoundClock.expanded = true },
            Modifier.onSizeChanged { chip = it }
                .absoluteOffset { IntOffset(position.value.x.roundToInt(), position.value.y.roundToInt()) }
                .pointerInput(w, h, rtl) {
                    val tracker = VelocityTracker()
                    detectDragGestures(
                        onDragStart = { dragging = true; tracker.resetTracking() },
                        onDragCancel = { dragging = false; scope.launch { position.animateTo(target(corner)) } },
                        onDragEnd = {
                            dragging = false
                            val v = tracker.calculateVelocity()
                            // where a throw is heading: the chip's centre carried on a quarter second
                            val x = position.value.x + chip.width / 2f + v.x * 0.25f
                            val y = position.value.y + chip.height / 2f + v.y * 0.25f
                            val across = (x / maxOf(1f, w)).toDouble()
                            // leading is on the right in a right-to-left language
                            val next = WardRoundCorner.nearest(if (rtl) 1 - across else across, (y / maxOf(1f, h)).toDouble())
                            LearnDefaults.shared.set(WardRoundCorner.key, next.raw)
                            corner = next
                            scope.launch { position.animateTo(target(next), spring(dampingRatio = 0.85f, stiffness = 600f)) }
                        },
                    ) { change, amount ->
                        change.consume()
                        tracker.addPosition(change.uptimeMillis, position.value + change.position)
                        scope.launch { position.snapTo(position.value + amount) }
                    }
                }
                // not seen until it is in its corner
                .alpha(if (placed) 1f else 0f))
    }
}

// MARK: the goal ring and the streak

/** What the exam plan's Today row shows, from what Android keeps. */
internal data class TodayLog(val streak: Int, val restDayReady: Boolean, val today: Int) {
    companion object {
        fun read(store: StudyStore, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): TodayLog {
            val days = HomeRound.studyDays(store, zone)
            val summary = StudyStreak.summary(days.filter { it.value > 0 }.keys, now, zone)
            val done = HomeRound.studyDays(store, zone, minutes = emptyMap())[StudyStreak.key(now, zone)] ?: 0
            return TodayLog(summary.streak, summary.restReady, done)
        }
    }
}

/** A thin ring of today against the daily goal, and "32 / 50 today". */
@Composable internal fun DailyGoalRing(done: Int) {
    val progress = GoalProgress(done, DailyGoal.current)
    val tint = if (progress.met) wardColor(WardToken.success) else wardColor(WardToken.beam)
    val track = wardColor(WardToken.hairline)
    Row(Modifier.clearAndSetSemantics { contentDescription = "Daily goal: ${progress.done} of ${progress.goal} done today" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Canvas(Modifier.size(18.dp)) {
            val stroke = 3.dp.toPx()
            val inset = stroke / 2
            val arcSize = androidx.compose.ui.geometry.Size(size.width - stroke, size.height - stroke)
            drawArc(track, 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(stroke))
            drawArc(tint, -90f, 360f * progress.fraction.toFloat(), false, Offset(inset, inset), arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Text(progress.label, style = WardTextStyle.caption.textStyle(WardWeight.semibold, mono = true),
            color = wardColor(WardToken.inkSecondary), maxLines = 1)
    }
}

/** The streak, the rest day and the goal ring, for the exam plan's Today. */
@Composable internal fun TodayGoalRow(log: TodayLog) {
    val days = if (log.streak == 1) "1-day streak" else "${log.streak}-day streak"
    val rest = if (log.restDayReady) "Rest day ready" else "Rest day used this week"
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(Icons.Rounded.LocalFireDepartment, null, Modifier.size(24.dp),
            tint = if (log.streak > 0) wardColor(WardToken.beam) else wardColor(WardToken.inkSecondary))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(days, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(Icons.Rounded.NightsStay, null, Modifier.size(12.dp), tint = wardColor(WardToken.inkSecondary))
                Text(rest, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        }
        DailyGoalRing(log.today)
    }
}
