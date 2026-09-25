import Foundation
import Compression

/// Reading files out of a zip archive.
///
/// A .docx is a zip: the text of the document is one XML file inside it, and
/// the pictures are in a folder beside it. Without a way in, the file format
/// most lecturers actually hand out - a Word handout rather than a PDF - cannot
/// be studied from at all.
///
/// Only reading is needed, and only of the two things a .docx uses: stored
/// entries and deflated ones. Deflate comes from Apple's own Compression
/// framework, which is on every device and on the test runner, so this is a few
/// dozen lines of offsets rather than a dependency.
///
/// Zip64 - an archive over four gigabytes or 65,535 entries - is read too:
/// no Word document is that size, but a whole Anki collection with its
/// pictures (AnKing) can be, and Anki writes zip64 when it is.
///
/// Everything an archive says about itself is a claim, and the file can come
/// from anyone - a handout shared in a group chat is opened the moment it is
/// picked. So nothing here sizes memory from a field in the file: every entry
/// is inflated a piece at a time against a ceiling (`Limits`), entries that
/// share bytes with one another are refused (the trick that turns one bomb
/// stream into ten thousand files), and only the entries a caller asks for are
/// read at all.
enum Zip {

    /// What opening one archive may cost.
    struct Limits {
        /// The most one entry may inflate to. A slide's XML is kilobytes and a
        /// picture a few megabytes; a 64 MB entry is a video nobody reads here.
        var entryBytes: Int
        /// The most every entry read from the archive may inflate to, together.
        var totalBytes: Int
        /// Deflate cannot do better than about 1,032 to 1, so an entry that
        /// claims - or turns out - to be larger than this many bytes for every
        /// compressed one is a bomb, not a document.
        var ratio: Int

        static let standard = Limits(entryBytes: 64 << 20, totalBytes: 256 << 20, ratio: 1_100)
    }

    /// One file as the central directory lists it, with where its bytes are.
    struct Entry: Equatable {
        var name: String
        /// 0 stored, 8 deflated; anything else is not read.
        var method: UInt16
        var compressed: Int
        /// As the archive states it: a claim, never a buffer size.
        var uncompressed: Int
        /// Where the entry's own header starts.
        var localOffset: Int
        /// Where its bytes start, past that header.
        var dataStart: Int

        var dataEnd: Int { dataStart + compressed }
    }

    /// Every file the archive lists, without reading any of them. Entries
    /// whose header is missing, whose bytes run past the end of the file, or
    /// that overlap another entry are left out.
    static func directory(of data: Data) -> [Entry] {
        data.withUnsafeBytes { raw in listing(raw) }
    }

    /// The files wanted, by their path inside the archive.
    ///
    /// Only names `wanted` accepts are inflated, in the order the archive
    /// lists them, and reading stops once `limits.totalBytes` have been
    /// produced. An entry over its own ceiling is left out rather than cut
    /// short: half a picture is not a picture.
    static func entries(in data: Data, limits: Limits = .standard,
                        where wanted: (String) -> Bool = { _ in true }) -> [String: Data] {
        data.withUnsafeBytes { raw -> [String: Data] in
            var found: [String: Data] = [:]
            var spent = 0
            for entry in listing(raw) where wanted(entry.name) {
                let left = limits.totalBytes - spent
                guard left > 0 else { break }
                let read = contents(of: entry, in: raw, limits: limits, budget: left)
                spent += read.cost
                if let body = read.body { found[entry.name] = body }
            }
            return found
        }
    }

    /// One entry's bytes, and how much of the budget reading it used - which
    /// counts the work done on an entry that was then refused, so a run of
    /// bombs cannot each cost a full ceiling for free.
    static func contents(of entry: Entry, in data: Data, limits: Limits = .standard,
                         budget: Int) -> (body: Data?, cost: Int) {
        data.withUnsafeBytes { raw -> (body: Data?, cost: Int) in
            guard entry.dataStart >= 0, entry.dataEnd <= raw.count else { return (nil, 0) }
            return contents(of: entry, in: raw, limits: limits, budget: budget)
        }
    }

    // MARK: reading one entry

    /// Headroom for tiny entries, whose ratio says nothing.
    private static let slack = 4_096

