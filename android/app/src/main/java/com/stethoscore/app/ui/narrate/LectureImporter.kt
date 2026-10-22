package com.stethoscore.app.ui.narrate

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.stethoscore.app.audio.AudioRate
import com.stethoscore.app.audio.LectureAudio
import com.stethoscore.app.audio.LectureLanguage
import com.stethoscore.app.audio.LectureTranscriber
import com.stethoscore.app.audio.segments
import com.stethoscore.app.data.NarrateScheduler
import com.stethoscore.app.data.NarrateSegment
import com.stethoscore.app.ui.sources.isBroad
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.InputStream

/**
 * Attaching a recording to a Narrate set and transcribing it
 * (ios/RedPen/Features/Narrate/LectureImporter.swift, fed0105): the recording
 * is copied in under the set's id, then Gemini is tried, and the phone after
 * it; both failing is one message, not two alerts.
 *
 * On Android neither transcriber is set up: there is no paid AI and no
 * recogniser that hears a file, so the copy is kept and the student is told
 * so, in iOS's own words for both ways failing. The two transcribers are
 * passed in, so the flow is the same one iOS runs and a test can follow it.
 */
class LectureImporter(
    private val cloud: suspend (File, LectureLanguage) -> List<LectureTranscriber.Line> =
        { _, _ -> throw TranscriberUnavailable(LectureTranscriber.Failure.cloudNotSetUp) },
    private val device: suspend (File, LectureLanguage) -> List<LectureTranscriber.Line> =
        { _, _ -> throw TranscriberUnavailable(LectureTranscriber.Failure.deviceNotSetUp) },
) {
    /** What it is doing, or null when idle: a state, not a percentage. */
    var working by mutableStateOf<String?>(null)
    var trouble by mutableStateOf<String?>(null)
    /** The transcript the recording produced, ready to replace the set's own. */
    var produced by mutableStateOf<List<NarrateSegment>?>(null)
    /** A passing note, such as the lecture being transcribed on the phone instead. */
    var notice by mutableStateOf<String?>(null)
    /** True while Gemini has the recording, so the screen says where it went. */
    var inCloud by mutableStateOf(false)
    /** Whether the Narrate screen is showing; a transcript finishing after it has gone is handed to [keep]. */
    var onScreen = true
    var keep: ((List<NarrateSegment>, LectureLanguage) -> Unit)? = null

    enum class Engine { cloud, device }

    class TranscriberUnavailable(message: String) : Exception(message)

    /** Copies the picked recording in, then transcribes it. Returns the kept file, or null when the copy failed. */
    suspend fun attach(open: () -> InputStream, extension: String, setId: String, dir: File,
                       engine: Engine, language: LectureLanguage, learned: (MutableList<String>) -> Unit): File? {
        trouble = null
        working = "Copying the recording"
        val stored = try {
            withContext(Dispatchers.IO) { LectureAudio.store(open, extension, setId, dir) }
        } catch (e: Exception) {
            working = null
            trouble = e.localizedMessage ?: "The recording could not be copied."
            return null
        }
        transcribe(stored, engine, language, learned)
        return stored
    }

    suspend fun transcribe(file: File, engine: Engine, language: LectureLanguage, learned: (MutableList<String>) -> Unit) {
        trouble = null
        notice = null
        try {
            var lines: List<LectureTranscriber.Line> = emptyList()
            var byLine = false
            if (engine == Engine.cloud) {
                working = "Sending the lecture to Gemini"
                inCloud = true
                try {
                    lines = cloud(file, language)
                    byLine = true
                } catch (e: Exception) {
                    // a transcript from the phone beats no transcript
                    notice = "Transcribed on this phone instead. ${e.message ?: ""}".trimEnd()
                } finally {
                    inCloud = false
                }
            }
            if (!byLine) {
                working = "Listening to the lecture"
                lines = device(file, language)
            }
            if (lines.isEmpty()) {
                working = null
                trouble = "Nothing recognisable was found in that recording."
                return
            }
            val lang = if (language.locale.startsWith("ar")) "ar" else "en"
            val made = NarrateScheduler.segments(lines, lang).toMutableList()
            // everything already learned is applied before the student ever sees the transcript
            val texts = made.map { it.text }.toMutableList()
            learned(texts)
            for (i in made.indices) made[i] = made[i].copy(text = texts[i])
            if (!onScreen) keep?.invoke(made, language)
            produced = made
            working = null
        } catch (e: Exception) {
            working = null
            val why = e.message ?: "The recording could not be transcribed."
            // both ways failed: one message saying so, not two alerts
            val cloudWhy = notice
            if (cloudWhy != null) {
                notice = null
                trouble = cloudWhy.replace("Transcribed on this phone instead. ", "Gemini: ") + "\n\nOn this phone: " + why
            } else {
                trouble = why
            }
        }
    }
}

