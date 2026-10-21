package com.stethoscore.app.ui

import android.os.Handler
import androidx.activity.compose.BackHandler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

@Composable
fun ClinicalScreen(set: StudySet, store: StudyStore, onBack: () -> Unit) {
    when (set.kind) {
        StudySetKind.OSCE -> com.stethoscore.app.ui.osce.OsceReviewScreen(set, store, onBack)
        StudySetKind.BOOK -> com.stethoscore.app.ui.book.BookReaderScreen(set, store, onBack)
        StudySetKind.NARRATE -> NarrateScreen(set, store, onBack)
        StudySetKind.CASES -> com.stethoscore.app.ui.cases.CaseListScreen(set, store, onBack)
        else -> Column(Modifier.fillMaxSize().padding(20.dp)) {
            ScreenHeader(set.name, set.kind.label, onBack)
            Text("Open this set from the library to start a review.")
        }
    }
}

@Composable
private fun ClinicalColumn(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp), content = content
    )
}

@Composable
private fun ProgressStrip(label: String, progress: Float, detail: String = "") {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            if (detail.isNotBlank()) Text(detail, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        LinearProgressIndicator(progress = { progress.coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().height(5.dp))
    }
}

@Composable
private fun NarrateScreen(set: StudySet, store: StudyStore, onBack: () -> Unit) {
    val context = LocalContext.current
    val segments = set.narrateSegments
    var line by rememberSaveable(set.id) { mutableIntStateOf((store.readingProgress[set.id]?.position ?: 0).coerceIn(0, (segments.size - 1).coerceAtLeast(0))) }
    var playing by remember { mutableStateOf(false) }
    var speed by rememberSaveable(set.id) { mutableFloatStateOf(1f) }
    var engine by remember { mutableStateOf<TextToSpeech?>(null) }
    var ready by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var activeUtterance by remember { mutableStateOf("") }
    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    DisposableEffect(context, set.id) {
        var disposed = false
        val tts = TextToSpeech(context) { status ->
            mainHandler.post {
                if (!disposed) {
                    ready = status == TextToSpeech.SUCCESS
                    if (!ready) error = "The device speech engine is unavailable. You can still read the transcript."
                }
            }
        }
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) = Unit
            override fun onDone(utteranceId: String?) {
                mainHandler.post {
                    if (!disposed && playing && utteranceId == activeUtterance) {
                        if (line < segments.lastIndex) line++ else playing = false
                    }
                }
            }
            @Deprecated("Deprecated by Android")
            override fun onError(utteranceId: String?) {
                mainHandler.post {
                    if (!disposed && utteranceId == activeUtterance) { playing = false; error = "This line could not be spoken. Try another installed voice or continue reading." }
                }
            }
        })
        engine = tts
        onDispose { disposed = true; tts.stop(); tts.shutdown(); engine = null }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, engine) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                playing = false
                engine?.stop()
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(line, playing, speed, ready) {
        if (segments.isNotEmpty()) store.saveReadingProgress(set.id, line)
        activeUtterance = ""
        engine?.stop()
        if (playing && ready && line in segments.indices) {
            val segment = segments[line]
            val locale = Locale.forLanguageTag(if (segment.lang == "ar") "ar-EG" else segment.lang.ifBlank { "en" })
            val result = engine?.setLanguage(locale)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                error = "No ${locale.displayLanguage} voice is installed on this device. Install a voice in Android text-to-speech settings to listen."
                playing = false
            } else {
                error = null
                engine?.setSpeechRate(speed)
                activeUtterance = "${segment.id}-${System.nanoTime()}"
                if (engine?.speak(segment.text, TextToSpeech.QUEUE_FLUSH, null, activeUtterance) == TextToSpeech.ERROR) {
                    playing = false; error = "The speech engine could not read this line."
                }
            }
        }
    }
    ClinicalColumn {
        ScreenHeader(set.name, "Narrate · Read and listen", onBack)
        if (segments.isEmpty()) {
            WardCard { Text("No transcript lines in this set.") }
            return@ClinicalColumn
        }
        ProgressStrip("Line ${line + 1} of ${segments.size}", (line + 1f) / segments.size, "Device voice")
        WardCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.AutoMirrored.Filled.VolumeUp, null, tint = MaterialTheme.colorScheme.primary)
                Text(if (playing) "Listening" else "Your lecture, at your pace", style = MaterialTheme.typography.titleMedium)
            }
            Text(segments[line].text, style = MaterialTheme.typography.headlineSmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { line = (line - 1).coerceAtLeast(0) }, enabled = line > 0) { Text("Previous") }
                WardButton(if (playing) "Pause" else "Listen", onClick = { playing = !playing }, enabled = ready, modifier = Modifier.weight(1f))
                OutlinedButton(onClick = { line = (line + 1).coerceAtMost(segments.lastIndex) }, enabled = line < segments.lastIndex) { Text("Next") }
            }
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Pace", style = MaterialTheme.typography.labelLarge)
                listOf(0.75f, 1f, 1.25f, 1.5f).forEach { rate ->
                    FilterChip(selected = speed == rate, onClick = { speed = rate }, label = { Text("${rate}×") })
                }
            }
            Text("Speech uses the voices installed on your Android device. Transcript timing is not an original recording.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        }
        SectionLabel("TRANSCRIPT")
        segments.forEachIndexed { index, segment ->
            WardCard(Modifier.fillMaxWidth().clickable { line = index }) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text((index + 1).toString().padStart(2, '0'), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                    Text(segment.text, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, fontWeight = if (index == line) FontWeight.SemiBold else FontWeight.Normal)
                    if (index == line) Icon(Icons.AutoMirrored.Filled.VolumeUp, "Current line", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}
