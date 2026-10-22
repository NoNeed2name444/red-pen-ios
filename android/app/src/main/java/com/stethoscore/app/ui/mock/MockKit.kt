package com.stethoscore.app.ui.mock

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardAnnulus
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardControl
import com.stethoscore.app.ui.ward.WardControlState
import com.stethoscore.app.ui.ward.WardControlStates
import com.stethoscore.app.ui.ward.WardIconSquare
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.capPop
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardChosenEdge
import com.stethoscore.app.ui.ward.wardDepth
import com.stethoscore.app.ui.ward.wardDisabledInk
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardInset
import com.stethoscore.app.ui.ward.wardPressFace
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.ward.wardRelief

// The study screens' frame for OSCE and the mock paper, ported from
// ios/RedPen/Shared/Theme.swift (StudyProgressHeader, StudyActionBar,
// FinishHero, FinishSymbol, ScoreRing, ThinProgress, contentCard,
// readableColumn, the big button styles) and Shared/Ward/WardStates.swift
// (WardEmptyState, WardBanner, WardGroove, WardProgressBar), every face and
// control drawn by the Ward port in ui/ward (wardRaised, wardInset,
// WardButtonBox, the chip's look and press). Not ported: the study bar's
// fold, the finish's aurora and its sound, and the pop-out's lean.

/** iOS's bar and screen widths: a phone's column, at most 700 wide on a big screen (readableColumn). */
internal fun Modifier.readableColumn(): Modifier = this.widthIn(max = 700.dp).fillMaxWidth()

/** The navigation bar: back (or [leading]), the title in the middle, [trailing] at the end. */
@Composable internal fun StudyTitleBar(title: String, onBack: (() -> Unit)?, leading: (@Composable () -> Unit)? = null,
                                       trailing: @Composable RowScope.() -> Unit = {}) {
    // 52 tall, as iOS: the back circle's touch area (the least target) fits inside it
    Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).padding(horizontal = 12.dp)) {
        Row(Modifier.align(Alignment.CenterStart), verticalAlignment = Alignment.CenterVertically) {
            if (leading != null) leading()
            else if (onBack != null) WardCircleButton(Icons.AutoMirrored.Rounded.ArrowBack, "Back", onBack)
        }
        Text(title, Modifier.align(Alignment.Center).padding(horizontal = 88.dp).semantics { heading() },
            style = WardType.headline.textStyle(), color = wardColor(WardToken.ink), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Row(Modifier.align(Alignment.CenterEnd), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp), content = trailing)
    }
}

/**
 * The top of a study screen (StudyProgressHeader): what to read ("Step 3 of
 * 12"), a quieter second fact, the bar under it as a length, and the one
 * small control that belongs up here, on a thin slab raised a little off the base.
 */
