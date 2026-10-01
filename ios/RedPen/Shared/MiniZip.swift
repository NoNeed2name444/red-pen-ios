import Foundation

/// The smallest possible ZIP writer: STORE (no compression), CRC-32, local
/// headers and a central directory. Anki only needs a valid archive, and the
/// SQLite file and the JPEGs compress poorly anyway.
///
/// It writes from files to a file, a piece at a time. The Anki exporter used to
/// hold every picture in memory, then copy all of them again into one archive
/// in memory before writing it - a deck of diagrams cost twice its own size in
/// RAM at the moment it was most likely to be killed for it.
///
/// Foundation only, so it is tested.
enum MiniZip {

    enum Failure: LocalizedError {
        case tooMany, tooLarge, unwritable
        var errorDescription: String? {
            switch self {
            case .tooMany: return "That deck has more pictures than one Anki file can hold."
            case .tooLarge: return "That deck is too large for one Anki file."
            case .unwritable: return "The file could not be written."
            }
        }
    }

    /// Writes `files` - each a name inside the archive and a file on disk -
    /// as one zip at `url`, replacing anything there.
    static func write(files: [(name: String, file: URL)], to url: URL) throws {
        // a plain zip counts entries in 16 bits and offsets in 32; past
        // either it would need zip64, which Anki does not need and this
        // does not write
        guard files.count <= 0xFFFF else { throw Failure.tooMany }
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw Failure.unwritable }
        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }

        var central = Data()
        var offset: UInt64 = 0
        for (name, file) in files {
            let nameBytes = Array(name.utf8)
            let sum = try checksum(of: file)
            guard offset <= UInt64(UInt32.max), sum.size <= UInt64(UInt32.max) else { throw Failure.tooLarge }
            let size = UInt32(sum.size)

            var local = Data()
            local.append(le32(0x0403_4b50)); local.append(le16(20)); local.append(le16(0)); local.append(le16(0))
            local.append(le16(0)); local.append(le16(0x21)) // time/date: fixed
            local.append(le32(sum.crc)); local.append(le32(size)); local.append(le32(size))
            local.append(le16(UInt16(nameBytes.count))); local.append(le16(0))
            local.append(contentsOf: nameBytes)
            try out.write(contentsOf: local)
            try copy(file, into: out)

            central.append(le32(0x0201_4b50)); central.append(le16(20)); central.append(le16(20))
            central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0x21))
            central.append(le32(sum.crc)); central.append(le32(size)); central.append(le32(size))
            central.append(le16(UInt16(nameBytes.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0))
            central.append(le32(UInt32(offset)))
            central.append(contentsOf: nameBytes)

            offset += UInt64(local.count) + sum.size
        }
        guard offset <= UInt64(UInt32.max) else { throw Failure.tooLarge }
        try out.write(contentsOf: central)
        var end = Data()
        end.append(le32(0x0605_4b50)); end.append(le16(0)); end.append(le16(0))
        end.append(le16(UInt16(files.count))); end.append(le16(UInt16(files.count)))
        end.append(le32(UInt32(central.count))); end.append(le32(UInt32(offset))); end.append(le16(0))
        try out.write(contentsOf: end)
    }

    /// Pieces this size are read and written at a time.
    private static let chunk = 1 << 20

    private static func checksum(of file: URL) throws -> (crc: UInt32, size: UInt64) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var running: UInt32 = 0xFFFF_FFFF
        var size: UInt64 = 0
        while let piece = try handle.read(upToCount: chunk), !piece.isEmpty {
            running = update(running, piece)
            size += UInt64(piece.count)
        }
        return (running ^ 0xFFFF_FFFF, size)
    }

    private static func copy(_ file: URL, into out: FileHandle) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        while let piece = try handle.read(upToCount: chunk), !piece.isEmpty {
            try out.write(contentsOf: piece)
        }
    }

    /// CRC-32 of some bytes, as a zip records it.
    static func crc32(_ data: Data) -> UInt32 {
        update(0xFFFF_FFFF, data) ^ 0xFFFF_FFFF
    }

    private static func update(_ crc: UInt32, _ data: Data) -> UInt32 {
        var c = crc
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for byte in raw { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        }
        return c
    }

    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}
