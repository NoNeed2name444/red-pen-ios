package com.stethoscore.app.widget

import android.appwidget.AppWidgetProviderInfo
import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.collection.intSetOf
import androidx.glance.appwidget.GlanceAppWidgetManager
import com.stethoscore.app.data.GlanceDigest
import com.stethoscore.app.data.GlanceState
import kotlinx.coroutines.runBlocking
import java.time.Instant
import java.time.ZoneId

/**
 * The widget picker's previews: each widget's own face, drawn by the same
 * composable as on the home screen (DueCards, ExamCountdown, DoneToday) from
 * iOS's gallery numbers, GlanceDigest.sample: 24 cards due, Cardiology 14 and
 * Renal 10, PLAB 1 in 38 days, 32 of a goal of 50 done today. Never a
 * picture, and no logo.
 *
 * Which Android gets what:
 * - Android 15 (API 35) and later: Glance generates them (each widget's
 *   providePreview, at every size it lists), and the app publishes them with
 *   GlanceAppWidgetManager.setWidgetPreviews when one of its screens starts,
 *   again after each install or update and each new font or display size.
 *   Until the app first starts, the picker shows what it shows on older ones.
 * - API 26 to 34: no generated previews (the platform has no call for them).
 *   The picker shows what the launcher draws for a widget with no preview
 *   image or layout, as before; both would be a picture, or a copy of the face
 *   drawn by hand, which the faces' own composables are kept in place of.
 */
object WidgetPreviews {
    /** The receivers whose widgets are published, one preview each, for the home screen (widget_*.xml's category). */
    val receivers = listOf(DueCardsReceiver::class, ExamCountdownReceiver::class, DoneTodayReceiver::class)

    /** iOS's sample decks, with WidgetShots' ids (an id is only a deck row's link, which a preview drops). */
    private val decks = listOf(
        GlanceDigest.DueDeck("7C9E6679-7425-40DE-944B-E07FC1F90AE7", "Cardiology", 14),
        GlanceDigest.DueDeck("16FD2706-8BAF-433B-82EB-8C7FADA847DA", "Renal", 10),
    )

    /** iOS's GlanceDigest.sample at [now] in [zone]: made today, so today's count shows, and the exam 38 days on. */
    fun sample(now: Long, zone: ZoneId = ZoneId.systemDefault()): GlanceState {
        val exam = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(38).atStartOfDay(zone).toInstant().toEpochMilli()
        val digest = GlanceDigest(
            madeAt = GlanceDigest.seconds(now), dueNow = 24, topDecks = decks, nextDue = null,
            examName = "PLAB 1", examDate = exam, today = 32, goal = 50,
        )
        return GlanceState.CardsDue(digest, digest.dueNow)
    }

    private const val publishedKey = "previewsPublishedFor"

    /** What the published previews were drawn for: this install of the app, at this font scale and density. */
    internal fun drawnFor(context: Context): String {
        val installed = runCatching { context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime }.getOrDefault(0L)
        val scale = DrawnScale.of(context.resources.configuration)
        return "$installed ${scale.fontScale} ${scale.densityDpi}"
    }

    /**
     * Publishes the three previews unless they were published for this install
     * and scale (drawnFor). The system limits how often a provider's preview
     * may be set; a refused one is tried again at the next start.
     */
    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    fun publishIfStale(context: Context) {
        val prefs = WidgetUpdates.prefs(context)
        val key = drawnFor(context)
        if (prefs.getString(publishedKey, null) == key) return
        val manager = GlanceAppWidgetManager(context.applicationContext)
        val published = runBlocking {
            receivers.all {
                manager.setWidgetPreviews(it, intSetOf(AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN)) ==
                    GlanceAppWidgetManager.SET_WIDGET_PREVIEWS_RESULT_SUCCESS
            }
        }
        if (published) prefs.edit().putString(publishedKey, key).apply()
    }
}
