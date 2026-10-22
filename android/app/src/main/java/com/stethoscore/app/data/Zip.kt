package com.stethoscore.app.data

import java.util.zip.DataFormatException
import java.util.zip.Inflater

/**
 * Reading files out of a zip archive (iOS Zip): stored and deflated entries,
 * zip64 too. Everything an archive says about itself is a claim, so nothing
 * here sizes memory from a field in the file: every entry is inflated a piece
 * at a time against a ceiling, entries that share bytes are refused, and only
 * the entries a caller asks for are read.
 */
object Zip {

    /** What opening one archive may cost. */
    data class Limits(val entryBytes: Int, val totalBytes: Int, val ratio: Int) {
        companion object { val standard = Limits(64 shl 20, 256 shl 20, 1_100) }
    }

    /** One file as the central directory lists it, with where its bytes are. */
    data class Entry(val name: String, val method: Int, val compressed: Long, val uncompressed: Long, val localOffset: Long, val dataStart: Long) {
        val dataEnd: Long get() = dataStart + compressed
    }

    /** Every file the archive lists, without reading any of them. */
    fun directory(data: ByteArray): List<Entry> = listing(data)

    /** The files wanted, by their path inside the archive, within [limits]. */
    fun entries(data: ByteArray, limits: Limits = Limits.standard, wanted: (String) -> Boolean = { true }): Map<String, ByteArray> {
        val found = LinkedHashMap<String, ByteArray>()
        var spent = 0L
        for (entry in listing(data)) {
            if (!wanted(entry.name)) continue
            val left = limits.totalBytes - spent
            if (left <= 0) break
            val (body, cost) = contents(entry, data, limits, left)
            spent += cost
            if (body != null) found[entry.name] = body
        }
        return found
    }

    /** Headroom for tiny entries, whose ratio says nothing. */
    private const val slack = 4_096L

    /** One entry's bytes, and how much of the budget reading it used. */
    fun contents(entry: Entry, data: ByteArray, limits: Limits = Limits.standard, budget: Long): Pair<ByteArray?, Long> {
        if (entry.dataStart < 0 || entry.dataStart > data.size || entry.compressed < 0 || entry.compressed > data.size - entry.dataStart) return null to 0L
        val plausible = entry.compressed * limits.ratio + slack
        if (entry.uncompressed > limits.entryBytes || entry.uncompressed > plausible || budget <= 0) return null to 0L
        val start = entry.dataStart.toInt()
        val end = entry.dataEnd.toInt()
        return when (entry.method) {
            0 -> if (entry.compressed <= minOf(limits.entryBytes.toLong(), budget)) data.copyOfRange(start, end) to entry.compressed else null to 0L
            8 -> inflate(data, start, end, minOf(limits.entryBytes.toLong(), budget, plausible))
            else -> null to 0L
        }
    }

    /** Raw deflate, a chunk at a time, abandoned the moment it passes [limit]; a stream that stops short gives back what it had. */
    fun inflate(data: ByteArray, from: Int, to: Int, limit: Long): Pair<ByteArray?, Long> {
        if (to <= from) return ByteArray(0) to 0L
        val inflater = Inflater(true)
        try {
            inflater.setInput(data, from, to - from)
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(1 shl 16)
            var produced = 0L
            while (true) {
                val made = try { inflater.inflate(buffer) } catch (e: DataFormatException) { return null to produced }
                produced += made
                if (produced > limit) return null to produced
                out.write(buffer, 0, made)
                if (inflater.finished()) return out.toByteArray() to produced
                if (made == 0 && (inflater.needsInput() || inflater.needsDictionary())) {
                    return (if (out.size() == 0) null else out.toByteArray()) to produced
                }
            }
        } finally {
            inflater.end()
        }
    }

