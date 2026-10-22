package com.stethoscore.app.ui.osce

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.OsceProgress
import com.stethoscore.app.data.OsceRun
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.data.stationMinutes
import com.stethoscore.app.ui.QuizPrefs
import com.stethoscore.app.ui.mock.BigButton
import com.stethoscore.app.ui.mock.BigKind
import com.stethoscore.app.ui.mock.BroadGap
import com.stethoscore.app.ui.mock.ChipBox
import com.stethoscore.app.ui.mock.ContentCard
import com.stethoscore.app.ui.mock.FinishHero
import com.stethoscore.app.ui.mock.FinishSymbol
import com.stethoscore.app.ui.mock.StudyProgressHeader
import com.stethoscore.app.ui.mock.StudyTitleBar
import com.stethoscore.app.ui.ward.StudyActionBar
import com.stethoscore.app.ui.ward.WardEmptyState
import com.stethoscore.app.ui.mock.readableColumn
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTimerPill
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.delay

// Port of ios/RedPen/Features/OSCE/OsceReviewView.swift.
//
// OSCE recall drill: work through each checklist's steps in order, one hidden
// at a time ("what comes next?"), reveal it, then either "I got it" (on to the
// next step) or "Start over". The steps of a station are done in order, so a
// missed step ends the attempt: the station goes back to step 1 and the clock
// back to full, and the miss is kept against that step (OsceRun) so the finish
// can say which steps tripped the student up. When a checklist is got all the
// way through, move on to the next one in the set.
//
// Not ported: the spoken patient (the Voice batch), Check accuracy and Save
// to Ideas (with their More menu), the accuracy badge and keyboard shortcuts.

/** Spoken length of the station clock ("7 minutes 5 seconds"), as iOS's SpokenText.duration. */
internal fun spokenDuration(seconds: Int): String {
    val m = seconds / 60
    val s = seconds % 60
    val mins = if (m == 1) "1 minute" else "$m minutes"
    val secs = if (s == 1) "1 second" else "$s seconds"
    return when {
        m == 0 -> secs
        s == 0 -> mins
        else -> "$mins $secs"
    }
}

