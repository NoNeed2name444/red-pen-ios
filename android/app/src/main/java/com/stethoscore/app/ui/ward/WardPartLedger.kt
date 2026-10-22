package com.stethoscore.app.ui.ward

import kotlin.math.floor

// A port of ios/RedPen/Shared/Ward/WardPartLedger.swift: the book of
// parts that can meet home's cut (WardPartBook, HomeFit), without the views,
// so it is checked on the JVM (HomeFitTest). Pure Kotlin.

/**
 * The top a part is booked at: floored onto the pixel grid, never rounded
 * to the nearest half point, so a booked top is never below the real one
 * (682.78 at 3x books 682.667, not 683: the part drawn at 682.67 would
 * otherwise show a pixel over a cut at 683).
 */
fun wardBookedTop(value: Double, scale: Double): Double {
    if (!value.isFinite()) return value
    if (!(scale > 0) || !scale.isFinite()) return floor(value)
    return floor(value * scale + 1e-6) / scale
}

/** CGRect.isEmpty, for the ledger: no width or no height (WardRect is WardIsland's). */
val WardRect.isEmpty: Boolean get() = !(width > 0) || !(height > 0)

/**
 * The parts of a page that reported themselves at rest, by key (the view's
 * id): the logic of WardPartBook without the views (HomeFit's settledCut
 * reads its tops). A part that goes away is dropped; a new page clears the
 * lot.
 */
class WardPartLedger<K> {
    /** A live part's latest reported frame, kept whether or not the page is at rest so the next rest can book it. */
    data class Sighting(val name: String, val rect: WardRect, val reach: Double, val scale: Double)

    data class Entry(val name: String, val rect: WardRect, val top: Double) {
        constructor(sighting: Sighting) : this(
            sighting.name,
            sighting.rect.copy(y = sighting.rect.y - sighting.reach, height = sighting.rect.height + sighting.reach),
            wardBookedTop(sighting.rect.y - sighting.reach, sighting.scale),
        )

        fun isHidden(cut: Double?): Boolean {
            if (cut == null) return false
            return rect.minY + 1e-6 >= cut
        }
    }

    /** What dropping a part did. */
    enum class Drop { removed, kept, none }

    private val entryMap = LinkedHashMap<K, Entry>()
    private val sightingMap = LinkedHashMap<K, Sighting>()
    /** Disappeared parts kept only because their last face was below the cut. */
    private val keptKeys = LinkedHashSet<K>()

    val entries: Map<K, Entry> get() = entryMap
    val sightings: Map<K, Sighting> get() = sightingMap

    /** The tops last published at rest. */
    var told: List<Double> = emptyList()
        private set

    /** The page's settled cut (global points), for the at-rest drop loop guard. */
    var cut: Double? = null

    /** The sorted, distinct booked tops. */
    val tops: List<Double> get() = entryMap.values.map { it.top }.toSet().sorted()

    /**
     * Records a sighting of one part and, at rest, books it from that
     * sighting and reports whether the published tops changed. Empty frames
     * are not kept.
     */
    fun set(key: K, sighting: Sighting, atRest: Boolean = true): Boolean {
        if (sighting.rect.isEmpty) return false
        sightingMap[key] = sighting
        keptKeys.remove(key)
        if (!atRest) return false
        entryMap[key] = Entry(sighting)
        return publish()
    }

    /** Books one part again from a sighting it is handed. */
    fun book(key: K, sighting: Sighting, atRest: Boolean = true): Boolean = set(key, sighting, atRest)

    /** One part's frame; [reach] is how far its face stands out above its frame (a row's tile). */
    fun set(key: K, name: String, rect: WardRect, reach: Double, scale: Double, atRest: Boolean = true): Boolean =
        set(key, Sighting(name, rect, reach, scale), atRest)

    /**
     * Books every live sighting again at once (used when the list comes to
     * rest) and reports whether the published tops changed.
     */
    fun rebook(): Boolean {
        // A hidden part's old frame cannot hold the cut up after the cut
        // moves below it. Live sightings above the cut still belong here.
        for (key in keptKeys.toList()) {
            val sighting = sightingMap[key]
            if (sighting != null && Entry(sighting).isHidden(cut)) continue
            sightingMap.remove(key)
            keptKeys.remove(key)
        }
        entryMap.clear()
        for ((key, sighting) in sightingMap) entryMap[key] = Entry(sighting)
        return publish()
    }

    /**
     * Drops a part that went away and reports what happened: removed, kept
     * because its last face was below the cut, or no such part. (iOS's
     * Drop-typed overload of drop.)
     */
    fun dropOutcome(key: K, atRest: Boolean = true, cut: Double? = null): Drop {
        val sighting = sightingMap[key]
        if (sighting != null && Entry(sighting).isHidden(cut ?: this.cut)) {
            keptKeys.add(key)
            return Drop.kept
        }
        if (sightingMap[key] == null && entryMap[key] == null && key !in keptKeys) return Drop.none
        keptKeys.remove(key)
        sightingMap.remove(key)
        entryMap.remove(key)
        if (atRest) publish()
        return Drop.removed
    }

    /**
     * Drops a part that went away. A part whose latest sighted face lies
     * wholly at or below the page's current cut is hidden by the cut rather
     * than gone, so it keeps its entry and its sighting: the next rest books
     * it where it was, and the cut never falls back to show it again (a
     * cut/drop loop at rest). This also holds a self-topped row that hides
     * just before scrolling back to rest. Use its latest sighting, not its
     * old rest frame; a row recycled above the cut still leaves the book.
     * While moving nothing publishes; the next rest publishes.
     */
    fun drop(key: K, atRest: Boolean = true, cut: Double? = null): Boolean {
        val sighting = sightingMap[key]
        if (sighting != null && Entry(sighting).isHidden(cut ?: this.cut)) {
            keptKeys.add(key)
            return false
        }
        keptKeys.remove(key)
        sightingMap.remove(key)
        entryMap.remove(key)
        if (!atRest) return false
        return publish()
    }

    /**
     * A new page: empties the book and reports whether the tops changed.
     * Keep the cut: an unchanged pageCut will not be reported again.
     */
    fun clear(): Boolean {
        entryMap.clear()
        sightingMap.clear()
        keptKeys.clear()
        return publish()
    }

    private fun publish(): Boolean {
        val now = tops
        if (now == told) return false
        told = now
        return true
    }
}
