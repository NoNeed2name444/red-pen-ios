package com.stethoscore.app.ui.editors

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardControlStates
import com.stethoscore.app.ui.ward.WardEaseInOut
import com.stethoscore.app.ui.ward.WardMotion
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSectionLabel
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDisabledInk
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardField
import com.stethoscore.app.ui.ward.wardFocusRing
import com.stethoscore.app.ui.ward.wardInset
import com.stethoscore.app.ui.ward.wardMillis
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.ward.wardReduceMotion
import com.stethoscore.app.ui.wardColor

// What the library's editors are built from, all of it out of the Ward port
// (ui/ward): iOS's Form in wardForm (a section's small-caps header, its rows
// raised off the base, its footer in Biro Grey), a sheet's bar (Cancel quiet,
// the confirming button compact), TextEditor in its well (popEditorRow),
// CountField (Shared/CountField.swift), DisclosureGroup and EcgLoader
// (WardVitals.swift). The banner and the bottom deck are the Ward kit's
// (WardStates.kt, WardDeck.kt).

/** A sheet's bar: Cancel on the left (wardQuiet), the title inline, the confirming button on the right (wardCompact). */
@Composable internal fun EditorTopBar(title: String, onCancel: (() -> Unit)?, cancelTitle: String = "Cancel", trailing: @Composable () -> Unit = {}) {
    Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp).padding(horizontal = WardSpace.s.wardDp)) {
        if (onCancel != null) Box(Modifier.align(Alignment.CenterStart)) {
            WardTextButton(cancelTitle, onCancel, kind = WardButtonKind.quiet, fills = false)
        }
        Text(title, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink), textAlign = TextAlign.Center, maxLines = 1,
            modifier = Modifier.align(Alignment.Center).widthIn(max = 220.dp).semantics { heading() })
        Box(Modifier.align(Alignment.CenterEnd)) { trailing() }
    }
}

/**
 * A Form section in wardForm: the header in small caps, the rows on a face
 * raised off the base (wardRowBackground), the footer in Biro Grey under it.
 * [rows] false lays the content straight on the base (a tag field, which
 * sits on the grid).
 */
@Composable internal fun EditorSection(
    header: String?,
    footer: String? = null,
    rows: Boolean = true,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        if (header != null) WardSectionLabel(header, Modifier.padding(horizontal = WardSpace.xs.wardDp))
        val body = if (rows) Modifier.fillMaxWidth().wardRaised().padding(WardSpace.m.wardDp) else Modifier.fillMaxWidth()
        Column(body, verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp), content = content)
        if (footer != null) EditorNote(footer, Modifier.padding(horizontal = WardSpace.xs.wardDp))
    }
}

/** A footnote in Biro Grey. */
@Composable internal fun EditorNote(text: String, modifier: Modifier = Modifier, style: WardTextStyle = WardTextStyle.footnote) {
    Text(text, style = style.textStyle(), color = wardColor(WardToken.inkSecondary), modifier = modifier)
}

/** A text box in its well (TextEditor with popEditorRow): several lines, at least [minHeight] tall. */
@Composable internal fun EditorTextArea(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    minHeight: Dp = 90.dp,
    placeholder: String = "",
    enabled: Boolean = true,
    mono: Boolean = false,
    singleLine: Boolean = false,
    label: String? = null,
) {
    val source = remember { MutableInteractionSource() }
    val focused by source.collectIsFocusedAsState()
    val shape = RoundedCornerShape(WardRadius.field.wardDp)
    val ink = if (enabled) wardColor(WardToken.ink) else wardDisabledInk()
    val style = (if (mono) WardTextStyle.footnote.textStyle(mono = true) else WardType.body.textStyle()).copy(color = ink)
    BasicTextField(
        value, onValueChange,
        modifier = modifier.fillMaxWidth().wardFocusRing(shape, focused, wardColor(WardControlStates.focusInk))
            .then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier),
        enabled = enabled, singleLine = singleLine, interactionSource = source, textStyle = style,
        cursorBrush = SolidColor(wardColor(WardToken.primaryInk)),
        decorationBox = { inner ->
            Box(Modifier.fillMaxWidth().heightIn(min = minHeight).wardField(), contentAlignment = if (singleLine) Alignment.CenterStart else Alignment.TopStart) {
                if (value.isEmpty() && placeholder.isNotEmpty()) Text(placeholder, style = style.copy(color = wardDisabledInk()))
                inner()
            }
        },
    )
}

