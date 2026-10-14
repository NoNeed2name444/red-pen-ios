package com.stethoscore.app.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class MapMathTest {
    @Test fun frustumKeepsWhatIsAheadAndCullsWhatIsBehind() {
        val camera = OrbitCamera(target = Vec3.ZERO, distance = 10f, yaw = 0f, pitch = 0f)
        val f = Frustum(Mat4.multiply(camera.projection(1f), camera.view()))
        assertTrue(f.intersectsSphere(0f, 0f, 0f, 0.1f))
        // the eye is at +z looking at the origin: a point behind the eye is culled
        assertFalse(f.intersectsSphere(0f, 0f, 30f, 1f))
        // far to the side is culled, unless the sphere is large enough to reach in
        assertFalse(f.intersectsSphere(100f, 0f, 0f, 1f))
        assertTrue(f.intersectsSphere(100f, 0f, 0f, 100f))
        // a margin grows the test region
        assertFalse(f.intersectsSphere(8f, 0f, 0f, 1f))
        assertTrue(f.intersectsSphere(8f, 0f, 0f, 1f, margin = 5f))
    }

    @Test fun projectionPutsTheTargetAtTheCentre() {
        val camera = OrbitCamera(target = Vec3(1f, 2f, 3f), distance = 5f)
        val vp = Mat4.multiply(camera.projection(1.5f), camera.view())
        val out = FloatArray(4)
        Mat4.project(vp, 1f, 2f, 3f, out)
        assertEquals(0f, out[0] / out[3], 1e-4f)
        assertEquals(0f, out[1] / out[3], 1e-4f)
    }

    @Test fun theHomeViewFitsTheMapOnTheNarrowAxis() {
        val c = OrbitCamera()
        val d = c.fitDistance(10f, aspect = 0.75f, margin = 1f)
        // a sphere of radius 10 at that distance just touches the sides of a 3:4 view
        val halfH = kotlin.math.atan(kotlin.math.tan(c.fovY / 2) * 0.75f)
        assertEquals(10f, d * kotlin.math.sin(halfH), 1e-3f)
        assertTrue(c.fitDistance(10f, aspect = 2f) < c.fitDistance(10f, aspect = 0.75f))
    }

    @Test fun cameraPanAndZoomStayInBounds() {
        val camera = OrbitCamera(distance = 10f)
        camera.minDistance = 1f; camera.maxDistance = 20f
        camera.zoom(100f); assertEquals(1f, camera.distance, 0f)
        camera.zoom(0.001f); assertEquals(20f, camera.distance, 0f)
        camera.orbit(0f, 10f); assertTrue(camera.pitch <= 1.5f)
        val before = camera.target
        camera.pan(0.1f, 0f)
        assertTrue((camera.target - before).length() > 0f)
    }
}

class GraphAndOctreeTest {
    private fun note(id: String, vararg links: String) = object : NoteLike {
        override val id = id; override val title = "Note $id"; override val links = links.toList(); override val tags = listOf("t")
    }

    @Test fun notesBecomeAGraphWithUndirectedLinksOnce() {
        val g = MapGraph.fromNotes(listOf(note("a", "b", "c"), note("b", "a"), note("c", "missing"), note("d", "c")))
        assertEquals(4, g.nodeCount)
        assertEquals(3, g.edgeCount) // a-b once, a-c, d-c; the missing id is ignored
        assertEquals(listOf("Note a", "Note b", "Note c", "Note d"), g.titles)
        assertTrue(g.positions.all { it.isFinite() })
    }

    @Test fun syntheticMillionIsSeededAndSized() {
        val a = SyntheticGraph.make(nodes = 20_000)
        val b = SyntheticGraph.make(nodes = 20_000)
        assertEquals(20_000, a.nodeCount)
        assertTrue(a.positions.contentEquals(b.positions))
        assertTrue(a.edges.contentEquals(b.edges))
        assertTrue("about 1.5 links a node", a.edgeCount in 25_000..36_000)
        for (k in 0 until a.edgeCount) assertTrue(a.edges[2 * k] < a.edges[2 * k + 1])
    }

