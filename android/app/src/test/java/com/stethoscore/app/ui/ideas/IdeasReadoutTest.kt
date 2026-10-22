package com.stethoscore.app.ui.ideas

import org.junit.Assert.assertEquals
import org.junit.Test

// The map's frame-rate readout is a debug aid: never in a release build, and
// in a debug build only while the switch for it is on (the tour turns it off).
class IdeasReadoutTest {
    @Test fun theReadoutShowsOnlyInADebugBuildThatWantsIt() {
        assertEquals(true, IdeasSettings.readoutShown(debug = true, wanted = true))
        assertEquals(false, IdeasSettings.readoutShown(debug = true, wanted = false))
        assertEquals(false, IdeasSettings.readoutShown(debug = false, wanted = true))
        assertEquals(false, IdeasSettings.readoutShown(debug = false, wanted = false))
    }
}
