package com.stethoscore.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.HourglassTop
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.VerifiedUser
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.automirrored.rounded.Help
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.stethoscore.app.accuracy.AccuracyAssessment
import com.stethoscore.app.accuracy.AccuracyEvidence
import com.stethoscore.app.accuracy.AccuracyGrade
import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.accuracy.AccuracyKind
import com.stethoscore.app.accuracy.AccuracyLedger
import com.stethoscore.app.accuracy.AccuracyModel
import com.stethoscore.app.accuracy.AccuracyRecord
import com.stethoscore.app.accuracy.AccuracyVote
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.llm.AccuracyCheck
import com.stethoscore.app.ui.editors.rememberLLMService
import com.stethoscore.app.ui.exam.ExamSheet
import com.stethoscore.app.ui.exam.plainRowTile
import com.stethoscore.app.ui.sources.ReaderDoneButton
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import kotlinx.coroutines.launch
import org.json.JSONObject
import kotlin.math.roundToInt

// Check accuracy in a study screen's More menu (iOS Shared/Theme.swift
// StudyMoreMenu and AccuracyAsk, at Theme.swift:767-875) and the sheet it
// opens (iOS Features/Support/AccuracyBadge.swift AccuracyWhySheet, :99-337):
// the result, the rule checks, the checker models' votes and the sources they
// were shown, with Check now; opened from Check accuracy, an item never
// checked is checked at once (checksWhenUnchecked). The grade is
// AccuracyModel's (Shared/Accuracy/AccuracyModel.swift: featureValues,
// probability and grade, with the bundled prior-1 weights).
//
// The engine is in accuracy/ (AccuracyModel, AccuracyLedger); this sheet reads
// it. Not wired here yet (T0115b): the ledger kept on disk (a check is
// remembered while the app runs, in AccuracySeen), the trained weights, the
// source proof and vignette route (the sheet keeps only the votes, the sources
// and the lecture match of a reply, so nothing is Verified on Android yet),
// Accept the correction, and Report an error / Report a problem
// (/accuracy/report).

/**
 * What Check accuracy looks at on a study screen (iOS AccuracyAsk): the
 * instruction the item was written to, and the item on screen at the moment
 * of the tap. [text] is null until the item may be checked (a question once
 * answered); [item] is the item as the accuracy engine reads it.
 */
class AccuracyAsk(val instruction: String, val item: (() -> AccuracyItem?)? = null, val text: () -> String?) {
    /** The structured item, else the text on screen, else the set by name (iOS reportItem(in:)). */
    fun reportItem(set: StudySet): AccuracyItem {
        item?.invoke()?.let { return it }
        val shown = text() ?: ""
        return AccuracyItem(set.id, AccuracyKind.fact, text = shown.ifEmpty { "Set: " + set.name })
    }

    /** The item to verify, when the tap is to open the sheet (iOS: only once text() is not empty). */
    fun verifying(set: StudySet): AccuracyItem? = text()?.takeIf { it.isNotEmpty() }?.let { reportItem(set) }
}

/** The tone a grade is drawn in (the grade itself is accuracy/AccuracyModel.kt's). */
internal val AccuracyGrade.tone: WardTone get() = when (this) {
    AccuracyGrade.verified -> WardTone.Green
    AccuracyGrade.checked -> WardTone.Blue
    AccuracyGrade.check -> WardTone.Warning
    AccuracyGrade.flagged -> WardTone.Danger
    AccuracyGrade.unchecked -> WardTone.Grey
}

/** The symbol a grade is drawn with (iOS AccuracyGrade.symbol). */
internal val AccuracyGrade.icon: ImageVector get() = when (this) {
    AccuracyGrade.verified -> Icons.Rounded.Verified
    AccuracyGrade.checked -> Icons.Rounded.CheckCircle
    AccuracyGrade.check -> Icons.AutoMirrored.Rounded.Help
    AccuracyGrade.flagged -> Icons.Rounded.Warning
    AccuracyGrade.unchecked -> Icons.Rounded.Schedule
}

/**
 * What the sheet says about a grade and keeps of a reply. The grading itself
 * is the engine's (AccuracyLedger.assess over AccuracyModel's prior-1 weights
 * and verdict).
 */
object AccuracyGrading {
    /** iOS AccuracyWhySheet.riskWords. */
    fun riskWords(risk: Int): String = when (risk) {
        1 -> "No error"
        2 -> "Minor"
        3 -> "Could mislead"
        else -> "Wrong"
    }