@Composable internal fun StudyProgressHeader(status: String, detail: String?, fraction: Double?,
                                             accessory: @Composable () -> Unit = {}) {
    Box(Modifier.fillMaxWidth().padding(horizontal = WardSpace.m.wardDp).padding(top = WardSpace.s.wardDp), contentAlignment = Alignment.Center) {
        Column(Modifier.readableColumn().wardRaised(WardRadius.bar, WardLift.low)
            .padding(horizontal = WardSpace.l.wardDp, vertical = WardSpace.m.wardDp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
                    Text(status, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
                    if (detail != null) Text(detail, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
                accessory()
            }
            if (fraction != null) Box(Modifier.clearAndSetSemantics {}) { WardGroove(fraction, wardColor(WardToken.primaryInk), 6.dp) }
        }
    }
}

/** The bottom deck (StudyActionBar): a slab raised off the base holding the screen's buttons. */
@Composable internal fun StudyActionBar(content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 8.dp, top = 4.dp), contentAlignment = Alignment.Center) {
        Column(Modifier.readableColumn().wardRaised(WardRadius.bar, WardLift.low).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

/** The bar's buttons: .bigPrimary, .bigSecondary (raised, its words in ink) and .bigCompanion (only the room its words need). */
internal enum class BigKind { primary, secondary, companion }

@Composable internal fun BigButton(text: String, icon: ImageVector?, kind: BigKind, onClick: () -> Unit, modifier: Modifier = Modifier,
                                   enabled: Boolean = true, label: String? = null) {
    WardButtonBox(onClick, modifier.then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier),
        kind = if (kind == BigKind.primary) WardButtonKind.primary else WardButtonKind.secondary,
        enabled = enabled, fills = kind != BigKind.companion) {
        if (icon != null) Icon(icon, null, Modifier.size(20.dp))
        Text(text, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A reading surface (contentCard): a card raised off the base, padded 24. */
@Composable internal fun ContentCard(modifier: Modifier = Modifier, spacing: Dp = 12.dp, content: @Composable ColumnScope.() -> Unit) {
    WardCardFace(modifier.fillMaxWidth(), padding = WardSpace.xl.wardDp, spacing = spacing, content = content)
}

/**
 * A chip that is a button, holding any label (WardChipButtonStyle): a
 * capsule raised just off the base; chosen or held, pressed in, with a solid
 * edge in [tone] (the accent when it has none) when chosen.
 */
@Composable internal fun ChipBox(on: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, tone: WardTone? = null,
                                 enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val held = enabled && pressed
    val look = WardControl.chip.look(WardControlState(isChosen = on, isHeld = held, isEnabled = enabled))
    val chosenInk = tone?.ink() ?: wardColor(WardToken.primaryInk)
    Box(modifier.defaultMinSize(WardControlSize.target.wardDp, WardControlSize.target.wardDp)
        .selectable(on, enabled = enabled, role = Role.Button, interactionSource = source, indication = null, onClick = onClick)
        .capPop(held), contentAlignment = Alignment.Center) {
        Row(Modifier.wardChosenEdge(CircleShape, on, chosenInk)
            .wardPressFace(CircleShape, WardLift.low, wardDepth(look.stand.isPressedIn))
            .padding(horizontal = WardSpace.m.wardDp, vertical = WardSpace.s.wardDp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), content = content)
    }
}

/** A chip's words and glyph in its colours: [tone] when chosen, Chart Ink at rest, Biro Grey disabled. */
@Composable internal fun chipInk(on: Boolean, tone: WardTone? = null, enabled: Boolean = true): Color = when {
    !enabled -> wardDisabledInk()
    on -> tone?.ink() ?: wardColor(WardToken.primaryInk)
    else -> wardColor(WardToken.ink)
}

/** A groove pressed into the base, the tint filling it from the leading edge (WardGroove). */
@Composable internal fun WardGroove(fraction: Double, tint: Color, height: Dp = 8.dp) {
    val f by animateFloatAsState(fraction.coerceIn(0.0, 1.0).toFloat(), tween(300), label = "groove")
    val pad = if (height >= 8.dp) 2.dp else 1.5.dp
    Box(Modifier.fillMaxWidth().height(height).wardInset(CircleShape)) {
        BoxWithConstraints(Modifier.fillMaxSize().padding(pad)) {
            val bar = maxHeight
            val width = if (f > 0) maxOf(bar, maxWidth * f).coerceAtMost(maxWidth) else 0.dp
            Box(Modifier.width(width).fillMaxHeight().background(tint, CircleShape))
        }
    }
}

/** A bar for a score (WardProgressBar): Resus Red under half, Caution Amber under three quarters, Discharge Green above. */
@Composable internal fun WardProgressBar(value: Double, label: String) {
    val v = value.coerceIn(0.0, 1.0)
    val tone = if (v < 0.5) WardTone.Danger else if (v < 0.75) WardTone.Warning else WardTone.Green
    Box(Modifier.clearAndSetSemantics { contentDescription = label; stateDescription = "${Math.round(v * 100)} percent" }) {
        WardGroove(v, tone.color())
    }
}

/** A line of news across a screen (WardBanner): the tone's glyph and the words in a well pressed into the base. */
@Composable internal fun WardBanner(tone: WardTone, icon: ImageVector, text: String) {
    Row(Modifier.fillMaxWidth().wardInset(RoundedCornerShape(WardRadius.field.wardDp)).padding(WardSpace.m.wardDp)
        .semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        Icon(icon, null, tint = tone.color(), modifier = Modifier.size(18.dp))
        Text(text, Modifier.weight(1f), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
    }
}

/** Nothing here (WardEmptyState): an icon square, the title. */
@Composable internal fun WardEmptyState(icon: ImageVector, title: String, tone: WardTone = WardTone.Blue, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(WardSpace.xl.wardDp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp, Alignment.CenterVertically)) {
        WardIconSquare(icon, tone = tone, size = 56.0)
        Text(title, Modifier.semantics { heading() }, style = WardType.title.textStyle(), color = wardColor(WardToken.ink), textAlign = TextAlign.Center)
    }
}

/** The end of a session (FinishHero): the result on a soft disc raised off the base, the title, and what it means. */
@Composable internal fun FinishHero(title: String, message: String, graphic: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 24.dp, horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.wardRelief(CircleShape, WardLift.mid), contentAlignment = Alignment.Center) { graphic() }
        Text(title, Modifier.semantics { heading() }, style = WardTextStyle.title.textStyle(WardWeight.bold), color = wardColor(WardToken.ink),
            textAlign = TextAlign.Center)
        if (message.isNotEmpty()) Text(message, style = WardType.body.textStyle(), color = wardColor(WardToken.inkSecondary), textAlign = TextAlign.Center)
    }
}

/** The large symbol at the top of a finish (FinishSymbol), in the section's accent. */
@Composable internal fun FinishSymbol(icon: ImageVector) {
    Box(Modifier.size(128.dp).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(72.dp))
    }
}

/** The animated score ring (ScoreRing): an arc in the section's accent in a groove pressed into the base. */
@Composable internal fun ScoreRing(fraction: Double, label: String, sublabel: String) {
    var target by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(fraction) { target = fraction.coerceIn(0.0, 1.0).toFloat() }
    val shown by animateFloatAsState(target, spring(dampingRatio = 0.72f, stiffness = 30f), label = "score")
    val arc = wardColor(WardToken.primaryInk)
    Box(Modifier.size(168.dp).clearAndSetSemantics { contentDescription = "$label $sublabel" }, contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().padding(10.dp).wardRelief(WardAnnulus(12.dp), WardLift.low, wardColor(WardToken.surface), inset = true))
        Box(Modifier.fillMaxSize().padding(16.dp).drawBehind {
            val w = 6.dp.toPx()
            drawArc(arc, -90f, 360f * shown, false, topLeft = Offset(w / 2, w / 2), size = Size(size.width - w, size.height - w),
                style = Stroke(w, cap = StrokeCap.Round))
        })
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, color = wardColor(WardToken.ink), fontSize = 38.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
            Text(sublabel, style = WardTextStyle.footnote.textStyle(WardWeight.medium), color = wardColor(WardToken.inkSecondary))
        }
    }
}

