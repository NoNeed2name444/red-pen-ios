package com.stethoscore.app.ui.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Autorenew
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.ModeConversion
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.exam.NewSetPreset
import com.stethoscore.app.ui.exam.ExamSheet
import com.stethoscore.app.ui.modeIcon
import com.stethoscore.app.ui.sources.ReaderNavBar
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardButtonKind
import com.stethoscore.app.ui.ward.WardEmptyState
import com.stethoscore.app.ui.ward.WardIconSquare
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardRadius
import com.stethoscore.app.ui.ward.WardSection
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextButton
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardTile
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardTone
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardRaised

// iOS Features/Library/TurnIntoPicker.swift: "Turn into…", choosing which
// mode a set should become. Every mode is a tile with what will happen
// written on it before it is tapped - "Instant" when the set can simply be
// rearranged (data/ModeConversion.kt), "Written from…" when it has to go
// through the writer. Tapping one does it: an instant set is made and opened
// straight away; a written one lands in New set with the mode chosen and the
// material already in, one tap from Make. The set it came from is never
// changed. The same sheet serves a library row's menu, the Turn into… tile's
// page (CategoryShelves.swift TurnIntoListView) and the More menu of the
// quiz, card review, OSCE review and book (Theme.swift studyMoreMenu).

/**
 * Carries a choice made in the picker to the app, which owns the navigation
 * (iOS ModeSwitch). Held back until the picker has closed, so the new set is
 * opened on a screen that is really there.
 */
object ModeSwitch {
    sealed interface Choice {
        /** An instant conversion, already in the library: open it. */
        data class Open(val set: StudySet) : Choice
        /** A conversion that needs writing: open New set, filled in. */
        data class Write(val preset: NewSetPreset) : Choice
    }

    /** The set to open, for the app to show. */
    var opening by mutableStateOf<StudySet?>(null)
    /** New set, ready to make, for the app to raise. */
    var writing by mutableStateOf<NewSetPreset?>(null)

    private var staged: Choice? = null

    fun stage(choice: Choice) { staged = choice }

    /** Called when the picker has closed. */
    fun deliver() {
        val choice = staged ?: return
        staged = null
        when (choice) {
            is Choice.Open -> opening = choice.set
            is Choice.Write -> writing = choice.preset
        }
    }

    /** Forgets everything (a test's fresh start). */
    fun reset() { staged = null; opening = null; writing = null }
}

/** Turn into…, as a More menu's or a row menu's item (iOS StudyMoreMenu and rowMenu). */
@Composable internal fun TurnIntoMenuItem(close: () -> Unit, turn: () -> Unit) {
    DropdownMenuItem(text = { Text("Turn into…") }, leadingIcon = { Icon(Icons.Rounded.Autorenew, null) },
        onClick = { close(); turn() }, modifier = Modifier.testTag("turnInto"))
}

/** The picker for whichever set [turning] holds, if any (iOS View.turnIntoPicker(for:)). */
@Composable fun TurnIntoPickerHost(turning: StudySet?, store: StudyStore, onClose: () -> Unit) {
    turning?.let { TurnIntoPicker(it, store, onClose) }
}

/** What a tile says will happen, with its symbol (iOS TurnIntoPicker.note(for:)). */
internal fun turnNote(source: StudySet, kind: StudySetKind, ready: Map<StudySetKind, StudySet>, hasLecture: Boolean): Pair<String, ImageVector> {
    if (kind == source.kind) return "This set" to Icons.Rounded.Check
    ready[kind]?.let { made ->
        val n = made.itemCount
        val plural = if (n == 1) "" else "s"
        return "Instant · $n ${made.itemNoun}$plural" to Icons.Rounded.Bolt
    }
    return (if (hasLecture) "Written from your lecture. Check before relying on it." else "Written from this set. Check before relying on it.") to Icons.Rounded.AutoAwesome
}

