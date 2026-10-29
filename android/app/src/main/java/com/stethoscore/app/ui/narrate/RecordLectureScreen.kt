package com.stethoscore.app.ui.narrate

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.FiberManualRecord
import androidx.compose.material.icons.rounded.MicOff
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.stethoscore.app.R
import com.stethoscore.app.audio.LectureAudio
import com.stethoscore.app.audio.LectureLanguage
import com.stethoscore.app.audio.LectureRecorder
import com.stethoscore.app.audio.MicAsk
import com.stethoscore.app.audio.MicPermission
import com.stethoscore.app.audio.PermissionGate
import com.stethoscore.app.audio.RecordFlow
import com.stethoscore.app.audio.RecorderNames
import com.stethoscore.app.audio.RecorderState
import com.stethoscore.app.audio.RecordingSave
import com.stethoscore.app.audio.RecordingService
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.exam.ExamSheet
import com.stethoscore.app.ui.mock.ConfirmChoice
import com.stethoscore.app.ui.mock.ConfirmSheet
import com.stethoscore.app.ui.sources.ReaderBackButton
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File

/**
 * Record a lecture in the app (T0146 item 5; iOS RecordLectureView), from
 * New set's lecture choices and the Narrate screen.
 *
 * The elapsed time, a level meter, and Pause/Resume and Stop in the study
 * bar. The microphone is asked for only from the Record tap here: the plain
 * sheet first, then RECORD_AUDIO, then POST_NOTIFICATIONS for the ongoing
 * notification; refused for good, a row with Open Settings. On Stop the
 * student chooses an existing lecture set or a new one named for when the
 * recording began ("Lecture, 23 Oct 14:05"), and the file is saved there on
 * this phone, nothing sent (RecordingSave, LectureImporter.storeRecorded).
 * Cancel keeps it, with Save the recording in the bar. Transcribe on the
 * Saved banner is the one way it is sent to Gemini; [handOff] lets the
 * Narrate screen transcribe its own set itself. A recording the app was
 * killed during is offered to keep or delete.
 */
