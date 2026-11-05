package com.stethoscore.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.unit.ColorProvider
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.Text
import com.stethoscore.app.AppLink
import com.stethoscore.app.R
import com.stethoscore.app.data.GlanceShelf
import com.stethoscore.app.data.GlanceState

// The three home-screen widgets (docs/design/widgets-watches-proposal.md §2),
// drawn with Jetpack Glance from the digest the app writes (GlanceShelf).
// What each says is worked out in WidgetFaces; this file only lays it out,
// as iOS's DueCardsWidget, ExamCountdownWidget and DoneTodayWidget do. No
// widget opens the library or the network, and none shows a streak.

/** The sizes each widget is drawn at (cells: 2x2 small, 4x2 medium, 2x1 one line). */
internal object WidgetSizes {
    /** A 2x2 at least 122 dp tall: the number at iOS's 44 sp, whatever the caption. */
    val small = DpSize(110.dp, 122.dp)
    /** A 2x2 from 110 to 121 dp tall: the number steps down where the caption takes two lines (NumberStack.fit). */
    val smallFloor = DpSize(110.dp, 110.dp)
    val medium = DpSize(250.dp, 110.dp)
    /** A 4x2 widget 112 to 159 dp tall: one deck row and the button. */
    val mediumOneRow = DpSize(250.dp, 112.dp)
    /** A 4x2 widget at least 160 dp tall: both deck rows and the button, 48 dp each, with 8 dp above and below. */
    val mediumTall = DpSize(250.dp, 160.dp)
    val oneLine = DpSize(110.dp, 48.dp)
    /** Below this height a widget draws its one-line size. */
    const val oneLineHeight = 100.0
}

/**
 * What the widget shows now: the file on disk, read again each time
 * WidgetUpdates says it changed, so a widget whose Glance session is still
 * running redraws too, not only one that starts a new session.
 */
@Composable
private fun glanceState(): GlanceState {
    val context = LocalContext.current
    val version by WidgetUpdates.version.collectAsState()
    return remember(version) { GlanceShelf(context.filesDir).state(System.currentTimeMillis()) }
}

/** A tap that opens [link] in the app (WidgetLinks). */
@Composable
private fun GlanceModifier.opens(link: AppLink): GlanceModifier =
    clickable(actionStartActivity(WidgetLinks.intent(LocalContext.current, link)))

/** The widget's ground, its tap, and its margins: iOS's 16 dp at the sides; 12 dp above and below a 2x2 (FaceRoom). */
@Composable
private fun Ground(link: AppLink, spoken: String, vertical: Double = WidgetStyle.smallVerticalMargin, content: @Composable () -> Unit) {
    Box(
        modifier = GlanceModifier.fillMaxSize().background(WidgetStyle.ground).opens(link)
            .padding(horizontal = WidgetStyle.dp(WidgetStyle.margin), vertical = WidgetStyle.dp(vertical))
            .semantics { contentDescription = spoken },
        contentAlignment = Alignment.TopStart,
    ) { content() }
}

/**
 * The glyph at the top, then the big number and the caption under it at the
 * widget's foot (iOS's bigCount), as [fit] sizes them for the room. The glyph
 * stands in the number's top line padding, where nothing is drawn.
 */
@Composable
private fun NumberAndCaption(glyph: Int, number: String, fit: StackFit, modifier: GlanceModifier = GlanceModifier.fillMaxSize()) {
    Box(modifier = modifier, contentAlignment = Alignment.TopStart) {
        Glyph(glyph, WidgetStyle.pen)
        Column(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.Bottom, horizontalAlignment = Alignment.Start) {
            Text(number, style = WidgetStyle.number(fit.numberSize), maxLines = 1)
            Text(fit.caption, style = WidgetStyle.caption, maxLines = NumberStack.captionLines)
        }
    }
}

/** The size Glance lays this face out for (one of WidgetSizes), in dp. */
@Composable
private fun laidOut(): Pair<Double, Double> = LocalSize.current.let { it.width.value.toDouble() to it.height.value.toDouble() }

/** A Material glyph in place of iOS's SF Symbol, decorative: the words beside it say what it means. */
@Composable
private fun Glyph(glyph: Int, colour: ColorProvider) {
    Image(ImageProvider(glyph), contentDescription = null, colorFilter = ColorFilter.tint(colour),
        modifier = GlanceModifier.size(WidgetStyle.dp(WidgetStyle.glyph)))
}

/** The one-line size: the first of [forms] that fits 110 dp across, one line, centred in a height that can be 40 dp (widget_today.xml). */
@Composable
private fun OneLine(forms: List<String>) {
    val (width, height) = laidOut()
    Column(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
        Text(OneLineFit.pick(forms, FaceRoom.oneLine(width, height)), style = WidgetStyle.line, maxLines = 1)
    }
}

// MARK: - Due cards

class DueCardsWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(WidgetSizes.smallFloor, WidgetSizes.small, WidgetSizes.medium, WidgetSizes.mediumOneRow, WidgetSizes.mediumTall))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { DueCards(DueFace.of(glanceState())) }
    }
}