@Composable
fun OsceReviewScreen(set: StudySet, store: StudyStore, onBack: () -> Unit, startChecklistIndex: Int = 0,
                     startRevealed: Boolean = false, startComplete: Boolean = false, startMissed: List<Int> = emptyList()) {
    val context = LocalContext.current
    val view = LocalView.current
    val haptic = LocalHapticFeedback.current
    val broad = LocalConfiguration.current.screenWidthDp >= 600
    val checklists = set.osceChecklists
    // A station starts with the time the student's exam gives one - eight
    // minutes for PLAB 2, ten for a PACES encounter.
    val stationSeconds = remember { QuizPrefs.track(context).stationMinutes * 60.0 }

    var checklistIndex by remember(set.id) { mutableIntStateOf(minOf(startChecklistIndex, maxOf(0, checklists.size - 1))) }
    var revealed by remember(set.id) { mutableStateOf(startRevealed) }
    var run by remember(set.id) {
        mutableStateOf(OsceRun(checklists.getOrNull(checklistIndex)?.steps?.size ?: 0, misses = startMissed, complete = startComplete))
    }
    /** When the clock runs out while running (ms), 0 while stopped. */
    var clockEndsAt by remember(set.id) { mutableLongStateOf(0L) }
    /** What is left on the clock while it is stopped. */
    var clockLeft by remember(set.id) { mutableDoubleStateOf(stationSeconds) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }

    val checklist = checklists.getOrNull(checklistIndex)
    val complete = run.complete
    val currentStepText = checklist?.steps?.getOrNull(run.stepIndex)

    fun keepPlace() {
        // The whole set finished is not a position to come back to.
        val point = run.resumePoint(checklistIndex, checklists.size)
        if (point == null) { store.clearOsceProgress(set.id); return }
        // a station just finished is saved as the start of the next one
        val station = checklists.getOrNull(point.station) ?: return
        store.saveOsceProgress(set.id, OsceProgress(point.station, station.title, point.step, point.misses))
    }

    fun stopClock() {
        if (clockEndsAt == 0L) return
        clockLeft = maxOf(0.0, (clockEndsAt - System.currentTimeMillis()) / 1000.0)
        clockEndsAt = 0L
    }

    fun secondsLeft(at: Long): Int {
        val raw = if (clockEndsAt != 0L) (clockEndsAt - at) / 1000.0 else clockLeft
        return maxOf(0, Math.ceil(raw).toInt())
    }

    fun toggleClock() {
        haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
        when {
            clockEndsAt != 0L -> stopClock()
            clockLeft <= 0 -> clockLeft = stationSeconds
            else -> { clockEndsAt = System.currentTimeMillis() + (clockLeft * 1000).toLong(); now = System.currentTimeMillis() }
        }
    }

    fun setRun(new: OsceRun) {
        val old = run
        run = new
        keepPlace()
        if (new.complete && !old.complete) stopClock()
    }

    fun reveal() {
        revealed = true
        if (currentStepText != null) @Suppress("DEPRECATION") view.announceForAccessibility("Step ${run.stepIndex + 1}: $currentStepText")
    }

    fun gotIt() {
        setRun(run.gotIt())
        revealed = false
    }

    /** Back to step 1 with no confirming; the clock goes back to full (still running if it was). */
    fun startOver() {
        haptic.performHapticFeedback(HapticFeedbackType.Reject)
        val wasRunning = clockEndsAt != 0L
        clockLeft = stationSeconds
        clockEndsAt = if (wasRunning) System.currentTimeMillis() + (clockLeft * 1000).toLong() else 0L
        setRun(run.startOver())
        revealed = false
    }

    fun nextChecklist() {
        // a new station gets a fresh clock
        clockEndsAt = 0L
        clockLeft = stationSeconds
        checklistIndex += 1
        revealed = false
        run = OsceRun(checklists.getOrNull(checklistIndex)?.steps?.size ?: 0)
        keepPlace()
    }

    // Picking the station back up: only when the screen was opened at the start.
    LaunchedEffect(set.id) {
        if (checklistIndex == 0 && run.stepIndex == 0 && !complete && run.misses.isEmpty()) {
            val saved = store.osceProgress[set.id]
            if (saved != null && saved.fits(checklists)) {
                checklistIndex = saved.checklistIndex
                run = OsceRun(checklists[saved.checklistIndex].steps.size, saved.stepIndex, saved.missed)
                revealed = false
            }
        }
    }

    // The clock's tick, and two gentle taps from it: one with a minute left,
    // one at the end, so it can be felt without looking away from the patient.
    LaunchedEffect(clockEndsAt) {
        val ends = clockEndsAt
        if (ends == 0L) return@LaunchedEffect
        var warned = ends - System.currentTimeMillis() <= 60_000
        while (true) {
            now = System.currentTimeMillis()
            val rest = ends - now
            if (!warned && rest <= 60_000) { warned = true; haptic.performHapticFeedback(HapticFeedbackType.ContextClick) }
            if (rest <= 0) {
                haptic.performHapticFeedback(HapticFeedbackType.Reject)
                clockEndsAt = 0L
                clockLeft = 0.0
                break
            }
            delay(minOf(1_000L, rest % 1_000L + 1L))
        }
    }

    Column(Modifier.fillMaxSize()) {
        StudyTitleBar(set.subject.ifEmpty { "OSCE" }, onBack)
        if (checklist == null) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                WardEmptyState(Icons.Rounded.Checklist, "No checklists in this set.")
            }
            return@Column
        }

        // "Step 3 of 12", the station's name, and the clock.
        val totalSteps = checklists.sumOf { it.steps.size }
        val earlier = checklists.take(checklistIndex).sumOf { it.steps.size }
        val here = if (complete) checklist.steps.size else run.stepIndex
        val fraction = if (totalSteps > 0) minOf(1.0, (earlier + here).toDouble() / totalSteps) else 0.0
        val status = when {
            complete -> "Station done"
            run.restarts > 0 -> "Step ${run.stepIndex + 1} of ${checklist.steps.size} · attempt ${run.restarts + 1}"
            else -> "Step ${run.stepIndex + 1} of ${checklist.steps.size}"
        }
        StudyProgressHeader(status, checklist.title, fraction) {
            if (!complete) {
                val left = secondsLeft(now)
                val running = clockEndsAt != 0L
                val icon = if (running) Icons.Rounded.Pause else if (left == 0) Icons.Rounded.Replay else Icons.Rounded.PlayArrow
                ChipBox(running, ::toggleClock, Modifier.clearAndSetSemantics {
                    contentDescription = "Station clock, " + spokenDuration(left)
                    stateDescription = if (running) "Pauses the clock" else if (left == 0) "Resets the clock" else "Starts the clock"
                }) {
                    Icon(icon, null, Modifier.size(16.dp), tint = wardColor(WardToken.primaryInk))
                    // red in the last minute only while the clock runs
                    WardTimerPill(left, warnBelow = if (running) 61 else 0, well = false)
                }
            }
        }

        if (complete) {
            val hasNext = checklistIndex < checklists.size - 1
            val restarts = run.restarts
            val title = when {
                restarts == 0 -> "All ${checklist.steps.size} steps, first time"
                restarts == 1 -> "Done after 1 start over"
                else -> "Done after $restarts start overs"
            }
            val weak = run.weakSteps
            val recall = if (weak.isEmpty()) "You recalled every step of ${checklist.title}, in order."
            else "You started over at " + weak.take(3).joinToString(", ") { e ->
                "step ${e.step + 1}" + (if (e.times == 1) "" else " (${e.times} times)")
            } + " - worth another look."
            val next = checklists.getOrNull(checklistIndex + 1)
            val message = if (next == null) "$recall All stations done!" else "$recall Next up: ${next.title}."
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.readableColumn().padding(horizontal = 16.dp).padding(top = 16.dp, bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    FinishHero(title, message) { FinishSymbol(Icons.Rounded.Verified) }
                }
            }
            StudyActionBar {
                if (hasNext) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    BigButton("Done for now", null, BigKind.companion, onBack)
                    BroadGap(broad)
                    BigButton("Next station", Icons.AutoMirrored.Rounded.ArrowForward, BigKind.primary, ::nextChecklist, Modifier.weight(1f))
                } else BigButton("Done", null, BigKind.primary, onBack, Modifier.fillMaxWidth())
            }
        } else {
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                // a start over brings the station back from the top
                key(run.restarts) {
                    Column(Modifier.readableColumn().heightIn(min = 220.dp).padding(16.dp).padding(bottom = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        if (revealed && currentStepText != null) {
                            ContentCard {
                                Text(currentStepText, Modifier.fillMaxWidth().padding(vertical = 12.dp),
                                    style = WardTextStyle.title3.textStyle(WardWeight.medium), color = wardColor(WardToken.ink),
                                    textAlign = TextAlign.Center)
                            }
                        } else {
                            Text("What comes next? Say it out loud, then tap Reveal.", Modifier.fillMaxWidth().padding(16.dp),
                                style = WardTextStyle.title3.textStyle(), color = wardColor(WardToken.inkSecondary), textAlign = TextAlign.Center)
                        }
                        if (!revealed && run.stepIndex == 0) {
                            Text(if (run.restarts == 0) "Work through the station out loud, in order, revealing each step to check yourself."
                                 else "From the top. The steps go in order, so a missed one means starting again.",
                                style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary), textAlign = TextAlign.Center)
                        }
                    }
                }
            }
            // the station's bar folds away (iOS OsceReviewView studyBar(folds: true))
            StudyActionBar(folds = true) {
                if (revealed) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    BigButton("Start over", Icons.Rounded.Replay, BigKind.secondary, ::startOver,
                        Modifier.weight(1f).semantics { stateDescription = "Back to step 1, with the clock reset" })
                    BroadGap(broad)
                    BigButton("I got it", Icons.Rounded.Check, BigKind.primary, ::gotIt,
                        Modifier.weight(1f).semantics { stateDescription = "On to the next step" })
                } else BigButton("Reveal", Icons.Rounded.Visibility, BigKind.primary, ::reveal, Modifier.fillMaxWidth())
            }
        }
    }
}
