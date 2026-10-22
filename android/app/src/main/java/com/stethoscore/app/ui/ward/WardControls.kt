package com.stethoscore.app.ui.ward

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.ui.wardColor
import java.util.Locale
import kotlin.math.roundToInt

// A port of ios/RedPen/Shared/Ward/WardControls.swift (and the ring of
// WardVitals.swift, the field of WardStates.swift): buttons, chips, pills, icon
// squares, the switch, the segmented control, fields and rings, in soft UI.
// Every control keeps the states WardControlStates names (rest, held,
// disabled, chosen, chosen and held, chosen and disabled), drawn from the
// same roles, plus Android's focused ring:
// - held, it sinks into the base (its face pressed in, the control a little
//   smaller: capPop), never the system's ripple or dimming;
// - disabled, its words go Biro Grey (wardDisabledInk), solid, and it lies at
//   the lowest lift: nothing looks faded;
// - chosen, it is pressed in, its words take the accent and a 2-point accent
//   edge goes round it.

/**
 * The semantic tones a chip, an icon square or a ring can take. `blue` is
 * the accent of the section on show, so a control follows the section's
 * hue; `accent` is a given section's (a mode's own glyph on home).
 */
sealed class WardTone {
    object Blue : WardTone()
    object Red : WardTone()
    object Green : WardTone()
    object Amber : WardTone()
    object Warning : WardTone()
    object Danger : WardTone()
    object Grey : WardTone()
    data class Accent(val section: WardSection) : WardTone()

    /** The tone's colour, for a glyph or an arc. */
    @Composable fun color(): Color = when (this) {
        Blue -> wardColor(WardToken.primaryInk)
        is Accent -> wardAccent(section)
        Red -> wardColor(WardToken.ecg)
        Green -> wardColor(WardToken.success)
        Amber -> wardColor(WardToken.beam)
        Warning -> wardColor(WardToken.warning)
        Danger -> wardColor(WardToken.danger)
        Grey -> wardColor(WardToken.inkSecondary)
    }

    /** Small words in this tone: amber words read in Caution Amber (Pager Amber is 3.3:1 in light). */
    @Composable fun ink(): Color = when (this) {
        Amber, Warning -> wardColor(WardToken.warning)
        else -> color()
    }
}

/** A given section's accent ink, whatever section is on show. */
@Composable fun wardAccent(section: WardSection): Color =
    androidx.compose.ui.graphics.Color(0xFF000000.toInt() or section.accent(com.stethoscore.app.ui.LocalWardLook.current.dark))

/** A disabled control's words, glyphs and switch track: Biro Grey, solid. */
@Composable fun wardDisabledInk(): Color = wardColor(WardControlStates.disabledInk)

/** A control's interaction: held (or drawn held by the gallery) and focused. */
private class WardTouch(val held: Boolean, val focused: Boolean)

@Composable private fun wardTouch(source: MutableInteractionSource, enabled: Boolean): WardTouch {
    val pressed by source.collectIsPressedAsState()
    val focused by source.collectIsFocusedAsState()
    val gallery = LocalWardShowsPressed.current
    return WardTouch(held = enabled && (pressed || gallery), focused = enabled && focused)
}

// MARK: - Buttons

/** WardButtonStyle's kinds. */
enum class WardButtonKind { primary, secondary, destructive, compact, quiet;
    val small: Boolean get() = this == compact || this == quiet
    val control: WardControl get() = WardControl.valueOf(name)
}

/**
 * The buttons: soft capsules raised off the base, 56 tall (compact and
 * quiet 44), at most 360 wide on a broad screen. The kind shows in the
 * label's colour (the accent, Chart Ink, Resus Red), never a fill, and the
 * primary stands a step higher; held, a button is pressed into the base;
 * disabled, it sinks to the lowest step and says its word in Biro Grey.
 */
