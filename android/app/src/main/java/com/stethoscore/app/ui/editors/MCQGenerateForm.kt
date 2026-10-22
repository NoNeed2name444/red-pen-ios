package com.stethoscore.app.ui.editors

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.MCQGenerator
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.ReadSource
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.exam.ExamChoice
import com.stethoscore.app.llm.LLMBackend
import com.stethoscore.app.llm.LLMChoice
import com.stethoscore.app.llm.LLMService
import com.stethoscore.app.llm.MedicalGenerate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardTextField
import com.stethoscore.app.ui.ward.WardToggle
import com.stethoscore.app.ui.ward.WardTone

// A port of ios/RedPen/Features/Library/MCQGenerateForm.swift
// (fed0105): the "generate a set from my material" half of New set. Step 2
// holds the lecture (LecturePDFSection) and the notes; step 3 the count, the
// one big button and the rest behind More options.
//
// iOS writes with Apple's on-device model, the downloaded Gemma model or a
// writer chosen in AI models. On Android only the last exists: Stethoscore
// Cloud, chosen in Settings > AI models (LLMService). With it chosen and not
// blocked, Make writes the set through MedicalGenerate and hands it to
// onGenerated; with none, the form takes the path iOS takes when no model is
// ready: what is needed first comes before the button, and Make stays greyed
// with the reason under it. Nothing is sent anywhere and no key is asked for.

/** The no-writer words, the same path the other batches show (CaseMaker.noWriter, the quiz's twins). */
internal object NoWriter {
    const val questions = "On-device writing isn't available here. Choose a writer in Settings \u25B8 AI models to write new questions."
    const val questionsHint = "No question writer is set up on this phone yet."
    const val cards = "No model is ready: writing new cards and textbooks comes to Android with its AI models."
}

@Composable fun MCQGenerateForm(
    sourceText: String,
    onSourceText: (String) -> Unit,
    questionCount: Int,
    onQuestionCount: (Int) -> Unit,
    highYield: Boolean,
    onHighYield: (Boolean) -> Unit,
    readSource: ReadSource?,
    onReadSource: (ReadSource?) -> Unit,
    subject: String,
    onSubject: (String) -> Unit,
    name: String,
    step: LectureStep,
    onGenerated: (StudySet) -> Unit,
) {
    val context = LocalContext.current
    val llm = remember { LLMService.from(context) }
    val backend: LLMBackend? = remember(step) { llm.backend() }
    val blocker: String? = if (llm.choice() == LLMChoice.cloud) llm.cloudBlocker else null
    val scope = rememberCoroutineScope()
    var generation by remember { mutableStateOf<Job?>(null) }
    var generationStatus by rememberSaveable { mutableStateOf<String?>(null) }
    val isGenerating = generation != null
    val needsOfflineModel = backend == null
    var showMore by rememberSaveable { mutableStateOf(false) }
    val canStart = !isGenerating && !needsOfflineModel && sourceText.trim().isNotEmpty()

    fun generate() {
        val text = sourceText.trim()
        val writer = backend ?: return
        if (text.isEmpty() || isGenerating) return
        val count = questionCount
        val subj = subject
        val cite = readSource
        val defaults = ExamChoice.defaults(context)
        val exam = MedicalGenerate.Exam(ExamChoice.currentTrack(defaults), ExamChoice.current(defaults), ExamChoice.currentSecondary(defaults))
        generationStatus = "Writing 0 of $count questions\u2026"
        generation = scope.launch {
            try {
                val questions: List<MCQQuestion> = MedicalGenerate.mcq(text, count, subj, highYield, writer, exam) { done, total ->
                    generationStatus = "Writing $done of $total questions\u2026"
                }
                generationStatus = "Done \u2014 ${questions.size} question(s) written."
                onGenerated(generatedSet(name, subj, questions, exam.target?.id, cite))
            } catch (e: CancellationException) {
                generationStatus = "Cancelled."
                throw e
            } catch (e: Exception) {
                generationStatus = e.message ?: "The questions could not be written."
            } finally {
                generation = null
            }
        }
    }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        // always built, only shown in step 2
        LecturePDFSection(sourceText, onSourceText, questionCount, onQuestionCount, readSource, onReadSource,
            disabled = isGenerating, visible = step == LectureStep.material)

        if (step == LectureStep.material) {
            EditorSection("Or paste your notes", footer = "The questions are written from this text. A file you add above lands here too.") {
                EditorTextArea(sourceText, onSourceText, minHeight = 160.dp, mono = true, enabled = !isGenerating, label = "Or paste your notes")
            }
        }

        if (step == LectureStep.make) {
            val makeHint: String? = when {
                isGenerating -> null
                needsOfflineModel -> blocker ?: NoWriter.questionsHint
                sourceText.trim().isEmpty() -> "Nothing to write from yet \u2014 go Back and add a lecture."
                else -> null
            }
            if (needsOfflineModel) {
                // with no model ready, getting one is the first thing to do, so it
                // comes before the button it would unlock
                EditorSection("Needed first: a question writer") {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                        Icon(Icons.Rounded.Warning, null, tint = WardTone.Warning.color())
                        EditorNote(NoWriter.questions)
                    }
                }
            }
            EditorSection(null) {
                CountField("How many questions", questionCount, 3..MCQGenerator.maxQuestionsTotal, onQuestionCount, enabled = !isGenerating)
                // the same as its floating copy in the dock
                WardButtonBox(::generate, Modifier.fillMaxWidth(), kind = WardButtonKind.primary, enabled = canStart) {
                    Text(if (isGenerating) generationStatus ?: "Writing\u2026" else "Make $questionCount questions")
                }
                if (isGenerating) {
                    WardButtonBox({ generation?.cancel() }, Modifier.fillMaxWidth(), kind = WardButtonKind.secondary) { Text("Cancel") }
                }
                generationStatus?.takeIf { !isGenerating }?.let { EditorNote(it) }
                makeHint?.let { EditorNote(it) }
                MoreOptions("More options", showMore, { showMore = it }) {
                    WardTextField(subject, onSubject, Modifier.fillMaxWidth(), placeholder = "Subject, e.g. Cardiology", enabled = !isGenerating)
                    WardToggle(highYield, onHighYield, enabled = !isGenerating, label = "Focus on high-yield facts")
                    llm.summary()?.let { EditorNote("Using $it.") }
                }
            }
        }
    }
}

/**
 * The set a generation makes (iOS MCQGenerateForm's onGenerated): named for
 * the subject when no name is given, badged with the exam it was written to,
 * and carrying the lecture so its pages can be cited. Provenance (each
 * question matched back to its page) is not on Android yet.
 */
internal fun generatedSet(name: String, subject: String, questions: List<MCQQuestion>, exam: String?, cite: ReadSource?): StudySet {
    val plainSubject = subject.isEmpty() || subject == "General"
    val title = name.ifEmpty { if (plainSubject) "Generated set" else subject }
    return StudySet(name = title, subject = subject.ifEmpty { "General" }, kind = StudySetKind.MCQ,
        questions = questions, exam = exam, sources = listOfNotNull(cite?.doc()))
}
