package com.stethoscore.app.ui.exam

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AddCircleOutline
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.stethoscore.app.coverage.CoverageEngine
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.exam.BlueprintStanding
import com.stethoscore.app.exam.ExamBlueprint
import com.stethoscore.app.exam.ExamCatalog
import com.stethoscore.app.exam.ExamChoice
import com.stethoscore.app.exam.ExamWords
import com.stethoscore.app.exam.NewSetPreset
import com.stethoscore.app.exam.TargetExam
import com.stethoscore.app.ui.editors.EcgLoader
import com.stethoscore.app.ui.home.ExamCountdown
import com.stethoscore.app.ui.ward.WardProgressBar
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardCardFace
import com.stethoscore.app.ui.ward.WardChip
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardPill
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSectionLabel
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToggle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardRelief
import com.stethoscore.app.ui.wardColor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.Date

// A port of ios/RedPen/Features/Exam/ExamPickerView.swift and
// ExamDashboardCard.swift on the Ward port: choosing the exam (one primary,
// optionally a second, and the date), the badge on a set written for one, and
// the chosen exam at a glance - the countdown, the predicted score against the
// pass mark, the blueprint's biggest areas and what to study next. The words
// are in exam/ExamWords.kt, the working out in exam/ExamBlueprint.kt over
// coverage/CoverageEngine.kt.

// MARK: - pieces shared by the exam screens

/** A page over whatever is showing, as an iOS sheet is: the Ward base, inside the safe area. */
@Composable internal fun ExamSheet(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = wardColor(WardToken.background)) {
            Box(Modifier.fillMaxSize().safeDrawingPadding()) { content() }
        }
    }
}

/**
 * A row as a tile (WardRowTile) that is itself the button: the whole tile
 * takes the tap, not only its words.
 */
@Composable internal fun Modifier.tappableRowTile(onClick: () -> Unit, role: Role = Role.Button, selected: Boolean? = null,
                                                  inset: Boolean = false): Modifier {
    val shape = RoundedCornerShape(WardRadius.field.wardDp)
    val tile = this.padding(WardSpace.s.wardDp).wardRelief(shape, WardLift.low, inset = inset, control = true)
    val tapped = if (selected != null) tile.selectable(selected, role = role, onClick = onClick) else tile.clickable(role = role, onClick = onClick)
    return tapped.padding(horizontal = 12.dp, vertical = 8.dp)
}

/** A row as a tile with no tap of its own (wardRowBackground). */
@Composable internal fun Modifier.plainRowTile(inset: Boolean = false): Modifier =
    this.padding(WardSpace.s.wardDp).wardRelief(RoundedCornerShape(WardRadius.field.wardDp), WardLift.low, inset = inset, control = true)
        .padding(horizontal = 12.dp, vertical = 8.dp)

// MARK: - the picker