    private static func contents(of entry: Entry, in raw: UnsafeRawBufferPointer,
                                 limits: Limits, budget: Int) -> (body: Data?, cost: Int) {
        let plausible = entry.compressed * limits.ratio + slack
        // the stated size is only a claim, but a claim over the ceiling is
        // enough to refuse without inflating anything
        guard entry.uncompressed <= limits.entryBytes, entry.uncompressed <= plausible,
              budget > 0 else { return (nil, 0) }
        let bytes = UnsafeRawBufferPointer(rebasing: raw[entry.dataStart..<entry.dataEnd])
        switch entry.method {
        case 0:
            guard entry.compressed <= min(limits.entryBytes, budget) else { return (nil, 0) }
            return (Data(bytes), entry.compressed)
        case 8:
            let ceiling = min(limits.entryBytes, budget, plausible)
            let result = inflate(bytes, limit: ceiling)
            return (result.data, result.produced)
        default:
            return (nil, 0)
        }
    }

    /// Raw deflate - which is what COMPRESSION_ZLIB means here, despite the
    /// name: Apple's constant is the algorithm, not the zlib wrapper, and a zip
    /// entry carries no wrapper.
    ///
    /// Streamed a chunk at a time and abandoned the moment it passes `limit`,
    /// so the memory it takes is what the entry really holds, never what its
    /// header claims. A stream that stops short gives back what it had, as the
    /// one-shot decoder used to: most of a slide's text beats none of it.
    static func inflate(_ source: UnsafeRawBufferPointer, limit: Int) -> (data: Data?, produced: Int) {
        guard let base = source.baseAddress, !source.isEmpty else { return (Data(), 0) }
        let chunk = 1 << 16
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { return (nil, 0) }
        defer { compression_stream_destroy(stream) }
        stream.pointee.src_ptr = base.assumingMemoryBound(to: UInt8.self)
        stream.pointee.src_size = source.count

        var out = Data()
        var produced = 0
        let finish = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
        while true {
            let unread = stream.pointee.src_size
            stream.pointee.dst_ptr = buffer
            stream.pointee.dst_size = chunk
            let status = compression_stream_process(stream, finish)
            let made = chunk - stream.pointee.dst_size
            produced += made
            if status == COMPRESSION_STATUS_ERROR { return (nil, produced) }
            if produced > limit { return (nil, produced) }
            out.append(buffer, count: made)
            if status == COMPRESSION_STATUS_END { return (out, produced) }
            // nothing produced and nothing consumed: the stream ends early
            if made == 0 && stream.pointee.src_size == unread {
                return (out.isEmpty ? nil : out, produced)
            }
        }
    }

    // MARK: the archive's own bookkeeping

