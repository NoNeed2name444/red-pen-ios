package com.stethoscore.app.export

import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

/**
 * The smallest possible ZIP writer (iOS MiniZip): STORE, CRC-32, local
 * headers and a central directory, written from files to a file a piece at a
 * time, so a deck of pictures never sits in memory twice.
 */
object MiniZip {

    class Failure(message: String) : IOException(message) {
        companion object {
            val tooMany get() = Failure("That deck has more pictures than one Anki file can hold.")
            val tooLarge get() = Failure("That deck is too large for one Anki file.")
            val unwritable get() = Failure("The file could not be written.")
        }
    }

    /** Writes [files] - each a name inside the archive and a file on disk - as one zip at [to], replacing anything there. */
    fun write(files: List<Pair<String, File>>, to: File) {
        // a plain zip counts entries in 16 bits and offsets in 32; past either it would need zip64
        if (files.size > 0xFFFF) throw Failure.tooMany
        to.delete()
        val out = try { FileOutputStream(to).buffered(chunk) } catch (e: IOException) { throw Failure.unwritable }
        out.use { stream ->
            val central = java.io.ByteArrayOutputStream()
            var offset = 0L
            for ((name, file) in files) {
                val nameBytes = name.toByteArray(Charsets.UTF_8)
                val (crc, size) = checksum(file)
                if (offset > 0xFFFFFFFFL || size > 0xFFFFFFFFL) throw Failure.tooLarge
                val local = java.io.ByteArrayOutputStream()
                local.le32(0x04034b50); local.le16(20); local.le16(0); local.le16(0)
                local.le16(0); local.le16(0x21) // time/date: fixed
                local.le32(crc); local.le32(size); local.le32(size)
                local.le16(nameBytes.size); local.le16(0)
                local.write(nameBytes)
                local.writeTo(stream)
                FileInputStream(file).use { it.copyTo(stream, chunk) }

                central.le32(0x02014b50); central.le16(20); central.le16(20)
                central.le16(0); central.le16(0)
                central.le16(0); central.le16(0x21)
                central.le32(crc); central.le32(size); central.le32(size)
                central.le16(nameBytes.size); central.le16(0); central.le16(0)
                central.le16(0); central.le16(0); central.le32(0)
                central.le32(offset)
                central.write(nameBytes)

                offset += local.size() + size
            }
            if (offset > 0xFFFFFFFFL) throw Failure.tooLarge
            central.writeTo(stream)
            val end = java.io.ByteArrayOutputStream()
            end.le32(0x06054b50); end.le16(0); end.le16(0)
            end.le16(files.size); end.le16(files.size)
            end.le32(central.size().toLong()); end.le32(offset); end.le16(0)
            end.writeTo(stream)
        }
    }

    /** Pieces this size are read and written at a time. */
    private const val chunk = 1 shl 20

    private fun checksum(file: File): Pair<Long, Long> {
        var running = 0xFFFFFFFFL
        var size = 0L
        FileInputStream(file).use { input ->
            val buffer = ByteArray(chunk)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                running = update(running, buffer, read)
                size += read
            }
        }
        return (running xor 0xFFFFFFFFL) to size
    }

    /** CRC-32 of some bytes, as a zip records it. */
    fun crc32(data: ByteArray): Long = update(0xFFFFFFFFL, data, data.size) xor 0xFFFFFFFFL

    private fun update(crc: Long, data: ByteArray, count: Int): Long {
        var c = crc
        for (i in 0 until count) c = table[((c xor (data[i].toLong() and 0xFF)) and 0xFF).toInt()] xor (c ushr 8)
        return c
    }

    private val table: LongArray = LongArray(256) { i ->
        var c = i.toLong()
        repeat(8) { c = if (c and 1L != 0L) 0xEDB88320L xor (c ushr 1) else c ushr 1 }
        c
    }

    private fun java.io.ByteArrayOutputStream.le16(v: Int) { write(v and 0xFF); write((v ushr 8) and 0xFF) }
    private fun java.io.ByteArrayOutputStream.le32(v: Long) { for (shift in 0..24 step 8) write(((v ushr shift) and 0xFF).toInt()) }
    private fun java.io.ByteArrayOutputStream.le32(v: Int) = le32(v.toLong() and 0xFFFFFFFFL)
}
