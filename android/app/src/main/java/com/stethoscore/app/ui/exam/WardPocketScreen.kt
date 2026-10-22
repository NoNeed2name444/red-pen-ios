package com.stethoscore.app.ui.exam

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Accessibility
import androidx.compose.material.icons.rounded.Air
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Biotech
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.FamilyRestroom
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.FormatListNumbered
import androidx.compose.material.icons.rounded.MonitorHeart
import androidx.compose.material.icons.rounded.Opacity
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.Science
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.exam.NewSetPreset
import com.stethoscore.app.exam.WardBand
import com.stethoscore.app.exam.WardCalc
import com.stethoscore.app.exam.WardField
import com.stethoscore.app.exam.WardFieldKind
import com.stethoscore.app.exam.WardItem
import com.stethoscore.app.exam.WardOutcome
import com.stethoscore.app.exam.WardPocket
import com.stethoscore.app.exam.WardScore
import com.stethoscore.app.exam.WardScoreEntry
import com.stethoscore.app.exam.WardScores
import com.stethoscore.app.exam.WardUnit
import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.LabRange
import com.stethoscore.app.quiz.LabRanges
import com.stethoscore.app.quiz.LabUnits
import com.stethoscore.app.ui.NewSetScreen
import com.stethoscore.app.ui.sources.ReaderBackButton
import com.stethoscore.app.ui.sources.ReaderDoneButton
import com.stethoscore.app.ui.sources.ReaderFormSection
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSegmented
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextField
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToggle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardField
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.wardColor
import kotlin.math.abs

// A port of ios/RedPen/Features/Exam/WardPocketView.swift on the
// Ward port: the lab values sheet grown into three tabs - Lab values,
// Calculators and Scores - opened from a study screen's More menu. The
// formulas and tables are in exam/WardPocket.kt and exam/WardPocketScores.kt;
// this is only how they are shown.
//
// Every screen carries "For learning only - not for patient care" at the
// bottom: this teaches how a score works, it is not a medical device.

/** Which of the Ward pocket's tabs is showing. */
enum class WardPocketTab(val title: String) {
    labs("Lab values"), calculators("Calculators"), scores("Scores");

    val searchPrompt: String get() = when (this) {
        labs -> "Search lab values"
        calculators -> "Search calculators"
        scores -> "Search scores"
    }
}

/** The nearest Material icon to a calculator's SF Symbol. */
internal fun wardCalcIcon(calc: WardCalc): ImageVector = when (calc.symbol) {
    "figure.stand" -> Icons.Rounded.Accessibility
    "drop.halffull" -> Icons.Rounded.Opacity
    "testtube.2" -> Icons.Rounded.Science
    "lungs" -> Icons.Rounded.Air
    "cross.vial" -> Icons.Rounded.Biotech
    "heart" -> Icons.Rounded.FavoriteBorder
    "waveform.path.ecg" -> Icons.Rounded.MonitorHeart
    "ivfluid.bag" -> Icons.Rounded.WaterDrop
    "figure.and.child.holdinghands" -> Icons.Rounded.FamilyRestroom
    "arrow.left.arrow.right" -> Icons.Rounded.SwapHoriz
    else -> Icons.Rounded.FormatListNumbered
}

/**
 * The Ward pocket. [track] sets the units it opens in (US conventional for a
 * USMLE track, SI for every other); "Practise this" opens New set, and a set
 * made there goes to [onSaveSet].
 */
