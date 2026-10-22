package com.stethoscore.app.ui.editors

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.ext.SdkExtensions
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.NoteAdd
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.LectureForms
import com.stethoscore.app.data.MCQCoverage
import com.stethoscore.app.data.MCQGenerator
import com.stethoscore.app.data.OfficeText
import com.stethoscore.app.data.ReadSource
import com.stethoscore.app.data.SourcePage
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.textStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// A port of ios/RedPen/Features/Library/LecturePDFSection.swift
// (fed0105): reading the lecture out of the file the lecturer handed out, for
// the question form of New set. The text is appended to whatever the student
// already pasted, and the count is proposed from how much there is
// (MCQCoverage.suggestedCount).
//
// What differs on Android: the words of a PDF are read by the platform's
// PdfRenderer, which reads them from Android 15 (with its PDF extension); a
// scanned page has no words to read without a text reader (ML Kit is not
// among this build's libraries), and the labelled diagrams iOS turns into
// picture cards are not looked for, so the "Also make N picture cards" offer
// never shows. Word and PowerPoint are read from their XML (OfficeText).

/** Which step of New set is showing (iOS NewSetStep): the form keeps its state across all three. */
enum class LectureStep { kind, material, make }

/** One lecture file read on the device: its name, its kind, its pages. */
data class LectureFile(val name: String, val extension: String, val pages: List<SourcePage>)

/** Reading a lecture file picked from Files: PDF, Word or PowerPoint. Slow work, off the main thread. */
object LectureFiles {
    /** What the picker offers (iOS readableTypes). */
    val types = arrayOf(
        "application/pdf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    )

    /** Whether this phone can read a PDF's words (PdfRenderer's text, Android 15 with the PDF extension). */
    val readsPdfText: Boolean
        get() = Build.VERSION.SDK_INT >= 35 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.S) >= 13

    fun read(context: Context, uri: Uri): LectureFile {
        val display = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        } ?: uri.lastPathSegment ?: "Lecture"
        val dot = display.lastIndexOf('.')
        val ext = if (dot > 0) display.substring(dot + 1).lowercase() else ""
        val name = if (dot > 0) display.substring(0, dot) else display
        val pages = when (ext) {
            "pdf" -> pdfPages(context, uri)
            "docx", "pptx" -> context.contentResolver.openInputStream(uri)?.use { OfficeText.read(it, ext) }
                ?: throw OfficeText.Unreadable("That file could not be opened.")
            else -> throw OfficeText.Unreadable("Choose a PDF, Word or PowerPoint file.")
        }
        return LectureFile(name, ext, pages)
    }

    @SuppressLint("NewApi")
    private fun pdfPages(context: Context, uri: Uri): List<SourcePage> {
        if (!readsPdfText) throw OfficeText.Unreadable("This phone can't read the words of a PDF. Paste your notes below, or choose the Word or PowerPoint file.")
        val descriptor = context.contentResolver.openFileDescriptor(uri, "r") ?: throw OfficeText.Unreadable("That file could not be opened.")
        return descriptor.use { pfd ->
            val renderer = PdfRenderer(pfd)
            try {
                (0 until renderer.pageCount).map { index ->
                    val page = renderer.openPage(index)
                    try {
                        SourcePage(number = index + 1, text = page.textContents.joinToString("\n") { it.text }.trim())
                    } finally { page.close() }
                }
            } finally { renderer.close() }
        }
    }
}

/**
 * LecturePDFSection: "Add a file" with the file button, what reading it found,
 * and the footer. Drawn only when [visible]; the state it reports lives in
 * the form that holds it, so a file read in step 2 is still read in step 3.
 */
@Composable fun LecturePDFSection(
    sourceText: String,
    onSourceText: (String) -> Unit,
    questionCount: Int,
    onQuestionCount: (Int) -> Unit,
    readSource: ReadSource?,
    onReadSource: (ReadSource?) -> Unit,
    disabled: Boolean,
    visible: Boolean = true,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var reading by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    val now = rememberUpdatedState(sourceText)
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        reading = true
        status = null
        scope.launch {
            try {
                val file = withContext(Dispatchers.IO) { LectureFiles.read(context, uri) }
                val source = ReadSource(name = file.name, pages = file.pages, kind = LectureForms.kind(file.extension))
                // appended rather than replacing: a student who pasted notes and
                // then adds the slides means both
                val existing = now.value.trim()
                val text = if (existing.isEmpty()) source.text else existing + "\n\n" + source.text
                onSourceText(text)
                onReadSource(source)
                // proposed, not imposed: the count still moves
                val count = minOf(MCQGenerator.maxQuestionsTotal, MCQCoverage.suggestedCount(forCharacters = text.length))
                onQuestionCount(count)
                status = LectureForms.pdfSummary(source.pages.size, source.recognisedPages, figures = 0, cards = 0, questionCount = count)
            } catch (e: Exception) {
                status = e.message ?: "That file could not be read."
            }
            reading = false
        }
    }
    if (!visible) return
    EditorSection("Add a file", footer = "PDF, Word or PowerPoint. It is read on this device.") {
        // second to the dock's Next
        WardButtonBox({ picker.launch(LectureFiles.types) }, Modifier.fillMaxWidth(), kind = WardButtonKind.secondary, enabled = !reading && !disabled) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (reading) EcgLoader()
                Icon(Icons.AutoMirrored.Rounded.NoteAdd, null)
                Text(LectureForms.pdfPickTitle(reading, readSource != null))
            }
        }
        status?.let { EditorNote(it, style = WardTextStyle.caption) }
    }
}

