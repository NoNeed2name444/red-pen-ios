package com.stethoscore.app.map

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * A map's nodes and links in flat arrays: positions x, y, z per node, a colour group per
 * node, and links as pairs of node indices. Flat arrays keep a million nodes at about 16 MB
 * and let them go to the GPU in one copy.
 */
class MapGraph(
    val positions: FloatArray,
    val groups: ByteArray,
    val edges: IntArray,
    /** Titles of real notes, by node; empty for synthetic maps. */
    val titles: List<String> = emptyList(),
    /** Note ids by node, for opening a tapped note; empty for synthetic maps. */
    val ids: List<String> = emptyList(),
) {
    val nodeCount get() = groups.size
    val edgeCount get() = edges.size / 2

    init {
        require(positions.size == groups.size * 3) { "positions must hold x, y, z per node" }
        require(edges.size % 2 == 0) { "edges must be pairs" }
    }

    companion object {
        /** Linked notes, laid out in 3D: a few hundred force steps for small maps, a sphere for big ones. */
        fun fromNotes(notes: List<NoteLike>): MapGraph {
            val n = notes.size
            val index = notes.withIndex().associate { it.value.id to it.index }
            val pairs = LinkedHashSet<Long>()
            notes.forEachIndexed { i, note ->
                note.links.forEach { id ->
                    val j = index[id] ?: return@forEach
                    if (j != i) pairs.add(min(i, j).toLong() shl 32 or max(i, j).toLong())
                }
            }
            val edges = IntArray(pairs.size * 2)
            pairs.forEachIndexed { k, key -> edges[2 * k] = (key ushr 32).toInt(); edges[2 * k + 1] = key.toInt() }
            val tags = notes.map { it.tags.firstOrNull() ?: "" }.distinct()
            val groups = ByteArray(n) { i -> (tags.indexOf(notes[i].tags.firstOrNull() ?: "") % PALETTE_SIZE).toByte() }
            val positions = layout(n, edges)
            return MapGraph(positions, groups, edges, notes.map { it.title }, notes.map { it.id })
        }

        /** Fibonacci sphere start, then spring steps (links pull, every pair pushes) when the map is small. */
        fun layout(n: Int, edges: IntArray, steps: Int = 300): FloatArray {
            val p = FloatArray(n * 3)
            if (n == 0) return p
            val radius = 1.6f * Math.cbrt(n.toDouble()).toFloat()
            val golden = PI * (3 - sqrt(5.0))
            for (i in 0 until n) {
                val y = if (n == 1) 0.0 else 1 - 2.0 * i / (n - 1)
                val r = sqrt(max(0.0, 1 - y * y))
                val a = golden * i
                p[3 * i] = (cos(a) * r * radius).toFloat(); p[3 * i + 1] = (y * radius).toFloat(); p[3 * i + 2] = (sin(a) * r * radius).toFloat()
            }
            if (n > 1500 || n == 1) return p
            val force = FloatArray(n * 3)
            for (step in 0 until steps) {
                force.fill(0f)
                for (i in 0 until n) for (j in i + 1 until n) {
                    val dx = p[3 * i] - p[3 * j]; val dy = p[3 * i + 1] - p[3 * j + 1]; val dz = p[3 * i + 2] - p[3 * j + 2]
                    val d2 = max(dx * dx + dy * dy + dz * dz, 0.01f)
                    val k = 1.2f / d2
                    force[3 * i] += dx * k; force[3 * i + 1] += dy * k; force[3 * i + 2] += dz * k
                    force[3 * j] -= dx * k; force[3 * j + 1] -= dy * k; force[3 * j + 2] -= dz * k
                }
                for (e in 0 until edges.size / 2) {
                    val i = edges[2 * e]; val j = edges[2 * e + 1]
                    val dx = p[3 * j] - p[3 * i]; val dy = p[3 * j + 1] - p[3 * i + 1]; val dz = p[3 * j + 2] - p[3 * i + 2]
                    val d = sqrt(dx * dx + dy * dy + dz * dz).coerceAtLeast(1e-3f)
                    val k = 0.08f * (d - 2f) / d
                    force[3 * i] += dx * k; force[3 * i + 1] += dy * k; force[3 * i + 2] += dz * k
                    force[3 * j] -= dx * k; force[3 * j + 1] -= dy * k; force[3 * j + 2] -= dz * k
                }
                val cool = 0.5f * (1 - step.toFloat() / steps) + 0.02f
                for (k in 0 until n * 3) p[k] += force[k].coerceIn(-1f, 1f) * cool
            }
            // centre on the origin
            for (axis in 0 until 3) {
                var mean = 0f
                for (i in 0 until n) mean += p[3 * i + axis]
                mean /= n
                for (i in 0 until n) p[3 * i + axis] -= mean
            }
            return p
        }

        const val PALETTE_SIZE = 6
    }
}