/**
 * Choosing the exam: one primary, optionally a second, and the date. Names
 * only - no flags or logos - grouped by where the exam is sat, each with a
 * line on its format so two similar names are told apart. [onClose] is
 * called when the choice is saved, cancelled or (from onboarding) skipped.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExamPickerScreen(store: StudyStore, onClose: () -> Unit, isOnboarding: Boolean = false) {
    val context = LocalContext.current
    val defaults = remember { ExamChoice.defaults(context) }
    var primary by rememberSaveable { mutableStateOf(ExamChoice.current(defaults)?.id ?: "") }
    var secondary by rememberSaveable { mutableStateOf(ExamChoice.currentSecondary(defaults)?.id ?: "") }
    var choosingSecond by rememberSaveable { mutableStateOf(secondary.isNotEmpty()) }
    // the date is kept as soon as it is set, as iOS's @AppStorage keeps it
    var examDate by remember { mutableStateOf(store.examDate) }
    var pickingDate by remember { mutableStateOf(false) }

    fun setDate(date: Long?) {
        examDate = date
        runCatching { store.setExamDate(date) }
    }

    fun save() {
        val chosen = ExamCatalog.exam(primary)
        val second = if (choosingSecond) ExamCatalog.exam(secondary) else null
        if (chosen != null || !isOnboarding) ExamChoice.choose(chosen, second, defaults) else ExamChoice.markAsked(defaults)
        onClose()
    }

    fun skip() {
        if (isOnboarding) ExamChoice.markAsked(defaults)
        onClose()
    }

    BackHandler { skip() }
    Column(Modifier.fillMaxSize()) {
        ReaderNavBar(if (isOnboarding) "Which exam are you preparing for?" else "Your exam",
            leading = {
                WardTextButton(if (isOnboarding) "Skip" else "Cancel", ::skip,
                    Modifier.testTag(if (isOnboarding) "examOnboardingSkip" else "examPickerCancel"), kind = WardButtonKind.quiet, fills = false)
            },
            trailing = {
                WardTextButton("Save", ::save, Modifier.testTag("examPickerSave"), kind = WardButtonKind.compact,
                    enabled = primary.isNotEmpty() || isOnboarding, fills = false)
            })
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)) {
            if (isOnboarding) {
                Text("Questions, study plan, coverage map and mock papers will follow its format and blueprint. You can change it any time.",
                    Modifier.padding(horizontal = 20.dp), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            ExamCatalog.exam(primary)?.let { exam ->
                ReaderFormSection(header = exam.name, footer = "A second exam counts for 30% of what to study next and of a generated set's topics.") {
                    Box(Modifier.fillMaxWidth().plainRowTile()) {
                        WardToggle(choosingSecond, { choosingSecond = it }, label = "Also preparing for a second exam")
                    }
                    if (choosingSecond) SecondExamRow(exam, secondary) { secondary = it }
                    Row(Modifier.fillMaxWidth().tappableRowTile({ pickingDate = true }).heightIn(min = 28.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text("Exam date", Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                        Text(DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(examDate ?: defaultDate())),
                            style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk))
                    }
                    if (examDate != null) Box(Modifier.fillMaxWidth().plainRowTile()) {
                        WardTextButton("Clear the date", { setDate(null) }, kind = WardButtonKind.destructive, fills = false)
                    }
                }
            }
            for (group in ExamCatalog.byRegion) {
                ReaderFormSection(header = group.region.title) {
                    for (exam in group.exams) ExamRow(exam, exam.id == primary) {
                        primary = exam.id
                        if (secondary == exam.id) secondary = ""
                    }
                }
            }
            ReaderFormSection {
                Text("Formats and blueprints come from each exam's published outline; where an exam publishes no percentages the weights are our estimate and are marked approximate. Always check the official candidate guide.",
                    Modifier.fillMaxWidth().plainRowTile(), style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        }
    }

    if (pickingDate) {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val shown = Instant.ofEpochMilli(examDate ?: defaultDate()).atZone(zone).toLocalDate()
        val state = rememberDatePickerState(
            initialSelectedDateMillis = shown.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates {
                // from today on, as iOS's in: Date()...
                override fun isSelectableDate(utcTimeMillis: Long): Boolean =
                    utcTimeMillis >= today.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
            })
        DatePickerDialog(onDismissRequest = { pickingDate = false },
            confirmButton = {
                WardTextButton("Done", {
                    state.selectedDateMillis?.let { utc ->
                        val day = Instant.ofEpochMilli(utc).atZone(ZoneOffset.UTC).toLocalDate()
                        // midday, so the day is the same wherever the clock is read
                        setDate(day.atTime(12, 0).atZone(zone).toInstant().toEpochMilli())
                    }
                    pickingDate = false
                }, kind = WardButtonKind.compact, fills = false)
            },
            dismissButton = { WardTextButton("Cancel", { pickingDate = false }, kind = WardButtonKind.quiet, fills = false) },
            colors = androidx.compose.material3.DatePickerDefaults.colors(containerColor = wardColor(WardToken.raised))) {
            DatePicker(state)
        }
    }
}

/** No date yet: ninety days from now, as iOS's picker opens on. */
private fun defaultDate(): Long = System.currentTimeMillis() + 90L * 86_400_000L