/** "Turn into…" on [source]: a sheet of mode tiles, with Cancel. [onClose] takes it away. */
@Composable fun TurnIntoPicker(source: StudySet, store: StudyStore, onClose: () -> Unit) {
    // every instant conversion, made once when the sheet opens, so each tile
    // can say how many cards or questions it will give
    val ready = remember(source) { ModeConversion.targets.mapNotNull { kind -> ModeConversion.convert(source, kind)?.let { kind to it } }.toMap() }
    val hasLecture = remember(source) { ModeConversion.lecture(source) != null }
    // every mode a set can become, with this set's own among them (shown, not choosable)
    val kinds = if (source.kind in ModeConversion.targets) ModeConversion.targets else listOf(source.kind) + ModeConversion.targets
    fun close() { onClose(); ModeSwitch.deliver() }
    fun pick(kind: StudySetKind) {
        if (kind == source.kind) return
        val made = ready[kind]
        if (made != null) {
            if (runCatching { store.addSet(made) }.isSuccess) ModeSwitch.stage(ModeSwitch.Choice.Open(made))
        } else {
            ModeSwitch.stage(ModeSwitch.Choice.Write(ModeConversion.preset(source, kind)))
        }
        // the app acts on the choice once the sheet has gone
        close()
    }
    ExamSheet(::close) {
        Column(Modifier.fillMaxSize().testTag("turnIntoPicker")) {
            ReaderNavBar("Turn into…", leading = { WardTextButton("Cancel", ::close, kind = WardButtonKind.quiet, fills = false) })
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(WardSpace.gutter.wardDp),
                verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("“${source.name}” stays as it is. The new set is added beside it, with the same subject and folder.",
                    style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
                kinds.chunked(2).forEach { pair ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        pair.forEach { kind ->
                            TurnTile(kind, current = kind == source.kind, said = turnNote(source, kind, ready, hasLecture), Modifier.weight(1f)) { pick(kind) }
                        }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

/** One mode as a soft tile raised off the base; the set's own mode lies low and faint, and cannot be chosen. */
@Composable private fun TurnTile(kind: StudySetKind, current: Boolean, said: Pair<String, ImageVector>, modifier: Modifier, onClick: () -> Unit) {
    WardTile(onClick, modifier.heightIn(min = 124.dp).semantics { contentDescription = "${kind.label}. ${said.first}" }
        .testTag("turnInto-${kind.rawValue}"), enabled = !current) {
        Column(Modifier.fillMaxWidth().padding(WardSpace.gutter.wardDp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            WardIconSquare(modeIcon(kind), tone = WardTone.Accent(WardSection.fromKindRaw(kind.rawValue)), size = 40.0)
            Text(kind.label, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
                Icon(said.second, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(14.dp).padding(top = 1.dp))
                Text(said.first, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 2,
                    overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/**
 * The Turn into… tile's page (iOS CategoryShelves.swift TurnIntoListView):
 * this category's sets that can be turned, newest first; tapping one raises
 * the picker.
 */
@Composable fun TurnIntoListScreen(kinds: List<StudySetKind>, store: StudyStore, revision: Int, onBack: () -> Unit) {
    var turning by remember { mutableStateOf<StudySet?>(null) }
    val sets = remember(revision, kinds) {
        store.library.filter { set -> set.kind in kinds && ModeConversion.targets.any { ModeConversion.canTurn(set, it) } }
            .sortedByDescending { it.updatedAt }
    }
    Column(Modifier.fillMaxSize()) {
        LibraryPageTop("Turn into…", onBack)
        LazyColumn(Modifier.weight(1f).fillMaxWidth().widthIn(max = 760.dp),
            contentPadding = PaddingValues(WardSpace.gutter.wardDp, WardSpace.s.wardDp, WardSpace.gutter.wardDp, WardSpace.xl.wardDp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { LibraryHeading("Pick a set to turn", Modifier.padding(horizontal = 4.dp)) }
            if (sets.isEmpty()) item {
                WardEmptyState(Icons.Rounded.Autorenew, "Nothing to turn yet",
                    "Make a set here first. Then any of them can become questions, flashcards, an OSCE station or a textbook.")
            }
            items(sets, key = { it.id }) { set ->
                LibrarySetRow(set, 0, null, Modifier.fillMaxWidth().wardRaised(WardRadius.card, WardLift.low)
                    .clickable(role = Role.Button) { turning = set }.testTag("turnPick-${set.kind.rawValue}")
                    .padding(horizontal = WardSpace.gutter.wardDp, vertical = 10.dp))
            }
            item {
                Text("The set you pick stays as it is; the new one opens straight away.", Modifier.padding(horizontal = 4.dp),
                    style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        }
    }
    TurnIntoPickerHost(turning, store) { turning = null }
}
