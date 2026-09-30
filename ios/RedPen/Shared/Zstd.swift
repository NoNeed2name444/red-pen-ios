import Foundation

/// Reading Zstandard (RFC 8878) - decompression only.
///
/// Anki 2.1.50 and later write their packages with zstd: the collection is
/// `collection.anki21b`, the media list and every picture inside the package
/// are zstd frames too, and "Support older Anki versions" is off by default.
/// A deck a classmate exports today - AnKing included - is almost always one
/// of these. Apple's Compression framework has no zstd, so this is the
/// decoder, written from the RFC: frames, raw / RLE / compressed blocks,
/// Huffman literals (one or four streams), FSE sequences with the predefined,
/// RLE, compressed and repeat modes, and the three repeat offsets.
///
/// Not handled: dictionaries (Anki never uses one) - a frame that names one
/// is refused. The content checksum is skipped rather than verified.
///
/// Everything a frame says about itself is a claim: output is capped by
/// `limit`, table descriptions are range-checked, and a malformed stream
/// ends in `Zstd.Failure` rather than a crash.
///
/// Foundation only, so it is tested on the runner against frames written by
/// the reference implementation.
enum Zstd {

    enum Failure: Error, Equatable {
        case notZstd, corrupt, dictionary, tooLarge, unwritable
    }

    static let magic: UInt32 = 0xFD2F_B528

    /// Whether some bytes start with a zstd frame.
    static func isZstd(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let b = [UInt8](data.prefix(4))
        let word: UInt32 = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        return word == magic
    }

