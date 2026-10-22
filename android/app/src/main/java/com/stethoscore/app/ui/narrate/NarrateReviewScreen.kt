package com.stethoscore.app.ui.narrate

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.*
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.stethoscore.app.audio.AudioChapters
import com.stethoscore.app.audio.AudioRate
import com.stethoscore.app.audio.CorrectionOutcome
import com.stethoscore.app.audio.LectureAudio
import com.stethoscore.app.audio.LectureLanguage
import com.stethoscore.app.audio.NarratePlan
import com.stethoscore.app.audio.WordTiming
import com.stethoscore.app.audio.measured
import com.stethoscore.app.data.NarrateScheduler
import com.stethoscore.app.data.NarrateSegment
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.home.HomeBrand
import com.stethoscore.app.ui.mock.ConfirmChoice
import com.stethoscore.app.ui.mock.ConfirmSheet
import com.stethoscore.app.ui.sources.*
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.launch
import java.io.File
import java.io.IOException

// A port of ios/RedPen/Features/Narrate/NarrateReviewView.swift (fed0105),
// with NarrateListening.swift and NarrateReading.swift: the Narrate player, in
// its two states. With a recording attached it follows the audio: the
// recogniser's word times decide which word is lit and the clock is the
// audio's position. With no recording the lecture is read aloud by the
// phone's voice and the word being said is lit.
//
// The transcript is editable either way: hold a word, say what it should have
// been, and the fix spreads to everything that sounds the same and is
// remembered for next time.
//
// Not here, for want of the feature on Android: the Guess first questions
// before a first reading (batch 14), the lock screen's controls (NowPlaying),
// iOS's natural cloud voice, and Gemini or on-device transcription, which
// both say they are not set up on this phone.

/** The words the screen says, kept apart from the view so they can be checked. */
object NarrateWords {
    fun title(subject: String): String = subject.ifEmpty { "Narrate" }

    /** "Line 3 of 40", by line rather than by the audio clock. */
    fun status(index: Int, total: Int): String = "Line ${minOf(index + 1, maxOf(total, 1))} of $total"

    fun fraction(index: Int, finished: Boolean, total: Int): Double =
        (if (total > 0) (index + if (finished) 1 else 0).toDouble() / total else 0.0).coerceIn(0.0, 1.0)

    fun detail(hasAudio: Boolean, waiting: Boolean): String = when {
        hasAudio -> "Following the recording · hold a word to fix it"
        waiting -> "Getting the voice ready…"
        else -> "Tap a line to read from it · hold a word to fix it"
    }

    const val emptyTitle = "Nothing to read yet"

    /** Where to go from an empty transcript. */
    fun emptyLine(transcribing: Boolean, hasAudio: Boolean): String = when {
        transcribing -> "Your recording is being transcribed. The transcript appears here when it's ready."
        hasAudio -> "This transcript is empty. Replace the recording from More."
        else -> "This transcript is empty. Tap Add audio below to add a recording of the lecture."
    }

    fun recordingItem(hasAudio: Boolean): String = if (hasAudio) "Replace recording" else "Add recording"

    const val engineTitle = "Transcribe the recording with"
    val engineMessage: String = "Gemini is part of Pro and runs on Google's servers: the audio goes through ${HomeBrand.name} to Google " +
        "to transcribe, and while ${HomeBrand.name} uses Google's free service Google may use it to improve its models. Only send " +
        "lectures you're allowed to record. On this phone, nothing leaves the device, but mixed Arabic and English comes out far less accurate."
    val engines: List<Pair<String, Pair<LectureImporter.Engine, LectureLanguage>>> = listOf(
        "Gemini (Pro) — Arabic + English lecture" to (LectureImporter.Engine.cloud to LectureLanguage.mixed),
        "Gemini (Pro) — English-only lecture" to (LectureImporter.Engine.cloud to LectureLanguage.english),
        "This phone only — Arabic + English, offline" to (LectureImporter.Engine.device to LectureLanguage.mixed),
        "This phone only — English, offline" to (LectureImporter.Engine.device to LectureLanguage.english),
    )
    const val troubleTitle = "Couldn't use that recording"
    const val noticeTitle = "Transcribed"
}

