package com.stethoscore.app.ui.cases

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.NoteAdd
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.CaseChecks
import com.stethoscore.app.data.CaseMaker
import com.stethoscore.app.data.CaseWriting
import com.stethoscore.app.data.LectureForms
import com.stethoscore.app.data.ReadSource
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.llm.LLMChoice
import com.stethoscore.app.ui.editors.CountField
import com.stethoscore.app.ui.editors.EcgLoader
import com.stethoscore.app.ui.ward.WardBanner
import com.stethoscore.app.ui.editors.EditorNote
import com.stethoscore.app.ui.editors.EditorSection
import com.stethoscore.app.ui.editors.LectureFiles
import com.stethoscore.app.ui.editors.LectureStep
import com.stethoscore.app.ui.editors.MoreOptions
import com.stethoscore.app.ui.editors.rememberLLMService
import com.stethoscore.app.ui.modeIcon
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardTextField
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// A port of ios/RedPen/Features/Cases/CaseMakeSection.swift: New set, for
// Cases. The lecture in step 2, how many patients and Make in step 3. The
// cases are written, checked and saved as a set in one go (a case is not a
// draft to edit line by line), and the lecture goes with the set, so the
// teaching points can be checked against it.
//
// iOS writes with the writer CaseMaker finds; Android's one writer is
// Stethoscore Cloud, chosen in Settings > AI models (LLMService), and the
// server writes every patient as one job. With no writer, Make says why in
// CaseMaker.noWriter's words: Pro, signing in or the spend cap, as the
// debrief's "Another patient like this" does. iOS's progress card
// (GenerationHUD) is not on Android, so the count shows under the button
// with a Cancel, as in MCQGenerateForm. A set turned into cases (iOS
// presetText) has no way here yet.

@Composable fun CaseMakeSection(
    subject: String,
    onSubject: (String) -> Unit,
    name: String,
    step: LectureStep,
    onMade: (StudySet) -> Unit,
) {
    val context = LocalContext.current
    val llm = rememberLLMService()
    val scope = rememberCoroutineScope()
    var read by remember { mutableStateOf<ReadSource?>(null) }
    var reading by remember { mutableStateOf(false) }
    var task by remember { mutableStateOf<Job?>(null) }
    var status by remember { mutableStateOf<String?>(null) }
    var trouble by remember { mutableStateOf<String?>(null) }
    var caseCount by rememberSaveable { mutableIntStateOf(3) }
    var showMore by rememberSaveable { mutableStateOf(false) }
    val working = reading || task != null
    val sourceText = read?.let { lecture -> CaseMaker.sourceText(lecture.pages.map { it.number to it.text }) }.orEmpty()
    val sourceName = read?.name.orEmpty()
    val canMake = !working && LectureForms.hasSource(sourceText)
    val makeTitle = "Make $caseCount patient" + if (caseCount == 1) "" else "s"

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        trouble = null
        if (uri == null) return@rememberLauncherForActivityResult
        reading = true
        status = "Reading…"
        scope.launch {
            try {
                val file = withContext(Dispatchers.IO) { LectureFiles.read(context, uri) }
                val lecture = ReadSource(name = file.name, pages = file.pages, kind = LectureForms.writerFileKind(file.extension))
                read = lecture
                status = "${file.name} — ${file.pages.size} pages."
                if (!LectureForms.hasSource(CaseMaker.sourceText(file.pages.map { it.number to it.text }))) {
                    trouble = "There is not much text in that file to write patients from."
                }
            } catch (e: CancellationException) {
                // New set closed: nobody is waiting for this file any more
                throw e
            } catch (e: Exception) {
                status = null
                trouble = e.message ?: "That file could not be read."
            } finally {
                reading = false
            }
        }
    }

    fun start() {
        trouble = null
        if (!canMake) return
        val writer = CaseMaker.writer(llm.backend()) ?: run {
            trouble = CaseMaker.noWriter(llm.cloudBlocker.takeIf { llm.choice() != LLMChoice.off })
            return
        }
        val wanted = caseCount
        val subj = subject
        val text = sourceText
        val lecture = sourceName
        val doc = read?.doc()
        val setName = if (name.trim().isEmpty()) lecture.ifEmpty { "Cases" } else name
        status = "Writing 0 of $wanted…"
        // started once it is held, so a writer that fails at once still clears it
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                val made = CaseMaker.write(wanted, text, lecture, subj, using = writer,
                    onProgress = { done, total -> status = "Writing $done of $total…" })
                val set = StudySet(name = setName, subject = subj.ifEmpty { "General" }, kind = StudySetKind.CASES,
                    caseFiles = made.cases, sources = listOfNotNull(doc))
                status = "${made.cases.size} written." + CaseChecks.note(made.cases.size, made.dropped)
                onMade(set)
            } catch (e: CancellationException) {
                status = "Cancelled."
                throw e
            } catch (e: Exception) {
                status = null
                trouble = e.message ?: "The patients could not be written."
            } finally {
                task = null
            }
        }
        task = job
        job.start()
    }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        if (step == LectureStep.material) {
            EditorSection("Add a lecture",
                footer = "PDF, Word or PowerPoint. A lecture on a condition - how it presents, what the tests show, how it is treated - makes the best patients.") {
                WardButtonBox({ picker.launch(LectureFiles.types) }, Modifier.fillMaxWidth(), kind = WardButtonKind.secondary, enabled = !working) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.AutoMirrored.Rounded.NoteAdd, null)
                        Text(if (sourceName.isEmpty()) "Choose a lecture" else "Choose a different lecture")
                    }
                }
                if (sourceName.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.CheckCircle, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
                        EditorNote(sourceName)
                    }
                }
                Messages(status, trouble)
            }
        }
        if (step == LectureStep.make) {
            EditorSection(null,
                footer = "Each patient is checked for its structure and its numbers before it is kept, and by the accuracy checkers once the set is saved.") {
                if (sourceName.isEmpty()) {
                    EditorNote("Nothing to write from yet — go Back and add a lecture.")
                } else {
                    CountField("How many patients", caseCount, 1..CaseWriting.maxCases, { caseCount = it }, enabled = !working)
                    WardButtonBox(::start, Modifier.fillMaxWidth(), kind = WardButtonKind.primary, enabled = canMake) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            if (task != null) EcgLoader()
                            Icon(modeIcon(StudySetKind.CASES), null)
                            Text(makeTitle)
                        }
                    }
                    if (task != null) {
                        WardButtonBox({ task?.cancel() }, Modifier.fillMaxWidth(), kind = WardButtonKind.secondary) { Text("Cancel") }
                    }
                }
                Messages(status, trouble)
                MoreOptions("More options", showMore, { showMore = it }) {
                    WardTextField(subject, onSubject, Modifier.fillMaxWidth().semantics { contentDescription = "Subject" },
                        placeholder = "Subject, e.g. Cardiology", enabled = !working)
                }
            }
        }
    }
}

/** What the section is doing, in grey, and what went wrong, in a danger banner (iOS messages). */
@Composable private fun Messages(status: String?, trouble: String?) {
    status?.let { EditorNote(it, style = WardTextStyle.caption) }
    trouble?.let { WardBanner(it, Icons.Rounded.Warning, WardTone.Danger) }
}