    /** What the worker's /accuracy/check reply says of [item], or null when it holds no vote on it. */
    fun record(reply: JSONObject?, item: AccuracyItem): AccuracyRecord? {
        val id = item.id
        val items = reply?.optJSONArray("items") ?: return null
        val found = (0 until items.length()).mapNotNull { items.optJSONObject(it) }.firstOrNull { it.optString("id") == id } ?: return null
        fun strings(o: JSONObject, key: String): List<String> =
            o.optJSONArray(key)?.let { a -> (0 until a.length()).map { a.optString(it) } }.orEmpty()
        val votes = found.optJSONArray("votes")?.let { a ->
            (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map { v ->
                AccuracyVote(model = v.optString("model"), risk = v.optInt("risk", 1), answer = v.optString("answer").ifEmpty { null },
                    evidence = v.optString("evidence", "none"), cites = strings(v, "cites"), issues = strings(v, "issues"),
                    blind = if (v.has("blind")) v.optBoolean("blind") else null)
            }
        }.orEmpty()
        if (votes.isEmpty()) return null
        val evidence = found.optJSONArray("evidence")?.let { a ->
            (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map { e ->
                AccuracyEvidence(e.optString("id"), e.optString("source"), e.optString("title"), e.optString("url"))
            }
        }.orEmpty()
        val match = if (found.has("sourceMatch")) found.optDouble("sourceMatch") else null
        return AccuracyRecord(hash = item.contentHash, votes = votes, evidence = evidence, sourceMatch = match)
    }

    /** iOS AccuracyWhySheet.ruleTitle. */
    fun ruleTitle(rule: String): String = when (rule) {
        "dose-range" -> "Dose outside the usual range"
        "lab-implausible" -> "Impossible lab value (wrong unit?)"
        "lab-unit" -> "Unusual unit"
        "reference-range" -> "Wrong normal range"
        "key-explanation-conflict" -> "Key and explanation disagree"
        "key-called-wrong" -> "Explanation calls the key wrong"
        "duplicate-option" -> "Duplicate options"
        "no-key" -> "No valid key"
        "non-answer-position", "all-and-none", "all-above-contradiction" -> "\"All/none of the above\""
        "negation-mismatch" -> "NOT/EXCEPT question"
        "numbers-disagree" -> "Numbers disagree"
        "direction-conflict" -> "Contradiction"
        else -> rule
    }

    /** iOS AccuracyWhySheet.explanation. */
    fun explanation(a: AccuracyAssessment): String {
        val percent = (a.probability * 100).roundToInt()
        return when (a.grade) {
            AccuracyGrade.verified -> "The checkers agree it is right, and the sources support it ($percent% likely accurate)."
            AccuracyGrade.checked -> (a.grade.meaning ?: "") + " ($percent% likely accurate)"
            AccuracyGrade.check -> "Something about it is uncertain - read the reasons below before you rely on it ($percent% likely accurate)."
            AccuracyGrade.flagged -> if (a.record == null) "A rule check found a likely error." else "The checkers found a likely error ($percent% likely accurate)."
            AccuracyGrade.unchecked -> "Not checked by the models yet. Rule checks found nothing; the rest of the check needs Stethoscore Cloud."
        }
    }

    /** The Result section's footer. */
    fun footer(kind: AccuracyKind): String =
        "Checked against this ${kind.noun}'s lecture and current literature by free checker models voting, with rule checks for doses, lab values and contradictions. Scored by Stethoscore's accuracy model (${AccuracyModel.bundled.version}). Still use your judgement."
}

/** What the checks said while the app runs, by the item's content (accuracy/AccuracyLedger.kt). */
internal typealias AccuracySeen = com.stethoscore.app.accuracy.AccuracySeen

/** The study screen's More circle and its menu (iOS StudyMoreMenu's Menu), for a screen with no menu of its own yet. */
@Composable internal fun StudyMoreButton(enabled: Boolean = true, items: @Composable ColumnScope.(close: () -> Unit) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        WardCircleButton(Icons.Rounded.MoreHoriz, "More", { open = true }, enabled = enabled)
        DropdownMenu(open, { open = false }, containerColor = wardColor(WardToken.raised)) { items { open = false } }
    }
}

/** Check accuracy, as a More menu's item: opens the sheet once the item may be checked (iOS StudyMoreMenu). */
@Composable internal fun CheckAccuracyMenuItem(ask: AccuracyAsk, set: StudySet, close: () -> Unit, open: (AccuracyItem) -> Unit) {
    DropdownMenuItem(text = { Text("Check accuracy") }, leadingIcon = { Icon(Icons.Rounded.VerifiedUser, null) },
        onClick = { close(); ask.verifying(set)?.let(open) }, modifier = Modifier.testTag("checkAccuracy"))
}

/** The grade as a chip: a symbol and a word in the grade's tone, or Checking… (iOS AccuracyBadgeFace). */
@Composable internal fun AccuracyBadgeFace(grade: AccuracyGrade, checking: Boolean = false) {
    if (checking) WardChip("Checking…", tone = WardTone.Grey, icon = Icons.Rounded.HourglassTop)
    else WardChip(grade.title, tone = grade.tone, icon = grade.icon)
}

/**
 * Why an item has its grade (iOS AccuracyWhySheet): the result with Check
 * now, the rule checks, the checker models' votes and the sources they were
 * shown. [checksWhenUnchecked]: opened from Check accuracy, an item never
 * checked is checked at once.
 */
@Composable internal fun AccuracyWhySheet(item: AccuracyItem, checksWhenUnchecked: Boolean = false, onDone: () -> Unit) {
    val llm = rememberLLMService()
    val scope = rememberCoroutineScope()
    var checking by remember(item) { mutableStateOf(false) }
    var message by remember(item) { mutableStateOf<String?>(null) }
    val record = AccuracySeen.records[item.contentHash]
    val assessment = remember(item, record) { AccuracyLedger.assess(item, record) }

    fun checkNow() {
        if (checking) return
        checking = true
        scope.launch {
            val (said, reply) = AccuracyCheck.checkNow(item, llm)
            AccuracyGrading.record(reply, item)?.let { AccuracySeen.records[item.contentHash] = it }
            message = said
            checking = false
        }
    }
    LaunchedEffect(item) {
        if (checksWhenUnchecked && assessment.grade == AccuracyGrade.unchecked && !checking) checkNow()
    }

    ExamSheet(onDone) {
        BackHandler(onBack = onDone)
        Column(Modifier.fillMaxSize()) {
            ReaderNavBar("Accuracy", trailing = { ReaderDoneButton(onClick = onDone) })
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(top = 4.dp, bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp)) {
                ReaderFormSection(header = "Result", footer = AccuracyGrading.footer(item.kind)) {
                    Column(Modifier.fillMaxWidth().plainRowTile(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        AccuracyBadgeFace(assessment.grade, checking)
                        Text(AccuracyGrading.explanation(assessment), style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.ink))
                        if (assessment.grade == AccuracyGrade.unchecked && !checking) {
                            WardTextButton("Check now", ::checkNow, kind = WardButtonKind.compact, fills = false)
                        }
                        message?.let { Text(it, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary)) }
                    }
                }
                if (assessment.rules.isNotEmpty()) ReaderFormSection(header = "Rule checks") {
                    assessment.rules.forEach { hit ->
                        Column(Modifier.fillMaxWidth().plainRowTile(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            val tone = if (hit.isSevere) WardTone.Danger else WardTone.Warning
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(Icons.Rounded.Warning, null, Modifier.size(14.dp), tint = tone.color())
                                Text(AccuracyGrading.ruleTitle(hit.rule), style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
                            }
                            Text(hit.detail, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.ink))
                        }
                    }
                }
                val votes = assessment.record?.votes.orEmpty()
                if (votes.isNotEmpty()) ReaderFormSection(header = "Checker models") {
                    votes.forEach { vote ->
                        Column(Modifier.fillMaxWidth().plainRowTile(), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(vote.model, Modifier.weight(1f), style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
                                WardChip(AccuracyGrading.riskWords(vote.risk), tone = if (vote.risk >= 3) WardTone.Danger else WardTone.Green,
                                    icon = if (vote.risk >= 3) Icons.Rounded.Cancel else Icons.Rounded.CheckCircle)
                            }
                            val answer = vote.answer
                            if (answer != null && item.kind == AccuracyKind.mcq) Text("Its own answer: $answer",
                                style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                            vote.issues.forEach { Text(it, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.ink)) }
                            if (vote.cites.isNotEmpty()) Text("Cites " + vote.cites.joinToString(", "),
                                style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
                        }
                    }
                }
                val evidence = assessment.record?.evidence.orEmpty()
                if (evidence.isNotEmpty()) ReaderFormSection(header = "Sources the checkers were shown") {
                    val uri = LocalUriHandler.current
                    evidence.forEach { e ->
                        Column(Modifier.fillMaxWidth().plainRowTile().clickable(role = Role.Button) { runCatching { uri.openUri(e.url) } },
                            verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("[" + e.id + "] " + e.source, style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
                            Text(e.title, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.ink), maxLines = 3)
                        }
                    }
                }
            }
        }
    }
}