@Composable fun NarrateReviewScreen(set: StudySet, store: StudyStore, onBack: () -> Unit, importOnOpen: Boolean = false) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val learned = remember { PronunciationLibrary.shared(context) }
    val memory = remember { PreferencesRateMemory(context) }
    val lectures = remember { LectureAudio.folder(context.noBackupFilesDir) }
    val player = remember { LecturePlayer() }
    val voice = remember { NarrateVoice(context) }
    val sleep = remember { SleepTimer() }
    val importer = remember { LectureImporter() }
    val title = NarrateWords.title(set.subject)

    var index by remember { mutableIntStateOf(0) }
    var playing by remember { mutableStateOf(false) }
    var finished by remember { mutableStateOf(false) }
    var speed by remember { mutableDoubleStateOf(1.0) }
    var segments by remember { mutableStateOf<List<NarrateSegment>>(emptyList()) }
    var texts by remember { mutableStateOf<List<String>>(emptyList()) }
    var fixing by remember { mutableStateOf<FixTarget?>(null) }
    var report by remember { mutableStateOf<String?>(null) }
    var lastOutcome by remember { mutableStateOf<CorrectionOutcome?>(null) }
    var snapshot by remember { mutableStateOf<List<String>>(emptyList()) }
    var choosingEngine by remember { mutableStateOf(false) }
    var madeHere by remember { mutableStateOf(false) }
    var engine by remember { mutableStateOf(LectureImporter.Engine.cloud) }
    var language by remember { mutableStateOf(LectureLanguage.mixed) }
    var moreOpen by remember { mutableStateOf(false) }

    fun current(): StudySet = store.library.firstOrNull { it.id == set.id } ?: set

    /** The word timeline and the text to read, worked out once whenever the transcript changes. */
    fun relayout() {
        voice.load(texts, segments.map { it.lang })
        val made = AudioChapters.derive(texts, segments.map { it.start }, segments.map { it.end })
        voice.useChapters(made)
        player.useChapters(made)
        val measured = NarrateScheduler.measured(segments)
        player.setTimeline(if (measured == null) emptyList() else WordTiming.layout(texts, segments.map { it.end ?: 0.0 }, measured))
    }

    fun loadRecording() {
        LectureAudio.existing(set.id, lectures)?.let { player.load(it) }
    }

    fun speedChosen(now: Double) {
        voice.chooseSpeed(now)
        player.chooseRate(now)
        if (AudioRate.remembered(set.id, memory) != now) AudioRate.remember(now, set.id, memory)
    }

    /** A correction is an edit to the transcript, so it outlives the screen. */
    fun persistText() {
        if (texts.size != segments.size) return
        segments = segments.mapIndexed { i, s -> s.copy(text = texts[i]) }
        store.updateSet(current().copy(narrateSegments = segments))
    }

    /** A freshly transcribed lecture replaces the typed transcript, and is saved. */
    fun adopt(made: List<NarrateSegment>) {
        segments = made
        texts = made.map { it.text }
        index = 0
        store.updateSet(current().copy(narrateSegments = made, lectureLanguage = language.rawValue))
        voice.stop()
        loadRecording()
        relayout()
        importer.produced = null
    }

    // MARK: reading (NarrateReading)

    fun play() {
        if (segments.isEmpty()) return
        if (finished) { index = 0; finished = false }
        playing = true
        if (voice.spot.line == index) voice.resume() else voice.play(index)
    }

    fun pause() {
        playing = false
        voice.pause()
    }

    /** Tapping a line means "take me there" in both states. */
    fun jump(to: Int) {
        if (segments.isEmpty()) return
        index = to.coerceIn(0, segments.size - 1)
        if (player.hasAudio) {
            segments[index].start?.let { player.seek(it) }
            return
        }
        finished = false
        voice.jump(index)
    }

    fun restart() {
        index = 0
        finished = false
        playing = false
        voice.jump(0)
    }

    // MARK: fixing a word

    fun fix(target: FixTarget, spelling: String) {
        val before = texts
        val edited = texts.toMutableList()
        val outcome = learned.fix(target.segment, target.word, spelling, edited)
        if (outcome.here == null) return
        snapshot = before
        texts = edited
        lastOutcome = outcome
        persistText()
        relayout()
        report = outcome.summary()
    }

    fun undo() {
        val outcome = lastOutcome ?: return
        val edited = texts.toMutableList()
        learned.undo(snapshot, edited, outcome)
        texts = edited
        lastOutcome = null
        persistText()
        relayout()
        report = null
    }

    // MARK: setting up and going

    LaunchedEffect(set.id) {
        if (importOnOpen) { madeHere = true; choosingEngine = true }
        if (segments.isNotEmpty()) return@LaunchedEffect
        segments = set.narrateSegments
        texts = set.narrateSegments.map { it.text }.toMutableList().also { learned.applyLearned(it) }
        val kept = AudioRate.remembered(set.id, memory)
        speed = kept
        voice.chooseSpeed(kept)
        player.chooseRate(kept)
        relayout()
        loadRecording()
    }
    DisposableEffect(set.id) {
        importer.onScreen = true
        onDispose {
            importer.onScreen = false
            sleep.cancel()
            voice.release()
            player.stop()
            // the audio tile's lecture, left with nothing in it, goes with the screen
            val now = store.library.firstOrNull { it.id == set.id }
            if (now != null && NarratePlan.dropsEmptyLecture(madeHere, now.narrateSegments.size,
                    LectureAudio.existing(set.id, lectures) != null, importer.working != null)) store.deleteSet(set.id)
        }
    }
    // the timer stops whichever is playing; adding a recording moves it
    LaunchedEffect(player.hasAudio) { sleep.attach(if (player.hasAudio) player else voice) }
    // the audio is the clock, so the current line follows it
    LaunchedEffect(player.spot) { player.spot?.line?.let { if (it != index) index = it } }
    LaunchedEffect(voice.spot) { if (!player.hasAudio && voice.spot.line != index) index = voice.spot.line }
    LaunchedEffect(voice.playing) { playing = voice.playing }
    LaunchedEffect(voice.finished) { finished = voice.finished }
    LaunchedEffect(importer.produced) { importer.produced?.let { adopt(it) } }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        importer.keep = { made, spoken ->
            // the screen has gone: the transcript still lands on the set
            store.library.firstOrNull { it.id == set.id }?.let { store.updateSet(it.copy(narrateSegments = made, lectureLanguage = spoken.rawValue)) }
        }
        val chosenEngine = engine
        val chosenLanguage = language
        scope.launch {
            val kept = importer.attach({ context.contentResolver.openInputStream(uri) ?: throw IOException("The recording could not be opened.") },
                extensionOf(context, uri), set.id, lectures, chosenEngine, chosenLanguage) { learned.applyLearned(it) }
            // the recording is kept even with no transcript, so it can be played (iOS shows it on the next opening)
            if (kept != null && importer.produced == null && !player.hasAudio) loadRecording()
        }
    }

    val hasAudio = player.hasAudio
    val sections = if (hasAudio) player.chapters else voice.chapters
    val currentSection = if (hasAudio) player.section else AudioChapters.indexContainingLine(index, voice.chapters)
    val addAudio: (() -> Unit)? = if (importer.working == null) ({ choosingEngine = true }) else null
    val listState = rememberLazyListState()
    var viewport by remember { mutableIntStateOf(0) }
    var handsOffUntil by remember { mutableLongStateOf(0L) }
    LaunchedEffect(listState) {
        // the student's own scrolling wins for a few seconds
        listState.interactionSource.interactions.collect {
            if (it is DragInteraction.Start || it is DragInteraction.Stop || it is DragInteraction.Cancel)
                handsOffUntil = System.currentTimeMillis() + NarrateScrollBand.handsOffMillis
        }
    }
    LaunchedEffect(index) {
        val (top, bottom) = NarrateScrollBand.frame(listState, index)
        if (texts.isNotEmpty() && NarrateScrollBand.needsScroll(top, bottom, viewport, System.currentTimeMillis(), handsOffUntil))
            listState.animateScrollToItem(index, -(viewport * NarrateScrollBand.anchor).toInt())
    }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    Column(Modifier.fillMaxSize().focusRequester(focus).focusable().onPreviewKeyEvent { e ->
        if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
        when (e.key) {
            Key.Spacebar -> { if (hasAudio) player.toggle() else if (finished) restart() else if (playing) pause() else play(); true }
            Key.DirectionLeft -> if (hasAudio) { player.skip(-NarrateSkip.back); true } else false
            Key.DirectionRight -> if (hasAudio) { player.skip(NarrateSkip.forward); true } else false
            else -> false
        }
    }) {
        ReaderNavBar(title, leading = { ReaderBackButton(onBack) }, trailing = {
            Box {
                WardCircleButton(Icons.Rounded.MoreHoriz, "More", { moreOpen = true })
                DropdownMenu(moreOpen, { moreOpen = false }, containerColor = wardColor(WardToken.raised)) {
                    DropdownMenuItem(text = { Text(NarrateWords.recordingItem(hasAudio)) }, leadingIcon = { Icon(Icons.Rounded.GraphicEq, null) },
                        onClick = { moreOpen = false; choosingEngine = true })
                }
            }
        })
        StudyProgressHeader(NarrateWords.status(index, segments.size), NarrateWords.detail(hasAudio, voice.waiting),
            NarrateWords.fraction(index, finished, segments.size))
        importer.working?.let { TranscribingBanner(it, onDevice = !importer.inCloud) }
        Box(Modifier.weight(1f).fillMaxWidth().onSizeChanged { viewport = it.height }) {
            if (texts.isEmpty()) {
                ReaderEmptyState(Icons.Rounded.GraphicEq, NarrateWords.emptyTitle,
                    NarrateWords.emptyLine(importer.working != null, hasAudio), modifier = Modifier.padding(top = 32.dp))
            } else {
                TranscriptCard(listState)
                // the word being said in the current line, from whichever is playing
                val spoken = (if (hasAudio) player.spot else voice.spot)?.takeIf { it.line == index }?.word
                val looks = narrateLineLooks(texts, segments.map { it.lang }, index, spoken, fixing)
                LazyColumn(Modifier.fillMaxSize(), state = listState,
                    contentPadding = PaddingValues(start = 40.dp, end = 40.dp, top = 32.dp, bottom = 48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    itemsIndexed(looks, key = { i, _ -> i }) { _, look ->
                        Box(Modifier.widthIn(max = 652.dp).fillMaxWidth()) {
                            NarrateLine(look, onJump = { jump(it) }, onFix = { fixing = it })
                        }
                    }
                }
            }
            // what a correction did, just above the bar, until undone or replaced
            report?.let { FixReport(it, { undo() }, Modifier.align(Alignment.BottomCenter).widthIn(max = 560.dp).padding(bottom = 8.dp)) }
        }
        StudyActionBar(folds = true) {
            if (texts.isNotEmpty() || hasAudio) NarrateListenRow(sections, currentSection, sleep,
                onPrevious = { if (hasAudio) player.previousSection() else voice.previousSection() },
                onNext = { if (hasAudio) player.nextSection() else voice.nextSection() },
                onPick = { if (hasAudio) player.jumpToSection(it) else voice.jumpToSection(it) })
            if (hasAudio) NarrateAudioBar(player, speed) { speed = it; speedChosen(it) }
            else NarrateReadingControls(speed, { speed = it; speedChosen(it) }, playing, finished, canPlay = segments.isNotEmpty(),
                isEmpty = texts.isEmpty(), onPlayPause = { if (playing) pause() else play() }, onRestart = { restart() }, onAddAudio = addAudio)
        }
    }

    fixing?.let { target -> FixWordSheet(target, onSave = { fix(target, it) }, onDismiss = { fixing = null }) }
    if (choosingEngine) ConfirmSheet(NarrateWords.engineTitle, NarrateWords.engineMessage,
        NarrateWords.engines.map { (words, how) ->
            ConfirmChoice(words, destructive = false) {
                engine = how.first
                language = how.second
                picker.launch(arrayOf("audio/*"))
            }
        }, cancelTitle = "Cancel", onDismiss = { choosingEngine = false })
    importer.trouble?.let { NarrateAlert(NarrateWords.troubleTitle, it) { importer.trouble = null } }
    if (importer.trouble == null) importer.notice?.let { NarrateAlert(NarrateWords.noticeTitle, it) { importer.notice = null } }
}

