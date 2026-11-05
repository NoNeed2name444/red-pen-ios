package com.stethoscore.app.widget

import com.stethoscore.app.AppLink
import com.stethoscore.app.data.GlanceDigest
import com.stethoscore.app.data.GlanceState
import com.stethoscore.app.data.WardWords
import java.time.ZoneId
import kotlin.math.floor

// What the three home-screen widgets say, worked out from the digest's state
// (GlanceShelf.state) in plain Kotlin, so every state is tested on the JVM
// (WidgetFacesTest). The words are iOS's (ios/StethoscoreWidgets:
// DueCardsWidget, ExamCountdownWidget, DoneTodayWidget, GlanceWords); the
// Glance code only draws them. No widget shows a streak.

/** What a widget says when it has no file from the app (iOS GlanceWords). */
object WidgetWords {
    const val openApp = "Open Stethoscore"
    /** The number when there is none to show: an en dash, never read out. */
    const val noNumber = "–"

    /** "12 cards", "1 card" (iOS cardWords). */
    fun cards(count: Int): String = if (count == 1) "1 card" else "$count cards"
}

/** One deck row of the medium Due widget: it opens that deck (owner decision D4). */
data class DeckRow(val name: String, val count: Int, val link: AppLink) {
    /** "Anatomy, 12 cards due" (iOS's accessibility label for the row). */
    val spoken: String get() = "$name, ${WidgetWords.cards(count)} due"
}

/** The Due cards widget. */
data class DueFace(
    val hasFile: Boolean,
    val due: Int,
    /** The big number, or the en dash with no file. */
    val number: String,
    /** "due now", "All caught up", or "Open Stethoscore to see your cards". */
    val caption: String,
    /** The busiest decks, most first (at most three in the digest). */
    val decks: List<DeckRow>,
    /** The Review button shows only with cards due. */
    val showsReview: Boolean,
    /** What a screen reader says for the count and caption together. */
    val spoken: String,
) {
    /** The whole widget's tap, and the Review button's. */
    val link: AppLink get() = AppLink.ReviewDue

    companion object {
        fun of(state: GlanceState): DueFace {
            val digest = digest(state)
            val due = (state as? GlanceState.CardsDue)?.count ?: 0
            val hasFile = state != GlanceState.NoFile
            val caption = when {
                !hasFile -> "${WidgetWords.openApp} to see your cards"
                due == 0 -> "All caught up"
                else -> "due now"
            }
            val decks = digest?.topDecks.orEmpty().map { DeckRow(it.name, it.count, AppLink.OpenSet(it.id.lowercase())) }
            return DueFace(
                hasFile = hasFile, due = due, number = if (hasFile) "$due" else WidgetWords.noNumber, caption = caption,
                decks = decks, showsReview = hasFile && due > 0,
                spoken = if (!hasFile) caption else if (due == 0) caption else "${WidgetWords.cards(due)} due",
            )
        }
    }
}

/** The Exam countdown widget. */
data class CountdownFace(
    val hasFile: Boolean,
    /** Days to the exam; null with no date, or once it has passed (home shows none then either). */
    val days: Int?,
    val number: String,
    /** Under the number: "days to Step 1", "Set your exam date". */
    val caption: String,
    /** The one-line size: home's sentence, "Step 1 in 90 days". */
    val line: String,
) {
    val link: AppLink get() = AppLink.ExamPlan

    /** Spoken for the whole widget: the en dash is never read out. */
    val spoken: String get() = if (days == null) caption else "$number $caption"

    companion object {
        fun of(state: GlanceState, now: Long, zone: ZoneId = ZoneId.systemDefault()): CountdownFace {
            val digest = digest(state)
            val hasFile = digest != null
            val days = digest?.daysToExam(now, zone)?.takeIf { it >= 0 }
            val name = digest?.examName ?: WardWords.defaultExam
            val sentence = WardWords.countdown(days, digest?.examName)
            val caption = when {
                !hasFile -> "${WidgetWords.openApp} to see your countdown"
                days == null -> "Set your exam date"
                days == 0 -> sentence ?: name
                else -> (if (days == 1) "day to " else "days to ") + name
            }
            val line = if (!hasFile) WidgetWords.openApp else sentence ?: "Set your exam date"
            return CountdownFace(hasFile, days, days?.toString() ?: WidgetWords.noNumber, caption, line)
        }
    }
}

/** The Done today widget: today's count against the daily goal. */
data class TodayFace(
    val hasFile: Boolean,
    val today: Int,
    val goal: Int,
    val number: String,
    /** Under the number: "of 50 done today". */
    val caption: String,
    /** The one-line size: "32 of 50 done today". */
    val line: String,
) {
    /** What the 2x2 size says aloud: the sentence, or with no file the caption (iOS DoneTodayWidget.swift:69). */
    val spoken: String get() = if (hasFile) line else caption

    val link: AppLink get() = AppLink.ReviewDue

    companion object {
        fun of(state: GlanceState, now: Long, zone: ZoneId = ZoneId.systemDefault()): TodayFace {
            val digest = digest(state)
            if (digest == null) {
                val goal = GlanceDigest.empty.goalShown
                return TodayFace(false, 0, goal, WidgetWords.noNumber,
                    "${WidgetWords.openApp} to see today’s count", WidgetWords.openApp)
            }
            val today = digest.todayShown(now, zone)
            val goal = digest.goalShown
            return TodayFace(true, today, goal, "$today", "of $goal done today", "$today of $goal done today")
        }
    }
}

/** How the medium Due widget fits its rows: each row and the button at least [WidgetStyle.target] tall. */
object DueLayout {
    /** The widest a small widget is drawn; wider is the medium layout (count left, rows and button right). */
    const val mediumWidth = 200.0
    /** At most two deck rows, so both rows and the button fit a 4x2 widget (the proposal's sizing). */
    const val maxRows = 2

    fun isMedium(widthDp: Double): Boolean = widthDp >= mediumWidth

    /**
     * How many deck rows fit [heightDp] after the widget's own margins and,
     * when it shows, the Review button: two, then one, then none (iOS's
     * ViewThatFits order).
     */
    fun rows(heightDp: Double, decks: Int, review: Boolean): Int {
        val room = heightDp - 2 * WidgetStyle.mediumVerticalMargin - (if (review) WidgetStyle.target else 0.0)
        val fit = if (room <= 0) 0 else floor(room / WidgetStyle.target).toInt()
        return minOf(maxRows, decks, fit).coerceAtLeast(0)
    }
}

private fun digest(state: GlanceState): GlanceDigest? = when (state) {
    GlanceState.NoFile -> null
    is GlanceState.NothingDue -> state.digest
    is GlanceState.CardsDue -> state.digest
}
