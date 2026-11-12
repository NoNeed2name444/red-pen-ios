package com.stethoscore.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import com.stethoscore.app.data.BedPlan
import com.stethoscore.app.data.ExamWeekPlanner.Mission
import com.stethoscore.app.data.ExamWeekPlanner.Phase
import com.stethoscore.app.ui.home.HomeRoundCard
import com.stethoscore.app.ui.ward.WardControlSize
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.UUID

// T0244: FoldLayoutTest read a home row ("Item 2, Cardiology. ...") 31.8 dp tall in the tabletop
// posture (Android CI run 43186101851). The row is not that short: it is cut by the edge of the pane
// above the hinge, where the list scrolls, and its touch bounds are cut with it. Here each bed row
// of the round card, whole, is at least 48 dp tall: at the default size, and at font scale 2.0 where
// the row stacks. A row that was short would fail here, before the cut can hide it.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HomeBedRowTargetTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val input = BedPlan.Input(
        phase = Phase.Building(30), mission = Mission.DueCards(12), dueCards = 12, dueFrom = listOf("Cardiology"),
        topics = listOf(BedPlan.Topic("Cardiology", 40, 40, 30), BedPlan.Topic("Renal", 40, 25, 12)),
        fresh = listOf(BedPlan.FreshSet(UUID.randomUUID().toString(), "Nephrotic syndrome", "Renal", BedPlan.Mode.questions, 42, 0L)),
        stations = listOf(BedPlan.Station(UUID.randomUUID().toString(), "CVS examination", false, 0L)),
        secondsPerQuestion = 75, stationMinutes = 8,
    )

    private fun everyBedRowIsWholeAndTallEnough(scale: Float) {
        val beds = BedPlan.beds(input)
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, scale)) {
                StethoscoreTheme { Column(Modifier.verticalScroll(rememberScrollState())) { HomeRoundCard(beds, null, {}) } }
            }
        }
        val rows = compose.onAllNodes(hasClickAction() and hasContentDescription("Item ", substring = true))
        assertEquals("a row for each bed", beds.size, rows.fetchSemanticsNodes().size)
        val least = WardControlSize.target.dp
        for (i in beds.indices) {
            val own = rows[i].getUnclippedBoundsInRoot()
            assertTrue("bed ${i + 1} is $least tall whole at font scale $scale: ${own.height}", own.height >= least)
        }
    }

    @Test fun everyBedRowIsAWhole48DpTall() = everyBedRowIsWholeAndTallEnough(1f)

    @Test fun everyBedRowIsAWhole48DpTallWhereItStacks() = everyBedRowIsWholeAndTallEnough(2f)
}
