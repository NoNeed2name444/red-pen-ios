import Foundation

/// The library's pictures, kept beside the library file rather than in it.
///
/// A set carries its pictures as base64, and the library file used to as
/// well: tens of megabytes re-encoded and rewritten after every rename and
/// every rating. On disk each picture is now a reference ("blob:<sha256>")
/// to a file in the pictures folder, written once and shared by every set
/// that shows it (audit row 17). In memory nothing changed: a StudySet still
/// holds base64, which is what every screen and exporter reads, so the swap
/// happens only as the file is written (`pack`) and read (`fill`).
///
/// One per Store, used from the write queue and from the read that runs off
/// the main thread, so everything here is behind one lock.
///
/// Foundation only, so it is tested on Linux (the pictures suite).
final class LibraryPictures: @unchecked Sendable {
    let folder: URL
    private let lock = NSLock()
    /// Per set: its images as last packed or filled, and the blob each one
    /// is (nil where it is none, or not known yet). A set unchanged since the
    /// last write shares its strings with this, so finding a picture's name
    /// again costs a comparison of two pointers instead of a hash of
    /// megabytes.
    private var memo: [UUID: (images: [String], names: [String?])] = [:]
    /// Names known to be on disk, so a write does not ask the file system
    /// about every picture every time.
    private var verified: Set<String> = []
    /// What the recovery copies mention, by file name, with the size it was
    /// read at: a copy is hundreds of megabytes and does not change.
    private var copyScans: [String: (size: Int, names: Set<String>)] = [:]
    /// The file holding when the folder was last swept.
    private var sweptFile: URL { folder.appendingPathComponent(".swept") }

    init(folder: URL) {
        self.folder = folder
    }

    /// Where a library file's pictures go. The app's own library (no URL
    /// given) uses the picture cache sync already fills (RedPenBlobs, also
    /// BlobCache's and LibraryBackupRunner's folder), so a picture is on the
    /// device once; any other library (tests, previews) a folder beside it.
    static func folder(forLibrary fileURL: URL?, support: URL) -> URL {
        guard let fileURL else { return support.appendingPathComponent("RedPenBlobs", isDirectory: true) }
        let stem = fileURL.deletingPathExtension().lastPathComponent
        return fileURL.deletingLastPathComponent().appendingPathComponent(stem + "-pictures", isDirectory: true)
    }

    // MARK: writing

