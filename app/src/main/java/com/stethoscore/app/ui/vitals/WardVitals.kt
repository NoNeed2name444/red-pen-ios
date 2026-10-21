package com.stethoscore.app.ui.vitals

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.mock.WardGroove
import com.stethoscore.app.ui.ward.WardSmallCapsText
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardTypeSpec
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.wardColor

// The parts of upstream/ios/RedPen/Shared/Ward/WardVitals.swift the rest of
// the Ward port had not taken yet: EcgStrip and ObsValue. WardRing and
// WardAnnulus are in ui/ward/WardControls.kt, EcgSquiggle in
// ui/home/WardHome.kt and EcgLoader in ui/editors/EditorKit.kt.

/** The amber strip that fills as something goes on: a Pager Amber beam in a groove pressed into the base (WardGroove at 6). */
@Composable fun EcgStrip(progress: Double, tone: Color = wardColor(WardToken.beam)) {
    Box(Modifier.clearAndSetSemantics {}) { WardGroove(progress, tone, 6.dp) }
}

/** An observation: a small-caps label over a mono value, flagged high or low in Resus Red. */
@Composable fun ObsValue(label: String, value: String, flag: ObsFlag? = null) {
    Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        WardSmallCapsText(label)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(value, style = WardTypeSpec(WardType.obs.style, WardWeight.semibold, mono = true).textStyle(),
                color = if (flag == null) wardColor(WardToken.ink) else wardColor(WardToken.danger))
            if (flag != null) Icon(if (flag == ObsFlag.high) Icons.Rounded.ArrowUpward else Icons.Rounded.ArrowDownward,
                if (flag == ObsFlag.high) "high" else "low", tint = wardColor(WardToken.danger), modifier = Modifier.size(14.dp))
        }
    }
}

/** ObsValue's flag. */
@Suppress("EnumEntryName")
enum class ObsFlag { high, low }

/** Rounded percent, as iOS's Int((x * 100).rounded()) has it. */
internal fun percentOf(x: Double): Int = Math.round(x * 100).toInt()

/** "68%". */
internal fun percentText(x: Double): String = "${percentOf(x)}%"

/** The caption's words, for the small lines under a chart. */
@Composable internal fun captionStyle() = WardTextStyle.caption.textStyle()