/**
 * The reading-pace controls, for a set with no recording attached (iOS
 * NarrateReadingControls): Add audio at the leading end, the speed as a
 * compact menu beside Play at the trailing end. With nothing to read yet,
 * adding a recording is the main button on its own.
 */
@Composable internal fun NarrateReadingControls(
    speed: Double, onSpeed: (Double) -> Unit, playing: Boolean, finished: Boolean, canPlay: Boolean, isEmpty: Boolean,
    onPlayPause: () -> Unit, onRestart: () -> Unit, onAddAudio: (() -> Unit)?,
) {
    if (isEmpty && onAddAudio != null) {
        WardButtonBox(onAddAudio, Modifier.semantics { contentDescription = "Add an audio file" }, kind = WardButtonKind.primary) {
            Icon(Icons.Rounded.GraphicEq, null, Modifier.size(20.dp))
            Text("Add audio", maxLines = 1)
        }
        return
    }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val broad = isBroad(maxWidth)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            if (onAddAudio != null) {
                WardButtonBox(onAddAudio, Modifier.semantics { contentDescription = "Add an audio file" },
                    kind = WardButtonKind.secondary, fills = false) {
                    Icon(Icons.Rounded.GraphicEq, null, Modifier.size(20.dp))
                    // words when there is room, the symbol alone on a phone
                    if (broad) Text("Add audio", maxLines = 1)
                }
                if (broad) Spacer(Modifier.weight(1f).widthIn(min = 16.dp))
            }
            SpeedMenu(speed, onSpeed, "Reading speed", mono = false)
            Box(if (broad) Modifier else Modifier.weight(1f)) {
                if (finished) {
                    WardButtonBox(onRestart, kind = WardButtonKind.primary, fills = !broad) {
                        Icon(Icons.Rounded.Replay, null, Modifier.size(20.dp))
                        Text("Start again", maxLines = 1)
                    }
                } else {
                    WardButtonBox(onPlayPause, kind = WardButtonKind.primary, enabled = canPlay, fills = !broad) {
                        Icon(if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, Modifier.size(20.dp))
                        Text(if (playing) "Pause" else "Play", maxLines = 1)
                    }
                }
            }
        }
    }
}

/**
 * The speed as a compact menu showing the one chosen (0.75x to 2.5x), the
 * chosen one ticked; [what] is "Reading speed" or "Playback speed".
 */
@Composable internal fun SpeedMenu(speed: Double, onSpeed: (Double) -> Unit, what: String, mono: Boolean) {
    var open by remember { mutableStateOf(false) }
    val shown = AudioRate.label(speed)
    Box {
        WardButtonBox({ open = true }, Modifier.semantics { contentDescription = "$what, $shown" },
            kind = WardButtonKind.secondary, fills = false) {
            Text(shown, maxLines = 1, fontFamily = if (mono) FontFamily.Monospace else null)
        }
        DropdownMenu(open, { open = false }, containerColor = wardColor(WardToken.raised)) {
            AudioRate.steps.forEach { rate ->
                val chosen = AudioRate.snapped(speed) == rate
                DropdownMenuItem(text = { Text(AudioRate.name(rate)) },
                    leadingIcon = { if (chosen) Icon(Icons.Rounded.Check, null) else Spacer(Modifier.size(24.dp)) },
                    modifier = Modifier.semantics { if (chosen) stateDescription = "Selected" },
                    onClick = { open = false; onSpeed(rate) })
            }
        }
    }
}
