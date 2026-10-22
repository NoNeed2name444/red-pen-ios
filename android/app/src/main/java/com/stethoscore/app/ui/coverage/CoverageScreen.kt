package com.stethoscore.app.ui.coverage

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Contrast
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.School
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.coverage.AreaCoverage
import com.stethoscore.app.coverage.CoverageEngine
import com.stethoscore.app.coverage.CoverageStatus
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.coverage.SubtopicCoverage
import com.stethoscore.app.coverage.Syllabus
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.ui.QuizPrefs
import com.stethoscore.app.ui.editors.EcgLoader
import com.stethoscore.app.ui.mock.ChipBox
import com.stethoscore.app.ui.mock.StudyTitleBar
import com.stethoscore.app.ui.mock.readableColumn
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.wardRowTile
import com.stethoscore.app.ui.ward.StudyActionBar
import com.stethoscore.app.ui.ward.WardBanner
import com.stethoscore.app.ui.ward.WardButtonBox
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardSectionLabel
import com.stethoscore.app.ui.ward.WardSegmented
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardRelief
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

// A port of ios/RedPen/Features/Coverage/CoverageView.swift: what
// the exam covers that the library does not - the exam's syllabus, area by
// area, each subtopic marked covered, thin or not covered by the keyword
// check (CoverageEngine). Not here: the AI check (CoverageChecker: the
// cloud needs a sign-in Android lacks, so its blocker shows), a specific
// exam's weighted blueprint, and writing questions with a writer: Generate
// questions opens New set ready for an MCQ set on the gap instead, and
// Choose a specific exam… opens the exam picker.

object CoverageWords {
    /** "PLAB", or "General" for general revision: the exam menu's label. */
    fun shortName(exam: ExamTrack): String = if (exam == ExamTrack.general) "General" else exam.rawValue.uppercase(Locale.ROOT)

    /** What the keyword engine found, in one line. */
    fun detail(sub: SubtopicCoverage): String {
        if (sub.evidence <= 0) return "Nothing in your library mentions it"
        val parts = mutableListOf("${sub.evidence} item${if (sub.evidence == 1) "" else "s"}")
        parts.add(if (sub.practice == 0) "no questions or cards" else "${sub.practice} to practise")
        sub.accuracy?.let { parts.add("${Math.round(it * 100)}% right of ${sub.answered}") }
        return parts.joinToString(" · ")
    }

    fun tone(status: CoverageStatus): WardTone = when (status) {
        CoverageStatus.covered -> WardTone.Green
        CoverageStatus.thin -> WardTone.Warning
        CoverageStatus.notCovered -> WardTone.Danger
    }

    fun icon(status: CoverageStatus): ImageVector = when (status) {
        CoverageStatus.covered -> Icons.Rounded.CheckCircle
        CoverageStatus.thin -> Icons.Rounded.Contrast
        CoverageStatus.notCovered -> Icons.Rounded.Cancel
    }

    /** The summary's footnote: where the syllabus is condensed from. */
    fun summaryFooter(track: ExamTrack): String =
        "Condensed from ${Syllabus.blueprint(track)}, so approximate: it shows where your gaps probably are, not what the exam will ask. Tap a count to show only those."

    /** Whether a row is on show: the picked count's status, or Everything / Gaps only. */
    fun passes(status: CoverageStatus, filter: CoverageStatus?, gapsOnly: Boolean): Boolean =
        if (filter != null) status == filter else !gapsOnly || status != CoverageStatus.covered
}

