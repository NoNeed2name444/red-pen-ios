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
import androidx.compose.runtime.mutableStateMapOf
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
import com.stethoscore.app.accuracy.AccuracyItem
import com.stethoscore.app.accuracy.AccuracyKind
import com.stethoscore.app.accuracy.AccuracyRules
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
import kotlin.math.exp
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
// Not here, for want of the feature on Android (T0115b): the ledger kept on
// disk (a check is remembered while the app runs), the trained weights, the
// source proof and vignette route (so nothing is Verified on Android yet),
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

/** An item's grade (iOS AccuracyGrade). */
enum class AccuracyGrade(val title: String) {
    verified("Verified"), checked("Checked"), check("Check this"), flagged("Flagged"), unchecked("Not checked yet");

    /** server/accuracy-model.js TIER_MEANINGS, word for word. */
    val meaning: String? get() = when (this) {
        verified -> "Verified means every fact was matched word for word to an open source, and every step was checked."
        checked -> "Checked means it passed our checks and agreement tests, but it isn't fully proven yet."
        else -> null
    }

    val tone: WardTone get() = when (this) {
        verified -> WardTone.Green
        checked -> WardTone.Blue
        check -> WardTone.Warning
        flagged -> WardTone.Danger
        unchecked -> WardTone.Grey
    }

    val icon: ImageVector get() = when (this) {
        verified -> Icons.Rounded.Verified
        checked -> Icons.Rounded.CheckCircle
        check -> Icons.AutoMirrored.Rounded.Help
        flagged -> Icons.Rounded.Warning
        unchecked -> Icons.Rounded.Schedule
    }
}

/** One checker model's vote on one item, as the server returns it (iOS AccuracyVote). */
data class AccuracyVote(val model: String, val risk: Int, val answer: String? = null, val evidence: String = "none",
                        val cites: List<String> = emptyList(), val issues: List<String> = emptyList(), val blind: Boolean? = null)

/** A source the checkers were shown (iOS AccuracyEvidence). */
data class AccuracyEvidence(val id: String, val source: String, val title: String, val url: String)

/** What a check said about one item: its votes and the sources shown. */
data class AccuracyRecord(val votes: List<AccuracyVote>, val evidence: List<AccuracyEvidence>, val sourceMatch: Double? = null)

/** An item's verdict: the grade, P(accurate), the rule hits and the record (iOS AccuracyAssessment). */
data class AccuracyAssessment(val grade: AccuracyGrade, val probability: Double, val rules: List<AccuracyRules.Hit>, val record: AccuracyRecord?)

/**
 * The app's accuracy model, as iOS Shared/Accuracy/AccuracyModel.swift has
 * it: the same features, the bundled prior-1 weights and the same verdict,
 * with no source proof or vignette route on Android.
 */
object AccuracyGrading {
    /** The bundled weights (AccuracyModel.defaultJSON, kept identical to server/accuracy-model.js). */
    val weights: Map<String, Double> = mapOf(
        "bias" to 3.0, "rule_severe" to -2.5, "rule_minor" to -0.4, "risk_max" to -2.5, "risk_mean" to -1.5,
        "flag_frac" to -2.0, "disagree" to -0.5, "voters" to 0.3, "key_disagree" to -2.5, "ev_support" to 0.8,
        "ev_contradict" to -2.5, "ev_count" to 0.1, "source_match" to 0.8, "no_source" to -0.3, "no_models" to -1.5,
        "kind_mcq" to 0.0, "kind_card" to 0.0, "kind_case" to 0.0, "kind_osce" to 0.0, "kind_page" to 0.0,
    )
    const val version = "prior-1"
    const val verifiedCut = 0.85
    const val flaggedCut = 0.4
    const val minVerifyVoters = 3

    private fun clamp01(x: Double): Double = minOf(1.0, maxOf(0.0, x))

    /** server/accuracy-model.js familyOf, pattern for pattern. */
    private val families = listOf(
        "google" to "gemini|gemma", "openai" to "gpt|openai", "nvidia" to "nemotron|nvidia", "meta" to "llama|\\bmeta\\b",
        "alibaba" to "qwen", "mistral" to "mistral|mixtral", "deepseek" to "deepseek", "anthropic" to "claude|anthropic",
        "baichuan" to "baichuan", "microsoft" to "\\bphi-|microsoft", "apple" to "\\bapple\\b",
    )

    fun familyOf(model: String): String {
        val m = model.lowercase()
        for ((family, pattern) in families) if (Regex(pattern).containsMatchIn(m)) return family
        return m.ifEmpty { "unknown" }
    }

