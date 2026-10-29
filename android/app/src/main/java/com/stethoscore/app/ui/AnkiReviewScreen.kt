package com.stethoscore.app.ui

import com.stethoscore.app.ui.mock.StudyTitleBar
import com.stethoscore.app.ui.ward.wardRaised
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.*
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.ward.*

// The card review screens: one deck at a time, and everything due across the library. Ports
// of ios/RedPen/Features/Anki/AnkiReviewView.swift and DueTodayView.swift at dcb4745: the
// same sitting (a rating is written to the schedule, and a card due again within twenty
// minutes stays in the queue), the same words, the same finishes and the same Undo, Bury and
// Suspend. Plain Compose in the Ward colours; the header and the big buttons here stand in
// for iOS's StudyProgressHeader and big button styles until the Ward surfaces and controls
// batches bring the shared ones. The bar is the Ward kit's StudyActionBar (ui/ward/WardDeck.kt).
//
// Check accuracy is in More (iOS studyMoreMenu, T0115b2), opening AccuracyWhySheet. Not carried
// over, because Android has no such feature yet: Quiz me (QuizFromCards), the accuracy badge,
// Turn into, Report a problem, Save to Ideas, opening a citation's lecture page, and Due today's
// Listen (commute mode).

/** One deck's review. */
@Composable fun AnkiReviewScreen(set: StudySet, store: StudyStore, onBack: () -> Unit, startRevealed: Boolean = false) {
    var queue by remember(set.id) { mutableStateOf<List<AnkiQueueItem>?>(null) }
    // the card's answer shown, and how many were rated, kept through a rotation or a fold (T0139)
    var revealed by rememberSaveable(set.id) { mutableStateOf(startRevealed) }
    var reviewedCount by rememberSaveable(set.id) { mutableIntStateOf(0) }
    // studying ahead and the card on screen are kept too: the queue is made again
    // after a turn, and a revealed answer is shown only over the card it was revealed on
    var studyingAhead by rememberSaveable(set.id) { mutableStateOf(false) }
    var shownCardId by rememberSaveable(set.id) { mutableStateOf<String?>(null) }
    var undoUntil by remember(set.id) { mutableStateOf<Long?>(null) }
    var verifying by remember(set.id) { mutableStateOf<com.stethoscore.app.accuracy.AccuracyItem?>(null) }
    // the set whose "Turn into…" picker is up (iOS StudyMoreMenu's turning)
    var turning by remember(set.id) { mutableStateOf<StudySet?>(null) }
    // a return to this screen is not a new sitting
    if (queue == null) {
        val made = if (studyingAhead) store.everything(set).sortedBy { it.due } else store.queue(set)
        if (revealed && shownCardId != null && made.firstOrNull()?.id != shownCardId) revealed = false
        queue = made
    }
    val items = queue.orEmpty()
    val current = items.firstOrNull()
    if (shownCardId != current?.id) shownCardId = current?.id

    fun showNext(next: List<AnkiQueueItem>) { queue = next.sortedBy { it.due }; revealed = false }
    fun rate(rating: AnkiRating) {
        val item = current ?: return
        val kept = store.rateCard(item.card, rating)
        reviewedCount++
        undoUntil = System.currentTimeMillis() + CardReview.undoSeconds * 1000
        showNext(CardReview.afterRating(items, item, kept))
    }
    fun undo() {
        undoUntil = null
        val last = store.undoLast() ?: return
        val card = set.cards.firstOrNull { it.id == last.cardId } ?: return
        val before = ReviewPlan.record(card, store.reviews)
        queue = CardReview.afterUndo(items, card, before.intervalMin)
        reviewedCount = maxOf(0, reviewedCount - 1)
        revealed = false
    }
    // a card buried or suspended leaves this sitting at once
    fun leave(item: AnkiQueueItem) { undoUntil = null; showNext(items.filterNot { it.id == item.id }) }
    fun bury() { val item = current ?: return; store.buryCard(item.card); leave(item) }
    fun suspend() { val item = current ?: return; store.suspendCard(item.card); leave(item) }
    fun studyAhead() { studyingAhead = true; showNext(store.everything(set)) }
    val canStudyAhead = set.cards.isNotEmpty() && reviewedCount == 0

    val header = CardReview.deckHeader(items.size, reviewedCount, studyingAhead)
    ReviewKeys(revealed = revealed, hasCard = current != null, onReveal = { revealed = true }, onRate = ::rate, onUndo = { if (undoUntil != null) undo() },
        onReturn = { if (current == null) { if (canStudyAhead) studyAhead() else onBack() } }) {
        // Turn into is the deck's, so it stays when no card is on screen
        ReviewTopBar(set.subject.ifEmpty { "Cards" }, onBack, (if (current == null) emptyList() else listOf(
            MenuEntry("Bury until tomorrow", Icons.Rounded.Bedtime, ::bury),
            MenuEntry("Suspend this card", Icons.Rounded.PauseCircle, ::suspend),
            MenuEntry("Check accuracy", Icons.Rounded.VerifiedUser, { cardAsk(current.card).verifying(set)?.let { verifying = it } }, "checkAccuracy"),
        )) + MenuEntry("Turn into\u2026", Icons.Rounded.Autorenew, { turning = set }, "turnInto"))
        ProgressHeader(header)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (current != null) {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = if (revealed) 8.dp else 24.dp)) {
                    ReviewCardActions(::bury, ::suspend, Modifier.fillMaxWidth()) {
                        ContentCard { AnkiCardFace(current.card, set.images, revealed, set.cards) }
                    }
                }
            } else {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 32.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    val next = CardReview.nextLine(store.nextDue(set), System.currentTimeMillis())
                    when {
                        set.cards.isEmpty() -> WardEmptyState(Icons.Rounded.Inbox, "No cards yet", "This deck has no cards.", WardTone.Grey)
                        reviewedCount > 0 -> FinishHero(Icons.Rounded.Verified, "Done for now", CardReview.doneLine(reviewedCount, next))
                        else -> WardEmptyState(Icons.Rounded.Schedule, "Nothing to review", "No cards in this deck are due yet. $next")
                    }
                }
            }
            ReviewUndoChip(undoUntil, { undoUntil = null }, ::undo)
        }
        // the card's bar folds away; the finish's does not (iOS AnkiReviewView)
        if (current != null) StudyActionBar(folds = true) {
            val labels = ReviewOptions.previewLabels(ReviewPlan.record(current.card, store.reviews), System.currentTimeMillis(), store.examDate, store.reviewSettings.scheduler)
            AnkiFooter(revealed, labels, { revealed = true }, ::rate)
        } else StudyActionBar {
            if (canStudyAhead) Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CardsCompanionButton("Done", onBack, Modifier.weight(1f))
                CardsPrimaryButton("Study it anyway", ::studyAhead, Modifier.weight(1f))
            } else CardsPrimaryButton("Done", onBack, Modifier.fillMaxWidth())
        }
    }
    verifying?.let { AccuracyWhySheet(it, checksWhenUnchecked = true) { verifying = null } }
    com.stethoscore.app.ui.library.TurnIntoPickerHost(turning, store) { turning = null }
}

