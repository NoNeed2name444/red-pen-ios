package com.stethoscore.app.map

import kotlin.math.ln
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * The region prepared ahead of the camera (plan 4e, point 3): the view frustum grown by a
 * margin, plus the frustum where the camera will be after [lookaheadSeconds] at its current
 * velocity, so a pan arrives at chunks already loaded.
 */
class GuardBand(val view: Frustum, val ahead: Frustum?, val margin: Float) {
    fun contains(x: Float, y: Float, z: Float, r: Float) =
        view.intersectsSphere(x, y, z, r, margin) || (ahead?.intersectsSphere(x, y, z, r, margin) ?: false)

    companion object {
        fun predict(camera: OrbitCamera, aspect: Float, velocity: Vec3, lookaheadSeconds: Float, marginFraction: Float = 0.12f): GuardBand {
            val proj = camera.projection(aspect)
            val view = Frustum(Mat4.multiply(proj, camera.view()))
            val shift = velocity * lookaheadSeconds
            val ahead = if (shift.length() < 1e-6f) null else {
                val eye = camera.eye() + shift
                Frustum(Mat4.multiply(proj, Mat4.lookAt(eye, camera.target + shift)))
            }
            return GuardBand(view, ahead, camera.distance * marginFraction)
        }
    }
}

/** What to draw this frame, written by [LodSelector.select] and read by the renderer. */
class FramePlan(leafCount: Int) {
    /** Per leaf: the point its nodes morph out of (x, y, z) and how far out they are (0..1). */
    val leafState = FloatArray(max(leafCount, 1) * 4)
    /** Leaves drawn node by node this frame. */
    val detailLeaves = IntList(64)
    /** Summary points: x, y, z, diameter in pixels, r, g, b. */
    val summaries = GrowFloats(7 * 256)
    /** Link bundles: ax, ay, az, bx, by, bz, width in pixels, r, g, b. */
    val bundles = GrowFloats(10 * 256)
    var detailNodes = 0
    var visibleCells = 0
    var summaryCount = 0
    var bundleCount = 0

    fun reset() {
        detailLeaves.clear(); summaries.clear(); bundles.clear()
        detailNodes = 0; visibleCells = 0; summaryCount = 0; bundleCount = 0
    }

    companion object { const val SUMMARY_STRIDE = 7; const val BUNDLE_STRIDE = 10 }
}

/**
 * Chooses each chunk's level of detail by its size on screen, continuously (plan 4e):
 * a chunk smaller than [openPixels] is one summary point (brightness = how many nodes,
 * colour = their mix); from there to twice that size it opens, its nodes moving out of the
 * summary point as it shrinks; beyond, it is drawn node by node. A chunk outside the frustum
 * is neither drawn nor opened; chunks in the guard band are requested from the cache so
 * they are ready when they arrive. A chunk not loaded yet stays a summary. Openness follows
 * its target at a fixed rate, so a load or a budget change morphs instead of popping.
 * Nothing here changes opacity: every change is position or size.
 */
class LodSelector(val tree: Octree, val cache: ChunkCache?) {
    private val shown = FloatArray(tree.cellCount)
    private val seen = IntArray(tree.cellCount) { -10 }
    private val drawnX = FloatArray(tree.cellCount)
    private val drawnY = FloatArray(tree.cellCount)
    private val drawnZ = FloatArray(tree.cellCount)
    private val openness = FloatArray(tree.cellCount)
    private val rep = IntArray(max(tree.leafCount, 1))
    private val repVisible = BooleanArray(max(tree.leafCount, 1))
    private val pairs = LongIntMap(1024)
    private val childScratch = Array(32) { IntArray(8) }
    private val childDist = Array(32) { FloatArray(8) }
    private val logMax = ln(1f + max(tree.count.firstOrNull() ?: 1, 1))
    val plan = FramePlan(tree.leafCount)

    /** Opening per second while catching up with its target: about a fifth of a second for a full morph. */
    var morphRate = 5f

    companion object { const val BUNDLE_GLOW = 0.06f; const val SUMMARY_SATURATION = 2.2f }

    private lateinit var frustum: Frustum
    private lateinit var guard: GuardBand
    private var eyeX = 0f; private var eyeY = 0f; private var eyeZ = 0f
    private var focal = 1f
    private var open = 36f
    private var dt = 0f
    private var frame = 0
    private var maxDetail = Int.MAX_VALUE

