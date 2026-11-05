package com.stethoscore.app

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
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

    private val small = DpSize(160.dp, 160.dp)
    private val medium = DpSize(320.dp, 170.dp)
    private val oneLine = DpSize(160.dp, 72.dp)

    @Test fun dueCards() {
        shots("w01-due-small", small) { DueCards(DueFace.of(due)) }
        shots("w02-due-medium", medium) { DueCards(DueFace.of(due)) }
        shots("w03-due-no-file", small) { DueCards(DueFace.of(GlanceState.NoFile)) }
    }

    @Test fun examCountdown() {
        shots("w04-countdown-small", small) { ExamCountdown(CountdownFace.of(due, now)) }
        shots("w05-countdown-line", oneLine) { ExamCountdown(CountdownFace.of(due, now)) }
    }

    @Test fun doneToday() {
        shots("w06-today-small", small) { DoneToday(TodayFace.of(due, now)) }
        shots("w07-today-line", oneLine) { DoneToday(TodayFace.of(due, now)) }
    }

    /** [content] at [size], light and dark, into the app's external files (widgets/), which adb can pull. */
    private fun shots(name: String, size: DpSize, content: @Composable () -> Unit) {
        val directory = File(context.getExternalFilesDir(null), "widgets").apply { mkdirs() }
        for (dark in listOf(false, true)) {
            val themed = night(context, dark)
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

    private fun night(base: Context, dark: Boolean): Context {
        val config = Configuration(base.resources.configuration)
        val mode = if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or mode
        return base.createConfigurationContext(config)
    }
}