    /** iOS AccuracyModel.featureValues (no source proof, no vignette). */
    fun features(kind: AccuracyKind, rules: List<AccuracyRules.Hit>, votes: List<AccuracyVote>, evidenceCount: Int,
                 sourceMatch: Double?, keyLetter: String?): Map<String, Double> {
        val risks = votes.map { clamp01((it.risk - 1) / 3.0) }
        val flags = votes.map { it.risk >= 3 }
        val answered = votes.filter { v -> v.answer?.let { it.length == 1 && "ABCDEFGHIJ".contains(it) } == true }
        val n = votes.size.toDouble()
        val f = mutableMapOf<String, Double>()
        f["bias"] = 1.0
        f["rule_severe"] = minOf(2, rules.count { it.isSevere }).toDouble()
        f["rule_minor"] = minOf(3, rules.count { !it.isSevere }).toDouble()
        f["risk_max"] = risks.maxOrNull() ?: 0.0
        f["risk_mean"] = if (risks.isEmpty()) 0.0 else risks.sum() / n
        f["flag_frac"] = if (flags.isEmpty()) 0.0 else flags.count { it } / n
        f["disagree"] = if (flags.size > 1 && flags.contains(true) && flags.contains(false)) 1.0 else 0.0
        f["voters"] = minOf(3, votes.size) / 3.0
        f["key_disagree"] = if (kind == AccuracyKind.mcq && keyLetter != null && answered.isNotEmpty())
            answered.count { it.answer != keyLetter }.toDouble() / answered.size else 0.0
        f["ev_support"] = if (votes.isEmpty()) 0.0 else votes.count { it.evidence == "supports" } / n
        f["ev_contradict"] = if (votes.isEmpty()) 0.0 else votes.count { it.evidence == "contradicts" } / n
        f["ev_count"] = minOf(5, evidenceCount) / 5.0
        f["source_match"] = sourceMatch?.let(::clamp01) ?: 0.0
        f["no_source"] = if (sourceMatch == null) 1.0 else 0.0
        f["source_proof"] = 0.0
        f["no_models"] = if (votes.isEmpty()) 1.0 else 0.0
        f["kind_mcq"] = if (kind == AccuracyKind.mcq) 1.0 else 0.0
        f["kind_card"] = if (kind == AccuracyKind.card) 1.0 else 0.0
        f["kind_case"] = if (kind == AccuracyKind.case) 1.0 else 0.0
        f["kind_osce"] = if (kind == AccuracyKind.osce) 1.0 else 0.0
        f["kind_page"] = if (kind == AccuracyKind.page || kind == AccuracyKind.fact || kind == AccuracyKind.note) 1.0 else 0.0
        f["families"] = votes.filter { it.risk < 3 }.map { familyOf(it.model) }.toSet().size.toDouble()
        if (kind == AccuracyKind.mcq && keyLetter != null) {
            val byLetter = mutableMapOf<String, MutableSet<String>>()
            for (v in answered) if (v.blind == true) v.answer?.let { byLetter.getOrPut(it) { mutableSetOf() } += familyOf(v.model) }
            f["blind_agree"] = (byLetter[keyLetter]?.size ?: 0).toDouble()
            f["blind_against"] = (byLetter.filterKeys { it != keyLetter }.values.maxOfOrNull { it.size } ?: 0).toDouble()
            f["blind_split"] = if (byLetter.size > 1) 1.0 else 0.0
            f["blind_dissent"] = byLetter.filterKeys { it != keyLetter }.values.flatten().toSet().size.toDouble()
        }
        f["flag_families"] = votes.filter { it.risk >= 3 }.map { familyOf(it.model) }.toSet().size.toDouble()
        return f
    }

    fun probability(f: Map<String, Double>): Double {
        var z = 0.0
        for ((name, w) in weights) z += (f[name] ?: 0.0) * w
        z = maxOf(-40.0, minOf(40.0, z))
        return 1 / (1 + exp(-z))
    }

