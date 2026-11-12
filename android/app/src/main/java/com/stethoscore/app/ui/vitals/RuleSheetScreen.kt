package com.stethoscore.app.ui.vitals

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ListAlt
import androidx.compose.material.icons.rounded.CheckCircleOutline
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.Memory
import androidx.compose.material.icons.rounded.PlaylistAdd
import androidx.compose.material.icons.rounded.RemoveCircle
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.RuleGroup
import com.stethoscore.app.data.RuleWriter
import com.stethoscore.app.data.StudyRule
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.editors.EcgLoader
import com.stethoscore.app.ui.editors.rememberLLMService
import com.stethoscore.app.ui.mock.BigButton
import com.stethoscore.app.ui.mock.BigKind
import com.stethoscore.app.ui.mock.BroadGap
import com.stethoscore.app.ui.mock.StudyTitleBar
import com.stethoscore.app.ui.mock.readableColumn
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.ward.StudyActionBar
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardEmptyState
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextField
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.WardWidthClass
import com.stethoscore.app.ui.ward.currentWindowShape
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlin.math.max

// A port of ios/RedPen/Features/Insight/RuleSheetView.swift: one
// line to remember for every question got wrong, grouped by subject,
// searchable, and shareable as plain text. Rules start as the question's own
// words. Where Android already allows a model call (LLMService.backend(): Pro,
// inside the $20 cap), "Write N rules with AI" rewrites the plain ones ten at
// a time and the sheet fills in as each batch comes back; with no model that
// button never shows and the plain rules stay.

/** The groups as shown: everything, or only the rules that match [query] (a subject match keeps all its rules). */
fun filterRuleGroups(groups: List<RuleGroup>, query: String): List<RuleGroup> {
    val term = query.trim()
    if (term.isEmpty()) return groups
    return groups.mapNotNull { group ->
        val subjectHit = group.subject.contains(term, ignoreCase = true)
        val hits = group.rules.filter { rule ->
            subjectHit || rule.text.contains(term, ignoreCase = true) || rule.detail.contains(term, ignoreCase = true)
                || rule.stem.contains(term, ignoreCase = true)
        }
        if (hits.isEmpty()) null else RuleGroup(group.subject, hits)
    }
}

@Composable fun RuleSheetScreen(store: StudyStore, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    var revision by remember { mutableIntStateOf(0) }
    var query by rememberSaveable { mutableStateOf("") }
    var note by remember { mutableStateOf<String?>(null) }
    var noteFailed by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    var writing by remember { mutableStateOf(false) }
    var writtenSoFar by remember { mutableIntStateOf(0) }
    var writingTotal by remember { mutableIntStateOf(0) }
    val llm = rememberLLMService()
    val sheet = remember(revision) { store.ruleSheet }
    val shown = remember(revision, query) { filterRuleGroups(StoreInsight.rulesBySubject(sheet), query) }
    val missed = remember(revision) { StoreInsight.missedWithoutRules(store).size }
    // rules still in their plain wording, newest first: what the model would rewrite
    val plain = remember(revision) { sheet.values.filter { !it.byAI }.sortedByDescending { it.date } }
    // the writer model, only where Android already allows a model call (Pro, inside the cap)
    val backend = remember(revision, writing) { llm.backend() }
    val canWrite = !writing && plain.isNotEmpty() && backend != null
    fun delete(id: String) { store.deleteRule(id); revision++ }

    /** Starts the model on every plain rule and returns at once; the sheet fills in as each batch comes back. */
    fun writeWithAI() {
        val model = backend
        if (writing || model == null || plain.isEmpty()) return
        val todo = plain
        writing = true
        writtenSoFar = 0
        writingTotal = todo.size
        note = null
        ruleWriting.launch {
            RuleWriter.write(todo, model) { lines ->
                store.applyWrittenRules(lines)
                writtenSoFar += lines.size
                revision++
            }
            val done = writtenSoFar
            writing = false
            noteFailed = done == 0
            note = if (done == 0) WRITE_FAILED else "Rewrote $done of ${todo.size} rule${if (todo.size == 1) "" else "s"}."
        }
    }

    Column(Modifier.fillMaxSize()) {
        StudyTitleBar("Rule sheet", onBack) {
            WardCircleButton(Icons.Rounded.Share, "Share", { shareText(context, StoreInsight.ruleSheetText(store.ruleSheet)) },
                enabled = sheet.isNotEmpty())
            if (sheet.isNotEmpty()) WardTextButton(if (editing) "Done" else "Edit", { editing = !editing }, kind = WardButtonKind.compact, fills = false)
        }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.readableColumn().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                WardTextField(query, { query = it }, Modifier.fillMaxWidth().padding(horizontal = 16.dp), placeholder = "Search rules")
                if (sheet.isEmpty()) ReaderFormSection {
                    Box(Modifier.fillMaxWidth().wardRowTile()) {
                        WardEmptyState(Icons.AutoMirrored.Rounded.ListAlt, "No rules yet",
                            "Every question you get wrong can leave one line here to remember. Add them from a quiz’s results, or from your recent mistakes below.")
                    }
                }
                note?.let { text ->
                    ReaderFormSection {
                        // read out when it appears; the whole tile is one element, at least one target tall
                        Row(Modifier.fillMaxWidth().testTag("ruleSheetNote")
                            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }
                            .heightIn(min = 48.dp).wardRowTile(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(if (noteFailed) Icons.Rounded.ErrorOutline else Icons.Rounded.CheckCircleOutline, null,
                                tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
                            Text(text, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
                        }
                    }
                }
                for (group in shown) ReaderFormSection(header = group.subject) {
                    for (rule in group.rules) RuleRow(rule, editing, context) { delete(rule.id) }
                }
                if (sheet.isNotEmpty() && shown.isEmpty()) ReaderFormSection {
                    Text("No rules match “$query”.", Modifier.fillMaxWidth().wardRowTile(),
                        style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
            }
        }
        // the slab only while there is something to do
        if (missed > 0 || canWrite || writing) StudyActionBar {
            if (writing) RuleWritingProgress(writtenSoFar, writingTotal)
            else RuleSheetButtons(missed, if (canWrite) plain.size else 0, onAdd = {
                val added = StoreInsight.addRulesForMissed(store)
                noteFailed = false
                note = "Added $added rule${if (added == 1) "" else "s"}."
                revision++
            }, onWrite = ::writeWithAI)
        }
    }
}

/** What the model's run ends on when no rule came back: nothing was changed. */
internal const val WRITE_FAILED = "The model did not answer in a usable way; your rules are unchanged. Try again later."

/**
 * The model's run belongs to the app, not to the sheet: the work goes on, and
 * what it writes lands in the store, when the student goes elsewhere (iOS's
 * Task in the view; the progress says "You can keep using the app while it works").
 */
private val ruleWriting = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

/**
 * The rule sheet's slab (RuleSheetButtons): "Write N rules with AI" beside
 * "Add N from your recent mistakes", the add button the main one, at the
 * trailing end. Stacked on a phone, where both would otherwise wrap.
 * [plain] is the number of plain rules the model could rewrite: 0 when there is
 * no model or nothing to rewrite.
 */
@Composable internal fun RuleSheetButtons(missed: Int, plain: Int, onAdd: () -> Unit, onWrite: () -> Unit) {
    val shape = currentWindowShape()
    val wide = shape.widthClass != WardWidthClass.compact
    val writeTitle = "Write $plain rule${if (plain == 1) "" else "s"} with AI"
    val addTitle = "Add $missed from your recent mistakes"
    val hint = "Rewrites each plain rule as one exam-style line, ten at a time"
    @Composable fun write(modifier: Modifier) =
        BigButton(writeTitle, Icons.Rounded.Edit, BigKind.secondary, onWrite, modifier.semantics { stateDescription = hint })
    @Composable fun add(modifier: Modifier) = BigButton(addTitle, Icons.Rounded.PlaylistAdd, BigKind.primary, onAdd, modifier)
    when {
        plain > 0 && missed > 0 && wide -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            write(Modifier.weight(1f))
            BroadGap(shape.isBroad)
            add(Modifier.weight(1f))
        }
        plain > 0 && missed > 0 -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            write(Modifier.fillMaxWidth())
            add(Modifier.fillMaxWidth())
        }
        plain > 0 -> write(Modifier.fillMaxWidth())
        else -> add(Modifier.fillMaxWidth())
    }
}

