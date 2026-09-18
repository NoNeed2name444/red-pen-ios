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
/// Zip64 archives - over four gigabytes, or over 65,535 entries - are not
/// handled. A Word document that size is not a lecture handout.
enum Zip {

    /// Every file in the archive, by its path inside it.
    static func entries(in data: Data) -> [String: Data] {
        guard let directory = endOfCentralDirectory(data) else { return [:] }
        var found: [String: Data] = [:]
        var offset = directory.start
        for _ in 0..<directory.count {
            guard offset + 46 <= data.count,
                  read32(data, offset) == 0x0201_4b50 else { break }
            let method = read16(data, offset + 10)
            let compressed = Int(read32(data, offset + 20))
            let uncompressed = Int(read32(data, offset + 24))
            let nameLength = Int(read16(data, offset + 28))
            let extraLength = Int(read16(data, offset + 30))
            let commentLength = Int(read16(data, offset + 32))
            let localOffset = Int(read32(data, offset + 42))
            let nameRange = (offset + 46)..<(offset + 46 + nameLength)
            guard nameRange.upperBound <= data.count else { break }
            let name = String(decoding: data[nameRange], as: UTF8.self)

            if let body = contents(data, at: localOffset, method: method,
                                   compressed: compressed, uncompressed: uncompressed) {
                found[name] = body
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        return found
    }

    /// One entry's bytes, following its local header.
    ///
    /// The local header's own name and extra-field lengths are read rather than
    /// the central directory's: the two disagree in real archives, and trusting
    /// the wrong one lands the read a few bytes into the middle of the data.
    private static func contents(_ data: Data, at offset: Int, method: UInt16,
                                 compressed: Int, uncompressed: Int) -> Data? {
        guard offset + 30 <= data.count, read32(data, offset) == 0x0403_4b50 else { return nil }
        let nameLength = Int(read16(data, offset + 26))
        let extraLength = Int(read16(data, offset + 28))
        let start = offset + 30 + nameLength + extraLength
        guard start + compressed <= data.count, compressed >= 0 else { return nil }
        let body = data.subdata(in: start..<(start + compressed))
        switch method {
        case 0: return body
        case 8: return inflate(body, expecting: uncompressed)
        default: return nil
        }
    }

    /// Raw deflate - which is what COMPRESSION_ZLIB means here, despite the
    /// name: Apple's constant is the algorithm, not the zlib wrapper, and a zip
    /// entry carries no wrapper.
    static func inflate(_ data: Data, expecting size: Int) -> Data? {
        guard !data.isEmpty else { return Data() }
        // an empty or absurd stated size is not trusted; a little headroom
        // costs nothing and a wrong size would truncate the document
        let capacity = max(size, data.count * 8) + 4096
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { destination -> Int in
            guard let dst = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { source -> Int in
                guard let src = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dst, capacity, src, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return out.prefix(written)
    }

    // MARK: the archive's own bookkeeping

    /// Where the central directory starts, and how many entries it lists.
    ///
    /// The record sits at the very end of the file, unless the archive carries
    /// a comment, so it is searched for backwards - over the comment's maximum
    /// length and no further.
    private static func endOfCentralDirectory(_ data: Data) -> (start: Int, count: Int)? {
        guard data.count >= 22 else { return nil }
        let lowest = max(0, data.count - 22 - 65_535)
        var offset = data.count - 22
        while offset >= lowest {
            if read32(data, offset) == 0x0605_4b50 {
                return (Int(read32(data, offset + 16)), Int(read16(data, offset + 10)))
            }
            offset -= 1
        }
        return nil
    }

    private static func read16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count, offset >= 0 else { return 0 }
        let base = data.startIndex + offset
        return UInt16(data[base]) | UInt16(data[base + 1]) << 8
    }

    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count, offset >= 0 else { return 0 }
        let base = data.startIndex + offset
        return UInt32(data[base]) | UInt32(data[base + 1]) << 8
            | UInt32(data[base + 2]) << 16 | UInt32(data[base + 3]) << 24
    }
}