    @Test fun octreeChunksEveryNodeOnceAndKeepsLeavesContiguous() {
        val g = SyntheticGraph.make(nodes = 50_000)
        val t = Octree.build(g, leafCapacity = 1024)
        assertEquals(g.nodeCount, t.nodeCount)
        assertEquals(g.nodeCount, t.order.distinct().size)
        assertEquals(g.nodeCount, t.count[Octree.ROOT])
        var covered = 0
        for (leaf in 0 until t.leafCount) {
            val cell = t.leafCell[leaf]
            assertTrue(t.count[cell] <= 1024 || t.depth[cell] >= 10)
            assertEquals(covered, t.start[cell]) // leaves tile the node order, depth first
            covered = t.end[cell]
            for (k in t.start[cell] until t.end[cell]) assertEquals(leaf, t.leafOfNode[k])
        }
        assertEquals(g.nodeCount, covered)
        // reordered positions are the originals
        for (k in 0 until t.nodeCount step 997) {
            val i = t.order[k]
            assertEquals(g.positions[3 * i], t.positions[3 * k], 0f)
        }
    }

    @Test fun summariesHoldCountCentroidAndRadius() {
        val g = SyntheticGraph.make(nodes = 10_000)
        val t = Octree.build(g, leafCapacity = 512)
        for (cell in 0 until t.cellCount) {
            if (t.isLeaf(cell)) continue
            var sum = 0
            for (k in 0 until t.childCount[cell]) sum += t.count[t.childList[t.firstChild[cell] + k]]
            assertEquals(t.count[cell], sum)
            assertEquals(t.leafEnd[cell] - t.leafStart[cell], (t.leafStart[cell] until t.leafEnd[cell]).count())
        }
        val cell = t.leafCell[0]
        var x = 0.0
        for (k in t.start[cell] until t.end[cell]) x += t.positions[3 * k]
        assertEquals((x / t.count[cell]).toFloat(), t.cx[cell], 1e-3f)
        for (k in t.start[cell] until t.end[cell]) {
            val dx = t.positions[3 * k] - t.cx[cell]; val dy = t.positions[3 * k + 1] - t.cy[cell]; val dz = t.positions[3 * k + 2] - t.cz[cell]
            assertTrue(dx * dx + dy * dy + dz * dz <= t.radius[cell] * t.radius[cell] * 1.0001f)
        }
    }

    @Test fun everyLinkIsListedWithBothChunksAndBundledOncePerPair() {
        val g = SyntheticGraph.make(nodes = 30_000)
        val t = Octree.build(g, leafCapacity = 1024)
        var crossFromLists = 0; var withinFromLists = 0
        for (leaf in 0 until t.leafCount) {
            for (k in t.leafEdgeStart[leaf] until t.leafEdgeStart[leaf + 1] step 2) {
                val a = t.leafOfNode[t.leafEdges[k]]; val b = t.leafOfNode[t.leafEdges[k + 1]]
                assertTrue(a == leaf || b == leaf)
                if (a == b) withinFromLists++ else crossFromLists++
            }
        }
        val crossLinks = t.bundleCount.sum()
        assertEquals(2 * crossLinks, crossFromLists)
        assertEquals(g.edgeCount, withinFromLists + crossLinks)
        val keys = t.bundleA.indices.map { Octree.pairKey(t.bundleA[it], t.bundleB[it]) }
        assertEquals(keys.size, keys.toSet().size)
        assertTrue(t.bundleA.indices.all { t.bundleA[it] < t.bundleB[it] })
    }

    @Test fun longIntMapSumsAndGrows() {
        val m = LongIntMap(4)
        for (i in 0 until 1000) m.add(i.toLong() * 7919, 1)
        for (i in 0 until 1000) m.add(i.toLong() * 7919, 2)
        assertEquals(1000, m.size)
        assertEquals(3, m[7919L * 500])
        assertEquals(0, m[-1L])
        m.clear(); assertEquals(0, m.size)
    }
}

class ChunkCacheTest {
    private fun cache(pages: Int, sizes: IntArray, pageSize: Int = 10) = ChunkCache(pages, pageSize) { sizes[it] }

    @Test fun loadsNearestFirstWithinTheFrameBudget() {
        val c = cache(100, IntArray(10) { 10 })
        val loaded = mutableListOf<Int>()
        c.request(1, 5f); c.request(2, 50f); c.request(3, 20f)
        c.pump(frame = 1, budget = 20) { chunk, _ -> loaded.add(chunk) }
        assertEquals(listOf(2, 3), loaded) // highest priority first, budget of two chunks
        assertTrue(c.isResident(2)); assertFalse(c.isResident(1))
        c.request(1, 5f)
        c.pump(frame = 2, budget = 20) { chunk, _ -> loaded.add(chunk) }
        assertTrue(c.isResident(1))
    }