    /** The central directory, each entry checked against its local header. */
    private fun listing(raw: ByteArray): List<Entry> {
        val (dirStart, count) = endOfCentralDirectory(raw) ?: return emptyList()
        val entries = mutableListOf<Entry>()
        var offset = dirStart
        for (n in 0 until count) {
            if (offset < 0 || offset + 46 > raw.size || read32(raw, offset) != 0x02014b50L) break
            val method = read16(raw, offset + 10)
            var compressed = read32(raw, offset + 20)
            var uncompressed = read32(raw, offset + 24)
            val nameLength = read16(raw, offset + 28)
            val extraLength = read16(raw, offset + 30)
            val commentLength = read16(raw, offset + 32)
            var localOffset = read32(raw, offset + 42)
            val nameStart = offset + 46
            if (nameStart + nameLength > raw.size) break
            val name = String(raw, nameStart.toInt(), nameLength, Charsets.UTF_8)
            val extraStart = nameStart + nameLength
            val wide32 = 0xFFFFFFFFL
            if (uncompressed == wide32 || compressed == wide32 || localOffset == wide32) {
                val wide = zip64Extra(raw, extraStart, extraLength)
                if (wide != null) {
                    var next = 0
                    if (uncompressed == wide32 && next < wide.size) { uncompressed = wide[next]; next++ }
                    if (compressed == wide32 && next < wide.size) { compressed = wide[next]; next++ }
                    if (localOffset == wide32 && next < wide.size) localOffset = wide[next]
                }
            }
            offset = nameStart + nameLength + extraLength + commentLength
            // the local header's own name and extra lengths are read, not the directory's
            if (localOffset < 0 || localOffset > raw.size - 30L || read32(raw, localOffset) != 0x04034b50L) continue
            val dataStart = localOffset + 30 + read16(raw, localOffset + 26) + read16(raw, localOffset + 28)
            if (compressed < 0 || uncompressed < 0 || dataStart > raw.size || compressed > raw.size - dataStart) continue
            entries += Entry(name, method, compressed, uncompressed, localOffset, dataStart)
        }
        return withoutOverlaps(entries)
    }

    /** Entries that share bytes with another are how a zip bomb is made; the first keeps its bytes. */
    fun withoutOverlaps(entries: List<Entry>): List<Entry> {
        val order = entries.indices.sortedWith(compareBy<Int> { entries[it].localOffset }.thenBy { it })
        val keep = BooleanArray(entries.size)
        var reached = 0L
        for (index in order) {
            if (entries[index].localOffset >= reached) {
                keep[index] = true
                reached = entries[index].dataEnd
            }
        }
        return entries.indices.filter { keep[it] }.map { entries[it] }
    }

    /** The 64-bit values in an entry's zip64 extra field (header 0x0001). */
    private fun zip64Extra(raw: ByteArray, start: Long, length: Int): List<Long>? {
        var at = start
        val end = minOf(start + length, raw.size.toLong())
        while (at + 4 <= end) {
            val id = read16(raw, at)
            val size = read16(raw, at + 2)
            val body = at + 4
            if (id == 0x0001) {
                val values = mutableListOf<Long>()
                var i = body
                while (i + 8 <= minOf(body + size, end)) {
                    val value = read64(raw, i)
                    if (value < 0) return null
                    values += value
                    i += 8
                }
                return values
            }
            at = body + size
        }
        return null
    }

    /** Where the central directory starts, and how many entries it lists, searched for backwards. */
    private fun endOfCentralDirectory(raw: ByteArray): Pair<Long, Int>? {
        if (raw.size < 22) return null
        val lowest = maxOf(0, raw.size - 22 - 65_535)
        var offset = raw.size - 22L
        while (offset >= lowest) {
            if (read32(raw, offset) == 0x06054b50L) {
                val start = read32(raw, offset + 16)
                val count = read16(raw, offset + 10)
                if ((start == 0xFFFFFFFFL || count == 0xFFFF) && offset >= 20 && read32(raw, offset - 20) == 0x07064b50L) {
                    val record = read64(raw, offset - 12)
                    if (raw.size >= 56 && record >= 0 && record <= raw.size - 56L && read32(raw, record) == 0x06064b50L) {
                        val wideCount = read64(raw, record + 32)
                        val wideStart = read64(raw, record + 48)
                        if (wideCount in 0..raw.size.toLong() && wideStart in 0..raw.size.toLong()) return wideStart to wideCount.toInt()
                    }
                }
                return start to count
            }
            offset -= 1
        }
        return null
    }

    private fun read16(raw: ByteArray, offset: Long): Int {
        if (offset < 0 || offset + 2 > raw.size) return 0
        val o = offset.toInt()
        return (raw[o].toInt() and 0xFF) or ((raw[o + 1].toInt() and 0xFF) shl 8)
    }

    private fun read32(raw: ByteArray, offset: Long): Long {
        if (offset < 0 || offset + 4 > raw.size) return 0
        val o = offset.toInt()
        return (raw[o].toLong() and 0xFF) or ((raw[o + 1].toLong() and 0xFF) shl 8) or
            ((raw[o + 2].toLong() and 0xFF) shl 16) or ((raw[o + 3].toLong() and 0xFF) shl 24)
    }

    /** Negative when the value is past Long.MAX_VALUE, which no file can hold. */
    private fun read64(raw: ByteArray, offset: Long): Long {
        if (offset < 0 || offset + 8 > raw.size) return 0
        return read32(raw, offset) or (read32(raw, offset + 4) shl 32)
    }
}