/** Everything due right now, from every deck at once. */
@Composable fun DueTodayScreen(store: StudyStore, onBack: () -> Unit) {
    var queue by remember { mutableStateOf<List<ReviewPlan.Due>?>(null) }
    var revealed by rememberSaveable { mutableStateOf(false) }
    var reviewedCount by rememberSaveable { mutableIntStateOf(0) }
    var undoUntil by remember { mutableStateOf<Long?>(null) }
    // where the undone card came from, so it can go back in front
    var lastRated by remember { mutableStateOf<ReviewPlan.Due?>(null) }
    var verifying by remember { mutableStateOf<com.stethoscore.app.accuracy.AccuracyItem?>(null) }
    // as one deck's review: a revealed answer only over the card it was revealed on
    var shownCardId by rememberSaveable { mutableStateOf<String?>(null) }
    if (queue == null) {
        val made = store.dueAcross()
        if (revealed && shownCardId != null && made.firstOrNull()?.id != shownCardId) revealed = false
        queue = made
    }
    val items = queue.orEmpty()
    val due = items.firstOrNull()
    if (shownCardId != due?.id) shownCardId = due?.id
    fun deckOf(d: ReviewPlan.Due) = store.library.firstOrNull { it.id == d.setId }

    fun rate(rating: AnkiRating) {
        val d = due ?: return
        val kept = store.rateCard(d.card, rating)
        reviewedCount++
        queue = CardReview.afterRating(items, d, kept)
        revealed = false
        lastRated = d
        undoUntil = System.currentTimeMillis() + CardReview.undoSeconds * 1000
    }
    fun undo() {
        undoUntil = null
        val d = lastRated ?: return
        if (store.lastRating?.cardId != d.card.id) return
        store.undoLast()
        lastRated = null
        queue = listOf(d) + items.filterNot { it.id == d.id }
        reviewedCount = maxOf(0, reviewedCount - 1)
        revealed = false
    }
    // a card buried or suspended leaves the queue at once
    fun leave(d: ReviewPlan.Due) { undoUntil = null; lastRated = null; queue = items.filterNot { it.id == d.id }; revealed = false }
    fun bury() { val d = due ?: return; store.buryCard(d.card); leave(d) }
    fun suspend() { val d = due ?: return; store.suspendCard(d.card); leave(d) }

    val header = CardReview.dueHeader(items.size, reviewedCount)
    ReviewKeys(revealed = revealed, hasCard = due != null, onReveal = { revealed = true }, onRate = ::rate, onUndo = { if (undoUntil != null) undo() }, onReturn = { if (due == null) onBack() }) {
        ReviewTopBar("Due today", onBack, if (due != null && deckOf(due) != null) listOf(
            MenuEntry("Bury until tomorrow", Icons.Rounded.Bedtime, ::bury),
            MenuEntry("Suspend this card", Icons.Rounded.PauseCircle, ::suspend),
            MenuEntry("Check accuracy", Icons.Rounded.VerifiedUser, { deckOf(due)?.let { cardAsk(due.card).verifying(it) }?.let { verifying = it } }, "checkAccuracy"),
        ) else emptyList())
        ProgressHeader(header)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (due != null) {
                val set = deckOf(due)
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = if (revealed) 8.dp else 24.dp)) {
                    ReviewCardActions(::bury, ::suspend, Modifier.fillMaxWidth()) {
                        ContentCard(spacing = 8.dp) {
                            SmallCaps(due.setName)
                            AnkiCardFace(due.card, set?.images.orEmpty(), revealed, set?.cards.orEmpty())
                        }
                    }
                }
            } else {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 32.dp)) {
                    if (reviewedCount > 0) FinishHero(Icons.Rounded.Verified, "That's everything", CardReview.dueEmptyLine(reviewedCount))
                    else WardEmptyState(Icons.Rounded.Schedule, "Nothing due today", CardReview.dueEmptyLine(reviewedCount))
                }
            }
            ReviewUndoChip(undoUntil, { undoUntil = null }, ::undo)
        }
        StudyActionBar {
            if (due != null) {
                val labels = ReviewOptions.previewLabels(ReviewPlan.record(due.card, store.reviews), System.currentTimeMillis(), store.examDate, store.reviewSettings.scheduler)
                AnkiFooter(revealed, labels, { revealed = true }, ::rate)
            } else CardsPrimaryButton("Done", onBack, Modifier.fillMaxWidth())
        }
    }
    verifying?.let { AccuracyWhySheet(it, checksWhenUnchecked = true) { verifying = null } }
}

