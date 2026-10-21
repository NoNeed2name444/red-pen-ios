package com.stethoscore.app.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.ui.modeIcon
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardIconSquare
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardInset
import com.stethoscore.app.ui.ward.wardRaised

// The library's small pieces, drawn from the Ward port: a set's row (iOS
// SetRow in WardHome), the heading over a group (CategoryHeading), and the
// parts of Shared/Ward/WardStates.swift the library uses (WardEmptyState,
// WardBanner, WardEtch, WardGroove, EcgStrip). They live here, inside the
// library, until a shared home for them is ported.

/** A group's heading in small caps (iOS CategoryHeading). */
@Composable fun LibraryHeading(title: String, modifier: Modifier = Modifier) {
    WardSmallCapsText(title, modifier.semantics { heading() })
}

/** An empty state: an icon square, a title, a line, and any actions (iOS WardEmptyState). */
@Composable fun LibraryEmptyState(icon: ImageVector, title: String, message: String? = null, modifier: Modifier = Modifier,
                                  tone: WardTone = WardTone.Blue, actions: @Composable ColumnScope.() -> Unit = {}) {
    Column(modifier.fillMaxWidth().padding(WardSpace.xl.wardDp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
        WardIconSquare(icon, tone = tone, size = 56.0)
        Text(title, style = WardType.title.textStyle(), color = wardColor(WardToken.ink), textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() })
        if (message != null) Text(message, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary),
            textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 420.dp))
        Column(Modifier.padding(top = WardSpace.xs.wardDp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), content = actions)
    }
}

/** A line pressed into the base, its glyph in the tone (iOS WardBanner). */
@Composable fun LibraryBanner(text: String, icon: ImageVector, tone: WardTone, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().wardInset(WardRadius.field).padding(WardSpace.m.wardDp),
        horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        Icon(icon, null, tint = tone.color(), modifier = Modifier.size(18.dp))
        Text(text, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink), modifier = Modifier.weight(1f))
    }
}

/** A groove between rows: a shade line over a highlight (iOS WardEtch). */
@Composable fun LibraryEtch(modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(wardColor(WardToken.hairline)))
        Box(Modifier.fillMaxWidth().height(1.dp).background(wardColor(WardToken.surface)))
    }
}

/** A bar run in a groove pressed into the base (iOS WardGroove). */
@Composable fun LibraryGroove(fraction: Double, tint: Color, modifier: Modifier = Modifier, height: Double = 8.0) {
    val f = fraction.coerceIn(0.0, 1.0)
    val pad = if (height >= 8) 2.0 else 1.5
    val bar = maxOf(0.0, height - 2 * pad)
    BoxWithConstraints(modifier.fillMaxWidth().height(height.wardDp).wardInset(height / 2)) {
        val inner = maxOf(0.0, maxWidth.value.toDouble() - 2 * pad)
        val width = if (f > 0) minOf(inner, maxOf(bar, inner * f)) else 0.0
        Box(Modifier.padding(pad.wardDp).width(width.wardDp).height(bar.wardDp).background(tint, CircleShape))
    }
}

/** A set's progress strip, in Pager Amber (iOS EcgStrip). */
@Composable fun LibraryProgressStrip(progress: Double, modifier: Modifier = Modifier) {
    LibraryGroove(progress, wardColor(WardToken.beam), modifier, height = 6.0)
}

/** The face of a "more" menu: an ellipsis on a small soft disc inside a 44-point target (iOS moreMenuFace). */
@Composable fun LibraryMoreFace(spoken: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.size(44.dp).clickable(onClick = onClick).semantics { contentDescription = spoken }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(34.dp).wardRaised(17.0, WardLift.low), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.MoreHoriz, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
        }
    }
}

/** A pushed page's top: back, and the title in the middle (iOS's inline navigation title). */
@Composable fun LibraryPageTop(title: String, onBack: () -> Unit, trailing: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(horizontal = WardSpace.s.wardDp, vertical = WardSpace.xs.wardDp), verticalAlignment = Alignment.CenterVertically) {
        WardCircleButton(Icons.AutoMirrored.Rounded.ArrowBack, "Back", onBack)
        Text(title, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink), textAlign = TextAlign.Center,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).semantics { heading() })
        Box(Modifier.widthIn(min = 44.dp), contentAlignment = Alignment.CenterEnd) { trailing() }
    }
}

/**
 * One set's row (iOS SetRow): its icon in a square, its name with the exam
 * it was written for, "Kind · N items · subject", how far into it the
 * student is, and a deck's cards due.
 */
@Composable fun LibrarySetRow(set: StudySet, due: Int, progress: Double?, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().heightIn(min = 56.dp).padding(vertical = WardSpace.xs.wardDp),
        horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp), verticalAlignment = Alignment.Top) {
        WardIconSquare(modeIcon(set.kind), tone = WardTone.Blue, size = 40.0)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalAlignment = Alignment.CenterVertically) {
                Text(set.name, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink),
                    maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                set.exam?.takeIf { it.isNotBlank() }?.let { exam ->
                    WardChip(exam.uppercase(), Modifier.semantics { contentDescription = "Written for $exam" }, tone = WardTone.Blue)
                }
            }
            Text(kindLine(set), style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1,
                overflow = TextOverflow.Ellipsis)
            if (progress != null) {
                val percent = Math.round(progress.coerceIn(0.0, 1.0) * 100).toInt()
                Row(horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalAlignment = Alignment.CenterVertically) {
                    LibraryProgressStrip(progress, Modifier.widthIn(max = 160.dp).weight(1f, fill = false))
                    Text("$percent%", style = WardTextStyle.caption2.textStyle(WardWeight.semibold, mono = true),
                        color = wardColor(WardToken.inkSecondary), modifier = Modifier.semantics { contentDescription = "$percent percent done" })
                }
            }
        }
        if (due > 0) WardChip("$due due", tone = WardTone.Warning)
    }
}

/** "Kind · N items · subject", the subject left out when it is General (iOS SetRow.kindLine). */
fun kindLine(set: StudySet): String {
    val plural = if (set.itemCount == 1) "" else "s"
    val subject = set.subject.trim()
    val parts = mutableListOf(set.kind.label, "${set.itemCount} ${set.itemNoun}$plural")
    if (subject.isNotEmpty() && subject != "General") parts += subject
    return parts.joinToString(" · ")
}

/** A spacer as tall as a step of the scale. */
@Composable fun LibraryGap(step: Double) { Spacer(Modifier.height(step.wardDp)) }

/** The bar at the bottom with the one thing to do next, the page scrolling above it (iOS studyBar). */
@Composable fun LibraryStudyBar(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth().background(wardColor(WardToken.raised)).padding(horizontal = 16.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center) {
        Box(Modifier.widthIn(max = 700.dp).fillMaxWidth()) { content() }
    }
}

/**
 * A grouped form's section on the Ward (iOS List Section with
 * wardRowBackground): a small-caps header, the rows on one raised card, and
 * a caption footer.
 */
@Composable fun LibraryFormSection(header: String? = null, footer: String? = null, modifier: Modifier = Modifier,
                                   content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        if (header != null) LibraryHeading(header, Modifier.padding(horizontal = WardSpace.xs.wardDp))
        Column(Modifier.fillMaxWidth().wardRaised(WardRadius.card).padding(WardSpace.l.wardDp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp), content = content)
        if (footer != null) Text(footer, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary),
            modifier = Modifier.padding(horizontal = WardSpace.xs.wardDp))
    }
}
