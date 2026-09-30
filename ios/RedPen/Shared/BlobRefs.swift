import Foundation
import CryptoKit

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
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
