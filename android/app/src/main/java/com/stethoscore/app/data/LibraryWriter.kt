package com.stethoscore.app.data

import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * The one writer of a library file. A change hands it a numbered snapshot
 * ([submit]) and returns at once; the writer serialises and writes it on its
 * own thread. Snapshots that arrive while one is being written are coalesced:
 * only the newest waiting one is written. Every write, background or
 * [writeNow], goes through one lock and carries its number, so a later
 * snapshot is never overwritten by an earlier one.
 */
class LibraryWriter(private val executor: Executor) {
    /** A snapshot to write, numbered in the order the changes were made. */
    class Job(val generation: Long, val write: () -> Unit, val written: () -> Unit, val failed: (Exception) -> Unit)

    private val state = Object()
    private var pending: Job? = null
    private var draining = false
    private val io = ReentrantLock()
    /** The newest generation on disk; only read and written under [io]. */
    private var writtenGeneration = 0L

    private val numbers = java.util.concurrent.atomic.AtomicLong()
    /** The next snapshot's number: one count for every store over this library, so order holds across them. */
    fun nextGeneration(): Long = numbers.incrementAndGet()

    /** Called on the writing thread before each write, for tests (the thread, a write that is cut off). */
    @Volatile internal var beforeWrite: (() -> Unit)? = null
    /** How many writes reached the disk, for tests. */
    @Volatile var writes = 0
        private set

    /** Queues [job], replacing any older snapshot still waiting; never does file work on the calling thread. */
    fun submit(job: Job) {
        val start = synchronized(state) {
            val waiting = pending
            if (waiting == null || job.generation > waiting.generation) pending = job
            !draining.also { draining = true }
        }
        if (start) executor.execute(::drain)
    }

    /**
     * Writes [job] on the calling thread, after any write already running,
     * dropping waiting snapshots it supersedes. Throws what the write throws.
     */
    fun writeNow(job: Job) {
        synchronized(state) { pending?.let { if (it.generation <= job.generation) { pending = null; state.notifyAll() } } }
        io.withLock {
            if (job.generation <= writtenGeneration) return
            beforeWrite?.invoke()
            job.write()
            writtenGeneration = job.generation
            writes++
        }
    }

    /** Drops the waiting snapshot, if any (a failed write put memory back, so it no longer matches). */
    fun dropPending() { synchronized(state) { pending = null; state.notifyAll() } }

    /**
     * Blocks until every submitted snapshot is written (or failed). On a
     * writing thread itself (a callback) it returns at once: waiting there
     * would wait on itself, and its drain writes what is still waiting.
     */
    fun flush() {
        if (inDrain.get() == true) return
        synchronized(state) { while (draining || pending != null) state.wait() }
    }

    private fun drain() {
        val outer = inDrain.get() == true
        inDrain.set(true)
        try {
            while (true) {
                val job = synchronized(state) { pending.also { pending = null } } ?: break
                val error = io.withLock {
                    if (job.generation <= writtenGeneration) return@withLock SKIPPED
                    try {
                        beforeWrite?.invoke()
                        job.write()
                        writtenGeneration = job.generation
                        writes++
                        null
                    } catch (e: Exception) { e }
                }
                if (error === SKIPPED) continue
                // the callbacks run outside the write lock: they take the store's lock
                runCatching { if (error == null) job.written() else job.failed(error) }
            }
        } finally {
            if (!outer) inDrain.set(false)
            val again = synchronized(state) {
                // a snapshot that came in after the last look gets its own drain
                draining = pending != null
                state.notifyAll()
                draining
            }
            if (again) executor.execute(::drain)
        }
    }

    companion object {
        private val SKIPPED = Exception("superseded")
        private val inDrain = ThreadLocal<Boolean>()

        /** The one background thread every library writes on. */
        private val thread: Executor by lazy {
            Executors.newSingleThreadExecutor { r -> Thread(r, "library-writer").apply { isDaemon = true } }
        }
        private val writers = ConcurrentHashMap<String, LibraryWriter>()

        /** The process's writer for the library in [directory]: a store opened again over it waits for its writes. */
        fun of(directory: File): LibraryWriter =
            writers.getOrPut(runCatching { directory.canonicalPath }.getOrDefault(directory.absolutePath)) { LibraryWriter(thread) }
    }
}
