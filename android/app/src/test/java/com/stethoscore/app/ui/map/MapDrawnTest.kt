package com.stethoscore.app.ui.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/** The record ScreenshotTest waits on before it looks at the map (MapDrawn, Map3DView's MapDrawnKey). */
class MapDrawnTest {
    @Test fun countsFramesAndFramesWithBodiesThenStopsChanging() {
        // the Space map of four notes: the summary star alone, then its bodies, the first of
        // them seconds later where the GL builds each shader on its first draw
        var d = MapDrawn().after(0, 40)
        assertEquals(1, d.frames); assertEquals(0, d.bodyFrames); assertEquals(40L, d.firstFrameMs); assertEquals(-1L, d.firstBodyFrameMs)
        d = d.after(4, 5_200)
        assertEquals(2, d.frames); assertEquals(1, d.bodyFrames); assertEquals(4, d.bodies); assertEquals(5_200L, d.firstBodyFrameMs)
        d = d.after(4, 5_260).after(4, 5_300)
        assertEquals(MapDrawn.ENOUGH, d.frames); assertEquals(MapDrawn.ENOUGH, d.bodyFrames)
        // settled: the same record, so nothing more is handed to the main thread
        assertSame(d, d.after(5, 9_000))
        assertSame(d, d.after(0, 9_100))
        assertEquals(40L, d.firstFrameMs); assertEquals(5_200L, d.firstBodyFrameMs); assertEquals(4, d.bodies)
    }

    @Test fun aMapWithoutBodiesSettlesButStillCountsBodiesThatComeLater() {
        var d = MapDrawn()
        repeat(MapDrawn.ENOUGH) { d = d.after(0, 16L * (it + 1)) }
        assertEquals(MapDrawn.ENOUGH, d.frames); assertEquals(16L, d.firstFrameMs)
        assertSame(d, d.after(0, 1_000))
        // the camera came close to a note: its body counts from then on
        val later = d.after(2, 2_000)
        assertEquals(MapDrawn.ENOUGH, later.frames); assertEquals(1, later.bodyFrames); assertEquals(2, later.bodies); assertEquals(2_000L, later.firstBodyFrameMs)
    }

    @Test fun changesOnlyAFewTimesOverAThousandFrames() {
        var d = MapDrawn(width = 1080, height = 1950, renderer = "SwiftShader", maxPointSize = 1f, bodyStyles = 6)
        var changes = 0
        for (f in 1..1000) {
            val next = d.after(if (f == 1) 0 else 3 + f % 4, f * 16L)
            if (next != d) changes++
            d = next
        }
        assertEquals(MapDrawn.ENOUGH + 1, changes)
        assertEquals(MapDrawn(MapDrawn.ENOUGH, MapDrawn.ENOUGH, 3, 16, 32, 1080, 1950, "SwiftShader", 1f, 6), d)
    }
}
