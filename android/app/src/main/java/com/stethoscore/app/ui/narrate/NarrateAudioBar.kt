package com.stethoscore.app.ui.narrate

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Forward30
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.audio.LectureAudio
import com.stethoscore.app.ui.editors.EcgLoader
import com.stethoscore.app.ui.sources.contentCard
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor

/** NowPlaying.back and .forward: the steps a podcast player uses. */
internal object NarrateSkip {
    const val back = 15.0
    const val forward = 30.0
}

/**
 * The controls for a lecture with a recording attached
 * (ios/RedPen/Features/Narrate/NarrateAudioBar.swift, fed0105): the scrub
 * bar with the time and the length, then back fifteen, Play, forward thirty
 * and the speed. While the thumb is held the slider shows the held value and
 * the player is only moved on release, so scrubbing does not fight it.
 */
@Composable internal fun NarrateAudioBar(player: LecturePlayer, speed: Double, onSpeed: (Double) -> Unit) {
    var scrubbing by remember { mutableStateOf(false) }
    var held by remember { mutableDoubleStateOf(0.0) }
    val position = if (scrubbing) held else player.clock.time
    val length = maxOf(player.duration, 0.1)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Slider(position.coerceIn(0.0, length).toFloat(),
                onValueChange = { if (!scrubbing) scrubbing = true; held = it.toDouble() },
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Position in the recording" },
                valueRange = 0f..length.toFloat(),
                onValueChangeFinished = { scrubbing = false; player.seek(held) },
                // a native slider, as iOS's system Slider: it draws no inset shadows, so its
                // empty track keeps the palette's well rather than the page colour wells take
                colors = SliderDefaults.colors(thumbColor = wardColor(WardToken.primaryInk),
                    activeTrackColor = wardColor(WardToken.primaryInk), inactiveTrackColor = wardColor(WardToken.well)))
            Row(Modifier.fillMaxWidth().clearAndSetSemantics {}) {
                val clockStyle = WardTextStyle.subheadline.textStyle(mono = true)
                Text(LectureAudio.clock(position), style = clockStyle, color = wardColor(WardToken.inkSecondary))
                Spacer(Modifier.weight(1f))
                Text(LectureAudio.clock(player.duration), style = clockStyle, color = wardColor(WardToken.inkSecondary))
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            WardButtonBox({ player.skip(-NarrateSkip.back) }, Modifier.semantics { contentDescription = "Back 15 seconds" },
                kind = WardButtonKind.secondary, fills = false) { BackFifteen() }
            Box(Modifier.weight(1f)) {
                WardButtonBox({ player.toggle() }, kind = WardButtonKind.primary) {
                    Icon(if (player.playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, Modifier.size(20.dp))
                    Text(if (player.playing) "Pause" else "Play", maxLines = 1)
                }
            }
            WardButtonBox({ player.skip(NarrateSkip.forward) }, Modifier.semantics { contentDescription = "Forward 30 seconds" },
                kind = WardButtonKind.secondary, fills = false) {
                Icon(Icons.Rounded.Forward30, null, Modifier.size(22.dp))
            }
            SpeedMenu(speed, onSpeed, "Playback speed", mono = true)
        }
    }
}

/** iOS's gobackward.15: the back arrow with its fifteen inside, as Material has no Replay 15. */
@Composable private fun BackFifteen() {
    Box(contentAlignment = Alignment.Center) {
        Icon(Icons.Rounded.Replay, null, Modifier.size(24.dp))
        Text("15", Modifier.padding(top = 2.dp), fontSize = 7.sp, fontWeight = FontWeight.Bold)
    }
}

/**
 * What the screen shows while a recording is being turned into a transcript
 * (TranscribingBanner): the ECG loader, what is happening, and where the
 * recording went.
 */
@Composable internal fun TranscribingBanner(message: String, onDevice: Boolean) {
    val whereLine = if (onDevice) "On this phone. The recording is not uploaded anywhere."
        else "Gemini (Pro) is transcribing it: the recording went through ${com.stethoscore.app.ui.home.HomeBrand.name} to Google."
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp), contentAlignment = Alignment.TopCenter) {
        Row(Modifier.widthIn(max = 700.dp).fillMaxWidth().contentCard(), horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically) {
            EcgLoader()
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(message, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
                Text(whereLine, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        }
    }
}
