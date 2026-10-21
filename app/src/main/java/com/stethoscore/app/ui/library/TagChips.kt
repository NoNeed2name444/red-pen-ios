package com.stethoscore.app.ui.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Sell
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.CardTags
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.WardChipButton
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardField
import com.stethoscore.app.ui.ward.wardInset

// iOS Features/Library/TagChips.swift: tags as capsules pressed into the
// base, each with its x to take it off, a field to add more (Done, or the
// plus), and the library's own tags offered underneath as the typing narrows
// them. The rules (no spaces inside a tag, "::" nests, case ignored) are
// CardTags', so what is typed here matches what came in from Anki.

@OptIn(ExperimentalLayoutApi::class)
@Composable fun TagChipsField(tags: List<String>, onChange: (List<String>) -> Unit, modifier: Modifier = Modifier,
                              known: List<Pair<String, Int>> = emptyList()) {
    var typed by remember { mutableStateOf("") }
    var focused by remember { mutableStateOf(false) }
    fun add() { onChange(CardTags.adding(typed, tags)); typed = "" }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (tags.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            tags.forEach { tag ->
                Row(Modifier.wardInset(CircleShape).padding(start = 10.dp, end = 4.dp, top = 3.dp, bottom = 3.dp)
                    .semantics { contentDescription = "Tag $tag" },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(CardTags.label(tag), style = WardTextStyle.caption.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink),
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Box(Modifier.size(22.dp).clickable(role = Role.Button) { onChange(CardTags.removing(tag, tags)) }
                        .semantics { contentDescription = "Remove tag $tag" }, contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.Close, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(12.dp))
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).wardField(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Rounded.Sell, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
            Box(Modifier.weight(1f)) {
                if (typed.isEmpty()) Text("Add a tag", style = WardTextStyle.body.textStyle(), color = wardColor(WardToken.inkSecondary),
                    modifier = Modifier.clearAndSetSemantics {})
                BasicTextField(typed, { typed = it }, Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused }
                    .semantics { contentDescription = "Add a tag" },
                    textStyle = WardTextStyle.body.textStyle().copy(color = wardColor(WardToken.ink)), singleLine = true,
                    cursorBrush = SolidColor(wardColor(WardToken.primaryInk)),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { add() }))
            }
            val canAdd = CardTags.parse(typed).isNotEmpty()
            Box(Modifier.size(44.dp).clickable(enabled = canAdd, role = Role.Button) { add() }.semantics { contentDescription = "Add tag" },
                contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.AddCircle, null, tint = wardColor(if (canAdd) WardToken.primaryInk else WardToken.inkSecondary),
                    modifier = Modifier.size(24.dp))
            }
        }
        val offered = CardTags.suggestions(typed, known, tags, 8)
        if (offered.isNotEmpty() && (focused || typed.isNotEmpty())) {
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                offered.forEach { tag ->
                    WardChipButton("+ ${CardTags.label(tag)}", { onChange(CardTags.adding(tag, tags)); typed = "" },
                        Modifier.semantics { contentDescription = "Add tag $tag" })
                }
            }
        }
    }
}

/** A row of small read-only tag labels, for a card's row in a list (iOS TagLine). */
@Composable fun TagLine(tags: List<String>, modifier: Modifier = Modifier, limit: Int = 3) {
    if (tags.isEmpty()) return
    val shown = tags.take(limit)
    val more = tags.size - shown.size
    Row(modifier.clearAndSetSemantics { contentDescription = "Tags: " + tags.joinToString(", ") }, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        shown.forEach { tag ->
            Text("#" + CardTags.label(tag), style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary), maxLines = 1)
        }
        if (more > 0) Text("+$more", style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
    }
}