    /// The central directory, each entry checked against its local header.
    private static func listing(_ raw: UnsafeRawBufferPointer) -> [Entry] {
        guard let directory = endOfCentralDirectory(raw) else { return [] }
        var entries: [Entry] = []
        var offset = directory.start
        for _ in 0..<directory.count {
            guard offset >= 0, offset + 46 <= raw.count,
                  read32(raw, offset) == 0x0201_4b50 else { break }
            let method = read16(raw, offset + 10)
            var compressed = Int(read32(raw, offset + 20))
            var uncompressed = Int(read32(raw, offset + 24))
            let nameLength = Int(read16(raw, offset + 28))
            let extraLength = Int(read16(raw, offset + 30))
            let commentLength = Int(read16(raw, offset + 32))
            var localOffset = Int(read32(raw, offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLength <= raw.count else { break }
            let nameBytes = UnsafeRawBufferPointer(rebasing: raw[nameStart..<(nameStart + nameLength)])
            let name = String(decoding: nameBytes, as: UTF8.self)
            // a field too big for 32 bits says 0xFFFFFFFF and puts the real
            // value in the zip64 extra field, in this order
            let extraStart = nameStart + nameLength
            if uncompressed == 0xFFFF_FFFF || compressed == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF,
               let wide = zip64Extra(raw, from: extraStart, length: extraLength) {
                var next = 0
                if uncompressed == 0xFFFF_FFFF, next < wide.count { uncompressed = wide[next]; next += 1 }
                if compressed == 0xFFFF_FFFF, next < wide.count { compressed = wide[next]; next += 1 }
                if localOffset == 0xFFFF_FFFF, next < wide.count { localOffset = wide[next] }
            }
            offset = nameStart + nameLength + extraLength + commentLength

            // The local header's own name and extra-field lengths are read
            // rather than the central directory's: the two disagree in real
            // archives, and trusting the wrong one lands the read a few bytes
            // into the middle of the data.
            guard localOffset + 30 <= raw.count,
                  read32(raw, localOffset) == 0x0403_4b50 else { continue }
            let dataStart = localOffset + 30 + Int(read16(raw, localOffset + 26))
                + Int(read16(raw, localOffset + 28))
            guard dataStart + compressed <= raw.count else { continue }
            entries.append(Entry(name: name, method: method, compressed: compressed,
                                 uncompressed: uncompressed, localOffset: localOffset,
                                 dataStart: dataStart))
        }
        return withoutOverlaps(entries)
    }

    /// Entries that share bytes with another are never how a document is
    /// written; they are how a zip bomb makes thousands of files out of one
    /// stream. The first entry in the file keeps its bytes, and any entry
    /// reaching back into them is dropped.
    static func withoutOverlaps(_ entries: [Entry]) -> [Entry] {
        let order = entries.indices.sorted { a, b in
            let left = entries[a].localOffset, right = entries[b].localOffset
            return left == right ? a < b : left < right
        }
        var keep = [Bool](repeating: false, count: entries.count)
        var reached = 0
        for index in order where entries[index].localOffset >= reached {
            keep[index] = true
            reached = entries[index].dataEnd
        }
        return entries.indices.filter { keep[$0] }.map { entries[$0] }
    }

    /// The 64-bit values in an entry's zip64 extra field (header 0x0001).
    private static func zip64Extra(_ raw: UnsafeRawBufferPointer, from start: Int, length: Int) -> [Int]? {
        var at = start
        let end = min(start + length, raw.count)
        while at + 4 <= end {
            let id = read16(raw, at)
            let size = Int(read16(raw, at + 2))
            let body = at + 4
            if id == 0x0001 {
                var values: [Int] = []
                var i = body
                while i + 8 <= min(body + size, end) {
                    let value = read64(raw, i)
                    guard value <= UInt64(Int.max) else { return nil }
                    values.append(Int(value))
                    i += 8
                }
                return values
            }
            at = body + size
        }
        return nil
    }

    /// Where the central directory starts, and how many entries it lists.
    ///
    /// The record sits at the very end of the file, unless the archive carries
    /// a comment, so it is searched for backwards - over the comment's maximum
    /// length and no further.
    private static func endOfCentralDirectory(_ raw: UnsafeRawBufferPointer) -> (start: Int, count: Int)? {
        guard raw.count >= 22 else { return nil }
        let lowest = max(0, raw.count - 22 - 65_535)
        var offset = raw.count - 22
        while offset >= lowest {
            if read32(raw, offset) == 0x0605_4b50 {
                let start = Int(read32(raw, offset + 16))
                let count = Int(read16(raw, offset + 10))
                // zip64: a locator just before this record points at the
                // zip64 end record, which holds the real count and start
                if start == 0xFFFF_FFFF || count == 0xFFFF, offset >= 20,
                   read32(raw, offset - 20) == 0x0706_4b50 {
                    let record = read64(raw, offset - 12)
                    if raw.count >= 56, record <= UInt64(raw.count - 56), read32(raw, Int(record)) == 0x0606_4b50 {
                        let wideCount = read64(raw, Int(record) + 32)
                        let wideStart = read64(raw, Int(record) + 48)
                        if wideCount <= UInt64(raw.count), wideStart <= UInt64(raw.count) {
                            return (Int(wideStart), Int(wideCount))
                        }
                    }
                }
                return (start, count)
            }
            offset -= 1
        }
        return nil
    }

    private static func read16(_ raw: UnsafeRawBufferPointer, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= raw.count else { return 0 }
        return UInt16(raw[offset]) | UInt16(raw[offset + 1]) << 8
    }

    private static func read64(_ raw: UnsafeRawBufferPointer, _ offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= raw.count else { return 0 }
        let low = UInt64(read32(raw, offset))
        let high = UInt64(read32(raw, offset + 4))
        return low | high << 32
    }

    private static func read32(_ raw: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= raw.count else { return 0 }
        let low = UInt32(raw[offset]) | UInt32(raw[offset + 1]) << 8
        let high = UInt32(raw[offset + 2]) << 16 | UInt32(raw[offset + 3]) << 24
        return low | high
    }
}