/**
 * The keys Anki answers to, for a keyboard on a tablet: Space turns the card over, 1 to 4 rate
 * it Again to Easy, Return presses the finish's main button, and Ctrl+Z undoes.
 */
@Composable private fun ReviewKeys(revealed: Boolean, hasCard: Boolean, onReveal: () -> Unit, onRate: (AnkiRating) -> Unit, onUndo: () -> Unit, onReturn: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    Column(Modifier.fillMaxSize().focusRequester(focus).focusable().onPreviewKeyEvent { e ->
        if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
        when {
            e.key == Key.Z && e.isCtrlPressed -> { onUndo(); true }
            hasCard && !revealed && e.key == Key.Spacebar -> { onReveal(); true }
            hasCard && revealed && e.key in ratingKeys -> { onRate(AnkiRating.entries[ratingKeys.indexOf(e.key)]); true }
            !hasCard && (e.key == Key.Enter || e.key == Key.NumPadEnter) -> { onReturn(); true }
            else -> false
        }
    }, content = content)
}

private val ratingKeys = listOf(Key.One, Key.Two, Key.Three, Key.Four)

private data class MenuEntry(val title: String, val icon: ImageVector, val action: () -> Unit, val tag: String? = null)

/** What Check accuracy looks at on a card (iOS AnkiReviewView and DueTodayView accuracyAsk). */
private fun cardAsk(card: AnkiCard): AccuracyAsk =
    AccuracyAsk("Write a flashcard (question and answer) from the source.", item = { com.stethoscore.app.accuracy.AccuracyItem.card(card) }) {
        (listOf(card.front, card.clozeText) + card.bullets + listOf(card.why)).filter { it.isNotEmpty() }.joinToString("\n")
    }

