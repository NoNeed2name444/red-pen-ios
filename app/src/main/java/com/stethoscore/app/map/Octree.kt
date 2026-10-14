package com.stethoscore.app.map

import kotlin.math.max
import kotlin.math.sqrt

/** The node colours by group: blue, teal, amber, violet, rose, green (the Ward map palette). */
object MapPalette {
    val rgb = floatArrayOf(
        0.46f, 0.71f, 0.95f,
        0.41f, 0.82f, 0.75f,
        0.94f, 0.71f, 0.40f,
        0.69f, 0.61f, 0.95f,
        0.95f, 0.52f, 0.62f,
        0.55f, 0.85f, 0.45f,
    )
    fun r(g: Int) = rgb[3 * (g % MapGraph.PALETTE_SIZE)]
    fun g(g: Int) = rgb[3 * (g % MapGraph.PALETTE_SIZE) + 1]
    fun b(g: Int) = rgb[3 * (g % MapGraph.PALETTE_SIZE) + 2]
}

/**
 * The map cut into an octree of chunks (plan 4e). Building it reorders the nodes so every
 * chunk's nodes sit next to each other: one GPU buffer holds them all, and a chunk is drawn
 * as one range of it. Each octree cell keeps a summary (centroid, how many, colour mix) for
 * drawing it from far away; each leaf chunk keeps the links that touch it; and every pair
 * of leaf chunks that links keeps one bundle with its link count.
 */
