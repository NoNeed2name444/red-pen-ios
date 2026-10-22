package com.stethoscore.app.ui

import com.stethoscore.app.ui.ward.wardRaised
import android.content.Context
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.ward.*

// One card's face, front and back, and the bar under it that turns it over and rates it.
// Port of ios/RedPen/Features/Anki/AnkiCardFace.swift (AnkiCardFace, AnkiFooter,
// AnkiRatingBar) at dcb4745. Plain Compose in the Ward colours (wardColor): the Ward
// surfaces and controls are being ported in their own batches, so nothing here is a Ward*
// component of its own.

/** What one card looks like: the badge, the picture, the question, and once revealed the answer under it. */
@Composable fun AnkiCardFace(card: AnkiCard, images: List<String>, revealed: Boolean, deck: List<AnkiCard> = emptyList(), modifier: Modifier = Modifier) {
    val view = LocalView.current
    // turned over: the answer is read out, so a screen reader need not go and find it
    LaunchedEffect(revealed) { if (revealed) @Suppress("DEPRECATION") view.announceForAccessibility(CardReview.spokenBack(card)) }
    // with animations off the answer is simply there (iOS: reduceMotion ? nil : .snappy(duration: 0.28))
    val reduce = com.stethoscore.app.ui.ward.wardReduceMotion()
    Column(modifier.then(if (reduce) Modifier else Modifier.animateContentSize()).clipToBounds(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(CardReview.badge(card.type).uppercase(), style = wardSmallCapsStyle(), color = wardColor(WardToken.primaryInk))
        if (card.pictureOnFront) CardPicture(card, images, revealed, deck)
        if (card.type == AnkiCardType.CLOZE) {
            // as Anki shows it: the sentence stays where it is, the answer appears in its gap
            Text(clozeSentence(card.clozeText, revealed), style = WardType.title.textStyle(), color = wardColor(WardToken.ink),
                modifier = Modifier.semantics { contentDescription = CardReview.clozeSpoken(card.clozeText, revealed) })
        } else {
            Text(card.displayFront, style = WardType.title.textStyle(), color = wardColor(WardToken.ink))
        }
        if (revealed) {
            // the answer opens under the question: nothing turns over (a cloze fills its gap instead)
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                if (card.type != AnkiCardType.CLOZE) HorizontalDivider(thickness = 1.dp, color = wardColor(WardToken.hairline))
                CardBack(card)
                if (!card.pictureOnFront) CardPicture(card, images, revealed, deck)
                if (card.why.isNotBlank()) CardWhy(card.why)
            }
        }
        card.source?.takeIf { it.isNotEmpty() }?.let { Text(it, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary)) }
    }
}

@Composable private fun CardBack(card: AnkiCard) {
    when (card.type) {
        AnkiCardType.QA -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            card.bullets.forEach { bullet ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("•", style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                    Text(highlighted(bullet), style = WardType.body.textStyle(), color = wardColor(WardToken.ink))
                }
            }
        }
        // filled in where it stood, in the sentence above: nothing to repeat
        AnkiCardType.CLOZE -> Unit
        // the mask comes off the picture above; the answer is the label it was covering
        AnkiCardType.OCCLUSION -> card.bullets.firstOrNull()?.let { Text(highlighted(it), style = WardTextStyle.body.textStyle(WardWeight.medium), color = wardColor(WardToken.ink)) }
    }
}