    /// Every frame in `data`, decompressed into memory. `limit` caps the output.
    static func decompress(_ data: Data, limit: Int = 512 << 20) throws -> Data {
        var collected = Data()
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var decoder = Decoder(input: raw, limit: limit)
            try decoder.run { piece in collected.append(contentsOf: piece) }
        }
        return collected
    }

    /// Every frame in `data`, written to `url` as it is produced, so a
    /// collection of hundreds of megabytes never sits in memory whole - only
    /// the window the format needs to look back into.
    static func decompress(_ data: Data, to url: URL, limit: Int = 4 << 30) throws {
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw Failure.unwritable }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var failed = false
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var decoder = Decoder(input: raw, limit: limit)
            try decoder.run { piece in
                do { try handle.write(contentsOf: Data(piece)) } catch { failed = true }
            }
        }
        if failed { throw Failure.unwritable }
    }

    // MARK: - the decoder

    fileprivate struct Decoder {
        let input: UnsafeRawBufferPointer
        let limit: Int
        var pos = 0
        var produced = 0

        /// The output not yet handed to the sink, which is also the window
        /// matches copy from.
        var out: [UInt8] = []
        var window = 1 << 20

        // state carried between blocks of one frame
        var rep: [Int] = [1, 4, 8]
        var huffman: HuffmanTable?
        var llTable: FSETable?
        var ofTable: FSETable?
        var mlTable: FSETable?

        init(input: UnsafeRawBufferPointer, limit: Int) {
            self.input = input
            self.limit = limit
        }

        mutating func run(_ sink: ([UInt8]) -> Void) throws {
            var frames = 0
            while pos + 4 <= input.count {
                let word: UInt32 = read32(pos)
                if word & 0xFFFF_FFF0 == 0x184D_2A50 {
                    // a skippable frame: its size, then that many bytes
                    guard pos + 8 <= input.count else { throw Failure.corrupt }
                    let size = Int(read32(pos + 4))
                    pos += 8 + size
                    continue
                }
                guard word == Zstd.magic else {
                    if frames == 0 { throw Failure.notZstd }
                    break
                }
                pos += 4
                try frame(sink)
                frames += 1
            }
            if frames == 0 { throw Failure.notZstd }
            if !out.isEmpty { sink(out); out.removeAll() }
        }

        // MARK: frame and blocks

        mutating func frame(_ sink: ([UInt8]) -> Void) throws {
            let descriptor = try byte()
            let fcsFlag = Int(descriptor >> 6)
            let single = descriptor & 0x20 != 0
            let checksum = descriptor & 0x04 != 0
            let dictFlag = Int(descriptor & 0x03)
            if descriptor & 0x08 != 0 { throw Failure.corrupt }
            var windowSize = 0
            if !single {
                let wd = Int(try byte())
                let exponent: Int = wd >> 3
                let mantissa: Int = wd & 7
                let log: Int = 10 + exponent
                guard log <= 41 else { throw Failure.corrupt }
                let base: Int = 1 << log
                windowSize = base + (base / 8) * mantissa
            }
            let dictBytes: [Int] = [0, 1, 2, 4]
            var dictID = 0
            for i in 0..<dictBytes[dictFlag] { dictID |= Int(try byte()) << (8 * i) }
            if dictID != 0 { throw Failure.dictionary }
            var fcsBytes: Int = [0, 2, 4, 8][fcsFlag]
            if fcsFlag == 0 && single { fcsBytes = 1 }
            var contentSize = 0
            for i in 0..<fcsBytes { contentSize |= Int(try byte()) << (8 * i) }
            if fcsBytes == 2 { contentSize += 256 }
            if single { windowSize = contentSize }
            window = max(windowSize, 1 << 10)
            // a frame starts from scratch
            rep = [1, 4, 8]
            huffman = nil
            llTable = nil
            ofTable = nil
            mlTable = nil

            var last = false
            while !last {
                guard pos + 3 <= input.count else { throw Failure.corrupt }
                let header: Int = Int(input[pos]) | Int(input[pos + 1]) << 8 | Int(input[pos + 2]) << 16
                pos += 3
                last = header & 1 != 0
                let type: Int = (header >> 1) & 3
                let size: Int = header >> 3
                switch type {
                case 0:
                    guard pos + size <= input.count else { throw Failure.corrupt }
                    try grow(size)
                    out.append(contentsOf: UnsafeRawBufferPointer(rebasing: input[pos..<(pos + size)]))
                    pos += size
                case 1:
                    guard pos < input.count else { throw Failure.corrupt }
                    try grow(size)
                    out.append(contentsOf: repeatElement(input[pos], count: size))
                    pos += 1
                case 2:
                    guard pos + size <= input.count, size <= 1 << 17 else { throw Failure.corrupt }
                    let blockEnd: Int = pos + size
                    try compressedBlock(end: blockEnd)
                    pos = blockEnd
                default:
                    throw Failure.corrupt
                }
                flushIfNeeded(sink)
            }
            if checksum { pos += 4 }
        }

        mutating func flushIfNeeded(_ sink: ([UInt8]) -> Void) {
            let keep: Int = window
            guard out.count > keep + (4 << 20) else { return }
            let cut: Int = out.count - keep
            sink(Array(out[0..<cut]))
            out.removeFirst(cut)
        }

        mutating func grow(_ count: Int) throws {
            produced += count
            if produced > limit { throw Failure.tooLarge }
        }

        // MARK: one compressed block

        mutating func compressedBlock(end: Int) throws {
            let literals = try literalsSection(end: end)
            try sequencesSection(literals: literals, end: end)
        }

        mutating func literalsSection(end: Int) throws -> [UInt8] {
            let b0 = Int(try byte())
            let type: Int = b0 & 3
            let format: Int = (b0 >> 2) & 3
            if type == 0 || type == 1 {
                var size = 0
                switch format {
                case 0, 2: size = b0 >> 3
                case 1:
                    let b1 = Int(try byte())
                    size = (b0 >> 4) + (b1 << 4)
                default:
                    let b1 = Int(try byte())
                    let b2 = Int(try byte())
                    size = (b0 >> 4) + (b1 << 4) + (b2 << 12)
                }
                if type == 0 {
                    guard pos + size <= end else { throw Failure.corrupt }
                    let bytes = [UInt8](UnsafeRawBufferPointer(rebasing: input[pos..<(pos + size)]))
                    pos += size
                    return bytes
                }
                guard pos < end else { throw Failure.corrupt }
                let value = input[pos]
                pos += 1
                return [UInt8](repeating: value, count: size)
            }
            // Huffman-coded: the sizes, then (for type 2) the tree, then streams
            var headerBytes = 3
            var bits = 10
            var streams = 4
            switch format {
            case 0: streams = 1
            case 1: break
            case 2: headerBytes = 4; bits = 14
            default: headerBytes = 5; bits = 18
            }
            var h: Int = b0
            for i in 1..<headerBytes { h |= Int(try byte()) << (8 * i) }
            let mask: Int = (1 << bits) - 1
            let regenerated: Int = (h >> 4) & mask
            let compressed: Int = (h >> (4 + bits)) & mask
            let start: Int = pos
            let stop: Int = start + compressed
            guard stop <= end, regenerated <= 1 << 17 else { throw Failure.corrupt }
            if type == 2 {
                huffman = try readHuffmanTable(end: stop)
            }
            guard let table = huffman else { throw Failure.corrupt }
            var result = [UInt8](repeating: 0, count: regenerated)
            if streams == 1 {
                try decodeHuffmanStream(table, from: pos, to: stop, into: &result, at: 0, count: regenerated)
            } else {
                guard pos + 6 <= stop else { throw Failure.corrupt }
                let s1 = Int(read16(pos))
                let s2 = Int(read16(pos + 2))
                let s3 = Int(read16(pos + 4))
                let first: Int = pos + 6
                let s4: Int = stop - first - s1 - s2 - s3
                guard s4 >= 0 else { throw Failure.corrupt }
                let quarter: Int = (regenerated + 3) / 4
                guard quarter * 3 <= regenerated else { throw Failure.corrupt }
                var at = first
                let sizes: [Int] = [s1, s2, s3, s4]
                for index in 0..<4 {
                    let count: Int = index < 3 ? quarter : regenerated - quarter * 3
                    try decodeHuffmanStream(table, from: at, to: at + sizes[index],
                                            into: &result, at: quarter * index, count: count)
                    at += sizes[index]
                }
            }
            pos = stop
            return result
        }

        // MARK: Huffman

        mutating func readHuffmanTable(end: Int) throws -> HuffmanTable {
            let header = Int(try byte())
            var weights: [Int] = []
            if header < 128 {
                // FSE-compressed weights, in `header` bytes
                let stop: Int = pos + header
                guard stop <= end, header > 0 else { throw Failure.corrupt }
                var forward = ForwardBits(input: input, start: pos, end: stop)
                let table = try FSETable.read(&forward, maxLog: 6, maxSymbol: 255)
                let streamStart: Int = forward.alignedByte()
                guard streamStart < stop else { throw Failure.corrupt }
                var bits = try BackwardBits(input: input, start: streamStart, end: stop)
                var state1 = bits.read(table.log)
                var state2 = bits.read(table.log)
                while weights.count < 255 {
                    weights.append(Int(table.symbol[state1]))
                    state1 = table.next(state1, &bits)
                    if bits.overflowed { weights.append(Int(table.symbol[state2])); break }
                    weights.append(Int(table.symbol[state2]))
                    state2 = table.next(state2, &bits)
                    if bits.overflowed { weights.append(Int(table.symbol[state1])); break }
                }
                pos = stop
            } else {
                let count: Int = header - 127
                let bytes: Int = (count + 1) / 2
                guard pos + bytes <= end else { throw Failure.corrupt }
                for i in 0..<count {
                    let b = Int(input[pos + i / 2])
                    weights.append(i % 2 == 0 ? b >> 4 : b & 15)
                }
                pos += bytes
            }
            return try HuffmanTable(weights: weights)
        }

        func decodeHuffmanStream(_ table: HuffmanTable, from start: Int, to stop: Int,
                                 into result: inout [UInt8], at offset: Int, count: Int) throws {
            guard count > 0 else { return }
            guard start < stop, stop <= input.count, offset + count <= result.count else { throw Failure.corrupt }
            var bits = try BackwardBits(input: input, start: start, end: stop)
            let maxBits: Int = table.maxBits
            for i in 0..<count {
                let index = Int(bits.peek(maxBits))
                bits.skip(Int(table.bits[index]))
                result[offset + i] = table.symbol[index]
            }
            if bits.position < -maxBits { throw Failure.corrupt }
        }

        // MARK: sequences

        mutating func sequencesSection(literals: [UInt8], end: Int) throws {
            guard pos < end else {
                try grow(literals.count)
                out.append(contentsOf: literals)
                return
            }
            let b0 = Int(try byte())
            var count = 0
            if b0 == 0 {
                try grow(literals.count)
                out.append(contentsOf: literals)
                return
            } else if b0 < 128 {
                count = b0
            } else if b0 < 255 {
                count = ((b0 - 128) << 8) + Int(try byte())
            } else {
                let lo = Int(try byte())
                let hi = Int(try byte())
                count = lo + (hi << 8) + 0x7F00
            }
            let modes = Int(try byte())
            if modes & 3 != 0 { throw Failure.corrupt }
            llTable = try table(mode: (modes >> 6) & 3, kind: .literalLength, previous: llTable, end: end)
            ofTable = try table(mode: (modes >> 4) & 3, kind: .offset, previous: ofTable, end: end)
            mlTable = try table(mode: (modes >> 2) & 3, kind: .matchLength, previous: mlTable, end: end)
            guard let ll = llTable, let of = ofTable, let ml = mlTable else { throw Failure.corrupt }

            var bits = try BackwardBits(input: input, start: pos, end: end)
            var llState = bits.read(ll.log)
            var ofState = bits.read(of.log)
            var mlState = bits.read(ml.log)
            var lit = 0
            for index in 0..<count {
                let ofCode = Int(of.symbol[ofState])
                let llCode = Int(ll.symbol[llState])
                let mlCode = Int(ml.symbol[mlState])
                guard ofCode <= 31, llCode <= 35, mlCode <= 52 else { throw Failure.corrupt }
                let ofExtra = Int(bits.read(ofCode))
                let offsetValue: Int = (1 << ofCode) + ofExtra
                let matchLength: Int = Zstd.mlBase[mlCode] + Int(bits.read(Zstd.mlBits[mlCode]))
                let literalLength: Int = Zstd.llBase[llCode] + Int(bits.read(Zstd.llBits[llCode]))
                if index + 1 < count {
                    llState = ll.next(llState, &bits)
                    mlState = ml.next(mlState, &bits)
                    ofState = of.next(ofState, &bits)
                }
                let offset: Int = resolve(offsetValue, literalLength: literalLength)
                // the literals, then the match
                guard lit + literalLength <= literals.count else { throw Failure.corrupt }
                try grow(literalLength + matchLength)
                if literalLength > 0 {
                    out.append(contentsOf: literals[lit..<(lit + literalLength)])
                    lit += literalLength
                }
                try copyMatch(offset: offset, length: matchLength)
            }
            if lit < literals.count {
                try grow(literals.count - lit)
                out.append(contentsOf: literals[lit...])
            }
        }

        /// The offset a sequence means, and the three repeat offsets moved on.
        mutating func resolve(_ value: Int, literalLength: Int) -> Int {
            if value > 3 {
                let offset: Int = value - 3
                rep[2] = rep[1]
                rep[1] = rep[0]
                rep[0] = offset
                return offset
            }
            var index: Int = value - 1
            if literalLength == 0 { index += 1 }
            if index == 0 { return rep[0] }
            let offset: Int = index == 3 ? rep[0] - 1 : rep[index]
            if index > 1 { rep[2] = rep[1] }
            rep[1] = rep[0]
            rep[0] = offset
            return offset
        }

        mutating func copyMatch(offset: Int, length: Int) throws {
            guard length > 0 else { return }
            guard offset > 0, offset <= out.count else { throw Failure.corrupt }
            let start: Int = out.count - offset
            let at: Int = out.count
            // grown first and filled through a pointer: appending a slice of
            // the array to itself copies the whole array, every match
            out.append(contentsOf: repeatElement(0, count: length))
            out.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<UInt8>) in
                guard let base = p.baseAddress else { return }
                if offset >= length {
                    (base + at).update(from: base + start, count: length)
                } else {
                    // overlapping: byte by byte, so a short offset repeats
                    for i in 0..<length { base[at + i] = base[start + i] }
                }
            }
        }

        enum Kind { case literalLength, offset, matchLength }

        mutating func table(mode: Int, kind: Kind, previous: FSETable?, end: Int) throws -> FSETable {
            switch mode {
            case 0:
                switch kind {
                case .literalLength: return Zstd.predefinedLL
                case .offset: return Zstd.predefinedOF
                case .matchLength: return Zstd.predefinedML
                }
            case 1:
                guard pos < end else { throw Failure.corrupt }
                let symbol = input[pos]
                pos += 1
                return FSETable(rle: symbol)
            case 2:
                let maxLog: Int = kind == .offset ? 8 : 9
                let maxSymbol: Int = kind == .literalLength ? 35 : (kind == .offset ? 31 : 52)
                var forward = ForwardBits(input: input, start: pos, end: end)
                let table = try FSETable.read(&forward, maxLog: maxLog, maxSymbol: maxSymbol)
                pos = forward.alignedByte()
                return table
            default:
                guard let previous else { throw Failure.corrupt }
                return previous
            }
        }

        // MARK: bytes

        mutating func byte() throws -> UInt8 {
            guard pos < input.count else { throw Failure.corrupt }
            let b = input[pos]
            pos += 1
            return b
        }

        func read16(_ at: Int) -> UInt16 {
            guard at + 2 <= input.count else { return 0 }
            return UInt16(input[at]) | UInt16(input[at + 1]) << 8
        }

        func read32(_ at: Int) -> UInt32 {
            guard at + 4 <= input.count else { return 0 }
            let lo: UInt32 = UInt32(input[at]) | UInt32(input[at + 1]) << 8
            let hi: UInt32 = UInt32(input[at + 2]) << 16 | UInt32(input[at + 3]) << 24
            return lo | hi
        }
    }

    // MARK: - bit readers

    /// Little-endian bits read from the front: FSE table descriptions.
    fileprivate struct ForwardBits {
        let input: UnsafeRawBufferPointer
        let start: Int
        let end: Int
        var bit = 0

        init(input: UnsafeRawBufferPointer, start: Int, end: Int) {
            self.input = input
            self.start = start
            self.end = end
        }

        func peek(_ count: Int) -> Int {
            var value = 0
            var got = 0
            var at: Int = bit
            while got < count {
                let byteIndex: Int = start + at / 8
                let b: Int = byteIndex < end ? Int(input[byteIndex]) : 0
                let shift: Int = at % 8
                let take: Int = min(8 - shift, count - got)
                let piece: Int = (b >> shift) & ((1 << take) - 1)
                value |= piece << got
                got += take
                at += take
            }
            return value
        }

        mutating func skip(_ count: Int) { bit += count }

        mutating func read(_ count: Int) -> Int {
            let value = peek(count)
            bit += count
            return value
        }

        var overran: Bool { start + (bit + 7) / 8 > end }

        func alignedByte() -> Int { start + (bit + 7) / 8 }
    }

    /// Bits read from the back: Huffman streams and FSE sequences. The last
    /// byte's highest set bit marks where the stream begins; bits past the
    /// front read as zero, and `overflowed` says it happened.
    fileprivate struct BackwardBits {
        let input: UnsafeRawBufferPointer
        let start: Int
        /// Bits still unread, counted from the first byte; may go negative.
        var position: Int

        init(input: UnsafeRawBufferPointer, start: Int, end: Int) throws {
            guard end > start, end <= input.count else { throw Failure.corrupt }
            let last = input[end - 1]
            guard last != 0 else { throw Failure.corrupt }
            var high = 7
            while (last >> UInt8(high)) & 1 == 0 { high -= 1 }
            self.input = input
            self.start = start
            position = (end - start - 1) * 8 + high
        }

        var overflowed: Bool { position < 0 }

        /// The `count` bits below the current position, first-read highest.
        func peek(_ count: Int) -> UInt64 {
            guard count > 0 else { return 0 }
            let low: Int = position - count
            if low >= 0 {
                return window(at: low) & ((1 << UInt64(count)) - 1)
            }
            // past the front: what is left, shifted up, zeros below
            guard position > 0 else { return 0 }
            let have: UInt64 = window(at: 0) & ((1 << UInt64(position)) - 1)
            return have << UInt64(-low)
        }

        /// 57 or more bits starting at bit `at`.
        private func window(at bitIndex: Int) -> UInt64 {
            let first: Int = start + bitIndex / 8
            var value: UInt64 = 0
            var i = 0
            let available: Int = input.count - first
            let n: Int = min(8, available)
            while i < n {
                value |= UInt64(input[first + i]) << UInt64(8 * i)
                i += 1
            }
            return value >> UInt64(bitIndex % 8)
        }

        mutating func skip(_ count: Int) { position -= count }

        mutating func read(_ count: Int) -> Int {
            guard count > 0 else { return 0 }
            let value = peek(count)
            position -= count
            return Int(value)
        }
    }

    // MARK: - tables

    fileprivate struct HuffmanTable {
        var maxBits: Int
        var symbol: [UInt8]
        var bits: [UInt8]

        init(weights given: [Int]) throws {
            guard !given.isEmpty, given.count < 256 else { throw Failure.corrupt }
            var total = 0
            for w in given {
                guard w <= 11 else { throw Failure.corrupt }
                if w > 0 { total += 1 << (w - 1) }
            }
            guard total > 0 else { throw Failure.corrupt }
            var high = 0
            while (1 << (high + 1)) <= total { high += 1 }
            let maxBits: Int = high + 1
            let left: Int = (1 << maxBits) - total
            // what is left must be a power of two: the implied last weight
            guard left > 0, left & (left - 1) == 0, maxBits <= 11 else { throw Failure.corrupt }
            var lastWeight = 1
            while (1 << (lastWeight - 1)) < left { lastWeight += 1 }
            var weights = given
            weights.append(lastWeight)
            let size: Int = 1 << maxBits
            var symbol = [UInt8](repeating: 0, count: size)
            var bits = [UInt8](repeating: 0, count: size)
            var next = 0
            for w in 1...maxBits {
                for (s, weight) in weights.enumerated() where weight == w {
                    let span: Int = 1 << (w - 1)
                    let length = UInt8(maxBits + 1 - w)
                    guard next + span <= size else { throw Failure.corrupt }
                    for i in next..<(next + span) {
                        symbol[i] = UInt8(s)
                        bits[i] = length
                    }
                    next += span
                }
            }
            guard next == size else { throw Failure.corrupt }
            self.maxBits = maxBits
            self.symbol = symbol
            self.bits = bits
        }
    }

    fileprivate struct FSETable {
        var log: Int
        var symbol: [UInt8]
        var bits: [UInt8]
        var base: [Int]

        init(rle value: UInt8) {
            log = 0
            symbol = [value]
            bits = [0]
            base = [0]
        }

        init(counts: [Int], log: Int) throws {
            let size: Int = 1 << log
            var symbol = [UInt8](repeating: 0, count: size)
            var next = [Int](repeating: 0, count: counts.count)
            var high: Int = size - 1
            for (s, count) in counts.enumerated() where count == -1 {
                guard high >= 0 else { throw Failure.corrupt }
                symbol[high] = UInt8(s)
                high -= 1
                next[s] = 1
            }
            let step: Int = (size >> 1) + (size >> 3) + 3
            let mask: Int = size - 1
            var position = 0
            for (s, count) in counts.enumerated() where count > 0 {
                next[s] = count
                for _ in 0..<count {
                    symbol[position] = UInt8(s)
                    repeat { position = (position + step) & mask } while position > high
                }
            }
            guard position == 0 else { throw Failure.corrupt }
            var bits = [UInt8](repeating: 0, count: size)
            var base = [Int](repeating: 0, count: size)
            for u in 0..<size {
                let s = Int(symbol[u])
                let state: Int = next[s]
                next[s] += 1
                guard state > 0 else { throw Failure.corrupt }
                var highBit = 0
                while (1 << (highBit + 1)) <= state { highBit += 1 }
                let nb: Int = log - highBit
                bits[u] = UInt8(nb)
                base[u] = (state << nb) - size
            }
            self.log = log
            self.symbol = symbol
            self.bits = bits
            self.base = base
        }

        func next(_ state: Int, _ stream: inout BackwardBits) -> Int {
            base[state] + stream.read(Int(bits[state]))
        }

        /// A table description (RFC 8878 4.1.1), read from the front.
        static func read(_ bits: inout ForwardBits, maxLog: Int, maxSymbol: Int) throws -> FSETable {
            let log: Int = bits.read(4) + 5
            guard log <= maxLog else { throw Failure.corrupt }
            var remaining: Int = (1 << log) + 1
            var threshold: Int = 1 << log
            var nbBits: Int = log + 1
            var counts: [Int] = []
            while remaining > 1 {
                guard counts.count <= maxSymbol else { throw Failure.corrupt }
                let maxValue: Int = (2 * threshold - 1) - remaining
                let low: Int = bits.peek(nbBits - 1)
                var count = 0
                if low < maxValue {
                    count = low
                    bits.skip(nbBits - 1)
                } else {
                    count = bits.peek(nbBits)
                    if count >= threshold { count -= maxValue }
                    bits.skip(nbBits)
                }
                count -= 1
                remaining -= count < 0 ? -count : count
                counts.append(count)
                if count == 0 {
                    while true {
                        let repeatFlag: Int = bits.read(2)
                        for _ in 0..<repeatFlag { counts.append(0) }
                        if repeatFlag != 3 { break }
                    }
                }
                while remaining < threshold && threshold > 1 {
                    nbBits -= 1
                    threshold >>= 1
                }
                if bits.overran { throw Failure.corrupt }
            }
            guard remaining == 1, counts.count <= maxSymbol + 1 else { throw Failure.corrupt }
            return try FSETable(counts: counts, log: log)
        }
    }

    // MARK: - the format's constants

    fileprivate static let llBase: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
                                            16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512,
                                            1024, 2048, 4096, 8192, 16384, 32768, 65536]
    fileprivate static let llBits: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                            1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12,
                                            13, 14, 15, 16]
    fileprivate static let mlBase: [Int] = (0..<32).map { $0 + 3 } + [35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99,
                                                                     131, 259, 515, 1027, 2051, 4099, 8195,
                                                                     16387, 32771, 65539]
    fileprivate static let mlBits: [Int] = [Int](repeating: 0, count: 32) + [1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5,
                                                                           7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

    /// A symbol that is "less than one": it gets one cell at the top of the table.
    fileprivate static let lessThanOne: Int = -1

    fileprivate static let predefinedLL: FSETable = {
        var counts: [Int] = [4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2,
                             2, 3, 2, 1, 1, 1, 1, 1]
        counts += [Int](repeating: lessThanOne, count: 4)
        return (try? FSETable(counts: counts, log: 6)) ?? FSETable(rle: 0)
    }()
    fileprivate static let predefinedML: FSETable = {
        var counts: [Int] = [1, 4, 3, 2, 2, 2, 2, 2, 2]
        counts += [Int](repeating: 1, count: 37)
        counts += [Int](repeating: lessThanOne, count: 7)
        return (try? FSETable(counts: counts, log: 6)) ?? FSETable(rle: 0)
    }()
    fileprivate static let predefinedOF: FSETable = {
        var counts: [Int] = [1, 1, 1, 1, 1, 1, 2, 2, 2]
        counts += [Int](repeating: 1, count: 15)
        counts += [Int](repeating: lessThanOne, count: 5)
        return (try? FSETable(counts: counts, log: 5)) ?? FSETable(rle: 0)
    }()
}