@Composable fun WardButtonBox(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: WardButtonKind = WardButtonKind.primary,
    enabled: Boolean = true,
    fills: Boolean = true,
    broad: Boolean = false,
    clickLabel: String? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val source = remember { MutableInteractionSource() }
    val touch = wardTouch(source, enabled)
    val look = kind.control.look(if (!enabled) WardControlState.disabled else if (touch.held) WardControlState.pressed else WardControlState.rest)
    val height = if (kind.small) WardControlSize.buttonSmall else WardControlSize.button
    val shape = RoundedCornerShape(50)
    val lift = (look.stand as? WardStand.PressedIn)?.lift ?: (look.stand as WardStand.Raised).lift
    val depth = wardDepth(look.stand.isPressedIn)
    val style = when (kind) {
        WardButtonKind.primary -> WardType.buttonPrimary
        WardButtonKind.secondary, WardButtonKind.destructive -> WardType.button
        else -> WardType.buttonSmall
    }.textStyle()
    val width = when {
        !fills || kind.small -> Modifier
        broad -> Modifier.widthIn(max = WardControlSize.buttonMaxWidth.wardDp).fillMaxWidth()
        else -> Modifier.fillMaxWidth()
    }
    Row(
        modifier
            .then(width)
            .defaultMinSize(minWidth = height.wardDp, minHeight = height.wardDp)
            .capPop(touch.held)
            .wardFocusRing(shape, touch.focused, wardColor(WardControlStates.focusInk))
            .wardPressFace(shape, lift, depth, fill = wardColor(look.face))
            .clickable(source, indication = null, enabled = enabled, onClickLabel = clickLabel, role = Role.Button, onClick = onClick)
            .padding(horizontal = (if (kind.small) WardSpace.m else WardSpace.xl).wardDp,
                vertical = (if (kind.small) WardSpace.s else WardSpace.m).wardDp),
        horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides wardColor(look.words!!),
            androidx.compose.material3.LocalTextStyle provides style) { content() }
    }
}

/** A Ward button with words. */
@Composable fun WardTextButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: WardButtonKind = WardButtonKind.primary,
    enabled: Boolean = true,
    fills: Boolean = true,
) = WardButtonBox(onClick, modifier, kind, enabled, fills) {
    Text(text, textAlign = TextAlign.Center)
}

// MARK: - Chips, circles, tiles

/**
 * A chip that is a button (Sure, Hint, Flag): a capsule raised just off the
 * base, a 44-point target. Chosen, or held, it is pressed in; chosen, its
 * words take [tone] (the accent when it has none) and a solid edge in the
 * same colour goes round it. Disabled, Biro Grey and low; chosen and
 * disabled, it stays pressed in with its edge. Never a fill.
 */
@Composable fun WardChipButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    on: Boolean = false,
    tone: WardTone? = null,
    enabled: Boolean = true,
) {
    val source = remember { MutableInteractionSource() }
    val touch = wardTouch(source, enabled)
    val look = WardControl.chip.look(WardControlState(isChosen = on, isHeld = touch.held, isEnabled = enabled))
    val chosenInk = tone?.ink() ?: wardColor(WardToken.primaryInk)
    val ink = if (!enabled) wardDisabledInk() else if (on) chosenInk else wardColor(look.words!!)
    val shape = CircleShape
    Box(
        modifier
            .defaultMinSize(WardControlSize.target.wardDp, WardControlSize.target.wardDp)
            .selectable(on, enabled = enabled, role = Role.Checkbox, interactionSource = source, indication = null, onClick = onClick)
            .capPop(touch.held),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = WardType.chip.textStyle(), color = ink, maxLines = 1,
            modifier = Modifier
                .wardFocusRing(shape, touch.focused, chosenInk)
                .wardChosenEdge(shape, on, chosenInk)
                .wardPressFace(shape, WardLift.low, wardDepth(look.stand.isPressedIn))
                .padding(horizontal = WardSpace.m.wardDp, vertical = WardSpace.s.wardDp))
    }
}

/**
 * A round button for a glyph (a stepper's minus and plus): a soft circle 44
 * across, the glyph in Chart Ink; chosen, the glyph and an edge in the
 * accent, pressed in. Disabled, Biro Grey and low.
 */