/** Back, the screen's title inline, and More with what can be done to the card on screen (StudyTitleBar). */
@Composable private fun ReviewTopBar(title: String, onBack: () -> Unit, menu: List<MenuEntry>) {
    var open by remember { mutableStateOf(false) }
    StudyTitleBar(title, onBack) {
        Box {
            // with nothing to do, More is a disabled circle: Biro Grey, solid, never faded
            WardCircleButton(Icons.Rounded.MoreHoriz, "More", { open = true }, enabled = menu.isNotEmpty())
            DropdownMenu(open, { open = false }, containerColor = wardColor(WardToken.background)) {
                menu.forEach { entry -> DropdownMenuItem(text = { Text(entry.title) }, leadingIcon = { Icon(entry.icon, null) }, onClick = { open = false; entry.action() },
                    modifier = entry.tag?.let { Modifier.testTag(it) } ?: Modifier) }
            }
        }
    }
}

/** Where you are and how far there is to go: a thin raised slab over the content. */
@Composable private fun ProgressHeader(header: CardReview.Header) {
    Box(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 8.dp), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 700.dp).fillMaxWidth().wardRaised(WardRadius.bar, lift = com.stethoscore.app.ui.ward.WardLift.low)
            .background(wardColor(WardToken.surface), RoundedCornerShape(WardRadius.bar.wardDp)).padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(header.status, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
                // no detail line, and so no gap for one, when there is no count to show (iOS: detail nil)
                if (header.detail.isNotEmpty()) Text(header.detail, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
            // the same thing as a length, in a groove pressed into the slab (iOS ThinProgress:
            // a WardGroove 6 high, its bar 1.5 in from the groove's wall)
            Box(Modifier.fillMaxWidth().height(6.dp).wardInset(CircleShape)) {
                Box(Modifier.padding(1.5.dp).fillMaxWidth(header.fraction.toFloat().coerceIn(0f, 1f)).fillMaxHeight().background(wardColor(WardToken.primaryInk), CircleShape))
            }
        }
    }
}

/** A card standing on the base: raised, a shade off it. */
@Composable private fun ContentCard(spacing: androidx.compose.ui.unit.Dp = 0.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.widthIn(max = 700.dp).fillMaxWidth().wardRaised(WardRadius.card).background(wardColor(WardToken.surface), RoundedCornerShape(WardRadius.card.wardDp)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(spacing), content = content)
}

@Composable private fun SmallCaps(text: String) =
    Text(text.uppercase(), style = wardSmallCapsStyle(), color = wardColor(WardSmallCaps.colour), maxLines = 1, overflow = TextOverflow.Ellipsis)

/** The end of a sitting: the done seal on a raised disc, large, and a line saying what happened. */
@Composable private fun FinishHero(icon: ImageVector, title: String, message: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 24.dp, horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.size(96.dp).wardRaised(48.0).background(wardColor(WardToken.surface), CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, Modifier.size(48.dp), tint = wardColor(WardToken.success))
        }
        Text(title, style = WardTextStyle.title.textStyle(WardWeight.bold), textAlign = TextAlign.Center, color = wardColor(WardToken.ink), modifier = Modifier.semantics { heading() })
        if (message.isNotEmpty()) Text(message, style = WardType.body.textStyle(), textAlign = TextAlign.Center, color = wardColor(WardToken.inkSecondary))
    }
}

/** The screen's one main button (.bigPrimary): raised a step higher, its words in the section's ink, never a fill. */
@Composable internal fun CardsPrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, hint: String? = null) {
    WardButtonBox(onClick, modifier, kind = WardButtonKind.primary, clickLabel = hint) {
        Text(text, textAlign = TextAlign.Center)
    }
}

/** The quieter button beside it: raised, its words in the primary's ink. */
@Composable internal fun CardsCompanionButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.heightIn(min = 56.dp).wardRelief(RoundedCornerShape(50)).background(wardColor(WardToken.surface), RoundedCornerShape(50))
        .clickable(role = Role.Button, onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp), contentAlignment = Alignment.Center) {
        Text(text, style = WardType.headline.textStyle(), color = wardColor(WardToken.primaryInk), textAlign = TextAlign.Center)
    }
}
