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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.ward.WardToken

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
    Column(modifier.animateContentSize().clipToBounds(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(CardReview.badge(card.type).uppercase(), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp, color = wardColor(WardToken.primaryInk))
        if (card.pictureOnFront) CardPicture(card, images, revealed, deck)
        if (card.type == AnkiCardType.CLOZE) {
            // as Anki shows it: the sentence stays where it is, the answer appears in its gap
            Text(clozeSentence(card.clozeText, revealed), fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold, color = wardColor(WardToken.ink),
                modifier = Modifier.semantics { contentDescription = CardReview.clozeSpoken(card.clozeText, revealed) })
        } else {
            Text(card.displayFront, fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold, color = wardColor(WardToken.ink))
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
        card.source?.takeIf { it.isNotEmpty() }?.let { Text(it, fontSize = 13.sp, color = wardColor(WardToken.inkSecondary)) }
    }
}

@Composable private fun CardBack(card: AnkiCard) {
    when (card.type) {
        AnkiCardType.QA -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            card.bullets.forEach { bullet ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("•", fontSize = 17.sp, color = wardColor(WardToken.ink))
                    Text(highlighted(bullet), fontSize = 17.sp, lineHeight = 23.sp, color = wardColor(WardToken.ink))
                }
            }
        }
        // filled in where it stood, in the sentence above: nothing to repeat
        AnkiCardType.CLOZE -> Unit
        // the mask comes off the picture above; the answer is the label it was covering
        AnkiCardType.OCCLUSION -> card.bullets.firstOrNull()?.let { Text(highlighted(it), fontSize = 17.sp, fontWeight = FontWeight.Medium, color = wardColor(WardToken.ink)) }
    }
}

/** "Why / how": a note pressed into the card. */
@Composable private fun CardWhy(why: String) {
    Column(Modifier.padding(top = 4.dp).fillMaxWidth().background(wardColor(WardToken.well), RoundedCornerShape(12.dp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("WHY / HOW", fontSize = 11.sp, letterSpacing = 1.2.sp, fontWeight = FontWeight.SemiBold, color = wardColor(WardToken.inkSecondary), modifier = Modifier.semantics { heading() })
        Text(why, fontSize = 17.sp, lineHeight = 24.sp, color = wardColor(WardToken.ink))
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
 * The four ratings after a card is turned over: Again, Hard, Good, Easy, each in its tone with
 * when it comes back. Two by two on a phone, one row in a wider window, one to a row at the
 * largest text sizes. For the first few cards each button says what it means.
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
    BoxWithConstraints {
        val oneRow = maxWidth >= 600.dp
        Column(verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            if (hints) Text("How well did you remember it?", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = wardColor(WardToken.inkSecondary))
            val all = AnkiRating.entries
            val rows = when { large -> all.map { listOf(it) }; oneRow -> listOf(all); else -> all.chunked(2) }
            rows.forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) { row.forEach { RatingButton(it, labels[it] ?: "", hints, { rate(it) }, Modifier.weight(1f)) } }
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
@Composable private fun RatingButton(rating: AnkiRating, whenBack: String, hints: Boolean, onClick: () -> Unit, modifier: Modifier) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val ink = tone(rating)
    val shape = RoundedCornerShape(16.dp)
    val ground = if (pressed) wardColor(WardToken.well) else wardColor(WardToken.surface)
    Column(modifier.heightIn(min = 56.dp).then(if (pressed) Modifier else Modifier.wardRaised(16.0)).background(ground, shape)
        .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = onClick)
        .semantics { contentDescription = CardReview.title(rating); stateDescription = CardReview.spokenInterval(whenBack) }
        .padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(CardReview.title(rating), color = ink, fontSize = 17.sp, fontWeight = if (rating == AnkiRating.GOOD) FontWeight.Bold else FontWeight.SemiBold, textAlign = TextAlign.Center)
        if (hints) Text(CardReview.meaning(rating), color = ink, fontSize = 13.sp, textAlign = TextAlign.Center)
        if (whenBack.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("back", color = ink, fontSize = 12.sp)
            Text(whenBack, color = ink, fontSize = 12.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold)
        }
    }
}
