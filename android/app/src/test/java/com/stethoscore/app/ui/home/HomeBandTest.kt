package com.stethoscore.app.ui.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// The owner, 9 Oct: home's grid only "from upwards till under the
// stethoscore word", as iOS HomeBand (WardPaperBand to the header's bottom
// and HomeBandTrack.belowHeader), with no fading.
class HomeBandTest {
    @Test fun theBandEndsTenUnderTheHeader() = assertEquals(10.0, HomeFit.belowHeader, 0.0)

    @Test fun homeDrawsTheGridAsABandToTheHeader() {
        val app = File("src/main/java/com/stethoscore/app/ui/StethoscoreApp.kt").readText()
        assertTrue("home's ground takes the band's bottom", app.contains("WardGroundBackground(WardGround.home(section, dark),Modifier.fillMaxSize(),gridBottom={ bandBottom })"))
        assertTrue("the header reports its bottom", app.contains("bandBottom=it.positionInWindow().y+it.size.height+below"))
        val ground = File("src/main/java/com/stethoscore/app/ui/WardGroundViews.kt").readText()
        val start = ground.indexOf("@Composable fun WardGroundBackground(")
        val body = ground.substring(start)
        assertTrue("the grid is clipped at the band", body.contains("clipRect(bottom = band)"))
        for (fade in listOf("Brush.", "Gradient", "alpha = 1f -")) assertTrue("the band fades ($fade)", !body.contains(fade))
    }
}