/** "Why / how": a note pressed into the card (iOS: wardInset at the field's radius). */
@Composable private fun CardWhy(why: String) {
    Column(Modifier.padding(top = 4.dp).fillMaxWidth().wardInset(RoundedCornerShape(WardRadius.field.wardDp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        WardSmallCapsText("Why / how", Modifier.semantics { heading() })
        // iOS sets the note with 2 points more between its lines (lineSpacing(2))
        Text(why, style = WardType.body.textStyle().copy(lineHeight = (WardType.body.line + 2).sp), color = wardColor(WardToken.ink))
    }
}

/** A cloze sentence with its gaps as Anki draws them: "[...]" (or the hint), then the answer, bold, in place. */
@Composable private fun clozeSentence(text: String, revealed: Boolean): AnnotatedString {
    val ink = wardColor(WardToken.primaryInk)
    return buildAnnotatedString {
        CardReview.clozePieces(text).forEach { piece ->
            if (!piece.isGap) append(piece.text)
            else withStyle(SpanStyle(color = ink, fontWeight = FontWeight.Bold)) { append(if (revealed) piece.text else CardReview.clozeGap(piece)) }
        }
    }
}

/** `**term**` markers as real bold. */
private fun highlighted(s: String): AnnotatedString = buildAnnotatedString {
    CardReview.boldRuns(s).forEach { (text, bold) -> if (bold) withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(text) } else append(text) }
}

private fun rgb(t: Triple<Double, Double, Double>) = Color(t.first.toFloat(), t.second.toFloat(), t.third.toFloat())

/** The card's picture: an occlusion card's with its covers, any other card's as it came. */
@Composable private fun CardPicture(card: AnkiCard, images: List<String>, revealed: Boolean, deck: List<AnkiCard>) {
    val encoded = card.imageIndex?.let { images.getOrNull(it) } ?: return
    // decoded once, not on every redraw
    val bitmap = remember(encoded) { runCatching { if (encoded.startsWith("blob:")) null else { val bytes = Base64.decode(encoded.substringAfter("base64,", encoded), Base64.DEFAULT); BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() } }.getOrNull() } ?: return
    val aspect = bitmap.width.toFloat() / bitmap.height.coerceAtLeast(1)
    if (card.type != AnkiCardType.OCCLUSION) {
        Image(bitmap, "Picture on the card", Modifier.heightIn(max = 280.dp).aspectRatio(aspect, matchHeightConstraintsFirst = true))
        return
    }
    val others = remember(card, deck) { OcclusionCovers.others(card, deck) }
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    Box(Modifier.heightIn(max = 280.dp).aspectRatio(aspect, matchHeightConstraintsFirst = true).semantics {
        contentDescription = if (revealed) "Picture, with the hidden label now outlined" else "Picture, with one label hidden under a question mark"
    }) {
        Image(bitmap, null, Modifier.fillMaxSize())
        Canvas(Modifier.fillMaxSize()) {
            val px = density.density.toDouble()
            fun place(box: OcclusionBox) = OcclusionCovers.rect(box, size.width / px, size.height / px)
            others.forEach { box -> place(box)?.let { r -> drawRect(rgb(OcclusionCovers.otherRgb), Offset((r.x * px).toFloat(), (r.y * px).toFloat()), Size((r.w * px).toFloat(), (r.h * px).toFloat())) } }
            val target = card.occlusion?.let(::place) ?: return@Canvas
            val at = Offset((target.x * px).toFloat(), (target.y * px).toFloat()); val sized = Size((target.w * px).toFloat(), (target.h * px).toFloat())
            val orange = rgb(OcclusionCovers.targetRgb)
            if (revealed) drawRect(orange, at, sized, style = Stroke(2.dp.toPx()))
            else {
                drawRect(orange, at, sized)
                val mark = measurer.measure("?", TextStyle(color = Color.White, fontWeight = FontWeight.Bold, fontSize = maxOf(9.0, minOf(target.h * 0.7, 22.0)).sp))
                drawText(mark, topLeft = Offset(at.x + (sized.width - mark.size.width) / 2, at.y + (sized.height - mark.size.height) / 2))
            }
        }
    }
}

/**
 * What sits in a card screen's bottom bar: Reveal while the card is face down, then the four
 * ratings. [companion] is an optional small button at the leading end of the Reveal row.
 */
@Composable fun AnkiFooter(revealed: Boolean, labels: Map<AnkiRating, String>, onReveal: () -> Unit, onRate: (AnkiRating) -> Unit, companion: (@Composable RowScope.() -> Unit)? = null) {
    if (revealed) AnkiRatingBar(labels, onRate)
    else Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        companion?.invoke(this)
        CardsPrimaryButton("Reveal", onReveal, Modifier.weight(1f), hint = "Shows the answer. Say it to yourself first.")
    }
}