/** EcgLoader: an ECG trace drawn again and again in ECG Red, 64 by 24, "Working" to TalkBack. */
@Composable internal fun EcgLoader(modifier: Modifier = Modifier) {
    val color = wardColor(WardToken.ecg)
    // the one loop the canon keeps: iOS's .easeInOut(duration: 1.2), drawn again from the start each time;
    // with animations off the whole trace stands still, as iOS's does under Reduce Motion
    val trace = if (wardReduceMotion()) null else rememberInfiniteTransition(label = "ecg").animateFloat(0f, 1f,
        infiniteRepeatable(tween(wardMillis(WardMotion.trace), easing = WardEaseInOut), RepeatMode.Restart), label = "trace")
    Canvas(modifier.size(64.dp, 24.dp).semantics { contentDescription = "Working" }) {
        val drawn = trace?.value ?: 1f
        val pts = listOf(0f to .55f, .24f to .55f, .31f to .4f, .4f to .65f, .5f to .05f, .61f to .92f, .69f to .45f, .8f to .55f, 1f to .55f)
        val path = Path().apply { pts.forEachIndexed { i, (x, y) -> if (i == 0) moveTo(x * size.width, y * size.height) else lineTo(x * size.width, y * size.height) } }
        val measure = PathMeasure().apply { setPath(path, false) }
        val part = Path()
        measure.getSegment(0f, measure.length * drawn, part, true)
        drawPath(part, color, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/**
 * CountField: the title, then minus, the number and plus on one well, so the
 * keys ride with the number. A typed number is kept within [range] when the
 * field is left or submitted.
 */
@Composable internal fun CountField(title: String, value: Int, range: IntRange, onValueChange: (Int) -> Unit, enabled: Boolean = true) {
    var text by remember { mutableStateOf(value.toString()) }
    LaunchedEffect(value) { if (text.toIntOrNull() != value) text = value.toString() }
    fun commit() {
        val typed = text.filter { it.isDigit() }.toIntOrNull()
        val kept = (typed ?: value).coerceIn(range.first, range.last)
        text = kept.toString()
        if (kept != value) onValueChange(kept)
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = WardType.body.textStyle(), color = if (enabled) wardColor(WardToken.ink) else wardDisabledInk(), modifier = Modifier.weight(1f))
        Row(Modifier.wardInset(CircleShape, control = true), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            WardCircleButton(Icons.Rounded.Remove, "One fewer", { onValueChange((value - 1).coerceAtLeast(range.first)) }, enabled = enabled && value > range.first)
            BasicTextField(text, { typed -> text = typed.filter { it.isDigit() }.take(6); text.toIntOrNull()?.let { if (it in range) onValueChange(it) } },
                modifier = Modifier.widthIn(min = 44.dp, max = 64.dp).semantics { contentDescription = title },
                enabled = enabled, singleLine = true,
                textStyle = WardTextStyle.body.textStyle(mono = true).copy(color = if (enabled) wardColor(WardToken.ink) else wardDisabledInk(), textAlign = TextAlign.Center, fontFamily = FontFamily.Monospace),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { commit() }),
                cursorBrush = SolidColor(wardColor(WardToken.primaryInk)))
            WardCircleButton(Icons.Rounded.Add, "One more", { onValueChange((value + 1).coerceAtMost(range.last)) }, enabled = enabled && value < range.last)
        }
    }
}

/** DisclosureGroup: the title with its chevron, the rest shown under it once opened. */
@Composable internal fun MoreOptions(title: String, expanded: Boolean, onToggle: (Boolean) -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
            .clickable(role = Role.Button, onClickLabel = if (expanded) "Collapse" else "Expand") { onToggle(!expanded) },
            verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = WardType.body.textStyle(), color = wardColor(WardToken.ink), modifier = Modifier.weight(1f))
            Icon(if (expanded) Icons.Rounded.KeyboardArrowDown else Icons.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.primaryInk))
        }
        if (expanded) content()
    }
}

/** A gap between a page's sections. */
@Composable internal fun SectionGap() = Spacer(Modifier.size(WardSpace.xs.wardDp))

/** A footnote's words, semibold, for a group's own title ("Or paste your notes"). */
@Composable internal fun EditorRowTitle(text: String) {
    Text(text, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
}