@Composable
internal fun DueCards(face: DueFace) {
    val (width, height) = laidOut()
    if (!DueLayout.isMedium(width)) {
        Ground(face.link, face.spoken) {
            NumberAndCaption(R.drawable.ic_widget_stack, face.number, NumberStack.fit(face.number, face.captions, FaceRoom.small(width, height)))
        }
        return
    }
    val rows = DueLayout.rows(height, face.decks.size, face.showsReview)
    Ground(face.link, face.spoken, vertical = WidgetStyle.mediumVerticalMargin) {
        Row(modifier = GlanceModifier.fillMaxSize()) {
            // only the widget's own 8 dp above and below, as iOS's medium margins (DueCardsWidget.swift:39-40)
            NumberAndCaption(R.drawable.ic_widget_stack, face.number,
                NumberStack.fit(face.number, face.captions, FaceRoom.mediumLeft(width, height)), GlanceModifier.defaultWeight().fillMaxHeight())
            Spacer(GlanceModifier.width(WidgetStyle.dp(WidgetStyle.margin)))
            Column(modifier = GlanceModifier.defaultWeight().fillMaxHeight()) {
                for (deck in face.decks.take(rows)) DeckLine(deck)
                Spacer(GlanceModifier.defaultWeight())
                if (face.showsReview) ReviewButton()
            }
        }
    }
}

/** One deck: its name and count, a 48 dp row that opens the deck. */
@Composable
private fun DeckLine(deck: DeckRow) {
    Row(
        modifier = GlanceModifier.fillMaxWidth().height(WidgetStyle.dp(WidgetStyle.target)).opens(deck.link)
            .semantics { contentDescription = deck.spoken },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(deck.name, style = WidgetStyle.deck, maxLines = 1, modifier = GlanceModifier.defaultWeight())
        Spacer(GlanceModifier.width(WidgetStyle.dp(WidgetStyle.gap)))
        Text("${deck.count}", style = WidgetStyle.deck, maxLines = 1)
    }
}

/**
 * "Review": a 48 dp coral capsule that opens the due cards. The capsule is a
 * drawable, so it is round on every version; cornerRadius, from API 31, only
 * clips the press ripple to it.
 */
@Composable
private fun ReviewButton() {
    Box(
        modifier = GlanceModifier.fillMaxWidth().height(WidgetStyle.dp(WidgetStyle.target))
            .background(ImageProvider(R.drawable.widget_review_capsule), alpha = WidgetStyle.reviewWash,
                colorFilter = ColorFilter.tint(WidgetStyle.pen))
            .cornerRadius(WidgetStyle.dp(WidgetStyle.target / 2))
            .opens(AppLink.ReviewDue).semantics { contentDescription = "Review" },
        contentAlignment = Alignment.Center,
    ) {
        // Chart Ink on the wash: coral is kept for the capsule (WidgetStyle.review)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Glyph(R.drawable.ic_widget_play, WidgetStyle.ink)
            Spacer(GlanceModifier.width(WidgetStyle.dp(WidgetStyle.gap)))
            Text("Review", style = WidgetStyle.review, maxLines = 1)
        }
    }
}

class DueCardsReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DueCardsWidget()
}

// MARK: - Exam countdown

class ExamCountdownWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(WidgetSizes.oneLine, WidgetSizes.smallFloor, WidgetSizes.small))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            ExamCountdown(CountdownFace.of(glanceState(), System.currentTimeMillis()))
        }
    }
}

@Composable
internal fun ExamCountdown(face: CountdownFace) {
    val (width, height) = laidOut()
    if (height < WidgetSizes.oneLineHeight) {
        // home's sentence where it fits, else "90 days" and the like; read out whole
        Ground(face.link, face.line, vertical = WidgetStyle.mediumVerticalMargin) { OneLine(face.lineForms) }
    } else {
        Ground(face.link, face.spoken) {
            NumberAndCaption(R.drawable.ic_widget_calendar, face.number, NumberStack.fit(face.number, face.captions, FaceRoom.small(width, height)))
        }
    }
}

class ExamCountdownReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ExamCountdownWidget()
}

// MARK: - Done today

class DoneTodayWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(WidgetSizes.oneLine, WidgetSizes.smallFloor, WidgetSizes.small))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            DoneToday(TodayFace.of(glanceState(), System.currentTimeMillis()))
        }
    }
}

@Composable
internal fun DoneToday(face: TodayFace) {
    val (width, height) = laidOut()
    if (height < WidgetSizes.oneLineHeight) {
        // the sentence is too wide for a 2x1 at 110 dp, so it shows "32/50 today" and is read out whole
        Ground(face.link, face.line, vertical = WidgetStyle.mediumVerticalMargin) { OneLine(face.lineForms) }
    } else {
        Ground(face.link, face.spoken) {
            NumberAndCaption(R.drawable.ic_widget_check, face.number, NumberStack.fit(face.number, face.captions, FaceRoom.small(width, height)))
        }
    }
}

class DoneTodayReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DoneTodayWidget()
}
