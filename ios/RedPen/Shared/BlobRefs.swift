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
    static func hash(fromRef ref: String) -> String? {
        guard isRef(ref) else { return nil }
        return String(ref.dropFirst(prefix.count))
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
