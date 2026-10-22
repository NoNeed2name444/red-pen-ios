package com.stethoscore.app.ui.narrate

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.stethoscore.app.ui.editors.EditorTopBar
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor

/** A word picked to fix: the line, the word in it, and what it was heard as. */
data class FixTarget(val segment: Int, val word: Int, val heard: String)

/**
 * Fixing a misheard word, from the transcript itself
 * (ios/RedPen/Features/Narrate/FixWordSheet.swift, fed0105): the word as it
 * was heard, what it should be, a plain line saying the fix spreads, and Fix
 * under the thumb (with Cancel and a second Fix at the top, as iOS's toolbar).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun FixWordSheet(target: FixTarget, onSave: (String) -> Unit, onDismiss: () -> Unit) {
    var spelling by remember(target) { mutableStateOf("") }
    val usable = spelling.isNotBlank()
    val focus = remember { FocusRequester() }
    fun save() {
        val wanted = spelling.trim()
        if (wanted.isEmpty()) return
        onSave(wanted)
        onDismiss()
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = wardColor(WardToken.background)) {
        EditorTopBar("Fix this word", onCancel = onDismiss) {
            WardTextButton("Fix", { save() }, kind = WardButtonKind.compact, enabled = usable, fills = false)
        }
        Column(Modifier.fillMaxWidth().padding(16.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                WardSmallCapsText("Heard as")
                SelectionContainer {
                    Text(target.heard, style = WardTextStyle.title3.textStyle(WardWeight.semibold), color = wardColor(WardToken.danger),
                        textDecoration = TextDecoration.Underline)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                WardSmallCapsText("Should be")
                WardTextField(spelling, { spelling = it }, Modifier.fillMaxWidth().focusRequester(focus), placeholder = "the correct spelling")
            }
            // said plainly up front: the student is about to change more of the transcript than the word they tapped
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                Icon(Icons.Rounded.AutoFixHigh, null, Modifier.size(16.dp), tint = wardColor(WardToken.inkSecondary))
                Text("Every other word that sounds the same is fixed too, and remembered for next time.",
                    style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            // the one action, under the thumb
            WardTextButton("Fix", { save() }, Modifier.fillMaxWidth().padding(top = 8.dp), kind = WardButtonKind.primary, enabled = usable)
        }
    }
    LaunchedEffect(target) { runCatching { focus.requestFocus() } }
}

/**
 * What a correction did, shown until it is undone or replaced (FixReport): a
 * green tick, the summary and Undo, on a capsule raised high over the
 * transcript. A toast, not an alert: the student is reading.
 */
@Composable internal fun FixReport(summary: String, onUndo: () -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.padding(horizontal = 16.dp).wardRelief(CircleShape, WardLift.high)
        .padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.CheckCircle, null, tint = wardColor(WardToken.success))
        Text(summary, Modifier.weight(1f), style = WardTextStyle.subheadline.textStyle(WardWeight.medium), color = wardColor(WardToken.ink))
        WardTextButton("Undo", onUndo, kind = WardButtonKind.compact, fills = false)
    }
}
