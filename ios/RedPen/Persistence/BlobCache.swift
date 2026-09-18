import Foundation

/// Slide images, on disk, filed under the hash of their own bytes.
///
/// Two things fall out of content addressing and both matter here. The same
/// diagram appearing in three decks is stored once. And a download that was
/// interrupted and retried cannot corrupt anything, because identical bytes
/// always land in the same place - so writing a blob twice is writing the same
/// file twice.
///
/// Kept out of the library's own JSON on purpose. A set with forty slides in it
/// would otherwise carry tens of megabytes of base64 through every save, and
/// the library is saved after every card rating.
@MainActor
final class BlobCache {
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("RedPenBlobs", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory,
                                                 withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func has(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    func data(_ name: String) -> Data? {
        try? Data(contentsOf: url(name))
    }

    /// Writes a blob under its own hash.
    ///
    /// The name is recomputed rather than trusted. A blob filed under the wrong
    /// hash is a picture that can never be found again and is re-downloaded for
    /// ever, and the cost of checking is one hash of something already in
    /// memory.
    @discardableResult
    func store(_ data: Data) -> String {
        let name = BlobRefs.name(for: data)
        guard !has(name) else { return name }
        try? data.write(to: url(name), options: .atomic)
        return name
    }

    /// Everything on hand, so a sync can ask only for what is genuinely new.
    func names() -> Set<String> {
        let found = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        return Set(found ?? [])
    }

    /// Fills in the images of a set from the cache, leaving any that have not
    /// arrived yet as references.
    func restore(_ set: StudySet) -> StudySet {
        var out = set
        var blobs: [String: Data] = [:]
        for ref in set.images {
            guard let name = BlobRefs.hash(fromRef: ref), let data = data(name) else { continue }
            blobs[name] = data
        }
        out.images = BlobRefs.unpack(set.images, blobs: blobs)
        return out
    }

    /// Drops blobs nothing refers to any more.
    ///
    /// Only ever called with the WHOLE library in hand: a sweep that runs on a
    /// partial view of it deletes pictures that are still in use, and unlike a
    /// stale file, a missing one is visible on a card.
    func sweep(keeping live: Set<String>) {
        for name in names() where !live.contains(name) {
            try? FileManager.default.removeItem(at: url(name))
        }
    }
}