@Composable
fun WardPocketScreen(track: ExamTrack, onDone: () -> Unit, onSaveSet: (StudySet) -> Unit, start: WardPocketTab = WardPocketTab.calculators) {
    var tab by rememberSaveable { mutableStateOf(start) }
    var conventional by rememberSaveable { mutableStateOf(LabUnits.conventional(track)) }
    var query by rememberSaveable { mutableStateOf("") }
    var calcId by rememberSaveable { mutableStateOf<String?>(null) }
    var scoreId by rememberSaveable { mutableStateOf<String?>(null) }
    var practice by remember { mutableStateOf<NewSetPreset?>(null) }

    val preset = practice
    if (preset != null) {
        BackHandler { practice = null }
        NewSetScreen({ set -> onSaveSet(set); practice = null }, { practice = null }, preset = preset)
        return
    }
    val calc = WardCalc.from(calcId)
    if (calc != null) {
        BackHandler { calcId = null }
        WardCalcPage(calc, conventional, { conventional = it }, { calcId = null }) {
            practice = NewSetPreset.wardPocket(calc.title, WardPocket.practiceNotes(calc))
        }
        return
    }
    val score = scoreId?.let { WardScores.named(it) }
    if (score != null) {
        BackHandler { scoreId = null }
        WardScorePage(score, { scoreId = null }) { practice = NewSetPreset.wardPocket(score.name, score.practiceNotes) }
        return
    }

    BackHandler(onBack = onDone)
    fun matches(name: String): Boolean {
        val q = query.trim()
        return q.isEmpty() || name.contains(q, ignoreCase = true)
    }
    WardDisclaimerFrame { foot ->
        Column(Modifier.fillMaxSize()) {
            ReaderNavBar("Clinical reference", trailing = { ReaderDoneButton(onClick = onDone) })
            Column(Modifier.weight(1f).fillMaxWidth().padding(bottom = foot).verticalScroll(rememberScrollState()).padding(top = 4.dp, bottom = WardSpace.l.wardDp),
                verticalArrangement = Arrangement.spacedBy(WardSpace.section.wardDp)) {
                WardTextField(query, { query = it }, Modifier.fillMaxWidth().padding(horizontal = 16.dp), placeholder = tab.searchPrompt)
                // the switches sit on the base itself, not on tiles
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    WardSegmented(tab, WardPocketTab.entries, { tab = it },
                        Modifier.fillMaxWidth().semantics { contentDescription = "Section" }.testTag("wardPocketTabs")) { t, style, color ->
                        Text(t.title, style = style, color = color, maxLines = 1)
                    }
                    if (tab != WardPocketTab.scores) WardUnitsPicker(conventional) { conventional = it }
                }
                when (tab) {
                    WardPocketTab.labs -> LabRangesSections(query, conventional)
                    WardPocketTab.calculators -> ReaderFormSection(header = "Calculators") {
                        for (c in WardCalc.calculators.filter { matches(it.title) }) {
                            Row(Modifier.fillMaxWidth().tappableRowTile({ calcId = c.rawValue }).heightIn(min = 28.dp),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Icon(wardCalcIcon(c), null, Modifier.size(22.dp), tint = wardColor(WardToken.primaryInk))
                                Text(c.title, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                                Chevron()
                            }
                        }
                    }
                    WardPocketTab.scores -> ReaderFormSection(header = "Scores") {
                        for (entry in WardScores.entries.filter { matches(it.name) }) {
                            val (title, detail) = when (entry) {
                                is WardScoreEntry.Table -> entry.score.name to entry.score.purpose
                                is WardScoreEntry.Formula -> entry.calc.title to "Liver disease severity and transplant priority"
                            }
                            Row(Modifier.fillMaxWidth().tappableRowTile({
                                when (entry) {
                                    is WardScoreEntry.Table -> scoreId = entry.score.id
                                    is WardScoreEntry.Formula -> calcId = entry.calc.rawValue
                                }
                            }), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
                                    Text(title, style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                                    Text(detail, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary),
                                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                                }
                                Chevron()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable private fun Chevron() =
    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, Modifier.size(18.dp), tint = wardColor(WardToken.inkSecondary))

/** SI or US conventional units; the quiz's lab values sheet shares it, as on iOS. */
@Composable internal fun WardUnitsPicker(conventional: Boolean, onChange: (Boolean) -> Unit) {
    WardSegmented(conventional, listOf(false, true), onChange, Modifier.fillMaxWidth().semantics { contentDescription = "Units" }) { us, style, color ->
        Text(if (us) "US conventional" else "SI", style = style, color = color, maxLines = 1)
    }
}

/**
 * "For learning only - not for patient care", a small soft chip with amber
 * words at the foot of the screen, always in view, below [content]. The page
 * gets the room it must leave at its foot (what floats there, as measured,
 * and a gap) and ends above it, so no row runs under the chip or the
 * score's total.
 */
@Composable private fun WardDisclaimerFrame(bottomExtra: (@Composable ColumnScope.() -> Unit)? = null, content: @Composable (foot: Dp) -> Unit) {
    val density = LocalDensity.current
    var floating by remember { mutableStateOf(WardDisclaimer.reserve.dp) }
    Box(Modifier.fillMaxSize()) {
        content(floating + WardSpace.s.wardDp)
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().onSizeChanged { floating = with(density) { it.height.toDp() } },
            horizontalAlignment = Alignment.CenterHorizontally) {
            bottomExtra?.invoke(this)
            Row(Modifier.padding(bottom = WardSpace.s.wardDp).wardRaised(radius = 100.0, lift = WardLift.mid)
                .padding(horizontal = WardSpace.l.wardDp, vertical = 8.dp).semantics(mergeDescendants = true) {}.testTag("wardDisclaimer"),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Rounded.School, null, Modifier.size(16.dp), tint = wardColor(WardToken.warning))
                Text(WardPocket.disclaimer, style = WardTextStyle.footnote.textStyle(WardWeight.semibold), color = wardColor(WardToken.warning))
            }
        }
    }
}

/** The disclaimer's own room before it is measured: the chip's height at the standard text size. */
internal object WardDisclaimer {
    const val reserve = 48
}

/**
 * The reference ranges matching [query], a section per group, with the
 * caveat that the paper's own ranges win (iOS LabRangesSections).
 */
@Composable private fun LabRangesSections(query: String, conventional: Boolean) {
    val found = remember(query) { LabRanges.search(query) }
    Column(verticalArrangement = Arrangement.spacedBy(WardSpace.section.wardDp)) {
        ReaderFormSection {
            Text(LabRanges.caveat, Modifier.fillMaxWidth().plainRowTile(), style = WardTextStyle.footnote.textStyle(),
                color = wardColor(WardToken.inkSecondary))
        }
        for (group in LabRanges.groups) {
            val rows: List<LabRange> = found.filter { it.group == group }
            if (rows.isNotEmpty()) ReaderFormSection(header = group) {
                for (row in rows) Row(Modifier.fillMaxWidth().plainRowTile().semantics(mergeDescendants = true) {},
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(row.name, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                    Text(row.value(conventional), Modifier.weight(1f), style = WardType.body.textStyle(), textAlign = TextAlign.End,
                        color = wardColor(WardToken.inkSecondary))
                }
            }
        }
    }
}

/** A block of text under a heading: the formula, the note, the source. */
@Composable private fun WardTextSection(title: String, text: String) {
    if (text.isEmpty()) return
    ReaderFormSection(header = title) {
        Text(text, Modifier.fillMaxWidth().plainRowTile(), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
    }
}

/** "Practise this": opens New set with the calculator or score as its material. */
@Composable private fun PractiseButton(action: () -> Unit) {
    ReaderFormSection(footer = WardPocket.disclaimerDetail) {
        Row(Modifier.fillMaxWidth().tappableRowTile(action).heightIn(min = 28.dp).testTag("wardPractise")
            .semantics { contentDescription = "Practise this. Writes exam questions on this with your usual question settings" },
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(20.dp), tint = wardColor(WardToken.primaryInk))
            Text("Practise this", style = WardType.body.textStyle().copy(fontWeight = FontWeight.SemiBold), color = wardColor(WardToken.primaryInk))
        }
    }
}

// MARK: - a calculator

private fun number(text: String?): Double? = text?.trim()?.replace(",", ".")?.toDoubleOrNull()

@Composable private fun WardCalcPage(calc: WardCalc, conventional: Boolean, onConventional: (Boolean) -> Unit, onBack: () -> Unit,
                                     onPractise: () -> Unit) {
    // what was typed in each number field, in the units showing
    val typed = remember(calc) { mutableStateMapOf<String, String>() }
    val toggles = remember(calc) { mutableStateMapOf<String, Boolean>() }
    val choices = remember(calc) { mutableStateMapOf<String, Int>() }
    val hasUnits = calc.fields.any { (it.kind as? WardFieldKind.Number)?.unit?.let { u -> u.si != u.us } == true }

    /** Everything entered, numbers in SI. */
    fun values(): Map<String, Double> {
        val out = HashMap<String, Double>()
        for (field in calc.fields) when (val kind = field.kind) {
            is WardFieldKind.Number -> number(typed[field.id])?.let { out[field.id] = kind.unit.toSI(it, conventional) }
            WardFieldKind.Toggle -> out[field.id] = if (toggles[field.id] == true) 1.0 else 0.0
            is WardFieldKind.Choice -> out[field.id] = (choices[field.id] ?: 0).toDouble()
        }
        return out
    }

    /** Switching units rewrites what was typed, so a value keeps its meaning. */
    fun switchUnits(now: Boolean) {
        val was = conventional
        if (was == now) return
        for (field in calc.fields) {
            val unit = (field.kind as? WardFieldKind.Number)?.unit ?: continue
            if (unit.usPerSI == 1.0) continue
            val x = number(typed[field.id]) ?: continue
            val shown = unit.fromSI(unit.toSI(x, was), now)
            val places = if (abs(shown) >= 100) 0 else if (abs(shown) >= 10) 1 else 2
            typed[field.id] = WardPocket.format(shown, places)
        }
        onConventional(now)
    }

    val outcome = calc.compute(values(), conventional)
    WardDisclaimerFrame { foot ->
        Column(Modifier.fillMaxSize()) {
            ReaderNavBar(calc.title, leading = { ReaderBackButton(onBack) })
            Column(Modifier.weight(1f).fillMaxWidth().padding(bottom = foot).verticalScroll(rememberScrollState()).padding(top = 4.dp, bottom = WardSpace.l.wardDp),
                verticalArrangement = Arrangement.spacedBy(WardSpace.section.wardDp)) {
                if (hasUnits) Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) { WardUnitsPicker(conventional, ::switchUnits) }
                ReaderFormSection(header = "Values") {
                    for (field in calc.fields) FieldRow(field, conventional, typed[field.id] ?: "", { typed[field.id] = it },
                        toggles[field.id] ?: false, { toggles[field.id] = it }, choices[field.id] ?: 0, { choices[field.id] = it })
                }
                ResultSection(outcome)
                WardTextSection("How it is worked out", calc.formula)
                WardTextSection("Keep in mind", calc.note)
                WardTextSection("Source", calc.source)
                PractiseButton(onPractise)
            }
        }
    }
}

@Composable private fun ResultSection(outcome: WardOutcome?) {
    ReaderFormSection(header = "Result") {
        Column(Modifier.fillMaxWidth().plainRowTile().semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (outcome != null) {
                for (line in outcome.lines) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(line.label, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                    Text(line.value, style = WardType.obsLarge.textStyle(), color = wardColor(WardToken.ink), textAlign = TextAlign.End)
                }
                outcome.verdict?.let { Text(it, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary)) }
            } else {
                Text("Fill in the values above.", style = WardType.body.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        }
    }
}

@Composable private fun FieldRow(field: WardField, conventional: Boolean, text: String, onText: (String) -> Unit,
                                 on: Boolean, onToggle: (Boolean) -> Unit, choice: Int, onChoice: (Int) -> Unit) {
    when (val kind = field.kind) {
        is WardFieldKind.Number -> NumberRow(field, kind.unit, conventional, text, onText)
        WardFieldKind.Toggle -> Box(Modifier.fillMaxWidth().plainRowTile()) { WardToggle(on, onToggle, label = field.label) }
        is WardFieldKind.Choice -> {
            var menu by remember { mutableStateOf(false) }
            Box {
                Row(Modifier.fillMaxWidth().tappableRowTile({ menu = true }).heightIn(min = 28.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(field.label, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                    Text(kind.options.getOrElse(choice) { "" }, style = WardType.body.textStyle(), color = wardColor(WardToken.primaryInk))
                    Icon(Icons.Rounded.ExpandMore, null, Modifier.size(18.dp), tint = wardColor(WardToken.primaryInk))
                }
                DropdownMenu(menu, { menu = false }, containerColor = wardColor(WardToken.raised)) {
                    kind.options.forEachIndexed { index, name ->
                        DropdownMenuItem(text = { Text(name) }, onClick = { menu = false; onChoice(index) },
                            leadingIcon = if (index == choice) ({ Icon(Icons.Rounded.Check, null) }) else null)
                    }
                }
            }
        }
    }
}

@Composable private fun NumberRow(field: WardField, unit: WardUnit, conventional: Boolean, text: String, onText: (String) -> Unit) {
    val unitName = unit.name(conventional)
    val spoken = if (unitName.isEmpty()) field.label else field.label + ", " + unitName
    Row(Modifier.fillMaxWidth().plainRowTile(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(field.label, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
        BasicTextField(text, onText, Modifier.widthIn(max = 110.dp).semantics { contentDescription = spoken },
            singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            textStyle = WardType.obs.textStyle().copy(color = wardColor(WardToken.ink), textAlign = TextAlign.End),
            cursorBrush = SolidColor(wardColor(WardToken.primaryInk)),
            decorationBox = { inner ->
                Box(Modifier.fillMaxWidth().wardField(), contentAlignment = Alignment.CenterEnd) {
                    if (text.isEmpty() && field.optional) Text("optional", style = WardType.obs.textStyle(), color = wardColor(WardToken.inkSecondary))
                    inner()
                }
            })
        if (unitName.isNotEmpty()) Text(unitName, Modifier.widthIn(min = 44.dp), style = WardTextStyle.caption.textStyle(),
            color = wardColor(WardToken.inkSecondary))
    }
}

// MARK: - a score

@Composable private fun WardScorePage(score: WardScore, onBack: () -> Unit, onPractise: () -> Unit) {
    val picks = remember(score) { mutableStateMapOf<String, Int>() }
    val now = picks.toMap()
    val total = score.total(now)
    val verdict = score.verdict(now)
    WardDisclaimerFrame(bottomExtra = { WardScoreTotal(total, verdict) }) { foot ->
        Column(Modifier.fillMaxSize()) {
            ReaderNavBar(score.name, leading = { ReaderBackButton(onBack) }, trailing = {
                WardTextButton("Reset", { picks.clear() }, kind = WardButtonKind.compact, enabled = picks.isNotEmpty(), fills = false)
            })
            Column(Modifier.weight(1f).fillMaxWidth().padding(bottom = foot).verticalScroll(rememberScrollState()).padding(top = 4.dp, bottom = WardSpace.l.wardDp),
                verticalArrangement = Arrangement.spacedBy(WardSpace.section.wardDp)) {
                ReaderFormSection {
                    Text(score.purpose, Modifier.fillMaxWidth().plainRowTile(), style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.ink))
                }
                for (item in score.items.filter { !it.isYesNo }) ReaderFormSection(header = item.label) {
                    ChoicePicker(item, picks[item.id] ?: 0) { picks[item.id] = it }
                }
                val yesNo = score.items.filter { it.isYesNo }
                if (yesNo.isNotEmpty()) ReaderFormSection(header = "Criteria") {
                    for (item in yesNo) YesNoRow(item, (picks[item.id] ?: 0) == 1) { picks[item.id] = if (it) 1 else 0 }
                }
                ReaderFormSection(header = "Bands") {
                    for (band in score.bands) BandRow(band, band == verdict)
                }
                WardTextSection("Keep in mind", score.note)
                WardTextSection("Source", score.source)
                PractiseButton(onPractise)
            }
        }
    }
}

@Composable private fun ChoicePicker(item: WardItem, chosen: Int, onPick: (Int) -> Unit) {
    item.choices.forEachIndexed { index, choice ->
        val on = index == chosen
        Row(Modifier.fillMaxWidth().tappableRowTile({ onPick(index) }, Role.RadioButton, selected = on).heightIn(min = 28.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(choice.label, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
            Text(WardScores.points(choice.points), style = WardTextStyle.subheadline.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
            if (on) Icon(Icons.Rounded.Check, null, Modifier.size(18.dp), tint = wardColor(WardToken.primaryInk))
            else Box(Modifier.size(18.dp))
        }
    }
}

@Composable private fun YesNoRow(item: WardItem, on: Boolean, onChange: (Boolean) -> Unit) {
    val points = WardScores.points(item.choices[1].points)
    Row(Modifier.fillMaxWidth().plainRowTile(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(item.label, Modifier.weight(1f), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
        Text(points, style = WardTextStyle.subheadline.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
        WardToggle(on, onChange, Modifier.semantics { contentDescription = "${item.label}, $points" })
    }
}

@Composable private fun BandRow(band: WardBand, on: Boolean) {
    val low = WardScores.points(band.low)
    val high = WardScores.points(band.high)
    val range = if (band.low == band.high) low else low + "–" + high
    val ink = if (on) wardColor(WardToken.primaryInk) else wardColor(WardToken.ink)
    // the band the score falls in, pressed into the base
    Row(Modifier.fillMaxWidth().plainRowTile(inset = on).semantics(mergeDescendants = true) { selected = on },
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(range, Modifier.widthIn(min = 44.dp), style = WardTextStyle.subheadline.textStyle(WardWeight.semibold, mono = true), color = ink)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
            Text(band.title, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = ink)
            Text(band.detail, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
        if (on) Icon(Icons.Rounded.Check, null, Modifier.size(18.dp), tint = ink)
    }
}

/** The running total and what it means, on a card above the disclaimer. */
@Composable private fun WardScoreTotal(total: Double, band: WardBand?) {
    Row(Modifier.padding(horizontal = 16.dp).padding(bottom = WardSpace.s.wardDp).fillMaxWidth()
        .wardRaised(WardRadius.card, WardLift.high).padding(horizontal = 16.dp, vertical = WardSpace.m.wardDp)
        .semantics(mergeDescendants = true) {}.testTag("wardScoreTotal"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.l.wardDp)) {
        Text(WardScores.points(total), Modifier.widthIn(min = 48.dp),
            style = WardTextStyle.largeTitle.textStyle(WardWeight.bold, mono = true), color = wardColor(WardToken.ink))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
            Text(band?.title ?: "", style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
            Text(band?.detail ?: "", style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 3,
                overflow = TextOverflow.Ellipsis)
        }
    }
}
