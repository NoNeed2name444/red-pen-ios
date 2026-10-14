package com.stethoscore.app.ui

import android.os.Handler
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
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

@Composable
fun ClinicalScreen(set: StudySet, store: StudyStore, onBack: () -> Unit) {
    when (set.kind) {
        StudySetKind.OSCE -> OsceScreen(set, store, onBack)
        StudySetKind.BOOK -> TextbookScreen(set, store, onBack)
        StudySetKind.NARRATE -> NarrateScreen(set, store, onBack)
        StudySetKind.CASES -> CasesScreen(set, store, onBack)
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
private fun OsceScreen(set: StudySet, store: StudyStore, onBack: () -> Unit) {
    val saved = remember(set.id) { store.osceProgress[set.id]?.takeIf { it.fits(set.osceChecklists) } }
    var stationIndex by rememberSaveable(set.id) { mutableIntStateOf(saved?.checklistIndex ?: 0) }
    var step by rememberSaveable(set.id) { mutableIntStateOf(saved?.stepIndex ?: 0) }
    var misses by rememberSaveable(set.id) { mutableStateOf(ArrayList(saved?.missed ?: emptyList())) }
    var revealed by rememberSaveable(set.id) { mutableStateOf(false) }
    var complete by rememberSaveable(set.id) { mutableStateOf(false) }
    val station = set.osceChecklists.getOrNull(stationIndex)
    val stationSeconds = if (set.exam.orEmpty().contains("paces", true)) 600 else 480
    var secondsLeft by rememberSaveable(set.id) { mutableIntStateOf(stationSeconds) }
    var clockRunning by rememberSaveable(set.id) { mutableStateOf(false) }
    var clockEndsAt by rememberSaveable(set.id) { mutableLongStateOf(0L) }
    LaunchedEffect(clockRunning, clockEndsAt) {
        while (clockRunning) {
            secondsLeft = ((clockEndsAt - System.currentTimeMillis() + 999) / 1000).toInt().coerceAtLeast(0)
            if (secondsLeft == 0) clockRunning = false
            delay(250)
        }
    }
    LaunchedEffect(stationIndex, step, misses, complete) {
        if (station != null) {
            if (complete) {
                clockRunning = false
                val next = set.osceChecklists.getOrNull(stationIndex + 1)
                if (next == null) store.clearOsceProgress(set.id)
                else store.saveOsceProgress(set.id, OsceProgress(stationIndex + 1, next.title, 0))
            } else store.saveOsceProgress(set.id, OsceProgress(stationIndex, station.title, step, misses))
        }
    }
    ClinicalColumn {
        ScreenHeader(set.name, "OSCE · Recall in order", onBack)
        if (station == null || station.steps.isEmpty()) {
            WardCard { Text("No checklist steps in this set.", style = MaterialTheme.typography.titleMedium) }
            return@ClinicalColumn
        }
        ProgressStrip(
            if (complete) "Station complete" else "Step ${step + 1} of ${station.steps.size}",
            if (complete) 1f else step.toFloat() / station.steps.size,
            "Station ${stationIndex + 1}/${set.osceChecklists.size}"
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(station.title, Modifier.weight(1f), style = MaterialTheme.typography.headlineSmall)
            if (!complete) OutlinedButton(onClick = {
                when {
                    clockRunning -> clockRunning = false
                    secondsLeft == 0 -> secondsLeft = stationSeconds
                    else -> { clockEndsAt = System.currentTimeMillis() + secondsLeft * 1000L; clockRunning = true }
                }
            }) {
                Icon(if (clockRunning) Icons.Default.Pause else Icons.Default.PlayArrow, contentDescription = null, Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text("${secondsLeft / 60}:${(secondsLeft % 60).toString().padStart(2, '0')}", color = if (secondsLeft <= 60) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
            }
        }
        if (complete) {
            WardCard {
                Icon(Icons.Default.Check, null, Modifier.size(36.dp), tint = MaterialTheme.colorScheme.primary)
                Text(if (misses.isEmpty()) "All ${station.steps.size} steps, first time" else "Complete after ${misses.size} ${if (misses.size == 1) "restart" else "restarts"}", style = MaterialTheme.typography.headlineSmall)
                Text("You recalled the whole station in order.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (misses.isNotEmpty()) {
                SectionLabel("STEPS TO REVISIT")
                misses.groupingBy { it }.eachCount().entries.sortedWith(compareByDescending<Map.Entry<Int, Int>> { it.value }.thenBy { it.key }).forEach { (index, count) ->
                    WardCard {
                        Text("Step ${index + 1} · $count ${if (count == 1) "restart" else "restarts"}", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                        Text(station.steps.getOrElse(index) { "" })
                    }
                }
            }
            if (stationIndex + 1 < set.osceChecklists.size) WardButton("Next station", onClick = {
                stationIndex++; step = 0; misses = arrayListOf(); complete = false; revealed = false
                secondsLeft = stationSeconds; clockRunning = false
            }, modifier = Modifier.fillMaxWidth())
            WardButton("Done for now", onBack, Modifier.fillMaxWidth())
        } else {
            WardCard(Modifier.fillMaxWidth().heightIn(min = 230.dp)) {
                SectionLabel(if (revealed) "STEP ${step + 1}" else "RECALL BEFORE REVEAL")
                Spacer(Modifier.height(16.dp))
                Text(if (revealed) station.steps[step.coerceIn(station.steps.indices)] else "What comes next?", style = MaterialTheme.typography.headlineSmall)
                if (!revealed) Text("Say the step out loud, then reveal it to check yourself.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(16.dp))
                Text("Attempt ${misses.size + 1}", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            }
            if (!revealed) WardButton("Reveal step", onClick = { revealed = true }, modifier = Modifier.fillMaxWidth())
            else Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = {
                    misses = ArrayList(misses + step); step = 0; revealed = false; secondsLeft = stationSeconds
                    if (clockRunning) clockEndsAt = System.currentTimeMillis() + stationSeconds * 1000L
                }, modifier = Modifier.weight(1f).heightIn(min = 52.dp)) { Text("Start over") }
                WardButton("I got it", onClick = {
                    if (step == station.steps.lastIndex) complete = true else step++
                    revealed = false
                }, modifier = Modifier.weight(1f))
            }
            Text("A missed step restarts the chain from step 1. Your restart points are saved for the finish.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun TextbookScreen(set: StudySet, store: StudyStore, onBack: () -> Unit) {
    val pages = remember(set.bookMarkdown) { splitReadingPages(set.bookMarkdown) }
    var page by rememberSaveable(set.id) { mutableIntStateOf((store.readingProgress[set.id]?.position ?: 0).coerceIn(0, (pages.size - 1).coerceAtLeast(0))) }
    var contents by rememberSaveable(set.id) { mutableStateOf(false) }
    LaunchedEffect(page) { if (pages.isNotEmpty()) store.saveReadingProgress(set.id, page) }
    ClinicalColumn {
        ScreenHeader(set.name, "Textbook · ${set.subject}", onBack)
        if (pages.isEmpty()) {
            WardCard { Text("No textbook pages in this set.") }
            return@ClinicalColumn
        }
        ProgressStrip("Page ${page + 1} of ${pages.size}", (page + 1f) / pages.size, "Position saved")
        OutlinedButton(onClick = { contents = !contents }, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.MenuBook, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text(if (contents) "Close contents" else "Table of contents")
        }
        if (contents) WardCard {
            pages.forEachIndexed { index, item ->
                TextButton(onClick = { page = index; contents = false }, modifier = Modifier.fillMaxWidth()) {
                    Text("${index + 1}. ${item.title}", Modifier.fillMaxWidth(), fontWeight = if (index == page) FontWeight.Bold else FontWeight.Normal)
                }
            }
        }
        key(page) {
            SelectionContainer {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    readingBlocks(pages[page].markdown).forEach { block -> MarkdownBlock(block) }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = { page-- }, enabled = page > 0, modifier = Modifier.weight(1f).heightIn(min = 52.dp)) { Text("Previous") }
            WardButton(if (page == pages.lastIndex) "Finish reading" else "Next page", onClick = {
                if (page == pages.lastIndex) onBack() else page++
            }, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun MarkdownBlock(block: ReadingBlock) {
    val text = remember(block.text) { inlineMarkdown(block.text) }
    when (block.kind) {
        ReadingBlockKind.HEADING -> Text(text, style = if (block.level <= 2) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 8.dp))
        ReadingBlockKind.CALLOUT -> WardCard { Text(text, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyLarge) }
        ReadingBlockKind.TABLE_ROW -> Text(text, Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(10.dp)).padding(12.dp), style = MaterialTheme.typography.bodyMedium)
        ReadingBlockKind.CODE -> Text(text, Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(10.dp)).padding(12.dp), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
        else -> Text(text, style = MaterialTheme.typography.bodyLarge)
    }
}

private fun inlineMarkdown(value: String): AnnotatedString = buildAnnotatedString {
    val tokens = Regex("\\*\\*(.+?)\\*\\*|`([^`]+)`|(?<!\\*)\\*([^*]+)\\*(?!\\*)|_([^_]+)_|\\[([^]]+)]\\(([^)]+)\\)")
    var cursor = 0
    tokens.findAll(value).forEach { token ->
        append(value.substring(cursor, token.range.first))
        when {
            token.groupValues[1].isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(token.groupValues[1]) }
            token.groupValues[2].isNotEmpty() -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append(token.groupValues[2]) }
            token.groupValues[3].isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(token.groupValues[3]) }
            token.groupValues[4].isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(token.groupValues[4]) }
            else -> append(token.groupValues[5])
        }
        cursor = token.range.last + 1
    }
    append(value.substring(cursor))
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

@Composable
private fun CasesScreen(set: StudySet, store: StudyStore, onBack: () -> Unit) {
    var activeId by rememberSaveable(set.id) { mutableStateOf<String?>(null) }
    val allowed = set.caseFiles.filter { it.verification.lowercase() !in setOf("flagged", "held") && it.heldBecause.isEmpty() }
    val active = allowed.firstOrNull { it.id == activeId }
    if (active != null) {
        key(active.id) { CaseWorkupScreen(set, active, store) { activeId = null } }
        return
    }
    ClinicalColumn {
        ScreenHeader(set.name, "Cases · Clinical decisions", onBack)
        Text("From arrival to a decision", style = MaterialTheme.typography.headlineSmall)
        Text("Read the clerking note, choose examinations and tests, then commit to a diagnosis and next step.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        allowed.forEach { file ->
            val saved = parseCaseSession(store.caseRuns[caseRunKey(set, file)])
            WardCard(Modifier.fillMaxWidth().clickable { activeId = file.id }) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(48.dp).background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                        Text(file.patient.initials.ifBlank { "PT" }, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onPrimaryContainer)
                    }
                    Column(Modifier.weight(1f)) {
                        Text(file.patient.name.ifBlank { file.title }, style = MaterialTheme.typography.titleLarge)
                        Text("${file.patient.ageSex} · ${file.setting.replaceFirstChar { it.uppercase() }}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text("${file.budgetMinutes} min", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                }
                Text(file.complaint.ifBlank { file.title }, style = MaterialTheme.typography.bodyLarge)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(if (saved.finished) "Discharged · ${scoreClinicalCase(file, saved.taken.toSet(), saved.ladder.firstOrNull().orEmpty(), saved.nextStep).total}/100" else if (saved.taken.isNotEmpty()) "Seen · Resume work-up" else "New patient", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                    Text("Open →", style = MaterialTheme.typography.labelLarge)
                }
            }
        }
        if (allowed.isEmpty()) WardCard { Text("No available cases in this set.") }
        if (allowed.size < set.caseFiles.size) Text("${set.caseFiles.size - allowed.size} flagged or held cases are withheld from practice.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
    }
}

private data class CaseSession(val taken: List<String> = emptyList(), val ladder: List<String> = emptyList(), val nextStep: Int = -1, val reason: String = "", val finished: Boolean = false, val history: String = "[]")
private fun caseRunKey(set: StudySet, file: CaseFile) = "${set.id}:${file.id}"
private fun parseCaseSession(raw: String?): CaseSession = runCatching {
    val item = JSONObject(raw ?: "{}")
    fun strings(key: String): List<String> = item.optJSONArray(key)?.let { array -> (0 until array.length()).map { array.optString(it) } } ?: emptyList()
    CaseSession(strings("taken"), strings("ladder"), item.optInt("nextStep", -1), item.optString("reason"), item.optBoolean("finished"), item.optJSONArray("history")?.toString() ?: "[]")
}.getOrDefault(CaseSession())

@Composable
private fun CaseWorkupScreen(set: StudySet, file: CaseFile, store: StudyStore, onBack: () -> Unit) {
    val saved = remember(file.id) { parseCaseSession(store.caseRuns[caseRunKey(set, file)]) }
    var taken by rememberSaveable(file.id) { mutableStateOf(ArrayList(saved.taken.filter { id -> file.steps.any { it.id == id } })) }
    var first by rememberSaveable(file.id) { mutableStateOf(saved.ladder.getOrElse(0) { "" }) }
    var second by rememberSaveable(file.id) { mutableStateOf(saved.ladder.getOrElse(1) { "" }) }
    var third by rememberSaveable(file.id) { mutableStateOf(saved.ladder.getOrElse(2) { "" }) }
    var nextStep by rememberSaveable(file.id) { mutableIntStateOf(saved.nextStep) }
    var reason by rememberSaveable(file.id) { mutableStateOf(saved.reason) }
    var finished by rememberSaveable(file.id) { mutableStateOf(saved.finished) }
    var deciding by rememberSaveable(file.id) { mutableStateOf(false) }
    var history by rememberSaveable(file.id) { mutableStateOf(saved.history) }
    var showClerking by rememberSaveable(file.id) { mutableStateOf(true) }
    val used = file.steps.filter { it.id in taken }.sumOf { it.minutes }
    fun snapshot(action: String, atMinutes: Int = used) {
        val items = runCatching { JSONArray(history) }.getOrDefault(JSONArray())
        items.put(JSONObject().put("after", action).put("ladder", JSONArray(listOf(first, second, third))).put("minutes", atMinutes))
        history = items.toString()
    }
    LaunchedEffect(taken, first, second, third, nextStep, reason, finished, history) {
        store.saveCaseRun(caseRunKey(set, file), JSONObject().put("taken", JSONArray(taken)).put("ladder", JSONArray(listOf(first, second, third))).put("nextStep", nextStep).put("reason", reason).put("finished", finished).put("history", JSONArray(history)).toString())
    }
    ClinicalColumn {
        ScreenHeader(file.patient.name.ifBlank { file.title }, "${file.patient.ageSex} · ${file.setting.replaceFirstChar { it.uppercase() }}", onBack)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            SectionLabel(if (finished) "DISCHARGE SUMMARY" else if (deciding) "YOUR DECISION" else "ARRIVAL & WORK-UP")
            Text("$used / ${file.budgetMinutes} min", color = if (used > file.budgetMinutes) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.titleMedium)
        }
        if (file.verification.lowercase() !in setOf("verified", "checked", "passed")) {
            Text("${if (file.id.startsWith("demo") || set.tags.any { it.equals("demo", true) }) "Practice case" else "Verification"}: ${file.verification.ifBlank { "unchecked" }}. Review against your teaching material.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (finished) {
            CaseDebrief(set, file, store, taken.toSet(), first, nextStep, reason, history)
            WardButton("Back to patients", onBack, Modifier.fillMaxWidth())
            OutlinedButton(onClick = {
                taken = arrayListOf(); first = ""; second = ""; third = ""; nextStep = -1; reason = ""; finished = false; deciding = false; history = "[]"
            }, modifier = Modifier.fillMaxWidth()) { Text("Practise this patient again") }
            return@ClinicalColumn
        }
        if (!deciding) {
            WardCard {
                Text("“${file.complaint}”", style = MaterialTheme.typography.headlineSmall)
                if (file.patient.about.isNotBlank()) Text(file.patient.about, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (file.arrival.isNotEmpty()) {
                    file.arrival.chunked(3).forEach { row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            row.forEach { obs ->
                                Column(Modifier.weight(1f).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(10.dp)).padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(obs.label, style = MaterialTheme.typography.labelSmall)
                                    Text(obs.shown, style = MaterialTheme.typography.titleMedium)
                                    Text(obs.unit, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
                TextButton(onClick = { showClerking = !showClerking }) { Text(if (showClerking) "Hide clerking note" else "Read clerking note") }
                if (showClerking) file.clerking.parts.forEach { (label, text) ->
                    Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                    Text(text, style = MaterialTheme.typography.bodyMedium)
                }
            }
            if (taken.isNotEmpty()) {
                SectionLabel("CLINICAL NOTE · ${taken.size} FINDINGS")
                taken.reversed().mapNotNull { id -> file.steps.firstOrNull { it.id == id } }.forEach { step ->
                    WardCard {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(step.label, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                            Text("${step.minutes} min", style = MaterialTheme.typography.labelMedium)
                        }
                        Text(step.finding)
                        step.results.forEach { result ->
                            val flag = when { result.low != null && result.value < result.low -> " L"; result.high != null && result.value > result.high -> " H"; else -> "" }
                            Text("${result.name}  ${result.value} ${result.unit}$flag", color = if (flag.isEmpty()) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
            listOf("examine" to "EXAMINE", "test" to "TEST").forEach { (group, label) ->
                val actions = file.steps.filter { it.group.equals(group, true) }
                if (actions.isNotEmpty()) {
                    SectionLabel(label)
                    actions.forEach { step ->
                        OutlinedButton(onClick = {
                            if (step.id !in taken) { snapshot(step.id, used + step.minutes); taken = ArrayList(taken + step.id) }
                        }, enabled = step.id !in taken, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
                            if (step.id in taken) { Icon(Icons.Default.Check, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
                            Text(step.label, Modifier.weight(1f))
                            Text("${step.minutes} min", style = MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            }
            if (used > file.budgetMinutes) Text("You are over the time budget. You may continue; the debrief includes the extra time.", color = MaterialTheme.colorScheme.error)
        }
        SectionLabel(if (deciding) "CONFIRM THE LEADING DIAGNOSIS" else "DIFFERENTIAL LADDER")
        OutlinedTextField(value = first, onValueChange = { first = it }, label = { Text("1 · Leading diagnosis") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
        if (!deciding) {
            OutlinedTextField(value = second, onValueChange = { second = it }, label = { Text("2 · Alternative (optional)") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            OutlinedTextField(value = third, onValueChange = { third = it }, label = { Text("3 · Alternative (optional)") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            WardButton("Make a decision", onClick = { snapshot("decision_started"); deciding = true }, modifier = Modifier.fillMaxWidth(), enabled = first.isNotBlank())
        } else {
            SectionLabel("BEST NEXT STEP")
            file.nextStep.options.forEachIndexed { index, option ->
                Row(Modifier.fillMaxWidth().background(if (index == nextStep) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface, RoundedCornerShape(14.dp)).clickable { nextStep = index }.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = nextStep == index, onClick = { nextStep = index })
                    Text(option, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                }
            }
            OutlinedTextField(value = reason, onValueChange = { reason = it }, label = { Text("Your reasoning (optional)") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
            WardButton("Complete case & debrief", onClick = { snapshot("decision"); finished = true }, modifier = Modifier.fillMaxWidth(), enabled = first.isNotBlank() && nextStep in file.nextStep.options.indices)
            TextButton(onClick = { deciding = false }) { Text("Return to work-up") }
        }
    }
}

@Composable
private fun CaseDebrief(set: StudySet, file: CaseFile, store: StudyStore, taken: Set<String>, diagnosis: String, nextStep: Int, reason: String, history: String) {
    val score = scoreClinicalCase(file, taken, diagnosis, nextStep)
    val missedFlags = file.steps.filter { it.redFlag && it.id !in taken }
    val missedKeys = file.steps.filter { it.value.equals("key", true) && it.id !in taken }
    val missed = (missedFlags + missedKeys).distinctBy { it.id }
    var cardsSaved by rememberSaveable(file.id) { mutableStateOf(false) }
    var ideaSaved by rememberSaveable(file.id) { mutableStateOf(false) }
    if (missedFlags.isNotEmpty()) WardCard {
        Text("Missed red flags", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.error)
        missedFlags.forEach { Text("${it.label}: ${it.finding}", color = MaterialTheme.colorScheme.error) }
        if (score.capped) Text("A must-not-miss red flag was missed. The total is capped at 60.", style = MaterialTheme.typography.bodySmall)
    }
    WardCard {
        Text("${score.total} / 100", style = MaterialTheme.typography.displaySmall, color = MaterialTheme.colorScheme.primary)
        listOf("Diagnosis" to "${score.diagnosis}/30", "Next step" to "${score.nextStep}/20", "Key findings" to "${score.keyFindings}/25", "Red flags" to "${score.redFlags}/15", "Time & efficiency" to "${score.time}/10").forEach { (name, value) ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(name); Text(value, fontWeight = FontWeight.SemiBold) }
        }
    }
    WardCard {
        SectionLabel("DIAGNOSIS")
        Text(file.diagnosis.name, style = MaterialTheme.typography.headlineSmall)
        Text("Your answer: $diagnosis", color = if (score.diagnosis > 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error)
        SectionLabel("NEXT STEP")
        Text(file.nextStep.options.getOrElse(file.nextStep.key) { "No answer supplied" }, style = MaterialTheme.typography.titleMedium)
        Text("Your answer: ${file.nextStep.options.getOrElse(nextStep) { "Not selected" }}", color = if (score.nextStep > 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error)
        Text(file.nextStep.why)
        if (reason.isNotBlank()) Text("Your reasoning: $reason", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    val keySteps = file.steps.filter { it.value.equals("key", true) }
    SectionLabel("KEY FINDINGS · ${keySteps.count { it.id in taken }} OF ${keySteps.size}")
    keySteps.forEach { step ->
        WardCard {
            Text(if (step.id in taken) "Found · ${step.label}" else "Missed · ${step.label}", style = MaterialTheme.typography.titleMedium, color = if (step.id in taken) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error)
            Text(step.finding)
        }
    }
    file.steps.firstOrNull { it.id == file.turningStep }?.let { turning ->
        WardCard {
            SectionLabel("THE TURNING POINT")
            Text(turning.label, style = MaterialTheme.typography.titleMedium)
            Text(turning.finding)
            val events = runCatching { JSONArray(history) }.getOrDefault(JSONArray())
            val leading = (0 until events.length()).mapNotNull { index -> events.optJSONObject(index) }.firstOrNull { event -> diagnosisMatches(event.optJSONArray("ladder")?.optString(0).orEmpty(), file) }
            Text(if (leading == null) "The accepted diagnosis did not lead your ladder during this run." else "The accepted diagnosis was first recorded at the top of your ladder at ${leading.optInt("minutes")} minutes.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    val low = file.steps.filter { it.id in taken && it.value.equals("low", true) }
    if (low.isNotEmpty()) WardCard {
        SectionLabel("LOW-YIELD ACTIONS")
        low.forEach { Text("${it.label} · ${it.minutes} min${if (it.note.isNotBlank()) "\n${it.note}" else ""}") }
    }
    if (file.teaching.isNotEmpty()) WardCard {
        SectionLabel("TEACHING POINTS")
        file.teaching.forEachIndexed { index, point -> Text("${index + 1}. $point") }
        val source = listOf(file.source.lecture, file.source.pages).filter { it.isNotBlank() }.joinToString(" · ")
        if (source.isNotBlank()) Text(source, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (missed.isNotEmpty()) WardButton(if (cardsSaved) "${missed.size} cards saved to your library" else "Make cards from what I missed", onClick = {
        val source = listOf(file.source.lecture, file.source.pages).filter { it.isNotBlank() }.joinToString(" · ")
        val cards = missed.map { step -> AnkiCard(front = "${file.diagnosis.name}: what does ${step.label.lowercase()} show in this case?", bullets = listOf(step.finding), source = source.ifBlank { null }, tags = listOf("case-review")) }
        store.addSet(StudySet(name = "${file.title.ifBlank { file.diagnosis.name }} · missed findings", subject = set.subject, kind = StudySetKind.ANKI, cards = cards, sources = set.sources, tags = listOf("case-review")))
        cardsSaved = true
    }, modifier = Modifier.fillMaxWidth(), enabled = !cardsSaved)
    OutlinedButton(onClick = {
        val body = buildString {
            appendLine(file.diagnosis.name)
            appendLine("Decision: ${file.nextStep.options.getOrElse(file.nextStep.key) { "" }}")
            appendLine(file.nextStep.why)
            if (missed.isNotEmpty()) { appendLine("\nFindings to revisit"); missed.forEach { appendLine("• ${it.label}: ${it.finding}") } }
            if (file.teaching.isNotEmpty()) { appendLine("\nTeaching points"); file.teaching.forEach { appendLine("• $it") } }
            appendLine("\nSource: ${file.source.lecture} ${file.source.pages}")
            appendLine("Verification: ${file.verification}")
        }
        store.saveNote(Note(title = file.title.ifBlank { file.diagnosis.name }, body = body, tags = listOf("case-review", set.subject)))
        ideaSaved = true
    }, modifier = Modifier.fillMaxWidth(), enabled = !ideaSaved) { Text(if (ideaSaved) "Saved to Ideas" else "Add to Ideas") }
}