@Composable fun CoverageScreen(store: StudyStore, onBack: () -> Unit, onNewSet: ((com.stethoscore.app.exam.NewSetPreset) -> Unit)? = null) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    var track by remember { mutableStateOf(QuizPrefs.track(context)) }
    var areas by remember { mutableStateOf<List<AreaCoverage>>(emptyList()) }
    var computing by remember { mutableStateOf(true) }
    var gapsOnly by remember { mutableStateOf(false) }
    var statusFilter by remember { mutableStateOf<CoverageStatus?>(null) }
    var menu by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    var picking by remember { mutableStateOf(false) }
    if (picking) {
        com.stethoscore.app.ui.exam.ExamPickerScreen(store, { picking = false; track = QuizPrefs.track(context) })
        return
    }
    val edited = store.library.maxOfOrNull { it.updatedAt } ?: 0L
    val answers = store.answerHistory.values.sumOf { it.size }
    // re-run the keyword check when the exam, the library or the answers change - not on every redraw
    LaunchedEffect(track, store.library.size, edited, answers) {
        computing = true
        val library = store.library
        val history = store.answerHistory
        areas = withContext(Dispatchers.Default) { CoverageEngine.assess(library, history, Syllabus.areas(track)) }
        computing = false
    }
    val ready = !(computing && areas.isEmpty())
    val check = CoverageChecker.check
    fun shown(sub: SubtopicCoverage): CoverageStatus = check?.verdicts?.get(sub.id)?.status ?: sub.status
    fun generate(sub: SubtopicCoverage) {
        val exam = com.stethoscore.app.exam.ExamChoice.effective(track, com.stethoscore.app.exam.ExamChoice.defaults(context))
        val open = onNewSet
        if (open == null) { notice = "Writing questions on one subtopic is not on Android yet. Make an MCQ set on it from New set."; return }
        open(if (exam != null) com.stethoscore.app.exam.NewSetPreset.blueprintArea(sub.subtopic.name, exam)
            else com.stethoscore.app.exam.NewSetPreset(com.stethoscore.app.data.StudySetKind.MCQ, sub.subtopic.name, sub.subtopic.name, "Write questions on ${sub.subtopic.name}."))
    }

    Column(Modifier.fillMaxSize()) {
        StudyTitleBar("Syllabus", onBack) {
            Box {
                WardButtonBox({ menu = true }, Modifier.semantics { contentDescription = "Exam"; stateDescription = track.title },
                    kind = WardButtonKind.compact, fills = false) {
                    Icon(Icons.Rounded.School, null, Modifier.size(18.dp))
                    Text(CoverageWords.shortName(track))
                }
                DropdownMenu(menu, { menu = false }, containerColor = wardColor(WardToken.raised)) {
                    for (exam in ExamTrack.entries) DropdownMenuItem(
                        { Text(exam.title, color = wardColor(if (exam == track) WardToken.primaryInk else WardToken.ink)) },
                        { menu = false; track = exam },
                        leadingIcon = if (exam == track) ({ Icon(Icons.Rounded.CheckCircle, null, tint = wardColor(WardToken.primaryInk)) }) else null)
                    DropdownMenuItem({ Text("Choose a specific exam…", color = wardColor(WardToken.ink)) }, { menu = false; picking = true })
                }
            }
        }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.readableColumn().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                if (!ready) ReaderFormSection {
                    Row(Modifier.fillMaxWidth().wardRowTile(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        EcgLoader()
                        Text("Reading your library…", style = WardType.body.textStyle(), color = wardColor(WardToken.inkSecondary))
                    }
                } else {
                    notice?.let { WardBanner(it, Icons.Rounded.Info, modifier = Modifier.padding(horizontal = 16.dp)) }
                    val all = areas.flatMap { it.subtopics }
                    ReaderFormSection(footer = CoverageWords.summaryFooter(track)) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            for (status in CoverageStatus.entries) {
                                val chosen = statusFilter == status
                                CountChip(all.count { shown(it) == status }, status, chosen, Modifier.weight(1f)) {
                                    if (chosen) statusFilter = null else { statusFilter = status; gapsOnly = status != CoverageStatus.covered }
                                }
                            }
                        }
                    }
                    ReaderFormSection(header = "AI check",
                        footer = "Sends each area’s subtopics and a short digest of your library — set names, matching questions and cards, lecture headings — to ${CoverageChecker.brand} Cloud.") {
                        CoverageChecker.blocker?.let {
                            Text(it, Modifier.fillMaxWidth().wardRowTile(), style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
                        }
                    }
                    for (area in areas) {
                        val rows = area.subtopics.filter { CoverageWords.passes(shown(it), statusFilter, gapsOnly) }
                        if (rows.isEmpty()) continue
                        val covered = area.subtopics.count { shown(it) == CoverageStatus.covered }
                        Column(Modifier.fillMaxWidth()) {
                            WardSectionLabel(area.area.name, Modifier.padding(horizontal = 20.dp).padding(bottom = 2.dp)) {
                                Text("$covered of ${area.subtopics.size} covered", style = WardTextStyle.caption.textStyle(mono = true),
                                    color = wardColor(WardToken.inkSecondary))
                            }
                            for (sub in rows) SubtopicRow(sub, shown(sub)) { generate(sub) }
                        }
                    }
                }
            }
        }
        // the slab only once there is something to show
        if (ready) StudyActionBar {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                WardSegmented(gapsOnly, listOf(false, true), { gapsOnly = it; statusFilter = null },
                    Modifier.widthIn(max = 560.dp).fillMaxWidth().semantics { contentDescription = "Show" }) { gaps, style, colour ->
                    Text(if (gaps) "Gaps only" else "Everything", style = style, color = colour, maxLines = 1)
                }
            }
        }
    }
}

