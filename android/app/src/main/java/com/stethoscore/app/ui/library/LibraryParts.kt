package com.stethoscore.app.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
import com.stethoscore.app.ui.ward.WardGroove
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
import com.stethoscore.app.ui.ward.wardRaised

// The library's small pieces, drawn from the Ward port: a set's row (iOS
// SetRow in WardHome), the heading over a group (CategoryHeading), the
// etched line (WardEtch) and the set's strip (EcgStrip). The empty state,
// the banner and the groove are the Ward kit's (ui/ward/WardStates.kt).

/** A group's heading in small caps (iOS CategoryHeading). */
@Composable fun LibraryHeading(title: String, modifier: Modifier = Modifier) {
    WardSmallCapsText(title, modifier.semantics { heading() })
}

/** A groove between rows: a shade line over a highlight (iOS WardEtch). */
@Composable fun LibraryEtch(modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(wardColor(WardToken.hairline)))
        Box(Modifier.fillMaxWidth().height(1.dp).background(wardColor(WardToken.surface)))
    }
}

/** A set's progress strip, in Pager Amber (iOS EcgStrip). */
@Composable fun LibraryProgressStrip(progress: Double, modifier: Modifier = Modifier) {
    WardGroove(progress, wardColor(WardToken.beam), modifier, height = 6.dp)
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
