package com.stethoscore.app.map

import kotlin.math.max
import kotlin.math.min

/**
 * The adaptive frame budget (plan 4c and 4e): the frame rate is the display's own, and a
 * device that cannot keep it draws less, never slower. [detail] scales how far each level
 * of detail reaches: a chunk opens into its nodes once it covers [openPixels] on screen, so
 * a slow phone sees summaries sooner and a fast tablet later. Changes are small steps, and
 * the map morphs between levels, so a budget change never pops.
 */
class FrameBudget(refreshHz: Float, initialDetail: Float = 0.6f) {
    var refreshHz = refreshHz
        set(value) { field = max(value, 1f) }
    val targetMs get() = 1000.0 / refreshHz

    /** 1 is the reference reach; lower opens fewer chunks. */
    var detail = initialDetail.coerceIn(MIN_DETAIL, MAX_DETAIL); private set

    /** On-screen radius (pixels) at which a chunk starts to open into its nodes. */
    val openPixels get() = BASE_OPEN_PIXELS / detail

    /** Most nodes drawn one by one in a frame, a backstop for the worst views. */
    val maxDetailNodes get() = (BASE_DETAIL_NODES * detail * detail).toInt().coerceIn(20_000, 4_000_000)

    /** Link indices streamed to the GPU per frame. */
    val uploadBudget get() = (120_000 * detail).toInt().coerceIn(16_384, 400_000)

    private var slowStreak = 0
    private var fastStreak = 0

    /**
     * One finished frame: [intervalMs] since the previous vsync this map drew on, and
     * [workMs], the time spent preparing and submitting it. A frame that missed a refresh,
     * or work that eats most of the frame, cuts detail; a steady run of easy frames raises it.
     */
    fun onFrame(intervalMs: Double, workMs: Double) {
        val target = targetMs
        val missed = intervalMs > target * 1.45
        val heavy = workMs > target * 0.75
        if (missed || heavy) {
            fastStreak = 0
            if (++slowStreak >= 2) { detail = max(MIN_DETAIL, detail * 0.88f); slowStreak = 0 }
        } else {
            slowStreak = 0
            val easy = intervalMs < target * 1.2 && workMs < target * 0.4
            if (easy && ++fastStreak >= 24) { detail = min(MAX_DETAIL, detail * 1.05f); fastStreak = 0 }
            if (!easy) fastStreak = 0
        }
    }

    companion object {
        const val MIN_DETAIL = 0.05f
        const val MAX_DETAIL = 4f
        const val BASE_OPEN_PIXELS = 36f
        const val BASE_DETAIL_NODES = 600_000
    }
}

/** Frame times summed up for the on-screen readout. */
class FrameStats(private val capacity: Int = 240) {
    private val intervals = DoubleArray(capacity)
    private val work = DoubleArray(capacity)
    private val stamps = LongArray(capacity)
    private var next = 0
    var count = 0; private set

    fun add(timeNanos: Long, intervalMs: Double, workMs: Double) {
        stamps[next] = timeNanos; intervals[next] = intervalMs; work[next] = workMs
        next = (next + 1) % capacity; count = min(count + 1, capacity)
    }

    /** Frames a second over the frames drawn in the last [windowNanos] before [nowNanos]. */
    fun fps(nowNanos: Long, windowNanos: Long = 500_000_000L): Double {
        if (count == 0) return 0.0
        val newest = stamps[(next - 1 + capacity) % capacity]
        var frames = 0; var oldest = newest
        for (k in 0 until count) {
            val t = stamps[(next - 1 - k + capacity) % capacity]
            if (nowNanos - t > windowNanos) break
            frames++; oldest = t
        }
        if (frames < 2 || newest == oldest) return 0.0
        return (frames - 1) * 1e9 / (newest - oldest).toDouble()
    }

    fun medianInterval(): Double = percentile(intervals, 0.5)
    fun medianWork(): Double = percentile(work, 0.5)
    fun p95Work(): Double = percentile(work, 0.95)

    private fun percentile(source: DoubleArray, q: Double): Double {
        if (count == 0) return 0.0
        val sorted = DoubleArray(count) { k -> source[(next - 1 - k + capacity) % capacity] }.also { it.sort() }
        val rank = kotlin.math.ceil(q * count).toInt().coerceIn(1, count)
        return sorted[rank - 1]
    }
}

/** A display mode as Android reports it. */
data class DisplayModeInfo(val id: Int, val width: Int, val height: Int, val refreshHz: Float)

object RefreshRate {
    /**
     * The mode to ask for: the highest refresh rate at the current resolution (changing the
     * resolution would rescale the whole app), or null when the current mode is already it.
     */
    fun bestMode(modes: List<DisplayModeInfo>, current: DisplayModeInfo): DisplayModeInfo? {
        val same = modes.filter { it.width == current.width && it.height == current.height }
        val best = same.maxByOrNull { it.refreshHz } ?: return null
        return if (best.refreshHz > current.refreshHz + 0.5f) best else null
    }

    fun maxHz(modes: List<DisplayModeInfo>, fallback: Float = 60f) = modes.maxOfOrNull { it.refreshHz } ?: fallback
}

/** Thousands with commas, the same in every locale (the readout is a meter). */
fun grouped(n: Int): String {
    val digits = kotlin.math.abs(n).toString()
    val out = StringBuilder()
    digits.forEachIndexed { k, ch -> if (k > 0 && (digits.length - k) % 3 == 0) out.append(','); out.append(ch) }
    return (if (n < 0) "-" else "") + out
}
