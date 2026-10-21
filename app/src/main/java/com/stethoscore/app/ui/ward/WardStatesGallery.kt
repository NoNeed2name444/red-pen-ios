package com.stethoscore.app.ui.ward

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.List
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Book
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Collections
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.Assignment
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

// A port of upstream/ios/RedPen/Shared/Ward/WardStatesGallery.swift: every
// Ward control in each of its states, for one section, drawn with the real
// controls (WardControls). Three columns: at rest, held (drawn held through
// LocalWardShowsPressed, with no finger on it) and disabled. A control that
// can be chosen has two rows, not chosen and chosen, so its six states
// (WardControlStates) are all on one screen. WardStatesTest checks the same
// states' colours for every section and mode on the JVM.

/** A column of the gallery: the state its controls are drawn in. */
enum class WardGalleryColumn(val title: String) { rest("Rest"), held("Held"), disabled("Disabled") }

@Composable fun WardStatesGallery(section: WardSection, modifier: Modifier = Modifier) {
    Column(
        modifier.verticalScroll(rememberScrollState())
            .padding(horizontal = WardSpace.gutter.wardDp, vertical = WardSpace.s.wardDp),
    ) {
        WardSmallCapsText("States · ${section.galleryTitle}", Modifier.semantics { heading() }.padding(bottom = WardSpace.s.wardDp))
        Row(Modifier.fillMaxWidth().padding(bottom = WardSpace.m.wardDp), horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            for (column in WardGalleryColumn.entries) {
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { WardSmallCapsText(column.title) }
            }
        }
        Group {
            States { e -> WardTextButton("Start", {}, kind = WardButtonKind.primary, enabled = e) }
            States { e -> WardTextButton("Skip", {}, kind = WardButtonKind.secondary, enabled = e) }
            States { e -> WardTextButton("Delete", {}, kind = WardButtonKind.destructive, enabled = e) }
            States { e -> WardTextButton("Done", {}, kind = WardButtonKind.compact, enabled = e) }
            States { e -> WardTextButton("Cancel", {}, kind = WardButtonKind.quiet, enabled = e) }
        }
        Group {
            States { e -> ChipAndCircle(chosen = false, enabled = e) }
            States { e -> ChipAndCircle(chosen = true, enabled = e) }
        }
        Group {
            States { e -> WardToggle(false, {}, enabled = e, modifier = Modifier.semantics { contentDescription = "Timed" }) }
            States { e -> WardToggle(true, {}, enabled = e, modifier = Modifier.semantics { contentDescription = "Timed" }) }
            States { e ->
                WardSegmented(0, listOf(0, 1), {}, enabled = e) { option, _, color ->
                    Icon(if (option == 0) Icons.AutoMirrored.Rounded.List else Icons.Rounded.GridView,
                        if (option == 0) "List" else "Grid", tint = color)
                }
            }
        }
        Group(last = true) {
            States { e -> WardTile({}, chosen = false, enabled = e) { WardTileLabel(section.galleryTitle, section.galleryIcon, e) } }
            States { e -> WardTile({}, chosen = true, enabled = e) { WardTileLabel(section.galleryTitle, section.galleryIcon, e) } }
        }
    }
}

@Composable private fun Group(last: Boolean = false, content: @Composable () -> Unit) {
    Column(Modifier.padding(bottom = if (last) 0.dp else WardSpace.l.wardDp), verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
        content()
    }
}

/** One row: the control at rest, held and disabled, a column each. */
@Composable private fun States(control: @Composable (enabled: Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalAlignment = Alignment.CenterVertically) {
        for (column in WardGalleryColumn.entries) {
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                CompositionLocalProvider(LocalWardShowsPressed provides (column == WardGalleryColumn.held)) {
                    control(column != WardGalleryColumn.disabled)
                }
            }
        }
    }
}

/** A chip that is a button and a round button, chosen or not. */
@Composable private fun ChipAndCircle(chosen: Boolean, enabled: Boolean) {
    Row(horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp), verticalAlignment = Alignment.CenterVertically) {
        WardChipButton("Hint", {}, on = chosen, enabled = enabled)
        WardCircleButton(Icons.Rounded.Add, "Add", {}, on = chosen, enabled = enabled)
    }
}

/** The section's name, for the gallery's heading and its tile. */
val WardSection.galleryTitle: String get() = when (this) {
    WardSection.questions -> "Questions"
    WardSection.cards -> "Cards"
    WardSection.textbook -> "Textbook"
    WardSection.cases -> "Cases"
    WardSection.osce -> "OSCE"
    WardSection.audio -> "Audio"
    WardSection.ideas -> "Ideas"
}

/** The section's glyph, the nearest Material icon to its mode's symbol. */
val WardSection.galleryIcon: ImageVector get() = when (this) {
    WardSection.questions -> Icons.Rounded.Checklist
    WardSection.cards -> Icons.Rounded.Collections
    WardSection.textbook -> Icons.Rounded.Book
    WardSection.cases -> Icons.Rounded.MedicalServices
    WardSection.osce -> Icons.Rounded.Assignment
    WardSection.audio -> Icons.Rounded.GraphicEq
    WardSection.ideas -> Icons.Rounded.Lightbulb
}