    /// One set's images as the library file holds them: every picture whose
    /// blob is on disk (written now if it is not) as a reference.
    ///
    /// Left as it is: a reference already, base64 that does not decode (a
    /// garbled picture is a bad card, a missing one a card about nothing),
    /// and a picture whose blob could not be written - the file then carries
    /// it inline, as before, rather than naming a file that is not there.
    func pack(_ images: [String], of id: UUID) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let before = memo[id]
        var out: [String] = images
        var names = [String?](repeating: nil, count: images.count)
        for (index, image) in images.enumerated() where !BlobRefs.isRef(image) {
            var data: Data?
            var name: String? = before.flatMap { Self.known(image, at: index, in: $0) }
            if name == nil {
                guard let decoded = BlobRefs.data(fromStored: image) else { continue }
                data = decoded
                name = BlobRefs.name(for: decoded)
            }
            guard let name else { continue }
            names[index] = name
            if ensure(name, data: data, image: image) { out[index] = BlobRefs.prefix + name }
        }
        memo[id] = (images, names)
        return out
    }

    /// Forgets the sets no longer in the library, so the memo does not hold
    /// a deleted set's pictures in memory for the rest of the run.
    func keepOnly(_ ids: Set<UUID>) {
        lock.lock()
        defer { lock.unlock() }
        memo = memo.filter { ids.contains($0.key) }
    }

    /// The name an image had when it was last packed or filled: at the same
    /// place first, then anywhere else in that set (a picture moved), only
    /// comparing strings of its length.
    private static func known(_ image: String, at index: Int,
                              in before: (images: [String], names: [String?])) -> String? {
        if before.images.indices.contains(index), before.images[index] == image {
            if let name = before.names[index] { return name }
        }
        let length = image.utf8.count
        for (other, name) in zip(before.images, before.names) {
            guard let name, other.utf8.count == length, other == image else { continue }
            return name
        }
        return nil
    }

    /// Makes sure a blob is on disk; true once it is. Called under the lock.
    private func ensure(_ name: String, data: Data?, image: String) -> Bool {
        if verified.contains(name) { return true }
        let file = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) {
            verified.insert(name)
            return true
        }
        guard let bytes = data ?? BlobRefs.data(fromStored: image) else { return false }
        prepareFolder()
        do {
            try bytes.write(to: file, options: .atomic)
        } catch {
            return false
        }
        verified.insert(name)
        return true
    }

    /// Makes the folder, and keeps it in the phone's backup: the pictures are
    /// no longer inside the library file, so this is the only copy on the
    /// device. (The picture cache used to leave itself out of the backup.)
    func prepareFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if canImport(Darwin)
        var url = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try? url.setResourceValues(values)
        #endif
    }

    // MARK: reading

    /// One set's images as read from the file, references filled in from
    /// the folder. A reference whose blob is not here stays a reference: the
    /// card still knows which picture it wants, and sync fetches it.
    func fill(_ images: [String], of id: UUID) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var out: [String] = images
        var names = [String?](repeating: nil, count: images.count)
        var filled = false
        for (index, image) in images.enumerated() {
            guard let name = BlobRefs.hash(fromRef: image) else { continue }
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { continue }
            out[index] = data.base64EncodedString()
            names[index] = name
            verified.insert(name)
            filled = true
        }
        if filled { memo[id] = (out, names) }
        return out
    }

    /// Whether a set read from the file still carries a picture inline that
    /// can be stored as a blob: the library is then written again at once
    /// (the migration). Garbled base64 does not count, or it would force a
    /// rewrite every launch.
    static func needsPacking(_ images: [String]) -> Bool {
        images.contains { !BlobRefs.isRef($0) && BlobRefs.data(fromStored: $0) != nil }
    }

    // MARK: sweeping

    /// Whether a day has passed since the last sweep (or there has been none).
    func sweepDue(now: Date = Date(), every interval: TimeInterval = 86_400) -> Bool {
        guard let text = try? String(contentsOf: sweptFile, encoding: .utf8),
              let seconds = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return true }
        return now.timeIntervalSince(Date(timeIntervalSince1970: seconds)) >= interval
    }

    /// Drops blobs nothing refers to any more: only files named as blobs,
    /// none in `live`, none changed in the last `age` (a picture sync fetched,
    /// or one written for a set not saved yet). Notes when it ran. Returns
    /// the names removed.
    @discardableResult
    func sweep(keeping live: Set<String>, sparingNewerThan age: TimeInterval = 86_400,
               now: Date = Date()) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let files = FileManager.default
        let found = (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        let cutoff = now.addingTimeInterval(-age)
        var removed: [String] = []
        for name in found where BlobRefs.isName(name) && !live.contains(name) {
            let url = folder.appendingPathComponent(name)
            let modified = (try? files.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            guard let modified, modified < cutoff else { continue }
            if (try? files.removeItem(at: url)) != nil {
                verified.remove(name)
                removed.append(name)
            }
        }
        var isFolder: ObjCBool = false
        if files.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue {
            try? String(now.timeIntervalSince1970).write(to: sweptFile, atomically: true, encoding: .utf8)
        }
        return removed
    }

    /// Every blob the library's recovery copies in `folder` mention
    /// (library-unreadable-, library-partly-unreadable-): what they hold is
    /// still to be recovered, pictures included. Each copy is read once per
    /// size.
    func mentions(inCopiesIn folder: URL) -> Set<String> {
        let copies = RecoveryFiles.copies(in: [folder]).filter { $0.lastPathComponent.hasPrefix("library-") }
        var found = Set<String>()
        var scans: [String: (size: Int, names: Set<String>)] = [:]
        lock.lock()
        let cached = copyScans
        lock.unlock()
        for copy in copies {
            let key = copy.lastPathComponent
            let size = (try? FileManager.default.attributesOfItem(atPath: copy.path))?[.size] as? Int ?? -1
            if let scan = cached[key], scan.size == size {
                scans[key] = scan
            } else if let data = try? Data(contentsOf: copy, options: .mappedIfSafe) {
                scans[key] = (size, Self.mentions(in: data))
            }
            found.formUnion(scans[key]?.names ?? [])
        }
        lock.lock()
        copyScans = scans
        lock.unlock()
        return found
    }

    /// Every "blob:<name>" in some bytes - BlobRefs.names(mentionedIn:)
    /// without turning hundreds of megabytes into a String first.
    static func mentions(in data: Data) -> Set<String> {
        let prefix: [UInt8] = Array(BlobRefs.prefix.utf8)
        var found = Set<String>()
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            let count = bytes.count
            var at = 0
            while at + prefix.count + 64 <= count {
                guard bytes[at] == prefix[0] else { at += 1; continue }
                var matches = true
                for offset in 1..<prefix.count where bytes[at + offset] != prefix[offset] {
                    matches = false
                    break
                }
                guard matches else { at += 1; continue }
                let start = at + prefix.count
                var hex = true
                for byte in bytes[start..<(start + 64)] where !((48...57).contains(byte) || (97...102).contains(byte)) {
                    hex = false
                    break
                }
                if hex, let name = String(bytes: bytes[start..<(start + 64)], encoding: .utf8) { found.insert(name) }
                at = start
            }
        }
        return found
    }
}
