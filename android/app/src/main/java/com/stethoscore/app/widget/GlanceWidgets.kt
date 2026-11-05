package com.stethoscore.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
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
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.Text
import com.stethoscore.app.AppLink
import com.stethoscore.app.data.GlanceShelf
import com.stethoscore.app.data.GlanceState

// The three home-screen widgets (docs/design/widgets-watches-proposal.md §2),
// drawn with Jetpack Glance from the digest the app writes (GlanceShelf).
// What each says is worked out in WidgetFaces; this file only lays it out,
// as iOS's DueCardsWidget, ExamCountdownWidget and DoneTodayWidget do. No
// widget opens the library or the network, and none shows a streak.

/** The sizes each widget is drawn at (cells: 2x2 small, 4x2 medium, 2x1 one line). */
internal object WidgetSizes {
    val small = DpSize(110.dp, 110.dp)
    val medium = DpSize(250.dp, 110.dp)
    /** A 4x2 widget in portrait: room for both deck rows and the button. */
    val mediumTall = DpSize(250.dp, 180.dp)
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

/** The widget's ground, its tap, and the margins iOS's widgets keep. */
@Composable
private fun Ground(link: AppLink, spoken: String, vertical: Double = WidgetStyle.margin, content: @Composable () -> Unit) {
    Box(
        modifier = GlanceModifier.fillMaxSize().background(WidgetStyle.ground).opens(link)
            .padding(horizontal = WidgetStyle.dp(WidgetStyle.margin), vertical = WidgetStyle.dp(vertical))
            .semantics { contentDescription = spoken },
        contentAlignment = Alignment.TopStart,
    ) { content() }
}

/** The big number and the caption under it, at the widget's foot (iOS's bigCount). */
@Composable
private fun NumberAndCaption(number: String, caption: String, modifier: GlanceModifier = GlanceModifier.fillMaxSize()) {
    Column(modifier = modifier, verticalAlignment = Alignment.Bottom, horizontalAlignment = Alignment.Start) {
        Text(number, style = WidgetStyle.number, maxLines = 1)
        Text(caption, style = WidgetStyle.caption, maxLines = 2)
    }
}

/** The one-line size: a sentence, centred in the height. */
@Composable
private fun OneLine(text: String) {
    Column(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = WidgetStyle.line, maxLines = 2)
    }
}

// MARK: - Due cards

class DueCardsWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(WidgetSizes.small, WidgetSizes.medium, WidgetSizes.mediumTall))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { DueCards(DueFace.of(glanceState())) }
    }
}

@Composable
internal fun DueCards(face: DueFace) {
    val size = LocalSize.current
    if (!DueLayout.isMedium(size.width.value.toDouble())) {
        Ground(face.link, face.spoken) { NumberAndCaption(face.number, face.caption) }
        return
    }
    val rows = DueLayout.rows(size.height.value.toDouble(), face.decks.size, face.showsReview)
    Ground(face.link, face.spoken, vertical = WidgetStyle.mediumVerticalMargin) {
        Row(modifier = GlanceModifier.fillMaxSize()) {
            NumberAndCaption(face.number, face.caption,
                GlanceModifier.defaultWeight().fillMaxHeight().padding(vertical = WidgetStyle.dp(WidgetStyle.margin - WidgetStyle.mediumVerticalMargin)))
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

/** "Review": a 48 dp coral capsule that opens the due cards. */
@Composable
private fun ReviewButton() {
    Box(
        modifier = GlanceModifier.fillMaxWidth().height(WidgetStyle.dp(WidgetStyle.target))
            .background(WidgetStyle.penWash).cornerRadius(WidgetStyle.dp(WidgetStyle.target / 2))
            .opens(AppLink.ReviewDue).semantics { contentDescription = "Review" },
        contentAlignment = Alignment.Center,
    ) { Text("Review", style = WidgetStyle.review, maxLines = 1) }
}

class DueCardsReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DueCardsWidget()
}

// MARK: - Exam countdown

class ExamCountdownWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(WidgetSizes.oneLine, WidgetSizes.small))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            ExamCountdown(CountdownFace.of(glanceState(), System.currentTimeMillis()))
        }
    }
}

@Composable
internal fun ExamCountdown(face: CountdownFace) {
    if (LocalSize.current.height.value < WidgetSizes.oneLineHeight) {
        Ground(face.link, face.line, vertical = WidgetStyle.mediumVerticalMargin) { OneLine(face.line) }
    } else {
        Ground(face.link, face.spoken) { NumberAndCaption(face.number, face.caption) }
    }
}

class ExamCountdownReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ExamCountdownWidget()
}

// MARK: - Done today

class DoneTodayWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(WidgetSizes.oneLine, WidgetSizes.small))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            DoneToday(TodayFace.of(glanceState(), System.currentTimeMillis()))
        }
    }
}

@Composable
internal fun DoneToday(face: TodayFace) {
    if (LocalSize.current.height.value < WidgetSizes.oneLineHeight) {
        Ground(face.link, face.line, vertical = WidgetStyle.mediumVerticalMargin) { OneLine(face.line) }
    } else {
        Ground(face.link, face.line) { NumberAndCaption(face.number, face.caption) }
    }
}

class DoneTodayReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DoneTodayWidget()
}
