package com.stethoscore.app.ui.editors

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.CaseMaker
import com.stethoscore.app.data.MCQGenerator
import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.ReadSource
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.exam.ExamChoice
import com.stethoscore.app.llm.HostedProvider
import com.stethoscore.app.llm.LLMBackend
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
// Every writer is the worker's writer route (LLMService): there is no
// writer to choose (the owner, 22 Oct). Not blocked, Make writes the set through MedicalGenerate and hands it to
// onGenerated; with none, the form takes the path iOS takes when no model is
// ready: what is needed first comes before the button, and Make stays greyed
// with the reason under it. Nothing is sent anywhere and no key is asked for.

/** The no-writer words, the same path the other batches show (CaseMaker.noWriter, the quiz's twins). */
internal object NoWriter {
    const val questions = "New questions are written by ${HostedProvider.BRAND} Cloud, which is part of Pro."
    const val cards = "No model is ready: writing new cards and textbooks comes to Android later."
}

/**
 * The AI service New set's writers use (this form and CaseMakeSection). None
 * given means the app's own, LLMService.from; a test gives one on a fake
 * transport, so it can tap from home to the worker without the network.
 */
val LocalLLMService = staticCompositionLocalOf<LLMService?> { null }

/**
 * A New set section's main button, copied into the dock while the real one
 * is out of sight (iOS Shared/FloatingAction.swift): the section registers
 * what its button does ([FloatingActionRegistration]) and marks the button
 * ([floatingActionAnchor]); the dock floats the copy only for the section it
 * expects, and never while one of them is writing.
 */
class FloatingAction {
    data class Item(val id: String, val title: String, val enabled: Boolean, val busy: Boolean, val icon: ImageVector)

    val items = mutableStateMapOf<String, Item>()
    /** Which real buttons are on screen; a button counts as off screen until it reports in. */
    val visible = mutableStateMapOf<String, Boolean>()
    private val runs = HashMap<String, () -> Unit>()

    internal fun register(item: Item, run: () -> Unit) {
        runs[item.id] = run
        if (items[item.id] != item) items[item.id] = item
    }

    internal fun remove(id: String) { items.remove(id); visible.remove(id); runs.remove(id) }

    internal fun setVisible(id: String, now: Boolean) { if (visible[id] != now) visible[id] = now }

    /** The copy to float for [expecting]: only while its real button is out of sight, and never while something is being written. */
    fun floating(expecting: String?): Item? {
        if (expecting == null || items.values.any { it.busy }) return null
        val item = items[expecting] ?: return null
        return if (visible[expecting] == true) null else item
    }

    fun run(id: String) { runs[id]?.invoke() }
}

/** New set's floating action, for the sections it hosts; none outside New set. */
val LocalFloatingAction = staticCompositionLocalOf<FloatingAction?> { null }

/** Registers a section's main action, kept current as its title and whether it can run change (iOS floatingAction). */
@Composable internal fun FloatingActionRegistration(id: String, title: String, enabled: Boolean, busy: Boolean, icon: ImageVector, run: () -> Unit) {
    val floating = LocalFloatingAction.current ?: return
    val latest by rememberUpdatedState(run)
    SideEffect { floating.register(FloatingAction.Item(id, title, enabled, busy, icon)) { latest() } }
    DisposableEffect(floating, id) { onDispose { floating.remove(id) } }
}

/** Marks the real button, so the floating copy knows when it is on screen: 60% of it in sight (iOS floatingActionAnchor). */
@Composable internal fun Modifier.floatingActionAnchor(id: String): Modifier {
    val floating = LocalFloatingAction.current ?: return this
    return onGloballyPositioned { c ->
        val height = c.size.height
        floating.setVisible(id, height > 0 && c.boundsInWindow().height >= 0.6f * height)
    }
}

/** The service [LocalLLMService] gives, or the app's own. */
@Composable internal fun rememberLLMService(): LLMService {
    val given = LocalLLMService.current
    val context = LocalContext.current
    return remember(given) { given ?: LLMService.from(context) }
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
    val llm = rememberLLMService()
    val backend: LLMBackend? = remember(step) { llm.backend() }
    val blocker: String? = llm.cloudBlocker
    val scope = rememberCoroutineScope()
    var generation by remember { mutableStateOf<Job?>(null) }
    var generationStatus by rememberSaveable { mutableStateOf<String?>(null) }
    val isGenerating = generation != null
    val needsWriter = backend == null
    var showMore by rememberSaveable { mutableStateOf(false) }
    val canStart = !isGenerating && !needsWriter && sourceText.trim().isNotEmpty()

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
                needsWriter -> CaseMaker.noWriter(blocker)
                sourceText.trim().isEmpty() -> "Nothing to write from yet \u2014 go Back and add a lecture."
                else -> null
            }
            if (needsWriter) {
                // with no writer, what it takes comes before the button it would
                // unlock; nothing is written on the phone
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
                FloatingActionRegistration("mcq", "Make $questionCount questions", canStart, isGenerating, Icons.Rounded.EditNote, ::generate)
                WardButtonBox(::generate, Modifier.fillMaxWidth().floatingActionAnchor("mcq"), kind = WardButtonKind.primary, enabled = canStart) {
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
