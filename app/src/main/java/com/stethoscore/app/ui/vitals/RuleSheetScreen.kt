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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ListAlt
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.CheckCircleOutline
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.PlaylistAdd
import androidx.compose.material.icons.rounded.RemoveCircle
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.RuleGroup
import com.stethoscore.app.data.StudyRule
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.mock.BigButton
import com.stethoscore.app.ui.mock.BigKind
import com.stethoscore.app.ui.mock.StudyActionBar
import com.stethoscore.app.ui.mock.StudyTitleBar
import com.stethoscore.app.ui.mock.readableColumn
import com.stethoscore.app.ui.sources.ReaderEmptyState
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextField
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.wardColor

// A port of upstream/ios/RedPen/Features/Insight/RuleSheetView.swift: one
// line to remember for every question got wrong, grouped by subject,
// searchable, and shareable as plain text. Rules start as the question's own
// words. Android has no writer model, so "Write N rules with AI" and its
// progress never show; rules written with AI elsewhere (a restored backup)
// keep their chip.

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
    var editing by remember { mutableStateOf(false) }
    val sheet = remember(revision) { store.ruleSheet }
    val shown = remember(revision, query) { filterRuleGroups(StoreInsight.rulesBySubject(sheet), query) }
    val missed = remember(revision) { StoreInsight.missedWithoutRules(store).size }
    fun delete(id: String) { store.deleteRule(id); revision++ }

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
                        ReaderEmptyState(Icons.AutoMirrored.Rounded.ListAlt, "No rules yet",
                            "Every question you get wrong can leave one line here to remember. Add them from a quiz’s results, or from your recent mistakes below.")
                    }
                }
                note?.let { text ->
                    ReaderFormSection {
                        Row(Modifier.fillMaxWidth().wardRowTile(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.CheckCircleOutline, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
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
        if (missed > 0) StudyActionBar {
            BigButton("Add $missed from your recent mistakes", Icons.Rounded.PlaylistAdd, BigKind.primary, {
                val added = StoreInsight.addRulesForMissed(store)
                note = "Added $added rule${if (added == 1) "" else "s"}."
                revision++
            })
        }
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
                modifier = Modifier.size(44.dp).padding(10.dp).combinedClickable(role = Role.Button, onClick = onDelete))
            Column(Modifier.weight(1f).padding(vertical = 2.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(rule.text, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
                if (rule.detail.isNotEmpty()) Text(rule.detail, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                if (rule.byAI || rule.isExample == true) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (rule.byAI) WardChip("Written with AI", tone = WardTone.Blue, icon = Icons.Rounded.AutoAwesome)
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
