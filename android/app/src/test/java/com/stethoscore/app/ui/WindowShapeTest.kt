package com.stethoscore.app.ui

import android.graphics.Rect
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.ForcedSize
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.window.layout.FoldingFeature
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.ward.WardFold
import com.stethoscore.app.ui.ward.WardPosture
import com.stethoscore.app.ui.ward.WardRect
import com.stethoscore.app.ui.ward.WardWidthClass
import com.stethoscore.app.ui.ward.WindowShape
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

// The window's shape (T0139): the width classes at their edges, each fold
// posture's two areas clear of the hinge, layout read from the window and
// never the device, and home laid out by the window's size alone: a 10-inch
// tablet's window at a phone's width is the phone's home (bottom bar, one
// column), at 840 dp the tablet's (the rail, two areas).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WindowShapeTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    @Test fun widthClassesAtTheirEdges() {
        val expected = listOf(599.0 to WardWidthClass.compact, 600.0 to WardWidthClass.medium, 699.0 to WardWidthClass.medium,
            700.0 to WardWidthClass.medium, 839.0 to WardWidthClass.medium, 840.0 to WardWidthClass.expanded)
        for ((w, c) in expected) assertEquals("$w dp", c, WindowShape(w, 900.0).widthClass)
        // iOS WindowSpan.broad, kept at 700 for parity: the dock's rail and the readers' two columns
        for ((w, broad) in listOf(599.0 to false, 600.0 to false, 699.0 to false, 700.0 to true, 839.0 to true, 840.0 to true)) {
            assertEquals("$w dp broad", broad, WindowShape(w, 900.0).isBroad)
            assertEquals("$w dp rail", broad, WindowShape(w, 900.0).dockIsRail)
        }
        // the frame's and home's tablet measure is the window's shorter side
        assertTrue(WindowShape(1280.0, 800.0).isPadSized)
        assertFalse("a tablet split to a third is a phone-wide window", WindowShape(424.0, 800.0).isPadSized)
        assertFalse(WindowShape(915.0, 412.0).isPadSized)
    }

    private fun fold(state: WardFold.State, orientation: WardFold.Orientation, bounds: WardRect, separating: Boolean,
                     occlusion: WardFold.Occlusion = WardFold.Occlusion.none) = WardFold(state, orientation, bounds, separating, occlusion)

    @Test fun eachPostureSplitsClearOfTheHinge() {
        // a book-style foldable open (Pixel Fold's inner screen, 841 x 701 dp), its fold down the middle
        val w = 841.0; val h = 701.0
        val vertical = WardRect(420.0, 0.0, 0.0, h)
        val horizontal = WardRect(0.0, 350.0, w, 0.0)
        // flat open: one area, laid out as the tablet it is
        val flat = WindowShape(w, h, fold(WardFold.State.flat, WardFold.Orientation.vertical, vertical, separating = false))
        assertEquals(WardPosture.flat, flat.posture)
        assertNull(flat.separatingFold)
        assertTrue("flat open is expanded: the list beside the open item", flat.panes() != null)
        assertTrue(flat.dockIsRail)
        assertEquals(WindowShape.Clearance(), flat.hingeClearance(WardRect(0.0, 0.0, w, h)))
        // book: half open, the fold upright; each area one side of it
        val book = WindowShape(w, h, fold(WardFold.State.halfOpened, WardFold.Orientation.vertical, vertical, separating = true))
        assertEquals(WardPosture.book, book.posture)
        val (left, right) = book.panes()!!.let { it.first to it.second }
        assertEquals(WardRect(0.0, 0.0, 420.0, h), left)
        assertEquals(WardRect(420.0, 0.0, 421.0, h), right)
        assertFalse(book.meetsHinge(left)); assertFalse(book.meetsHinge(right))
        assertTrue(book.meetsHinge(WardRect(400.0, 100.0, 48.0, 48.0)))
        // the page keeps to the larger side, drawn in from the hinge
        assertEquals(WindowShape.Clearance(left = 420.0), book.hingeClearance(WardRect(0.0, 0.0, w, h)))
        // tabletop: half open, the fold across; the reading half above it, the controls' half below
        val table = WindowShape(w, h, fold(WardFold.State.halfOpened, WardFold.Orientation.horizontal, horizontal, separating = true))
        assertEquals(WardPosture.tabletop, table.posture)
        val (top, bottom) = table.panes()!!.let { it.first to it.second }
        assertEquals(WardRect(0.0, 0.0, w, 350.0), top)
        assertEquals(WardRect(0.0, 350.0, w, 351.0), bottom)
        assertEquals(WindowShape.Clearance(bottom = 351.0), table.hingeClearance(WardRect(0.0, 0.0, w, h)))
        // a hinge between two screens hides what is under it, half open or flat
        val hinge = WindowShape(1114.0, 705.0, fold(WardFold.State.flat, WardFold.Orientation.vertical, WardRect(540.0, 0.0, 34.0, 705.0),
            separating = true, occlusion = WardFold.Occlusion.full))
        assertEquals(WardPosture.book, hinge.posture)
        val (a, b) = hinge.panes()!!.let { it.first to it.second }
        assertEquals(540.0, a.width, 0.0); assertEquals(574.0, b.x, 0.0)
        assertTrue(hinge.meetsHinge(WardRect(560.0, 10.0, 4.0, 4.0)))
        // folded: the cover screen is the phone (no fold in its window)
        val cover = WindowShape(412.0, 900.0)
        assertEquals(WardPosture.flat, cover.posture)
        assertNull(cover.panes())
        assertFalse(cover.dockIsRail)
        // a medium window with no fold is one area
        assertNull(WindowShape(700.0, 900.0).panes())
    }

    /** A page cleared of the hinge is laid out by its pane, never the whole window (rail, broad, home's short window). */
    @Test fun clearedPageIsLaidOutByItsPane() {
        val w = 841.0; val h = 701.0
        val book = WindowShape(w, h, fold(WardFold.State.halfOpened, WardFold.Orientation.vertical, WardRect(420.0, 0.0, 0.0, h), separating = true))
        assertTrue("the whole window is broad", book.dockIsRail && book.widthClass != WardWidthClass.compact)
        val pane = book.pagePane
        // the larger side, as hingeClearance keeps the page to: 421 of 841 dp, under 600
        assertEquals(421.0, pane.width, 0.0); assertEquals(h, pane.height, 0.0)
        assertTrue(pane.width < WindowShape.compactMax)
        assertFalse("no rail in the book's half", pane.dockIsRail)
        assertEquals("not broad in the book's half", WardWidthClass.compact, pane.widthClass)
        assertFalse(pane.isPadSized)
        assertNull("no fold inside the pane", pane.separatingFold)
        // tabletop: the reading half above the fold, its height the fold's top
        val table = WindowShape(w, h, fold(WardFold.State.halfOpened, WardFold.Orientation.horizontal, WardRect(0.0, 350.0, w, 0.0), separating = true))
        assertEquals(WindowShape(w, 350.0), table.pagePane)
        // a hinge with thickness: the side it leaves
        val hinge = WindowShape(1114.0, 705.0, fold(WardFold.State.flat, WardFold.Orientation.vertical, WardRect(540.0, 0.0, 34.0, 705.0),
            separating = true, occlusion = WardFold.Occlusion.full))
        assertEquals(540.0, hinge.pagePane.width, 0.0)
        // no splitting fold: the window itself
        val flat = WindowShape(w, h, fold(WardFold.State.flat, WardFold.Orientation.vertical, WardRect(420.0, 0.0, 0.0, h), separating = false))
        assertEquals(flat, flat.pagePane)
        // and the first frame, before the page has measured itself, is already clear of the hinge
        assertEquals(book.hingeClearance(WardRect(0.0, 0.0, w, h)), book.clearanceFor(null))
        assertEquals(WindowShape.Clearance(left = 420.0), book.clearanceFor(null))
    }

    /** Inside WardHingePane the page reads the pane's shape: the provider the app lays every page in. */
    @Test fun hingePaneProvidesThePane() {
        val book = WindowShape(841.0, 701.0, fold(WardFold.State.halfOpened, WardFold.Orientation.vertical, WardRect(420.0, 0.0, 0.0, 701.0), separating = true))
        var seen: WindowShape? = null
        compose.setContent {
            androidx.compose.runtime.CompositionLocalProvider(com.stethoscore.app.ui.ward.LocalWindowShape provides book) {
                com.stethoscore.app.ui.ward.WardHingePane(com.stethoscore.app.ui.ward.currentWindowShape()) {
                    seen = com.stethoscore.app.ui.ward.currentWindowShape()
                }
            }
        }
        compose.waitForIdle()
        assertEquals(book.pagePane, seen)
        assertFalse("the page inside sees no rail", seen!!.dockIsRail)
    }

    @Test fun foldFromAndroidxWindow() {
        val feature = object : FoldingFeature {
            override val bounds = Rect(1100, 0, 1100, 1840)
            override val isSeparating = true
            override val occlusionType = FoldingFeature.OcclusionType.NONE
            override val orientation = FoldingFeature.Orientation.VERTICAL
            override val state = FoldingFeature.State.HALF_OPENED
        }
        val fold = WindowShape.fold(feature, 2.625)
        assertEquals(WardFold.State.halfOpened, fold.state)
        assertEquals(WardFold.Orientation.vertical, fold.orientation)
        assertEquals(1100 / 2.625, fold.bounds.x, 1e-9)
        assertEquals(1840 / 2.625, fold.bounds.height, 1e-9)
        assertTrue(fold.isSeparating)
    }

    /** The window's size, never the device: no screen-size, model or tablet read outside WindowShape.kt. */
    @Test fun layoutReadsTheWindowNotTheDevice() {
        val root = File("src/main/java")
        val sources = root.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
        assertTrue("sources found", sources.size > 50)
        val banned = Regex("""smallestScreenWidthDp|screenWidthDp|screenHeightDp|Build\.MODEL|isTablet|maxWidth\s*>=\s*\d+\.dp|>=\s*(600|700|840)\.dp""")
        val found = sources.filter { it.name != "WindowShape.kt" }.flatMap { f ->
            f.readLines().mapIndexedNotNull { i, line -> if (banned.containsMatchIn(line)) "${f.path}:${i + 1}: ${line.trim()}" else null }
        }
        assertTrue("read the window's shape (WindowShape) instead:\n" + found.joinToString("\n"), found.isEmpty())
        // and no resource folder chooses by the device's size or how it is held
        val res = File("src/main/res").listFiles().orEmpty().map { it.name }
        assertTrue("size or orientation resource folders: $res", res.none { it.contains(Regex("""-(sw|w|h)\d+dp|-land|-port""")) })
    }

    private fun store() = StudyStore(folder.newFolder()).also { it.loadExamples() }

    private fun homeAt(size: DpSize) {
        val s = store()
        compose.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.ForcedSize(size)) { StethoscoreApp(s) }
        }
        compose.waitForIdle()
    }

    private fun has(tag: String) = compose.onAllNodes(androidx.compose.ui.test.hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty()

    // A 10-inch tablet (pixel_tablet, 1280 x 800 dp) given a phone-wide window: the phone's home.
    @Config(sdk = [35], qualifiers = "w1280dp-h800dp-xhdpi")
    @Test fun tabletWindowAtPhoneWidthIsThePhone() {
        homeAt(DpSize(360.dp, 800.dp))
        assertTrue("the bottom bar at 360 dp", has("dockBar"))
        assertFalse("no rail at 360 dp", has("dockRail"))
        assertNull("one column at 360 dp", WindowShape(360.0, 800.0).panes())
    }

    @Config(sdk = [35], qualifiers = "w1280dp-h800dp-xhdpi")
    @Test fun tabletWindowAt840IsTheTablet() {
        homeAt(DpSize(840.dp, 800.dp))
        assertTrue("the rail at 840 dp", has("dockRail"))
        assertFalse("no bottom bar beside the rail", has("dockBar"))
        assertNotNull("two areas at 840 dp", WindowShape(840.0, 800.0).panes())
    }

    // And the other way: a small phone shows the phone's home, whatever the device reports.
    @Config(sdk = [35], qualifiers = "w360dp-h640dp-xhdpi")
    @Test fun smallPhoneIsThePhone() {
        homeAt(DpSize(360.dp, 640.dp))
        assertTrue(has("dockBar"))
        assertFalse(has("dockRail"))
    }
}