    /** iOS AccuracyModel.grade, rule for rule (no vignette route). */
    fun grade(p: Double, f: Map<String, Double>): AccuracyGrade {
        val severe = (f["rule_severe"] ?: 0.0) > 0
        if ((f["no_models"] ?: 1.0) > 0) return if (severe) AccuracyGrade.flagged else AccuracyGrade.unchecked
        val need = minVerifyVoters.toDouble()
        val question = (f["kind_mcq"] ?: 0.0) == 1.0
        if (question && (f["blind_against"] ?: 0.0) >= need && (f["blind_agree"] ?: 0.0) == 0.0) return AccuracyGrade.flagged
        if (severe && p < flaggedCut) return AccuracyGrade.flagged
        if (!question && (f["flag_families"] ?: 0.0) >= need && (f["flag_frac"] ?: 0.0) == 1.0 && p < flaggedCut) return AccuracyGrade.flagged
        val voters = ((f["voters"] ?: 0.0) * 3).roundToInt()
        val backed = (f["source_proof"] ?: 0.0) == 1.0
        val independent = (f["families"] ?: 0.0) >= need
        val unanimous = (f["flag_frac"] ?: 0.0) == 0.0 && (f["ev_contradict"] ?: 0.0) == 0.0
        val clean = !severe && (f["rule_minor"] ?: 0.0) == 0.0
        val solved = !question || ((f["blind_agree"] ?: 0.0) >= need && (f["blind_dissent"] ?: 0.0) == 0.0)
        if (p >= verifiedCut && clean && voters >= minVerifyVoters && backed && independent && unanimous && solved) return AccuracyGrade.verified
        return AccuracyGrade.check
    }

    /** iOS AccuracyLedger.assess, for an item and what a check said of it. */
    fun assess(item: AccuracyItem, record: AccuracyRecord?): AccuracyAssessment {
        val rules = AccuracyRules.hits(item)
        val key = if (item.kind == AccuracyKind.mcq && item.key in item.options.indices) AccuracyItem.letter(item.key) else null
        val f = features(item.kind, rules, record?.votes.orEmpty(), record?.evidence?.size ?: 0,
            record?.sourceMatch ?: AccuracyRules.sourceMatch(item), key)
        val p = probability(f)
        return AccuracyAssessment(grade(p, f), p, rules, record)
    }

    /** What the worker's /accuracy/check reply says of item [id], or null when it holds no vote on it. */
    fun record(reply: JSONObject?, id: String): AccuracyRecord? {
        val items = reply?.optJSONArray("items") ?: return null
        val found = (0 until items.length()).mapNotNull { items.optJSONObject(it) }.firstOrNull { it.optString("id") == id } ?: return null
        fun strings(o: JSONObject, key: String): List<String> =
            o.optJSONArray(key)?.let { a -> (0 until a.length()).map { a.optString(it) } }.orEmpty()
        val votes = found.optJSONArray("votes")?.let { a ->
            (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map { v ->
                AccuracyVote(v.optString("model"), v.optInt("risk", 1), v.optString("answer").ifEmpty { null },
                    v.optString("evidence", "none"), strings(v, "cites"), strings(v, "issues"),
                    if (v.has("blind")) v.optBoolean("blind") else null)
            }
        }.orEmpty()
        if (votes.isEmpty()) return null
        val evidence = found.optJSONArray("evidence")?.let { a ->
            (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map { e ->
                AccuracyEvidence(e.optString("id"), e.optString("source"), e.optString("title"), e.optString("url"))
            }
        }.orEmpty()
        val match = if (found.has("sourceMatch")) found.optDouble("sourceMatch") else null
        return AccuracyRecord(votes, evidence, match)
    }

    /** iOS AccuracyWhySheet.riskWords. */
    fun riskWords(risk: Int): String = when (risk) {
        1 -> "No error"
        2 -> "Minor"
        3 -> "Could mislead"
        else -> "Wrong"
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
        "Checked against this ${kind.noun}'s lecture and current literature by free checker models voting, with rule checks for doses, lab values and contradictions. Scored by Stethoscore's accuracy model ($version). Still use your judgement."
}

/** What the checks said while the app runs, by the item's content (iOS AccuracyStore's ledger, not kept on disk). */
internal object AccuracySeen {
    val records = mutableStateMapOf<String, AccuracyRecord>()
}

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
    val assessment = remember(item, record) { AccuracyGrading.assess(item, record) }

    fun checkNow() {
        if (checking) return
        checking = true
        scope.launch {
            val (said, reply) = AccuracyCheck.checkNow(item, llm)
            AccuracyGrading.record(reply, item.id)?.let { AccuracySeen.records[item.contentHash] = it }
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
                                Text(AccuracyGrading.ruleTitle(hit.rule), style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = tone.ink())
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
                            Text("[" + e.id + "] " + e.source, style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.primaryInk))
                            Text(e.title, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.ink), maxLines = 3)
                        }
                    }
                }
            }
        }
    }
}
