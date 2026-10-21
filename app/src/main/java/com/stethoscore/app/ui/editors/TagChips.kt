package com.stethoscore.app.ui.editors

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Sell
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.CardTags
import com.stethoscore.app.ui.ward.WardChipButton
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardDisabledInk
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardField
import com.stethoscore.app.ui.ward.wardInset
import com.stethoscore.app.ui.wardColor

// A port of upstream/ios/RedPen/Features/Library/TagChips.swift (fed0105):
// tags as capsules pressed into the base, each with its × to take it off, a
// field to add more (Done, or the plus), and the library's own tags offered
// underneath as chips to tap while the typing narrows them. The rules are
// CardTags', so what is typed matches what came in from Anki.

/** TagChipsField: the tags of a card, a question or a whole set. Null when none, as iOS stores it. */
@OptIn(ExperimentalLayoutApi::class)
@Composable fun TagChipsField(tags: List<String>?, onChange: (List<String>?) -> Unit, known: List<CardTags.Count> = emptyList()) {
    var typed by rememberSaveable { mutableStateOf("") }
    val source = remember { MutableInteractionSource() }
    val focused by source.collectIsFocusedAsState()
    fun add() { onChange(CardTags.adding(typed, tags)); typed = "" }
    fun take(tag: String) { onChange(CardTags.adding(tag, tags)); typed = "" }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (!tags.isNullOrEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            tags.forEach { tag -> TagChip(tag) { onChange(CardTags.removing(tag, tags)) } }
        }
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).wardField(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Rounded.Sell, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
            Box(Modifier.weight(1f)) {
                if (typed.isEmpty()) Text("Add a tag", style = WardType.body.textStyle(), color = wardDisabledInk())
                BasicTextField(typed, { typed = it }, Modifier.fillMaxWidth().semantics { contentDescription = "Add a tag" },
                    singleLine = true, interactionSource = source, textStyle = WardType.body.textStyle().copy(color = wardColor(WardToken.ink)),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { add() }), cursorBrush = SolidColor(wardColor(WardToken.primaryInk)))
            }
            val canAdd = CardTags.parse(typed).isNotEmpty()
            Icon(Icons.Rounded.AddCircle, "Add tag", tint = if (canAdd) wardColor(WardToken.primaryInk) else wardDisabledInk(),
                modifier = Modifier.size(26.dp).clickable(enabled = canAdd, role = Role.Button) { add() })
        }
        val offered = CardTags.suggestions(typed, known, tags, limit = 8)
        if (offered.isNotEmpty() && (focused || typed.isNotEmpty())) Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            offered.forEach { tag -> WardChipButton("+ ${CardTags.label(tag)}", { take(tag) }, Modifier.semantics { contentDescription = "Add tag $tag" }) }
        }
    }
}

/** One tag in its capsule, pressed into the base, with the × that takes it off. */
@Composable private fun TagChip(tag: String, onRemove: () -> Unit) {
    Row(Modifier.wardInset(CircleShape).padding(start = 10.dp, end = 4.dp, top = 3.dp, bottom = 3.dp)
        .semantics { contentDescription = "Tag $tag" }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(CardTags.label(tag), style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Box(Modifier.size(44.dp).padding(11.dp).clickable(role = Role.Button, onClickLabel = "Remove tag $tag", onClick = onRemove)
            .semantics { contentDescription = "Remove tag $tag" }, contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Close, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(12.dp))
        }
    }
}

/** TagLine: a row of small read-only tag labels, for a card's row in a list. */
@Composable fun TagLine(tags: List<String>?, limit: Int = 3) {
    if (tags.isNullOrEmpty()) return
    val shown = tags.take(limit)
    val more = tags.size - shown.size
    Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "Tags: " + tags.joinToString(", ") },
        horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        shown.forEach { Text("#" + CardTags.label(it), style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1) }
        if (more > 0) Text("+$more", style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
    }
}