/** The parts of a note the map needs, so tests do not need the app's data layer. */
interface NoteLike { val id: String; val title: String; val links: List<String>; val tags: List<String> }

/**
 * A seeded synthetic vault for the performance demo: clusters of notes (folders) spread
 * like a galaxy, most links inside a cluster, some to a neighbour, a few anywhere. The same
 * seed gives the same map.
 */
object SyntheticGraph {
    fun make(nodes: Int = 1_000_000, clusters: Int = max(1, nodes / 500), meanExtraLinks: Double = 0.5, seed: Long = 0x5EED_1000_000L): MapGraph {
        val rng = SplitMix(seed)
        val worldRadius = 40f * Math.cbrt(nodes / 1000.0).toFloat().coerceAtLeast(1f)
        // cluster centres on a thick spiral disc, sizes by a heavy-tailed weight
        val cx = FloatArray(clusters); val cy = FloatArray(clusters); val cz = FloatArray(clusters); val spread = FloatArray(clusters)
        val weight = DoubleArray(clusters)
        for (c in 0 until clusters) {
            val arm = rng.below(3)
            val t = sqrt(rng.unit())
            val angle = t * 4.0 * PI + arm * 2 * PI / 3 + rng.gaussian() * 0.25
            val r = t * worldRadius
            cx[c] = (cos(angle) * r).toFloat(); cz[c] = (sin(angle) * r).toFloat()
            cy[c] = (rng.gaussian() * worldRadius * 0.06 * (1.2 - t)).toFloat()
            weight[c] = 1.0 / (1 + rng.unit() * 20)
            spread[c] = 0f
        }
        val total = weight.sum()
        val start = IntArray(clusters + 1)
        var acc = 0.0
        for (c in 0 until clusters) { acc += weight[c] / total; start[c + 1] = min(nodes, (acc * nodes).toInt()) }
        start[clusters] = nodes
        val positions = FloatArray(nodes * 3)
        val groups = ByteArray(nodes)
        val clusterOf = IntArray(nodes)
        for (c in 0 until clusters) {
            val count = start[c + 1] - start[c]
            spread[c] = 0.35f * Math.cbrt(max(count, 1).toDouble()).toFloat()
            val group = (c % MapGraph.PALETTE_SIZE).toByte()
            for (i in start[c] until start[c + 1]) {
                positions[3 * i] = cx[c] + (rng.gaussian() * spread[c]).toFloat()
                positions[3 * i + 1] = cy[c] + (rng.gaussian() * spread[c]).toFloat()
                positions[3 * i + 2] = cz[c] + (rng.gaussian() * spread[c]).toFloat()
                groups[i] = group
                clusterOf[i] = c
            }
        }
        // links: each note links to 1 + Poisson(mean) earlier notes, 88% in its cluster,
        // 10% in a neighbouring cluster, 2% anywhere
        val edges = IntArrayBuilder(nodes * 3)
        for (i in 1 until nodes) {
            val c = clusterOf[i]
            val want = 1 + rng.poisson(meanExtraLinks)
            for (k in 0 until want) {
                val u = rng.unit()
                val j = when {
                    u < 0.88 && i > start[c] -> start[c] + rng.below(i - start[c])
                    u < 0.98 && c > 0 -> { val d = max(0, c - 1 - rng.below(3)); start[d] + rng.below(max(1, start[d + 1] - start[d])) }
                    else -> rng.below(i)
                }
                if (j in 0 until i) edges.add(j, i)
            }
        }
        return MapGraph(positions, groups, edges.toArray())
    }
}

internal class IntArrayBuilder(capacity: Int) {
    private var data = IntArray(max(capacity, 2))
    var size = 0; private set
    fun add(a: Int, b: Int) {
        if (size + 2 > data.size) data = data.copyOf(data.size * 2)
        data[size++] = a; data[size++] = b
    }
    fun toArray(): IntArray = data.copyOf(size)
}

/** A small, fast, seeded generator (SplitMix64). */
internal class SplitMix(private var state: Long) {
    fun next(): Long {
        state += -0x61c8864680b583ebL
        var z = state
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        return z xor (z ushr 31)
    }
    fun unit(): Double = (next() ushr 11) * (1.0 / (1L shl 53))
    fun below(n: Int): Int = if (n <= 1) 0 else ((next() ushr 1) % n).toInt()
    fun gaussian(): Double {
        val u = max(unit(), 1e-12); val v = unit()
        return sqrt(-2 * ln(u)) * cos(2 * PI * v)
    }
    fun poisson(mean: Double): Int {
        val l = exp(-mean); var k = 0; var p = 1.0
        while (true) { p *= unit(); if (p <= l || k > 64) return k; k++ }
    }
}