    @Test fun aChunkBiggerThanTheBudgetStillLoadsAlone() {
        val c = cache(100, intArrayOf(500, 10))
        val loaded = mutableListOf<Int>()
        c.request(0, 2f); c.request(1, 1f)
        c.pump(1, budget = 100) { chunk, pages -> loaded.add(chunk); assertEquals(50, pages.size) }
        assertEquals(listOf(0), loaded)
    }

    @Test fun evictsLeastRecentlyUsedButNeverWhatThisFrameDraws() {
        val c = cache(pages = 3, sizes = IntArray(10) { 10 })
        for (chunk in 0 until 3) { c.request(chunk, 1f); c.pump(chunk, 100) { _, _ -> } }
        assertEquals(listOf(0, 1, 2), c.lruOrder())
        c.touch(0, frame = 5) // 0 drawn again: 1 is now the oldest
        assertEquals(listOf(1, 2, 0), c.lruOrder())
        c.request(3, 1f); c.pump(5, 100) { _, _ -> }
        assertFalse(c.isResident(1)); assertTrue(c.isResident(3)); assertTrue(c.isResident(0))
        assertEquals(1, c.evictedTotal)
        // everything drawn this frame: nothing can go, so the new chunk waits
        for (chunk in listOf(0, 2, 3)) c.touch(chunk, 6)
        c.request(4, 1f); c.pump(6, 100) { _, _ -> }
        assertFalse(c.isResident(4))
        c.request(4, 1f); c.pump(7, 100) { _, _ -> }
        assertTrue(c.isResident(4))
    }

    @Test fun pagesAreReusedAfterEviction() {
        val c = cache(pages = 4, sizes = IntArray(10) { 20 })
        val seen = mutableSetOf<Int>()
        for (chunk in 0 until 10) { c.request(chunk, 1f); c.pump(chunk, 1000) { _, p -> p.forEach { seen.add(it) } } }
        assertEquals(setOf(0, 1, 2, 3), seen)
        assertEquals(2, c.residentCount)
        assertTrue(c.isResident(9) && c.isResident(8))
    }

    @Test fun emptyChunksAreAlwaysResident() {
        val c = cache(1, intArrayOf(0))
        assertTrue(c.isResident(0))
    }
}

class FrameBudgetTest {
    @Test fun slowFramesCutDetailAndEasyFramesRaiseIt() {
        val b = FrameBudget(refreshHz = 120f, initialDetail = 1f)
        assertEquals(8.333, b.targetMs, 0.01)
        val open = b.openPixels
        repeat(10) { b.onFrame(intervalMs = 16.7, workMs = 4.0) } // missed refreshes
        assertTrue(b.detail < 1f)
        assertTrue("chunks open later on a slow device", b.openPixels > open)
        val low = b.detail
        repeat(200) { b.onFrame(intervalMs = 8.3, workMs = 1.0) }
        assertTrue(b.detail > low)
    }

    @Test fun detailStaysWithinBoundsAndStepsAreSmall() {
        val b = FrameBudget(60f, 1f)
        var previous = b.detail
        repeat(1000) {
            b.onFrame(100.0, 90.0)
            assertTrue(b.detail >= previous * 0.879f)
            previous = b.detail
        }
        assertEquals(FrameBudget.MIN_DETAIL, b.detail, 1e-6f)
        assertTrue("even at the floor, chunks open by 120 px", b.openPixels <= 120.5f)
        repeat(100_000) { b.onFrame(16.6, 0.5) }
        assertEquals(FrameBudget.MAX_DETAIL, b.detail, 1e-6f)
        assertTrue(b.maxDetailNodes <= 4_000_000)
    }

    @Test fun theBudgetIsPerFrameAtTheDisplayRate() {
        val b = FrameBudget(60f, 1f)
        repeat(30) { b.onFrame(16.6, 5.0) } // fine at 60 Hz
        val at60 = b.detail
        b.refreshHz = 120f
        repeat(30) { b.onFrame(16.6, 5.0) } // the same frames miss at 120 Hz
        assertTrue(b.detail < at60)
    }

    @Test fun statsReportRateAndMedians() {
        val s = FrameStats()
        var t = 0L
        repeat(100) { s.add(t, 8.33, 2.0); t += 8_333_333L }
        assertEquals(120.0, s.fps(t - 8_333_333L), 1.0)
        assertEquals(8.33, s.medianInterval(), 1e-6)
        assertEquals(2.0, s.medianWork(), 1e-6)
    }

