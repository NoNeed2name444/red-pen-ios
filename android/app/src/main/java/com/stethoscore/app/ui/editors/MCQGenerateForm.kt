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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.MCQGenerator
import com.stethoscore.app.data.ReadSource
import com.stethoscore.app.data.StudySet
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
// writer chosen in AI models. None of them is on Android yet, so the form
// takes the path iOS takes when no model is ready: what is needed first comes
// before the button, and Make stays greyed with the reason under it. Nothing
// is sent anywhere and no key is asked for.

/** The no-writer words, the same path the other batches show (CaseMaker.noWriter, the quiz's twins). */
internal object NoWriter {
    const val questions = "On-device writing isn't available here. Writing new questions comes to Android with its AI models."
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
    @Suppress("UNUSED_PARAMETER") name: String,
    step: LectureStep,
    @Suppress("UNUSED_PARAMETER") onGenerated: (StudySet) -> Unit,
) {
    // No writer on this phone: iOS's activeBackend is nil, and none needs Pro.
    val isGenerating = false
    val needsOfflineModel = true
    var showMore by rememberSaveable { mutableStateOf(false) }
    val canStart = !isGenerating && !needsOfflineModel && sourceText.trim().isNotEmpty()

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
                needsOfflineModel -> NoWriter.questionsHint
                sourceText.trim().isEmpty() -> "Nothing to write from yet — go Back and add a lecture."
                else -> null
            }
            // with no model ready, getting one is the first thing to do, so it
            // comes before the button it would unlock
            EditorSection("Needed first: a question writer") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Rounded.Warning, null, tint = WardTone.Warning.color())
                    EditorNote(NoWriter.questions)
                }
            }
            EditorSection(null) {
                CountField("How many questions", questionCount, 3..MCQGenerator.maxQuestionsTotal, onQuestionCount, enabled = !isGenerating)
                // the same as its floating copy in the dock
                WardButtonBox({}, Modifier.fillMaxWidth(), kind = WardButtonKind.primary, enabled = canStart) {
                    Text("Make $questionCount questions")
                }
                makeHint?.let { EditorNote(it) }
                MoreOptions("More options", showMore, { showMore = it }) {
                    WardTextField(subject, onSubject, Modifier.fillMaxWidth(), placeholder = "Subject, e.g. Cardiology", enabled = !isGenerating)
                    WardToggle(highYield, onHighYield, enabled = !isGenerating, label = "Focus on high-yield facts")
                }
            }
        }
    }
}