    fun select(eye: Vec3, focalPixels: Float, frustum: Frustum, guard: GuardBand, openPixels: Float, maxDetailNodes: Int, dtSeconds: Float, frame: Int): FramePlan {
        this.frustum = frustum; this.guard = guard
        eyeX = eye.x; eyeY = eye.y; eyeZ = eye.z
        focal = focalPixels; open = openPixels; maxDetail = maxDetailNodes
        dt = dtSeconds.coerceIn(0f, 0.5f); this.frame = frame
        plan.reset()
        if (tree.cellCount == 0 || tree.nodeCount == 0) return plan
        val root = Octree.ROOT
        visit(root, tree.cx[root], tree.cy[root], tree.cz[root], 1f, true)
        buildBundles()
        return plan
    }

    /** On-screen radius of a cell, in pixels; a camera inside the cell sees it as huge. */
    fun pixelRadius(cell: Int): Float {
        val dx = tree.cx[cell] - eyeX; val dy = tree.cy[cell] - eyeY; val dz = tree.cz[cell] - eyeZ
        val d = sqrt(dx * dx + dy * dy + dz * dz)
        val r = tree.radius[cell]
        return if (d <= r) 1e6f else r * focal / d
    }

    private fun visit(cell: Int, ax: Float, ay: Float, az: Float, tParent: Float, drawing: Boolean) {
        val px = mix(ax, tree.cx[cell], tParent)
        val py = mix(ay, tree.cy[cell], tParent)
        val pz = mix(az, tree.cz[cell], tParent)
        drawnX[cell] = px; drawnY[cell] = py; drawnZ[cell] = pz
        val r = tree.radius[cell]
        val inView = drawing && frustum.intersectsSphere(tree.cx[cell], tree.cy[cell], tree.cz[cell], r)
        val inGuard = inView || guard.contains(tree.cx[cell], tree.cy[cell], tree.cz[cell], r)
        if (seen[cell] < frame - 1) shown[cell] = 0f
        seen[cell] = frame
        if (!inGuard) {
            shown[cell] = 0f
            assignLeaves(cell, visible = false)
            return
        }
        val pixels = pixelRadius(cell)
        var target = smoothstep(open, open * 2, pixels)
        val leaf = tree.leafIndex[cell]
        if (leaf >= 0 && target > 0f) {
            cache?.request(leaf, pixels + if (inView) 1e7f else 0f)
            if (cache != null && !cache.isResident(leaf)) target = 0f
            if (inView && plan.detailNodes + tree.count[cell] > maxDetail) target = 0f
        }
        val t = approach(shown[cell], target)
        shown[cell] = t
        if (!inView) {
            assignLeaves(cell, visible = false)
            if (leaf < 0 && target > 0f) visitChildren(cell, px, py, pz, t.coerceAtLeast(0.001f), drawing = false)
            return
        }
        plan.visibleCells++
        if (t < 1f) emitSummary(cell, pixels, 1f - t, px, py, pz)
        if (leaf >= 0) {
            cache?.touch(leaf, frame)
            val s = leaf * 4
            plan.leafState[s] = px; plan.leafState[s + 1] = py; plan.leafState[s + 2] = pz; plan.leafState[s + 3] = t
            rep[leaf] = cell; repVisible[leaf] = true
            openness[cell] = t
            if (t > 0f) { plan.detailLeaves.add(leaf); plan.detailNodes += tree.count[cell] }
            return
        }
        if (t <= 0f) { assignLeaves(cell, visible = true); return }
        visitChildren(cell, px, py, pz, t, drawing = true)
    }

    /** Children nearest first, so the detail cap spends itself on what is closest. */
    private fun visitChildren(cell: Int, px: Float, py: Float, pz: Float, t: Float, drawing: Boolean) {
        val n = tree.childCount[cell]
        val depth = min(tree.depth[cell], childScratch.size - 1)
        val ids = childScratch[depth]; val dist = childDist[depth]
        for (k in 0 until n) {
            val c = tree.childList[tree.firstChild[cell] + k]
            val dx = tree.cx[c] - eyeX; val dy = tree.cy[c] - eyeY; val dz = tree.cz[c] - eyeZ
            var j = k
            val d = dx * dx + dy * dy + dz * dz
            while (j > 0 && dist[j - 1] > d) { ids[j] = ids[j - 1]; dist[j] = dist[j - 1]; j-- }
            ids[j] = c; dist[j] = d
        }
        // a child's own children use the next row down, so this row stays intact meanwhile
        for (k in 0 until n) visit(ids[k], px, py, pz, t, drawing)
    }

