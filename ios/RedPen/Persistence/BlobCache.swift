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
        // Not in the phone's backup: every picture here is also inside the
        // library's own file and on the server, so backing it up again only
        // fills the student's iCloud with a second copy.
        var folder = self.directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    /// Where a blob lives - only for a real blob name. A name is used as a
    /// file name, so one that is not a hash (`../../Documents/...`, from a
    /// crafted file) must never get as far as the file system.
    private func url(_ name: String) -> URL? {
        guard BlobRefs.isName(name) else { return nil }
        return directory.appendingPathComponent(name)
    }

    func has(_ name: String) -> Bool {
        guard let file = url(name) else { return false }
        return FileManager.default.fileExists(atPath: file.path)
    }

    func data(_ name: String) -> Data? {
        guard let file = url(name) else { return nil }
        return try? Data(contentsOf: file)
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
        guard !has(name), let file = url(name) else { return name }
        try? data.write(to: file, options: .atomic)
        return name
    }

    /// Everything on hand, so a sync can ask only for what is genuinely new.
    func names() -> Set<String> {
        let found = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        return Set((found ?? []).filter(BlobRefs.isName))
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
            guard let file = url(name) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