private const val hintsKey = "anki.ratingHintsShown"

/**
 * The four ratings after a card is turned over: Again, Hard, Good, Easy, each one word in its
 * tone with no caption line, side by side in one row on every window (the owner, 22 Oct: not
 * two by two), each 48 dp tall; one to a row only at the largest text sizes. What each means and
 * when it comes back are TalkBack's (hint and state), not lines on the button. For the first
 * few cards a line above asks the question the buttons answer.
 */
@Composable fun AnkiRatingBar(labels: Map<AnkiRating, String>, onRate: (AnkiRating) -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("review", Context.MODE_PRIVATE) }
    var hintsShown by remember { mutableIntStateOf(runCatching { prefs.getInt(hintsKey, 0) }.getOrDefault(0)) }
    val hints = hintsShown < CardReview.hintCards
    val view = LocalView.current
    val rate: (AnkiRating) -> Unit = { rating ->
        if (hintsShown < CardReview.hintCards) { hintsShown++; runCatching { prefs.edit().putInt(hintsKey, hintsShown).apply() } }
        onRate(rating)
        @Suppress("DEPRECATION") view.announceForAccessibility("Rated " + CardReview.spokenRating(rating, labels[rating] ?: "") + ".")
    }
    val large = LocalDensity.current.fontScale >= 1.5f
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        if (hints) Text("How well did you remember it?", style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.inkSecondary))
        val rows = CardReview.ratingRows(large)
        rows.forEach { row ->
            Row(Modifier.testTag("ratingRow"), horizontalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
                row.forEach { RatingButton(it, labels[it] ?: "", { rate(it) }, Modifier.weight(1f)) }
            }
        }
    }
}

@Composable private fun tone(rating: AnkiRating): Color = wardColor(when (rating) {
    AnkiRating.AGAIN -> WardToken.danger
    AnkiRating.HARD -> WardToken.warning
    AnkiRating.GOOD -> WardToken.success
    AnkiRating.EASY -> WardToken.primaryInk
})

/** A soft tile raised off the base, its words in the rating's tone; Good, the one to press most, in bold. */
@Composable private fun RatingButton(rating: AnkiRating, whenBack: String, onClick: () -> Unit, modifier: Modifier) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val ink = tone(rating)
    val shape = RoundedCornerShape(WardRadius.button.wardDp)
    // held, it is a well pressed into the base: the well's fill, told by its inset shadows only
    val face = if (pressed) Modifier.wardInset(shape) else Modifier.wardRaised(WardRadius.button).background(wardColor(WardToken.surface), shape)
    // the word alone: what it means and when the card comes back are TalkBack's
    Box(modifier.heightIn(min = CardReview.ratingHeight.dp).then(face)
        .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClickLabel = CardReview.meaning(rating), onClick = onClick)
        .semantics { contentDescription = CardReview.title(rating); stateDescription = CardReview.spokenInterval(whenBack) }
        .padding(horizontal = 4.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
        // one line, never clipped: it shrinks to CardReview.leastWordScale of its size before it
        // would cross the button's edge, as iOS's minimumScaleFactor does
        val style = WardTextStyle.headline.textStyle(if (rating == AnkiRating.GOOD) WardWeight.bold else WardWeight.semibold)
            .copy(color = ink, textAlign = TextAlign.Center)
        androidx.compose.foundation.text.BasicText(CardReview.title(rating), style = style, maxLines = 1, softWrap = false,
            autoSize = androidx.compose.foundation.text.TextAutoSize.StepBased(
                minFontSize = style.fontSize * CardReview.leastWordScale, maxFontSize = style.fontSize, stepSize = 0.25.sp))
    }
}