/** One of the three counts at the top, as a chip that filters the rows to its status; the chosen one is pressed in and its words take its tone. */
@Composable private fun CountChip(count: Int, status: CoverageStatus, chosen: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val tone = CoverageWords.tone(status)
    val words = if (chosen) tone.ink() else wardColor(WardToken.inkSecondary)
    val source = remember { MutableInteractionSource() }
    Column(modifier.defaultMinSize(minHeight = 56.dp)
        .selectable(chosen, interactionSource = source, indication = null, role = Role.Button, onClick = onClick)
        .semantics(mergeDescendants = true) { stateDescription = if (chosen) "Shows every row again" else "Shows only these" }
        .wardRelief(CircleShape, WardLift.low, inset = chosen)
        .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("$count", style = WardType.obsLarge.textStyle(), color = tone.color())
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(CoverageWords.icon(status), null, tint = words, modifier = Modifier.size(12.dp))
            Text(status.label, style = WardTextStyle.caption.textStyle(), color = words, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A coverage status as a WardChip, with an icon so it never rests on colour. */
@Composable fun StatusChip(status: CoverageStatus) {
    WardChip(status.label, tone = CoverageWords.tone(status), icon = CoverageWords.icon(status))
}

@OptIn(ExperimentalFoundationApi::class)
@Composable private fun SubtopicRow(sub: SubtopicCoverage, status: CoverageStatus, onGenerate: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    // the gaps carry the button; a covered topic keeps it in its menu
    val isGap = status != CoverageStatus.covered
    Box {
        Column(Modifier.fillMaxWidth().wardRowTile().combinedClickable(onClick = {}, onLongClick = { menu = true }, onLongClickLabel = "More"),
            verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(sub.subtopic.name, Modifier.weight(1f), style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
                Spacer(Modifier.width(8.dp))
                StatusChip(status)
            }
            Text(CoverageWords.detail(sub), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
            if (isGap) ChipBox(false, onGenerate) {
                Icon(Icons.Rounded.AutoFixHigh, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(14.dp))
                Text("Generate questions", style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.primaryInk))
            }
        }
        DropdownMenu(menu, { menu = false }, containerColor = wardColor(WardToken.raised)) {
            DropdownMenuItem({ Text("Generate questions", color = wardColor(WardToken.ink)) }, { menu = false; onGenerate() },
                leadingIcon = { Icon(Icons.Rounded.AutoFixHigh, null, tint = wardColor(WardToken.ink)) })
        }
    }
}
