package com.stethoscore.app.ui.ward

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.wardColor

// The Compose side of ios/RedPen/Shared/Ward/WardStates.swift, one copy for
// every screen: the empty state, the banner, the groove and the score bar on
// it, and the filter chip. A groove and a banner are wells (wardInset), so
// their fill is the well token's. The rest of WardStates.swift (WardEtch,
// WardGroupedCard, the card tile and wardField) is not ported here.

/**
 * Nothing here yet (WardEmptyState): an icon square, a title, a line saying
 * what to do, and the buttons that do it, at most 420 wide, in the middle of
 * whatever room it is given.
 */
@Composable fun WardEmptyState(
    icon: ImageVector, title: String, message: String? = null, tone: WardTone = WardTone.Blue,
    modifier: Modifier = Modifier, actions: (@Composable ColumnScope.() -> Unit)? = null,
) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 420.dp).padding(WardSpace.xl.wardDp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
            WardIconSquare(icon, tone = tone, size = 56.0)
            Text(title, Modifier.semantics { heading() }, style = WardType.title.textStyle(), color = wardColor(WardToken.ink),
                textAlign = TextAlign.Center)
            if (message != null) Text(message, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary),
                textAlign = TextAlign.Center)
            if (actions != null) Column(Modifier.padding(top = WardSpace.xs.wardDp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), content = actions)
        }
    }
}

/**
 * A line of news across a screen (WardBanner): the tone's glyph and the
 * words in a well pressed into the base, with an optional action at its end,
 * read as one.
 */
@Composable fun WardBanner(
    text: String, icon: ImageVector = Icons.Rounded.Info, tone: WardTone = WardTone.Blue, modifier: Modifier = Modifier,
    actionTitle: String? = null, action: (() -> Unit)? = null,
) {
    Row(modifier.fillMaxWidth().wardInset(WardRadius.field, fill = WardToken.well).padding(WardSpace.m.wardDp)
        .semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        Icon(icon, null, tint = tone.color(), modifier = Modifier.size(18.dp))
        Text(text, Modifier.weight(1f), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
        if (actionTitle != null && action != null) Text(actionTitle, Modifier.clickable(role = Role.Button, onClick = action),
            style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.primaryInk))
    }
}

/**
 * A groove pressed into the base, the tint filling it from the leading edge
 * (WardGroove): progress, scores and the strip under the ECG. The fill keeps
 * a round end however small the fraction, and none at all at zero. It does
 * not move by itself: a caller that glides its fraction animates it.
 */
@Composable fun WardGroove(fraction: Double, tint: Color, modifier: Modifier = Modifier, height: Dp = 8.dp) {
    // it fills as iOS's grooves do (.easeOut(duration: 0.3)); with animations off it is simply there
    val f by animateFloatAsState(fraction.coerceIn(0.0, 1.0).toFloat(), wardEaseOut(WardMotion.fill, wardReduceMotion()), label = "groove")
    val pad = if (height >= 8.dp) 2.dp else 1.5.dp
    BoxWithConstraints(modifier.fillMaxWidth().height(height).wardInset(height.value / 2.0, fill = WardToken.well).padding(pad)) {
        val width = if (f > 0) maxOf(maxHeight, maxWidth * f).coerceAtMost(maxWidth) else 0.dp
        Box(Modifier.width(width).fillMaxHeight().background(tint, CircleShape))
    }
}

/** A score's tone (WardProgressBar.tone): Resus Red under half, Caution Amber under three quarters, Discharge Green above. */
fun wardScoreTone(value: Double): WardTone = when {
    value < 0.5 -> WardTone.Danger
    value < 0.75 -> WardTone.Warning
    else -> WardTone.Green
}

/** A bar for a score (WardProgressBar): the groove in the score's tone. The number is said, never only shown in a colour. */
@Composable fun WardProgressBar(value: Double, label: String = "Score", modifier: Modifier = Modifier) {
    val v = value.coerceIn(0.0, 1.0)
    Box(modifier.clearAndSetSemantics { contentDescription = label; stateDescription = "${Math.round(v * 100)} percent" }) {
        WardGroove(v, wardScoreTone(v).color())
    }
}

/**
 * A chip that filters (WardFilterChip): a soft capsule raised off the base,
 * 36 tall in a full target; on, it is pressed in and its words take the
 * section's accent.
 */
@Composable fun WardFilterChip(text: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector? = null) {
    val ink = if (selected) wardColor(WardToken.primaryInk) else wardColor(WardToken.ink)
    Box(modifier.defaultMinSize(minHeight = WardControlSize.target.wardDp).selectable(selected, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center) {
        Row(Modifier.heightIn(min = WardControlSize.segment.wardDp).wardPressFace(CircleShape, WardLift.low, wardDepth(selected))
            .padding(horizontal = WardSpace.m.wardDp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (icon != null) Icon(icon, null, tint = ink, modifier = Modifier.size(14.dp))
            Text(text, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = ink, maxLines = 1)
        }
    }
}
