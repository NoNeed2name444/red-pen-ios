package com.stethoscore.app.ui.narrate

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.stethoscore.app.audio.FlowLines
import com.stethoscore.app.ui.ward.*
import com.stethoscore.app.ui.wardColor

// The transcript laid out word by word (ios/RedPen/Features/Narrate/NarrateWordFlow.swift,
// fed0105). Every word is its own target - a tap jumps the player to that
// line, a hold of 0.35 seconds offers to fix the word - and a line still reads
// as a line because the words are flowed (FlowLines) rather than stacked.
//
// The spoken word is marked by colour and a wash drawn OUTSIDE its frame,
// never by a bolder weight or extra padding: either would widen the word, the
// line would re-wrap, and every word after it would shuffle sideways.

/** What one line shows: everything that decides how it is drawn, so an unchanged line is skipped. */
internal data class NarrateLineLook(val index: Int, val text: String, val rtl: Boolean, val current: Boolean,
                                    val spoken: Int?, val misheard: Int?)

/** The line for each transcript line, as the flow draws it. */
internal fun narrateLineLooks(texts: List<String>, langs: List<String>, currentIndex: Int, spokenWord: Int?,
                              misheard: FixTarget?): List<NarrateLineLook> = texts.indices.map { i ->
    val current = i == currentIndex
    NarrateLineLook(i, texts[i], i < langs.size && langs[i] == "ar", current,
        if (current) spokenWord else null, if (misheard?.segment == i) misheard.word else null)
}

/** A hold this long fixes a word (iOS's minimumDuration: 0.35). */
private class HoldConfiguration(private val base: ViewConfiguration) : ViewConfiguration by base {
    override val longPressTimeoutMillis: Long get() = 350
}

/** One line of the transcript: its words flowed, the line being read pressed into the page. */
@OptIn(ExperimentalFoundationApi::class)
@Composable internal fun NarrateLine(look: NarrateLineLook, onJump: (Int) -> Unit, onFix: (FixTarget) -> Unit) {
    val words = remember(look.text) { look.text.split(' ').filter { it.isNotEmpty() } }
    val ink = if (look.current) wardColor(WardToken.primaryInk) else wardColor(WardToken.ink)
    val danger = wardColor(WardToken.danger)
    val primary = wardColor(WardToken.primary)
    val shape = RoundedCornerShape(10.dp)
    val configuration = LocalViewConfiguration.current
    CompositionLocalProvider(LocalLayoutDirection provides if (look.rtl) LayoutDirection.Rtl else LayoutDirection.Ltr,
        LocalViewConfiguration provides remember(configuration) { HoldConfiguration(configuration) }) {
        FlowWords(Modifier.then(if (look.current) Modifier.wardInset(shape, WardLift.low) else Modifier)
            .padding(vertical = 6.dp, horizontal = 8.dp)) {
            words.forEachIndexed { w, word ->
                val speaking = look.spoken == w
                val wrong = look.misheard == w
                val wash = if (wrong) danger.copy(alpha = 0.12f) else Color.Transparent
                // quick enough to keep up with the voice, slow enough to glide
                val mark by animateColorAsState(if (speaking) primary.copy(alpha = WardWash.alpha.toFloat()) else wash, tween(100),
                    label = "spokenWash")
                Text(word,
                    Modifier
                        .drawBehind {
                            if (mark.alpha > 0f) drawRoundRect(mark, Offset(-3.dp.toPx(), -1.dp.toPx()),
                                Size(size.width + 6.dp.toPx(), size.height + 2.dp.toPx()), CornerRadius(5.dp.toPx()))
                        }
                        .combinedClickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button,
                            onClickLabel = "Plays from here", onLongClickLabel = "Fix this word",
                            onLongClick = { onFix(FixTarget(look.index, w, word)) },
                            onClick = { onJump(look.index) }),
                    style = WardTextStyle.body.textStyle(), color = if (wrong) danger else ink,
                    textDecoration = if (wrong) TextDecoration.Underline else null)
            }
        }
    }
}

/**
 * Words wrapped the way a paragraph wraps them (iOS FlowLayout): 4 apart,
 * lines 6 apart. Both the measure and the placing break the lines with
 * FlowLines against the width offered.
 */
@Composable internal fun FlowWords(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Layout(content, modifier) { measurables, constraints ->
        val spacing = 4.dp.toPx().toDouble()
        val lineSpacing = 6.dp.roundToPx()
        val placeables = measurables.map { it.measure(Constraints()) }
        val widths = placeables.map { it.width.toDouble() }
        val offered = if (constraints.hasBoundedWidth) constraints.maxWidth.toDouble() else Double.POSITIVE_INFINITY
        val lines = FlowLines.lines(widths, spacing, offered)
        val widest = FlowLines.lineWidths(widths, spacing, lines).maxOrNull() ?: 0.0
        val heights = ArrayList<Int>()
        for ((p, line) in placeables.zip(lines)) if (line < heights.size) heights[line] = maxOf(heights[line], p.height) else heights.add(p.height)
        val height = heights.sum() + lineSpacing * maxOf(0, heights.size - 1)
        val width = kotlin.math.ceil(minOf(widest, offered)).toInt().coerceIn(constraints.minWidth, maxOf(constraints.minWidth, constraints.maxWidth))
        layout(width, height.coerceAtLeast(constraints.minHeight)) {
            var x = 0.0
            var y = 0
            var current = 0
            placeables.forEachIndexed { i, p ->
                while (current < lines[i]) {
                    y += heights[current] + lineSpacing
                    current += 1
                    x = 0.0
                }
                p.placeRelative(x.toInt(), y)
                x += p.width + spacing
            }
        }
    }
}

/**
 * Whether the current line has left the comfortable band (iOS
 * NarrateScrollBand): the transcript is moved only when the line is above
 * 12% or below 72% of the visible height, and never while the student's own
 * scrolling has it (three seconds after they let go).
 */
internal object NarrateScrollBand {
    const val handsOffMillis = 3_000L
    const val anchor = 0.3

    fun needsScroll(top: Int?, bottom: Int?, viewport: Int, now: Long, handsOffUntil: Long): Boolean {
        if (now < handsOffUntil || viewport <= 0) return false
        if (top == null || bottom == null) return true
        return top < viewport * 0.12 || bottom > viewport * 0.72
    }

    /** The line's place in the visible list, or nulls when it is off screen. */
    fun frame(state: LazyListState, line: Int): Pair<Int?, Int?> {
        val info = state.layoutInfo
        val item = info.visibleItemsInfo.firstOrNull { it.key == line } ?: return null to null
        val top = item.offset - info.viewportStartOffset
        return top to top + item.size
    }
}