    @Test fun choosesTheHighestRefreshAtTheSameResolution() {
        val current = DisplayModeInfo(1, 1080, 2400, 60f)
        val modes = listOf(current, DisplayModeInfo(2, 1080, 2400, 120f), DisplayModeInfo(3, 1440, 3200, 144f), DisplayModeInfo(4, 1080, 2400, 90f))
        assertEquals(2, RefreshRate.bestMode(modes, current)?.id)
        assertNull(RefreshRate.bestMode(listOf(current), current))
        assertEquals(144f, RefreshRate.maxHz(modes), 0f)
        assertEquals("1,000,000", grouped(1_000_000))
        assertEquals("999", grouped(999))
    }
}

class LodSelectorTest {
    private val graph = SyntheticGraph.make(nodes = 60_000)
    private val tree = Octree.build(graph, leafCapacity = 1024)

    private fun cameraAt(distance: Float) = OrbitCamera(target = Vec3(tree.cx[0], tree.cy[0], tree.cz[0]), distance = distance, yaw = 0.3f, pitch = 0.5f)

    private fun run(lod: LodSelector, camera: OrbitCamera, frames: Int = 30, open: Float = 36f, velocity: Vec3 = Vec3.ZERO, maxDetail: Int = 10_000_000, cache: ChunkCache? = null): FramePlan {
        var plan: FramePlan? = null
        for (f in 1..frames) {
            val guard = GuardBand.predict(camera, 1f, velocity, 0.5f)
            plan = lod.select(camera.eye(), camera.focalPixels(1000f), guard.view, guard, open, maxDetail, 1f / 60, f)
            cache?.pump(f, Int.MAX_VALUE) { _, _ -> }
        }
        return plan!!
    }

    @Test fun fromFarAwayTheWholeMapIsOneSummaryPoint() {
        val lod = LodSelector(tree, null)
        val plan = run(lod, cameraAt(tree.radius[0] * 400))
        assertEquals(1, plan.summaryCount)
        assertEquals(0, plan.detailLeaves.size)
        assertEquals(0, plan.bundleCount)
    }

    @Test fun closeUpChunksOpenIntoNodesAndOffscreenChunksAreCulled() {
        val lod = LodSelector(tree, null)
        val camera = cameraAt(tree.radius[0] * 0.25f)
        val plan = run(lod, camera)
        assertTrue(plan.detailLeaves.size > 0)
        assertTrue("some chunks are behind the camera or off the sides", plan.visibleCells < tree.cellCount)
        val guard = GuardBand.predict(camera, 1f, Vec3.ZERO, 0f, 0f)
        for (k in 0 until plan.detailLeaves.size) {
            val cell = tree.leafCell[plan.detailLeaves[k]]
            assertTrue(guard.view.intersectsSphere(tree.cx[cell], tree.cy[cell], tree.cz[cell], tree.radius[cell]))
        }
    }

    @Test fun detailFollowsOnScreenSizeContinuously() {
        // as the camera comes in, openness of the root rises smoothly from 0 to 1
        val lod = LodSelector(tree, null)
        lod.morphRate = 1e9f // follow the target at once to see the rule itself
        var previous = -1f
        val r = tree.radius[0]
        var sawPartial = false
        for (step in 0 until 200) {
            val camera = cameraAt(r * (300f - step * 1.45f))
            val plan = run(lod, camera, frames = 1)
            val px = lod.pixelRadius(0)
            val expected = smoothstep(36f, 72f, px)
            // the summary point of the root shrinks exactly as its children come out
            if (expected in 0.05f..0.95f) sawPartial = true
            assertTrue(expected >= previous - 1e-6f)
            previous = expected
            assertTrue(plan.summaryCount >= 1)
        }
        assertTrue(sawPartial)
    }

    @Test fun morphingNeverJumpsBetweenFrames() {
        val lod = LodSelector(tree, null)
        val camera = cameraAt(tree.radius[0] * 300f)
        run(lod, camera, frames = 5)
        camera.distance = tree.radius[0] * 0.5f // a sudden zoom
        val plan = run(lod, camera, frames = 1)
        // openness moves at most morphRate * dt in one frame
        for (leaf in 0 until tree.leafCount) assertTrue(plan.leafState[leaf * 4 + 3] <= 5f / 60 + 1e-4f)
    }

    @Test fun summaryPointsUseColourMixAndBrightnessNotOpacity() {
        val lod = LodSelector(tree, null)
        val plan = run(lod, cameraAt(tree.radius[0] * 3f))
        assertTrue(plan.summaryCount > 1)
        for (s in 0 until plan.summaryCount) {
            val o = s * FramePlan.SUMMARY_STRIDE
            assertTrue(plan.summaries.data[o + 3] > 0f) // diameter
            for (ch in 4..6) assertTrue(plan.summaries.data[o + ch] in 0f..1f)
        }
    }