@Composable fun WardCircleButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    on: Boolean = false,
    lift: WardLift = WardLift.low,
    enabled: Boolean = true,
) {
    val source = remember { MutableInteractionSource() }
    val touch = wardTouch(source, enabled)
    val look = WardControl.circle.look(WardControlState(isChosen = on, isHeld = touch.held, isEnabled = enabled))
    Box(
        modifier
            .size(WardControlSize.target.wardDp)
            .capPop(touch.held)
            .wardFocusRing(CircleShape, touch.focused, wardColor(WardControlStates.focusInk))
            .wardChosenEdge(CircleShape, on)
            .wardPressFace(CircleShape, if (enabled) lift else WardLift.low, wardDepth(look.stand.isPressedIn))
            .selectable(on, enabled = enabled, role = Role.Button, interactionSource = source, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription, tint = wardColor(look.glyph!!), modifier = Modifier.size(20.dp))
    }
}

/**
 * A tile on the raised plane (PopTileStyle): raised at mid, pressed in when
 * held or chosen, with the accent edge when chosen. Its label colours
 * itself (WardControl.tile: Chart Ink words, the glyph in the accent).
 */
@Composable fun WardTile(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    chosen: Boolean = false,
    enabled: Boolean = true,
    cornerRadius: Double = WardRadius.card,
    content: @Composable () -> Unit,
) {
    val source = remember { MutableInteractionSource() }
    val touch = wardTouch(source, enabled)
    val look = WardControl.tile.look(WardControlState(isChosen = chosen, isHeld = touch.held, isEnabled = enabled))
    val shape = RoundedCornerShape(cornerRadius.wardDp)
    val lift = when (val s = look.stand) { is WardStand.Raised -> s.lift; is WardStand.PressedIn -> s.lift; else -> WardLift.low }
    Box(
        modifier
            .capPop(touch.held)
            .wardFocusRing(shape, touch.focused, wardColor(WardControlStates.focusInk))
            .wardChosenEdge(shape, chosen)
            .wardPressFace(shape, lift, wardDepth(look.stand.isPressedIn))
            .selectable(chosen, enabled = enabled, role = Role.Button, interactionSource = source, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}

/** A tile's label as the gallery's: the glyph in the accent and Chart Ink words, Biro Grey when disabled. */
@Composable fun WardTileLabel(title: String, icon: ImageVector, enabled: Boolean = true) {
    val look = WardControl.tile.look(if (enabled) WardControlState.rest else WardControlState.disabled)
    Column(Modifier.fillMaxWidth().defaultMinSize(minHeight = 64.dp).padding(horizontal = WardSpace.s.wardDp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp, Alignment.CenterVertically)) {
        Icon(icon, null, tint = wardColor(look.glyph!!), modifier = Modifier.size(22.dp))
        Text(title, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(look.words!!),
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// MARK: - Labels: chips, pills, the timer, icon squares

/** A status chip ("Due", "New", "Weak"): the tone's words in a capsule pressed into the surface, a label, not a button. */
@Composable fun WardChip(text: String, modifier: Modifier = Modifier, tone: WardTone = WardTone.Blue, icon: ImageVector? = null) {
    Row(
        modifier
            .wardInset(CircleShape)
            .padding(horizontal = WardSpace.s.wardDp, vertical = WardSpace.xs.wardDp)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) Icon(icon, null, tint = tone.color(), modifier = Modifier.size(12.dp))
        Text(text, style = WardType.statusChip.textStyle(), color = tone.ink())
    }
}

/** A countdown pill ("Finals in 23 days"): bold Caution Amber words and a Pager Amber clock in a pressed-in capsule. */
@Composable fun WardPill(text: String, modifier: Modifier = Modifier, icon: ImageVector? = Icons.Rounded.Schedule) {
    Row(
        modifier
            .wardInset(CircleShape)
            .padding(horizontal = WardSpace.m.wardDp, vertical = WardSpace.s.wardDp)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) Icon(icon, null, tint = wardColor(WardToken.beam), modifier = Modifier.size(14.dp))
        Text(text, style = WardType.pill.textStyle(), color = wardColor(WardToken.warning))
    }
}

/** The timer's words: "Time" at zero, hours for a paper over an hour (1:05:00). */
fun wardTimerText(seconds: Int): String {
    if (seconds <= 0) return "Time"
    val h = seconds / 3600
    return if (h > 0) String.format(Locale.ROOT, "%d:%02d:%02d", h, seconds % 3600 / 60, seconds % 60)
    else String.format(Locale.ROOT, "%d:%02d", seconds / 60, seconds % 60)
}

/** An exam timer in mono: Resus Red under [warnBelow]; `well = false` drops its own well. */
@Composable fun WardTimerPill(seconds: Int, modifier: Modifier = Modifier, warnBelow: Int = 60, well: Boolean = true) {
    val ink = if (seconds < warnBelow) wardColor(WardToken.danger) else wardColor(WardToken.ink)
    val m = if (well) modifier.wardInset(CircleShape).padding(horizontal = WardSpace.m.wardDp, vertical = WardSpace.s.wardDp) else modifier
    Row(m.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.Timer, null, tint = ink, modifier = Modifier.size(14.dp))
        Text(wardTimerText(seconds), style = WardType.timer.textStyle(), color = ink)
    }
}

/**
 * A rounded icon square: the glyph in its tone on a soft raised square;
 * chosen, the square is pressed in and the glyph takes the accent. No ink
 * edge: the row or tile around it is what is tapped.
 */
@Composable fun WardIconSquare(icon: ImageVector, modifier: Modifier = Modifier, tone: WardTone = WardTone.Blue,
                               size: Double = WardControlSize.iconSquare, selected: Boolean = false) {
    val shape = RoundedCornerShape(WardControlSize.iconRadius(size).wardDp)
    Box(
        modifier.size(size.wardDp)
            .wardPressFace(shape, WardControlSize.iconLift(size), wardDepth(selected), control = false)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = if (selected) wardColor(WardToken.primaryInk) else tone.color(),
            modifier = Modifier.size((size * WardControlSize.iconGlyph).wardDp))
    }
}

// MARK: - The switch

/**
 * A switch in soft UI: a track pressed into the base, a raised knob, and the
 * tint in the track only when it is on. The whole row toggles it; TalkBack
 * hears a switch. Held, the knob sinks into the track; disabled, an on-track
 * goes Biro Grey, the words too, and the knob lies flat with a thin Biro
 * Grey edge, solid, never faded.
 */
@Composable fun WardToggle(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    label: String? = null,
) {
    val source = remember { MutableInteractionSource() }
    val touch = wardTouch(source, enabled)
    val look = WardControl.toggle.look(WardControlState(isChosen = checked, isHeld = touch.held, isEnabled = enabled))
    // the knob crosses as iOS's does (.snappy(duration: 0.2)), never past its end; with animations off it is simply there
    val travel by animateDpAsState(if (checked) (WardControlSize.toggleWidth - WardControlSize.knob - 8).wardDp else 0.dp,
        wardSpring(WardMotion.toggle, wardReduceMotion()), label = "knob")
    val track = CircleShape
    Row(
        modifier
            .toggleable(checked, source, indication = null, enabled = enabled, role = Role.Switch, onValueChange = onCheckedChange)
            .then(if (label == null) Modifier else Modifier.fillMaxWidth()),
        horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp), verticalAlignment = Alignment.CenterVertically,
    ) {
        if (label != null) Text(label, style = WardType.body.textStyle(), color = wardColor(look.words!!), modifier = Modifier.weight(1f))
        Box(
            Modifier.size(WardControlSize.toggleWidth.wardDp, WardControlSize.toggleHeight.wardDp)
                .wardFocusRing(track, touch.focused, wardColor(WardControlStates.focusInk))
                .wardInset(track, control = true),
        ) {
            // the tint is in the track at once, solid; only the knob moves
            if (checked) Box(Modifier.matchParentSize().padding(3.dp).background(wardColor(look.face), track))
            val knob = Modifier.padding(4.dp).offset(x = travel).size(WardControlSize.knob.wardDp)
            when (val stand = look.knobStand) {
                WardStand.Flat -> Box(knob.background(wardColor(WardToken.surface), CircleShape)
                    .border(WardControlStates.knobEdgeWidth.wardDp, wardColor(look.mark!!), CircleShape))
                is WardStand.PressedIn -> Box(knob.wardRelief(CircleShape, stand.lift, inset = true))
                else -> Box(knob.wardRelief(CircleShape, WardLift.low))
            }
        }
    }
}