    private fun assignLeaves(cell: Int, visible: Boolean) {
        openness[cell] = 0f
        val x = drawnX[cell]; val y = drawnY[cell]; val z = drawnZ[cell]
        for (leaf in tree.leafStart[cell] until tree.leafEnd[cell]) {
            val s = leaf * 4
            plan.leafState[s] = x; plan.leafState[s + 1] = y; plan.leafState[s + 2] = z; plan.leafState[s + 3] = 0f
            rep[leaf] = cell; repVisible[leaf] = visible
        }
    }

    private fun emitSummary(cell: Int, pixels: Float, scale: Float, x: Float, y: Float, z: Float) {
        val diameter = (pixels * 1.1f).coerceIn(2.5f, 120f) * scale
        if (diameter < 0.4f) return
        val brightness = 0.35f + 0.65f * ln(1f + tree.count[cell]) / max(logMax, 1e-3f)
        // the mean of many topics drifts to grey, so its hue is pushed back out: the mix still decides the colour
        val r = tree.colorR[cell]; val g = tree.colorG[cell]; val b = tree.colorB[cell]
        val lum = 0.3f * r + 0.59f * g + 0.11f * b
        fun vivid(c: Float) = (lum + (c - lum) * SUMMARY_SATURATION).coerceIn(0f, 1f) * brightness
        plan.summaries.add(x, y, z, diameter, vivid(r), vivid(g), vivid(b))
        plan.summaryCount++
    }

    private fun approach(current: Float, target: Float): Float {
        val step = morphRate * dt
        return if (target > current) min(target, current + step) else max(target, current - step)
    }

    /** One bundle per pair of drawn chunks, from the leaf-pair link counts. */
    private fun buildBundles() {
        pairs.clear()
        val a = tree.bundleA; val b = tree.bundleB; val counts = tree.bundleCount
        for (i in a.indices) {
            val la = a[i]; val lb = b[i]
            val ra = rep[la]; val rb = rep[lb]
            if (ra == rb) continue
            if (!repVisible[la] && !repVisible[lb]) continue
            if (max(openness[ra], openness[rb]) >= 0.98f) continue
            pairs.add(Octree.pairKey(min(ra, rb), max(ra, rb)), counts[i])
        }
        // the more threads cross the view, the fainter each, so together they stay a haze
        val density = min(1f, sqrt(400f / max(pairs.size, 1)))
        pairs.forEach { key, count ->
            val ra = (key ushr 32).toInt(); val rb = key.toInt()
            val width = (0.8f + 0.55f * log2(1f + count)).coerceAtMost(6f) * (1f - max(openness[ra], openness[rb]))
            if (width < 0.05f) return@forEach
            // faint threads: thousands of bundles add up, and the summaries are what carry the eye
            val glow = BUNDLE_GLOW * density * (0.3f + 0.7f * min(1f, log2(1f + count) / 12f))
            plan.bundles.add10(
                drawnX[ra], drawnY[ra], drawnZ[ra], drawnX[rb], drawnY[rb], drawnZ[rb], width,
                (tree.colorR[ra] + tree.colorR[rb]) * glow, (tree.colorG[ra] + tree.colorG[rb]) * glow, (tree.colorB[ra] + tree.colorB[rb]) * glow,
            )
            plan.bundleCount++
        }
    }
}

class GrowFloats(capacity: Int) {
    var data = FloatArray(max(capacity, 16)); private set
    var size = 0; private set
    fun clear() { size = 0 }
    private fun ensure(extra: Int) { if (size + extra > data.size) data = data.copyOf(max(data.size * 2, size + extra)) }
    fun add(a: Float, b: Float, c: Float, d: Float, e: Float, f: Float, g: Float) {
        ensure(7); val s = size
        data[s] = a; data[s + 1] = b; data[s + 2] = c; data[s + 3] = d; data[s + 4] = e; data[s + 5] = f; data[s + 6] = g
        size += 7
    }
    fun add10(a: Float, b: Float, c: Float, d: Float, e: Float, f: Float, g: Float, h: Float, i: Float, j: Float) {
        ensure(10); val s = size
        data[s] = a; data[s + 1] = b; data[s + 2] = c; data[s + 3] = d; data[s + 4] = e
        data[s + 5] = f; data[s + 6] = g; data[s + 7] = h; data[s + 8] = i; data[s + 9] = j
        size += 10
    }
}