@Composable fun RecordLectureScreen(
    store: StudyStore,
    onClose: () -> Unit,
    preferred: StudySet? = null,
    onSaved: (StudySet) -> Unit = {},
    /** Transcribe tapped for a saved recording: true when the opener transcribes it itself (this screen then closes). */
    handOff: ((File, StudySet) -> Boolean)? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val recorder = remember { LectureRecorder.shared(context) }
    val importer = remember { LectureImporter.forApp() }
    val learned = remember { PronunciationLibrary.shared(context) }
    val lectures = remember { LectureAudio.folder(context.noBackupFilesDir) }

    var state by remember { mutableStateOf(recorder.state) }
    var level by remember { mutableDoubleStateOf(0.0) }
    var seconds by remember { mutableDoubleStateOf(recorder.elapsed()) }
    var save by remember { mutableStateOf(RecordingSave()) }
    var recovered by remember { mutableStateOf(recorder.recovered) }
    // the recording found at launch is trimmed off the main thread, then offered
    LaunchedEffect(recorder) { recovered = recorder.recoverLeftover() }
    var showingSheet by remember { mutableStateOf(false) }
    var micOff by remember { mutableStateOf(false) }
    var savedTo by remember { mutableStateOf<StudySet?>(null) }

    // the recorder's moves, and a stopped recording handed here; one not yet saved waits for the next opening
    DisposableEffect(recorder) {
        val stop = recorder.listen { state = it; seconds = recorder.elapsed() }
        LectureRecorder.handOff = { save = save.offer(it) }
        LectureRecorder.pending?.let { save = save.offer(it); LectureRecorder.pending = null }
        onDispose {
            stop(); LectureRecorder.handOff = null
            save.file?.let { LectureRecorder.pending = it }
        }
    }
    // the clock and the meter, ten times a second while a recording is open
    LaunchedEffect(state) {
        while (state.isActive) {
            seconds = recorder.elapsed()
            level = recorder.level()
            delay(100)
        }
        level = 0.0
    }
    DisposableEffect(Unit) { importer.onScreen = false; onDispose { } }

    // the microphone, then the notification; asked from the Record tap only
    // "refused for good" is kept only when the system said no and stopped offering a rationale (MicAsk)
    val asked = remember { context.getSharedPreferences("recorder", Context.MODE_PRIVATE) }
    var answer by remember { mutableStateOf<CompletableDeferred<Boolean>?>(null) }
    val askMic = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> answer?.complete(granted) }
    val askNotifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { RecordingService.start(context) }
    val gate = remember {
        object : PermissionGate {
            fun rationale(): Boolean = context.activity()?.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) == true
            override val status: MicPermission get() {
                val granted = context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                val rationale = rationale()
                val kept = asked.getBoolean(REFUSED_KEY, false)
                // a grant or a rationale since clears the refusal, so a later revoke is asked again
                val refused = MicAsk.stillRefused(granted, rationale, kept)
                if (refused != kept) asked.edit().putBoolean(REFUSED_KEY, refused).apply()
                return MicAsk.status(granted, rationale, refused)
            }
            override suspend fun request(): Boolean {
                val waiting = CompletableDeferred<Boolean>()
                answer = waiting
                askMic.launch(Manifest.permission.RECORD_AUDIO)
                val granted = waiting.await()
                asked.edit().putBoolean(REFUSED_KEY, MicAsk.refusedForGood(granted, rationale())).apply()
                return granted
            }
        }
    }
    val flow = remember { RecordFlow(gate) }
    fun begin() {
        micOff = false
        savedTo = null
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        else RecordingService.start(context)
    }
    fun tapRecord() {
        when (flow.tapRecord()) {
            RecordFlow.Step.sheet -> showingSheet = true
            RecordFlow.Step.record -> begin()
            RecordFlow.Step.settingsRow -> micOff = true
        }
    }

    val language = context.resources.configuration.locales[0].language
    // named for when the recording began, read from its file name as iOS does
    val newTitle = RecorderNames.defaultTitle(save.file?.let { RecorderNames.moment(it.name) } ?: recorder.moment, language)
    /**
     * Saving only saves: the file goes under the set on this phone, and
     * nothing is sent. A new set is added only once the copy is made; while
     * it is copying, Save the recording waits.
     */
    fun handOn(chosen: StudySet?) {
        save = save.begin() ?: return
        val set = chosen ?: StudySet(name = newTitle, subject = "Lectures", kind = StudySetKind.NARRATE)
        scope.launch {
            save = save.save(set.id) { file, id -> importer.storeRecorded(file, id, lectures) }
            if (save.kept == null) return@launch
            if (chosen == null) store.addSet(set)
            recorder.handedOn()
            savedTo = set
            onSaved(set)
        }
    }
    /** Transcribe, the student's own action on a saved recording: the one way it is sent to Gemini. */
    fun transcribe() {
        val kept = save.kept ?: return
        val set = savedTo ?: return
        if (handOff?.invoke(kept, set) == true) { onClose(); return }
        importer.keep = { made, spoken ->
            store.library.firstOrNull { it.id == set.id }?.let { store.updateSet(it.copy(narrateSegments = made, lectureLanguage = spoken.rawValue)) }
        }
        save = RecordingSave()
        scope.launch { importer.transcribe(kept, LectureImporter.Engine.cloud, LectureLanguage.mixed) { learned.applyLearned(it) } }
    }

    ExamSheet(onDismiss = { if (!state.isActive) onClose() }) {
        Column(Modifier.fillMaxSize()) {
            ReaderNavBar(stringResource(R.string.recorder_title), leading = { if (!state.isActive) ReaderBackButton(onClose) })
            Column(Modifier.weight(1f).fillMaxWidth().padding(horizontal = WardSpace.gutter.wardDp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(WardSpace.l.wardDp, Alignment.CenterVertically)) {
                val line = stateLine(state)
                Text(RecorderNames.clock(seconds), style = WardTextStyle.largeTitle.textStyle(), fontFamily = FontFamily.Monospace,
                    color = wardColor(WardToken.ink), modifier = Modifier.semantics { contentDescription = line + ", " + RecorderNames.clock(seconds) })
                Text(line, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
                WardGroove(level, wardColor(WardToken.primaryInk), Modifier.fillMaxWidth().clearAndSetSemantics { })
                if (micOff) WardBanner(stringResource(R.string.recorder_mic_off), Icons.Rounded.MicOff, WardTone.Danger,
                    actionTitle = stringResource(R.string.recorder_open_settings)) {
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                }
                recorder.note?.let { WardBanner(stringResource(R.string.recorder_low_disk)) }
                val working = importer.working
                val saved = savedTo
                if (working != null) TranscribingBanner(working, onDevice = !importer.inCloud)
                else if (saved != null && save.kept != null) WardBanner(stringResource(R.string.recorder_saved_to, saved.name), Icons.Rounded.CheckCircle,
                    WardTone.Green, actionTitle = stringResource(R.string.recorder_transcribe)) { transcribe() }
                else if (saved != null) WardBanner(stringResource(R.string.recorder_saved_to, saved.name), Icons.Rounded.CheckCircle, WardTone.Green)
            }
            StudyActionBar {
                when (state) {
                    is RecorderState.Recording, is RecorderState.Paused -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
                        val recording = state.isRecording
                        WardButtonBox({ RecordingService.send(context, if (recording) RecordingService.ACTION_PAUSE else RecordingService.ACTION_RESUME) },
                            Modifier.weight(1f), kind = WardButtonKind.primary) {
                            Icon(if (recording) Icons.Rounded.Pause else Icons.Rounded.FiberManualRecord, null, Modifier.size(20.dp))
                            Text(stringResource(if (recording) R.string.recorder_pause else R.string.recorder_resume), maxLines = 1)
                        }
                        WardButtonBox({ RecordingService.send(context, RecordingService.ACTION_STOP) }, Modifier.weight(1f), kind = WardButtonKind.secondary) {
                            Icon(Icons.Rounded.Stop, null, Modifier.size(20.dp))
                            Text(stringResource(R.string.recorder_stop), maxLines = 1)
                        }
                    }
                    // a cancelled choice keeps the recording: saving it again is the bar's one button
                    else -> if (save.waiting) WardButtonBox({ save = save.reopen() }, kind = WardButtonKind.primary, enabled = save.canSave) {
                        Icon(Icons.Rounded.CheckCircle, null, Modifier.size(20.dp))
                        Text(stringResource(R.string.recorder_save_again), maxLines = 1)
                    } else if (state == RecorderState.Saving) Unit
                    else WardButtonBox(::tapRecord, kind = WardButtonKind.primary, enabled = importer.working == null) {
                        Icon(Icons.Rounded.FiberManualRecord, null, Modifier.size(20.dp))
                        Text(stringResource(R.string.recorder_start), maxLines = 1)
                    }
                }
            }
        }
    }

    if (showingSheet) ConfirmSheet(stringResource(R.string.recorder_sheet_title), stringResource(R.string.recorder_sheet_body),
        listOf(ConfirmChoice(stringResource(R.string.recorder_continue), destructive = false) {
            scope.launch { if (flow.continueFromSheet() == RecordFlow.Step.record) begin() else micOff = true }
        }), cancelTitle = stringResource(R.string.recorder_cancel), onDismiss = { showingSheet = false })

    val failure = importer.trouble ?: (state as? RecorderState.Failed)?.let {
        stringResource(R.string.recorder_failed, RecordingService.failedWord(it.reason)?.let { word -> stringResource(word) } ?: it.reason)
    }

    if (save.choosing && failure == null) {
        val sets = store.library.filter { it.kind == StudySetKind.NARRATE }.sortedBy { if (it.id == preferred?.id) 0 else 1 }
        ConfirmSheet(stringResource(R.string.recorder_save_to), stringResource(R.string.recorder_save_body),
            sets.map { set -> ConfirmChoice(set.name, destructive = false) { handOn(set) } } +
                ConfirmChoice(stringResource(R.string.recorder_new_set, newTitle), destructive = false) { handOn(null) },
            // the recording is kept: Save the recording in the bar opens this again
            cancelTitle = stringResource(R.string.recorder_cancel), onDismiss = { save = save.cancel() })
    }

    // a recording the app was killed during: keep it (then choose its set) or delete it
    recovered?.let { left ->
        fun done() { recovered = null; recorder.recovered = null }
        ConfirmSheet(stringResource(R.string.recorder_recover_title), stringResource(R.string.recorder_recover_body),
            listOf(ConfirmChoice(stringResource(R.string.recorder_keep), destructive = false) { done(); save = save.offer(left) },
                ConfirmChoice(stringResource(R.string.recorder_discard), destructive = true) { done(); left.delete() }),
            cancelTitle = stringResource(R.string.recorder_cancel), onDismiss = { recovered = null })
    }

    failure?.let { message ->
        AlertDialog(onDismissRequest = { importer.trouble = null; recorder.clearFailure() }, containerColor = wardColor(WardToken.raised),
            title = { Text(stringResource(R.string.recorder_failed_title), style = WardType.headline.textStyle(), color = wardColor(WardToken.ink)) },
            text = { Text(message, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary)) },
            confirmButton = { WardTextButton(stringResource(R.string.recorder_done), { importer.trouble = null; recorder.clearFailure() },
                kind = WardButtonKind.compact, fills = false) })
    }
}

private const val REFUSED_KEY = "mic.refusedForGood"

/** The activity behind a Compose context, for shouldShowRequestPermissionRationale. */
private tailrec fun Context.activity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.activity()
    else -> null
}

@Composable private fun stateLine(state: RecorderState): String = when (state) {
    is RecorderState.Recording -> stringResource(R.string.recorder_recording)
    is RecorderState.Paused -> stringResource(RecordingService.pausedWord(state.reason))
    RecorderState.Saving -> stringResource(R.string.recorder_saving)
    else -> stringResource(R.string.recorder_title)
}
