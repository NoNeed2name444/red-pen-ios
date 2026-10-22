package com.stethoscore.app.quiz

// A port of ios/RedPen/Shared/OptionOrder.swift.
//
// The order a question's options are shown in, and the one translation that
// every screen marking a shuffled question has to get right.
//
// There are two ways to number an option. The SLOT is where it sits on the
// screen (A is slot 0). The ORIGINAL index is its place in the question's own
// `options`, which is what `correctIndex`, the answer log's `picked`, the
// summary and the store all use. `order[slot]` is the original index shown in
// that slot. Marking compares original with original, always, so a slot can
// never be compared with `correctIndex` by mistake.
object OptionOrder {

    /**
     * [order] if it is a real ordering of [count] options - each index from
     * 0 to count-1 exactly once - and the options in their written order if
     * not. A saved order can go stale when a question is edited.
     */
    fun valid(order: List<Int>?, count: Int): List<Int> {
        val identity = (0 until maxOf(0, count)).toList()
        if (order == null || order.size != count) return identity
        return if (order.sorted() == identity) order else identity
    }

    /** A fresh order: shuffled, or as written. */
    fun make(count: Int, shuffle: Boolean): List<Int> {
        val identity = (0 until maxOf(0, count)).toList()
        return if (shuffle) identity.shuffled() else identity
    }

    /** The original index of the option in [slot], or null for no such slot. */
    fun original(slot: Int?, order: List<Int>): Int? {
        if (slot == null || slot !in order.indices) return null
        return order[slot]
    }

    /** The slot showing the option whose original index is [original]. */
    fun slot(original: Int, order: List<Int>): Int? = order.indexOf(original).takeIf { it >= 0 }

    /** Whether the option in [slot] is the right answer. */
    fun isCorrect(slot: Int?, correctIndex: Int, order: List<Int>): Boolean {
        val picked = original(slot, order) ?: return false
        return picked == correctIndex
    }
}
