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
        // a page's content starts at WardPaper.contentEdge; the one top bar (StudyTitleBar) pads its ends by its
        // inset, WardSpace.m, or none inside a column that keeps the gutter (ScreenHeader): the nearer of the two
        val barInset = minOf(WardSpace.m, WardSpace.gutter)
        for (p in phones) {
            val panel = WardPaper.panel(p.width, p.height, p.safe, p.device) ?: continue
            val leading = WardPaper.contentEdge(p.safe.left) + barInset
            val ringInner = panel.x + WardPaper.edgeWidth / 2
            check("${p.label}: leading control inside the ring by its width and the edge padding",
                leading - ringInner >= WardPaper.edgeWidth + WardSpace.s, "control at $leading, ring's inner edge $ringInner")
            val trailing = p.width - WardPaper.contentEdge(p.safe.right) - barInset
            check("${p.label}: trailing control inside the ring too",
                (panel.x + panel.width - WardPaper.edgeWidth / 2) - trailing >= WardPaper.edgeWidth + WardSpace.s)
        }
        // the pages and the learning sheet pad by exactly those numbers
        fun source(path: String) = File(path).takeIf { it.exists() }?.readText() ?: ""
        val surfaces = source("src/main/java/com/stethoscore/app/ui/ward/WardSurfaces.kt")
        val bar = source("src/main/java/com/stethoscore/app/ui/mock/MockKit.kt")
        val theme = source("src/main/java/com/stethoscore/app/ui/Theme.kt")
        val learn = source("src/main/java/com/stethoscore/app/ui/learn/LearnRoutes.kt")
        val app = source("src/main/java/com/stethoscore/app/ui/StethoscoreApp.kt")
        check("the clearance is the safe area and sideInset",
            surfaces.contains("safeDrawingPadding().padding(horizontal = WardPaper.sideInset.dp, vertical = WardPaper.edgeWidth.dp)"))
        check("the top bar pads by WardSpace.m", bar.contains("inset: Dp = WardSpace.m.wardDp") &&
            bar.contains(".padding(horizontal = inset)"))
        check("a header without inset keeps its column's gutter", theme.contains("StudyTitleBar(title, onBack, inset = 0.dp)"))
        check("the learning sheet sits inside the ring", learn.contains("Box(Modifier.fillMaxSize().wardFrameClearance())"))
        check("framed pages sit inside the ring", app.contains("if(inFrame) Modifier.fillMaxSize().wardFrameClearance()"))
        check("the frame reads the bars and the display's corner",
            surfaces.contains("WardPaper.panel((size.width / density).toDouble(), (size.height / density).toDouble(), safe, device, pad = pad)"))
    }
    /**
     * The corner elements on a 1080 x 2400 phone at 2.625 (411.43 x 914.29 dp)
     * with a 47 px display corner (17.9 dp), a 24 dp status bar and a 24 dp
     * gesture bar: each takes WardCorner.radii against the ring (framed
     * pages) or the screen (home), as the app lays them out.
     */
    @Test fun cornerElements() = checks {
        val w = 411.43
        val h = 914.29
        val device = 47 / 2.625
        val safe = WardSystemInsets(top = 24.0, bottom = 24.0)
        val panel = WardPaper.panel(w, h, safe, device)!!
        val ring = WardCornerFrame.ring(panel)
        val screen = WardCornerFrame.screen(w, h, device)
        check("the ring's corners floor at its minimum", panel.radius == WardEdge.minRadius && panel.bottomRadius == WardEdge.minRadius)
        val left = WardPaper.contentEdge(safe.left)
        val top = safe.top + WardPaper.edgeWidth
        val bottom = h - safe.bottom - WardPaper.edgeWidth
        // the top bar's Done: a capsule (its own radius half its height) a gutter's padding in
        val doneHeight = 36.0
        val done = WardRect(left + WardSpace.s, top + 8.0, 72.0, doneHeight)
        check("Done keeps its capsule", WardCorner.radii(done, ring, doneHeight / 2) == WardCornerRadii.all(doneHeight / 2))
        // a study bar along the bottom: square, its bottom corners follow the ring's
        val bar = WardRect(left, bottom - 64.0, w - 2 * left, 64.0)
        val barCorners = WardCorner.radii(bar, ring, 0.0)
        val expected = WardCorner.concentric(panel.bottomRadius, maxOf(left - panel.x, panel.y + panel.height - bar.maxY), 0.0)
        check("the study bar's bottom corners are the ring's less their distance",
            barCorners.bottomLeft == expected && barCorners.bottomRight == expected && expected > 0, "$barCorners, expected $expected")
        check("the study bar's top corners stay square", barCorners.topLeft == 0.0 && barCorners.topRight == 0.0)
        // home's dock: WardDock's panel, barSide in and 10 dp over the gesture bar
        val dock = WardRect(WardDock.barSide, h - safe.bottom - 10.0 - 72.0, w - 2 * WardDock.barSide - WardDock.ideasWidth - WardDock.barSpacing, 72.0)
        check("the dock keeps WardDock's radius here", WardCorner.radii(dock, screen, WardDock.panelRadius) == WardCornerRadii.all(WardDock.panelRadius))
        // a card a page's padding in from the content edge sits beyond a gutter: its own radius
        val card = WardRect(left + WardSpace.gutter, top + 60.0, w - 2 * (left + WardSpace.gutter), 120.0)
        check("a mid-page card keeps its radius", WardCorner.radii(card, ring, WardRadius.card) == WardCornerRadii.all(WardRadius.card))
        // a bigger corner and a dock right at it: the dock's corners follow the display's
        val round = WardCornerFrame.screen(w, h, 55.0)
        val low = WardRect(12.0, h - 140.0, w - 24.0, 136.0)
        val lowCorners = WardCorner.radii(low, round, WardDock.panelRadius)
        // 55 less its distance (12 from the side, the larger; 4 from the bottom)
        check("near a round corner the dock is concentric", lowCorners.bottomLeft == 43.0 && lowCorners.bottomRight == 43.0 &&
            lowCorners.topLeft == WardDock.panelRadius, "$lowCorners")
        check("never rounder than half its height", WardCorner.radii(WardRect(0.0, h - 20.0, w, 20.0), round, 0.0).bottomLeft == 10.0)
        // a device with square corners: every element at the screen's corner takes its own minimum
        val square = WardCornerFrame.screen(w, h, 0.0)
        for ((name, own) in listOf("dock" to WardDock.panelRadius, "card" to WardRadius.card, "bar" to 0.0, "Done" to doneHeight / 2)) {
            check("corner 0: the $name takes its own minimum", WardCorner.radii(low, square, own) == WardCornerRadii.all(own))
        }
        // where the app wires it
        fun source(path: String) = File(path).takeIf { it.exists() }?.readText() ?: ""
        val app = source("src/main/java/com/stethoscore/app/ui/StethoscoreApp.kt")
        check("the window's root gives the frame", app.contains("WardCornerScope(framed=!onGround)"))
        check("the dock's panel and Ideas pill follow the corner", app.contains("rememberWardCorners(WardDock.panelRadius)") &&
            app.contains(".wardChosenEdge(ideasShape,ideas)"))
        check("the library's study bar follows the ring",
            source("src/main/java/com/stethoscore/app/ui/library/LibraryParts.kt").contains("rememberWardCorners(own = 0.0)"))
        // the review's study deck (WardDeck) joins the ring's line, so it solves on the very opening the frame strokes
        check("the study deck joins the ring clear of the bars",
            source("src/main/java/com/stethoscore/app/ui/ward/WardDeck.kt").contains("WardPaper.panel(bounds.width, bounds.height, safe, device, pad)") &&
            source("src/main/java/com/stethoscore/app/ui/ward/WardSurfaces.kt").contains("WardEdgeStore.setWindow(view, it.wardWindowRect(points), pad, safe, device)"))
        check("cards follow the corner", source("src/main/java/com/stethoscore/app/ui/ward/WardSurfaces.kt")
            .contains("rememberWardCorners(WardFaceMetrics.cardRadius)"))
    }
}