/** Dp of the bar's slab and the edge it keeps, for screens laying out under it. */
internal val chosenEdgeWidth: Dp get() = WardControlStates.chosenEdgeWidth.wardDp

/** A gap between two bar buttons on a broad screen. */
@Composable internal fun RowScope.BroadGap(broad: Boolean) { if (broad) Spacer(Modifier.weight(0.01f).widthIn(min = 16.dp)) }

/**
 * A count typed or stepped (iOS's CountField): the title, then minus, the
 * number in mono and plus on one capsule well. A typed number is kept in
 * [range] when the field loses focus or is submitted.
 */
@Composable internal fun CountField(title: String, value: Int, onValue: (Int) -> Unit, range: IntRange, enabled: Boolean = true) {
    var text by remember(value) { mutableStateOf(value.toString()) }
    fun commit() {
        val typed = text.filter { it.isDigit() }.take(6).toIntOrNull()
        val kept = (typed ?: value).coerceIn(range.first, range.last)
        text = kept.toString()
        if (kept != value) onValue(kept)
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
        Row(Modifier.wardInset(CircleShape), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            WardCircleButton(Icons.Rounded.Remove, "One fewer", { onValue((value - 1).coerceAtLeast(range.first)) },
                enabled = enabled && value > range.first)
            BasicTextField(text, { text = it.filter { c -> c.isDigit() }.take(6) },
                Modifier.minimumInteractiveComponentSize().widthIn(min = 44.dp, max = 64.dp).onFocusChanged { if (!it.isFocused) commit() }
                    .semantics { contentDescription = "$title, between ${range.first} and ${range.last}" },
                enabled = enabled, singleLine = true,
                textStyle = WardType.body.textStyle().copy(fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center,
                    color = if (enabled) wardColor(WardToken.ink) else wardDisabledInk()),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { commit() }),
                cursorBrush = SolidColor(wardColor(WardToken.primaryInk)))
            WardCircleButton(Icons.Rounded.Add, "One more", { onValue((value + 1).coerceAtMost(range.last)) },
                enabled = enabled && value < range.last)
        }
    }
}

/** One choice in a [ConfirmSheet]: its words, and whether it loses something (in Resus Red). */
internal data class ConfirmChoice(val title: String, val destructive: Boolean, val action: () -> Unit)

/**
 * iOS's confirmationDialog as a phone shows it: a sheet from the bottom with
 * the title, what it means, the choices and a way to keep going.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable internal fun ConfirmSheet(title: String, message: String, choices: List<ConfirmChoice>, cancelTitle: String, onDismiss: () -> Unit) {
    androidx.compose.material3.ModalBottomSheet(onDismissRequest = onDismiss, containerColor = wardColor(WardToken.raised)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, Modifier.semantics { heading() }, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink), textAlign = TextAlign.Center)
            if (message.isNotEmpty()) Text(message, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary), textAlign = TextAlign.Center)
            choices.forEach { c ->
                WardButtonBox({ onDismiss(); c.action() }, Modifier.fillMaxWidth(), kind = WardButtonKind.secondary) {
                    Text(c.title, color = if (c.destructive) wardColor(WardToken.danger) else wardColor(WardToken.ink))
                }
            }
            WardButtonBox(onDismiss, Modifier.fillMaxWidth(), kind = WardButtonKind.secondary) {
                Text(cancelTitle, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