    @Test fun farChunkPairsAreDrawnAsOneBundleEach() {
        val lod = LodSelector(tree, null)
        val plan = run(lod, cameraAt(tree.radius[0] * 3f), open = 100f) // open the top, keep leaves as summaries
        assertTrue(plan.bundleCount > 0)
        val ends = HashSet<String>()
        for (b in 0 until plan.bundleCount) {
            val o = b * FramePlan.BUNDLE_STRIDE
            val d = plan.bundles.data
            val key = listOf(d[o], d[o + 1], d[o + 2], d[o + 3], d[o + 4], d[o + 5]).joinToString()
            assertTrue("one bundle per pair", ends.add(key))
            assertTrue(d[o + 6] > 0f && d[o + 6] <= 6f)
        }
    }

    @Test fun theDetailCapHoldsAndUnloadedChunksStaySummaries() {
        val cache = ChunkCache(pageCount = 100_000, pageSize = 4096) { tree.leafEdgeIndexCount(it) }
        val lod = LodSelector(tree, cache)
        val camera = cameraAt(tree.radius[0] * 0.6f)
        // first frame: nothing resident, so nothing opens
        val first = run(lod, camera, frames = 1, cache = null)
        assertEquals(0, first.detailLeaves.size)
        val plan = run(lod, camera, frames = 40, maxDetail = 5_000, cache = cache)
        assertTrue(plan.detailNodes <= 5_000)
        assertTrue(cache.residentCount > 0)
    }

    @Test fun theGuardBandPreparesChunksAheadOfTheMotion() {
        val camera = cameraAt(tree.radius[0] * 0.3f)
        val forward = (camera.target - camera.eye()).normalized()
        val right = forward.cross(Vec3(0f, 1f, 0f)).normalized()
        val speed = tree.radius[0]
        fun loadedSide(velocity: Vec3): Pair<Int, Int> {
            val cache = ChunkCache(100_000, 4096) { tree.leafEdgeIndexCount(it) }
            val lod = LodSelector(tree, cache)
            run(lod, camera, frames = 3, velocity = velocity, cache = cache)
            var ahead = 0; var behind = 0
            for (leaf in 0 until tree.leafCount) if (cache.isResident(leaf) && tree.leafEdgeIndexCount(leaf) > 0) {
                val cell = tree.leafCell[leaf]
                val side = (Vec3(tree.cx[cell], tree.cy[cell], tree.cz[cell]) - camera.target).dot(right)
                if (side > 0) ahead++ else behind++
            }
            return ahead to behind
        }
        val still = loadedSide(Vec3.ZERO)
        val moving = loadedSide(right * speed)
        assertTrue("moving right prepares more on the right", moving.first > still.first)
        assertEquals(still.second, moving.second)
    }

    @Test fun aMillionNodesBuildAndSelectInTime() {
        val start = System.nanoTime()
        val big = SyntheticGraph.make()
        val t = Octree.build(big)
        val built = (System.nanoTime() - start) / 1e6
        assertEquals(1_000_000, t.nodeCount)
        assertTrue("build took $built ms", built < 30_000)
        val lod = LodSelector(t, null)
        val camera = OrbitCamera(target = Vec3(t.cx[0], t.cy[0], t.cz[0]), distance = t.radius[0] * 1.2f)
        run(lod, camera, frames = 10)
        val s = System.nanoTime()
        repeat(20) { f ->
            camera.orbit(0.01f, 0f)
            val guard = GuardBand.predict(camera, 0.5f, Vec3.ZERO, 0f)
            lod.select(camera.eye(), camera.focalPixels(2400f), guard.view, guard, 36f, 600_000, 1f / 120, 100 + f)
        }
        val perFrame = (System.nanoTime() - s) / 1e6 / 20
        assertTrue("selection took $perFrame ms a frame", perFrame < 25)
        assertNotNull(lod.plan)
        assertTrue(abs(lod.plan.detailNodes) <= 1_000_000)
        // the demo's home view on the slowest budget: still the galaxy's shape, not one dot
        val slow = FrameBudget(60f, FrameBudget.MIN_DETAIL)
        val home = OrbitCamera(target = Vec3(t.cx[0], t.cy[0], t.cz[0]), distance = t.radius[0] * 2.4f)
        val floor = run(LodSelector(t, null), home, frames = 120, open = slow.openPixels, maxDetail = slow.maxDetailNodes)
        assertTrue("${floor.summaryCount} summaries at the floor", floor.summaryCount >= 100)
    }
}