/**
 * While the model rewrites the rules: how many so far, and that the app can
 * still be used (RuleWritingProgress). It speaks as one element, with the
 * count as its progress.
 */
@Composable internal fun RuleWritingProgress(done: Int, total: Int) {
    val fraction = done.toDouble() / max(1, total)
    val spoken = "Writing rules with AI, $done of $total. Ten at a time. You can keep using the app while it works."
    Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().heightIn(min = 48.dp).testTag("ruleWritingProgress")
        .clearAndSetSemantics {
            contentDescription = spoken
            progressBarRangeInfo = ProgressBarRangeInfo(done.toFloat(), 0f..max(1, total).toFloat())
        }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            EcgLoader()
            Text("Writing rules with AI · $done of $total", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold, mono = true),
                color = wardColor(WardToken.ink))
        }
        EcgStrip(fraction)
        Text("Ten at a time. You can keep using the app while it works.", style = WardTextStyle.caption.textStyle(),
            color = wardColor(WardToken.inkSecondary))
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable private fun RuleRow(rule: StudyRule, editing: Boolean, context: Context, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth().wardRowTile().combinedClickable(role = Role.Button, onClick = {}, onLongClick = { menu = true },
            onLongClickLabel = "Copy or delete"),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (editing) Icon(Icons.Rounded.RemoveCircle, "Delete", tint = wardColor(WardToken.danger),
                modifier = Modifier.minimumInteractiveComponentSize().size(44.dp).combinedClickable(role = Role.Button, onClick = onDelete).padding(10.dp))
            Column(Modifier.weight(1f).padding(vertical = 2.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(rule.text, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
                if (rule.detail.isNotEmpty()) Text(rule.detail, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                if (rule.byAI || rule.isExample == true) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (rule.byAI) WardChip("Written with AI", tone = WardTone.Blue, icon = Icons.Rounded.Memory)
                    if (rule.isExample == true) WardChip("Example data", tone = WardTone.Grey)
                }
            }
        }
        DropdownMenu(menu, { menu = false }, containerColor = wardColor(WardToken.raised)) {
            DropdownMenuItem({ Text("Copy", color = wardColor(WardToken.ink)) }, {
                menu = false
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.setPrimaryClip(ClipData.newPlainText("Rule", rule.text))
            }, leadingIcon = { Icon(Icons.Rounded.ContentCopy, null, tint = wardColor(WardToken.ink)) })
            DropdownMenuItem({ Text("Delete", color = wardColor(WardToken.danger)) }, { menu = false; onDelete() },
                leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = wardColor(WardToken.danger)) })
        }
    }
}

/** The system share sheet with [text] (iOS ShareLink). */
internal fun shareText(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}
