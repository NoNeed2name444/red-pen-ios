package com.stethoscore.app

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.stethoscore.app.data.GlanceDigest
import com.stethoscore.app.data.GlanceState
import com.stethoscore.app.widget.CountdownFace
import com.stethoscore.app.widget.DoneToday
import com.stethoscore.app.widget.DueCards
import com.stethoscore.app.widget.DueFace
import com.stethoscore.app.widget.ExamCountdown
import com.stethoscore.app.widget.TodayFace
import com.stethoscore.app.widget.WidgetSizes
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlin.math.roundToInt

/**
 * The home-screen widgets as the launcher draws them: each one composed by
 * Glance into RemoteViews at a widget size, applied in a light and a night
 * configuration, and saved as a picture (<name>-light.png, <name>-dark.png).
 * No launcher or placed widget is needed. capture-screenshots.sh pulls them
 * into screenshots/widgets and counts them apart from ScreenshotTest's: two
 * per name given to shots below.
 */
@OptIn(ExperimentalGlanceRemoteViewsApi::class)
@RunWith(AndroidJUnit4::class)
class WidgetShots {
    private val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val now = System.currentTimeMillis()
    private val day = 86_400_000L
    private val digest = GlanceDigest(
        madeAt = GlanceDigest.seconds(now), dueNow = 24,
        topDecks = listOf(
            GlanceDigest.DueDeck("7c9e6679-7425-40de-944b-e07fc1f90ae7", "Cardiology", 14),
            GlanceDigest.DueDeck("16fd2706-8baf-433b-82eb-8c7fada847da", "Renal", 7),
        ),
        examName = "Step 1", examDate = GlanceDigest.seconds(now + 90 * day), today = 32, goal = 50,
    )
    private val due = GlanceState.CardsDue(digest, digest.dueNow)

    // Each widget at the sizes its layout is drawn for (WidgetSizes), the least of each: the 2x2 floor
    // 110x110 and 110x122, 4x2 250x110 (the button), 250x112 (one deck row), 250x160 (two), and the
    // one-line 110x48. The number steps down where the caption takes two lines, further at the floor, and
    // where the font is larger (NumberStack.fit); w06c is drawn at a font scale of 1.3.
    private val longName = GlanceState.CardsDue(digest.copy(examName = "MRCP Part 1"), digest.dueNow)

    @Test fun dueCards() {
        shots("w01-due-small", WidgetSizes.small) { DueCards(DueFace.of(due)) }
        shots("w01b-due-small-floor", WidgetSizes.smallFloor) { DueCards(DueFace.of(due)) }
        shots("w02-due-medium", WidgetSizes.medium) { DueCards(DueFace.of(due)) }
        shots("w02b-due-medium-one-row", WidgetSizes.mediumOneRow) { DueCards(DueFace.of(due)) }
        shots("w02c-due-medium-tall", WidgetSizes.mediumTall) { DueCards(DueFace.of(due)) }
        shots("w03-due-no-file", WidgetSizes.smallFloor) { DueCards(DueFace.of(GlanceState.NoFile)) }
    }

    @Test fun examCountdown() {
        shots("w04-countdown-small", WidgetSizes.small) { ExamCountdown(CountdownFace.of(due, now)) }
        shots("w04b-countdown-small-floor", WidgetSizes.smallFloor) { ExamCountdown(CountdownFace.of(longName, now)) }
        shots("w04c-countdown-small-two-lines", WidgetSizes.small) { ExamCountdown(CountdownFace.of(longName, now)) }
        shots("w05-countdown-line", WidgetSizes.oneLine) { ExamCountdown(CountdownFace.of(due, now)) }
    }

    @Test fun doneToday() {
        shots("w06-today-small", WidgetSizes.small) { DoneToday(TodayFace.of(due, now)) }
        shots("w06b-today-small-floor", WidgetSizes.smallFloor) { DoneToday(TodayFace.of(due, now)) }
        shots("w06c-today-small-large-text", WidgetSizes.small, fontScale = 1.3f) { DoneToday(TodayFace.of(due, now)) }
        shots("w07-today-line", WidgetSizes.oneLine) { DoneToday(TodayFace.of(due, now)) }
    }

    /**
     * [content] at [size] and the system font scale [fontScale], light and dark, into the app's external
     * files (widgets/), which adb can pull. The configuration's font scale reaches both Glance's
     * LocalContext, where the faces are fitted, and the TextViews the RemoteViews inflate.
     */
    private fun shots(name: String, size: DpSize, fontScale: Float = 1f, content: @Composable () -> Unit) {
        val directory = File(context.getExternalFilesDir(null), "widgets").apply { mkdirs() }
        for (dark in listOf(false, true)) {
            val themed = configured(context, dark, fontScale)
            val views = runBlocking { GlanceRemoteViews().compose(themed, size) { content() } }.remoteViews
            val density = themed.resources.displayMetrics.density
            val width = (size.width.value * density).roundToInt()
            val height = (size.height.value * density).roundToInt()
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                val parent = FrameLayout(themed)
                val view = views.apply(themed, parent)
                parent.addView(view, FrameLayout.LayoutParams(width, height))
                parent.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                parent.layout(0, 0, width, height)
                parent.draw(Canvas(bitmap))
            }
            val file = File(directory, "$name-${if (dark) "dark" else "light"}.png")
            file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            check(file.length() > 0) { "Widget picture was not written: ${file.name}" }
        }
    }

    private fun configured(base: Context, dark: Boolean, fontScale: Float): Context {
        val config = Configuration(base.resources.configuration)
        val mode = if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or mode
        config.fontScale = fontScale
        return base.createConfigurationContext(config)
    }
}