@Composable private fun SecondExamRow(primary: TargetExam, secondary: String, onPick: (String) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth().tappableRowTile({ menu = true }).heightIn(min = 28.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Second exam", Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
            Text(ExamCatalog.exam(secondary)?.name ?: "None", Modifier.weight(1f, fill = false), style = WardType.body.textStyle(),
                color = wardColor(WardToken.primaryInk), maxLines = 1)
            Icon(Icons.Rounded.ExpandMore, null, Modifier.size(18.dp), tint = wardColor(WardToken.primaryInk))
        }
        DropdownMenu(menu, { menu = false }, containerColor = wardColor(WardToken.raised)) {
            DropdownMenuItem(text = { Text("None") }, onClick = { menu = false; onPick("") },
                leadingIcon = if (secondary.isEmpty()) ({ Icon(Icons.Rounded.Check, null) }) else null)
            for (other in ExamCatalog.all.filter { it.id != primary.id }) {
                DropdownMenuItem(text = { Text(other.name) }, onClick = { menu = false; onPick(other.id) },
                    leadingIcon = if (other.id == secondary) ({ Icon(Icons.Rounded.Check, null) }) else null)
            }
        }
    }
}

@Composable private fun ExamRow(exam: TargetExam, chosen: Boolean, onPick: () -> Unit) {
    Row(Modifier.fillMaxWidth().tappableRowTile(onPick, Role.RadioButton, selected = chosen).heightIn(min = 44.dp)
        .testTag("examPick-${exam.id}"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(exam.name, style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
            Text(ExamWords.detail(exam), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
        if (chosen) Icon(Icons.Rounded.Check, null, tint = wardColor(WardToken.primaryInk))
    }
}

/** "Step 2 CK" on a set written for that exam. */
@Composable
fun ExamBadge(examId: String?, modifier: Modifier = Modifier) {
    val exam = ExamCatalog.exam(examId) ?: return
    WardChip(exam.shortName, modifier.semantics(mergeDescendants = true) { contentDescription = "Written for ${exam.name}" }, tone = WardTone.Blue)
}

// MARK: - the dashboard card

/**
 * The chosen exam at a glance: the countdown, the predicted score against
 * the pass mark, the blueprint's biggest areas with how well the library
 * covers each, and what to study next - each a tap from a new question set
 * written to the exam's format. Everything is worked out from the student's
 * own library and answers (ExamBlueprint over the coverage engine) and says
 * it is an estimate.
 *
 * [onPreset] opens New set with the preset; [revision] changes when the
 * library or the answers do.
 */
@Composable
fun ExamDashboardCard(store: StudyStore, revision: Int, onPreset: (NewSetPreset) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val defaults = remember { ExamChoice.defaults(context) }
    var version by remember { mutableIntStateOf(0) }
    var picking by remember { mutableStateOf(false) }
    val exam = remember(version) { ExamChoice.current(defaults) }
    val second = remember(version) { ExamChoice.currentSecondary(defaults) }
    var standings by remember { mutableStateOf<List<BlueprintStanding>>(emptyList()) }
    // re-assess when the exam, the library or the answers change
    val library: List<StudySet> = store.library
    val history: Map<String, List<Boolean>> = store.answerHistory
    val key = "${exam?.id ?: "-"}/${second?.id ?: "-"}-${library.size}-${history.values.sumOf { it.size }}-$revision-$version"
    LaunchedEffect(key) {
        if (exam == null) { standings = emptyList(); return@LaunchedEffect }
        val plan = ExamBlueprint.plan(exam, second)
        standings = withContext(Dispatchers.Default) {
            val assessed = CoverageEngine.assess(library, history, ExamBlueprint.syllabus(plan))
            ExamBlueprint.standings(plan, assessed)
        }
    }

    WardCardFace(modifier.fillMaxWidth().testTag("examDashboard"), spacing = 12.dp) {
        if (exam != null) {
            DashboardHeader(exam, second, store.examDate) { picking = true }
            if (standings.isNotEmpty()) {
                ScoreLine(exam, standings)
                Bars(standings)
                NextUp(exam, standings, onPreset)
            } else {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { EcgLoader() }
            }
            Text(ExamWords.sourceNote(exam), style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Rounded.School, null, Modifier.size(20.dp), tint = wardColor(WardToken.ink))
                    Text("Which exam are you preparing for?", style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
                }
                Text("Pick it and questions, the plan, the coverage map and mock papers follow its format and blueprint.",
                    style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
                WardTextButton("Choose your exam", { picking = true }, Modifier.testTag("examDashboardChoose"),
                    kind = WardButtonKind.compact, fills = false)
            }
        }
    }
    if (picking) ExamSheet({ picking = false }) {
        ExamPickerScreen(store, { picking = false; version += 1 })
    }
}

@Composable private fun DashboardHeader(exam: TargetExam, second: TargetExam?, examDate: Long?, onChange: () -> Unit) {
    val days = ExamCountdown.daysLeft(examDate)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
            Text(exam.name, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
            if (second != null) Text("with ${second.shortName}", style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
        WardPill(ExamWords.countdown(days), Modifier.clearAndSetSemantics { contentDescription = days?.let { "$it days to go" } ?: "No exam date" })
        Box(Modifier.size(44.dp).clickable(role = Role.Button, onClickLabel = null, onClick = onChange)
            .semantics { contentDescription = "Change exam" }.testTag("examDashboardChange"), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Tune, null, tint = wardColor(WardToken.primaryInk))
        }
    }
}

@Composable private fun ScoreLine(exam: TargetExam, standings: List<BlueprintStanding>) {
    val predicted = ExamBlueprint.predictedScore(standings)
    val covered = ExamBlueprint.weightedCoverage(standings)
    val above = predicted >= exam.passMark
    Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        WardProgressBar(predicted, "Predicted score")
        WardChip(if (above) "Above the pass mark" else "Below the pass mark", tone = if (above) WardTone.Green else WardTone.Warning,
            icon = if (above) Icons.Rounded.CheckCircle else Icons.Rounded.Warning)
        Text(ExamWords.scoreLine(predicted, exam.passMark, covered),
            style = WardTextStyle.caption.textStyle().copy(fontFamily = FontFamily.Monospace), color = wardColor(WardToken.inkSecondary))
    }
}

/** The six biggest areas: share, coverage bar, readiness. */
@Composable private fun Bars(standings: List<BlueprintStanding>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        WardSectionLabel("Blueprint")
        for (s in standings.filter { it.area.percent > 0 }.take(6)) BlueprintBar(s)
    }
}

@Composable private fun NextUp(exam: TargetExam, standings: List<BlueprintStanding>, onPreset: (NewSetPreset) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        WardSectionLabel("Study next")
        for (s in ExamBlueprint.studyNext(standings, limit = 3)) {
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp)
                .clickable(role = Role.Button, onClickLabel = "Makes a question set on it in ${exam.shortName} format") {
                    onPreset(NewSetPreset.blueprintArea(s.area.title, exam))
                },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
                Icon(Icons.Rounded.AutoAwesome, null, tint = wardColor(WardToken.primaryInk))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(s.area.title, style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                    Text(ExamWords.why(s), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                }
                Icon(Icons.Rounded.AddCircleOutline, null, tint = wardColor(WardToken.primaryInk))
            }
        }
    }
}

/** One blueprint area: its share, its readiness, and a bar of how much is covered. */
@Composable
fun BlueprintBar(standing: BlueprintStanding) {
    val ready = ExamWords.percent(standing.readiness) + " ready"
    val readyTone = when {
        standing.readiness >= 0.6 -> WardToken.success
        standing.readiness >= 0.45 -> WardToken.warning
        else -> WardToken.danger
    }
    Column(Modifier.clearAndSetSemantics { contentDescription = ExamWords.spoken(standing) },
        verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(standing.area.title, Modifier.weight(1f), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.ink), maxLines = 1)
            Spacer(Modifier.widthIn(min = 6.dp))
            Text(ready, style = WardTextStyle.caption2.textStyle(mono = true), color = wardColor(readyTone))
            Spacer(Modifier.widthIn(min = 6.dp).size(6.dp))
            Text(ExamWords.share(standing), style = WardTextStyle.caption.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
        }
        WardProgressBar(standing.coverage, standing.area.title)
    }
}