// MARK: - The segmented control

/**
 * The segmented control: a soft capsule raised off the base, the chosen
 * segment pressed into it with its label in the accent and a solid accent
 * edge round it. Held, a segment sinks into the capsule; disabled, its
 * words go Biro Grey, and the chosen one stays pressed in with its edge.
 */
@Composable fun <T> WardSegmented(
    selection: T,
    options: List<T>,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    label: @Composable (T, TextStyle, Color) -> Unit,
) {
    Row(
        modifier.wardRelief(CircleShape, WardLift.low, control = true).padding(WardControlSize.segmentedPadding.wardDp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for (option in options) {
            val chosen = option == selection
            val source = remember(option) { MutableInteractionSource() }
            val touch = wardTouch(source, enabled)
            val look = WardControl.segment.look(WardControlState(isChosen = chosen, isHeld = touch.held, isEnabled = enabled))
            val down = look.stand.isPressedIn
            Box(
                Modifier.weight(1f)
                    .defaultMinSize(minHeight = WardControlSize.segment.wardDp)
                    .capPop(touch.held)
                    .wardFocusRing(CircleShape, touch.focused, wardColor(WardControlStates.focusInk))
                    .wardChosenEdge(CircleShape, chosen)
                    .then(if (down) Modifier.wardRelief(CircleShape, WardLift.low, wardColor(look.face), inset = true) else Modifier)
                    .selectable(chosen, enabled = enabled, role = Role.Tab, interactionSource = source, indication = null) { onSelect(option) }
                    .padding(horizontal = WardSpace.m.wardDp),
                contentAlignment = Alignment.Center,
            ) {
                label(option, (if (chosen) WardType.segmentChosen else WardType.segment).textStyle(), wardColor(look.words!!))
            }
        }
    }
}

// MARK: - Fields

/** A text field's well: pressed into the base, with a control's ink edge (wardField). */
@Composable fun Modifier.wardField(): Modifier =
    wardInset(RoundedCornerShape(WardRadius.field.wardDp), control = true)
        .padding(horizontal = WardSpace.m.wardDp, vertical = 10.dp)

/**
 * A text field in a well; focused, the accent ring goes round it; disabled,
 * its words go Biro Grey. The placeholder is Biro Grey too, as iOS's prompt.
 */
@Composable fun WardTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    enabled: Boolean = true,
    singleLine: Boolean = true,
) {
    val source = remember { MutableInteractionSource() }
    val focused by source.collectIsFocusedAsState()
    val shape = RoundedCornerShape(WardRadius.field.wardDp)
    val ink = if (enabled) wardColor(WardToken.ink) else wardDisabledInk()
    BasicTextField(
        value, onValueChange,
        modifier = modifier.wardFocusRing(shape, focused, wardColor(WardControlStates.focusInk)),
        enabled = enabled, singleLine = singleLine, interactionSource = source,
        textStyle = WardType.body.textStyle().copy(color = ink),
        cursorBrush = SolidColor(wardColor(WardToken.primaryInk)),
        decorationBox = { inner ->
            Box(Modifier.fillMaxWidth().wardField(), contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty() && placeholder.isNotEmpty()) Text(placeholder, style = WardType.body.textStyle(), color = wardDisabledInk())
                inner()
            }
        },
    )
}

