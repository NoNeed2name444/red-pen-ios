import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Keeping slide images out of every sync.
///
/// A set with forty slides in it carries forty JPEGs as base64 inside its own
/// JSON - tens of megabytes. Syncing that document because somebody renamed it
/// would send all of it again, on a phone connection, every time.
///
/// So on the wire an image is a reference to its own SHA-256 and nothing more.
/// The bytes are uploaded once, under that hash, and are never uploaded again
/// by anybody: the same diagram appearing in three decks is one blob, and a
/// device that already has it asks for nothing. Content addressing also makes
/// the upload safely repeatable - the same bytes always land in the same place,
/// so a retry cannot duplicate anything.
///
/// The local model is untouched: a StudySet still holds base64 images, exactly
/// as every screen and exporter expects. The swap happens here, at the edge,
/// which is why nothing else in the app had to learn about any of this.
enum BlobRefs {

    /// What a reference looks like in place of an image.
    static let prefix = "blob:"

    static func isRef(_ image: String) -> Bool { image.hasPrefix(prefix) }

    /// The blob a reference names - only when it really is a name: sixty-four
    /// lower-case hex characters, the way this app and the server write them.
    ///
    /// Anything else is refused rather than trusted. A reference arrives from
    /// shared files and from other devices, and `blob:../../Documents/...`
    /// used as a file name would read the app's own files into a "picture";
    /// sent to the server it is refused, and one refusal used to stop every
    /// picture after it from syncing.
    static func hash(fromRef ref: String) -> String? {
        guard isRef(ref) else { return nil }
        let name = String(ref.dropFirst(prefix.count))
        return isName(name) ? name : nil
    }

    /// Whether a string is a blob's name: a SHA-256 in lower-case hex.
    static func isName(_ name: String) -> Bool {
        name.utf8.count == 64 && name.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// The name a blob is stored under: the hash of its own bytes.
    static func name(for data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return PlainSHA256.hex(data)
        #endif
    }

    /// An image as it is held locally, turned into bytes.
    ///
    /// Images arrive from several places and not all of them agree on whether
    /// to keep the `data:` prefix, so both are accepted.
    static func data(fromStored image: String) -> Data? {
        if let comma = image.firstIndex(of: ","), image.hasPrefix("data:") {
            return Data(base64Encoded: String(image[image.index(after: comma)...]))
        }
        return Data(base64Encoded: image)
    }

    /// Replaces every image in a list with a reference, and hands back the
    /// bytes that now need to exist on the server.
    ///
    /// An image that cannot be decoded is left exactly as it is rather than
    /// dropped: a garbled picture is a bad card, but a missing one is a card
    /// about nothing.
    static func pack(_ images: [String]) -> (refs: [String], blobs: [String: Data]) {
        var refs: [String] = []
        var blobs: [String: Data] = [:]
        for image in images {
            if isRef(image) { refs.append(image); continue }
            guard let data = data(fromStored: image) else {
                refs.append(image)
                continue
            }
            let name = name(for: data)
            blobs[name] = data
            refs.append(prefix + name)
        }
        return (refs, blobs)
    }

    /// Turns references back into images, using blobs already fetched.
    ///
    /// A reference with no blob to go with it stays a reference rather than
    /// becoming an empty string: the card still knows which picture it wants,
    /// so a later sync can fill it in. Silently replacing it with nothing would
    /// make that permanent.
    static func unpack(_ refs: [String], blobs: [String: Data]) -> [String] {
        refs.map { ref in
            guard let name = hash(fromRef: ref) else { return ref }
            guard let data = blobs[name] else { return ref }
            return data.base64EncodedString()
        }
    }

    /// Every blob a list of images stands for, whichever form they are in.
    ///
    /// A set holds its pictures as base64 locally and as references once
    /// packed, and both turn up together - a set half-restored because one
    /// picture has not arrived yet holds some of each. An image's bytes hash to
    /// the same name it would be stored under, so both answer the question.
    static func names(in images: [String]) -> Set<String> {
        var found = Set<String>()
        for image in images {
            if let name = hash(fromRef: image) {
                found.insert(name)
            } else if let data = data(fromStored: image) {
                found.insert(name(for: data))
            }
        }
        return found
    }

    /// Two lists of pictures alike, picture by picture - one filled in from
    /// its reference since (a sync fetching it) is still the same picture.
    static func samePictures(_ a: [String], _ b: [String]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x != y {
            guard let first = picture(x), let second = picture(y), first == second else { return false }
        }
        return true
    }

    /// The blob one image stands for, whichever form it is in.
    private static func picture(_ image: String) -> String? {
        if let ref = hash(fromRef: image) { return ref }
        return data(fromStored: image).map { name(for: $0) }
    }

    /// Every blob named anywhere in some text: a set this version of the app
    /// cannot read is kept as the JSON it was written in, and its pictures must
    /// not be swept away while it waits for a version that can.
    static func names(mentionedIn text: String) -> Set<String> {
        var found = Set<String>()
        var rest = text[...]
        while let hit = rest.range(of: prefix) {
            let after = rest[hit.upperBound...]
            let candidate = String(after.prefix(64))
            if isName(candidate) { found.insert(candidate) }
            rest = after
        }
        return found
    }

    /// Every hash written anywhere in some text - sixty-four lower-case hex
    /// characters with none either side, prefixed or not. For JSON this
    /// version cannot read as a set (a lecture file's hash is a bare string),
    /// whose files must still be kept.
    static func hashes(in text: String) -> Set<String> {
        var found = Set<String>()
        var run: [UInt8] = []
        func close() {
            if run.count == 64, let name = String(bytes: run, encoding: .utf8) { found.insert(name) }
            run.removeAll(keepingCapacity: true)
        }
        for byte in text.utf8 {
            if (48...57).contains(byte) || (97...102).contains(byte) { run.append(byte) } else { close() }
        }
        close()
        return found
    }

    /// Which blobs a set of documents refers to but this device does not have.
    static func missing(_ refs: [String], have: Set<String>) -> [String] {
        var wanted: [String] = []
        for ref in refs {
            guard let name = hash(fromRef: ref), !have.contains(name),
                  !wanted.contains(name) else { continue }
            wanted.append(name)
        }
        return wanted
    }
}

#if !canImport(CryptoKit)
/// SHA-256 (FIPS 180-4) in plain Swift, for where CryptoKit is missing: the
/// Linux test suites, which check the library's pictures by their names. The
/// app itself always has CryptoKit.
enum PlainSHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hex(_ data: Data) -> String {
        digest(data).map { String(format: "%02x", $0) }.joined()
    }

    static func digest(_ data: Data) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                           0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var message = [UInt8](data)
        let bits = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        var w = [UInt32](repeating: 0, count: 64)
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let b = chunk + i * 4
                w[i] = UInt32(message[b]) << 24 | UInt32(message[b + 1]) << 16 | UInt32(message[b + 2]) << 8 | UInt32(message[b + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        return h.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> UInt32(24 - $0 * 8)) } }
    }
}
#endif
