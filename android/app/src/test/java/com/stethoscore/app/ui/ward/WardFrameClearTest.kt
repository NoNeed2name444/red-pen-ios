package com.stethoscore.app.ui.ward

import org.junit.Test
import java.io.File

// The paper frame against the system bars and the display's corner (the
// owner, 22 Oct: the frame never crosses or hides a system bar or a
// control, and every radius near a corner matches the device's). The same
// cases as ios/RedPen/Tests/WardFrameClearTests.swift.
class WardFrameClearTest {

    /** Phones in dp: 1080 x 2400 at 2.625, with a short and a tall status bar, gesture and button navigation, and a landscape cut-out. */
    private data class Phone(val label: String, val width: Double, val height: Double, val safe: WardSystemInsets, val device: Double?)

    private val phones = listOf(
        Phone("pixel gestures", 411.43, 914.29, WardSystemInsets(top = 24.0, bottom = 24.0), 46.0),
        Phone("punch hole, tall bar", 411.43, 914.29, WardSystemInsets(top = 52.0, bottom = 16.0), 52.0),
        Phone("three buttons", 360.0, 800.0, WardSystemInsets(top = 24.0, bottom = 48.0), null),
        Phone("square screen", 360.0, 640.0, WardSystemInsets(top = 24.0, bottom = 48.0), 0.0),
        Phone("landscape cut-out", 914.29, 411.43, WardSystemInsets(top = 24.0, bottom = 16.0, left = 48.0), 46.0),
        Phone("no bars", 402.0, 874.0, WardSystemInsets.none, null),
    )

    @Test fun concentricRule() = checks {
        check("radius is the device's less the inset", WardCorner.concentric(device = 46.0, inset = 12.0, floor = WardEdge.minRadius) == 34.0)
        check("floored at the element's own minimum", WardCorner.concentric(device = 46.0, inset = 40.0, floor = WardRadius.bar) == WardRadius.bar)
        // a device with square corners: every corner element takes its own minimum
        for ((name, floor) in listOf("ring" to WardEdge.minRadius, "dock" to WardRadius.bar, "card" to WardRadius.card,
                "button" to WardRadius.button, "tile" to WardRadius.tile)) {
            for (inset in listOf(0.0, WardPaper.frame, WardPaper.sideInset, 48.0)) {
                check("corner 0: $name at $inset takes its minimum", WardCorner.concentric(0.0, inset, floor) == floor)
            }
        }
        check("the frame's corner with a reported 0", WardPaper.panel(411.43, 914.29, WardSystemInsets(24.0, 24.0), 0.0)!!.let {
            it.radius == WardEdge.minRadius && it.bottomRadius == WardEdge.minRadius })
    }

    @Test fun frameClearsTheBars() = checks {
        val half = WardPaper.edgeWidth / 2
        for (p in phones) {
            val panel = WardPaper.panel(p.width, p.height, p.safe, p.device)
            check("${p.label}: a panel", panel != null)
            panel ?: continue
            // the ring's outer edge, so its inner edge too, stays clear of every bar
            check("${p.label}: clear of the status bar", panel.y - half >= p.safe.top - 1e-9, "ring top ${panel.y - half}, bar ${p.safe.top}")
            check("${p.label}: inner edge below the status bar", panel.y + half > p.safe.top)
            check("${p.label}: clear of the navigation bar", panel.y + panel.height + half <= p.height - p.safe.bottom + 1e-9,
                "ring bottom ${panel.y + panel.height + half}, bar from ${p.height - p.safe.bottom}")
            check("${p.label}: clear of the side bars", panel.x - half >= p.safe.left - 1e-9 &&
                panel.x + panel.width + half <= p.width - p.safe.right + 1e-9)
            check("${p.label}: never nearer the edge than the frame", panel.x >= WardPaper.frame && panel.y >= WardPaper.frame)
            // each corner concentric with the display, floored
            val device = p.device ?: WardPaper.deviceRadius(p.width, p.height)
            val side = maxOf(panel.x, p.width - panel.x - panel.width)
            val cap = minOf(panel.width, panel.height) / (2 * 1.52866483)
            check("${p.label}: top corners concentric", panel.radius ==
                minOf(WardCorner.concentric(device, maxOf(side, panel.y), WardEdge.minRadius), cap))
            check("${p.label}: bottom corners concentric", panel.bottomRadius ==
                minOf(WardCorner.concentric(device, maxOf(side, p.height - panel.y - panel.height), WardEdge.minRadius), cap))
            // the moved opening keeps the bars clear too
            val moved = WardPaper.panel(p.width, p.height, top = 4.0, safe = p.safe, device = p.device)!!
            check("${p.label}: a top above the bar is held below it", moved.y == panel.y)
            // the outline's bottom takes the bottom corners' radius
            val outline = WardEdge.outline(panel)
            check("${p.label}: outline inside the panel", outline.all { it.y >= panel.y - 1e-9 && it.y <= panel.y + panel.height + 1e-9 })
        }
        check("no bars, no device: the frame as before", WardPaper.panel(402.0, 874.0, WardSystemInsets.none, null) == WardPaper.panel(402.0, 874.0))
    }

    @Test fun topBarControlInsideTheRing() = checks {
        // a page's content starts at WardPaper.contentEdge; the top bar (ReaderNavBar) pads its leading control by WardSpace.s
        for (p in phones) {
            val panel = WardPaper.panel(p.width, p.height, p.safe, p.device) ?: continue
            val leading = WardPaper.contentEdge(p.safe.left) + WardSpace.s
            val ringInner = panel.x + WardPaper.edgeWidth / 2
            check("${p.label}: leading control inside the ring by its width and the edge padding",
                leading - ringInner >= WardPaper.edgeWidth + WardSpace.s, "control at $leading, ring's inner edge $ringInner")
            val trailing = p.width - WardPaper.contentEdge(p.safe.right) - WardSpace.s
            check("${p.label}: trailing control inside the ring too",
                (panel.x + panel.width - WardPaper.edgeWidth / 2) - trailing >= WardPaper.edgeWidth + WardSpace.s)
        }
        // the pages and the learning sheet pad by exactly those numbers
        fun source(path: String) = File(path).takeIf { it.exists() }?.readText() ?: ""
        val surfaces = source("src/main/java/com/stethoscore/app/ui/ward/WardSurfaces.kt")
        val reader = source("src/main/java/com/stethoscore/app/ui/sources/ReaderKit.kt")
        val learn = source("src/main/java/com/stethoscore/app/ui/learn/LearnRoutes.kt")
        val app = source("src/main/java/com/stethoscore/app/ui/StethoscoreApp.kt")
        check("the clearance is the safe area and sideInset",
            surfaces.contains("safeDrawingPadding().padding(horizontal = WardPaper.sideInset.dp, vertical = WardPaper.edgeWidth.dp)"))
        check("the top bar pads by WardSpace.s", reader.contains(".heightIn(min = 52.dp).padding(horizontal = WardSpace.s.wardDp)"))
        check("the learning sheet sits inside the ring", learn.contains("Box(Modifier.fillMaxSize().wardFrameClearance())"))
        check("framed pages sit inside the ring", app.contains("if(inFrame) Modifier.fillMaxSize().wardFrameClearance()"))
        check("the frame reads the bars and the display's corner",
            surfaces.contains("WardPaper.panel((size.width / density).toDouble(), (size.height / density).toDouble(), safe, device, pad = pad)"))
    }
}