// MARK: - Rings

/**
 * A readiness ring (WardVitals' WardRing): the tone's arc running in a groove
 * pressed into the base, the number in the middle in mono so it reads as an
 * observation. [centre] stands in for the percentage when the ring counts
 * something else, [spoken] for "68 percent".
 */
@Composable fun WardRing(
    value: Double,
    modifier: Modifier = Modifier,
    tone: WardTone = WardTone.Blue,
    label: String? = null,
    lineWidth: Double = WardControlSize.ringLine,
    centre: String? = null,
    spoken: String? = null,
) {
    val v = value.coerceIn(0.0, 1.0)
    val percent = (v * 100).roundToInt()
    val shown = centre ?: "$percent%"
    val clear = WardControlSize.ringClear(lineWidth)
    // the arc sweeps to its value as iOS's WardRing does (.easeOut(duration: 0.3)); with animations off it is simply there
    val sweep by animateFloatAsState(v.toFloat(), wardEaseOut(WardMotion.fill, wardReduceMotion()), label = "ring")
    val arc = tone.color()
    Box(
        modifier.aspectRatio(1f)
            .clearAndSetSemantics {
                contentDescription = label ?: "Progress"
                stateDescription = spoken ?: "$percent percent"
            }
            // the groove: a ring the arc's width and a little clearance, pressed into the base
            .wardRelief(WardAnnulus((lineWidth + 2 * clear).wardDp), WardLift.low, wardColor(WardToken.surface), inset = true)
            .drawBehind {
                val w = (lineWidth + 2 * clear).wardDp.toPx()
                val lw = lineWidth.wardDp.toPx()
                val inset = w / 2
                drawArc(arc, -90f, 360f * sweep, false, topLeft = Offset(inset, inset),
                    size = Size(size.width - 2 * inset, size.height - 2 * inset), style = Stroke(lw, cap = StrokeCap.Round))
            }
            .padding((lineWidth * 1.5 + clear).wardDp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(shown, style = WardTypeSpec(WardTextStyle.title2, WardWeight.semibold, mono = true).textStyle().copy(fontSize = WardControlSize.ringNumeral.sp),
                color = wardColor(WardToken.ink), maxLines = 1)
            if (label != null) Text(label, style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1)
        }
    }
}

