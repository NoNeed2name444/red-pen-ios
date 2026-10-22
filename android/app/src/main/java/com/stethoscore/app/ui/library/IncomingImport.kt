package com.stethoscore.app.ui.library

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.ImportPreview
import com.stethoscore.app.data.ImportSource
import com.stethoscore.app.data.LibraryImport
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardRaised
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// iOS Features/Library/IncomingImport.swift: a Quizlet / CSV / TSV table or a
// whole-library backup opened from another app gets the same preview as
// New set's Open a file, and a backup the "Restore from this backup?"
// question. Nothing changes until the student taps.

/** A file picked or opened from another app, read: its name and its bytes. */
class PickedFile(val name: String, val data: ByteArray)

/** The most a picked file may be: larger is refused before it is read in full. */
private const val MAX_BYTES = 64L * 1024 * 1024

/** Reads [uri] with its display name; throws when it cannot be opened or is too large. */
fun readPicked(context: Context, uri: Uri): PickedFile {
    val resolver = context.contentResolver
    var name = uri.lastPathSegment?.substringAfterLast('/') ?: "file"
    var size = -1L
    runCatching {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { i -> c.getString(i)?.let { name = it } }
                c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 && !c.isNull(it) }?.let { i -> size = c.getLong(i) }
            }
        }
    }
    require(size <= MAX_BYTES) { "This file is too large to open." }
    val data = resolver.openInputStream(uri)?.use { it.readBytes() } ?: error("Unable to open this file")
    require(data.size <= MAX_BYTES) { "This file is too large to open." }
    return PickedFile(name, data)
}

/**
 * Files other apps hand the app (Open with, Share), waiting for the library
 * to show them (iOS ImportRouter). MainActivity puts them here.
 */
object IncomingFiles {
    val waiting = mutableStateListOf<Uri>()

    /** Takes the file an Open with or Share intent carries, if any. */
    fun take(intent: Intent?) {
        intent ?: return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") (intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
            else -> null
        }
        if (uri != null) waiting += uri
    }
}

private class IncomingMessage(val title: String, val body: String)

/**
 * Shows each waiting file in turn: "Reading name…" while it is read, then
 * the preview with Import; a backup asks first; a file that cannot be read
 * says why. [busy]: the screen has something of its own up, so a file waits.
 */
@Composable fun IncomingImportHost(store: StudyStore, busy: Boolean, onChanged: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var reading by remember { mutableStateOf<String?>(null) }
    var preview by remember { mutableStateOf<ImportPreview?>(null) }
    var backup by remember { mutableStateOf<PickedFile?>(null) }
    var message by remember { mutableStateOf<IncomingMessage?>(null) }
    val idle = reading == null && preview == null && backup == null && message == null

    val ready = idle && !busy && IncomingFiles.waiting.isNotEmpty()
    LaunchedEffect(ready) {
        if (!ready) return@LaunchedEffect
        val uri = IncomingFiles.waiting.removeAt(0)
        val guess = uri.lastPathSegment?.substringAfterLast('/') ?: "file"
        reading = LibraryImport.stem(guess)
        // the work is the screen's, not this effect's: the effect ends as soon as reading is set
        scope.launch {
            val file = withContext(Dispatchers.IO) { runCatching { readPicked(context, uri) } }.getOrElse {
                reading = null
                message = IncomingMessage("Couldn\u2019t read $guess", it.message ?: "Unable to open this file")
                return@launch
            }
            reading = LibraryImport.stem(file.name)
            val head = file.data.copyOf(minOf(16, file.data.size))
            if (ImportSource.of(file.name, head) == ImportSource.APP_FILE) {
                reading = null
                backup = file
                return@launch
            }
            // a question sheet comes in as questions, anything else as cards
            val made = withContext(Dispatchers.Default) { runCatching { LibraryImport.previewDetecting(file.name, file.data, "") } }
            reading = null
            made.onSuccess { preview = it }.onFailure { message = IncomingMessage("Couldn\u2019t read ${file.name}", it.message ?: "") }
        }
    }

    reading?.let { name ->
        Box(Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.TopCenter) {
            Row(Modifier.wardRaised(20.0, WardLift.high).padding(horizontal = 14.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Download, null, tint = wardColor(WardToken.ink), modifier = Modifier.size(16.dp))
                Text("Reading $name…", style = WardTextStyle.footnote.textStyle(WardWeight.medium), color = wardColor(WardToken.ink))
            }
        }
    }
    preview?.let { shown ->
        ImportPreviewSheet(shown, onDismiss = { preview = null }) {
            runCatching { LibraryImport.commit(shown, store) }
                .onFailure { message = IncomingMessage("Couldn’t import", it.message ?: "") }
            preview = null
            onChanged()
        }
    }
    backup?.let { file ->
        AlertDialog(onDismissRequest = { backup = null },
            title = { Text("Restore from this backup?") },
            text = { Text("Sets, schedules, notes and files this phone doesn’t have are added. Nothing here is replaced or deleted.") },
            confirmButton = { WardTextButton("Restore", {
                backup = null
                reading = "backup"
                scope.launch {
                    val result = withContext(Dispatchers.IO) { runCatching { store.importJson(file.data.toString(Charsets.UTF_8)) } }
                    reading = null
                    message = result.fold({ IncomingMessage("Backup restored", "Added $it set${if (it == 1) "" else "s"}.") }) {
                        IncomingMessage("Couldn’t restore", it.message ?: "")
                    }
                    onChanged()
                }
            }, kind = WardButtonKind.quiet, fills = false) },
            dismissButton = { WardTextButton("Cancel", { backup = null }, kind = WardButtonKind.quiet, fills = false) },
            containerColor = wardColor(WardToken.raised), shape = androidx.compose.foundation.shape.RoundedCornerShape(28.dp))
    }
    message?.let { shown -> LibraryAlert(shown.title, shown.body) { message = null } }
}

