package com.stethoscore.app.map

/**
 * The GPU pool for chunk detail (each leaf chunk's link list), cut into fixed pages so any
 * chunk fits wherever pages are free. Chunks stream in with a per-frame budget, the most
 * wanted (largest on screen) first, so a fast pan never stalls a frame; when the pool is
 * full the least recently used chunk goes first, never one drawn this frame, so turning
 * back to a place just seen is instant (plan 4e, points 3 and 4).
 *
 * Pure Kotlin: the actual upload is the [Uploader] callback, so the policy is unit tested.
 */
class ChunkCache(
    val pageCount: Int,
    val pageSize: Int,
    /** Size of a chunk's detail, in elements (link indices). */
    private val sizeOf: (Int) -> Int,
) {
    fun interface Uploader { fun upload(chunk: Int, pages: IntArray) }

    private val pagesOf = HashMap<Int, IntArray>()
    /** Access order: the first entry is the least recently used. */
    private val lru = LinkedHashMap<Int, Int>(64, 0.75f, true)
    /** Free pages as a stack: free[0 until freeTop]. */
    private val free = IntArray(pageCount) { pageCount - 1 - it }
    private var freeTop = pageCount
    private val requests = HashMap<Int, Float>()

    var uploadedThisFrame = 0; private set
    var evictedTotal = 0; private set
    var uploadedTotal = 0; private set
    val residentCount get() = pagesOf.size
    val freePages get() = freeTop

    fun pagesNeeded(chunk: Int) = (sizeOf(chunk) + pageSize - 1) / pageSize

    fun isResident(chunk: Int) = pagesOf.containsKey(chunk) || sizeOf(chunk) == 0

    fun pages(chunk: Int): IntArray? = pagesOf[chunk]

    /** Marks a chunk as drawn in [frame]: it moves to the most recently used end. */
    fun touch(chunk: Int, frame: Int) { if (pagesOf.containsKey(chunk)) lru[chunk] = frame }

    /** Asks for a chunk this frame; a higher [priority] loads sooner. */
    fun request(chunk: Int, priority: Float) {
        if (isResident(chunk)) return
        val old = requests[chunk]
        if (old == null || priority > old) requests[chunk] = priority
    }

    /**
     * Loads the wanted chunks, highest priority first, until [budget] elements have gone up
     * this frame (at least one chunk always goes, so a chunk bigger than the budget still
     * loads). Evicts least recently used chunks not drawn in [frame] to make room.
     */
    fun pump(frame: Int, budget: Int, uploader: Uploader) {
        uploadedThisFrame = 0
        if (requests.isEmpty()) return
        val wanted = requests.entries.sortedByDescending { it.value }.map { it.key }
        requests.clear()
        var spent = 0
        for (chunk in wanted) {
            if (isResident(chunk)) continue
            val size = sizeOf(chunk)
            if (spent > 0 && spent + size > budget) break
            val need = pagesNeeded(chunk)
            if (need > pageCount) continue
            while (freeTop < need) if (!evictOne(frame)) break
            if (freeTop < need) break
            val pages = IntArray(need) { free[--freeTop] }
            uploader.upload(chunk, pages)
            pagesOf[chunk] = pages
            lru[chunk] = frame
            spent += size
            uploadedThisFrame++
            uploadedTotal++
        }
    }

    private fun evictOne(frame: Int): Boolean {
        val victim = lru.entries.firstOrNull { it.value != frame }?.key ?: return false
        lru.remove(victim)
        val pages = pagesOf.remove(victim) ?: return false
        for (p in pages) free[freeTop++] = p
        evictedTotal++
        return true
    }

    /** Ids of the resident chunks, least recently used first (for tests and the readout). */
    fun lruOrder(): List<Int> = lru.keys.toList()
}