// MARK: - Small caps, section labels

/**
 * A small-caps label, spaced at the standard sizes only. iOS keeps the source
 * in mixed case for VoiceOver; TalkBack reads an uppercase word as a word,
 * and screens and tests find the label by its words as shown.
 */
@Composable fun WardSmallCapsText(text: String, modifier: Modifier = Modifier, color: Color = wardColor(WardSmallCaps.colour)) {
    Text(text.uppercase(Locale.getDefault()), style = wardSmallCapsStyle(), color = color, modifier = modifier)
}

/** A section's small-caps label, with an optional trailing link ("See all") in the accent. */
@Composable fun WardSectionLabel(text: String, modifier: Modifier = Modifier, trailing: (@Composable () -> Unit)? = null) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        WardSmallCapsText(text, Modifier.semantics { heading() })
        Spacer(Modifier.weight(1f))
        if (trailing != null) CompositionLocalProvider(
            androidx.compose.material3.LocalContentColor provides wardColor(WardToken.primaryInk),
            androidx.compose.material3.LocalTextStyle provides WardTextStyle.subheadline.textStyle(WardWeight.semibold),
        ) { trailing() }
    }
}

/** A row's trailing chevron, in Biro Grey. */
@Composable fun WardChevron() {
    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
}

/** Dp of a scale step, for callers outside ui/ward. */
fun wardSpace(step: Double): Dp = step.wardDp

/**
 * A ring [width] wide just inside the frame's circle: a shape with a hole,
 * so a fill (and the lights a groove is drawn with) covers the ring alone.
 */
class WardAnnulus(private val width: Dp) : androidx.compose.ui.graphics.Shape {
    override fun createOutline(size: Size, layoutDirection: androidx.compose.ui.unit.LayoutDirection,
                               density: androidx.compose.ui.unit.Density): androidx.compose.ui.graphics.Outline {
        val outer = size.minDimension / 2
        val hole = outer - with(density) { width.toPx() }
        val centre = Offset(size.width / 2, size.height / 2)
        val path = androidx.compose.ui.graphics.Path().apply {
            fillType = androidx.compose.ui.graphics.PathFillType.EvenOdd
            addOval(androidx.compose.ui.geometry.Rect(centre, outer))
            if (hole > 0) addOval(androidx.compose.ui.geometry.Rect(centre, hole))
        }
        return androidx.compose.ui.graphics.Outline.Generic(path)
    }
}
