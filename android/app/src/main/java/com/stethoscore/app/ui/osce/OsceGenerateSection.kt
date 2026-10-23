package com.stethoscore.app.ui.osce

import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.NoteAdd
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.foundation.clickable
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.CaseMaker
import com.stethoscore.app.data.OsceGenerator
import com.stethoscore.app.data.OsceStations
import com.stethoscore.app.ui.editors.rememberLLMService
import com.stethoscore.app.ui.mock.CountField
import com.stethoscore.app.ui.ward.WardBanner
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardControlSize
import com.stethoscore.app.ui.ward.WardSectionLabel
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextField
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.zip.ZipInputStream

// Port of ios/RedPen/Features/OSCE/OsceGenerateSection.swift.
//
// Writing stations from a lecture, for the new-set screen. The result is
// written into the text box rather than straight into a set: a checklist
// written by a model is a draft, and the student who sat the teaching knows
// whether "auscultate in four areas" was taught as one step or four. They
// edit, then create.
//
// New set on Android is one page rather than iOS's steps, so the file
// (iOS step 2) and the count with its Make button (step 3) stand one under
// the other. Stations need an AI writer; none is set up on this phone yet
// (OsceGenerator.writer()), so Make says so, as batches 7 and 10 do.

/** What a file gave: its words, its name and how many pages it counts as. */
internal data class OsceSourceRead(val text: String, val name: String, val pages: Int)

internal class OsceReadTrouble(message: String) : Exception(message)

/** Reads a PDF, Word or PowerPoint file's words (SourceIngest and OfficeIngest, without figures). */
internal object OsceSourceReader {
    fun read(context: Context, uri: Uri): OsceSourceRead {
        val resolver = context.contentResolver
        val display = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        } ?: uri.lastPathSegment.orEmpty().substringAfterLast('/')
        val name = display.substringBeforeLast('.', display)
        val isPdf = display.lowercase().endsWith(".pdf") || resolver.getType(uri) == "application/pdf"
        return if (isPdf) readPdf(context, uri, name) else readOffice(context, uri, name)
    }

    private fun readPdf(context: Context, uri: Uri, name: String): OsceSourceRead {
        val fd = try { context.contentResolver.openFileDescriptor(uri, "r") } catch (e: Exception) { null }
            ?: throw OsceReadTrouble("That file could not be opened as a PDF.")
        fd.use {
            val renderer = try { PdfRenderer(fd) } catch (e: Exception) { throw OsceReadTrouble("That file could not be opened as a PDF.") }
            renderer.use { r ->
                if (r.pageCount == 0) throw OsceReadTrouble("That PDF has no pages.")
                val text = StringBuilder()
                // A PDF's words are readable on Android 15 and later; there is no OCR here.
                if (Build.VERSION.SDK_INT >= 35) {
                    for (i in 0 until r.pageCount) {
                        r.openPage(i).use { page -> page.textContents.forEach { text.append(it.text).append('\n') } }
                        text.append('\n')
                    }
                }
                if (text.isBlank()) throw OsceReadTrouble("No text could be read from that PDF, even by OCR.")
                return OsceSourceRead(text.toString().trim(), name, r.pageCount)
            }
        }
    }

    private fun readOffice(context: Context, uri: Uri, name: String): OsceSourceRead {
        val entries = HashMap<String, String>()
        try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                ZipInputStream(input).use { zip ->
                    while (true) {
                        val entry = zip.nextEntry ?: break
                        val n = entry.name
                        if (n == "word/document.xml" || slideNumber(n) != null) entries[n] = zip.readBytes().toString(Charsets.UTF_8)
                    }
                }
            } ?: throw OsceReadTrouble("That file could not be opened.")
        } catch (e: OsceReadTrouble) { throw e } catch (e: Exception) {
            throw OsceReadTrouble("That file is damaged, or too large inside to open safely. Try saving it again, or exporting it as a PDF.")
        }
        val slides = entries.keys.mapNotNull { k -> slideNumber(k)?.let { it to k } }.sortedBy { it.first }
        val pages: List<String> = when {
            slides.isNotEmpty() -> slides.map { xmlText(entries.getValue(it.second), "a") }
            entries.containsKey("word/document.xml") -> listOf(xmlText(entries.getValue("word/document.xml"), "w"))
            else -> throw OsceReadTrouble("That does not look like a Word or PowerPoint file. An old .doc or .ppt needs saving as .docx or .pptx first.")
        }
        val text = pages.joinToString("\n\n").trim()
        if (text.isEmpty()) throw OsceReadTrouble("No text could be read from that file.")
        return OsceSourceRead(text, name, pages.size)
    }

    private val slidePath = Regex("^ppt/slides/slide(\\d+)\\.xml$")
    private fun slideNumber(path: String): Int? = slidePath.find(path)?.groupValues?.get(1)?.toIntOrNull()

    /** The words of a WordprocessingML or DrawingML part: its <x:t> runs, a line per paragraph. */
    internal fun xmlText(xml: String, ns: String): String {
        val out = StringBuilder()
        val token = Regex("<$ns:t(?:\\s[^>]*)?>([^<]*)</$ns:t>|</$ns:p>|<$ns:br\\s*/>|<$ns:tab\\s*/>")
        for (m in token.findAll(xml)) {
            val v = m.value
            when {
                v.startsWith("</$ns:p") -> out.append('\n')
                v.startsWith("<$ns:br") -> out.append('\n')
                v.startsWith("<$ns:tab") -> out.append('\t')
                else -> out.append(unescape(m.groupValues[1]))
            }
        }
        return out.toString().lines().map { it.trim() }.filter { it.isNotEmpty() }.joinToString("\n")
    }

    private fun unescape(s: String): String = s.replace(Regex("&(#x[0-9a-fA-F]+|#\\d+|amp|lt|gt|quot|apos);")) { m ->
        when (val e = m.groupValues[1]) {
            "amp" -> "&"; "lt" -> "<"; "gt" -> ">"; "quot" -> "\""; "apos" -> "'"
            else -> {
                val code = if (e.startsWith("#x")) e.drop(2).toIntOrNull(16) else e.drop(1).toIntOrNull()
                code?.let { String(Character.toChars(it)) } ?: m.value
            }
        }
    }
}