class Octree private constructor(
    /** Node positions and groups in chunk order. */
    val positions: FloatArray,
    val groups: ByteArray,
    /** Original node index for each node in chunk order. */
    val order: IntArray,
    /** The leaf chunk of each node, in chunk order. */
    val leafOfNode: IntArray,
    val cellCount: Int,
    val cx: FloatArray, val cy: FloatArray, val cz: FloatArray,
    val radius: FloatArray,
    val count: IntArray,
    val colorR: FloatArray, val colorG: FloatArray, val colorB: FloatArray,
    val firstChild: IntArray, val childCount: IntArray,
    /** Children of a cell are cells childList[firstChild until firstChild + childCount]. */
    val childList: IntArray,
    val start: IntArray, val end: IntArray,
    val depth: IntArray,
    /** The leaf index of a cell, or -1 for an inner cell. */
    val leafIndex: IntArray,
    /** A cell's leaves are leaves leafStart until leafEnd (depth-first order). */
    val leafStart: IntArray, val leafEnd: IntArray,
    /** Cell of each leaf. */
    val leafCell: IntArray,
    /** Links touching each leaf, as node index pairs in chunk order (CSR: leafEdgeStart). */
    val leafEdgeStart: IntArray,
    val leafEdges: IntArray,
    /** One bundle per linked leaf pair (a < b) with its link count. */
    val bundleA: IntArray, val bundleB: IntArray, val bundleCount: IntArray,
    val edgeCount: Int,
) {
    val leafCount get() = leafCell.size
    val nodeCount get() = groups.size
    fun isLeaf(cell: Int) = leafIndex[cell] >= 0
    /** Index count (two per link) of the link list of a leaf. */
    fun leafEdgeIndexCount(leaf: Int) = leafEdgeStart[leaf + 1] - leafEdgeStart[leaf]

    companion object {
        const val ROOT = 0

        fun build(graph: MapGraph, leafCapacity: Int = 4096, maxDepth: Int = 10): Octree {
            val n = graph.nodeCount
            val src = graph.positions
            val perm = IntArray(n) { it }
            val scratch = IntArray(n)
            var minX = Float.MAX_VALUE; var minY = Float.MAX_VALUE; var minZ = Float.MAX_VALUE
            var maxX = -Float.MAX_VALUE; var maxY = -Float.MAX_VALUE; var maxZ = -Float.MAX_VALUE
            for (i in 0 until n) {
                minX = minOf(minX, src[3 * i]); maxX = maxOf(maxX, src[3 * i])
                minY = minOf(minY, src[3 * i + 1]); maxY = maxOf(maxY, src[3 * i + 1])
                minZ = minOf(minZ, src[3 * i + 2]); maxZ = maxOf(maxZ, src[3 * i + 2])
            }
            if (n == 0) { minX = 0f; minY = 0f; minZ = 0f; maxX = 0f; maxY = 0f; maxZ = 0f }
            val half = max(max(maxX - minX, maxY - minY), max(maxZ - minZ, 1e-3f)) / 2 * 1.0001f
            val cells = CellBuilder()
            val leafCells = ArrayList<Int>()

            fun buildCell(lo: Int, hi: Int, ox: Float, oy: Float, oz: Float, h: Float, d: Int): Int {
                val cell = cells.add(lo, hi, d)
                cells.leafStart[cell] = leafCells.size
                if (hi - lo <= leafCapacity || d >= maxDepth) {
                    cells.leafIndex[cell] = leafCells.size
                    leafCells.add(cell)
                    cells.leafEnd[cell] = leafCells.size
                    return cell
                }
                // counting sort of this range into the eight octants
                val counts = IntArray(8)
                for (k in lo until hi) { val i = perm[k]; counts[octant(src, i, ox, oy, oz)]++ }
                val offsets = IntArray(9)
                for (o in 0 until 8) offsets[o + 1] = offsets[o] + counts[o]
                val cursor = offsets.copyOf(8)
                for (k in lo until hi) { val i = perm[k]; scratch[lo + cursor[octant(src, i, ox, oy, oz)]++] = i }
                System.arraycopy(scratch, lo, perm, lo, hi - lo)
                val children = ArrayList<Int>(8)
                val q = h / 2
                for (o in 0 until 8) {
                    if (counts[o] == 0) continue
                    val nx = ox + if (o and 1 != 0) q else -q
                    val ny = oy + if (o and 2 != 0) q else -q
                    val nz = oz + if (o and 4 != 0) q else -q
                    children.add(buildCell(lo + offsets[o], lo + offsets[o + 1], nx, ny, nz, q, d + 1))
                }
                cells.setChildren(cell, children)
                cells.leafEnd[cell] = leafCells.size
                return cell
            }
            buildCell(0, n, (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2, half, 0)

            // reorder nodes into chunk order
            val positions = FloatArray(n * 3)
            val groups = ByteArray(n)
            val inverse = IntArray(n)
            for (k in 0 until n) {
                val i = perm[k]
                positions[3 * k] = src[3 * i]; positions[3 * k + 1] = src[3 * i + 1]; positions[3 * k + 2] = src[3 * i + 2]
                groups[k] = graph.groups[i]
                inverse[i] = k
            }
            val m = cells.size
            val cx = FloatArray(m); val cy = FloatArray(m); val cz = FloatArray(m); val radius = FloatArray(m)
            val cr = FloatArray(m); val cg = FloatArray(m); val cb = FloatArray(m); val count = IntArray(m)
            for (c in 0 until m) {
                val lo = cells.start[c]; val hi = cells.end[c]
                var sx = 0.0; var sy = 0.0; var sz = 0.0; var r = 0.0; var g = 0.0; var b = 0.0
                for (k in lo until hi) {
                    sx += positions[3 * k]; sy += positions[3 * k + 1]; sz += positions[3 * k + 2]
                    val gr = groups[k].toInt(); r += MapPalette.r(gr); g += MapPalette.g(gr); b += MapPalette.b(gr)
                }
                val cnt = max(hi - lo, 1)
                cx[c] = (sx / cnt).toFloat(); cy[c] = (sy / cnt).toFloat(); cz[c] = (sz / cnt).toFloat()
                cr[c] = (r / cnt).toFloat(); cg[c] = (g / cnt).toFloat(); cb[c] = (b / cnt).toFloat()
                var maxD2 = 0f
                for (k in lo until hi) {
                    val dx = positions[3 * k] - cx[c]; val dy = positions[3 * k + 1] - cy[c]; val dz = positions[3 * k + 2] - cz[c]
                    maxD2 = max(maxD2, dx * dx + dy * dy + dz * dz)
                }
                radius[c] = max(sqrt(maxD2), 1e-3f)
                count[c] = hi - lo
            }
            val leafOfNode = IntArray(n)
            leafCells.forEachIndexed { leaf, cell -> for (k in cells.start[cell] until cells.end[cell]) leafOfNode[k] = leaf }

            // links per leaf (a link between two leaves is listed in both) and bundles per leaf pair
            val e = graph.edges
            val links = e.size / 2
            val leaves = leafCells.size
            val perLeaf = IntArray(leaves + 1)
            for (k in 0 until links) {
                val a = leafOfNode[inverse[e[2 * k]]]; val b = leafOfNode[inverse[e[2 * k + 1]]]
                perLeaf[a + 1] += 2; if (b != a) perLeaf[b + 1] += 2
            }
            for (l in 0 until leaves) perLeaf[l + 1] += perLeaf[l]
            val leafEdges = IntArray(perLeaf[leaves])
            val fill = perLeaf.copyOf(leaves)
            val pairs = LongIntMap(1024)
            for (k in 0 until links) {
                val u = inverse[e[2 * k]]; val v = inverse[e[2 * k + 1]]
                val a = leafOfNode[u]; val b = leafOfNode[v]
                leafEdges[fill[a]++] = u; leafEdges[fill[a]++] = v
                if (b != a) {
                    leafEdges[fill[b]++] = u; leafEdges[fill[b]++] = v
                    pairs.add(pairKey(minOf(a, b), maxOf(a, b)), 1)
                }
            }
            val bundleA = IntArray(pairs.size); val bundleB = IntArray(pairs.size); val bundleCount = IntArray(pairs.size)
            var bi = 0
            pairs.forEach { key, value -> bundleA[bi] = (key ushr 32).toInt(); bundleB[bi] = key.toInt(); bundleCount[bi] = value; bi++ }

            return Octree(
                positions, groups, perm, leafOfNode, m, cx, cy, cz, radius, count, cr, cg, cb,
                cells.firstChild.copyOf(m), cells.childCount.copyOf(m), cells.childList.toArray(),
                cells.start.copyOf(m), cells.end.copyOf(m), cells.depth.copyOf(m), cells.leafIndex.copyOf(m),
                cells.leafStart.copyOf(m), cells.leafEnd.copyOf(m), leafCells.toIntArray(),
                perLeaf, leafEdges, bundleA, bundleB, bundleCount, links,
            )
        }

        private fun octant(p: FloatArray, i: Int, ox: Float, oy: Float, oz: Float): Int =
            (if (p[3 * i] >= ox) 1 else 0) or (if (p[3 * i + 1] >= oy) 2 else 0) or (if (p[3 * i + 2] >= oz) 4 else 0)

        fun pairKey(a: Int, b: Int) = (a.toLong() shl 32) or (b.toLong() and 0xffffffffL)
    }

    private class CellBuilder {
        var size = 0
        var start = IntArray(64); var end = IntArray(64); var depth = IntArray(64)
        var firstChild = IntArray(64); var childCount = IntArray(64)
        var leafIndex = IntArray(64); var leafStart = IntArray(64); var leafEnd = IntArray(64)
        val childList = IntList()
        fun add(lo: Int, hi: Int, d: Int): Int {
            if (size == start.size) {
                val cap = size * 2
                start = start.copyOf(cap); end = end.copyOf(cap); depth = depth.copyOf(cap)
                firstChild = firstChild.copyOf(cap); childCount = childCount.copyOf(cap)
                leafIndex = leafIndex.copyOf(cap); leafStart = leafStart.copyOf(cap); leafEnd = leafEnd.copyOf(cap)
            }
            start[size] = lo; end[size] = hi; depth[size] = d; leafIndex[size] = -1
            return size++
        }
        fun setChildren(cell: Int, children: List<Int>) {
            firstChild[cell] = childList.size; childCount[cell] = children.size
            children.forEach { childList.add(it) }
        }
    }
}

class IntList(capacity: Int = 16) {
    private var data = IntArray(capacity)
    var size = 0; private set
    fun add(v: Int) { if (size == data.size) data = data.copyOf(size * 2); data[size++] = v }
    operator fun get(i: Int) = data[i]
    fun clear() { size = 0 }
    fun toArray() = data.copyOf(size)
}

/** An open-addressing Long to Int map that sums values, reused frame to frame without allocating. */
class LongIntMap(capacity: Int) {
    private var keys = LongArray(tableSize(capacity))
    private var values = IntArray(keys.size)
    private var used = BooleanArray(keys.size)
    var size = 0; private set

    private fun tableSize(c: Int): Int { var s = 16; while (s < c * 2) s *= 2; return s }
    private fun slot(key: Long): Int {
        var h = key * -0x61c8864680b583ebL
        h = h xor (h ushr 29)
        return (h.toInt()) and (keys.size - 1)
    }

    fun add(key: Long, value: Int) {
        if ((size + 1) * 2 > keys.size) grow()
        var s = slot(key)
        while (used[s]) {
            if (keys[s] == key) { values[s] += value; return }
            s = (s + 1) and (keys.size - 1)
        }
        used[s] = true; keys[s] = key; values[s] = value; size++
    }

    operator fun get(key: Long): Int {
        var s = slot(key)
        while (used[s]) { if (keys[s] == key) return values[s]; s = (s + 1) and (keys.size - 1) }
        return 0
    }

    fun clear() { if (size > 0) { used.fill(false); size = 0 } }

    fun forEach(action: (Long, Int) -> Unit) {
        for (s in keys.indices) if (used[s]) action(keys[s], values[s])
    }

    private fun grow() {
        val oldKeys = keys; val oldValues = values; val oldUsed = used
        keys = LongArray(oldKeys.size * 2); values = IntArray(keys.size); used = BooleanArray(keys.size); size = 0
        for (s in oldKeys.indices) if (oldUsed[s]) add(oldKeys[s], oldValues[s])
    }
}
