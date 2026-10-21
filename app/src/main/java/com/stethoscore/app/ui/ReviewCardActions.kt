package com.stethoscore.app.ui

import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.PauseCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.CardReview
import com.stethoscore.app.ui.ward.WardToken
import kotlinx.coroutines.delay
import kotlin.math.abs

// Undo for a few seconds after each rating, and Bury / Suspend from the card itself. Port of
// ios/RedPen/Features/Anki/ReviewCardActions.swift at dcb4745, in plain Compose with the Ward
// colours (the Ward controls are being ported in their own batch).

@Suppress("DEPRECATION")
private fun android.view.View.say(text: String) = announceForAccessibility(text)

/**
 * "Undo" in a small capsule at the top end of the card while [until] (epoch ms) is in the
 * future; it clears itself ([onExpire]) when the time is up. With a screen reader on it stays
 * until the next rating: five seconds is not long enough to find it by swiping.
 */
@Composable fun BoxScope.ReviewUndoChip(until: Long?, onExpire: () -> Unit, onUndo: () -> Unit) {
    val context = LocalContext.current
    val view = LocalView.current
    val reader = remember { (context.getSystemService(android.content.Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager)?.isTouchExplorationEnabled == true }
    LaunchedEffect(until) {
        val shown = until ?: return@LaunchedEffect
        if (reader) return@LaunchedEffect
        val wait = shown - System.currentTimeMillis()
        if (wait > 0) delay(wait)
        onExpire()
    }
    if (until == null) return
    Row(Modifier.align(Alignment.TopEnd).padding(top = 8.dp, end = 16.dp).heightIn(min = 44.dp)
        .relief(LocalWardDark.current, 22f).background(wardColor(WardToken.raised), RoundedCornerShape(22.dp))
        .clickable(role = Role.Button, onClickLabel = "Brings the last card back as it was") { onUndo(); view.say("Rating undone. The card is back.") }
        .semantics(mergeDescendants = true) { contentDescription = "Undo last rating" }
        .padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(Icons.AutoMirrored.Rounded.Undo, null, Modifier.size(16.dp), tint = wardColor(WardToken.primaryInk))
        Text("Undo", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = wardColor(WardToken.primaryInk))
    }
}

/**
 * Hold a card (or swipe it sideways) for Bury until tomorrow and Suspend. Both are also in a
 * screen reader's actions, and the screen's More menu.
 */
@Composable fun ReviewCardActions(onBury: () -> Unit, onSuspend: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    var asking by remember { mutableStateOf(false) }
    val view = LocalView.current
    val swipe = with(LocalDensity.current) { CardReview.swipe.dp.toPx() }
    val bury = { onBury(); view.say("Buried until tomorrow.") }
    val suspend = { onSuspend(); view.say("Card suspended.") }
    Box(modifier
        .pointerInput(Unit) { detectTapGestures(onLongPress = { asking = true }) }
        // watched, never consumed, so the card still scrolls
        .pointerInput(swipe) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                var dx = 0f; var dy = 0f
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                    dx += change.positionChange().x; dy += change.positionChange().y
                    if (!change.pressed) break
                }
                if (abs(dx) > swipe && abs(dx) > abs(dy) * 2) asking = true
            }
        }
        .semantics { customActions = listOf(CustomAccessibilityAction("Bury until tomorrow") { bury(); true }, CustomAccessibilityAction("Suspend card") { suspend(); true }) }) {
        content()
    }
    if (asking) AlertDialog(
        onDismissRequest = { asking = false },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = { asking = false; bury() }, Modifier.fillMaxWidth()) {
                    Icon(Icons.Rounded.Bedtime, null); Spacer(Modifier.width(8.dp)); Text("Bury until tomorrow", Modifier.weight(1f))
                }
                TextButton(onClick = { asking = false; suspend() }, Modifier.fillMaxWidth()) {
                    Icon(Icons.Rounded.PauseCircle, null, tint = wardColor(WardToken.danger)); Spacer(Modifier.width(8.dp)); Text("Suspend card", Modifier.weight(1f), color = wardColor(WardToken.danger))
                }
            }
        },
        confirmButton = { TextButton(onClick = { asking = false }) { Text("Cancel") } },
    )
}
