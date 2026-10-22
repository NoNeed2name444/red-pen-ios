package com.stethoscore.app.ui.vitals

import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import com.stethoscore.app.data.RhythmReading
import com.stethoscore.app.ui.StethoscoreTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.time.ZoneOffset

// Vitals' rhythm card (the owner, 22 Oct: "make it like the monitor"): laid out
// as a bedside monitor in both modes - the trace fills the channel on the left
// and the parameter column (RDY, ACC, Q/D, each a label over a big number)
// stands beside it on the right, level with it, as iOS's RhythmMonitor does.
// The card speaks as one (clearAndSetSemantics), so the screen inside it is
// laid out on its own here, and the card is checked for what TalkBack hears.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class VitalsMonitorTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val dark = mutableStateOf(false)
    private val now = Instant.parse("2026-10-22T12:00:00Z")
    private val reading = RhythmReading.read(
        (0 until 10).associate { RhythmReading.key(now.minusSeconds(86_400L * it), ZoneOffset.UTC) to 5 }, now, ZoneOffset.UTC)

    @Test fun theReadoutsStandBesideTheTraceLikeAMonitor() {
        compose.setContent {
            StethoscoreTheme(dark.value) { MonitorScreen(reading, readiness = 0.68, accuracy = 0.74, today = 12, target = 30) }
        }
        for (mode in listOf(false, true)) {
            dark.value = mode
            compose.waitForIdle()
            val name = if (mode) "dark" else "light"
            val trace = compose.onNodeWithTag("rhythmTrace").getUnclippedBoundsInRoot()
            val column = compose.onNodeWithTag("monitorReadouts").getUnclippedBoundsInRoot()
            assertTrue("$name: the readouts stand right of the trace (${column.left} >= ${trace.right})", column.left >= trace.right)
            assertEquals("$name: the column starts level with the trace", trace.top, column.top)
            assertEquals("$name: the trace fills its channel", MonitorChannel.channel.dp, trace.height)
            assertTrue("$name: the trace takes the wider share (${trace.width} > ${column.width})", trace.width > column.width)
            for (words in listOf("RDY", "ACC", "Q/D", "68%", "74%", "12/30")) compose.onNodeWithText(words).assertExists()
        }
    }

    @Test fun theCardSpeaksAsOneWithTheStreakInItsStrip() {
        compose.setContent {
            StethoscoreTheme(false) { RhythmMonitor(reading, readiness = 0.68, accuracy = 0.74, today = 12, target = 30, streak = 10) }
        }
        compose.onNodeWithContentDescription("10-day streak", substring = true).assertExists()
        compose.onNodeWithContentDescription("Readiness 68 percent", substring = true).assertExists()
    }
}