/**
 * The reading card behind the transcript (contentCard): one card that scrolls
 * with the lines, drawn from where the first line is to where the last one
 * ends, so the list can stay lazy.
 */
@Composable private fun TranscriptCard(state: androidx.compose.foundation.lazy.LazyListState) {
    val density = LocalDensity.current
    val pad = with(density) { WardSpace.xl.wardDp.roundToPx() }
    val bounds by remember(state) {
        derivedStateOf {
            val info = state.layoutInfo
            val items = info.visibleItemsInfo
            val first = items.firstOrNull()
            val last = items.lastOrNull()
            val height = info.viewportEndOffset - info.viewportStartOffset
            val top = if (first != null && first.index == 0) first.offset - info.viewportStartOffset - pad else -4 * pad
            val bottom = if (last != null && last.index == info.totalItemsCount - 1) last.offset + last.size - info.viewportStartOffset + pad
                else height + 4 * pad
            top to bottom
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val width = minOf(maxWidth - 32.dp, 700.dp)
        val (top, bottom) = bounds
        val tall = with(density) { maxOf(0, bottom - top).toDp() }
        Box(Modifier.align(Alignment.TopCenter).offset { IntOffset(0, top) }.width(width).height(tall)
            .wardRaised(WardRadius.card, WardLift.mid))
    }
}

@Composable private fun NarrateAlert(title: String, message: String, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, containerColor = wardColor(WardToken.raised),
        title = { Text(title, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink)) },
        text = { Text(message, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary)) },
        confirmButton = { WardTextButton("Done", onDismiss, kind = WardButtonKind.compact, fills = false) })
}

/** The picked file's extension, so the player can work out the format: from its name, else its type, else m4a. */
private fun extensionOf(context: Context, uri: Uri): String {
    val named = runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    }.getOrNull()
    val fromName = named?.substringAfterLast('.', "")?.takeIf { it.isNotEmpty() && it.length <= 5 }
    if (fromName != null) return fromName
    val type = runCatching { context.contentResolver.getType(uri) }.getOrNull()
    return type?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) } ?: File(uri.path ?: "").extension.ifEmpty { "m4a" }
}