@Composable
fun OsceGenerateSection(bodyText: String, onBodyText: (String) -> Unit, subject: String, onSubject: (String) -> Unit,
                        presetText: String = "", presetName: String = "") {
    val context = LocalContext.current
    val llm = rememberLLMService()
    val scope = rememberCoroutineScope()
    var working by remember { mutableStateOf(false) }
    var status by rememberSaveable { mutableStateOf<String?>(null) }
    var trouble by rememberSaveable { mutableStateOf<String?>(null) }
    var sourceText by rememberSaveable { mutableStateOf(presetText) }
    var sourceName by rememberSaveable { mutableStateOf(if (presetText.isEmpty()) "" else presetName.ifEmpty { "This set" }) }
    var stationCount by rememberSaveable { mutableIntStateOf(3) }
    var showMore by rememberSaveable { mutableStateOf(false) }
    val canGenerate = !working && sourceText.trim().length > 200
    if (presetText.isNotEmpty() && sourceText == presetText && !canGenerate && trouble == null) {
        trouble = "There is not much in this set to write stations from."
    }
    val makeTitle = "Make $stationCount station" + if (stationCount == 1) "" else "s"

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        trouble = null
        if (uri == null) return@rememberLauncherForActivityResult
        working = true
        status = "Reading…"
        scope.launch {
            try {
                val read = withContext(Dispatchers.IO) { OsceSourceReader.read(context, uri) }
                sourceText = read.text
                sourceName = read.name
                status = "${read.name} — ${read.pages} pages."
                if (read.text.trim().length <= 200) trouble = "There is not much text in that file to work from."
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                status = null
                trouble = e.message ?: "That file could not be opened."
            } finally {
                working = false
            }
        }
    }

    fun start() {
        trouble = null
        // stations need the cloud's writer; without it, the cloud's own reason
        // (part of Pro, sign in, or out of reach), as the question and case screens say
        val writer = OsceGenerator.writer() ?: run { trouble = CaseMaker.noWriter(llm.cloudBlocker); return }
        working = true
        val wanted = stationCount
        val subj = subject
        val text = sourceText
        status = "Writing 0 of $wanted…"
        scope.launch {
            try {
                val stations = OsceStations.tidy(writer.stations(text, wanted, subj))
                if (stations.isEmpty()) throw OsceReadTrouble(OsceGenerator.nothingUsable)
                val made = stations.size
                val written = OsceStations.format(stations)
                // Appended, never replacing: a student who typed a station
                // and then generated more means both.
                val existing = bodyText.trim()
                onBodyText(if (existing.isEmpty()) written else existing + "\n\n" + written)
                status = "$made station${if (made == 1) "" else "s"} written — check them below."
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                status = null
                trouble = e.message
            } finally {
                working = false
            }
        }
    }

    @Composable fun Messages() {
        status?.let { Text(it, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary)) }
        trouble?.let { WardBanner(it, Icons.Rounded.Warning, WardTone.Danger) }
    }

    @Composable fun Footer(text: String) {
        Text(text, Modifier.padding(horizontal = WardSpace.l.wardDp), style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
    }

    Column(verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        // the skills lecture or mark sheet
        WardSectionLabel("Add a file")
        WardCardFace(Modifier.fillMaxWidth(), spacing = WardSpace.m.wardDp) {
            WardButtonBox({ picker.launch(arrayOf("application/pdf",
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "application/vnd.openxmlformats-officedocument.presentationml.presentation")) },
                Modifier.fillMaxWidth(), kind = WardButtonKind.secondary, enabled = !working) {
                Icon(Icons.Rounded.NoteAdd, null, Modifier.size(20.dp))
                Text(if (sourceName.isEmpty()) "Choose a skills lecture or mark sheet" else "Choose a different file")
            }
            if (sourceName.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Rounded.CheckCircle, null, Modifier.size(16.dp), tint = wardColor(WardToken.inkSecondary))
                Text(sourceName, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            if (sourceName.isEmpty()) Messages()
        }
        Footer("PDF, Word or PowerPoint. A skills lecture or a mark sheet works best.")

        // how many stations, the one big button, and More options
        WardCardFace(Modifier.fillMaxWidth().padding(top = WardSpace.m.wardDp), spacing = WardSpace.m.wardDp) {
            if (sourceName.isEmpty()) {
                Text("Nothing to write from yet — go Back and add a file.", style = WardTextStyle.footnote.textStyle(),
                    color = wardColor(WardToken.inkSecondary))
            } else {
                CountField("How many stations", stationCount, { stationCount = it }, 1..OsceGenerator.maxStationsTotal, enabled = !working)
                WardButtonBox(::start, Modifier.fillMaxWidth(), kind = WardButtonKind.primary, enabled = canGenerate) {
                    Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(20.dp))
                    Text(makeTitle)
                }
                Messages()
            }
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = WardControlSize.target.wardDp).clickable(role = Role.Button) { showMore = !showMore }
                .semantics { stateDescription = if (showMore) "Expanded" else "Collapsed" }.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text("More options", Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk))
                Icon(Icons.Rounded.ExpandMore, null, Modifier.rotate(if (showMore) 0f else -90f), tint = wardColor(WardToken.primaryInk))
            }
            if (showMore) WardTextField(subject, onSubject, Modifier.fillMaxWidth(), placeholder = "Subject, e.g. Cardiology", enabled = !working)
        }
        Footer("The stations appear below to check before you save the set.")
    }
}
